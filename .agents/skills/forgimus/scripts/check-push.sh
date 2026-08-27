#!/usr/bin/env bash
# Check the implementation worktree before anything is pushed.
#
# Usage: check-push.sh [base-ref]      (default: the publication remote's default branch)
# Run from inside the implementation worktree.
# Output: one "RESULT  check  detail" line per check, then the changed paths.
# Exit:  0 safe to push · 1 at least one FAIL · 2 prerequisite missing

set -euo pipefail

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "check-push.sh: not inside a git checkout" >&2; exit 2; }

remote=origin
git remote get-url "$remote" >/dev/null 2>&1 || { echo "check-push.sh: no remote named $remote" >&2; exit 2; }
git fetch --prune --quiet "$remote"

default=$(git symbolic-ref --quiet "refs/remotes/$remote/HEAD" 2>/dev/null | sed "s#refs/remotes/$remote/##")
base=${1:-${default:-main}}
git rev-parse --verify --quiet "$remote/$base" >/dev/null || { echo "check-push.sh: $remote/$base does not exist" >&2; exit 2; }

failed=0
report() { printf '%-5s %-22s %s\n' "$1" "$2" "$3"; [ "$1" = FAIL ] && failed=1 || true; }

branch=$(git branch --show-current)
[ -n "$branch" ] || { echo "check-push.sh: detached HEAD; check out the implementation branch" >&2; exit 2; }
if [ "$branch" != "$base" ]; then
  report PASS "branch" "$branch"
else
  report FAIL "branch" "still on $base — publish from a feature branch"
fi

dirty=$(git status --porcelain | wc -l)
if [ "$dirty" -eq 0 ]; then
  report PASS "worktree" "clean"
else
  report FAIL "worktree" "$dirty uncommitted entry/entries"
fi

commits=$(git rev-list --count "$remote/$base..HEAD")
if [ "$commits" -gt 0 ]; then
  report PASS "commits" "$commits ahead of $remote/$base"
else
  report FAIL "commits" "nothing to publish"
fi

if git diff --check "$remote/$base...HEAD" >/dev/null 2>&1; then
  report PASS "whitespace" "no trailing or mixed whitespace"
else
  report FAIL "whitespace" "$(git diff --check "$remote/$base...HEAD" | head -3)"
fi

# A branch already on the remote must fast-forward; anything else rewrites published history.
if git rev-parse --verify --quiet "$remote/$branch" >/dev/null; then
  if git merge-base --is-ancestor "$remote/$branch" HEAD; then
    ahead=$(git rev-list --count "$remote/$branch..HEAD")
    report PASS "push is fast-forward" "$ahead new commit(s) over $remote/$branch"
  else
    report FAIL "push is fast-forward" "HEAD does not contain $remote/$branch — pushing would rewrite it"
  fi
else
  report PASS "push is fast-forward" "$remote/$branch does not exist yet"
fi

echo
echo "changed paths versus $remote/$base:"
git diff --name-status "$remote/$base...HEAD" | sed 's/^/  /'
exit "$failed"
