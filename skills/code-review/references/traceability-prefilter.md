# Requirement-ID coverage — the 0-token prefilter

Read this when `code-review`'s "Requirement-ID coverage" step applies (that
is, whenever Gate 5 is not already ruled out as docs/config-only). It moved
out of `SKILL.md` when the deep-review prefilter was added in 0.5.0 and the
skill hit its 250-line limit — the mechanism itself is unchanged.

Before spawning `code-reviewer`, compute Gate 5 criterion 1's answer by
`grep` instead of handing the agent a spec to read cold — the same
cost-optimization logic as the trivial-diff and Gate-6 prefilters in
`opsx-apply-git`, and the same logic as the risk prefilter that decides
whether `deep-reviewer` runs at all:

```bash
change="<change-slug>"
proposal="openspec/changes/$change/proposal.md"
ids_file=$(mktemp)
grep -ohE '\b(FR|NFR)-[0-9]+\b' "$proposal" 2>/dev/null | sort -u > "$ids_file"
if [ ! -s "$ids_file" ]; then
  echo "traceability unavailable: no FR-/NFR- identifiers in $proposal"
else
  uncovered=""
  while IFS= read -r id; do
    grep -rlE "implements $id of $change([^A-Za-z0-9-]|\$)" \
      --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=openspec \
      . >/dev/null 2>&1 || uncovered="$uncovered $id"
  done < "$ids_file"
  rm -f "$ids_file"
  if [ -z "$uncovered" ]; then
    echo "all requirement IDs covered"
  else
    echo "uncovered requirement IDs:$uncovered"
  fi
fi
```

The `([^A-Za-z0-9-]|$)` tail is load-bearing, not decoration: a plain
`grep -F "implements $id of $change"` matches as a substring, so change
`add-auth`'s `FR-1` would read as covered by a marker actually written for
change `add-auth-v2` — two different changes, the second only sharing the
first's slug as a prefix. Anchoring on what follows `$change` (end of line,
or any character that can't extend a kebab-case slug) rules that out; kebab
case has no ERE metacharacters, so `$change` and `$id` are safe to embed
literally.

The `while ... done < "$ids_file"` form (not a pipe into `while`) is
deliberate, matching this project's own `.claudeignore` hook: piping into
`while read` runs the loop in a subshell in some shells, silently discarding
`uncovered` once the loop exits, and a plain `for id in $ids` relies on
word-splitting that zsh does not perform on an unquoted expansion by default
— either mistake here reports every change as fully covered regardless of
what's actually missing.

## The three outputs are not interchangeable

Pass this output to `code-reviewer` as context alongside the diff, so it
reads a ready answer instead of independently deciding whether the spec is
covered. The three possible outputs must stay distinguishable all the way
into the agent's report: **a named list of uncovered identifiers**, **"all
requirement IDs covered"**, and **"traceability unavailable"** (this change's
`proposal.md` carries no identifiers at all).

Collapsing the third into the second is the exact silent failure this check
exists to avoid — a change with zero identifiers would otherwise grep zero,
subtract zero, and report full coverage.
