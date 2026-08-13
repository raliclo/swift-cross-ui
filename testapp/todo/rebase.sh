#!/usr/bin/env zsh
# Rebases the current branch onto its upstream, then checks that every commit
# hash recorded in testapp/issue_commits.csv still exists on the branch.
#
#   zsh testapp/todo/rebase.sh              # rebase onto origin/develop, then check
#   zsh testapp/todo/rebase.sh --check      # check only, do not rebase
#   zsh testapp/todo/rebase.sh --onto main  # rebase onto a different upstream
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
repo_root="${script_dir:h:h}"
csv="$repo_root/testapp/issue_commits.csv"

upstream="origin/develop"
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

# Column 3 is the commit hash. Fields before it never contain a comma, so a
# plain split is safe here; the subject in column 4 is sometimes quoted and
# does contain commas, which is why it is read from git below rather than
# from the file.
hashes=("${(@f)$(awk -F, 'NR > 1 && $3 != "" { print $3 }' "$csv")}")

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
