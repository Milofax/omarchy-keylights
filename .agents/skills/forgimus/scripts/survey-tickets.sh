#!/usr/bin/env bash
# Survey the tracker for ticket selection.
#
# Usage: survey-tickets.sh <owner/repo>
# Output: one TSV row per open issue, header first:
#   number  blocked_by  sub_issues  branch  pr  labels  title
#   blocked_by / sub_issues are counts. branch and pr are yes/no.
# Exit:  0 survey printed · 2 prerequisite missing (follow the phase file's steps instead)

set -euo pipefail

repository=${1:-}
if [ -z "$repository" ]; then
  echo "survey-tickets.sh: pass the tracker repository as owner/repo" >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "survey-tickets.sh: gh is not installed; follow the phase file's steps" >&2
  exit 2
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "survey-tickets.sh: gh is not authenticated; run 'gh auth login' or follow the phase file's steps" >&2
  exit 2
fi

# Remote refs decide whether work already exists; a stale local view would hide it.
branches=$(git ls-remote --heads origin 2>/dev/null | sed 's#.*refs/heads/##' || true)
open_prs=$(gh pr list --repo "$repository" --state open --json headRefName --jq '.[].headRefName' 2>/dev/null || true)

printf 'number\tblocked_by\tsub_issues\tbranch\tpr\tlabels\ttitle\n'

# GitHub caps a page at 100; --paginate walks every page so no ticket is missed.
gh api --paginate "repos/$repository/issues?state=open&per_page=100" \
  --jq '.[] | select(has("pull_request") | not)
        | [.number,
           (.issue_dependencies_summary.total_blocked_by // 0),
           (.sub_issues_summary.total // 0),
           ([.labels[].name] | join(",") // ""),
           .title] | @tsv' \
| while IFS=$'\t' read -r number blocked subs labels title; do
    if printf '%s\n' "$branches" | grep -q "issue/${number}-"; then has_branch=yes; else has_branch=no; fi
    if printf '%s\n' "$open_prs" | grep -q "issue/${number}-"; then has_pr=yes; else has_pr=no; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$number" "$blocked" "$subs" "$has_branch" "$has_pr" "${labels:--}" "$title"
  done
