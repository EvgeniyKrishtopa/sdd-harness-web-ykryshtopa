# The deep review — when it runs, and why on that condition

`code-reviewer` has no security rules at all, and reads architecture only as
local reuse and simplification within the diff's neighbourhood. On a diff
that carries real risk that is not enough, so a second reviewer —
`deep-reviewer` (`agents/deep-reviewer.md`, rule codes `DR-01`…`DR-11`) —
runs on top of it.

It is a full extra delegation, usually on a larger model, so it only runs
when a deterministic shell check says the diff touches something worth the
run. Never "ask the model whether this looks risky": that spends exactly what
this check exists to save.

## The prefilter (0 tokens)

```bash
range="<parent>..HEAD"   # the same range Action step 1 resolves
risk=""
paths=$(git diff --name-only $range)
printf '%s\n' "$paths" | grep -qiE \
  'auth|login|logout|session|passwo?rd|token|permission|role|polic|payment|billing|checkout|invoice|migrat|schema|\.env|secret|credential|upload' \
  && risk="path"
if [ -z "$risk" ]; then
  git diff $range | grep '^+' | grep -qiE \
    'localStorage|sessionStorage|document\.cookie|dangerouslySetInnerHTML|innerHTML|eval\(|new Function\(|child_process|execSync|jwt|bcrypt|argon2|createHmac|randomBytes|cors\(|csrf|multipart|\.raw\(|SELECT .* FROM|INSERT INTO|DELETE FROM' \
    && risk="content"
fi
```

Path signals are checked before content signals, and the content grep looks
only at **added** lines — a risky pattern this diff *removes* is not a reason
to spend a review on it.

`$risk` empty → do not spawn `deep-reviewer`; log the skip and carry on with
Gate 4/5 exactly as before. `$risk` set → run it, and tell the agent which
signal fired (`path` or `content`) and on which files. That is the only clue
it has about why it was spawned, and it uses it to decide what to read
deeply beyond the diff hunks.

Both greps are intentionally broad on the recall side and narrow on the
precision side: a false fire costs one delegation, a miss costs the only
security review this plugin has. If a project finds a specific rule
consistently unhelpful it switches that rule off by code in
`disabledRules` — the prefilter itself is not the tuning surface.

## Why it is not tied to the change's route

The obvious cheaper design is "short route → never run it." Rejected, on two
grounds:

- Item 11 of this version wrote its own rule down: the short route skips
  **documents**, never a check on the result. This is a check on the result.
- The route is assigned by an estimate made in `opsx-propose-review`, before
  any code exists. One low estimate would then silently switch off the only
  security review in the plugin — and silently, because a skipped gate that
  was skipped "correctly" looks exactly like one that was never needed.

The saving would also be near zero in practice: a diff that trips the risk
prefilter is a diff touching a schema, a contract, or auth, and item 11 sends
exactly those down the full route anyway.

The risk prefilter is the single condition.

## Why a second agent rather than more rules in `code-reviewer`

Three reasons, in order of weight:

1. **It must be skippable.** Rules added to `code-reviewer` run on every
   diff, including the button-label edit. A separate agent is the only way to
   make a deep pass conditional at zero cost when it does not apply.
2. **Different verification bar.** `code-reviewer` confirms a finding by
   pointing at a broken behaviour. A security finding is confirmed by tracing
   an input someone controls to the damage — the code usually works exactly
   as written. Mixing the two bars in one agent blurs both.
3. **Different model.** The deep pass is worth a larger model precisely
   because it runs rarely; `code-reviewer` is worth a cheaper one precisely
   because it runs always. One agent cannot be both.
