#!/usr/bin/env zsh
# 同步這棵樹：superproject 以 rebase 拉取(保持線性歷史),再同步選用的 submodule testapp/api18。
# Sync this tree: pull the superproject with rebase (history stays linear), then the optional
# submodule testapp/api18.
#
# 用法 / Usage:
#   zsh sync_all.zsh               # pull, then pull api18 if it is checked out
#   zsh sync_all.zsh --api18       # also check api18 out when it is not (needs access to the private repo)
#   zsh sync_all.zsh --no-pull     # leave the superproject alone
#   zsh sync_all.zsh --dry-run     # report only: no fetch, pull or checkout
#   zsh sync_all.zsh --help
#
# testapp/api18 是私人 repo(raliclo/api18),在 .gitmodules 裡設為 update = none:一般的
# `git submodule update` 不會取出它，沒有權限的人也不會因此失敗。它自己維護變更紀錄，所以這裡是拉取它的
# develop,而不是把它退回 superproject 記錄的 commit;兩者不同時只回報，要記錄新的 commit 請自己
# `git add testapp/api18`。
# testapp/api18 is a private repository (raliclo/api18) with update = none in .gitmodules: a plain
# `git submodule update` leaves it out, and nobody without access fails because of it. It keeps its
# own change records, so this pulls its develop rather than moving it back to the commit the
# superproject records; when the two differ that is reported, and recording the new commit is a
# `git add testapp/api18` of your own.
#
# 髒污的工作樹只回報、不移動，與 multissh/helper/sync_all.zsh 相同。其他 submodule 不在這裡處理。
# Dirty working trees are reported, never moved, as in multissh/helper/sync_all.zsh. The other
# submodules are not handled here.

emulate -L zsh
set -uo pipefail

root="${0:A:h}"
api18=testapp/api18

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${0:A}"
}

do_pull=1
dry_run=0
want_api18=0
for arg in "$@"; do
  case $arg in
    -h|--help) usage; exit 0 ;;
    --no-pull) do_pull=0 ;;
    --dry-run) dry_run=1 ;;
    --api18) want_api18=1 ;;
    *) printf '未知選項 / unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
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

printf 'sync_all: %s\n\n' "$root"

if (( do_pull )); then
  printf 'superproject:\n'
  if (( dry_run )); then
    printf '  dry-run: 不 pull / no pull; distance to cached origin/develop (behind ahead): %s\n' \
      "$(git -C "$root" rev-list --left-right --count origin/develop...HEAD 2>/dev/null)"
  else
    run git -C "$root" pull --rebase --autostash
  fi
  printf '\n'
fi

printf '%s (optional / 選用):\n' "$api18"
recorded=$(git -C "$root" ls-tree HEAD "$api18" 2>/dev/null | awk '{print $3}')
if [[ -z $recorded ]]; then
  printf '  superproject 未記錄此路徑 / not recorded by the superproject\n'
elif [[ ! -e $root/$api18/.git ]]; then
  # 未取出的 submodule 是空目錄；不能對它跑 git -C,那會回報 superproject 自己的 HEAD。
  # An un-checked-out submodule is an empty directory; git -C there would report the
  # superproject's own HEAD.
  if (( ! want_api18 )); then
    printf '  未取出 / not checked out (zsh sync_all.zsh --api18 取出 / checks it out)\n'
  elif (( dry_run )); then
    printf '  dry-run: 會取出 / would check out %s\n' "${recorded[1,7]}"
  else
    # --checkout 越過 update = none。/ --checkout overrides update = none.
    run git -C "$root" submodule update --init --checkout "$api18" && \
      run git -C "$root/$api18" checkout develop && \
      run git -C "$root/$api18" pull --rebase
  fi
else
  n=$(dirty "$root/$api18")
  branch=$(git -C "$root/$api18" symbolic-ref --short -q HEAD)
  if (( n > 0 )); then
    printf '  STOP 工作樹有 %s 項變更；未拉取 / dirty with %s change(s); not pulled\n' "$n" "$n"
    (( failures += 1 ))
  elif [[ $branch != develop ]]; then
    printf '  STOP 不在 develop(%s);未拉取 / not on develop (%s); not pulled\n' "${branch:-detached}" "${branch:-detached}"
    (( failures += 1 ))
  elif (( dry_run )); then
    printf '  dry-run: 不 pull / no pull; distance to cached origin/develop (behind ahead): %s\n' \
      "$(git -C "$root/$api18" rev-list --left-right --count origin/develop...HEAD 2>/dev/null)"
  else
    run git -C "$root/$api18" pull --rebase
  fi
  current=$(git -C "$root/$api18" rev-parse HEAD 2>/dev/null)
  if [[ -n $current && $current != $recorded ]]; then
    printf '  superproject 記錄 / records %s, checked out %s;要記錄新的請 / to record it: git add %s\n' \
      "${recorded[1,7]}" "${current[1,7]}" "$api18"
  elif [[ -n $current ]]; then
    printf '  與記錄一致 / matches the record (%s)\n' "${current[1,7]}"
  fi
fi

(( failures > 0 )) && printf '\n失敗或擋下 %d / failed or stopped %d\n' $failures $failures
exit $(( failures != 0 ))
