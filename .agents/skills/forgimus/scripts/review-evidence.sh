#!/usr/bin/env bash
# Read or record the Standards/Spec review evidence for one pull request head.
#
# Usage: review-evidence.sh <owner/repo> <pr-number>
#        review-evidence.sh <owner/repo> <pr-number> --record <reviewed-head-sha>
# Output: one "RESULT  review  detail" line.
# Exit:   0 current clean evidence · 1 missing, stale, or blocking evidence
#         2 prerequisite missing or invalid invocation

set -euo pipefail

repository=${1:-}
pr=${2:-}
mode=${3:-read}
reviewed=${4:-}
marker='<!-- forgimus-review:v1 -->'
github_cli=${FORGIMUS_GH:-gh}

if [ -z "$repository" ] || [ -z "$pr" ]; then
  echo "review-evidence.sh: usage: review-evidence.sh <owner/repo> <pr-number> [--record <reviewed-head-sha>]" >&2
  exit 2
fi
if [ "$mode" != read ] && [ "$mode" != --record ]; then
  echo "review-evidence.sh: unknown argument $mode" >&2
  exit 2
fi
if [ "$mode" = --record ] && ! printf '%s' "$reviewed" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "review-evidence.sh: --record requires the exact 40-character reviewed head SHA" >&2
  exit 2
fi
command -v "$github_cli" >/dev/null 2>&1 || { echo "review-evidence.sh: gh is not installed; follow the phase file's steps" >&2; exit 2; }
"$github_cli" auth status >/dev/null 2>&1 || { echo "review-evidence.sh: gh is not authenticated; follow the phase file's steps" >&2; exit 2; }

head=$("$github_cli" pr view "$pr" --repo "$repository" --json state,headRefOid \
  --jq 'select(.state == "OPEN") | .headRefOid' 2>/dev/null) || {
  echo "review-evidence.sh: pull request #$pr not readable in $repository" >&2
  exit 2
}
if [ -z "$head" ]; then
  printf '%-5s %-22s %s\n' FAIL review "pull request #$pr is not open"
  exit 1
fi

if [ "$mode" = --record ]; then
  if [ "$reviewed" != "$head" ]; then
    printf '%-5s %-22s %s\n' FAIL review "reviewed head $reviewed is stale; current head is $head"
    exit 1
  fi

  body=$(printf '%s\nreviewed-head: %s\nstandards: PASS\nspec: PASS\nblocking-findings: 0' "$marker" "$reviewed")
  actor=$("$github_cli" api user --jq .login 2>/dev/null) || {
    echo "review-evidence.sh: cannot resolve the authenticated GitHub user" >&2
    exit 2
  }
  comment_id=$("$github_cli" api --paginate "repos/$repository/issues/$pr/comments" \
    --jq ".[] | select(.user.login == \"$actor\" and (.body | contains(\"$marker\"))) | .id" 2>/dev/null | tail -1)
  if [ -n "$comment_id" ]; then
    "$github_cli" api --method PATCH "repos/$repository/issues/comments/$comment_id" -f body="$body" --silent >/dev/null
  else
    "$github_cli" api --method POST "repos/$repository/issues/$pr/comments" -f body="$body" --silent >/dev/null
  fi
  printf '%-5s %-22s %s\n' PASS review "current head $head; Standards PASS; Spec PASS; blocking findings 0"
  exit 0
fi

if ! records=$("$github_cli" api --paginate "repos/$repository/issues/$pr/comments" --jq '
  def field($name):
    split("\n")
    | map(select(startswith($name + ": ")))
    | last // ""
    | ltrimstr($name + ": ");
  .[]
  | select(
      (.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR")
      and (.body | contains("<!-- forgimus-review:v1 -->"))
    )
  | [
      .id,
      (.body | field("reviewed-head")),
      (.body | field("standards")),
      (.body | field("spec")),
      (.body | field("blocking-findings"))
    ]
  | @tsv
' 2>/dev/null); then
  echo "review-evidence.sh: cannot read review evidence for pull request #$pr in $repository" >&2
  exit 2
fi

if [ -z "$records" ]; then
  printf '%-5s %-22s %s\n' INFO review "missing for current head $head"
  exit 1
fi

record=$(printf '%s\n' "$records" | awk -F '\t' -v head="$head" '$2 == head { current = $0 } END { print current }')
if [ -z "$record" ]; then
  reviewed=$(printf '%s\n' "$records" | tail -1 | cut -f2)
  printf '%-5s %-22s %s\n' INFO review "stale head ${reviewed:-unknown}; current head $head"
  exit 1
fi

IFS=$'\t' read -r _ reviewed standards spec blocking <<<"$record"
if [ "$standards" != PASS ] || [ "$spec" != PASS ] || [ "$blocking" != 0 ]; then
  printf '%-5s %-22s %s\n' FAIL review "current head $head; Standards ${standards:-unknown}; Spec ${spec:-unknown}; blocking findings ${blocking:-unknown}"
  exit 1
fi

printf '%-5s %-22s %s\n' PASS review "current head $head; Standards PASS; Spec PASS; blocking findings 0"
