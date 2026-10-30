#!/usr/bin/env zsh
# 同步這棵樹：superproject 以 rebase 拉取(保持線性歷史),再更新它的 submodule,最後拉取選用的 testapp/api18。
# Sync this tree: pull the superproject with rebase (history stays linear), bring its submodules up to date,
# then pull the optional testapp/api18.
#
# 用法 / Usage:
#   zsh sync_all.zsh                         # pull; update checked-out submodules; pull api18's branch
#   zsh sync_all.zsh --init                  # also check out submodules that are not (gtk4-source is large)
#   zsh sync_all.zsh --api18                 # also check api18 out when it is not (needs the private repo)
#   zsh sync_all.zsh --api18-branch NAME     # switch api18 to NAME first (e.g. crosswalk-single, chrome88-webview)
#   zsh sync_all.zsh --no-pull               # leave the superproject itself alone
#   zsh sync_all.zsh --dry-run               # report only: no fetch, pull, checkout or update
#   zsh sync_all.zsh --help
#
# Submodule 規則 / Submodules:
# - 已取出的 submodule 更新到 superproject 記錄的 commit。工作樹有變更、或目前的 commit 已經包含記錄的 commit(本地領先)時只回報，
#   不移動。未取出的只有加 --init 才取出。
#   A checked-out submodule goes to the commit the superproject records. One with changes in its working tree, or
#   whose HEAD already contains the recorded commit (ahead locally), is reported and left. One not checked out is
#   checked out only with --init.
# - testapp/api18 是私人 repo(raliclo/api18),在 .gitmodules 裡設為 update = none:一般的 `git submodule update`
#   不會取出它。它自己維護變更紀錄，所以這裡拉取它目前的分支(或 --api18-branch 指定的),而不是退回 superproject
#   記錄的 commit;兩者不同時只回報，要記錄新的 commit 請自己 `git add testapp/api18`。它自己的 submodule
#   (例如 chrome88-webview 的 Vendor/crosswalk)依同樣規則處理。
#   testapp/api18 is a private repository (raliclo/api18) with update = none in .gitmodules: a plain
#   `git submodule update` leaves it out. It keeps its own change records, so this pulls the branch it is on (or
#   the one --api18-branch names) rather than moving it back to the commit the superproject records; when the two
#   differ that is reported, and recording the new commit is a `git add testapp/api18` of your own. Its own
#   submodules (Vendor/crosswalk on chrome88-webview) follow the same rules.
# - 髒污的工作樹只回報、不移動，與 multissh/helper/sync_all.zsh 相同。
#   Dirty working trees are reported, never moved, as in multissh/helper/sync_all.zsh.

emulate -L zsh
set -uo pipefail

# $0 here, not inside usage(): in a function zsh gives the function's name. / 在這裡取 $0,不是在 usage()
# 裡面：函式裡 zsh 給的是函式名稱。
script_path="${0:A}"
root="${script_path:h}"
api18=testapp/api18

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$script_path"
}

do_pull=1
dry_run=0
want_init=0
want_api18=0
api18_branch=""
while (( $# )); do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --no-pull) do_pull=0 ;;
    --dry-run) dry_run=1 ;;
    --init) want_init=1 ;;
    --api18) want_api18=1 ;;
    --api18-branch)
      (( $# >= 2 )) || { printf '--api18-branch 需要分支名稱 / needs a branch name\n' >&2; exit 2 }
      api18_branch=$2; want_api18=1; shift ;;
    *) printf '未知選項 / unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

failures=0

# rc 直接取自 git,不經管線。/ The status comes from git itself, never through a pipe.
run() {
  local out=$(mktemp)
  "$@" > "$out" 2>&1
  local rc=$?
  if (( rc != 0 )); then
    printf '  FAIL (rc=%d): %s\n' "$rc" "$*"
    sed 's/^/       /' "$out" >&2
    (( failures += 1 ))
  else
    tail -1 "$out" | sed 's/^/  /'
  fi
  rm -f "$out"
  return $rc
}

dirty() {
  git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '
}

# The submodules of the repository at $1, each "path update" (update is "none" or empty), read with git config
# rather than by splitting .gitmodules. / $1 這個 repo 的 submodule,每行「路徑 update」(update 為 none 或空),
# 以 git config 讀取，不自己切 .gitmodules。
submodules() {
  local repo=$1 key name
  [[ -f $repo/.gitmodules ]] || return 0
  git -C "$repo" config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' | while read -r key; do
    name=${key%.path}
    printf '%s\t%s\n' "$(git -C "$repo" config -f .gitmodules --get "$key")" \
      "$(git -C "$repo" config -f .gitmodules --get "$name.update" 2>/dev/null)"
  done
}

# One submodule of the repository $1 at path $2, by the rules above. / $1 這個 repo 在路徑 $2 的 submodule,依上面的規則。
sync_submodule() {
  local repo=$1 sub=$2 recorded current n
  recorded=$(git -C "$repo" ls-tree HEAD "$sub" 2>/dev/null | awk '{print $3}')
  if [[ -z $recorded ]]; then
    printf '  %s: 未記錄 / not recorded on this branch\n' "$sub"
    return
  fi
  if [[ ! -e $repo/$sub/.git ]]; then
    # 未取出的 submodule 是空目錄；不能對它跑 git -C,那會回報外層 repo 的 HEAD。
    # An un-checked-out submodule is an empty directory; git -C there would report the outer repository's HEAD.
    if (( ! want_init )); then
      printf '  %s: 未取出 / not checked out (--init)\n' "$sub"
    elif (( dry_run )); then
      printf '  %s: dry-run: 會取出 / would check out %s\n' "$sub" "${recorded[1,7]}"
    else
      printf '  %s:\n' "$sub"
      run git -C "$repo" submodule update --init --checkout "$sub"
    fi
    return
  fi
  current=$(git -C "$repo/$sub" rev-parse HEAD 2>/dev/null)
  n=$(dirty "$repo/$sub")
  if [[ $current == $recorded ]]; then
    printf '  %s: 與記錄一致 / matches the record (%s)%s\n' "$sub" "${current[1,7]}" "${${n:#0}:+, $n change(s) in the working tree}"
  elif (( n > 0 )); then
    printf '  %s: STOP 工作樹有 %s 項變更；未移動 / %s change(s); not moved\n' "$sub" "$n" "$n"
    (( failures += 1 ))
  elif git -C "$repo/$sub" merge-base --is-ancestor "$recorded" HEAD 2>/dev/null; then
    printf '  %s: 本地領先記錄 / ahead of the record (%s, records %s); left\n' "$sub" "${current[1,7]}" "${recorded[1,7]}"
  elif (( dry_run )); then
    printf '  %s: dry-run: 會移到 / would move to %s (now %s)\n' "$sub" "${recorded[1,7]}" "${current[1,7]}"
  else
    printf '  %s: %s -> %s\n' "$sub" "${current[1,7]}" "${recorded[1,7]}"
    run git -C "$repo" submodule update --checkout "$sub"
  fi
}

printf 'sync_all: %s\n\n' "$root"

if (( do_pull )); then
  printf 'superproject:\n'
  if (( dry_run )); then
    printf '  dry-run: 不 pull / no pull; distance to cached upstream (behind ahead): %s\n' \
      "$(git -C "$root" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"
  else
    run git -C "$root" pull --rebase --autostash
  fi
  printf '\n'
fi

printf 'submodules:\n'
submodules "$root" | while IFS=$'\t' read -r sub update; do
  [[ $sub == $api18 ]] && continue
  if [[ $update == none ]]; then
    printf '  %s: update = none,略過 / skipped\n' "$sub"
    continue
  fi
  sync_submodule "$root" "$sub"
done
printf '\n'

printf '%s (optional / 選用):\n' "$api18"
recorded=$(git -C "$root" ls-tree HEAD "$api18" 2>/dev/null | awk '{print $3}')
if [[ -z $recorded ]]; then
  printf '  superproject 未記錄此路徑 / not recorded by the superproject\n'
elif [[ ! -e $root/$api18/.git ]]; then
  if (( ! want_api18 )); then
    printf '  未取出 / not checked out (zsh sync_all.zsh --api18 取出 / checks it out)\n'
  elif (( dry_run )); then
    printf '  dry-run: 會取出 / would check out %s, then %s\n' "${recorded[1,7]}" "${api18_branch:-develop}"
  else
    # --checkout 越過 update = none。/ --checkout overrides update = none.
    run git -C "$root" submodule update --init --checkout "$api18" && \
      run git -C "$root/$api18" checkout "${api18_branch:-develop}"
  fi
fi
if [[ -n $recorded && -e $root/$api18/.git ]]; then
  repo=$root/$api18
  n=$(dirty "$repo")
  branch=$(git -C "$repo" symbolic-ref --short -q HEAD)
  if [[ -n $api18_branch && $api18_branch != $branch ]]; then
    if (( n > 0 )); then
      printf '  STOP 工作樹有 %s 項變更；不切換到 %s / dirty with %s change(s); not switched to %s\n' "$n" "$api18_branch" "$n" "$api18_branch"
      (( failures += 1 ))
    elif (( dry_run )); then
      printf '  dry-run: 會切換 / would switch %s -> %s\n' "${branch:-detached}" "$api18_branch"
    else
      # A branch only on origin is created to track it. / 只在 origin 上的分支會建立並追蹤它。
      run git -C "$repo" fetch origin && run git -C "$repo" checkout "$api18_branch"
      branch=$(git -C "$repo" symbolic-ref --short -q HEAD)
    fi
  fi
  if [[ -z $branch ]]; then
    printf '  STOP 不在任何分支上；未拉取 / detached HEAD; not pulled (--api18-branch NAME)\n'
    (( failures += 1 ))
  elif (( n > 0 )); then
    printf '  STOP 工作樹有 %s 項變更；未拉取 / dirty with %s change(s); not pulled\n' "$n" "$n"
    (( failures += 1 ))
  elif ! git -C "$repo" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    printf '  %s 沒有 upstream(只在本機);未拉取 / %s has no upstream (local only); not pulled\n' "$branch" "$branch"
  elif (( dry_run )); then
    printf '  dry-run: %s 不 pull / no pull; distance to cached upstream (behind ahead): %s\n' "$branch" \
      "$(git -C "$repo" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"
  else
    printf '  %s:\n' "$branch"
    run git -C "$repo" pull --rebase
  fi
  submodules "$repo" | while IFS=$'\t' read -r sub update; do
    [[ $update == none ]] && { printf '  %s: update = none,略過 / skipped\n' "$sub"; continue }
    sync_submodule "$repo" "$sub"
  done
  current=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
  if [[ -n $current && $current != $recorded ]]; then
    printf '  superproject 記錄 / records %s, checked out %s;要記錄新的請 / to record it: git add %s\n' \
      "${recorded[1,7]}" "${current[1,7]}" "$api18"
  elif [[ -n $current ]]; then
    printf '  與記錄一致 / matches the record (%s)\n' "${current[1,7]}"
  fi
fi

(( failures > 0 )) && printf '\n失敗或擋下 %d / failed or stopped %d\n' $failures $failures
exit $(( failures != 0 ))
