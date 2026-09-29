import assert from 'node:assert/strict'
import { execFile, spawn } from 'node:child_process'
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(fileURLToPath(import.meta.url), '../..')
const launcher = join(repoRoot, 'scripts/workbench.mjs')
const provider = join(repoRoot, 'fixtures/providers/generic')
const secondProvider = join(repoRoot, 'fixtures/providers/second')

function runWorkbench(args, env = {}) {
  return new Promise((done) => execFile(process.execPath, [launcher, ...args], {
    cwd: repoRoot,
    env: { ...process.env, ...env },
  }, (error, stdout, stderr) => done({ code: error?.code ?? 0, stdout, stderr })))
}

function startWorkbench(args, env = {}) {
  return spawn(process.execPath, [launcher, ...args], {
    cwd: repoRoot,
    env: { ...process.env, ...env },
  })
}

async function waitFor(condition, message) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (await condition())
      return
    await new Promise((resolve) => setTimeout(resolve, 25))
  }
  throw new Error(message)
}

test('requires an explicit provider and ignores qsm-shell defaults', async () => {
  const missing = await runWorkbench(['--check'])
  assert.equal(missing.code, 1)
  assert.match(missing.stderr, /provider root must be supplied/)

  const ignoredShell = await runWorkbench(['--check'], { QSM_SHELL_ROOT: '/tmp/does-not-matter' })
  assert.equal(ignoredShell.code, 1)
  assert.doesNotMatch(ignoredShell.stderr, /qsm-shell/)
})

test('validates selected provider stories and a second provider', async () => {
  const first = await runWorkbench(['--check', '--provider', provider])
  assert.equal(first.code, 0, first.stderr)
  assert.match(first.stdout, /validated 1 stories/)

  const second = await runWorkbench(['--check'], { QSM_WORKBENCH_PROVIDER_ROOT: secondProvider })
  assert.equal(second.code, 0, second.stderr)
  assert.match(second.stdout, /validated 1 stories/)
})

test('launch exports provider identity, adapter, catalog, descriptor, and starters', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-workbench-launch-'))
  const logPath = join(dir, 'launch.json')
  const quickshell = join(dir, 'fake-quickshell.mjs')
  await writeFile(quickshell, [
    '#!/usr/bin/env node',
    'import { writeFileSync } from "node:fs"',
    `writeFileSync(${JSON.stringify(logPath)}, JSON.stringify({ argv: process.argv.slice(2), providerRoot: process.env.QSM_WORKBENCH_PROVIDER_ROOT, providerDir: process.env.QSM_WORKBENCH_PROVIDER_DIR, providerId: process.env.QSM_WORKBENCH_PROVIDER_ID, adapter: process.env.QSM_WORKBENCH_PROVIDER_ADAPTER, registryPath: process.env.QSM_WORKBENCH_REGISTRY_PATH, registry: process.env.QSM_WORKBENCH_REGISTRY, compositionTypes: process.env.QSM_WORKBENCH_COMPOSITION_TYPES, starters: process.env.QSM_WORKBENCH_COMPOSITION_STARTERS, qmlImportPath: process.env.QML_IMPORT_PATH }))`,
  ].join('\n'), { mode: 0o755 })

  const result = await runWorkbench(['text-input', '--provider', provider], { QSM_QUICKSHELL_BIN: quickshell })
  assert.equal(result.code, 0, result.stderr)
  const launch = JSON.parse(await readFile(logPath, 'utf8'))
  assert.deepEqual(launch.argv, ['--path', join(repoRoot, 'qml/shell.qml')])
  assert.equal(launch.providerId, 'generic-provider')
  assert.equal(launch.providerDir, provider)
  assert.match(launch.providerRoot, /^file:/)
  assert.match(launch.adapter, /Adapter\.qml$/)
  assert.equal(launch.registryPath, join(provider, 'workbench/stories.json'))
  assert.equal(JSON.parse(launch.registry)['text-input'].component, 'text-input')
  assert.equal(JSON.parse(launch.compositionTypes).types['text-field'].actions[0], 'clear')
  assert.deepEqual(JSON.parse(launch.starters).map((doc) => doc.key), ['text-field-matrix', 'menu-form', 'shell-border-rollout'])
  assert.match(launch.qmlImportPath, /fixtures\/providers\/generic\/qml:/)
  assert.match(launch.qmlImportPath, /qsm-workbench\/qml$/)
})

test('launch uses a provider-owned shell entry when present', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-workbench-entry-'))
  const providerRoot = join(dir, 'provider')
  const workbench = join(providerRoot, 'workbench')
  const qml = join(providerRoot, 'qml')
  const logPath = join(dir, 'launch.json')
  const quickshell = join(dir, 'fake-quickshell.mjs')
  await mkdir(workbench, { recursive: true })
  await mkdir(qml, { recursive: true })
  await writeFile(join(workbench, 'provider.json'), JSON.stringify({ version: 1, id: 'entry-provider', capabilities: ['stories'] }))
  await writeFile(join(workbench, 'Adapter.qml'), 'import QtQuick\nItem {}\n')
  await writeFile(join(workbench, 'shell.qml'), 'import Quickshell\nShellRoot {}\n')
  await writeFile(join(workbench, 'stories.json'), JSON.stringify({ version: 1, stories: { probe: { component: 'probe', variant: 'default', viewport: [640, 480] } } }))
  await writeFile(quickshell, [
    '#!/usr/bin/env node',
    'import { writeFileSync } from "node:fs"',
    `writeFileSync(${JSON.stringify(logPath)}, JSON.stringify({ argv: process.argv.slice(2) }))`,
  ].join('\n'), { mode: 0o755 })

  const result = await runWorkbench(['probe', '--provider', providerRoot], { QSM_QUICKSHELL_BIN: quickshell })
  assert.equal(result.code, 0, result.stderr)
  const launch = JSON.parse(await readFile(logPath, 'utf8'))
  assert.deepEqual(launch.argv, ['--path', join(workbench, 'shell.qml')])
})

test('flow launch resolves target through provider stories', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-workbench-flow-'))
  const flowPath = join(dir, 'story-flow.json')
  await writeFile(flowPath, JSON.stringify({ version: 1, key: 'story-flow', target: { story: 'text-input' }, steps: [{ type: 'expect', observable: 'text', equals: '' }] }))
  const logPath = join(dir, 'launch-flow.json')
  const quickshell = join(dir, 'fake-quickshell-flow.mjs')
  await writeFile(quickshell, [
    '#!/usr/bin/env node',
    'import { writeFileSync } from "node:fs"',
    `writeFileSync(${JSON.stringify(logPath)}, JSON.stringify({ initialStory: process.env.QSM_WORKBENCH_INITIAL_STORY, flowPath: process.env.QSM_WORKBENCH_FLOW_PATH }))`,
  ].join('\n'), { mode: 0o755 })
  const result = await runWorkbench(['--flow', flowPath, '--provider', provider], { QSM_QUICKSHELL_BIN: quickshell })
  assert.equal(result.code, 0, result.stderr)
  const launch = JSON.parse(await readFile(logPath, 'utf8'))
  assert.equal(launch.initialStory, 'text-input')
  assert.equal(launch.flowPath, flowPath)
})

test('replaces the prior provider Workbench process', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-workbench-lease-'))
  const logPath = join(dir, 'launches.jsonl')
  const quickshell = join(dir, 'fake-quickshell.mjs')
  await writeFile(quickshell, [
    '#!/usr/bin/env node',
    'import { appendFileSync } from "node:fs"',
    `appendFileSync(${JSON.stringify(logPath)}, JSON.stringify({ pid: process.pid, key: process.env.QSM_WORKBENCH_INITIAL_STORY }) + "\\n")`,
    'process.on("SIGTERM", () => process.exit(0))',
    'setInterval(() => {}, 1000)',
  ].join('\n'), { mode: 0o755 })
  const env = { QSM_QUICKSHELL_BIN: quickshell, QSM_WORKBENCH_LEASE_DIR: dir }
  const first = startWorkbench(['text-input', '--provider', provider], env)
  try {
    await waitFor(async () => {
      try { return (await readFile(logPath, 'utf8')).trim().split('\n').length === 1 } catch { return false }
    }, 'first workbench did not launch')
    const second = startWorkbench(['text-input', '--provider', provider], env)
    try {
      await waitFor(async () => {
        try { return (await readFile(logPath, 'utf8')).trim().split('\n').length === 2 } catch { return false }
      }, 'replacement workbench did not launch')
      await waitFor(() => first.exitCode !== null, 'prior workbench did not exit')
    } finally {
      second.kill('SIGTERM')
      await waitFor(() => second.exitCode !== null, 'replacement workbench did not exit')
    }
  } finally {
    if (first.exitCode === null)
      first.kill('SIGTERM')
  }
})

test('Workbench.qml has no shell/previews fallback and uses provider tasks', async () => {
  const qml = await readFile(join(repoRoot, 'qml/Workbench.qml'), 'utf8')
  assert.doesNotMatch(qml, /shellRoot|shellDir|previews\/Preview|previews\/units|openShellPath/)
  assert.match(qml, /QSM_WORKBENCH_PROVIDER_ID/)
  assert.match(qml, /root\.startTask\("story-capture"/)
})
