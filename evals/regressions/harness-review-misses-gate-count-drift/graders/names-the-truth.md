---
type: regex
pattern: 'review-gates\.md'
match: contains
---
The finding must also name the file carrying the truth it drifted from. A
drift report that names only one of the two sides is not actionable — the
reader cannot tell which number is the wrong one.

This gate deliberately does not follow the CONFIRMED/PLAUSIBLE pause rule
(see `skills/harness-review/SKILL.md`), so this case grades on what the
finding names, not on a verdict word.
