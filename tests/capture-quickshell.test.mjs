import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { test } from 'node:test'
import { captureStory } from '../scripts/capture-runner.mjs'

async function provider(t, status = 'ready') {
  const root = await mkdtemp('/tmp/opencode/capture-shell-')
  t.after(() => rm(root, { recursive: true, force: true }))
  const workbench = join(root, 'workbench')
  await mkdir(join(workbench, 'fixture'), { recursive: true })
  await writeFile(join(workbench, 'provider.json'), JSON.stringify({
    version: 1, id: 'capture-fixture', title: 'Capture fixture', capabilities: ['stories'],
  }))
  await writeFile(join(workbench, 'stories.json'), JSON.stringify({ version: 1, stories: {
    ready: { component: 'fixture', variant: 'ready', viewport: [240, 160], title: 'Fixture' },
  } }))
  await writeFile(join(workbench, 'shell.qml'), 'import Quickshell\nShellRoot {}\n')
  await writeFile(join(workbench, 'fixture', 'Reading.qml'), 'import QtQuick\nQtObject { property bool ready: false }\n')
  await writeFile(join(workbench, 'Adapter.qml'), `import QtQuick
import qs.fixture
Rectangle {
  id: root
  property string mode
  property var story
  property string component
  property string variant
  property string storyKey
  property int viewportWidth
  property int viewportHeight
  property int resetGeneration
  property bool interactive
  readonly property string storyStatus: ${JSON.stringify(status)}
  readonly property string storyError: "fixture refused"
  readonly property var integration: ({ idle: () => reading.ready })
  Reading { id: reading }
  Timer { interval: 200; running: true; onTriggered: reading.ready = true }
  color: reading.ready ? "green" : "red"
}`)
  return root
}

test('capture resolves Quickshell namespaces and waits for the ready story', async t => {
  const root = await provider(t)
  const output = join(root, 'ready.png')
  const result = await captureStory({ providerRoot: root, storyKey: 'ready', output })
  assert.equal(result.ok, true)
  const png = await readFile(output)
  assert.deepEqual(png.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
})

test('capture refuses a failed provider instead of reporting a screenshot success', async t => {
  const root = await provider(t, 'failed')
  await assert.rejects(captureStory({ providerRoot: root, storyKey: 'ready', output: join(root, 'failed.png') }), /fixture refused/)
})
