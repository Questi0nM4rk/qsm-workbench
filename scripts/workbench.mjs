import { existsSync, readFileSync, readdirSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs'
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { basename, resolve, sep } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { formatErrors, loadDescriptor, resolveCompositionPath, resolveDescriptorPath, validateDocument, validateFile } from './composition.mjs'
import { formatErrors as formatFlowErrors, resolveFlowPath } from './flow.mjs'
import { loadFlowFile, resolveFlowTarget, validateFlowDocument } from './flow-runner.mjs'
import { loadProvider, resolveProviderRoot } from './provider.mjs'

const root = resolve(import.meta.dirname, '..')
const launcherPath = fileURLToPath(import.meta.url)
const args = process.argv.slice(2)
const checkOnly = args.includes('--check')
let composeArg = null
let composeRequested = false
let flowArg = null
let flowRequested = false
let providerArg = null
const positionals = []
for (let index = 0; index < args.length; index += 1) {
  const arg = args[index]
  if (arg === '--check') {
    // Validation-only mode composes with the same target parsing as launch.
  } else if (arg === '--compose') {
    if (composeRequested) fail('--compose may be specified only once')
    composeRequested = true
    composeArg = args[index + 1] ?? null
    index += 1
  } else if (arg === '--flow') {
    if (flowRequested) fail('--flow may be specified only once')
    flowRequested = true
    flowArg = args[index + 1] ?? null
    index += 1
  } else if (arg === '--provider') {
    if (providerArg !== null) fail('--provider may be specified only once')
    providerArg = args[index + 1] ?? null
    index += 1
  } else if (arg.startsWith('--')) {
    fail(`unknown option: ${arg}`)
  } else {
    positionals.push(arg)
  }
}
let requestedKey = positionals[0] ?? ''
if (providerArg !== null && (!providerArg || providerArg.startsWith('--')))
  fail('--provider needs exactly one local provider root')
const provider = loadProvider(resolveProviderRoot(providerArg ?? process.env.QSM_WORKBENCH_PROVIDER_ROOT))
const registryPath = provider.paths.stories
const metadataPath = ''
const previewPath = provider.paths.adapter
const shellQmlPath = provider.shellEntry ?? resolve(root, 'qml/shell.qml')
const providerRootUrl = pathToFileURL(provider.root).href
const leaseDirectory = process.env.QSM_WORKBENCH_LEASE_DIR || process.env.XDG_RUNTIME_DIR || '/tmp'
const leaseKey = createHash('sha256').update(provider.root).digest('hex').slice(0, 16)
const leasePath = resolve(leaseDirectory, `qsm-workbench-${leaseKey}.json`)

const registryFields = new Set(['component', 'variant', 'viewport', 'title', 'description', 'tags', 'source', 'docs', 'tests', 'unit'])
const metadataFields = new Set(['title', 'description', 'tags', 'source', 'docs', 'tests'])
const forbiddenMetadataFields = new Set(['component', 'variant', 'viewport'])

function fail(message) {
  console.error(`qsm-workbench: ${message}`)
  process.exit(1)
}

function assertDirectory(path, label) {
  if (!existsSync(path)) fail(`${label} does not exist: ${path}`)
  if (!statSync(path).isDirectory()) fail(`${label} must be a directory: ${path}`)
}

function assertFile(path, label) {
  if (!existsSync(path)) fail(`${label} does not exist: ${path}`)
  if (!statSync(path).isFile()) fail(`${label} must be a file: ${path}`)
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch (error) {
    fail(`could not read ${label} ${path}: ${error.message}`)
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function readLease() {
  try {
    const lease = JSON.parse(readFileSync(leasePath, 'utf8'))
    return Number.isInteger(lease.pid) && lease.pid > 1 ? lease : null
  } catch {
    return null
  }
}

function removeLease() {
  try { unlinkSync(leasePath) } catch { /* already absent */ }
}

function ownsProviderProcess(pid) {
  try {
    const values = readFileSync(`/proc/${pid}/environ`).toString().split('\0')
    return values.includes(`QSM_WORKBENCH_PROVIDER_ROOT=${providerRootUrl}`)
  } catch {
    return false
  }
}

function pause(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function replacePriorProviderProcess() {
  const lease = readLease()
  if (!lease || !ownsProviderProcess(lease.pid)) {
    removeLease()
    return
  }
  try { process.kill(lease.pid, 'SIGTERM') } catch { /* process exited */ }
  for (let elapsed = 0; elapsed < 2000 && ownsProviderProcess(lease.pid); elapsed += 50)
    await pause(50)
  if (ownsProviderProcess(lease.pid)) {
    try { process.kill(lease.pid, 'SIGKILL') } catch { /* process exited */ }
  }
  removeLease()
}

function writeLease(pid) {
  const temporary = `${leasePath}.${process.pid}.tmp`
  writeFileSync(temporary, JSON.stringify({ pid, providerRoot: providerRootUrl }))
  renameSync(temporary, leasePath)
}

function assertSafeRelativePath(value, label) {
  if (typeof value !== 'string' || value.trim() === '') fail(`${label} must be a non-empty relative path`)
  if (value.includes('\0')) fail(`${label} contains a null byte`)
  if (value.startsWith('/') || /^[A-Za-z]:[\\/]/.test(value)) fail(`${label} must be relative: ${value}`)
  const resolved = resolve(provider.root, value)
  if (resolved !== provider.root && !resolved.startsWith(provider.root + sep)) fail(`${label} escapes provider: ${value}`)
  assertFile(resolved, label)
}

function validateMetadataEntry(key, metadata) {
  if (!isPlainObject(metadata)) fail(`metadata for '${key}' must be an object`)
  for (const field of Object.keys(metadata)) {
    if (forbiddenMetadataFields.has(field)) fail(`metadata for '${key}' cannot set rendering field '${field}'`)
    if (!metadataFields.has(field)) fail(`metadata for '${key}' has unknown field '${field}'`)
  }
  if ('title' in metadata && (typeof metadata.title !== 'string' || metadata.title.trim() === ''))
    fail(`metadata for '${key}' has invalid title`)
  if ('description' in metadata && typeof metadata.description !== 'string')
    fail(`metadata for '${key}' has invalid description`)
  if ('tags' in metadata && (!Array.isArray(metadata.tags) || metadata.tags.some((tag) => typeof tag !== 'string' || tag.trim() === '')))
    fail(`metadata for '${key}' has invalid tags`)
  for (const field of ['source', 'docs'])
    if (field in metadata) assertSafeRelativePath(metadata[field], `metadata '${key}.${field}'`)
  if ('tests' in metadata) {
    if (!Array.isArray(metadata.tests)) fail(`metadata for '${key}' tests must be an array`)
    for (const [index, test] of metadata.tests.entries()) {
      if (!isPlainObject(test)) fail(`metadata for '${key}' test ${index} must be an object`)
      for (const field of Object.keys(test))
        if (!['label', 'path'].includes(field)) fail(`metadata for '${key}' test ${index} has unknown field '${field}'`)
      if (typeof test.label !== 'string' || test.label.trim() === '') fail(`metadata for '${key}' test ${index} has invalid label`)
      assertSafeRelativePath(test.path, `metadata '${key}.tests[${index}].path'`)
    }
  }
}

assertDirectory(provider.root, 'provider root')
assertDirectory(provider.qmlImportPath, 'provider qml root')
assertFile(previewPath, 'provider adapter')
assertFile(shellQmlPath, 'workbench shell.qml')

const scenarios = provider.stories

if (!scenarios || Array.isArray(scenarios) || Object.keys(scenarios).length === 0)
  fail('registry must be a non-empty JSON object')

// A storybook is the whole catalog, so a story without a reachable harness is
// an entry that cannot be opened. Catching it here means the catalog is the
// checklist for the unit migration, rather than a second copy of the same
// list living in a host switch that nothing validates.
// A declared unit must be a real, reachable file. A story without one is NOT
// a failure on its own: units migrate one type at a time and the catalog is
// the checklist, so the count below is progress, not an error. What IS a
// failure is a storybook that cannot be opened.
for (const [key, story] of Object.entries(scenarios)) {
  if (story.unit)
    assertSafeRelativePath(story.unit, `story '${key}' unit`);
}

const unitBacked = Object.values(scenarios).filter((story) => story.unit).length
if (Object.keys(scenarios).length > 0 && unitBacked < Object.keys(scenarios).length) {
  console.log(`units: ${unitBacked}/${Object.keys(scenarios).length} stories name a unit file (migration in progress)`)
}

// The storybook holds EVERY type, and that is machine-checkable rather than a
// habit. A provider that owns a directory of components declares the directory
// and the types it deliberately does not show yet; anything in that directory
// must then be reachable from the catalog. Adding a component file therefore
// forces a choice: write its story, or name it as uncovered and say so.
const sourceRoot = provider.manifest.sourceRoot
if (typeof sourceRoot === 'string') {
  const dir = resolve(provider.root, sourceRoot)
  if (!existsSync(dir)) fail(`manifest sourceRoot does not exist: ${sourceRoot}`)
  const declared = new Set(provider.manifest.uncovered ?? [])
  const covered = new Set(
    Object.values(scenarios)
      .map((story) => story.source)
      .filter((value) => typeof value === 'string')
      .map((value) => basename(value)),
  )
  const missing = readdirSync(dir)
    .filter((name) => name.endsWith('.qml'))
    .filter((name) => !covered.has(name) && !declared.has(name))
    .sort()
  if (missing.length > 0) {
    fail(`components with no story and not listed in manifest.uncovered: ${missing.join(', ')}\n`
      + '  a type in a storybook is either reachable from the catalog or declared out of scope; adding a file means choosing one')
  }
}

for (const [key, story] of Object.entries(scenarios)) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(key)) fail(`story key '${key}' is not stable kebab-case`)
  if (!isPlainObject(story)) fail(`story '${key}' must be an object`)
  for (const field of Object.keys(story))
    if (!registryFields.has(field)) fail(`story '${key}' has unknown registry field '${field}'`)
  if (typeof story.component !== 'string' || story.component.trim() === '')
    fail(`story '${key}' needs component`)
  if (typeof story.variant !== 'string' || story.variant.trim() === '')
    fail(`story '${key}' needs variant`)
  if (!Array.isArray(story.viewport) || story.viewport.length !== 2)
    fail(`story '${key}' needs a two-number viewport`)
  if (story.viewport.some((value) => !Number.isFinite(value) || value <= 0))
    fail(`story '${key}' has an invalid viewport`)
}

const metadata = metadataPath && existsSync(metadataPath) ? readJson(metadataPath, 'metadata') : {}
if (!isPlainObject(metadata)) fail('metadata must be a JSON object')
for (const [key, entry] of Object.entries(metadata)) {
  if (!scenarios[key]) fail(`metadata references unknown story '${key}'`)
  validateMetadataEntry(key, entry)
}

// A unit path becomes an absolute URL HERE, where the provider root is known.
// The host receives a URL it can load directly, so nothing downstream has to
// guess whether a catalog path is provider-relative or host-relative.
const mergedScenarios = Object.fromEntries(Object.entries(scenarios).map(([key, story]) => {
  const merged = { ...story, ...(metadata[key] ?? {}) }
  if (merged.unit)
    merged.unit = pathToFileURL(resolve(provider.root, merged.unit)).href
  return [key, merged]
}))

let flowPath = ''
let flowDoc = null
let flowTarget = null
if (flowRequested) {
  if (!flowArg || flowArg.startsWith('--')) fail('--flow needs exactly one absolute or project-relative JSON path')
  if (composeRequested || positionals.length > 0) fail('--flow cannot be combined with a story key or --compose')
  flowPath = resolveFlowPath(flowArg)
  if (!flowPath || !flowPath.toLowerCase().endsWith('.json')) fail(`flow file must be JSON: ${flowArg}`)
  assertFile(flowPath, 'flow file')
  try {
    flowDoc = loadFlowFile(flowPath)
  } catch (error) {
    fail(`could not read flow ${flowPath}: ${error.message}`)
  }
  const checked = validateFlowDocument(flowDoc, provider)
  if (!checked.ok) fail(`invalid flow ${flowPath}\n${formatFlowErrors(checked.errors)}`)
  try {
    flowTarget = resolveFlowTarget(flowDoc, provider)
  } catch (error) {
    fail(error.message)
  }
  if (flowTarget.kind === 'story') requestedKey = flowTarget.key
  else composeRequested = true
}

let compositionPath = null
let compositionDoc = null
if (composeRequested) {
  if (flowTarget?.kind === 'composition') {
    compositionPath = resolve(root, flowTarget.path)
    compositionDoc = flowTarget.composition
  } else {
    if (!composeArg || composeArg.startsWith('--')) fail('--compose needs an absolute or project-relative JSON path')
    compositionPath = resolveCompositionPath(composeArg)
    if (!compositionPath.toLowerCase().endsWith('.json')) fail(`composition file must be JSON: ${composeArg}`)
    assertFile(compositionPath, 'composition file')
    const composition = validateFile(compositionPath, provider.paths.compositionTypes)
    if (!composition.ok) fail(`invalid composition ${compositionPath}\n${formatErrors(composition.errors)}`)
    compositionDoc = readJson(compositionPath, 'composition')
  }
}

// Bead 05v.4: deterministic prevalidated Compose boundary. The descriptor is
// source-free (no QML paths) and the starters are validated documents; both
// cross into QML as explicit environment JSON so QML never reads files or
// duplicates their content. Missing files degrade to an empty boundary
// (tests use synthetic shells); present-but-invalid files fail loudly.
let compositionTypes = null
try {
  compositionTypes = loadDescriptor(resolveDescriptorPath(provider.root))
} catch {
  compositionTypes = null
}
const starterNames = ['text-field-matrix', 'menu-form', 'shell-border-rollout']
const starterDocs = []
for (const name of starterNames) {
  const starterPath = resolve(root, 'compositions/examples', `${name}.json`)
  if (!existsSync(starterPath)) continue
  const starterDoc = readJson(starterPath, `starter ${name}`)
  if (compositionTypes) {
    const checked = validateDocument(starterDoc, compositionTypes)
    if (!checked.ok) fail(`invalid starter ${starterPath}\n${formatErrors(checked.errors)}`)
  }
  starterDocs.push(starterDoc)
}

if (checkOnly) {
  console.log(`validated ${Object.keys(scenarios).length} stories from ${registryPath}`)
  if (compositionPath) console.log(`composition ok: ${compositionPath}`)
  if (flowPath) console.log(`flow ok: ${flowPath}`)
  process.exit(0)
}

const firstKey = Object.keys(scenarios)[0]
const initialKey = requestedKey || firstKey
if (!scenarios[initialKey])
  fail(`unknown story '${initialKey}', choose one of: ${Object.keys(scenarios).join(', ')}`)

const quickshell = process.env.QSM_QUICKSHELL_BIN ?? 'quickshell'
const existingImportPath = process.env.QML_IMPORT_PATH ? `${process.env.QML_IMPORT_PATH}:` : ''
await replacePriorProviderProcess()
const child = spawn(quickshell, [
  '--path',
  shellQmlPath,
], {
  stdio: 'inherit',
  cwd: root,
  env: {
    ...process.env,
    QSM_WORKBENCH_PROVIDER_ROOT: pathToFileURL(provider.root).href,
    QSM_WORKBENCH_PROVIDER_DIR: provider.root,
    QSM_WORKBENCH_PROVIDER_ID: provider.manifest.id,
    QSM_WORKBENCH_PROVIDER_TITLE: provider.manifest.title ?? provider.manifest.id,
    QSM_WORKBENCH_PROVIDER_ADAPTER: pathToFileURL(provider.paths.adapter).href,
    QSM_WORKBENCH_ROOT: root,
    QSM_WORKBENCH_INITIAL_STORY: initialKey,
    QSM_WORKBENCH_REGISTRY: JSON.stringify(mergedScenarios),
    QSM_WORKBENCH_REGISTRY_PATH: registryPath,
    QSM_WORKBENCH_METADATA_PATH: metadataPath,
    QSM_WORKBENCH_EXPLICIT_STORY: requestedKey ? '1' : '0',
    QSM_WORKBENCH_COMPOSITION_PATH: compositionPath ?? '',
    QSM_WORKBENCH_COMPOSITION: compositionDoc ? JSON.stringify(compositionDoc) : '',
    QSM_WORKBENCH_COMPOSITION_TYPES: compositionTypes ? JSON.stringify(compositionTypes) : '',
    QSM_WORKBENCH_COMPOSITION_STARTERS: starterDocs.length > 0 ? JSON.stringify(starterDocs) : '',
    QSM_WORKBENCH_FLOW_PATH: flowPath,
    QSM_WORKBENCH_LAUNCHER: launcherPath,
    QML_IMPORT_PATH: `${existingImportPath}${provider.qmlImportPath}:${resolve(root, 'qml')}`,
    QML_XHR_ALLOW_FILE_READ: '1',
    QT_FORCE_STDERR_LOGGING: '1',
  },
})
writeLease(child.pid)

child.on('error', (error) => fail(`could not start ${quickshell}: ${error.message}`))
child.on('close', (code) => {
  const lease = readLease()
  if (lease?.pid === child.pid)
    removeLease()
  process.exitCode = code ?? 1
})

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => {
    try { child.kill(signal) } catch { /* child already exited */ }
  })
}
