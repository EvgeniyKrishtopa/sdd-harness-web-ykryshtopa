# Blocked tasks — writing, honouring, and clearing the marker

Read this when a run is about to stop without resolving a task (Case A step
5's pause, or Case B step 2's pause that outlives the run), or when a scan
found an existing `<!-- blocked: ... -->` marker.

## Who writes it, and where

The marker is `<!-- blocked: <reason> -->`, written on the task's own
`- [ ]` line — never on the group's `##` heading, which only ever carries the
isolated/judgement-heavy classification. This skill is the one that writes
it, at the exact moment a run stops without resolving the task. `spec-review`
never writes it — that classification happens before implementation starts,
with no task yet to block.

## It is committed on its own

That edit is committed as a small standalone commit
(`docs: mark <group>.<task> blocked — <reason>`), the same way every group's
own checkbox flips are committed, never left as a bare uncommitted
working-tree diff. Leaving it uncommitted would undercut the entire point of
this marker: a reason for stopping that survives only in an uncommitted diff
is exactly as fragile as one that survives only in chat, the failure #U3
already fixed for `PROGRESS.md`.

Like any other commit made mid-batch before this run reaches §4, it isn't
pushed to `origin` until the run reaches (or, on resume, re-reaches) §4's
push step — that's an existing property of this whole flow, not something new
the marker introduces: an already-completed group sitting earlier in the same
paused batch is in exactly the same committed-but-unpushed state until then.
A session that resumes on this same branch (§1 step 1's leftover-branch
check) finds the marker either way.

## Why a block holds back the whole group

A group containing any blocked task is never eligible for Case A's autonomous
batch, regardless of its own isolated/judgement-heavy mark. This holds back
the *whole* group, including its own non-blocked tasks, not just the one task
carrying the marker — deliberately: an isolated group is trusted to run
unattended precisely because nothing in it needs a human mid-way, and a block
is evidence that trust didn't hold for this group, so none of it runs
unattended until a human clears it.

Case B can still pick up a blocked task deliberately, with a human already in
the loop, but should say so explicitly rather than silently working past the
marker.

## Clearing is never automatic

No timeout, no retry-and-forget. Only a human removing the marker from
`tasks.md`, or explicitly telling this skill to continue past it, clears it.
