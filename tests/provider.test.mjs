import assert from 'node:assert/strict'
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { loadProvider } from '../scripts/provider.mjs'

async function makeProvider(manifest = { version: 1, id: 'test-kit', capabilities: ['stories', 'compositions'] }) {
  const root = await mkdtemp(join(tmpdir(), 'qsm-provider-'))
  const workbench = join(root, 'workbench')
  await mkdir(join(root, 'qml'), { recursive: true })
  await mkdir(workbench, { recursive: true })
  await writeFile(join(workbench, 'provider.json'), JSON.stringify(manifest))
  await writeFile(join(workbench, 'Adapter.qml'), 'import QtQuick\nItem {}\n')
  await writeFile(join(workbench, 'stories.json'), JSON.stringify({ version: 1, stories: { probe: { component: 'probe', variant: 'default', viewport: [640, 480] } } }))
  await writeFile(join(workbench, 'composition-types.json'), '{}\n')
  return root
}

test('loads only the fixed trusted provider layout', async () => {
  const root = await makeProvider()
  const provider = loadProvider(root)

  assert.equal(provider.manifest.id, 'test-kit')
  assert.equal(provider.paths.adapter, join(root, 'workbench/Adapter.qml'))
  assert.equal(provider.qmlImportPath, join(root, 'qml'))
  assert.equal(provider.shellEntry, null)
})

test('loads the fixed optional provider shell entry', async () => {
  const root = await makeProvider()
  await writeFile(join(root, 'workbench/shell.qml'), 'import Quickshell\nShellRoot {}\n')

  const provider = loadProvider(root)
  assert.equal(provider.shellEntry, join(root, 'workbench/shell.qml'))
})

test('rejects executable manifest fields and unsupported capabilities', async () => {
  for (const manifest of [
    { version: 1, id: 'test-kit', capabilities: ['stories'], adapter: '../outside.qml' },
    { version: 1, id: 'test-kit', capabilities: ['stories', 'shell'] },
  ]) {
    const root = await makeProvider(manifest)
    assert.throws(() => loadProvider(root), /unknown or executable field|unknown capability/)
  }
})

test('requires fixed files for declared capabilities', async () => {
  const root = await makeProvider({ version: 1, id: 'test-kit', capabilities: ['stories', 'flows'] })
  assert.throws(() => loadProvider(root), /FlowHost\.qml does not exist/)
})

test('rejects non-versioned or implicit story catalogs', async () => {
  const root = await makeProvider({ version: 1, id: 'test-kit', capabilities: ['stories'] })
  await writeFile(join(root, 'workbench/stories.json'), JSON.stringify({ probe: { component: 'probe', variant: 'default', viewport: [640, 480] } }))
  assert.throws(() => loadProvider(root), /stories version must be exactly 1|unknown field/)
})

test('detects missing story tags without replacing provider overrides', async () => {
  const root = await makeProvider({ version: 1, id: 'test-kit', capabilities: ['stories'] })
  await writeFile(join(root, 'workbench/stories.json'), JSON.stringify({
    version: 1,
    stories: {
      probe: { component: 'Probe Control', variant: 'Default State', viewport: [640, 480] },
      explicit: { component: 'Other', variant: 'Resting', viewport: [640, 480], tags: ['input', 'control'] },
    },
  }))

  const provider = loadProvider(root)
  assert.deepEqual(provider.stories.probe.tags, ['probe-control', 'default-state'])
  assert.deepEqual(provider.stories.explicit.tags, ['input', 'control'])
  const raw = JSON.parse(await readFile(join(root, 'workbench/stories.json'), 'utf8'))
  assert.equal('tags' in raw.stories.probe, false)
})
