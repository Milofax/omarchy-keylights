#!/usr/bin/env bash
# Evaluate the mechanical merge gates for one pull request.
#
# Usage: check-merge.sh <owner/repo> <pr-number>
# Output: one "RESULT  gate  detail" line per gate.
#   PASS the gate holds · FAIL it does not · INFO a fact the gate table judges
# Exit:  0 every mechanical gate passes · 1 at least one FAIL · 2 prerequisite missing
#
# The judged gates stay with the skill: review severities, acceptance criteria,
# and the docs-only exemption for a missing CI run.

set -euo pipefail

repository=${1:-}
pr=${2:-}
if [ -z "$repository" ] || [ -z "$pr" ]; then
  echo "check-merge.sh: usage: check-merge.sh <owner/repo> <pr-number>" >&2
  exit 2
fi
command -v gh >/dev/null 2>&1 || { echo "check-merge.sh: gh is not installed; follow the phase file's steps" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "check-merge.sh: gh is not authenticated; follow the phase file's steps" >&2; exit 2; }

failed=0
report() { printf '%-5s %-22s %s\n' "$1" "$2" "$3"; [ "$1" = FAIL ] && failed=1 || true; }

fields=$(gh pr view "$pr" --repo "$repository" \
  --json state,isDraft,mergeable,mergeStateStatus,baseRefName,headRefOid,reviewDecision \
  --jq '[.state, .isDraft, .mergeable, .mergeStateStatus, .baseRefName, .headRefOid, (.reviewDecision | if . == null or . == "" then "none" else . end)] | @tsv' 2>/dev/null) || {
  echo "check-merge.sh: pull request #$pr not readable in $repository" >&2; exit 2; }
IFS=$'\t' read -r state draft mergeable merge_state base head_oid decision <<<"$fields"

if [ "$state" = OPEN ]; then report PASS "state" "OPEN"; else report FAIL "state" "$state"; fi
if [ "$draft" = false ]; then
  report PASS "not a draft" "ready for review"
else
  report INFO "draft" "lift the draft only once every other gate passes"
fi
if [ "$mergeable" = MERGEABLE ]; then
  report PASS "mergeable" "$mergeable/$merge_state"
else
  report FAIL "mergeable" "$mergeable/$merge_state"
fi

# A base that is not the default branch is a stack, which the skill resolves in phases/merge.md.
default=$(gh api "repos/$repository" --jq .default_branch)
if [ "$base" = "$default" ]; then
  report PASS "base" "$base"
else
  report INFO "base" "$base (stacked; resolve the dependency order first)"
fi

checks=$(gh pr checks "$pr" --repo "$repository" 2>&1 || true)
if printf '%s' "$checks" | grep -q "no checks reported"; then
  report FAIL "remote CI" "no checks reported — MERGE BLOCKED unless the docs-only exemption applies"
else
  total=$(printf '%s\n' "$checks" | grep -c . || true)
  bad=$(printf '%s\n' "$checks" | grep -cE $'\tfail|\tpending' || true)
  if [ "$bad" -eq 0 ]; then
    report PASS "remote CI" "$total check(s), all passing"
  else
    report FAIL "remote CI" "$bad of $total check(s) failing or pending"
  fi
fi

threads=$(gh api "repos/$repository/pulls/$pr/comments" --jq 'length' 2>/dev/null || echo 0)
if [ "$threads" -eq 0 ]; then
  report PASS "review threads" "none open"
else
  report INFO "review threads" "$threads comment(s) — confirm each is resolved"
fi
report INFO "review decision" "$decision"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
review_evidence="$script_dir/review-evidence.sh"
if [ -x "$review_evidence" ]; then
  if evidence=$("$review_evidence" "$repository" "$pr" 2>&1); then
    printf '%s\n' "$evidence"
  else
    case "$evidence" in
      INFO\ *) printf '%s\n' "$evidence" ;;
      FAIL\ *) printf '%s\n' "$evidence"; failed=1 ;;
      *) report FAIL "review evidence" "${evidence:-lookup failed without detail}" ;;
    esac
  fi
else
  report FAIL "review evidence" "$review_evidence is unavailable"
fi

# Freshness: the reviewed head must sit on the base as it stands right now.
base_sha=$(gh api "repos/$repository/commits/$base" --jq .sha)
behind=$(gh api "repos/$repository/compare/$base_sha...$head_oid" --jq .behind_by 2>/dev/null || echo "?")
if [ "$behind" = "0" ]; then
  report PASS "base freshness" "head contains $base@$base_sha"
else
  report INFO "base freshness" "head is $behind commit(s) behind $base"
fi

report INFO "head" "$head_oid"
exit "$failed"
