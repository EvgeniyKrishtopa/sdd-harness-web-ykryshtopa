# Known false-positive shapes

Static analysis (knip, the linter, the commented-code heuristic) cannot see
these. Every finding that matches one of these shapes starts in Group 2 or 3,
never Group 1, regardless of what step 3's string search finds — the string
search is one more safety net, not the only one.

- **Computed/dynamic import or require path** — `import(\`./pages/${slug}\`)`,
  `require(path.join(dir, name))`. The referenced file(s) never appear as a
  literal specifier anywhere, so knip cannot resolve them and reports them
  unused.
- **String-key lookup into an object**, e.g. `components[name]`,
  `handlers[action]`. The key that "uses" the export is data, often loaded
  from config or a database, not visible in source at all.
- **i18n / translation keys.** A key present in a locale file with no
  matching source reference is usually still rendered — through a helper
  that takes the key as a runtime string.
- **Feature flags.** Code gated behind a flag that's currently off looks
  unreferenced from the flag's default branch, but is live once the flag
  flips.
- **References that exist only in bundler/build config** — a Vite/webpack
  `resolve.alias`, a `tsconfig.json` `paths` entry, a Vitest/Jest `setupFiles`
  list. Knip's own project/entry patterns should normally cover these; when
  they don't (a hand-rolled config file knip doesn't parse), the reference is
  real but invisible to it.
- **A package's public interface via `package.json`'s `exports` field.**
  Anything reachable from a published `exports` map is used by consumers
  outside this repo, even with zero in-repo callers.
- **Side-effect-only imports** — polyfills, global stylesheets
  (`import "./reset.css"`), anything imported purely for what it does on
  load rather than what it exports. These show up as "unused" because
  nothing consumes their exports, but the import itself is the point.

If a finding matches one of these shapes, say so explicitly in the report
next to it — don't just silently move it a group down. The next run (or the
next reader) needs to know *why*, not just *that*.
