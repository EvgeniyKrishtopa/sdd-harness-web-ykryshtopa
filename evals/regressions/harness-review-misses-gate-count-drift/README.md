# Why this case exists

0.7.0 added a seventh review gate. The release note assumed two places
carried the gate count; six did, and four of them still said six — the
marketplace entry, the `CLAUDE.md` pointer block written into every
configured repo, `harness-stats`' per-gate metric, and `dead-code-report`'s
disclaimers. The drift was found by hand and closed in commit `60530c6`,
after it had shipped.

Nothing would have caught it. `harness-review` is the gate whose whole job
is stale claims in the harness's own documentation, and the only reason it
did not report this one is that nobody ran it on a diff where the count had
drifted.

The scaffold plants exactly that: a repository whose `.claude/docs/
review-gates.md` lists seven gates while the `CLAUDE.md` pointer block says
six, with the stale edit left uncommitted so it is what the run under
review actually changed.

This is the pattern every regression case follows — a defect that reached
production once, planted back into a throwaway repository so the gate that
missed it has to face it on every model change from now on.

The graders require each filename *next to the count it carries*, not the
bare filename. A run that reads both files and reports nothing would name
them both anyway, and a grader that such a run satisfies is a grader that
cannot fail.
