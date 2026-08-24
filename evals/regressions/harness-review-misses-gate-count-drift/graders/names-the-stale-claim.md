---
type: regex
pattern: 'CLAUDE\.md.{0,300}(\bsix\b|шесть)|(\bsix\b|шесть).{0,300}CLAUDE\.md'
flags: 'is'
match: contains
---
The finding must name the file carrying the stale claim *together with the
claim itself* — `CLAUDE.md` and the count it was left at.

Matching the bare filename is not enough: a run that reads both files, finds
nothing, and says "checked CLAUDE.md and review-gates.md, nothing to flag"
would satisfy that — which is precisely the silence this case exists to
catch.
