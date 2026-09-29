import { randomBytes } from 'node:crypto'
import { spawn } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { loadDescriptor } from './composition.mjs'
import { formatErrors, resolveFlowPath, validateDocument } from './flow.mjs'
import { loadProvider, resolveProviderRoot } from './provider.mjs'

// Bounded semantic flow runner (workbench bead 1q6.3). Validates a flow
// document through scripts/flow.mjs, resolves its story/composition target,
// serializes only data into the fixed provider flow host template, runs it
// offscreen, and reports the structured result. No document-derived source,
// imports, commands, screenshots, or baselines in this bead.

const workbenchRoot = resolve(import.meta.dirname, '..')

export const FLOW_TIMEOUT_MS = 15000
export const QML_BIN = '/usr/lib/qt6/bin/qml'
export const QUICKSHELL_BIN = 'quickshell'
export const RESULT_MARKER = 'QSM_FLOW_RESULT '
export const BASELINE_ROOT = resolve(workbenchRoot, 'tests/integration/baselines')
export const DEFAULT_COLOR_FUZZ = 0.5
export const DEFAULT_MAX_CHANGED_RATIO = 0.002

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
    return { kind: 'story', key: doc.target.story, config }
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

// Serialize only data into the fixed host template: whole-line replacement
// of the three data markers, so document text can never become QML source,
// an import, or a command.
export function buildHostSource(doc, target, provider = selectedProvider(), captureArtifacts = {}, verbose = false) {
  const template = readFileSync(provider.paths.flowHost, 'utf8')
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
  for (const [marker, value] of [['__FLOW_DATA__', doc], ['__STORY_CONFIG__', storyConfig], ['__COMPOSITION_DOC__', compositionDoc], ['__CAPTURE_ARTIFACTS__', captureArtifacts], ['__VERBOSE__', verbose]]) {
    const { line, replacement } = inject(marker, value)
    source = source.replace(line, replacement)
  }
  if (source.includes('__FLOW_DATA__') || source.includes('__STORY_CONFIG__') || source.includes('__COMPOSITION_DOC__') || source.includes('__CAPTURE_ARTIFACTS__') || source.includes('__VERBOSE__')) {
    throw new Error('flow host template kept an unreplaced data marker')
  }
  return source
}

export function metadataPathFor(pngPath) {
  return `${pngPath}.metadata.json`
}

export function artifactRoot() {
  return resolve('/tmp', `qsm-flow-artifacts-${process.pid}-${randomBytes(4).toString('hex')}`)
}

export function captureArtifactMap(doc, rootDir = artifactRoot()) {
  const out = {}
  const steps = Array.isArray(doc?.steps) ? doc.steps : []
  for (let index = 0; index < steps.length; index += 1) {
    if (steps[index]?.type === 'capture') out[String(index)] = resolve(rootDir, `step-${index}.png`)
  }
  return out
}

export function resolveBaselinePath(relativePath) {
  const full = resolve(workbenchRoot, relativePath)
  if (full !== BASELINE_ROOT && !full.startsWith(BASELINE_ROOT + sep)) {
    throw new Error(`baseline path escapes ${BASELINE_ROOT}: ${relativePath}`)
  }
  return full
}

export function writeMetadata(pngPath, metadata) {
  writeFileSync(metadataPathFor(pngPath), `${JSON.stringify(metadata, Object.keys(metadata).sort(), 2)}\n`)
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

export function assertCompatibleMetadata(actual, expected) {
  const fields = ['flowKey', 'stepIndex', 'target', 'logicalWidth', 'logicalHeight', 'renderScale', 'physicalWidth', 'physicalHeight', 'theme', 'qtMajor', 'qtMinor', 'renderer']
  for (const field of fields) {
    if (stableJson(actual?.[field]) !== stableJson(expected?.[field])) {
      throw new Error(`incompatible baseline metadata: ${field} actual=${stableJson(actual?.[field])} expected=${stableJson(expected?.[field])}`)
    }
  }
}

function execFileText(command, args) {
  return new Promise((done) => {
    const child = spawn(command, args, { env: process.env })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', (error) => done({ error, stdout, stderr, code: null }))
    child.on('close', (code) => done({ code, stdout, stderr }))
  })
}

let qtVersionCache = null
async function qmlQtVersion() {
  if (qtVersionCache) return qtVersionCache
  const run = await execFileText(QML_BIN, ['--version'])
  const text = `${run.stdout ?? ''} ${run.stderr ?? ''}`
  const match = text.match(/Qt\s+(\d+)\.(\d+)/i) ?? text.match(/(\d+)\.(\d+)\.\d+/)
  qtVersionCache = { qtMajor: match ? Number(match[1]) : 0, qtMinor: match ? Number(match[2]) : 0 }
  return qtVersionCache
}

export async function pngDimensions(pngPath) {
  const first = await execFileText('identify', ['-format', '%w %h', pngPath])
  if (first.error || first.code !== 0) {
    const second = await execFileText('magick', ['identify', '-format', '%w %h', pngPath])
    if (second.error || second.code !== 0) throw new Error(`could not identify PNG dimensions for ${pngPath}: ${second.stderr || second.error?.message}`)
    const [width, height] = second.stdout.trim().split(/\s+/).map(Number)
    return { width, height }
  }
  const [width, height] = first.stdout.trim().split(/\s+/).map(Number)
  return { width, height }
}

export async function comparePngs({ expectedPath, actualPath, diffPath, colorFuzz, maxChangedRatio, expectedPixels }) {
  const args = ['-metric', 'AE', '-fuzz', `${colorFuzz}%`, expectedPath, actualPath, diffPath]
  let run = await execFileText('compare', args)
  if (run.error) run = await execFileText('magick', ['compare', ...args])
  if (run.error || (run.code !== 0 && run.code !== 1)) throw new Error(`ImageMagick comparison failed: ${run.stderr || run.error?.message}`)
  const countArgs = [expectedPath, actualPath, '-compose', 'difference', '-composite', '-separate', '-evaluate-sequence', 'max', '-threshold', `${colorFuzz}%`, '-format', '%[fx:mean*w*h]', 'info:']
  let count = await execFileText('magick', countArgs)
  if (count.error) count = await execFileText('convert', countArgs)
  if (count.error || count.code !== 0) throw new Error(`ImageMagick changed-pixel count failed: ${count.stderr || count.error?.message}`)
  const changedPixels = Math.round(Number(count.stdout.trim()))
  const totalPixels = expectedPixels
  const changedRatio = totalPixels > 0 ? changedPixels / totalPixels : 1
  if (changedPixels === 0) rmSync(diffPath, { force: true })
  return { changedPixels, totalPixels, changedRatio, passed: changedRatio <= maxChangedRatio }
}

async function processCaptures(result, doc, { updateBaseline = false } = {}) {
  const steps = Array.isArray(result?.steps) ? result.steps : []
  const captures = []
  const fail = (message) => {
    const error = new Error(message)
    error.captures = captures
    throw error
  }
  for (const step of steps.filter((item) => item?.type === 'capture' && item?.ok)) {
    const qtVersion = await qmlQtVersion()
    step.metadata = { ...step.metadata, ...qtVersion }
    const sourceStep = doc.steps[step.index]
    const actualPath = step.actualPath
    const actualMetadataPath = metadataPathFor(actualPath)
    const baselinePath = resolveBaselinePath(sourceStep.baseline)
    const baselineMetadataPath = metadataPathFor(baselinePath)
    const diffPath = resolve(dirname(actualPath), `step-${step.index}.diff.png`)
    writeMetadata(actualPath, step.metadata)
    const actualDimensions = await pngDimensions(actualPath)
    if (actualDimensions.width !== step.metadata.physicalWidth || actualDimensions.height !== step.metadata.physicalHeight) {
      fail(`capture step ${step.index} wrote ${actualDimensions.width}x${actualDimensions.height}, expected ${step.metadata.physicalWidth}x${step.metadata.physicalHeight}: ${actualPath}`)
    }
    if (updateBaseline) {
      mkdirSync(dirname(baselinePath), { recursive: true })
      const rel = relative(BASELINE_ROOT, dirname(baselinePath))
      if (rel.startsWith('..') || isAbsolute(rel)) throw new Error(`baseline directory escapes root: ${dirname(baselinePath)}`)
      copyFileSync(actualPath, baselinePath)
      copyFileSync(actualMetadataPath, baselineMetadataPath)
      captures.push({ stepIndex: step.index, actualPath, actualMetadataPath, expectedPath: baselinePath, expectedMetadataPath: baselineMetadataPath, updatedBaseline: true, dimensions: actualDimensions })
      continue
    }
    if (!existsSync(baselinePath) || !existsSync(baselineMetadataPath)) {
      captures.push({ stepIndex: step.index, actualPath, actualMetadataPath, expectedPath: baselinePath, expectedMetadataPath: baselineMetadataPath, missingBaseline: true, dimensions: actualDimensions })
      fail(`missing baseline for capture step ${step.index}: ${baselinePath} (run with --update-baseline to approve)`)
    }
    const expectedMetadata = JSON.parse(readFileSync(baselineMetadataPath, 'utf8'))
    try {
      assertCompatibleMetadata(step.metadata, expectedMetadata)
    } catch (error) {
      captures.push({ stepIndex: step.index, actualPath, actualMetadataPath, expectedPath: baselinePath, expectedMetadataPath: baselineMetadataPath, incompatible: true, reason: error.message, dimensions: actualDimensions })
      fail(error.message)
    }
    const expectedDimensions = await pngDimensions(baselinePath)
    if (expectedDimensions.width !== step.metadata.physicalWidth || expectedDimensions.height !== step.metadata.physicalHeight) {
      captures.push({ stepIndex: step.index, actualPath, actualMetadataPath, expectedPath: baselinePath, expectedMetadataPath: baselineMetadataPath, incompatible: true, dimensions: actualDimensions, expectedDimensions })
      fail(`incompatible baseline dimensions for step ${step.index}: ${baselinePath} is ${expectedDimensions.width}x${expectedDimensions.height}, expected ${step.metadata.physicalWidth}x${step.metadata.physicalHeight}`)
    }
    const metrics = await comparePngs({
      expectedPath: baselinePath,
      actualPath,
      diffPath,
      colorFuzz: sourceStep.colorFuzz ?? DEFAULT_COLOR_FUZZ,
      maxChangedRatio: sourceStep.maxChangedRatio ?? DEFAULT_MAX_CHANGED_RATIO,
      expectedPixels: step.metadata.physicalWidth * step.metadata.physicalHeight,
    })
    captures.push({ stepIndex: step.index, actualPath, actualMetadataPath, expectedPath: baselinePath, expectedMetadataPath: baselineMetadataPath, diffPath, colorFuzz: sourceStep.colorFuzz ?? DEFAULT_COLOR_FUZZ, maxChangedRatio: sourceStep.maxChangedRatio ?? DEFAULT_MAX_CHANGED_RATIO, ...metrics })
    if (!metrics.passed) {
      fail(`capture step ${step.index} changed ratio ${metrics.changedRatio} exceeded ${sourceStep.maxChangedRatio ?? DEFAULT_MAX_CHANGED_RATIO}; actual=${actualPath} diff=${diffPath} expected=${baselinePath}`)
    }
  }
  return captures
}

export function hostTempPath() {
  return resolve('/tmp', `.qsm-flow-host-${process.pid}-${randomBytes(4).toString('hex')}.qml`)
}

function providerHostTempPath(provider) {
  return resolve(dirname(provider.paths.flowHost), `.qsm-flow-host-${process.pid}-${randomBytes(4).toString('hex')}.qml`)
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
    const captures = Array.isArray(result?.artifacts?.captures) ? result.artifacts.captures : []
    for (const capture of captures) {
      const ratio = capture.changedRatio !== undefined ? capture.changedRatio : 0
      const threshold = capture.maxChangedRatio !== undefined ? capture.maxChangedRatio : 'n/a'
      const parts = [
        `  capture[${capture.stepIndex}]`,
        `actual=${capture.actualPath}`,
        `expected=${capture.expectedPath}`,
        `ratio=${ratio}`,
        `threshold=${threshold}`,
      ]
      if (capture.diffPath) parts.splice(3, 0, `diff=${capture.diffPath}`)
      if (capture.updatedBaseline) parts.push('baseline=updated')
      lines.push(parts.join(' '))
    }
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
    // Providers with a shell entry need Quickshell to register their `qs.*`
    // modules. Their FlowHost is already a ShellRoot, so no Window wrapper is
    // involved. Plain-QML providers retain the existing isolated Window path.
    const usesQuickshell = provider.shellEntry !== null
    const windowPath = usesQuickshell ? null : hostTempPath()
    if (windowPath)
      writeFileSync(windowPath, flowWindowSource(hostPath))
    const runtime = usesQuickshell ? QUICKSHELL_BIN : QML_BIN
    const args = usesQuickshell
      ? ['--path', hostPath]
      : ['-I', provider.qmlImportPath, windowPath]
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
export async function runFlowFile(flowArg, { timeoutMs = FLOW_TIMEOUT_MS, providerRoot = resolveProviderRoot(), updateBaseline = false, verbose = false } = {}) {
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
  const artifacts = captureArtifactMap(doc)
  for (const path of Object.values(artifacts)) mkdirSync(dirname(path), { recursive: true })
  try {
    hostSource = buildHostSource(doc, target, provider, artifacts, verbose)
  } catch (error) {
    return { ok: false, error: error.message, doc }
  }
  // The injected file stays beside the provider FlowHost so its local QML
  // dependencies resolve exactly as they do in the live provider.
  const hostPath = providerHostTempPath(provider)
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
    const outcome = {
      ok: passed,
      error: passed ? null : (parsed.result?.error ?? 'flow failed'),
      doc,
      result: parsed.result,
      output,
      code: run.code,
    }
    if (passed) {
      try {
        const captures = await processCaptures(parsed.result, doc, { updateBaseline })
        if (captures.length > 0) outcome.result.artifacts = { captures }
      } catch (error) {
        outcome.ok = false
        outcome.error = error.message
        outcome.result.status = 'fail'
        outcome.result.error = error.message
        outcome.result.artifacts = { captures: error.captures ?? [] }
      }
    }
    return outcome
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
  const updateBaseline = rest.includes('--update-baseline')
  const listSteps = rest.includes('--list-steps')
  const verbose = rest.includes('--verbose')
  const timeoutMs = timeoutFlag ? Number(timeoutFlag.split('=')[1]) : FLOW_TIMEOUT_MS
  if (command !== 'run' || !fileArg) {
    console.error('usage: node scripts/flow-runner.mjs run <flow.json> --provider <provider-root> [--timeout-ms=N] [--update-baseline] [--list-steps] [--verbose]')
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
  const unknownFlags = rest.filter((arg) => arg !== '--update-baseline' && !arg.startsWith('--timeout-ms=') && arg !== '--list-steps' && arg !== '--verbose')
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
      if (step.baseline !== undefined) parts.push(`baseline: ${step.baseline}`)
      if (step.reason !== undefined) parts.push(`reason: "${step.reason}"`)
      console.log(`  [${i}] ${parts.join(' ')}`)
    }
    process.exit(0)
  }
  const outcome = await runFlowFile(fileArg, { timeoutMs, providerRoot, updateBaseline, verbose })
  if (outcome.result) console.log(formatFlowResult(outcome.result, outcome.doc))
  else console.error(`flow fail: ${outcome.error}`)
  process.exit(outcome.ok ? 0 : 1)
}
