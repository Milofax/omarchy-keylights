# Publish

Commit, push, and open one draft pull request for a finished `@Implement` result.

Authorization ends at a verified draft pull request. Ready-for-review, merge, auto-merge, branch deletion, force-push, and deployment belong to [`merge.md`](merge.md). Repository identity and the P0–P3 scale are in [`../SKILL.md`](../SKILL.md).

## 1. Resolve the result

| Fact | Source |
|---|---|
| ticket, acceptance criteria | tracker |
| worktree, branch, prepared base | `git worktree list`, `git status` |
| changed paths since the base | `git diff --name-only <base>...HEAD` |
| staged, unstaged, untracked, committed work | `git status --short`, `git log <base>..HEAD` |
| verification and review evidence | this conversation, prior runs |

Reuse an existing branch or pull request only where its target and ancestry are proven. Treat every path outside the implementation result as user-owned.

**Ask:** the worktree mixes the implementation with other changes → one question, naming the exact path scope.

**Done when:** one ticket, one tree, one exact path set, one prepared base.

## 2. Prove readiness

Run the repository's own commands, under the names its instructions and configuration give them.

| Evidence | Requirement |
|---|---|
| tests, typecheck, lint, build | green on the exact tree |
| acceptance criteria | each one met by the diff |
| Standards/Spec review | covers the exact tree, one severity per finding |

Rerun any verification whose evidence predates a changed file. Run the code-review workflow where no review covers the exact tree.

Severity is the verdict. A review naming a P2 blocks while closing with "merge ok".

**Stop:** failed verification, or an unresolved P0, P1, or P2 → `STATUS: BLOCKED`.

**Done when:** the exact tree carries current green verification and current review evidence.

## 3. Choose the base

```bash
git fetch --prune <remote>
```

| Situation | Base |
|---|---|
| every prerequisite merged | the default branch |
| an explicit unmerged prerequisite | that prerequisite's head branch, stacked |

Specs and decision records take their place ahead of what depends on them.

**Stop:** repository identity, mirror parity, base ancestry, or dependency ownership cannot be proven.

**Done when:** the base and its reason are recorded.

## 4. Commit the exact tree

1. Branch, where the work still sits on the default branch.
2. Stage with explicit path arguments only.
3. Inspect: `git status --short`, `git diff --cached --name-only`, `git diff --cached`, `git diff --cached --check`.
4. One focused commit, in the language and format recent history uses. Verify and keep a correct `@Implement` commit.

**Done when:** the commit holds every intended path and nothing else.

## 5. Push

```bash
scripts/check-push.sh [base-ref]
```

Proves: not the default branch · worktree clean · commits exist · whitespace sound · push fast-forwards.

Refresh the remote branch and any pull request already on it. Push fast-forward only, setting upstream where needed.

| Shell authentication | Path |
|---|---|
| available | `git push` |
| absent, authorized GitHub connector present | branch, blob, tree, commit, and non-forced ref operations over the resolved remote base; verify the remote changed-file set equals the local one |

**Stop:** divergence, ambiguity, permission failure, or a non-fast-forward update.

**Done when:** the remote branch is the exact reviewed tree.

## 6. Open one draft pull request

Reuse the open pull request for the same head and base. Otherwise create exactly one, in draft, titled with the ticket title.

The body carries:

- the implemented outcome and the issue reference;
- current verification and review evidence;
- base branch, prerequisite pull requests, required merge order;
- `Closes #<issue>` where every acceptance criterion is met, otherwise the issue named without a closing keyword.

**Stop:** an existing pull request is already non-draft → report its state, ahead of the review lifecycle.

**Done when:** exactly one draft pull request carries the tree.

## 7. Record the reviewed head

```bash
scripts/review-evidence.sh <owner/repo> <pr-number> --record <reviewed-head-sha>
```

| Check | Required value |
|---|---|
| reviewed head | current remote pull request head |
| Standards | PASS |
| Spec | PASS |
| blocking findings | 0 |

**Stop:** the pull request head changed after the review.

**Done when:** the pull request carries current machine-readable review evidence.

## 8. Wait for CI

Verify: remote commit, exact filenames, base and head SHAs, draft state, mergeability, URL, dependency stack, CI status. Settle an uncertain external result by read-only lookup before retrying.

Wait for the first conclusion of the required checks. Bound the wait by the timeout the checks declare, or ten minutes where they declare none.

| CI for this head | Hand off as |
|---|---|
| success | `STATUS: DRAFT PR PUBLISHED` |
| failure | `STATUS: BLOCKED`, naming the failing check |
| queued past the bound | `CI: pending` |

A failing check leaves the fix on the branch. [`merge.md`](merge.md) re-evaluates CI against the current head immediately before merging.

**Done when:** the CI conclusion for this head is recorded, or the bound expired.

## 9. Return

Every line below is a field. A table rendering keeps every one of them as a row, `Pull request` included.

```text
Pull request: <#N — URL — draft state>
STATUS: <DRAFT PR PUBLISHED | EXISTING PR VERIFIED | BLOCKED>
Target: <issue and title>
Branch: <remote branch @ SHA>
Base: <branch @ SHA; dependency reason>
Changed paths: <count and list>
Verification: <commands and outcomes>
Review: <Standards/Spec result; every finding with its severity>
Reviewed head: <exact SHA recorded by review-evidence.sh>
CI: <conclusion for this head, pending, or absent>
Merge order: <prerequisite #Ns, then this #N>
Blocks: <tickets waiting on this one, or none>
Next: </forgimus merge <N>, or the exact blocker to clear first>
```

`Next` names the command to type. A draft stays invisible to every merge gate while its ticket blocks its dependents.
