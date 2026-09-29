import { spawn } from 'node:child_process'
import { resolve } from 'node:path'
import { formatErrors, validateFile } from './composition.mjs'
import { formatErrors as formatFlowErrors, resolveFlowPath } from './flow.mjs'
import { loadFlowFile, selectedProvider, validateFlowDocument } from './flow-runner.mjs'
import { resolveProviderRoot } from './provider.mjs'

const root = resolve(import.meta.dirname, '..')
const KILL_TIMEOUT_MS = 3000
const keyPattern = /^[a-z0-9][a-z0-9-]*$/

function fail(message) {
  console.error(`qsm-workbench task-runner: ${message}`)
  process.exit(1)
}

function checkedCaptureOutput(value, key) {
  const output = value ?? `/tmp/qsm-workbench-${key}.png`
  if (resolve(output) !== output || !output.startsWith('/tmp/') || !output.endsWith('.png'))
    fail(`capture output must be an absolute /tmp/*.png path: ${value ?? output}`)
  return output
}

function checkedCompositionPath(value, provider) {
  if (!value) fail('composition operation needs a JSON path')
  const path = resolve(root, value)
  if (!path.toLowerCase().endsWith('.json')) fail(`composition file must be JSON: ${value}`)
  const result = validateFile(path, provider.paths.compositionTypes)
  if (!result.ok) fail(`invalid composition ${path}\n${formatErrors(result.errors)}`)
  return path
}

function checkedFlowPath(value, provider) {
  if (!value) fail('flow operation needs a JSON path')
  const path = resolveFlowPath(value)
  if (!path || !path.toLowerCase().endsWith('.json')) fail(`flow file must be JSON: ${value}`)
  let doc
  try {
    doc = loadFlowFile(path)
  } catch (error) {
    fail(`invalid flow ${path}\n${path}: could not read flow file: ${error.message}`)
  }
  const result = validateFlowDocument(doc, provider)
  if (!result.ok) fail(`invalid flow ${path}\n${formatFlowErrors(result.errors)}`)
  return path
}

const [name, first, second, extra] = process.argv.slice(2)
const providerRoot = resolveProviderRoot()
const provider = selectedProvider(providerRoot)
const declared = provider.tasks?.[name]
if (!declared) fail(`unknown provider task '${name ?? ''}'`)

let argv
let cwd = root
switch (declared.operation) {
  case 'validate':
    if (first || second || extra) fail(`${name} takes no arguments`)
    argv = [process.execPath, 'scripts/workbench.mjs', '--check', '--provider', providerRoot]
    break
  case 'story-capture': {
    if (!first || !keyPattern.test(first)) fail(`invalid story key: ${first ?? ''}`)
    if (extra) fail(`${name} takes a story key and one optional output path`)
    if (!provider.manifest.capabilities.includes('stories')) fail('provider does not declare stories')
    argv = [process.execPath, 'scripts/capture-runner.mjs', 'story', first, checkedCaptureOutput(second, first)]
    break
  }
  case 'composition-check': {
    if (second || extra) fail(`${name} takes exactly one JSON path`)
    const composition = checkedCompositionPath(first, provider)
    argv = [process.execPath, 'scripts/composition.mjs', 'check', composition, '--provider', providerRoot]
    break
  }
  case 'composition-capture': {
    if (extra) fail(`${name} takes a JSON path and one optional output path`)
    const composition = checkedCompositionPath(first, provider)
    const key = composition.split('/').at(-1).replace(/\.json$/i, '')
    argv = [process.execPath, 'scripts/capture-runner.mjs', 'composition', composition, checkedCaptureOutput(second, key)]
    break
  }
  case 'flow': {
    if (second || extra) fail(`${name} takes exactly one JSON path`)
    const flow = checkedFlowPath(first, provider)
    argv = [process.execPath, 'scripts/flow-runner.mjs', 'run', flow, '--provider', providerRoot]
    break
  }
  default:
    fail(`unknown fixed operation '${declared.operation}'`)
}

const child = spawn(argv[0], argv.slice(1), { cwd, stdio: 'inherit', detached: true })

let cancelling = false
let killTimer = null

function signalGroup(signal) {
  if (!child.pid) return
  try { process.kill(-child.pid, signal) } catch {}
}

child.on('error', (error) => {
  if (!cancelling) fail(`could not start ${argv.join(' ')}: ${error.message}`)
})

child.on('close', (code) => {
  if (killTimer) clearTimeout(killTimer)
  process.exit(cancelling ? 143 : (code ?? 1))
})

function cancel() {
  if (cancelling) {
    signalGroup('SIGKILL')
    return
  }
  cancelling = true
  signalGroup('SIGTERM')
  killTimer = setTimeout(() => signalGroup('SIGKILL'), KILL_TIMEOUT_MS)
}

process.on('SIGTERM', cancel)
process.on('SIGINT', cancel)
