#!/usr/bin/env bash
# Survey every branch left behind in this checkout and reclaim the safe ones.
#
# Usage: survey-branches.sh <owner/repo> [--apply] [--force]
# Run from anywhere inside the primary checkout.
# Without --apply nothing is removed: the table is printed and the run ends.
# --force is passed through to reclaim.sh, which then also accepts a dirty worktree.
# Output: one row per leftover branch, then the plan or the actions.
# Exit:  0 surveyed, or swept with every attempt succeeding
#        1 an attempted reclaim failed · 2 prerequisite missing
#
# Safety is not decided here. Every verdict comes from reclaim.sh running its
# own checks against that one pull request, so "safe" means exactly one thing in
# this skill and the table can never drift away from what the removal enforces.

set -euo pipefail

repository=${1:-}
shift 1 2>/dev/null || true
apply=no
force=no
for argument in "$@"; do
  case "$argument" in
    --apply) apply=yes ;;
    --force) force=yes ;;
    *) echo "survey-branches.sh: unknown argument $argument" >&2; exit 2 ;;
  esac
done
if [ -z "$repository" ]; then
  echo "survey-branches.sh: usage: survey-branches.sh <owner/repo> [--apply] [--force]" >&2
  exit 2
fi
command -v gh >/dev/null 2>&1 || { echo "survey-branches.sh: gh is not installed; follow the phase file's steps" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "survey-branches.sh: not inside a git checkout" >&2; exit 2; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
reclaim="$script_dir/reclaim.sh"
review_evidence="$script_dir/review-evidence.sh"
[ -x "$reclaim" ] || { echo "survey-branches.sh: $reclaim is not executable" >&2; exit 2; }
[ -x "$review_evidence" ] || { echo "survey-branches.sh: $review_evidence is not executable" >&2; exit 2; }

default_branch=$(gh repo view "$repository" --json defaultBranchRef --jq .defaultBranchRef.name) || {
  echo "survey-branches.sh: cannot read $repository" >&2; exit 2; }

# One fetch for the whole sweep; reclaim.sh repeats it per pull request, which is
# then a no-op against an already current remote.
git fetch --prune --quiet origin || true

# Where each branch still exists decides what a reclaim would have to remove.
declare -A where=()
declare -A open_pr_record=()
note_place() { where["$1"]="${where["$1"]:-}$2 "; }

while read -r name; do
  [ -n "$name" ] && [ "$name" != "$default_branch" ] && note_place "$name" local
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

while read -r name; do
  [ -n "$name" ] && [ "$name" != HEAD ] && [ "$name" != "$default_branch" ] && note_place "$name" remote
done < <(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/)

while read -r name; do
  [ -n "$name" ] && [ "$name" != "$default_branch" ] && note_place "$name" worktree
done < <(git worktree list --porcelain | sed -n 's#^branch refs/heads/##p')

# Open pull requests are work in flight even when their head is not fetched or
# belongs to a fork. Keep owner-qualified fork heads distinct from local names.
repository_owner=${repository%%/*}
if ! open_prs=$(gh pr list --repo "$repository" --state open --limit 1000 \
  --json number,headRefName,headRepositoryOwner \
  --jq '.[] | [.number, .headRefName, .headRepositoryOwner.login] | @tsv'); then
  echo "survey-branches.sh: cannot read open pull requests in $repository" >&2
  exit 2
fi
while IFS=$'\t' read -r number head owner; do
  [ -n "$number" ] || continue
  branch=$head
  [ "$owner" = "$repository_owner" ] || branch="$owner:$head"
  # GitHub can expose more than one open PR for the same owner-qualified head
  # (for example against different bases). Preserve every PR as its own row.
  if [ -n "${open_pr_record[$branch]:-}" ]; then
    branch="$branch#pr-$number"
  fi
  open_pr_record["$branch"]="$number"$'\t'OPEN$'\t'none
  note_place "$branch" pull-request
done <<<"$open_prs"

if [ ${#where[@]} -eq 0 ]; then
  echo "nothing in flight or left behind: no non-default branch, worktree, or open pull request"
  exit 0
fi

# Collected before printing, so the table and the sweep judge the same rows.
safe=()
declare -A verdict=() detail=() pr_of=() review=() next=()

for branch in $(printf '%s\n' "${!where[@]}" | sort); do
  record=${open_pr_record["$branch"]:-}
  if [ -z "$record" ]; then
    record=$(gh pr list --repo "$repository" --head "$branch" --state all \
      --json number,state,mergedAt --jq '.[0] | select(.) | [.number, .state, (.mergedAt // "none")] | @tsv' 2>/dev/null || echo "")
  fi
  if [ -z "$record" ]; then
    verdict["$branch"]=kept
    detail["$branch"]="no pull request — unpublished work stays"
    pr_of["$branch"]="-"
    review["$branch"]="-"
    next["$branch"]="publish"
    continue
  fi
  IFS=$'\t' read -r number state merged_at <<<"$record"
  pr_of["$branch"]="#$number"
  case "$state" in
    MERGED)
      arguments=("$repository" "$number")
      [ "$force" = yes ] && arguments+=(--force)
      if output=$("$reclaim" "${arguments[@]}" 2>&1); then
        verdict["$branch"]=safe
        detail["$branch"]="merged $(printf '%.10s' "$merged_at")"
        review["$branch"]="-"
        next["$branch"]="cleanup"
        safe+=("$number")
      else
        # reclaim.sh pads the check name into a column; turn that padding back
        # into a separator so the row reads "check — why".
        reason=$(printf '%s\n' "$output" | sed -n 's/^REFUSE  *//p' | head -1 | sed 's/   */ — /')
        verdict["$branch"]=blocked
        detail["$branch"]="${reason:-reclaim.sh refused}"
        review["$branch"]="-"
        next["$branch"]="resolve"
      fi
      ;;
    OPEN)
      verdict["$branch"]=kept
      detail["$branch"]="pull request #$number is still open"
      if evidence=$("$review_evidence" "$repository" "$number" 2>&1); then
        review["$branch"]="current"
      elif printf '%s\n' "$evidence" | grep -q 'stale head'; then
        review["$branch"]="stale"
      elif printf '%s\n' "$evidence" | grep -q 'missing for'; then
        review["$branch"]="missing"
      else
        review["$branch"]="blocked"
      fi
      next["$branch"]="merge"
      ;;
    *)
      verdict["$branch"]=kept
      detail["$branch"]="pull request #$number closed without merging"
      review["$branch"]="-"
      next["$branch"]="inspect"
      ;;
  esac
done

width=0
for branch in "${!where[@]}"; do
  [ ${#branch} -gt "$width" ] && width=${#branch}
done
[ "$width" -gt 46 ] && width=46

printf "%-${width}s  %-6s %-9s %-24s %-9s %-8s %s\n" BRANCH PR VERDICT WHERE REVIEW NEXT DETAIL
for branch in $(printf '%s\n' "${!where[@]}" | sort); do
  printf "%-${width}s  %-6s %-9s %-24s %-9s %-8s %s\n" \
    "$branch" "${pr_of["$branch"]:--}" "${verdict["$branch"]}" \
    "$(echo "${where["$branch"]}" | tr ' ' '+' | sed 's/+$//')" \
    "${review["$branch"]}" "${next["$branch"]}" "${detail["$branch"]}"
done
echo

if [ ${#safe[@]} -eq 0 ]; then
  echo "nothing is safe to reclaim; the rows above say why"
  exit 0
fi

if [ "$apply" != yes ]; then
  echo "safe to reclaim (pass --apply to carry it out): ${#safe[@]} pull request(s)"
  for number in "${safe[@]}"; do
    echo "  $(basename "$reclaim") $repository $number --apply$([ "$force" = yes ] && echo ' --force')"
  done
  exit 0
fi

# Each one runs its own checks again. State moved since the survey — a branch
# checked out meanwhile, a pull request opened — is caught there, not assumed away.
failed=0
for number in "${safe[@]}"; do
  echo "--- #$number ---"
  arguments=("$repository" "$number" --apply)
  [ "$force" = yes ] && arguments+=(--force)
  "$reclaim" "${arguments[@]}" || { echo "reclaim of #$number failed" >&2; failed=1; }
done
exit "$failed"
