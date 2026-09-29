import assert from 'node:assert/strict'
import { join, resolve } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { loadDescriptor } from '../scripts/composition.mjs'
import { validateDocument } from '../scripts/flow.mjs'

const repoRoot = resolve(fileURLToPath(import.meta.url), '../..')
const provider = join(repoRoot, 'fixtures/providers/generic')
const descriptor = loadDescriptor(join(provider, 'workbench/composition-types.json'))
const stories = new Set(['text-input'])

test('validates generic provider story flows without qsm-shell metadata', () => {
  const result = validateDocument({ version: 1, key: 'story-flow', target: { story: 'text-input' }, steps: [{ type: 'expect', observable: 'text', equals: '' }] }, descriptor, stories)
  assert.equal(result.ok, true, result.errors.map((e) => e.message).join('\n'))
})

test('rejects unknown stories and executable flow content', () => {
  const unknown = validateDocument({ version: 1, key: 'bad', target: { story: 'ghost' }, steps: [{ type: 'expect', observable: 'text', equals: '' }] }, descriptor, stories)
  assert.match(unknown.errors.map((e) => e.message).join('\n'), /unknown story 'ghost'/)

  const executable = validateDocument({ version: 1, key: 'bad', target: { story: 'text-input' }, steps: [{ type: 'write', text: 'import QtQuick' }] }, descriptor, stories)
  assert.match(executable.errors.map((e) => e.message).join('\n'), /executable content/)
})
