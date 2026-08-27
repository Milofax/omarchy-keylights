# Merge

Take one published pull request through its review lifecycle, squash-merge its dependency chain, and verify the documented deployment.

Force-push, administrative bypass, unrelated fixes, destructive branch cleanup, and rollback stay outside this authorization. The P0–P3 scale is in [`../SKILL.md`](../SKILL.md).

## 1. Resolve the pull request

| # | Source | Use where |
|---|---|---|
| 1 | explicit number or URL | given |
| 2 | the [`publish.md`](publish.md) handoff | exactly one current pull request is unambiguous |
| 3 | one short question naming the candidates | a genuine tie |

Load: pull request, issue, linked spec and decisions, comments, reviews, unresolved threads, changed files, commits, base and head SHAs, checks, branch rules, merge queue, deployments.

Classify as draft, ready, merged, closed, conflicted, or blocked. `ALREADY MERGED` requires the integrated commit and the deployment state, both verified.

**Done when:** one pull request, its exact reviewed tree, repository identity, and lifecycle state are proven, and it holds one reviewed implementation result with no unrelated change.

## 2. Order the chain

Resolve blocking pull requests and stacked bases recursively into one topological order.

| Rule | |
|---|---|
| specs and decisions | merge ahead of the implementations depending on them |
| declared prerequisites the requested pull request needs | included |
| independent pull requests | left for their own invocation |

Record the default-branch SHA ahead of the first mutation.

**Stop:** cycle, ambiguous base, undeclared dependency, or repository mismatch.

**Done when:** every pull request in the chain and its position are explicit.

## 3. Enforce the gates

```bash
scripts/check-merge.sh <owner/repo> <pr-number>
```

`PASS`, `FAIL`, or `INFO` per gate; exit `1` on any `FAIL`. `INFO` marks a lookup that needs judgement. Evaluate each pull request against its current head immediately ahead of changing lifecycle or merging.

| # | Gate | Passes where |
|---|---|---|
| 1 | change set | open, mergeable, on the intended base, exactly the reviewed change set |
| 2 | permission | issue, acceptance criteria, dependency edges, and repository instructions permit integration |
| 3 | review | required approvals given, required threads resolved, no unresolved P0, P1, or P2 on the exact head |
| 4 | verification | tests, typecheck, lint, build, and required remote CI successful for the exact head |
| 5 | protection | branch protection, merge queue, required conversations, and required approvals satisfied without bypass |
| 6 | base | base current enough for repository policy, no conflict |

Gate 3 signals:

| Signal | Raise it as a concern where |
|---|---|
| `review decision: none` | the repository requires an approving review. Where none is required, the code-review workflow is the review evidence this gate asks for: record the signal as a standing repository property and pass the gate. |
| open review thread | a required conversation is unresolved |
| Standards/Spec finding | its severity is P0, P1, or P2 |

```bash
scripts/review-evidence.sh <owner/repo> <pr-number>
```

| Result | Procedure |
|---|---|
| `PASS review current head <sha>` | use it for gate 3 |
| `INFO review missing` | run the code-review workflow on the current head |
| `INFO review stale` | run the code-review workflow on the current head |
| `FAIL review` | keep gate 3 failed |

| Clean review step | Command |
|---|---|
| record the exact reviewed head | `scripts/review-evidence.sh <owner/repo> <pr-number> --record <reviewed-head-sha>` |
| re-read the evidence | `scripts/review-evidence.sh <owner/repo> <pr-number>` |

| Gate 3 completion | Required value |
|---|---|
| review evidence | `PASS review current head <sha>` |
| `<sha>` | current pull request head |

Gate 4 signals:

| Signal | Verdict |
|---|---|
| code change, no required remote CI | `MERGE BLOCKED: CI missing` |
| documented docs-only exemption naming the required local verification | exemption applies |

A changed head or base makes every affected gate stale — re-evaluate. This phase authorizes the normal merge; a failed gate stays failed, and its fix belongs on the branch.

**Auto-merge:** where only binding required checks remain pending and the repository supports protected auto-merge, enable squash auto-merge once every non-CI gate passes.

**Stop:** any failed gate → `MERGE BLOCKED`, named exactly.

**Done when:** every gate on the current head passes, or one is named as the blocker.

## 4. Squash-merge, one at a time

For the first gated pull request:

1. Lift the draft once every gate passes.
2. Re-fetch head, base, reviews, threads, and checks, closing the time-of-check gap.
3. Squash-merge. Title: `<pull request title> (#<N>)`. Body: the outcome plus the issue reference.
4. Verify:

   ```bash
   scripts/verify-merged.sh <owner/repo> <pr-number> <reviewed-head-sha>
   ```

   Squash rewrites the commit, so ancestry proves nothing about content. This compares trees, checks the issue transition, and names the leftovers.

Squash merge exclusively. Source branches stay while stacked children need them.

Each direct stacked child, after its prerequisite merges: refresh the default branch, realign the child by normal non-forced update or merge, retarget it, prove its changed-file set holds only its own result, then re-run every gate on its new head and base.

**Stop:** conflict, duplicated prerequisite changes, or a required history rewrite.

**Done when:** the requested pull request is merged, or a gate stopped the chain.

## 5. Verify deployment

Resolve the mechanism and target from repository documentation first. A service running on this machine is evidence of a deployment, never a specification of one.

| Documentation says | Do |
|---|---|
| automatic | wait for the workflow or hosting checkpoint tied to the merged SHA |
| manual, tied to merging | run its normal non-bypass procedure |
| nothing | `DEPLOYMENT NOT DOCUMENTED`, and finish there |

Build or observe only from the merged commit. Verify workflow status, deployed source SHA or immutable artifact identity, and the documented health check.

Report an absent, pending, or failed deployment as that state. A successful merge is not a release; rollback stays outside this phase.

**Done when:** production identity is proven, or the exact post-merge blocker is recorded.

## 6. Return

Every line below is a field. A table rendering keeps every one of them as a row, `Pull request` included.

```text
Pull request: <#N — URL>
STATUS: <MERGED AND DEPLOYED | AUTO-MERGE ENABLED | MERGE BLOCKED | MERGED, DEPLOYMENT PENDING | MERGED, DEPLOYMENT FAILED | MERGED, DEPLOYMENT NOT DOCUMENTED | ALREADY MERGED>
Target: <issue and title>
Repository: <owner/name>
Dependency order: <ordered #Ns>
Gate evidence: <reviews, threads, local verification, CI, branch rules>
Merged: <each #N and its squash commit, or none>
Default branch: <before SHA -> verified current SHA>
Stack realignment: <retarget and update result>
Deployment: <target, workflow or checkpoint, source SHA, health>
Unblocked: <tickets freed, and any that stay blocked and why>
Leftovers: </forgimus cleanup <N>, or none>
Remaining blocker: <exact gate, or none>
```
