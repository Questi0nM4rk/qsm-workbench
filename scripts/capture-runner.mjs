import { spawn } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { formatErrors, validateFile } from './composition.mjs'
import { loadProvider, resolveProviderRoot } from './provider.mjs'
import { mirrorQuickshellConfigRoot } from './quickshell-config.mjs'

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
  return `import QtQuick
import QtQuick.Window
Window {
  id: root
  visible: true
  width: ${Number(props.viewportWidth) || 800}
  height: ${Number(props.viewportHeight) || 500}
  property int settledFrames: 0
  property bool capturing: false
  function finish(ok, error) {
    console.log(${JSON.stringify(RESULT_MARKER)} + JSON.stringify({ ok: ok, error: error, path: ${JSON.stringify(output)} }))
    Qt.quit()
  }
  Loader {
    id: loader
    anchors.fill: parent
    source: ${JSON.stringify(pathToFileURL(provider.paths.adapter).href)}
    onLoaded: { for (var key in props) item[key] = props[key] }
    onStatusChanged: if (status === Loader.Error) root.finish(false, "adapter load failed")
    property var props: ${JSON.stringify(props)}
  }
  FrameAnimation {
    running: loader.status === Loader.Ready && !root.capturing
    onTriggered: {
      const peer = loader.item
      const status = peer.storyStatus
      if (status === "failed" || status === "error") {
        root.finish(false, peer.storyError || "story failed to load")
        return
      }
      const ready = status === undefined || status === "ready" || status === "empty"
      const integration = peer.integration
      const idle = !integration || typeof integration.idle !== "function" || integration.idle() === true
      if (!ready || !idle) { root.settledFrames = 0; return }
      if (++root.settledFrames < 2) return
      root.capturing = true
      if (!peer.grabToImage(function(result) {
        const ok = result.saveToFile(${JSON.stringify(output)})
        root.finish(ok, ok ? "" : "could not save PNG")
      })) root.finish(false, "grabToImage refused capture")
    }
  }
  Timer {
    interval: 15000; running: true
    onTriggered: root.finish(false, "story did not become ready and idle before capture deadline")
  }
}`
}

function runQml(hostPath, provider) {
  return new Promise((done) => {
    let stdout = ''
    let stderr = ''
    const usesQuickshell = provider.shellEntry !== null
    const imports = [provider.qmlImportPath, resolve(root, 'qml')]
    const runtime = usesQuickshell ? process.env.QSM_QS_BIN || process.env.QSM_QUICKSHELL_BIN || 'qs' : QML_BIN
    const args = usesQuickshell ? ['--path', hostPath] : [...imports.flatMap(path => ['-I', path]), hostPath]
    const child = spawn(runtime, args, {
      detached: true,
      env: { ...process.env, QML_IMPORT_PATH: imports.concat(process.env.QML_IMPORT_PATH || []).join(':'),
        QML_XHR_ALLOW_FILE_READ: '1', QT_FORCE_STDERR_LOGGING: '1', QT_OPENGL: 'desktop', QT_QPA_PLATFORM: 'offscreen', QSG_RHI_BACKEND: 'opengl' },
    })
    const deadline = setTimeout(() => {
      try { process.kill(-child.pid, 'SIGKILL') } catch {}
    }, 20000)
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', (error) => { clearTimeout(deadline); done({ error, stdout, stderr, code: null }) })
    child.on('close', (code) => { clearTimeout(deadline); done({ stdout, stderr, code }) })
  })
}

export async function captureStory({ providerRoot = resolveProviderRoot(), storyKey, output }) {
  const provider = loadProvider(providerRoot)
  const story = provider.stories[storyKey]
  if (!story) throw new Error(`unknown story '${storyKey}'`)
  return capture(provider, {
    mode: 'story', story: withUnitUrl(story, provider.root), component: story.component, variant: story.variant,
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

function withUnitUrl(story, providerRoot) {
  return story.unit ? { ...story, unit: pathToFileURL(resolve(providerRoot, story.unit)).href } : story
}

async function capture(provider, props, output) {
  assertOutput(output)
  const dir = mkdtempSync(resolve(tmpdir(), 'qsm-capture-'))
  const hostPath = resolve(dir, 'host.qml')
  try {
    if (provider.shellEntry !== null) mirrorQuickshellConfigRoot(dir, provider)
    writeFileSync(hostPath, hostSource(provider, props, output))
    const run = await runQml(hostPath, provider)
    const text = `${run.stdout ?? ''}\n${run.stderr ?? ''}`
    if (run.error) throw new Error(`could not start capture runtime: ${run.error.message}`)
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
