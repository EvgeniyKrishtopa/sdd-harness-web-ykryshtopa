#!/usr/bin/env node
// progress.mjs -- the only writer of PROGRESS.md's structured sections.
//
// Skills used to rewrite PROGRESS.md as free text, and ad-hoc regex edits
// broke the numbered Next steps list (a step vanished, numbering skipped).
// This script owns the format instead: same arguments in, same file out,
// numbering always contiguous. Format: skills/init-harness/references/
// progress-template.md. Sections it doesn't know are kept as they are.
//
// Usage (run from the repo root):
//   node progress.mjs clock-out --change <slug|none> --branch <name>
//        --last-commit "<hash> — <subject>" --done "<groups|none>"
//        --in-progress "<group|none>" --blocked "<group/task — reason|none>"
//        [--next "<step>"]... --clock-in <ISO> --clock-out <ISO> [--file PROGRESS.md]
//   (a value starting with "-" is passed as --name=-value)
//   node progress.mjs pause --change <slug> --date <YYYY-MM-DD> --reason "<one line>" [--file ...]
//   node progress.mjs pr-target --parent <branch> --target <branch> --date <YYYY-MM-DD> [--file ...]
//
// clock-out rewrites Current change, Status and Next steps, removes the
// change's own line from Paused changes (working on it means it isn't
// paused), and appends one Session log line unless that exact line is
// already the last one -- so running the same clock-out twice changes
// nothing. pause adds one line under Paused changes, once. pr-target
// records where PRs go for a parent already merged into the main branch
// (opsx-apply-git §1 step 3): one line per parent, replaced on a new answer.

import { readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { parseArgs as parseCli } from 'node:util';

const ORDER = ['Current change', 'Status', 'Next steps', 'Paused changes', 'PR target', 'Session log'];

function fail(msg) {
  console.error(`progress.mjs: ${msg}`);
  process.exit(2);
}

const OPTIONS = Object.fromEntries(
  ['file', 'change', 'branch', 'last-commit', 'done', 'in-progress', 'blocked', 'clock-in', 'clock-out', 'date', 'reason', 'parent', 'target']
    .map((name) => [name, { type: 'string' }]),
);
OPTIONS.next = { type: 'string', multiple: true, default: [] };

// util.parseArgs rejects a flag whose value is missing ("--blocked --next x")
// instead of silently shifting every later pair. A value that itself starts
// with a dash is passed as --name=-value.
function parseArgs(argv) {
  try {
    const { values, positionals } = parseCli({ args: argv, options: OPTIONS, allowPositionals: true, strict: true });
    return { command: positionals[0], args: values };
  } catch (err) {
    fail(err.message.split('\n')[0]);
  }
}

// One physical line per value: the SessionStart hook reads these line by line.
function oneLine(value, name) {
  if (value === undefined || value === '') fail(`--${name} is required`);
  return String(value).replace(/\s*\n\s*/g, ' ').trim();
}

// Lines before the first "## " heading (the "# Progress" title, any note
// under it) are kept as the file's preamble, untouched.
function parse(text) {
  const sections = new Map();
  const preamble = [];
  let current = null;
  for (const line of text.split(/\r?\n/)) {
    const heading = line.match(/^## (.+?)\s*$/);
    if (heading) {
      current = heading[1];
      sections.set(current, []);
    } else if (current) {
      sections.get(current).push(line);
    } else {
      preamble.push(line);
    }
  }
  for (const [name, lines] of sections) sections.set(name, trimBlank(lines));
  return { preamble: trimBlank(preamble), sections };
}

function trimBlank(lines) {
  let start = 0;
  let end = lines.length;
  while (start < end && lines[start].trim() === '') start++;
  while (end > start && lines[end - 1].trim() === '') end--;
  return lines.slice(start, end);
}

function render({ preamble, sections }) {
  const names = [...ORDER.filter((n) => sections.has(n)), ...[...sections.keys()].filter((n) => !ORDER.includes(n))];
  const parts = [preamble.length ? preamble.join('\n') : '# Progress'];
  for (const name of names) {
    const lines = sections.get(name);
    // An empty Paused changes section is omitted, never left as a bare heading.
    if (name === 'Paused changes' && lines.length === 0) continue;
    parts.push(`## ${name}\n\n${lines.join('\n')}`);
  }
  return `${parts.join('\n\n')}\n`;
}

function load(file) {
  try {
    return parse(readFileSync(file, 'utf8'));
  } catch (err) {
    if (err.code === 'ENOENT') return { preamble: [], sections: new Map() };
    fail(`cannot read ${file}: ${err.message}`);
  }
}

// Write to a temporary file and rename, so an interrupted write never leaves
// half a PROGRESS.md; on failure, remove the temporary file too.
function save(file, doc) {
  const tmp = `${file}.tmp-${process.pid}`;
  try {
    writeFileSync(tmp, render(doc));
    renameSync(tmp, file);
  } catch (err) {
    try { unlinkSync(tmp); } catch { /* never created */ }
    fail(`cannot write ${file}: ${err.message}`);
  }
}

function pausedLineFor(change) {
  return (line) => line.startsWith(`- ${change} — `);
}

function clockOut(file, a) {
  const change = oneLine(a.change, 'change');
  const doc = load(file);
  const { sections } = doc;
  sections.set('Current change', [
    `- Change: ${change}`,
    `- Branch: ${oneLine(a.branch, 'branch')}`,
    `- Last commit: ${oneLine(a['last-commit'], 'last-commit')}`,
  ]);
  sections.set('Status', [
    `- Done: ${oneLine(a.done, 'done')}`,
    `- In progress: ${oneLine(a['in-progress'], 'in-progress')}`,
    `- Blocked: ${oneLine(a.blocked, 'blocked')}`,
  ]);
  const steps = a.next.map((s) => oneLine(s, 'next'));
  sections.set('Next steps', steps.length ? steps.map((s, i) => `${i + 1}. ${s}`) : ['None.']);
  if (sections.has('Paused changes')) {
    sections.set('Paused changes', sections.get('Paused changes').filter((l) => !pausedLineFor(change)(l)));
  }
  const session = `- Clock-in: ${oneLine(a['clock-in'], 'clock-in')} — Clock-out: ${oneLine(a['clock-out'], 'clock-out')}`;
  const log = sections.get('Session log') ?? [];
  if (log[log.length - 1] !== session) log.push(session);
  sections.set('Session log', log);
  save(file, doc);
  console.log(`progress.mjs: clock-out for ${change} written to ${file}`);
}

function pause(file, a) {
  const change = oneLine(a.change, 'change');
  const doc = load(file);
  const { sections } = doc;
  const paused = sections.get('Paused changes') ?? [];
  if (!paused.some(pausedLineFor(change))) {
    paused.push(`- ${change} — paused ${oneLine(a.date, 'date')}: ${oneLine(a.reason, 'reason')}`);
  }
  sections.set('Paused changes', paused);
  save(file, doc);
  console.log(`progress.mjs: ${change} paused in ${file}`);
}

function prTarget(file, a) {
  const parent = oneLine(a.parent, 'parent');
  const line = `- ${parent} → ${oneLine(a.target, 'target')} — chosen ${oneLine(a.date, 'date')}`;
  const doc = load(file);
  const kept = (doc.sections.get('PR target') ?? []).filter((l) => !l.startsWith(`- ${parent} → `));
  doc.sections.set('PR target', [...kept, line]);
  save(file, doc);
  console.log(`progress.mjs: PR target for ${parent} written to ${file}`);
}

const { command, args } = parseArgs(process.argv.slice(2));
const file = args.file ?? 'PROGRESS.md';
if (command === 'clock-out') clockOut(file, args);
else if (command === 'pause') pause(file, args);
else if (command === 'pr-target') prTarget(file, args);
else fail('usage: progress.mjs clock-out|pause|pr-target --key value ... (see the header of this file)');
