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
//   node progress.mjs pause --change <slug> --date <YYYY-MM-DD> --reason "<one line>" [--file ...]
//
// clock-out rewrites Current change, Status and Next steps, removes the
// change's own line from Paused changes (working on it means it isn't
// paused), and appends one Session log line unless that exact line is
// already the last one -- so running the same clock-out twice changes
// nothing. pause adds one line under Paused changes, once.

import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';

const ORDER = ['Current change', 'Status', 'Next steps', 'Paused changes', 'Session log'];

function fail(msg) {
  console.error(`progress.mjs: ${msg}`);
  process.exit(2);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const args = { next: [] };
  for (let i = 0; i < rest.length; i += 2) {
    const key = rest[i];
    const value = rest[i + 1];
    if (!key?.startsWith('--') || value === undefined) fail(`expected --key value pairs, got "${key}"`);
    const name = key.slice(2);
    if (name === 'next') args.next.push(value);
    else args[name] = value;
  }
  return { command, args };
}

// One physical line per value: the SessionStart hook reads these line by line.
function oneLine(value, name) {
  if (value === undefined || value === '') fail(`--${name} is required`);
  return String(value).replace(/\s*\n\s*/g, ' ').trim();
}

function parse(text) {
  const sections = new Map();
  let current = null;
  for (const line of text.split('\n')) {
    const heading = line.match(/^## (.+?)\s*$/);
    if (heading) {
      current = heading[1];
      sections.set(current, []);
    } else if (current) {
      sections.get(current).push(line);
    }
  }
  for (const [name, lines] of sections) sections.set(name, trimBlank(lines));
  return sections;
}

function trimBlank(lines) {
  let start = 0;
  let end = lines.length;
  while (start < end && lines[start].trim() === '') start++;
  while (end > start && lines[end - 1].trim() === '') end--;
  return lines.slice(start, end);
}

function render(sections) {
  const names = [...ORDER.filter((n) => sections.has(n)), ...[...sections.keys()].filter((n) => !ORDER.includes(n))];
  const parts = ['# Progress'];
  for (const name of names) {
    const lines = sections.get(name);
    // An empty Paused changes section is omitted, never left as a bare heading.
    if (name === 'Paused changes' && lines.length === 0) continue;
    parts.push(`## ${name}\n\n${lines.join('\n')}`);
  }
  return `${parts.join('\n\n')}\n`;
}

function load(file) {
  return existsSync(file) ? parse(readFileSync(file, 'utf8')) : new Map();
}

function save(file, sections) {
  const tmp = `${file}.tmp-${process.pid}`;
  writeFileSync(tmp, render(sections));
  renameSync(tmp, file);
}

function pausedLineFor(change) {
  return (line) => line.startsWith(`- ${change} — `);
}

function clockOut(file, a) {
  const change = oneLine(a.change, 'change');
  const sections = load(file);
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
  const steps = a.next.map((s) => oneLine(s, 'next')).filter(Boolean);
  sections.set('Next steps', steps.length ? steps.map((s, i) => `${i + 1}. ${s}`) : ['None.']);
  if (sections.has('Paused changes')) {
    sections.set('Paused changes', sections.get('Paused changes').filter((l) => !pausedLineFor(change)(l)));
  }
  const session = `- Clock-in: ${oneLine(a['clock-in'], 'clock-in')} — Clock-out: ${oneLine(a['clock-out'], 'clock-out')}`;
  const log = sections.get('Session log') ?? [];
  if (log[log.length - 1] !== session) log.push(session);
  sections.set('Session log', log);
  save(file, sections);
}

function pause(file, a) {
  const change = oneLine(a.change, 'change');
  const sections = load(file);
  const paused = sections.get('Paused changes') ?? [];
  if (!paused.some(pausedLineFor(change))) {
    paused.push(`- ${change} — paused ${oneLine(a.date, 'date')}: ${oneLine(a.reason, 'reason')}`);
  }
  sections.set('Paused changes', paused);
  save(file, sections);
}

const { command, args } = parseArgs(process.argv.slice(2));
const file = args.file ?? 'PROGRESS.md';
if (command === 'clock-out') clockOut(file, args);
else if (command === 'pause') pause(file, args);
else fail('usage: progress.mjs clock-out|pause --key value ... (see the header of this file)');
