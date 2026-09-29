import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import { mkdtemp, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(fileURLToPath(import.meta.url), '../..')
const runner = join(repoRoot, 'scripts/task-runner.mjs')
const provider = join(repoRoot, 'fixtures/providers/generic')

function runRunner(args, env = {}) {
  return new Promise((done) => execFile(process.execPath, [runner, ...args], {
    cwd: repoRoot,
    env: { ...process.env, QSM_WORKBENCH_PROVIDER_ROOT: provider, ...env },
  }, (error, stdout, stderr) => done({ code: error?.code ?? 0, stdout, stderr })))
}

test('runs only manifest-declared named tasks', async () => {
  const result = await runRunner(['validate'])
  assert.equal(result.code, 0, result.stderr)
  assert.match(result.stdout, /validated 1 stories/)

  const unknown = await runRunner(['unit', 'TextField'])
  assert.equal(unknown.code, 1)
  assert.match(unknown.stderr, /unknown provider task 'unit'/)
})

test('validates composition task input before spawning implementation', async () => {
  const ok = await runRunner(['composition-check', 'compositions/examples/text-field-matrix.json'])
  assert.equal(ok.code, 0, ok.stderr)
  assert.match(ok.stdout, /composition ok:/)

  const dir = await mkdtemp(join(tmpdir(), 'qsm-task-runner-'))
  const invalid = join(dir, 'invalid.json')
  await writeFile(invalid, '{"version":2}\n')
  const bad = await runRunner(['composition-check', invalid])
  assert.equal(bad.code, 1)
  assert.match(bad.stderr, /invalid composition/)
})

test('validates flow task input and rejects arbitrary command shapes', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-task-flow-'))
  const flow = join(dir, 'flow.json')
  await writeFile(flow, JSON.stringify({ version: 1, key: 'task-flow', target: { story: 'text-input' }, steps: [{ type: 'expect', observable: 'text', equals: '' }] }))
  const ok = await runRunner(['flow', flow])
  assert.equal(ok.code, 0, ok.stderr)
  assert.match(ok.stdout, /flow pass: task-flow/)

  for (const args of [['rm', '-rf'], ['flow', flow, '--update-baseline'], ['story-capture', '../etc'], ['story-capture', 'text-input', '/etc/x.png']]) {
    const result = await runRunner(args)
    assert.equal(result.code, 1, `expected failure for ${args.join(' ')}`)
  }
})

test('capture tasks create PNGs through the generic provider adapter', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-task-capture-'))
  const storyPng = join(dir, 'story.png')
  const story = await runRunner(['story-capture', 'text-input', storyPng])
  assert.equal(story.code, 0, story.stderr)
  assert.deepEqual(Array.from((await readFile(storyPng)).subarray(0, 8)), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

  const compPng = join(dir, 'composition.png')
  const composition = await runRunner(['composition-capture', 'compositions/examples/text-field-matrix.json', compPng])
  assert.equal(composition.code, 0, composition.stderr)
  assert.deepEqual(Array.from((await readFile(compPng)).subarray(0, 8)), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
})
