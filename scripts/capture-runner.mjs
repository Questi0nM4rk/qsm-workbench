import { spawn } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { formatErrors, validateFile } from './composition.mjs'
import { loadProvider, resolveProviderRoot } from './provider.mjs'

const root = resolve(import.meta.dirname, '..')
const QML_BIN = '/usr/lib/qt6/bin/qml'
const RESULT_MARKER = 'QSM_CAPTURE_RESULT '

function fail(message) {
  console.error(`qsm-workbench capture: ${message}`)
  process.exit(1)
}

function assertOutput(path) {
  if (resolve(path) !== path || !path.startsWith('/tmp/') || !path.endsWith('.png')) fail(`output must be an absolute /tmp/*.png path: ${path}`)
}

function assertPng(path) {
  if (!existsSync(path) || !statSync(path).isFile()) throw new Error(`capture did not create PNG: ${path}`)
  const signature = readFileSync(path).subarray(0, 8)
  if (!signature.equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) throw new Error(`capture output is not a PNG: ${path}`)
}

function hostSource(provider, props, output) {
  return `import QtQuick\nimport QtQuick.Window\nWindow {\n  id: root\n  visible: true\n  width: ${Number(props.viewportWidth) || 800}\n  height: ${Number(props.viewportHeight) || 500}\n  Loader {\n    id: loader\n    anchors.fill: parent\n    source: ${JSON.stringify(pathToFileURL(provider.paths.adapter).href)}\n    onLoaded: {\n      for (var key in props) item[key] = props[key]\n      captureTimer.restart()\n    }\n    onStatusChanged: if (status === Loader.Error) { console.log(${JSON.stringify(RESULT_MARKER)} + JSON.stringify({ ok: false, error: "adapter load failed" })); Qt.quit() }\n    property var props: ${JSON.stringify(props)}\n  }\n  Timer {\n    id: captureTimer\n    interval: 100\n    repeat: false\n    onTriggered: {\n      if (!loader.item) {\n        console.log(${JSON.stringify(RESULT_MARKER)} + JSON.stringify({ ok: false, error: "adapter was not ready for capture" }))\n        Qt.quit()\n        return\n      }\n      loader.item.grabToImage(function(result) {\n        var ok = result.saveToFile(${JSON.stringify(output)})\n        console.log(${JSON.stringify(RESULT_MARKER)} + JSON.stringify({ ok: ok, path: ${JSON.stringify(output)} }))\n        Qt.quit()\n      })\n    }\n  }\n}`
}

function runQml(hostPath, provider) {
  return new Promise((done) => {
    let stdout = ''
    let stderr = ''
    const child = spawn(QML_BIN, ['-I', provider.qmlImportPath, hostPath], {
      env: { ...process.env, QT_FORCE_STDERR_LOGGING: '1', QT_OPENGL: 'desktop', QT_QPA_PLATFORM: 'offscreen', QSG_RHI_BACKEND: 'opengl' },
    })
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', (error) => done({ error, stdout, stderr, code: null }))
    child.on('close', (code) => done({ stdout, stderr, code }))
  })
}

export async function captureStory({ providerRoot = resolveProviderRoot(), storyKey, output }) {
  const provider = loadProvider(providerRoot)
  const story = provider.stories[storyKey]
  if (!story) throw new Error(`unknown story '${storyKey}'`)
  return capture(provider, {
    mode: 'story', story, component: story.component, variant: story.variant,
    viewportWidth: story.viewport[0], viewportHeight: story.viewport[1], storyKey, resetGeneration: 0, interactive: false,
  }, output)
}

export async function captureComposition({ providerRoot = resolveProviderRoot(), compositionPath, output }) {
  const provider = loadProvider(providerRoot)
  const full = resolve(root, compositionPath)
  const checked = validateFile(full, provider.paths.compositionTypes)
  if (!checked.ok) throw new Error(`invalid composition ${full}\n${formatErrors(checked.errors)}`)
  const doc = JSON.parse(readFileSync(full, 'utf8'))
  return capture(provider, { mode: 'composition', composition: doc, viewportWidth: doc.viewport[0], viewportHeight: doc.viewport[1], resetGeneration: 0 }, output)
}

async function capture(provider, props, output) {
  assertOutput(output)
  const dir = mkdtempSync(resolve(tmpdir(), 'qsm-capture-'))
  const hostPath = resolve(dir, 'host.qml')
  writeFileSync(hostPath, hostSource(provider, props, output))
  try {
    const run = await runQml(hostPath, provider)
    const text = `${run.stdout ?? ''}\n${run.stderr ?? ''}`
    if (run.error) throw new Error(`could not start ${QML_BIN}: ${run.error.message}`)
    const line = text.split('\n').find((candidate) => candidate.includes(RESULT_MARKER))
    if (!line) throw new Error(`QML runtime produced no capture result${run.code ? ` (code ${run.code})` : ''}: ${text}`)
    const result = JSON.parse(line.slice(line.indexOf(RESULT_MARKER) + RESULT_MARKER.length))
    if (!result.ok) throw new Error(result.error || 'capture failed')
    assertPng(output)
    return { ok: true, output }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

const invokedAsCli = process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (invokedAsCli) {
  const [command, target, output] = process.argv.slice(2)
  try {
    if (command === 'story' && target && output) {
      await captureStory({ storyKey: target, output })
    } else if (command === 'composition' && target && output) {
      await captureComposition({ compositionPath: target, output })
    } else {
      console.error('usage: node scripts/capture-runner.mjs story <key> <output.png> | composition <composition.json> <output.png>')
      process.exit(2)
    }
    console.log(`capture ok: ${output}`)
  } catch (error) {
    fail(error.message)
  }
}
