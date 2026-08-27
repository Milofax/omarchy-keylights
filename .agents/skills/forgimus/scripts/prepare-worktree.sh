#!/usr/bin/env bash
# Create the isolated worktree for one ticket, on a proven-fresh base.
#
# Usage: prepare-worktree.sh <owner/repo> <issue-number>
# Run from anywhere inside the primary checkout.
# Output: the verification block the skill's brief needs, as key: value lines.
# Exit:  0 worktree ready · 1 the worktree is not clean · 2 prerequisite missing
#        3 remote mismatch · 4 existing work found · 5 ticket not implementable as given

set -euo pipefail

repository=${1:-}
number=${2:-}
if [ -z "$repository" ] || [ -z "$number" ]; then
  echo "prepare-worktree.sh: usage: prepare-worktree.sh <owner/repo> <issue-number>" >&2
  exit 2
fi
for tool in gh git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "prepare-worktree.sh: $tool is not installed; follow the phase file's steps" >&2; exit 2; }
done
gh auth status >/dev/null 2>&1 || { echo "prepare-worktree.sh: gh is not authenticated; follow the phase file's steps" >&2; exit 2; }

checkout=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "prepare-worktree.sh: not inside a git checkout" >&2; exit 2; }

remote=""
while read -r name url; do
  case "$url" in
    *[:/]"$repository" | *[:/]"$repository".git) remote="$name"; break ;;
  esac
done < <(git remote -v | awk '$3 == "(fetch)" { print $1, $2 }')
[ -n "$remote" ] || { echo "prepare-worktree.sh: no git remote points at $repository" >&2; exit 2; }

# The repository has to answer before a ticket inside it can be judged
# unimplementable, or an unreachable repository reads as a bad ticket.
default=$(gh api "repos/$repository" --jq .default_branch) || {
  echo "prepare-worktree.sh: $repository is not readable" >&2; exit 2; }
git fetch --prune --quiet "$remote" || { echo "prepare-worktree.sh: cannot fetch $remote" >&2; exit 2; }

if ! ticket=$(gh issue view "$number" --repo "$repository" --json state,title --jq '[.state, .title] | @tsv' 2>/tmp/prepare-worktree.$$); then
  echo "prepare-worktree.sh: issue #$number not readable in $repository:" >&2
  sed 's/^/  /' /tmp/prepare-worktree.$$ >&2 || true
  rm -f /tmp/prepare-worktree.$$
  exit 5
fi
rm -f /tmp/prepare-worktree.$$
IFS=$'\t' read -r state title <<<"$ticket"
[ "$state" = "OPEN" ] || { echo "prepare-worktree.sh: issue #$number is $state; nothing to prepare" >&2; exit 5; }

# Slug: German umlauts spelled out, everything else folded to hyphens, cut on a
# word boundary within 40 characters so the branch name stays readable.
# LC_ALL=C is what keeps the slug ASCII: under a UTF-8 locale [a-z0-9] is a
# collation range that accented letters fall inside, so they would survive into
# a branch name. iconv only makes the result readable where it exists.
if command -v iconv >/dev/null 2>&1; then ascii=(iconv -f UTF-8 -t ASCII//TRANSLIT); else ascii=(cat); fi
slug=$(printf '%s' "$title" \
  | sed 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/Ä/Ae/g; s/Ö/Oe/g; s/Ü/Ue/g; s/ß/ss/g' \
  | "${ascii[@]}" 2>/dev/null \
  | LC_ALL=C tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' \
  | LC_ALL=C awk '{ s=""; n=split($0,w,"-"); for(i=1;i<=n;i++){ c=(s==""?w[i]:s"-"w[i]); if(length(c)>40) break; s=c }
                   if (s == "") s = substr($0,1,40); sub(/-$/,"",s); print s }')
# A title that transliterates to nothing at all still gets a name it can be
# found under, rather than a branch ending in a bare hyphen.
if [ -n "$slug" ]; then
  leaf="issue-${number}-${slug}"
  branch="issue/${number}-${slug}"
else
  leaf="issue-${number}"
  branch="issue/${number}"
fi
worktree="$(dirname "$checkout")/$(basename "$checkout")-worktrees/${leaf}"

# Parity: the code remote must carry the exact commit the tracker reports.
remote_head=$(git rev-parse "$remote/$default") || { echo "prepare-worktree.sh: $remote/$default is unknown here" >&2; exit 2; }
remote_tree=$(git rev-parse "$remote/$default^{tree}")
tracker=$(gh api "repos/$repository/commits/$default" --jq '.sha + " " + .commit.tree.sha') || {
  echo "prepare-worktree.sh: cannot read $repository@$default" >&2; exit 2; }
tracker_head=${tracker%% *}
tracker_tree=${tracker##* }
if [ "$remote_head" != "$tracker_head" ] || [ "$remote_tree" != "$tracker_tree" ]; then
  echo "prepare-worktree.sh: REMOTE MISMATCH" >&2
  echo "  tracker $repository@$default = $tracker_head tree $tracker_tree" >&2
  echo "  $remote/$default = $remote_head tree $remote_tree" >&2
  exit 3
fi

# Anything already carrying this ticket is another session's work, never ours to reuse silently.
if [ -e "$worktree" ]; then
  echo "prepare-worktree.sh: EXISTING WORK FOUND — worktree already at $worktree" >&2; exit 4; fi
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "prepare-worktree.sh: EXISTING WORK FOUND — local branch $branch exists" >&2; exit 4; fi
if git ls-remote --exit-code --heads "$remote" "$branch" >/dev/null 2>&1; then
  echo "prepare-worktree.sh: EXISTING WORK FOUND — remote branch $branch exists" >&2; exit 4; fi

mkdir -p "$(dirname "$worktree")"
if ! git worktree add --quiet -b "$branch" "$worktree" "$remote_head"; then
  rmdir "$(dirname "$worktree")" 2>/dev/null || true
  echo "prepare-worktree.sh: could not create the worktree at $worktree" >&2
  exit 2
fi

head=$(git -C "$worktree" rev-parse HEAD)
status_count=$(git -C "$worktree" status --porcelain | wc -l)
upstream=$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "none")

cat <<REPORT
ticket: #$number $title
worktree: $worktree
branch: $branch
upstream: $upstream
head: $head
base: $remote/$default @ $remote_head
tracker head: $tracker_head
parity: identical commit and tree
clean: $([ "$status_count" -eq 0 ] && echo yes || echo "no — $status_count entries")
REPORT
[ "$status_count" -eq 0 ]
