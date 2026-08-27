---
name: forgimus
description: Survey the state of the work and carry one ticket from preparation through publication, merge, and cleanup. Requires git and an authenticated GitHub CLI.
disable-model-invocation: true
---

# Forgimus

One skill for the arc a change travels: pick a ticket, prepare its worktree, publish the result, merge it, reclaim what the merge left behind. Implementation stays outside — `@Implement` is a separate skill this one hands to and receives back from.

User-facing updates keep the user's language.

## Preconditions

This skill runs on git and GitHub. Every phase reads or writes through `gh`, and every phase keeps the repository's documented tracker.

```bash
scripts/check-prerequisites.sh [owner/repo]
```

Run it ahead of the first option of a session, and whenever another script exits `2`. It checks git, the checkout, the commit identity, `gh`, its login, and read access, then prints the exact fix for anything missing.

| Missing | Who resolves it |
|---|---|
| a package | the user — installation needs elevation |
| GitHub network or credential-store access | this skill — rerun the check with that sandbox access |
| no configured account or confirmed invalid credentials | the user — `gh auth login` is interactive by design |
| anything else | this skill |

Hand those two to the user, say they can run one here by typing `!` followed by the command, then re-run the check.

## Invocation

```
/forgimus                    survey everything, report, recommend
/forgimus prepare [ticket]   → phases/prepare.md
/forgimus publish [ticket]   → phases/publish.md
/forgimus merge [pr]         → phases/merge.md
/forgimus cleanup [pr]       → phases/cleanup.md
```

Read a phase file when its option fires, and only then. Without an option, run the survey below and stop.

## Tiers

The tier decides both what a missing target means and what authorization the option needs.

| Tier | Options | Effect | Without a target | Needs the user's say-so |
|---|---|---|---|---|
| 1 · reads | the bare survey | reports | — | no |
| 2 · local | `prepare` | branch, worktree, setup — undone with one command | selects the next ticket itself and acts | no |
| 3 · outward | `publish` `merge` `cleanup` | pushes, merges into the default branch, deletes branches and worktrees along with their ignored files | reports what it would do, acts on nothing | yes |

`cleanup --all` reclaims every branch the survey proved safe, in one pass, through the sweep in [`phases/cleanup.md`](phases/cleanup.md).

| The survey's recommendation named | A bare "yes" |
|---|---|
| exactly one action | authorizes that tier 3 option |
| several as equal | authorizes nothing — the option is named first |

## The survey

Two sources, neither subordinate:

| Source | Holds |
|---|---|
| tracker | open tickets, blocking edges, sub-issues |
| repository | branches, worktrees, pull requests, checks |

```bash
scripts/survey-tickets.sh <owner/repo>
scripts/survey-branches.sh <owner/repo>
```

### Recommendation procedure

1. Run both survey scripts.
2. For each open pull request, run:

```bash
scripts/review-evidence.sh <owner/repo> <pr-number>
```

| Repository state | Review evidence | Recommendation |
|---|---|---|
| branch or worktree, no open pull request | — | `/forgimus publish <ticket>` |
| open pull request | current for its head | `/forgimus merge <pr>` |
| open pull request | missing or stale | `/forgimus merge <pr>`; the merge phase runs the review gate |
| merged pull request with safe leftovers | — | `/forgimus cleanup <pr>` |
| no work in flight | — | `/forgimus prepare <ticket>` |

| Invariant | Owner |
|---|---|
| create or refresh a pull request | `publish` |
| review the current head | `merge` |
| lift draft | `merge` |
| integrate | `merge` |

Report each source, then report where they disagree. A disagreement is itself the finding. Report these six:

| # | Disagreement |
|---|---|
| 1 | a pull request carries the work while its ticket still reads open |
| 2 | a ticket's acceptance criteria are already met by a pull request opened for another ticket |
| 3 | a merged pull request's branch or worktree is still here |
| 4 | a branch or worktree belongs to no ticket and no pull request |
| 5 | a local commit was never pushed |
| 6 | an open pull request has failing checks or a blocked gate |

Report a closed blocker as a closed blocker. Whether an edge is satisfied is a judgement with evidence behind it, and [`phases/prepare.md`](phases/prepare.md) makes it there.

Shape: sections for tickets, work in flight, disagreements, leftovers, then exactly one recommendation line naming one next action or stating that several rank equally.

| Rule | |
|---|---|
| facts | in tables, each said once |
| an empty section | one word |
| prose | only where a table cannot hold the point: a disagreement, or a caveat that changes what the recommendation means |
| a named ticket | highlights its rows, and leaves the report whole |

## Scripts

| Script family | Output |
|---|---|
| `check-*`, `review-evidence.sh`, `reclaim.sh`, `verify-merged.sh` | one `RESULT  check  detail` line per check |
| `survey-*` | one table row per surveyed item |
| `prepare-worktree.sh` | the `key: value` verification block used by `prepare.md` |

Exit: `0` fine · `1` a check refused · `2` prerequisite missing. `prepare-worktree.sh` also uses `3`, `4`, and `5` for its documented recovery states.

| Script | Does | Needs |
|---|---|---|
| `scripts/check-prerequisites.sh [owner/repo]` | git, checkout, commit identity, `gh`, login, repository access — and the fix for each | — |
| `scripts/survey-tickets.sh <owner/repo>` | one row per open ticket: blockers, sub-issues, whether a branch or pull request exists | `gh` |
| `scripts/survey-branches.sh <owner/repo> [--apply] [--force]` | one row per leftover branch: which pull request merged it, whether reclaiming is safe | `gh` |
| `scripts/prepare-worktree.sh <owner/repo> <issue>` | proves remote parity, creates the issue worktree | `gh` |
| `scripts/check-push.sh [base-ref]` | proves the worktree is safe to push | git |
| `scripts/review-evidence.sh <owner/repo> <pr> [--record <sha>]` | reads or records a clean Standards/Spec review for the exact pull request head | `gh` |
| `scripts/check-merge.sh <owner/repo> <pr>` | the merge gates against the current head | `gh` |
| `scripts/verify-merged.sh <owner/repo> <pr> <reviewed-sha>` | proves the squash carried the reviewed tree | `gh` |
| `scripts/reclaim.sh <owner/repo> <pr> [--apply] [--force]` | removes worktree and branches a merged pull request left | `gh` |

Removal and publication each require an explicit flag.

Where `gh` is unauthenticated, the seven that need it exit `2` and say so. The phase files are then the specification: carry out their steps against the documented tracker and report the same evidence by hand. Treat a survey assembled that way as a claim to check. The tracker is swappable by documentation; these scripts are not.

## Finding severity

Used by [`phases/publish.md`](phases/publish.md) and [`phases/merge.md`](phases/merge.md). The code-review workflow reports findings without severities, so state this scale when requesting a review and require one per finding.

| Severity | Meaning | Blocks publication and merge |
|---|---|---|
| P0 | the change is broken or unsafe, or contradicts a decision record | yes |
| P1 | an acceptance criterion is unmet, or a defect reaches a user | yes |
| P2 | a real defect, or verification the change removed and did not replace | yes |
| P3 | naming, style, or a suggestion that changes no behaviour | no, recorded |

## Repository identity

Used by every phase. Resolve and record three identities separately:

| Identity | Resolve from |
|---|---|
| tracker repository | an explicit issue URL first, then documented tracker configuration |
| publication repository | the repository that receives branches and pull requests |
| code remote | the local remote representing the publication repository |

A remote named `origin` and the local checkout are labels, not proof.

**Stop:** the identities differ without an explicit documented rule mapping them → `REMOTE MISMATCH`.

Fetch rather than pull, leaving the current worktree unmerged.

## Boundary

Implementation belongs to `@Implement`. Force-push, administrative bypass, history rewriting, unrelated fixes, and rollback stay outside every phase. The default branch is the canonical integrated source.
