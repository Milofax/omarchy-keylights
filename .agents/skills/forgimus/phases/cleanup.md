# Cleanup

Reclaim the local and remote state one merged pull request made redundant.

Unmerged commits, a dirty or locked worktree, and anything an open pull request still needs stay exactly where they are. Merges, force-push, history rewriting, and any branch whose content is unproven in the base stay outside this authorization.

```bash
scripts/survey-branches.sh <owner/repo>              # the table
scripts/survey-branches.sh <owner/repo> --apply      # reclaim every safe row
scripts/reclaim.sh <owner/repo> <pr-number>          # one pull request, the plan
scripts/reclaim.sh <owner/repo> <pr-number> --apply  # carry it out
```

| Invocation | Runs |
|---|---|
| `/forgimus cleanup <pr>` | `reclaim.sh <owner/repo> <pr>` |
| `/forgimus cleanup --all` | `survey-branches.sh <owner/repo> --apply` |

`--apply` is required before anything is removed. `--force` reaches `reclaim.sh`, which then also accepts a dirty worktree. Without `gh`, the steps below are the specification.

## The table

[`../scripts/survey-branches.sh`](../scripts/survey-branches.sh) prints one row per open pull request or non-default branch still present locally, remotely, or in a worktree, under the columns `BRANCH`, `PR`, `VERDICT`, `WHERE`, `REVIEW`, `NEXT`, `DETAIL`.

| Verdict | Meaning | Under `--apply` |
|---|---|---|
| safe | a merged pull request, and every check below passes | reclaimed |
| blocked | merged, and a check refused — `DETAIL` carries the refusal verbatim | resolve it, or pass `--force` where the refusal offers it |
| kept | no merged pull request stands behind the branch: unpublished work, an open pull request, a pull request closed unmerged | untouched |

Each verdict comes from [`../scripts/reclaim.sh`](../scripts/reclaim.sh) running steps 1 to 4 against that one pull request, so the table's `safe` and removal's `safe` are one judgement. `--apply` re-runs those checks per pull request rather than trusting the table, because state moves between surveying and sweeping.

## 1. Prove the merge carried the content

Both proofs required:

| Proof | How |
|---|---|
| tracker record | `state` is `MERGED` and `mergedAt` is set |
| content | rebuild the patch the squash produced, and ask whether the base carries it |

The content proof runs against the local branch, or against the merged head where that object is still here. With neither, there is no local object to prove anything about: the run says so and the tracker record stands alone.

```bash
merge_base=$(git merge-base origin/<base> <branch>)
synthetic=$(git commit-tree "$(git rev-parse <branch>^{tree})" -p "$merge_base" -m probe)
git cherry origin/<base> "$synthetic"    # a leading "-" means the content is in the base
```

Squash rewrites the commit, so the branch tip is unreachable from the base and reachability proves nothing. Require the local branch to sit exactly on the pull request's merged head, so nothing committed after the merge is thrown away.

`git branch -d` proves nothing here: while the remote branch exists it tests the branch against its own upstream, passes tautologically, and deletes with a warning and exit `0`.

**Done when:** both proofs hold.

## 2. Name what removal destroys

| Loss | Why | Do |
|---|---|---|
| ignored files | `git worktree remove` deletes them without `--force` and without warning, because `git status --porcelain` calls the worktree clean | run `git status --porcelain --ignored` and report what would go |
| reflogs | removal deletes the worktree's HEAD reflog with its administrative directory, and `git branch -D` deletes the branch reflog | print the merged head SHA as the rescue anchor first — afterwards only that SHA, or `git fsck --unreachable` ahead of the next `git gc`, leads back |
| a locked worktree | the lock is a deliberate signal | leave it, and say so |

**Done when:** every loss is named ahead of the first removal.

## 3. Check the pull requests around the branch

| The branch is the | Deletion would | Action |
|---|---|---|
| head of an open pull request | close it | refuse |
| base of open pull requests | leave them retargeted by the tracker to the merged pull request's base | report them, continue |

## 4. Reclaim in this order

| # | Command | Why here |
|---|---|---|
| 1 | `git worktree remove <path>` | the branch resists deletion while a worktree holds it |
| 2 | `git worktree prune` | always — an orphaned administrative directory keeps blocking branch deletion |
| 3 | `git branch -D <branch>` | `-D`, because step 1 proved what `-d` cannot |
| 4 | `git push origin --delete <branch>` | a second run exits `1` with `remote ref does not exist`, which is the work already done |

**Done when:** every step reported its outcome.

## 5. Return

Every line below is a field. A table rendering keeps every one of them as a row.

```text
STATUS: <RECLAIMED | PLAN ONLY | REFUSED>
Pull request: <#N, merged at>
Branch: <name at merged head SHA>
Rescue anchor: <git branch <name> <SHA>>
Worktree: <path removed, left in place with the reason, or none>
Local branch: <deleted, or already gone>
Remote branch: <deleted, or already gone>
Destroyed: <ignored paths that went with the worktree, or none>
Retargeted: <stacked pull requests the tracker moved, or none>
Refused: <exact reason, or nothing>
```

| Invocation | Report |
|---|---|
| survey | the table, then what a sweep would remove |
| sweep | one block per reclaimed pull request, plus every row left alone and why |
