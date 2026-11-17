import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyPaths, commandsFor, githubScope, parseDiff } from './ci-scope.mjs';

test('content and OG-only changes never run native tests, builds or packaging', () => {
  const scope = classifyPaths(['README.md', 'docs/releases/0.1.99.md', 'site/index.html', 'site/assets/og.png', '.github/ISSUE_TEMPLATE/feedback.yml']);
  assert.equal(scope.app, false);
  assert.deepEqual(commandsFor(scope), []);
});

test('core-only test edits do not build the app; core contracts also compile their consumer', () => {
  assert.deepEqual(commandsFor(classifyPaths(['Tests/HowlerCoreTests/SSEParserTests.swift'])), [['make', 'test-core']]);
  assert.deepEqual(commandsFor(classifyPaths(['Sources/HowlerCore/SSEParser.swift'])), [['make', 'test-core'], ['swift', 'build', '--product', 'Howler']]);
});

test('native behavior keeps app checks; mixed core and app changes run the full suite once', () => {
  assert.deepEqual(commandsFor(classifyPaths(['Sources/Howler/ChatViewModel.swift'])), [['make', 'test-app']]);
  assert.deepEqual(commandsFor(classifyPaths(['Sources/HowlerCore/ChatClient.swift', 'Sources/Howler/PanelController.swift'])), [['make', 'test-all']]);
  assert.deepEqual(commandsFor(classifyPaths(['Sources/Howler/PanelController.swift', 'scripts/homebrew.sh'])), [['make', 'test-app'], ['make', 'test-tooling']]);
});

test('icon presentation does not require interaction tests', () => {
  assert.deepEqual(commandsFor(classifyPaths(['Sources/Howler/AppIconArt.swift'])), [['swift', 'build', '--product', 'Howler']]);
  assert.deepEqual(commandsFor(classifyPaths(['Resources/AppIcon.icns'])), []);
});

test('release tooling selects fixtures and only relevant packaging', () => {
  assert.deepEqual(commandsFor(classifyPaths(['scripts/homebrew.sh'])), [['make', 'test-tooling']]);
  assert.deepEqual(commandsFor(classifyPaths(['scripts/bundle.sh'])), [['make', 'test-tooling'], ['make', 'app']]);
  assert.deepEqual(commandsFor(classifyPaths(['scripts/dmg.sh'])), [['make', 'test-tooling'], ['make', 'dmg']]);
});

test('CI policy changes test policy; workflow edits also retain release fixtures', () => {
  assert.deepEqual(commandsFor(classifyPaths(['scripts/ci-scope.mjs'])), [['make', 'test-ci']]);
  assert.deepEqual(commandsFor(classifyPaths(['.github/workflows/build.yml'])), [['make', 'test-ci'], ['make', 'test-tooling']]);
  assert.deepEqual(commandsFor(classifyPaths(['Makefile'])), [['make', 'test-ci'], ['make', 'test-tooling']]);
  assert.deepEqual(commandsFor(classifyPaths(['scripts/test-core.sh'])), [['make', 'test-ci'], ['make', 'test-core']]);
});

test('dependency changes retain full tests and bundle checks; unknown inputs fail closed', () => {
  for (const path of ['Package.swift', 'Package.resolved']) {
    assert.deepEqual(commandsFor(classifyPaths([path])), [['make', 'test-all'], ['make', 'app']]);
  }
  for (const paths of [['Resources/Unknown.plist'], ['../site/README.md']]) {
    const commands = commandsFor(classifyPaths(paths));
    assert.ok(commands.some(c => c[1] === 'test-all'));
    assert.ok(commands.some(c => c[1] === 'dmg'));
  }
  assert.equal(classifyPaths([], { incomplete: true }).interaction, true);
});

test('rename and deletion detection retains both old and new impact', () => {
  const paths = parseDiff('R100\0Sources/HowlerCore/Old.swift\0docs/Old.swift\0D\0Sources/Howler/HotKey.swift\0');
  assert.equal(classifyPaths(paths).core, true);
  assert.equal(classifyPaths(paths).interaction, true);
  assert.throws(() => parseDiff('R100\0missing-new-name\0'));
});

test('PR uses merge base; main push uses before/after and skips website-only changes', () => {
  const calls = [];
  const read = (...args) => { calls.push(args); return ['site/main.js']; };
  const event = { pull_request: { base: { sha: 'base' }, head: { sha: 'head' } } };
  assert.equal(githubScope('pull_request', 'refs/pull/1/merge', event, read, () => 'ancestor').app, false);
  assert.deepEqual(calls[0], ['ancestor', 'head']);
  assert.equal(githubScope('push', 'refs/heads/main', { before: 'before', after: 'after' }, read).app, false);
  assert.deepEqual(calls[1], ['before', 'after']);
});

test('tag/manual runs and unavailable/empty diffs cannot skip release protection', () => {
  const broken = () => { throw new Error('unavailable'); };
  for (const [event, ref, payload, diff] of [
    ['push', 'refs/tags/v0.1.99', {}, broken], ['workflow_dispatch', 'refs/heads/main', {}, broken],
    ['push', 'refs/heads/main', { before: 'before' }, broken], ['push', 'refs/heads/main', { before: '0'.repeat(40) }, broken],
    ['push', 'refs/heads/main', { before: 'before', after: 'after' }, () => []],
  ]) assert.ok(commandsFor(githubScope(event, ref, payload, diff)).some(c => c[1] === 'test-all'));
});
