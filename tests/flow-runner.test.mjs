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

test('resolves stories and fixed FlowHost.qml from provider only', () => {
  const target = resolveFlowTarget(doc(), provider)
  assert.equal(target.kind, 'story')
  assert.equal(target.config.component, 'text-input')
  const source = buildHostSource(doc(), target, provider)
  assert.match(source, /QSM_FLOW_RESULT/)
  assert.doesNotMatch(source, /previews|qsm-shell|__FLOW_DATA__/)
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
  assert.match(outcome.error, /expected text/)
})
