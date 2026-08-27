# Prepare

Prepare one implementation target completely, then return control.

This phase changes local state only: it finishes without implementation edits, commits, pushes, pull requests, merges, or tracker mutations. `@Implement` is a separate, explicit invocation. Repository identity rules are in [`../SKILL.md`](../SKILL.md).

## 1. Choose the target

| # | Source | Use where |
|---|---|---|
| 1 | explicit issue number, URL, or ticket path | given |
| 2 | conversational target | exactly one is unambiguous |
| 3 | the survey below | no target named |

```bash
scripts/survey-tickets.sh <owner/repo>
```

One TSV row per open issue: `number`, `blocked_by`, `sub_issues`, `branch`, `pr`, `labels`, `title`. `branch` and `pr` say whether work already exists. Without `gh`, enumerate the tracker's open tickets and establish the same facts.

A candidate is implementable where all hold:

- no open sub-issues — a ticket carrying them is a container, so descend and evaluate those instead;
- required decisions resolved;
- every blocking edge closed or otherwise satisfied;
- acceptance criteria not already implemented;
- no existing branch, worktree, commit, or pull request that calls for a resume or publication decision instead.

Rank eligible candidates by the tracker's documented queue, priority, milestone, and dependency order. An issue number or list position counts as priority only where project documentation says so.

| Outcome | Action |
|---|---|
| one highest-ranked eligible candidate | select it |
| genuine tie | one short question naming only the tied candidates |
| none eligible | `STATUS: BLOCKED`, each candidate with its stop reason |
| a higher-ranked ticket passed over because work already exists for it | that ticket fills the `Bottleneck` field, ahead of the ticket selected |

Load the selected ticket in full: comments, acceptance criteria, linked spec, and every declared blocking edge resolved to its current state. Inspect existing branches, commits, worktrees, and pull requests for the same ticket. Classify from that evidence as untouched, partial, already implemented, or blocked.

**Stop:** an open blocker, absent explicit authorization to work despite it.

**Stop:** issue closed or merged, or acceptance criteria already implemented → `ALREADY IMPLEMENTED` with the evidence, routed to verification or publication.

**Done when:** selection mode, ordering evidence, target, tracker repository, acceptance criteria, blocker states, and existing-work status are explicit. `@Implement` receives this choice and works no other ticket.

## 2. Read the ground

Read: the applicable `AGENTS.md` files, tracker guidance, domain docs, decision records, testing guidance.

Inspect ahead of any local Git change: current branch, `git status`, every remote URL, the default branch, `git worktree list --porcelain`.

Every existing dirty worktree is user-owned — its files, index, branch, and HEAD stay as they are.

**Done when:** instructions, tracker repository, publication repository, candidate code remote, default branches, and all worktree states are known.

## 3. Prove remote parity

```bash
git fetch --prune <remote>
```

Fetch the publication remote and any documented code mirror. Record:

| Value | Of |
|---|---|
| identity, default-branch commit, root-tree SHA | tracker and publication repository |
| URL, identity, fetched default-branch commit, root-tree SHA | local code remote |
| path of the document mapping a different remote or mirror | where identities differ |

| Case | Parity requires |
|---|---|
| same repository | identical commit SHAs |
| documented mirror rewriting commit IDs | identical root-tree SHAs |

Similar histories, overlapping files, newer timestamps, and an issue-specific local commit fall short of parity. A tracker connector may establish the tracker head where shell authentication is unavailable; it leaves an unrelated local remote non-canonical.

**Stop:** divergent SHAs or trees → `REMOTE MISMATCH` with both identities and both exact values, ahead of any worktree creation.

**Stop:** authentication, network access, mapping, ref resolution, or tree comparison prevents the proof.

**Done when:** both heads and trees are recorded and parity is proven.

## 4. Create or reuse the issue worktree

```bash
scripts/prepare-worktree.sh <owner/repo> <issue-number>
```

It derives the names, proves parity, creates the worktree from the exact fetched SHA, and prints the verification block.

| Exit | Means |
|---|---|
| 0 | the worktree is ready |
| 1 | the worktree was created and is not clean |
| 2 | a prerequisite is missing, or the repository is unreachable |
| 3 | the remotes diverge |
| 4 | work already exists |
| 5 | the issue is unreadable, or its state is other than open |

The script creates; it never reuses. Exit `4` hands the decision back to the table below, which is where reuse is judged.

Naming follows a convention a current branch or worktree already evidences. Absent that:

| Name | Rule |
|---|---|
| slug | ticket title, lowercased, transliterated to ASCII, each run of other characters replaced by one hyphen, trimmed to whole words within 40 characters |
| branch | `issue/<number>-<slug>` |
| worktree | `<parent of the primary checkout>/<primary checkout name>-worktrees/issue-<number>-<slug>` |

| State | Action |
|---|---|
| untouched | create branch and worktree from the exact fetched publication-default SHA |
| documented mirror rewriting commit IDs | use its fetched default commit once root-tree equality is proven and recorded |
| existing remote issue branch or pull request | create or reuse a clean worktree for that branch, fast-forwarding only where Git proves the update is one |
| existing issue worktree | reuse where ticket identity is certain and `git status --short` is empty |
| issue-specific commits or edits | another session's work — resume on explicit request and safe state, otherwise `EXISTING WORK FOUND` with branch, worktree, pull request, commit, and dirty-state evidence |

Local-only commits are preserved.

**Stop:** divergence, ambiguous unpublished work, a dirty issue worktree, or a branch checked out somewhere unexpected — report the exact condition.

Verify after creation or reuse: absolute worktree path, checked-out branch, HEAD SHA, publication-default SHA, code-remote-default SHA, upstream, clean status.

**Done when:** one isolated, clean, ticket-specific worktree is ready and every unrelated worktree is unchanged.

## 5. Establish the baseline

Discover the repository's setup, lint, typecheck, test, and build commands from its instructions and configuration, and use those exact names. Perform only documented, non-interactive setup. Run every discovered command, so the baseline covers what the publication and merge gates check later.

Record each command and its outcome, then verify `git status --short` again.

| Red because | Action |
|---|---|
| setup changed tracked files or broke the tree | stop, report the exact files or failure, leave them in place |
| the untouched tree already fails | record as pre-existing, name the command, mark it unusable as a regression oracle — preparation continues |
| a prerequisite is unavailable | mark unresolved |

**Done when:** the baseline result and the final clean status are evidenced.

## 6. Return

Every line below is a field. A table rendering keeps every one of them as a row.

```text
STATUS: <READY FOR @Implement | EXISTING WORK FOUND | ALREADY IMPLEMENTED | REMOTE MISMATCH | BLOCKED>
Bottleneck: <the passed-over higher-ranked ticket and why, or none>
Target: <issue number, title, URL or path>
Selection: <explicit | conversational | automatic; ordering evidence>
Tracker repository: <owner/name, default head and tree>
Publication repository: <owner/name, default head and tree>
Code remote: <name, URL or identity, default head and tree>
Mirror parity: <same repository, or documentation path plus exact tree proof>
Worktree: <absolute path>
Branch: <branch and upstream>
Fresh base: <publication remote default @ SHA; mirrored local SHA where applicable>
Current HEAD: <SHA>
Existing PR: <#N and URL, or none>
Blockers: <all resolved, or exact stop reason>
Acceptance criteria: <complete compact list>
Relevant docs: <paths and links>
Test seam: <agreed or best-supported seam; uncertainty labelled>
Baseline: <every command and outcome; each pre-existing failure and the oracle it disqualifies>
Constraints: <repository rules and known risks>
Next: <one safe next action; @Implement only for READY>
```

The prepared worktree is the active directory for later work in this chat. Verified facts and inferences stay labelled apart.
