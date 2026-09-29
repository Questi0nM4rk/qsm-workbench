import { randomBytes } from 'node:crypto'
import { spawn } from 'node:child_process'
import { readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { loadDescriptor } from './composition.mjs'
import { formatErrors, resolveFlowPath, validateDocument } from './flow.mjs'
import { loadProvider, resolveProviderRoot } from './provider.mjs'

// Bounded semantic flow runner (workbench bead 1q6.3). Validates a flow
// document through scripts/flow.mjs, resolves its story/composition target,
// serializes only data into the fixed harness flow host template, runs it
// offscreen against the provider adapter, and reports the structured result.
// No document-derived source, imports, commands, screenshots, or baselines.

const workbenchRoot = resolve(import.meta.dirname, '..')
const harnessFlowHost = resolve(workbenchRoot, 'qml/QsmWorkbench/FlowHost.qml')

export const FLOW_TIMEOUT_MS = 15000
export const QML_BIN = '/usr/lib/qt6/bin/qml'
export const QUICKSHELL_BIN = 'quickshell'
export const RESULT_MARKER = 'QSM_FLOW_RESULT '

export function selectedProvider(providerRoot = resolveProviderRoot()) {
  return loadProvider(providerRoot)
}

export function loadProviderStories(provider = selectedProvider()) {
  return provider.stories
}

export function loadFlowFile(flowPath) {
  return JSON.parse(readFileSync(flowPath, 'utf8'))
}

// Validate through scripts/flow.mjs, with story keys from the selected
// provider stories (the runtime source of truth for story targets).
export function validateFlowDocument(doc, provider = selectedProvider()) {
  let descriptor = null
  try {
    descriptor = loadDescriptor(provider.paths.compositionTypes)
  } catch {
    descriptor = null
  }
  let storyKeys = null
  try {
    storyKeys = new Set(Object.keys(loadProviderStories(provider)))
  } catch {
    storyKeys = null
  }
  return validateDocument(doc, descriptor, storyKeys)
}

// Resolve an already-validated flow document to its runtime target: story
// configuration from selected provider stories, or the
// validated composition document at its project-relative path. Throws on
// any resolution failure so callers report it without starting QML.
export function resolveFlowTarget(doc, provider = selectedProvider()) {
  if (doc?.target?.story !== undefined) {
    const scenarios = loadProviderStories(provider)
    const config = scenarios[doc.target.story]
    if (!config) throw new Error(`unknown story '${doc.target.story}' (not in provider '${provider.manifest.id}' stories)`)
    return { kind: 'story', key: doc.target.story, config: withUnitUrl(config, provider.root) }
  }
  if (doc?.target?.composition !== undefined) {
    const relative = doc.target.composition
    if (typeof relative !== 'string' || relative.trim() === '') throw new Error('composition target must be a non-empty path')
    const full = isAbsolute(relative) ? resolve(relative) : resolve(workbenchRoot, relative)
    let composition
    try {
      composition = JSON.parse(readFileSync(full, 'utf8'))
    } catch (error) {
      throw new Error(`could not read composition file '${relative}': ${error.message}`)
    }
    return { kind: 'composition', path: relative, composition }
  }
  throw new Error('flow target must contain exactly one of story or composition')
}

// A catalog `unit` is provider-relative; the adapter loads it directly, so the
// URL is resolved here, where the provider root is known, exactly as the live
// launcher does.
function withUnitUrl(story, providerRoot) {
  return story.unit ? { ...story, unit: pathToFileURL(resolve(providerRoot, story.unit)).href } : story
}

// Serialize only data into the fixed host template: whole-line replacement
// of the data markers, so document text can never become QML source, an
// import, or a command.
export function buildHostSource(doc, target, provider = selectedProvider(), verbose = false) {
  const template = readFileSync(harnessFlowHost, 'utf8')
  const storyConfig = target.kind === 'story' ? target.config : null
  const compositionDoc = target.kind === 'composition' ? target.composition : null
  const inject = (marker, value) => {
    const line = template.split('\n').find((candidate) => candidate.includes(marker))
    if (!line) throw new Error(`flow host template is missing marker ${marker}`)
    const markerIdx = line.indexOf(marker)
    if (markerIdx === -1) throw new Error(`marker ${marker} not found in line`)
    // Find the colon that precedes the value (before the marker)
    const colonIdx = line.lastIndexOf(':', markerIdx)
    if (colonIdx === -1) throw new Error(`no colon found before marker ${marker}`)
    return { line, replacement: line.slice(0, colonIdx + 1) + ` ${JSON.stringify(value)}` }
  }
  let source = template
  const markers = [
    ['__ADAPTER_URL__', pathToFileURL(provider.paths.adapter).href],
    ['__FLOW_DATA__', doc],
    ['__STORY_CONFIG__', storyConfig],
    ['__COMPOSITION_DOC__', compositionDoc],
    ['__VERBOSE__', verbose],
  ]
  for (const [marker, value] of markers) {
    const { line, replacement } = inject(marker, value)
    source = source.replace(line, replacement)
  }
  const left = markers.filter(([marker]) => source.includes(marker)).map(([marker]) => marker)
  if (left.length > 0) throw new Error(`flow host template kept an unreplaced data marker: ${left.join(', ')}`)
  return source
}

export function hostTempPath() {
  return resolve('/tmp', `.qsm-flow-host-${process.pid}-${randomBytes(4).toString('hex')}.qml`)
}

// Parse the single final structured result from combined QML output.
// Never throws: every failure mode returns an { ok: false, error } shape.
export function parseFlowOutput(output) {
  const text = String(output ?? '')
  const lines = text.split('\n').filter((line) => line.includes(RESULT_MARKER))
  if (lines.length === 0) return { ok: false, error: 'QML runtime produced no QSM_FLOW_RESULT record' }
  const raw = lines.at(-1).slice(lines.at(-1).indexOf(RESULT_MARKER) + RESULT_MARKER.length)
  try {
    return { ok: true, result: JSON.parse(raw) }
  } catch (error) {
    return { ok: false, error: `QSM_FLOW_RESULT was not valid JSON: ${error.message}` }
  }
}

export function targetLabel(doc) {
  if (doc?.target?.story !== undefined) return `story ${doc.target.story}`
  if (doc?.target?.composition !== undefined) return `composition ${doc.target.composition}`
  return 'unknown target'
}

// Deterministic concise pass/fail plus per-step diagnostics.
export function formatFlowResult(result, doc) {
  const lines = []
  const key = result?.key ?? doc?.key ?? '<missing>'
  const steps = Array.isArray(result?.steps) ? result.steps : []
  if (result?.status === 'pass') {
    lines.push(`flow pass: ${key} (${targetLabel(doc)}, ${steps.length} steps)`)
  } else {
    lines.push(`flow fail: ${key} (${targetLabel(doc)}): ${result?.error ?? 'unknown failure'}`)
    for (const step of steps) {
      const label = `${step?.type ?? '<missing>'}${step?.node !== undefined ? ` ${step.node}` : ''}`
      lines.push(`  [${step?.index ?? '?'}] ${label}: ${step?.ok ? 'ok' : `FAIL ${step?.error ?? 'unknown failure'}`}`)
    }
  }
  return lines.join('\n')
}

function flowWindowSource(hostPath) {
  return `import QtQuick\nimport QtQuick.Window\nWindow {\n  id: root\n  visible: true\n  width: 800\n  height: 600\n  Loader {\n    id: flowHost\n    source: ${JSON.stringify(pathToFileURL(hostPath).href)}\n    onLoaded: {\n      root.width = Math.max(1, item.width)\n      root.height = Math.max(1, item.height)\n    }\n  }\n}`
}

function runQmlOffscreen(hostPath, provider, timeoutMs, verbose = false) {
  return new Promise((done) => {
    let stdout = ''
    let stderr = ''
    let timedOut = false
    let settled = false
    // The harness flow host is an Item, so it always rides a Window wrapper.
    // A provider with a shell entry needs Quickshell to register its `qs.*`
    // modules, and a plain provider runs on qml; both load the same wrapper.
    const usesQuickshell = provider.shellEntry !== null
    const windowPath = hostTempPath()
    writeFileSync(windowPath, flowWindowSource(hostPath))
    const runtime = usesQuickshell ? QUICKSHELL_BIN : QML_BIN
    const importPath = `${provider.qmlImportPath}:${resolve(workbenchRoot, 'qml')}`
    const args = usesQuickshell
      ? ['--path', windowPath]
      : ['-I', importPath, windowPath]
    const child = spawn(runtime, args, {
      detached: true,
      env: {
        ...process.env,
        QT_FORCE_STDERR_LOGGING: '1',
        QT_OPENGL: 'desktop',
        QT_QPA_PLATFORM: 'offscreen',
        QSG_RHI_BACKEND: 'opengl',
        QML_XHR_ALLOW_FILE_READ: '1',
      },
    })
    if (verbose) {
      child.stdout.on('data', (chunk) => {
        const text = chunk.toString()
        for (const line of text.split('\n')) {
          if (line.trim()) {
            console.error(`[verbose] ${line}`)
          }
        }
      })
      child.stderr.on('data', (chunk) => {
        const text = chunk.toString()
        for (const line of text.split('\n')) {
          if (line.trim()) {
            console.error(`[verbose] ${line}`)
          }
        }
      })
    }
    const finish = (value) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      if (windowPath)
        rmSync(windowPath, { force: true })
      done(value)
    }
    const timer = setTimeout(() => {
      timedOut = true
      // Terminate the whole process group so no orphaned QML outlives us.
      try {
        process.kill(-child.pid, 'SIGKILL')
      } catch {
        try { child.kill('SIGKILL') } catch { /* already gone */ }
      }
    }, timeoutMs)
    timer.unref?.()
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', (error) => finish({ stdout, stderr, code: null, timedOut: false, spawnError: error }))
    child.on('close', (code, signal) => finish({ stdout, stderr, code, signal, timedOut }))
  })
}

// End-to-end run of one flow file: validate, resolve, execute offscreen
// with a bounded timeout, parse the structured result. Always removes only
// its own temporary host file. Returns a plain outcome object.
export async function runFlowFile(flowArg, { timeoutMs = FLOW_TIMEOUT_MS, providerRoot = resolveProviderRoot(), verbose = false } = {}) {
  const provider = selectedProvider(providerRoot)
  const flowPath = resolveFlowPath(flowArg)
  let doc
  try {
    doc = loadFlowFile(flowPath)
  } catch (error) {
    return { ok: false, error: `could not read flow file '${flowArg}': ${error.message}`, doc: null }
  }
  const checked = validateFlowDocument(doc, provider)
  if (!checked.ok) {
    return { ok: false, error: `invalid flow ${flowPath}\n${formatErrors(checked.errors)}`, doc }
  }
  let target
  try {
    target = resolveFlowTarget(doc, provider)
  } catch (error) {
    return { ok: false, error: error.message, doc }
  }
  let hostSource
  try {
    hostSource = buildHostSource(doc, target, provider, verbose)
  } catch (error) {
    return { ok: false, error: error.message, doc }
  }
  // The injected host lives in /tmp, never beside the template or the
  // provider, so no run can leave a copy inside a source directory.
  const hostPath = hostTempPath()
  writeFileSync(hostPath, hostSource)
  try {
    const run = await runQmlOffscreen(hostPath, provider, timeoutMs, verbose)
    const output = `${run.stdout ?? ''}\n${run.stderr ?? ''}`
    if (run.spawnError) {
      const runtime = provider.shellEntry !== null ? QUICKSHELL_BIN : QML_BIN
      return { ok: false, error: `could not start ${runtime}: ${run.spawnError.message}`, doc, output }
    }
    if (run.timedOut) {
      return { ok: false, error: `flow timed out after ${timeoutMs}ms; process group terminated`, doc, output, timedOut: true }
    }
    const parsed = parseFlowOutput(output)
    if (!parsed.ok) {
      const detail = run.code !== 0 ? ` (qml exited with code ${run.code})` : ''
      return { ok: false, error: `${parsed.error}${detail}`, doc, output, code: run.code }
    }
    const passed = parsed.result?.status === 'pass'
    return {
      ok: passed,
      error: passed ? null : (parsed.result?.error ?? 'flow failed'),
      doc,
      result: parsed.result,
      output,
      code: run.code,
    }
  } finally {
    rmSync(hostPath, { force: true })
  }
}

export function listHostTemps() {
  try {
    return readdirSync('/tmp').filter((name) => name.startsWith('.qsm-flow-host-'))
  } catch {
    return []
  }
}

const invokedAsCli = process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (invokedAsCli) {
  const raw = process.argv.slice(2)
  const providerIndex = raw.indexOf('--provider')
  const providerRoot = providerIndex >= 0 ? resolveProviderRoot(raw[providerIndex + 1]) : resolveProviderRoot()
  if (providerIndex >= 0) raw.splice(providerIndex, 2)
  const [command, fileArg, ...rest] = raw
  const timeoutFlag = rest.find((arg) => arg.startsWith('--timeout-ms='))
  const listSteps = rest.includes('--list-steps')
  const verbose = rest.includes('--verbose')
  const timeoutMs = timeoutFlag ? Number(timeoutFlag.split('=')[1]) : FLOW_TIMEOUT_MS
  if (command !== 'run' || !fileArg) {
    console.error('usage: node scripts/flow-runner.mjs run <flow.json> --provider <provider-root> [--timeout-ms=N] [--list-steps] [--verbose]')
    process.exit(2)
  }
  if (!fileArg.toLowerCase().endsWith('.json')) {
    console.error(`qsm-workbench flow: not a JSON document: ${fileArg}`)
    process.exit(1)
  }
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    console.error(`qsm-workbench flow: invalid timeout: ${timeoutFlag}`)
    process.exit(2)
  }
  const unknownFlags = rest.filter((arg) => !arg.startsWith('--timeout-ms=') && arg !== '--list-steps' && arg !== '--verbose')
  if (unknownFlags.length > 0) {
    console.error(`qsm-workbench flow: unknown option: ${unknownFlags[0]}`)
    process.exit(2)
  }
  if (listSteps) {
    const flowPath = resolveFlowPath(fileArg)
    const doc = loadFlowFile(flowPath)
    const checked = validateFlowDocument(doc, selectedProvider(providerRoot))
    if (!checked.ok) {
      console.error(`invalid flow ${flowPath}\n${formatErrors(checked.errors)}`)
      process.exit(1)
    }
    console.log(`Flow: ${doc.key ?? '<missing>'}`)
    console.log(`Target: ${doc.target?.story ? `story ${doc.target.story}` : `composition ${doc.target.composition}`}`)
    console.log(`Scale: ${doc.scale ?? 1}`)
    console.log('Steps:')
    for (const [i, step] of (doc.steps ?? []).entries()) {
      const parts = [step.type]
      if (step.node !== undefined) parts.push(`node: ${step.node}`)
      if (step.name !== undefined) parts.push(`name: ${step.name}`)
      if (step.event !== undefined) parts.push(`event: ${step.event}`)
      if (step.observable !== undefined) parts.push(`observable: ${step.observable}`)
      if (step.group !== undefined) parts.push(`group: ${step.group}`)
      if (step.option !== undefined) parts.push(`option: ${step.option}`)
      if (step.text !== undefined) parts.push(`text: "${step.text}"`)
      if (step.key !== undefined) parts.push(`key: ${step.key}`)
      console.log(`  [${i}] ${parts.join(' ')}`)
    }
    process.exit(0)
  }
  const outcome = await runFlowFile(fileArg, { timeoutMs, providerRoot, verbose })
  if (outcome.result) console.log(formatFlowResult(outcome.result, outcome.doc))
  else console.error(`flow fail: ${outcome.error}`)
  process.exit(outcome.ok ? 0 : 1)
}
