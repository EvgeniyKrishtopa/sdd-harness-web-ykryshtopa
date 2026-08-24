---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?harness-review"'
min: 1
---
`harness-review` must fire: the diff under review is the harness's own
documentation, which is exactly this gate's declared scope.
