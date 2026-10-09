#!/usr/bin/env node
// deps-audit.mjs -- the dependency audit .husky/pre-push runs, with an
// allowlist for known vulnerabilities the project has decided to live with
// for a while. Written by the sdd-harness init-harness skill; the project
// owns it from then on.
//
// Usage (from the repo root): node scripts/deps-audit.mjs <audit command with its JSON flag>
//   node scripts/deps-audit.mjs npm audit --json
//   node scripts/deps-audit.mjs pnpm audit --json
//   node scripts/deps-audit.mjs yarn audit --json        (yarn 1)
//   node scripts/deps-audit.mjs yarn npm audit --json    (yarn 2+)
//
// Fails (exit 1) on any high or critical advisory that has no live entry in
// scripts/audit-allowlist.json. An entry lives until the end of its
// "expires" day (UTC); after that its advisory fails the audit again.
// Entries whose advisory is no longer reported are listed so they can be
// removed. A report the script can't read fails too: an audit that didn't
// run is not a passed audit.
//
// scripts/audit-allowlist.json:
//   [{ "id": "GHSA-xxxx-xxxx-xxxx", "reason": "why it's acceptable for now", "expires": "YYYY-MM-DD" }]

import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const ALLOWLIST = 'scripts/audit-allowlist.json';
const BLOCKING = new Set(['high', 'critical']);
const LEVELS = new Set(['info', 'low', 'moderate', 'high', 'critical']);
const GHSA = /GHSA(?:-[0-9a-z]{4}){3}/i;

function fail(msg) {
  console.error(`deps-audit: ${msg}`);
  process.exit(1);
}

function readAllowlist() {
  let entries;
  try {
    entries = JSON.parse(readFileSync(ALLOWLIST, 'utf8'));
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    fail(`cannot read ${ALLOWLIST}: ${err.message}`);
  }
  if (!Array.isArray(entries)) fail(`${ALLOWLIST} must be a JSON array`);
  for (const e of entries) {
    const ok = e && GHSA.test(e.id ?? '') && typeof e.reason === 'string' && e.reason.trim()
      && /^\d{4}-\d{2}-\d{2}$/.test(e.expires ?? '');
    if (!ok) fail(`${ALLOWLIST}: every entry needs "id" (GHSA-...), "reason" and "expires" (YYYY-MM-DD): ${JSON.stringify(e)}`);
  }
  return entries;
}

// npm, pnpm and both yarns shape their JSON differently, but every one puts
// an advisory's severity and its GHSA link (or id) in the same object. Walk
// everything and keep each object that has both.
function collect(value, found) {
  if (Array.isArray(value)) {
    for (const v of value) collect(v, found);
    return;
  }
  if (!value || typeof value !== 'object') return;
  const severity = String(value.severity ?? value.Severity ?? '').toLowerCase();
  if (LEVELS.has(severity)) {
    const id = Object.values(value).find((v) => typeof v === 'string' && GHSA.test(v))?.match(GHSA)[0].toUpperCase();
    if (id) {
      const name = value.module_name ?? value.name ?? value.dependency ?? '';
      const prev = found.get(id);
      if (!prev || (BLOCKING.has(severity) && !BLOCKING.has(prev.severity))) found.set(id, { severity, name });
    }
  }
  for (const v of Object.values(value)) collect(v, found);
}

// One JSON document (npm, pnpm) or one per line (yarn): try both.
function parseReport(text) {
  const docs = [];
  try {
    docs.push(JSON.parse(text));
  } catch {
    for (const line of text.split(/\r?\n/)) {
      if (!line.trim()) continue;
      try { docs.push(JSON.parse(line)); } catch { /* a progress or warning line */ }
    }
  }
  return docs;
}

const command = process.argv.slice(2);
if (command.length === 0) fail('usage: node scripts/deps-audit.mjs <audit command> --json');

const allowlist = readAllowlist();
const run = spawnSync(command[0], command.slice(1), { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
if (run.error) fail(`cannot run ${command.join(' ')}: ${run.error.message}`);

const docs = parseReport(run.stdout ?? '');
const found = new Map();
collect(docs, found);
if (docs.length === 0 || (run.status !== 0 && found.size === 0)) {
  fail(`${command.join(' ')} exited ${run.status} and its report could not be read:\n${(run.stderr || run.stdout || '').trim().slice(0, 2000)}`);
}

const today = new Date().toISOString().slice(0, 10);
const byId = new Map(allowlist.map((e) => [e.id.toUpperCase(), e]));
let blocked = 0;
for (const [id, { severity, name }] of found) {
  if (!BLOCKING.has(severity)) continue;
  const entry = byId.get(id);
  const what = `${id} (${severity}${name ? `, ${name}` : ''})`;
  if (!entry) {
    console.error(`deps-audit: ${what} — not in ${ALLOWLIST}`);
    blocked++;
  } else if (entry.expires < today) {
    console.error(`deps-audit: ${what} — allowlist entry expired ${entry.expires} (${entry.reason}); it fails the audit again`);
    blocked++;
  } else {
    console.log(`deps-audit: ${what} — allowed until ${entry.expires}: ${entry.reason}`);
  }
}
for (const [id, entry] of byId) {
  if (!found.has(id)) console.log(`deps-audit: ${id} is no longer reported — remove its entry from ${ALLOWLIST} (was: ${entry.reason})`);
}

if (blocked > 0) fail(`${blocked} high or critical advisor${blocked === 1 ? "y blocks" : "ies block"} the push`);
console.log('deps-audit: no high or critical advisory blocks the push');
