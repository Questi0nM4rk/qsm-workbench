import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import { mkdtemp, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { loadDescriptor, validateDocument, validateFile } from '../scripts/composition.mjs'

const repoRoot = resolve(fileURLToPath(import.meta.url), '../..')
const provider = join(repoRoot, 'fixtures/providers/generic')
const composer = join(repoRoot, 'scripts/composition.mjs')
const descriptorPath = join(provider, 'workbench/composition-types.json')
const descriptor = loadDescriptor(descriptorPath)

function baseDoc(overrides = {}) {
  return { version: 1, key: 'test-doc', viewport: [800, 600], root: { id: 'root', type: 'column', props: { spacing: 'sm' }, children: [] }, ...overrides }
}

function messages(result) {
  return result.errors.map((error) => `${error.path}: ${error.message}`).join('\n')
}

test('validates examples through the selected provider descriptor', () => {
  for (const name of ['text-field-matrix', 'menu-form', 'shell-border-rollout']) {
    const result = validateFile(join(repoRoot, 'compositions/examples', `${name}.json`), descriptorPath)
    assert.equal(result.ok, true, messages(result))
  }
})

test('keeps composition validation bounded and non-executable', () => {
  assert.match(messages(validateDocument(baseDoc({ root: { id: 'root', type: 'dialog', props: {} } }), descriptor)), /unknown node type/)
  assert.match(messages(validateDocument(baseDoc({ root: { id: 'root', type: 'text-field', props: { source: 'Evil.qml' } } }), descriptor)), /executable content|not a declared property/)
  assert.match(messages(validateDocument(baseDoc({ viewport: [80, 600] }), descriptor)), /viewport width/)
})

test('CLI requires a provider descriptor and rejects invalid files before launch', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-composition-'))
  const badPath = join(dir, 'bad.json')
  await writeFile(badPath, JSON.stringify(baseDoc({ version: 2 })))
  const run = (args) => new Promise((done) => execFile(process.execPath, [composer, ...args], { cwd: repoRoot }, (error, stdout, stderr) => done({ code: error?.code ?? 0, stdout, stderr })))

  const ok = await run(['check', 'compositions/examples/menu-form.json', '--provider', provider])
  assert.equal(ok.code, 0, ok.stderr)
  assert.match(ok.stdout, /composition ok:/)

  const bad = await run(['check', badPath, '--provider', provider])
  assert.equal(bad.code, 1)
  assert.match(bad.stderr, /version must be exactly 1/)
})
