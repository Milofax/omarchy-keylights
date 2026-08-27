#!/usr/bin/env bash
# Prove that main carries the exact reviewed tree, and name what the merge left behind.
#
# Usage: verify-merged.sh <owner/repo> <pr-number> <reviewed-head-sha>
# Run from anywhere inside the primary checkout.
# Output: one "RESULT  check  detail" line per check, then the leftovers.
# Exit:  0 every check passes · 1 at least one FAIL · 2 prerequisite missing

set -euo pipefail

repository=${1:-}
pr=${2:-}
reviewed=${3:-}
if [ -z "$repository" ] || [ -z "$pr" ] || [ -z "$reviewed" ]; then
  echo "verify-merged.sh: usage: verify-merged.sh <owner/repo> <pr-number> <reviewed-head-sha>" >&2
  exit 2
fi
command -v gh >/dev/null 2>&1 || { echo "verify-merged.sh: gh is not installed; follow the phase file's steps" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "verify-merged.sh: gh is not authenticated; follow the phase file's steps" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "verify-merged.sh: not inside a git checkout" >&2; exit 2; }

# A remote named origin is a label, not proof: use the one whose URL is the
# repository this run is about.
remote=""
while read -r name url; do
  case "$url" in
    *[:/]"$repository" | *[:/]"$repository".git) remote="$name"; break ;;
  esac
done < <(git remote -v | awk '$3 == "(fetch)" { print $1, $2 }')
[ -n "$remote" ] || { echo "verify-merged.sh: no git remote points at $repository" >&2; exit 2; }

failed=0
report() { printf '%-5s %-24s %s\n' "$1" "$2" "$3"; [ "$1" = FAIL ] && failed=1 || true; }
headline() { printf '%-5s %-24s %s\n' "$1" "$2" "$3"; }

fields=$(gh pr view "$pr" --repo "$repository" --json state,mergeCommit,headRefName,headRefOid,baseRefName \
  --jq '[.state, (.mergeCommit.oid // "none"), .headRefName, .headRefOid, .baseRefName] | @tsv') || {
  echo "verify-merged.sh: pull request #$pr not readable in $repository" >&2; exit 2; }
IFS=$'\t' read -r state merge_commit head_branch head_oid base <<<"$fields"

# The reviewed sha is an argument, so it is a claim until the pull request
# confirms it. Comparing a head against itself would otherwise always pass.
if [ "$reviewed" = "$head_oid" ]; then
  report PASS "reviewed head" "$reviewed is the pull request's head"
else
  report FAIL "reviewed head" "$reviewed is not #$pr's head $head_oid"
fi

if [ "$state" = MERGED ]; then
  report PASS "pull request" "MERGED as $merge_commit"
else
  report FAIL "pull request" "$state"
  exit "$failed"
fi

git fetch --prune --quiet "$remote" || true
main_sha=$(git rev-parse "$remote/$base")

# Squash rewrites the commit, so ancestry proves nothing about content: compare trees.
if git merge-base --is-ancestor "$merge_commit" "$remote/$base" 2>/dev/null; then
  report PASS "in $base" "$merge_commit is an ancestor of $main_sha"
else
  report FAIL "in $base" "$merge_commit is not an ancestor of $main_sha"
fi

if ! git cat-file -e "${merge_commit}^{commit}" 2>/dev/null; then
  report FAIL "reviewed tree landed" "the merge commit $merge_commit is not in this checkout"
elif git cat-file -e "${reviewed}^{commit}" 2>/dev/null; then
  if [ -z "$(git diff "$reviewed" "$merge_commit")" ]; then
    report PASS "reviewed tree landed" "$reviewed and $merge_commit carry the same tree"
  else
    # The base moves between review and merge, so tree equality is the strong
    # case, not the only sound one. What must hold is that the squash introduced
    # exactly the patch the reviewed head proposed over its own fork point;
    # whatever the base gained meanwhile is not this pull request's doing.
    fork=$(git merge-base "$reviewed" "$merge_commit^" 2>/dev/null || true)
    if [ -n "$fork" ] && [ "$(git diff "$merge_commit^" "$merge_commit")" = "$(git diff "$fork" "$reviewed")" ]; then
      gained=$(git rev-list --count "${fork}..${merge_commit}^")
      report PASS "reviewed patch landed" "unaltered; the base gained $gained commit(s) between review and merge"
    else
      report FAIL "reviewed tree landed" "$(git diff --stat "$reviewed" "$merge_commit" | tail -1)"
    fi
  fi
else
  report FAIL "reviewed tree landed" "commit $reviewed is not in this checkout"
fi

# closingIssuesReferences carries no state, so ask each issue for its own.
if ! closes=$(gh pr view "$pr" --repo "$repository" --json closingIssuesReferences \
  --jq '.closingIssuesReferences[].number' 2>/dev/null); then
  report FAIL "linked issue" "the lookup failed; the issue transition is unverified"
  closes=""
  closes_unknown=yes
fi
if [ "${closes_unknown:-no}" = yes ]; then
  :
elif [ -z "$closes" ]; then
  report INFO "linked issue" "the pull request closes no issue"
else
  while read -r number; do
    issue_state=$(gh issue view "$number" --repo "$repository" --json state --jq .state 2>/dev/null || echo "unreadable")
    if [ "$issue_state" = CLOSED ]; then
      report PASS "issue #$number" "CLOSED"
    else
      report FAIL "issue #$number" "$issue_state"
    fi
  done <<<"$closes"
fi

# Merged branches and their worktrees are harmless but easy to forget; name them.
leftover_local=$(git branch --list "$head_branch" --format='%(refname:short)')
leftover_remote=$(git ls-remote --heads "$remote" "$head_branch" 2>/dev/null | sed 's#.*refs/heads/##' || true)
leftover_tree=$(git worktree list --porcelain | awk -v b="refs/heads/$head_branch" '/^worktree /{w=$0; sub(/^worktree /,"",w)} /^branch /{if($2==b) print w}')
headline INFO "leftovers" "local:${leftover_local:-none} remote:${leftover_remote:-none} worktree:${leftover_tree:-none}"

exit "$failed"
