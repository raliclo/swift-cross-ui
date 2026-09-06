#!/usr/bin/env zsh
# Rebases the current branch onto its upstream, then checks that every commit
# hash recorded in testapp/issue_commits.csv still exists on the branch.
#
#   zsh testapp/rebase.zsh              # rebase onto origin/develop, then check
#   zsh testapp/rebase.zsh --check      # check only, do not rebase
#   zsh testapp/rebase.zsh --onto main  # rebase onto a different upstream
#
# Why this exists: issue_commits.csv records hashes so commits can be
# cherry-picked per issue later. A rebase rewrites them, and the recorded ones
# are then unreachable from the branch. They keep resolving locally, out of the
# reflog, so `git rev-parse` and `git show` both still work and nothing looks
# wrong -- but they are gone from the branch and will disappear on the next
# clone or gc. `git merge-base --is-ancestor` is the check that catches it.
#
# This happened on 2026-08-14: three commits were recorded, the push was
# rejected because two iOS commits had landed on the fork, and the rebase that
# followed orphaned both recorded hashes within a minute of writing them.
#
# Reports only. Rewriting the CSV is left to a human, since the repair lands in
# a file that exists to be trusted.

set -euo pipefail

script_dir="${0:a:h}"
repo_root="${script_dir:h}"
csv="$repo_root/testapp/issue_commits.csv"

# The fork's remote is not necessarily called origin -- here it is Ralic -- so
# prefer whatever the current branch tracks and fall back to a remote that
# actually exists. Hardcoding origin made the script fail with "'origin' does
# not appear to be a git repository" before it checked anything.
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
    for remote in Ralic origin; do
        if git remote get-url "$remote" >/dev/null 2>&1; then
            upstream="$remote/develop"
            break
        fi
    done
fi
: "${upstream:=origin/develop}"
do_rebase=1

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            do_rebase=0
            shift
            ;;
        --onto)
            [ $# -ge 2 ] || { echo "--onto needs a ref" >&2; exit 2; }
            upstream="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$repo_root"

[ -f "$csv" ] || { echo "Not found: $csv" >&2; exit 1; }

branch="$(git rev-parse --abbrev-ref HEAD)"

if [ "$do_rebase" -eq 1 ]; then
    # Refuse rather than stash. An interrupted rebase with stashed work on top
    # is a worse place to be than a clear stop before anything moved.
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "Working tree has uncommitted changes. Commit or stash them first." >&2
        git status --short >&2
        exit 1
    fi

    remote="${upstream%%/*}"
    ref="${upstream#*/}"
    echo "==> Fetching $ref from $remote"
    git fetch "$remote" "$ref"

    echo "==> Rebasing $branch onto $upstream"
    git rebase "$upstream"
fi

echo "==> Checking recorded hashes in testapp/issue_commits.csv against $branch"

# Column 3 is the commit hash, and it is read with csv2 because a plain split
# gets it wrong.
#
# The comment here used to say "fields before it never contain a comma, so a
# plain split is safe". Three of them do. `issue_title` is quoted and holds
# lines like
#
#     ,"No macOS synthesiser, so -actionfile could not replay on AppKitBackend",ec6a2bac,...
#
# so `awk -F,` cut inside the quotes and handed back ` so -actionfile could not
# replay on AppKitBackend"` as the hash. Measured 2026-09-07: of the 39 values
# awk produced, 3 were prose. Those three then failed to resolve as commits and
# the script reported `3 of 39 recorded hashes are no longer on develop`, which
# is a fabricated alarm about the repository from a defect in the reader. Every
# one of the 39 actually resolves and is an ancestor of develop.
#
# That is the whole reason csv2 is in this project: splitting a CSV on `,`
# mis-aligns columns silently rather than failing. mistakes.md has carried the
# rule since 2026-08-27, and this script was written against it anyway.
#
# One csv2 call per record. `-get r:c` prints one cell, so the row count comes
# first; 72 records cost about eight seconds, which is nothing next to the
# rebase this script performs.
#
# 第 3 欄是 commit hash，而它改以 csv2 讀取，因為單純切割會取錯。
#
# 此處的註解原本寫著「它之前的欄位從不含逗號，因此單純切割是安全的」。其中三個含有逗號。
# `issue_title` 是帶引號的欄位，內容形如上方那一行，於是 `awk -F,` 在引號內切開，把
# ` so -actionfile could not replay on AppKitBackend"` 當成 hash 交回。2026-09-07 實測：
# awk 產出的 39 個值中有 3 個是散文。那三個接著無法解析為 commit，於是本腳本回報
# `3 of 39 recorded hashes are no longer on develop`——一個由「讀取器的缺陷」捏造出來、
# 卻指控「儲存庫」的警報。那 39 個實際上全部可解析，且全部是 develop 的祖先。
#
# 這正是 csv2 存在於本專案的全部理由：用 `,` 切 CSV 會**靜默地**錯開欄位，而不是失敗。
# mistakes.md 自 2026-08-27 起就記著這條規則，而本腳本仍然違反了它。
#
# 每筆記錄一次 csv2 呼叫。`-get r:c` 只印一格，因此先取得列數；72 筆約需八秒，相對於本腳本
# 所執行的 rebase 微不足道。
record_count="$(csv2 -r -i "$csv" 2>/dev/null | grep -c .)"
hashes=()
for row in {1..${record_count}}; do
    cell="$(csv2 -i "$csv" -get "$row":3 2>/dev/null)"
    [ -n "$cell" ] && hashes+=("$cell")
done

total=0
orphaned=0

# Read the branch's history once. Matching is done against this rather than by
# piping `git log` into `awk` per orphan: awk exits at the first match, which
# sends SIGPIPE back to git, and `pipefail` turns that into a failed script.
branch_log="$(git log --format='%h%x09%s' HEAD)"

for h in $hashes; do
    [ -n "$h" ] || continue
    total=$((total + 1))

    if git merge-base --is-ancestor "$h" HEAD 2>/dev/null; then
        continue
    fi

    orphaned=$((orphaned + 1))

    # The object usually still exists in the reflog, which means its subject
    # can be read and matched against the rebased branch to find where it
    # ended up. If it is gone entirely there is nothing to match on.
    if ! subject="$(git log -1 --format=%s "$h" 2>/dev/null)"; then
        echo "  $h  ORPHANED -- object is gone, cannot resolve"
        continue
    fi

    replacement="$(awk -F'\t' -v s="$subject" '$2 == s { print $1; exit }' <<< "$branch_log")"

    if [ -n "$replacement" ]; then
        echo "  $h  ORPHANED -> $replacement"
        echo "      $subject"
    else
        echo "  $h  ORPHANED -- no commit on $branch has subject: $subject"
    fi
done

echo
if [ "$orphaned" -eq 0 ]; then
    echo "All $total recorded hashes are reachable from $branch."
    exit 0
fi

echo "$orphaned of $total recorded hashes are no longer on $branch."
echo "Update testapp/issue_commits.csv with the replacements above, then commit."
exit 1
