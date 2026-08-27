#!/usr/bin/env bash
# Reclaim the worktree and branches a merged pull request left behind.
#
# Usage: reclaim.sh <owner/repo> <pr-number> [--apply] [--force]
# Run from anywhere inside the primary checkout.
# Without --apply nothing is removed: the plan is printed and the run ends.
# --force additionally removes a worktree holding untracked or modified files.
# Output: one "RESULT  check  detail" line per check, then the plan or the actions.
# Exit:  0 safe to reclaim, or reclaimed · 1 a check refused · 2 prerequisite missing
#
# git clean sets the precedent this follows: refuse to delete without an
# explicit force flag (clean.requireForce).

set -euo pipefail

repository=${1:-}
pr=${2:-}
if [ -z "$repository" ] || [ -z "$pr" ]; then
  echo "reclaim.sh: usage: reclaim.sh <owner/repo> <pr-number> [--apply] [--force]" >&2
  exit 2
fi
shift 2
apply=no
force=no
for argument in "$@"; do
  case "$argument" in
    --apply) apply=yes ;;
    --force) force=yes ;;
    *) echo "reclaim.sh: unknown argument $argument" >&2; exit 2 ;;
  esac
done
command -v gh >/dev/null 2>&1 || { echo "reclaim.sh: gh is not installed; follow the phase file's steps" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "reclaim.sh: not inside a git checkout" >&2; exit 2; }

# A remote named origin is a label, not proof: use the one whose URL is the
# repository this run is about.
remote=""
while read -r name url; do
  case "$url" in
    *[:/]"$repository" | *[:/]"$repository".git) remote="$name"; break ;;
  esac
done < <(git remote -v | awk '$3 == "(fetch)" { print $1, $2 }')
[ -n "$remote" ] || { echo "reclaim.sh: no git remote points at $repository" >&2; exit 2; }

refused=0
report() { printf '%-6s %-24s %s\n' "$1" "$2" "$3"; [ "$1" = REFUSE ] && refused=1 || true; }

fields=$(gh pr view "$pr" --repo "$repository" --json state,mergedAt,headRefName,headRefOid,baseRefName \
  --jq '[.state, (.mergedAt // "none"), .headRefName, .headRefOid, .baseRefName] | @tsv') || {
  echo "reclaim.sh: pull request #$pr not readable in $repository" >&2; exit 2; }
IFS=$'\t' read -r state merged_at branch merged_oid base <<<"$fields"

if [ "$state" = MERGED ] && [ "$merged_at" != none ]; then
  report OK "pull request" "MERGED at $merged_at"
else
  report REFUSE "pull request" "$state, mergedAt=$merged_at — reclaim only after a merge"
  exit 1
fi
[ "$branch" != "$base" ] || { report REFUSE "branch" "$branch is the base branch"; exit 1; }

current=$(git branch --show-current || true)
if [ "$branch" != "$current" ]; then
  report OK "not checked out here" "current branch is ${current:-detached}"
else
  report REFUSE "not checked out here" "$branch is checked out in this worktree"
  exit 1
fi

git fetch --prune --quiet "$remote" || true

# The local branch may not exist at all; that half of the work is simply done.
local_sha=""
if git show-ref --verify --quiet "refs/heads/$branch"; then
  local_sha=$(git rev-parse "refs/heads/$branch")
  if [ "$local_sha" = "$merged_oid" ]; then
    report OK "local branch" "$branch at the merged head"
  else
    report REFUSE "local branch" "$branch is at $local_sha, the merge took $merged_oid"
  fi
fi
[ -n "$local_sha" ] || report OK "local branch" "already gone"

# Squash rewrites the commit, so reachability proves nothing. Rebuild the patch
# the squash would have produced and ask whether it is already in the base. The
# tree comes from the local branch, or from the merged head where that object is
# still here; with neither, there is no local object left to prove anything about.
proof_ref=""
if [ -n "$local_sha" ]; then
  proof_ref="refs/heads/$branch"
elif git cat-file -e "${merged_oid}^{commit}" 2>/dev/null; then
  proof_ref="$merged_oid"
fi
if [ -z "$proof_ref" ]; then
  report NOTE "content in $base" "no local object carries this branch; the tracker record stands alone"
elif ! merge_base=$(git merge-base "$remote/$base" "$proof_ref" 2>/dev/null); then
  report REFUSE "content in $base" "no merge base between $proof_ref and $remote/$base"
elif ! synthetic=$(git commit-tree "$(git rev-parse "${proof_ref}^{tree}")" -p "$merge_base" -m reclaim-probe 2>/dev/null); then
  report REFUSE "content in $base" "the squash probe could not be built"
elif git cherry "$remote/$base" "$synthetic" | grep -q '^-'; then
  report OK "content in $base" "the branch tree is already in $remote/$base"
else
  report REFUSE "content in $base" "$remote/$base does not carry this tree"
fi

# A worktree still holding the branch blocks branch deletion, so it goes first.
worktree=$(git worktree list --porcelain -z \
  | awk -v RS='\0' -v want="branch refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0==want{print p; exit}')
primary=$(git worktree list --porcelain -z | awk -v RS='\0' '/^worktree /{print substr($0,10); exit}')
if [ -n "$worktree" ]; then
  if [ "$worktree" = "$primary" ]; then
    report REFUSE "worktree" "the branch is held by the primary checkout"
  elif git worktree list --porcelain -z \
    | awk -v RS='\0' -v p="worktree $worktree" '/^worktree /{f=($0==p)} f&&/^locked/{print;exit}' | grep -q .; then
    report REFUSE "worktree" "$worktree is locked — unlock it deliberately first"
  elif ! dirty=$(git -C "$worktree" status --porcelain 2>/dev/null | wc -l); then
    report REFUSE "worktree" "$worktree cannot be read"
  else
    if [ "$dirty" -eq 0 ]; then
      report OK "worktree" "$worktree is clean"
    elif [ "$force" = yes ]; then
      report OK "worktree" "$worktree has $dirty uncommitted entry/entries — --force will discard them"
    else
      report REFUSE "worktree" "$worktree has $dirty uncommitted entry/entries; pass --force to discard them"
    fi
    # Ignored files never block removal and are deleted without a warning.
    ignored=$(git -C "$worktree" status --porcelain --ignored 2>/dev/null | grep -c '^!!' || true)
    [ "$ignored" -gt 0 ] && report NOTE "ignored files" "$ignored path(s) such as build output or .env will be deleted with the worktree" || true
  fi
else
  report OK "worktree" "none holds this branch"
fi

# Deleting a branch that is the head of another open pull request closes it, so
# a lookup that failed is a refusal rather than an absence.
if heads=$(gh pr list --repo "$repository" --state open --head "$branch" --json number --jq '[.[].number] | join(", ")' 2>/dev/null); then
  if [ -z "$heads" ]; then
    report OK "open pull request" "none uses $branch as its head"
  else
    report REFUSE "open pull request" "#$heads still uses $branch as its head branch"
  fi
else
  report REFUSE "open pull request" "the lookup failed; deleting a head branch would close its pull request"
fi

# Open pull requests based on it are retargeted by GitHub, not closed.
if bases=$(gh pr list --repo "$repository" --state open --base "$branch" --json number --jq '[.[].number] | join(", ")' 2>/dev/null); then
  [ -n "$bases" ] && report NOTE "stacked pull requests" "#$bases will be retargeted to $base by GitHub" || true
else
  report NOTE "stacked pull requests" "the lookup failed; GitHub retargets any that exist"
fi

# git, not the API: a REST 404 arrives on stdout and would read as a sha.
set +e
remote_line=$(git ls-remote --exit-code "$remote" "refs/heads/$branch" 2>/dev/null)
ls_status=$?
set -e
remote_sha=""
case "$ls_status" in
  0)
    remote_sha=$(printf '%s\n' "$remote_line" | awk 'NR == 1 { print $1 }')
    if [ "$remote_sha" = "$merged_oid" ]; then
      report OK "remote branch" "$remote/$branch at the merged head"
    else
      report REFUSE "remote branch" "$remote/$branch is at $remote_sha, the merge took $merged_oid"
    fi
    ;;
  2) report OK "remote branch" "already gone" ;;
  *) report REFUSE "remote branch" "the lookup against $remote failed" ;;
esac

echo
echo "rescue anchor: git branch $branch $merged_oid   # the reflog does not survive this"
echo

if [ "$refused" -ne 0 ]; then
  echo "refusing to reclaim; resolve the REFUSE lines above"
  exit 1
fi

if [ "$apply" != yes ]; then
  echo "plan (pass --apply to carry it out):"
  [ -n "$worktree" ] && echo "  git worktree remove $([ "$force" = yes ] && echo '--force ')$worktree"
  echo "  git worktree prune"
  [ -n "$local_sha" ] && echo "  git branch -D $branch"
  [ -n "$remote_sha" ] && echo "  git push $remote --delete $branch"
  exit 0
fi

if [ -n "$worktree" ]; then
  if [ "$force" = yes ]; then
    git worktree remove --force "$worktree"
  else
    git worktree remove "$worktree"
  fi
  echo "removed worktree $worktree"
fi
# Orphaned administrative files keep blocking branch deletion even after a
# successful removal, so prune unconditionally.
git worktree prune
if [ -n "$local_sha" ]; then
  # -D, not -d: with the remote branch still present -d tests the branch against
  # its own upstream and passes tautologically. The proof was made above.
  git branch -D "$branch"
fi
if [ -n "$remote_sha" ]; then
  if git push "$remote" --delete "$branch" 2>/dev/null; then
    echo "deleted $remote/$branch"
  else
    echo "$remote/$branch was already gone"
  fi
fi
echo "reclaimed $branch"
