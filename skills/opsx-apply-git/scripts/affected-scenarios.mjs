#!/usr/bin/env node
// Picks the recorded web-qa scenarios a change could have broken, for the
// replay before push on a change's last run (SKILL.md §4 step 3a,
// references/e2e-replay.md). 0 model tokens.
//
// Walks the import graph upward from every file the whole change touched to
// the route files that end up importing it, turns those into URL patterns,
// and keeps each scenario whose "// pages:" list hits one of them -- plus
// every scenario tagged with this change. Whenever the answer would be a
// guess, it says "run them all" instead, with the reason: a scenario run for
// nothing costs seconds, a skipped one that was broken costs a broken main.
//
// Imports are parsed and resolved with the project's own `typescript`
// package (ts.preProcessFile, ts.resolveModuleName with the project's
// tsconfig paths). TypeScript 7 no longer ships that JS API; such a project
// gets "import map failed" and every scenario runs.
//
// Usage: node affected-scenarios.mjs --base <rev> --dir <scenariosDir> --change <slug> [--project <dir>]
// Prints one JSON object: {scope, scopeReason, files}. scope is "affected"
// (files = the picked list, possibly empty) or "full" (files = every
// scenario; scopeReason says why). Exit 2 on a usage error only.
import { readFileSync, readdirSync, existsSync, statSync, realpathSync } from 'node:fs';
import { join, relative, resolve, dirname, basename, extname, sep } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const args = parseArgs(process.argv.slice(2));
if (!args.base || !args.dir || !args.change) {
  console.error('usage: affected-scenarios.mjs --base <rev> --dir <scenariosDir> --change <slug> [--project <dir>]');
  process.exit(2);
}
// Real path: ts.resolveModuleName returns real paths, and a symlinked
// checkout (macOS /tmp, /var) would otherwise never match its own files.
const projectDir = realpathSync(resolve(args.project || '.'));
const scenariosDir = resolve(projectDir, args.dir);

const CODE_EXT = /\.(?:[cm]?[jt]sx?)$/;
const SCENARIO_FILE = /\.(?:spec|test)\.[cm]?[jt]sx?$/;
const STYLE_FILE = /\.(?:css|scss|sass|less)$/;
const SKIP_DIRS = new Set(['node_modules', '.git', '.next', 'dist', 'build', 'out', 'coverage']);
// Segment files in app/ that render for their whole subtree, not one address.
const SUBTREE_FILES = new Set(['layout', 'template', 'loading', 'error', 'not-found', 'default', 'global-error']);
const SHARED_FILES = [
  /^(?:src\/)?app\/layout\.[cm]?[jt]sx?$/,
  /^(?:src\/)?(?:middleware|proxy)\.[cm]?[jt]s$/,
  /^(?:src\/)?pages\/_(?:app|document)\.[cm]?[jt]sx?$/,
  /^package\.json$/,
  /^(?:package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?)$/,
  /^next\.config\.[cm]?[jt]s$/,
  /^(?:ts|js)config\.json$/,
  /^playwright\.config\.[cm]?[jt]s$/,
];

console.log(JSON.stringify(pick()));

function pick() {
  const scenarios = listScenarios();
  const all = (scopeReason) => ({ scope: 'full', scopeReason, files: scenarios.map((s) => s.file) });

  let changed;
  try {
    changed = execFileSync('git', ['diff', '--name-only', `${args.base}..HEAD`], { cwd: projectDir, encoding: 'utf8' })
      .split('\n').filter(Boolean);
  } catch {
    return all('import map failed');
  }

  const appDir = ['app', 'src/app'].map((d) => join(projectDir, d)).find(isDir);
  const pagesDir = ['pages', 'src/pages'].map((d) => join(projectDir, d)).find(isDir);
  if (!appDir && !pagesDir) return all('no route structure');

  if (changed.some(isSharedFile)) return all('shared file changed');

  let routeFiles;
  try {
    routeFiles = touchedRouteFiles(changed.map((f) => join(projectDir, f)), appDir, pagesDir);
  } catch {
    return all('import map failed');
  }
  const patterns = routeFiles.map((f) => routePattern(f, appDir, pagesDir)).filter(Boolean);
  const changedSet = new Set(changed.map((f) => join(projectDir, f)));

  const files = scenarios
    .filter((s) => s.taggedWithChange || s.pages === null || changedSet.has(s.path)
      || s.pages.some((p) => patterns.some((re) => re.test(p))))
    .map((s) => s.file);
  return { scope: 'affected', scopeReason: '', files };
}

function isSharedFile(file) {
  if (STYLE_FILE.test(file) && !/\.module\.[^.]+$/.test(file)) return true;
  return SHARED_FILES.some((re) => re.test(file));
}

function listScenarios() {
  if (!isDir(scenariosDir)) return [];
  const tag = new RegExp(`${escapeRegExp(`@${args.change}`)}(?![\\w-])`);
  return walk(scenariosDir).filter((f) => SCENARIO_FILE.test(f)).sort().map((path) => {
    const text = readFileSync(path, 'utf8');
    const line = text.match(/^\s*\/\/\s*pages:(.*)$/m);
    return {
      path,
      file: relative(projectDir, path).split(sep).join('/'),
      taggedWithChange: tag.test(text),
      pages: line ? line[1].split(',').map(normalizePage).filter(Boolean) : null,
    };
  });
}

// Every route file whose import chain reaches one of the changed files,
// including a changed route file itself.
function touchedRouteFiles(changedPaths, appDir, pagesDir) {
  const ts = createRequire(join(projectDir, 'package.json'))('typescript');
  if (typeof ts.preProcessFile !== 'function' || typeof ts.resolveModuleName !== 'function') {
    throw new Error('typescript has no preProcessFile/resolveModuleName');
  }
  const options = compilerOptions(ts);

  const importers = new Map();
  for (const file of walk(projectDir).filter((f) => CODE_EXT.test(f))) {
    const { importedFiles } = ts.preProcessFile(readFileSync(file, 'utf8'), true, true);
    for (const { fileName } of importedFiles) {
      const target = resolveImport(ts, options, fileName, file);
      if (!target) continue;
      if (!importers.has(target)) importers.set(target, new Set());
      importers.get(target).add(file);
    }
  }

  const seen = new Set(changedPaths);
  const queue = [...changedPaths];
  while (queue.length) {
    for (const importer of importers.get(queue.shift()) || []) {
      if (!seen.has(importer)) { seen.add(importer); queue.push(importer); }
    }
  }
  return [...seen].filter((f) => isRouteFile(f, appDir, pagesDir));
}

function compilerOptions(ts) {
  const configPath = ['tsconfig.json', 'jsconfig.json'].map((f) => join(projectDir, f)).find(existsSync);
  let options = {};
  if (configPath) {
    const { config, error } = ts.readConfigFile(configPath, ts.sys.readFile);
    if (error) throw new Error('unreadable tsconfig');
    options = ts.parseJsonConfigFileContent(config, ts.sys, dirname(configPath)).options;
  }
  // Resolution only, nothing is compiled: .js files must resolve too.
  return { ...options, allowJs: true };
}

// An import's file inside the project, or null for a package or anything
// that doesn't exist. ts.resolveModuleName only finds code; a CSS module or
// another asset is resolved by hand, relative or through tsconfig paths.
function resolveImport(ts, options, spec, fromFile) {
  const { resolvedModule } = ts.resolveModuleName(spec, fromFile, options, ts.sys);
  if (resolvedModule) {
    const target = resolve(resolvedModule.resolvedFileName);
    return resolvedModule.isExternalLibraryImport || !insideProject(target) ? null : target;
  }
  const candidates = spec.startsWith('.') ? [resolve(dirname(fromFile), spec)] : pathsCandidates(options, spec);
  return candidates.find((c) => insideProject(c) && existsSync(c) && !isDir(c)) || null;
}

function pathsCandidates(options, spec) {
  const base = options.pathsBasePath || options.baseUrl || projectDir;
  const out = [];
  for (const [pattern, targets] of Object.entries(options.paths || {})) {
    const star = pattern.indexOf('*');
    let matched;
    if (star === -1) matched = pattern === spec ? '' : null;
    else {
      const prefix = pattern.slice(0, star);
      const suffix = pattern.slice(star + 1);
      matched = spec.startsWith(prefix) && spec.endsWith(suffix) && spec.length >= prefix.length + suffix.length
        ? spec.slice(prefix.length, spec.length - suffix.length) : null;
    }
    if (matched === null) continue;
    for (const t of targets) out.push(resolve(base, t.replace('*', matched)));
  }
  return out;
}

function isRouteFile(file, appDir, pagesDir) {
  if (!CODE_EXT.test(file)) return false;
  const name = basename(file, extname(file));
  if (appDir && file.startsWith(appDir + sep)) return name === 'page' || name === 'route' || SUBTREE_FILES.has(name);
  if (pagesDir && file.startsWith(pagesDir + sep)) return !name.startsWith('_');
  return false;
}

// Route file -> a RegExp over normalized paths ("/login", "/items/42").
// Route groups "(x)" and slots "@x" are not part of the address; a private
// "_x" folder has none. A group's own layout is matched as its whole parent
// subtree -- broader than the group, never narrower.
function routePattern(file, appDir, pagesDir) {
  const inApp = appDir && file.startsWith(appDir + sep);
  const rel = relative(inApp ? appDir : pagesDir, file).split(sep);
  const name = basename(rel.pop(), extname(file));
  const segments = rel.filter((s) => !(s.startsWith('(') && s.endsWith(')')) && !s.startsWith('@'))
    .map((s) => s.replace(/^(?:\(\.{1,3}\))+/, ''));
  if (segments.some((s) => s.startsWith('_'))) return null;
  if (!inApp && name !== 'index') segments.push(name);

  let body = '';
  for (const s of segments) {
    if (/^\[\[\.\.\..+\]\]$/.test(s)) body += '(?:/.*)?';
    else if (/^\[\.\.\..+\]$/.test(s)) body += '/.+';
    else if (/^\[.+\]$/.test(s)) body += '/[^/]+';
    else body += `/${escapeRegExp(s)}`;
  }
  const subtree = inApp && SUBTREE_FILES.has(name);
  if (subtree) return new RegExp(`^${body}(?:/.*)?$`);
  return new RegExp(`^${body || '/'}$`);
}

function normalizePage(page) {
  let p = page.trim().replace(/^[a-z]+:\/\/[^/]+/i, '').replace(/[?#].*$/, '');
  if (!p) return '';
  if (!p.startsWith('/')) p = `/${p}`;
  return p.length > 1 ? p.replace(/\/+$/, '') : p;
}

function walk(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) out.push(...walk(join(dir, entry.name)));
    } else if (entry.isFile()) out.push(join(dir, entry.name));
  }
  return out;
}

function insideProject(p) {
  return p.startsWith(projectDir + sep) && !p.split(sep).includes('node_modules');
}

function isDir(p) {
  try { return statSync(p).isDirectory(); } catch { return false; }
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--')) break;
    out[argv[i].slice(2)] = argv[i + 1];
  }
  return out;
}
