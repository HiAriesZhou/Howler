#!/usr/bin/env node
// Shared local/CI selection. Known content-only paths skip native work; unknowns fail closed.
import { appendFileSync, readFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const flags = ['core', 'interaction', 'tooling', 'compile', 'bundle', 'dmg', 'ci'];
const toolingTests = /^(?:Tests\/HowlerAppTests\/)(?:Homebrew|ReleaseSigning|ReleaseNotes|CaptureLinkBundle)Tests\.swift$/;

export function fullScope(reason) {
  return { ...Object.fromEntries(flags.map(key => [key, true])), full: true, app: true, reason };
}

function addPath(scope, path) {
  if (!path || path.startsWith('/') || path.split('/').includes('..')) return false;
  if (path.startsWith('site/') || path.startsWith('docs/') || path.endsWith('.md')
    || path.startsWith('.github/ISSUE_TEMPLATE/') || ['LICENSE', '.gitignore', 'Resources/AppIcon.icns'].includes(path)) return true;
  if (path === 'Sources/Howler/AppIconArt.swift') { scope.compile = true; return true; }
  if (path.startsWith('Sources/HowlerCore/')) { scope.core = true; scope.compile = true; return true; }
  if (path.startsWith('Tests/HowlerCoreTests/')) { scope.core = true; return true; }
  if (toolingTests.test(path)) { scope.tooling = true; return true; }
  if (path.startsWith('Sources/Howler/') || path.startsWith('Tests/HowlerAppTests/')) {
    scope.interaction = true; return true;
  }
  if (path.startsWith('scripts/ci-scope.')) { scope.ci = true; return true; }
  if (path === 'scripts/test-core.sh') { scope.core = true; scope.ci = true; return true; }
  if (path === 'Makefile') { scope.ci = true; scope.tooling = true; return true; }
  if (['Package.swift', 'Package.resolved'].includes(path)) {
    scope.core = true; scope.interaction = true; scope.tooling = true; scope.bundle = true; scope.full = true; return true;
  }
  if (['.github/workflows/build.yml', '.github/workflows/homebrew.yml'].includes(path)) {
    scope.ci = true; scope.tooling = true; return true;
  }
  if (/^scripts\/(?:bundle|dmg|notarize|icon|appcast|homebrew)\.sh$/.test(path) || path === 'app.config') {
    scope.tooling = true;
    scope.bundle ||= ['scripts/bundle.sh', 'scripts/dmg.sh', 'scripts/icon.sh', 'app.config'].includes(path);
    scope.dmg ||= path === 'scripts/dmg.sh';
    return true;
  }
  return false;
}

export function classifyPaths(paths, { force = false, incomplete = false } = {}) {
  if (force || incomplete) return fullScope(force ? 'tag or explicit full check' : 'incomplete change list');
  const scope = { ...Object.fromEntries(flags.map(key => [key, false])), full: false };
  for (const path of paths) {
    if (!addPath(scope, path)) return fullScope(`unclassified path: ${path}`);
  }
  // Interaction tests compile the app; tooling fixtures are a separate suite.
  scope.compile &&= !scope.interaction;
  return { ...scope, app: flags.some(key => key !== 'ci' && scope[key]), reason: paths.length ? 'changed paths' : 'no changes' };
}

export function parseDiff(raw) {
  const fields = raw.split('\0');
  if (fields.at(-1) === '') fields.pop();
  const paths = [];
  for (let i = 0; i < fields.length;) {
    const status = fields[i++];
    if (!/^(?:[ACDMRTUXB]|[RC]\d+)$/.test(status)) throw new Error(`Invalid diff status: ${status}`);
    const count = /^[RC]/.test(status) ? 2 : 1;
    if (i + count > fields.length) throw new Error('Incomplete diff record');
    paths.push(...fields.slice(i, i + count)); i += count;
  }
  return paths;
}

const git = (...args) => execFileSync('git', args, { encoding: 'utf8' });
const diff = (base, head) => parseDiff(git('diff', '--name-status', '-z', '--find-renames', base, ...(head ? [head] : []), '--'));

export function githubScope(eventName, ref, event, readDiff = diff, mergeBase = (a, b) => git('merge-base', a, b).trim()) {
  if (eventName === 'workflow_dispatch' || (eventName === 'push' && ref.startsWith('refs/tags/v'))) return fullScope('tag or explicit full check');
  try {
    let paths;
    if (eventName === 'pull_request') {
      const base = event.pull_request.base.sha, head = event.pull_request.head.sha;
      paths = readDiff(mergeBase(base, head), head);
    } else if (eventName === 'push' && event.before && !/^0+$/.test(event.before)) {
      paths = readDiff(event.before, event.after);
    } else return fullScope('unsupported event or missing base');
    return classifyPaths(paths, { incomplete: !paths.length });
  } catch { return fullScope('change detection failed'); }
}

function localScope(base) {
  if (!base || base.startsWith('-')) throw new Error('Invalid base ref');
  const ancestor = git('merge-base', base, 'HEAD').trim();
  const paths = [...diff(ancestor, 'HEAD'), ...diff('HEAD')];
  paths.push(...git('ls-files', '--others', '--exclude-standard', '-z').split('\0').filter(Boolean));
  return classifyPaths([...new Set(paths)]);
}

export function commandsFor(scope) {
  const commands = [];
  if (scope.ci) commands.push(['make', 'test-ci']);
  if (scope.full) commands.push(['make', 'test-all']);
  else if (scope.core && scope.interaction) {
    commands.push(['make', 'test-core-app']);
    if (scope.tooling) commands.push(['make', 'test-tooling']);
  }
  else {
    if (scope.core) commands.push(['make', 'test-core']);
    if (scope.interaction) commands.push(['make', 'test-app']);
    if (scope.tooling) commands.push(['make', 'test-tooling']);
  }
  if (scope.compile && !scope.bundle) commands.push(['swift', 'build', '--product', 'Howler']);
  if (scope.bundle) commands.push(['make', scope.dmg ? 'dmg' : 'app']);
  return commands;
}

function main(args) {
  if (args.includes('--help')) {
    console.log('ci-scope.mjs [--base REF] [--check] | --github\nDefault: print local diff scope; --check runs selected checks. --github emits Actions outputs.');
    return;
  }
  const github = args.includes('--github');
  const base = args.includes('--base') ? args[args.indexOf('--base') + 1] : 'origin/main';
  const scope = github
    ? githubScope(process.env.GITHUB_EVENT_NAME, process.env.GITHUB_REF ?? '', JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')))
    : localScope(base);
  console.log(JSON.stringify({ ...scope, commands: commandsFor(scope) }, null, 2));
  if (github) {
    const outputs = [...flags, 'app', 'full'].map(key => `${key}=${scope[key]}`).join('\n') + '\n';
    appendFileSync(process.env.GITHUB_OUTPUT, outputs);
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY,
      `### Verification scope\n\n${scope.reason}\n\n${[...flags, 'app'].map(key => `- ${key}: ${scope[key]}`).join('\n')}\n`);
  }
  if (args.includes('--check')) for (const [command, ...argv] of commandsFor(scope)) {
    const result = spawnSync(command, argv, { stdio: 'inherit' });
    if (result.error) throw result.error;
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main(process.argv.slice(2));
