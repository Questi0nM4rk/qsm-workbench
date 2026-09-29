import assert from 'node:assert/strict'
import { mkdtemp, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { buildHostSource, parseFlowOutput, resolveFlowTarget, runFlowFile, selectedProvider, validateFlowDocument } from '../scripts/flow-runner.mjs'

const repoRoot = resolve(fileURLToPath(import.meta.url), '../..')
const providerRoot = join(repoRoot, 'fixtures/providers/generic')
const provider = selectedProvider(providerRoot)

function doc(overrides = {}) {
  return { version: 1, key: 'runner-probe', target: { story: 'text-input' }, steps: [{ type: 'expect', observable: 'text', equals: '' }], ...overrides }
}

test('resolves a story target and builds the harness host source', () => {
  const target = resolveFlowTarget(doc(), provider)
  assert.equal(target.kind, 'story')
  assert.equal(target.config.component, 'text-input')
  assert.match(target.config.unit, /^file:\/\/.*workbench\/units\/TextInput\.qml$/)
  const source = buildHostSource(doc(), target, provider)
  assert.match(source, /QSM_FLOW_RESULT/)
  assert.match(source, /Adapter\.qml/)
  assert.doesNotMatch(source, /previews|qsm-shell|__FLOW_DATA__|__ADAPTER_URL__/)
})

test('validates flow documents against provider stories and descriptor', () => {
  assert.equal(validateFlowDocument(doc(), provider).ok, true)
  const bad = validateFlowDocument(doc({ target: { story: 'ghost' } }), provider)
  assert.match(bad.errors.map((e) => e.message).join('\n'), /unknown story 'ghost'/)
})

test('parseFlowOutput extracts final result', () => {
  const parsed = parseFlowOutput('noise\nQSM_FLOW_RESULT {"status":"pass","key":"k"}\n')
  assert.equal(parsed.ok, true)
  assert.equal(parsed.result.key, 'k')
  assert.match(parseFlowOutput('noise').error, /no QSM_FLOW_RESULT/)
})

test('runFlowFile executes the provider host', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-flow-runner-'))
  const path = join(dir, 'flow.json')
  await writeFile(path, JSON.stringify(doc()))
  const outcome = await runFlowFile(path, { providerRoot })
  assert.equal(outcome.ok, true, outcome.error || outcome.output)
  assert.equal(outcome.result.key, 'runner-probe')
})

test('provider flow host fails a wrong expectation', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-flow-runner-'))
  const path = join(dir, 'bad-flow.json')
  await writeFile(path, JSON.stringify(doc({ steps: [{ type: 'expect', observable: 'text', equals: 'wrong' }] })))
  const outcome = await runFlowFile(path, { providerRoot })
  assert.equal(outcome.ok, false)
  assert.equal(outcome.result.status, 'fail')
  assert.match(outcome.error, /expected "wrong" but observed ""/)
})

test('harness flow host executes every step type it accepts', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-flow-runner-'))
  const path = join(dir, 'all-steps.json')
  await writeFile(path, JSON.stringify(doc({
    key: 'all-steps',
    steps: [
      { type: 'expect', observable: 'variant', equals: 'default' },
      { type: 'reset' },
      { type: 'control', group: 'state', option: 'filled' },
      { type: 'expect', observable: 'variant', equals: 'filled' },
      { type: 'write', text: 'Ada' },
      { type: 'expect', observable: 'text', equals: 'Ada' },
      { type: 'key', key: 'Enter' },
      { type: 'expectEvent', event: 'accepted', origin: 'component' },
      { type: 'emit', event: 'changed' },
      { type: 'expectEvent', event: 'changed', origin: 'injected' },
      { type: 'armCheckpoint', name: 'rollout.opened' },
      { type: 'action', name: 'open' },
      { type: 'awaitCheckpoint', name: 'rollout.opened' },
      { type: 'expect', observable: 'open', equals: true },
      { type: 'continueCheckpoint', name: 'rollout.opened' },
      { type: 'awaitIdle' },
    ],
  })))
  const outcome = await runFlowFile(path, { providerRoot })
  assert.equal(outcome.ok, true, outcome.error || outcome.output)
  assert.equal(outcome.result.steps.length, 16)
  assert.equal(outcome.result.steps.filter((step) => !step.ok).length, 0)
})

test('harness flow host names a step type it cannot execute', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'qsm-flow-runner-'))
  const path = join(dir, 'undrivable.json')
  await writeFile(path, JSON.stringify(doc({ steps: [{ type: 'expect', observable: 'ghost', equals: '' }] })))
  const outcome = await runFlowFile(path, { providerRoot })
  assert.equal(outcome.ok, false)
  assert.match(outcome.error, /step 0 \(expect\)/)
  assert.match(outcome.error, /exposes no observable 'ghost'/)
})
