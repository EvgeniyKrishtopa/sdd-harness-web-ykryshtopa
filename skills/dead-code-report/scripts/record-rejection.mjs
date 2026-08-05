#!/usr/bin/env node
// Records one rejected dead-code finding into the project's knip config,
// with an explanation -- knip's own settings, not this plugin's, per
// harness-audit/v0.4.0-planned/05-design-rationale.txt, decision 3: knip
// already reads this file, so writing the exception there is free, and it
// keeps a second, competing "what to ignore" list from ever existing.
//
// This never re-serializes the whole file (which would silently drop every
// comment already written there by a previous run or a human) -- it locates
// the target array/object by scanning the original text and inserts the new
// entry in place, then validates the result before writing.
//
// knip.json/.knip.json are plain JSON and don't tolerate comments; knip's
// own docs recommend the JSONC form ("knip.jsonc") specifically for
// "configuration that requires comments or trailing commas". Since every
// entry this script writes carries an explanatory comment, a plain-JSON
// config is migrated to its .jsonc sibling the first time this script
// touches it. A JS/TS knip config, or a `knip` key embedded in
// package.json, is out of scope -- this script refuses cleanly rather than
// attempting to edit executable config.
//
// Usage: node record-rejection.mjs <category> <name> <reason> [projectDir]
//   category: file | dependency | binary | unresolved | export | type
import { readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

const [, , category, name, reason, projectDirArg] = process.argv;
const projectDir = projectDirArg || '.';

if (!category || !name || !reason) {
  console.error('usage: record-rejection.mjs <category> <name> <reason> [projectDir]');
  process.exit(2);
}

const ARRAY_KEYS = {
  file: 'ignoreFiles',
  dependency: 'ignoreDependencies',
  binary: 'ignoreBinaries',
  unresolved: 'ignoreUnresolved',
};
const ISSUE_TYPE = { export: 'exports', type: 'types' };

const isArrayCategory = category in ARRAY_KEYS;
const isIssueCategory = category in ISSUE_TYPE;
if (!isArrayCategory && !isIssueCategory) {
  console.error(
    `unknown category "${category}" -- expected one of: file, dependency, binary, unresolved, export, type`
  );
  process.exit(2);
}

const CANDIDATES = ['knip.json', 'knip.jsonc', '.knip.json', '.knip.jsonc'];
const UNSUPPORTED = ['knip.ts', 'knip.js', 'knip.config.ts', 'knip.config.js'];

let existingPath = null;
for (const c of CANDIDATES) {
  if (existsSync(join(projectDir, c))) {
    existingPath = c;
    break;
  }
}
if (!existingPath) {
  for (const c of UNSUPPORTED) {
    if (existsSync(join(projectDir, c))) {
      console.error(
        `this project's knip config is ${c} -- a JS/TS config file. This script only edits the JSON/JSONC forms; add the rejection there by hand:\n  category=${category} name=${JSON.stringify(name)} reason=${JSON.stringify(reason)}`
      );
      process.exit(2);
    }
  }
}

let text;
let targetPath;
if (existingPath) {
  text = readFileSync(join(projectDir, existingPath), 'utf8');
  targetPath = existingPath.endsWith('.jsonc')
    ? existingPath
    : existingPath.replace(/\.json$/, '.jsonc');
} else {
  targetPath = 'knip.jsonc';
  text = '{\n  "$schema": "https://unpkg.com/knip@6/schema-jsonc.json"\n}\n';
}

// --- minimal string/comment-aware scanner ---------------------------------

function skipStringOrComment(s, i) {
  const c = s[i];
  if (c === '"') {
    let j = i + 1;
    while (j < s.length) {
      if (s[j] === '\\') {
        j += 2;
        continue;
      }
      if (s[j] === '"') return j + 1;
      j++;
    }
    return j;
  }
  if (c === '/' && s[i + 1] === '/') {
    let j = i;
    while (j < s.length && s[j] !== '\n') j++;
    return j;
  }
  if (c === '/' && s[i + 1] === '*') {
    const end = s.indexOf('*/', i + 2);
    return end === -1 ? s.length : end + 2;
  }
  return -1;
}

// Returns [openIdx, closeIdx] of the balanced bracket starting at openIdx,
// respecting strings and comments so brackets inside either don't confuse
// the depth count.
function scanBalanced(s, openIdx) {
  const open = s[openIdx];
  const close = open === '{' ? '}' : ']';
  let depth = 0;
  for (let i = openIdx; i < s.length; i++) {
    const skip = skipStringOrComment(s, i);
    if (skip !== -1) {
      i = skip - 1;
      continue;
    }
    if (s[i] === open) depth++;
    else if (s[i] === close) {
      depth--;
      if (depth === 0) return [openIdx, i];
    }
  }
  throw new Error('unbalanced brackets in config file');
}

function findTopLevelKey(s, key) {
  const re = new RegExp('"' + escapeRe(key) + '"\\s*:\\s*([[{])');
  const m = re.exec(s);
  if (!m) return null;
  const openIdx = m.index + m[0].length - 1;
  const [start, end] = scanBalanced(s, openIdx);
  return { openIdx: start, closeIdx: end };
}

function escapeRe(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function stripComments(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const skip = skipStringOrComment(s, i);
    if (skip !== -1) {
      if (s[i] === '"') out += s.slice(i, skip);
      i = skip - 1;
      continue;
    }
    out += s[i];
  }
  return out;
}

// Every entry this script writes is self-terminating ("value, // reason"),
// so appending never needs to decide whether a comma is required -- it just
// needs to land after whatever is already there.
function insertIntoBracket(s, span, entryLine) {
  const [openIdx, closeIdx] = span;
  const inner = s.slice(openIdx + 1, closeIdx).replace(/\s+$/, '');
  // Match the indent of whatever's already the last line inside the
  // bracket, defaulting to a nested-under-a-top-level-key depth (4 spaces)
  // when the bracket is still empty.
  const lastLineIndent = /\n([ \t]*)\S[^\n]*$/.exec(inner);
  const indent = lastLineIndent ? lastLineIndent[1] : '    ';
  return s.slice(0, openIdx + 1) + inner + '\n' + indent + entryLine + '\n' + s.slice(closeIdx);
}

// Top-level keys are NOT self-terminating (a hand-authored file's last key
// may or may not have a trailing comma), so this is the one place a comma
// actually needs to be decided.
function insertTopLevelKey(s, keyLine) {
  const openIdx = s.indexOf('{');
  const [, closeIdx] = scanBalanced(s, openIdx);
  const inner = s.slice(openIdx + 1, closeIdx).replace(/\s+$/, '');
  const hasEntries = inner.trim().length > 0;
  const needsComma = hasEntries && !/,$/.test(inner);
  const insertion = (hasEntries ? (needsComma ? ',' : '') : '') + '\n  ' + keyLine;
  return s.slice(0, openIdx + 1) + inner + insertion + '\n' + s.slice(closeIdx);
}

const escName = JSON.stringify(name);
const escReason = reason.replace(/\r?\n/g, ' ').trim();

let updated;

if (isArrayCategory) {
  const key = ARRAY_KEYS[category];
  const found = findTopLevelKey(text, key);
  if (found) {
    const arrayText = text.slice(found.openIdx, found.closeIdx + 1);
    if (new RegExp('"' + escapeRe(name) + '"').test(arrayText)) {
      console.log(`already recorded: "${key}" already lists ${escName} in ${targetPath}`);
      process.exit(0);
    }
    updated = insertIntoBracket(text, [found.openIdx, found.closeIdx], `${escName}, // ${escReason}`);
  } else {
    updated = insertTopLevelKey(text, `"${key}": [\n    ${escName}, // ${escReason}\n  ]`);
  }
} else {
  const issueType = ISSUE_TYPE[category];
  const found = findTopLevelKey(text, 'ignoreIssues');
  if (found) {
    const objText = text.slice(found.openIdx, found.closeIdx + 1);
    const entryRe = new RegExp('"' + escapeRe(name) + '"\\s*:\\s*(\\[)');
    const entryMatch = entryRe.exec(objText);
    if (entryMatch) {
      const entryOpenIdx = found.openIdx + entryMatch.index + entryMatch[0].length - 1;
      const [eOpen, eClose] = scanBalanced(text, entryOpenIdx);
      const entryArrayText = text.slice(eOpen, eClose + 1);
      if (new RegExp('"' + issueType + '"').test(entryArrayText)) {
        console.log(
          `already recorded: ignoreIssues[${escName}] already includes "${issueType}" in ${targetPath}`
        );
        process.exit(0);
      }
      updated = insertIntoBracket(text, [eOpen, eClose], `"${issueType}", // ${escReason}`);
    } else {
      updated = insertIntoBracket(
        text,
        [found.openIdx, found.closeIdx],
        `${escName}: ["${issueType}"], // ${escReason}`
      );
    }
  } else {
    updated = insertTopLevelKey(
      text,
      `"ignoreIssues": {\n    ${escName}: ["${issueType}"], // ${escReason}\n  }`
    );
  }
}

// Validate before writing: never leave the config in a broken state. knip's
// JSONC mode accepts trailing commas, so the validator strips those too
// rather than rejecting output that knip itself would happily load.
try {
  const withoutComments = stripComments(updated);
  const withoutTrailingCommas = withoutComments.replace(/,(\s*[}\]])/g, '$1');
  JSON.parse(withoutTrailingCommas);
} catch (e) {
  console.error(`refusing to write ${targetPath}: result would not parse (${e.message})`);
  process.exit(2);
}

writeFileSync(join(projectDir, targetPath), updated);
if (existingPath && existingPath !== targetPath) {
  unlinkSync(join(projectDir, existingPath));
  console.log(
    `migrated ${existingPath} -> ${targetPath} (comments require the .jsonc form) and recorded the rejection`
  );
} else {
  console.log(`recorded rejection in ${targetPath}: ${category} ${escName} -- ${escReason}`);
}
