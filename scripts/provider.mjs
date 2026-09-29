import { existsSync, readFileSync, statSync } from 'node:fs'
import { resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

export const PROVIDER_VERSION = 1

const manifestFields = new Set(['version', 'id', 'title', 'description', 'capabilities', 'sourceRoot', 'uncovered'])
const storiesFields = new Set(['version', 'stories'])
const storyFields = new Set(['component', 'variant', 'viewport', 'title', 'description', 'tags', 'source', 'docs', 'tests', 'unit'])
const capabilities = new Set(['stories', 'compositions', 'flows', 'tasks'])
const providerFiles = {
  manifest: 'provider.json',
  adapter: 'Adapter.qml',
  shell: 'shell.qml',
  stories: 'stories.json',
  compositionTypes: 'composition-types.json',
  tasks: 'tasks.json',
}

const taskFields = new Set(['operation', 'label'])
const taskOperations = new Set(['validate', 'story-capture', 'composition-check', 'composition-capture', 'flow'])

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function fail(message) {
  throw new Error(`provider: ${message}`)
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

function validateManifest(manifest) {
  if (!isPlainObject(manifest)) fail('manifest must be a JSON object')
  for (const field of Object.keys(manifest)) {
    if (!manifestFields.has(field)) fail(`manifest has unknown or executable field '${field}'`)
  }
  if (manifest.version !== PROVIDER_VERSION) fail(`manifest version must be exactly ${PROVIDER_VERSION}`)
  if (typeof manifest.id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(manifest.id))
    fail('manifest id must be stable kebab-case')
  for (const field of ['title', 'description']) {
    if (field in manifest && (typeof manifest[field] !== 'string' || manifest[field].trim() === ''))
      fail(`manifest ${field} must be a non-empty string`)
  }
  if (!Array.isArray(manifest.capabilities) || manifest.capabilities.length === 0)
    fail('manifest capabilities must be a non-empty array')
  const seen = new Set()
  for (const capability of manifest.capabilities) {
    if (!capabilities.has(capability)) fail(`manifest has unknown capability '${capability}'`)
    if (seen.has(capability)) fail(`manifest repeats capability '${capability}'`)
    seen.add(capability)
  }
  if (!seen.has('stories')) fail("manifest must declare 'stories' capability")
  // `sourceRoot` is the directory of components this provider is responsible
  // for. Naming it is what makes "the storybook holds every type" checkable:
  // a new file in that directory must become reachable from the catalog, or be
  // declared in `uncovered` on purpose. Data only — it names a directory the
  // harness reads, never anything to execute.
  if ('sourceRoot' in manifest) {
    if (typeof manifest.sourceRoot !== 'string' || manifest.sourceRoot.trim() === '')
      fail('manifest sourceRoot must be a non-empty string')
    else if (manifest.sourceRoot.startsWith('/') || manifest.sourceRoot.includes('..'))
      fail('manifest sourceRoot must be a relative path inside the provider')
  }
  if ('uncovered' in manifest) {
    if (!Array.isArray(manifest.uncovered) || manifest.uncovered.length === 0)
      fail('manifest uncovered must be a non-empty array when declared')
    const seenUncovered = new Set()
    for (const name of manifest.uncovered) {
      if (typeof name !== 'string' || !/^[A-Za-z][A-Za-z0-9]*\.qml$/.test(name))
        fail(`manifest uncovered entry '${name}' must be a type file name`)
      if (seenUncovered.has(name)) fail(`manifest repeats uncovered '${name}'`)
      seenUncovered.add(name)
    }
  }
}

function validateTaskDefinitions(tasks) {
  if (!isPlainObject(tasks) || Object.keys(tasks).length === 0) fail('tasks must be a non-empty JSON object')
  for (const [name, task] of Object.entries(tasks)) {
    if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(name)) fail(`task '${name}' must be stable kebab-case`)
    if (!isPlainObject(task)) fail(`task '${name}' must be an object`)
    for (const field of Object.keys(task))
      if (!taskFields.has(field)) fail(`task '${name}' has unknown or executable field '${field}'`)
    if (typeof task.operation !== 'string' || !taskOperations.has(task.operation))
      fail(`task '${name}' has unknown fixed operation '${task.operation}'`)
    if ('label' in task && (typeof task.label !== 'string' || task.label.trim() === ''))
      fail(`task '${name}' label must be a non-empty string`)
  }
}

function validateRelativePath(value, label) {
  if (typeof value !== 'string' || value.trim() === '') fail(`${label} must be a non-empty relative path`)
  if (value.includes('\0')) fail(`${label} contains a null byte`)
  if (value.startsWith('/') || /^[A-Za-z]:[\\/]/.test(value) || value.includes('..')) fail(`${label} must be a safe provider-relative path`)
}

function validateStoryEntry(key, story) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(key)) fail(`story key '${key}' is not stable kebab-case`)
  if (!isPlainObject(story)) fail(`story '${key}' must be an object`)
  for (const field of Object.keys(story))
    if (!storyFields.has(field)) fail(`story '${key}' has unknown field '${field}'`)
  if (typeof story.component !== 'string' || story.component.trim() === '') fail(`story '${key}' needs component`)
  if (typeof story.variant !== 'string' || story.variant.trim() === '') fail(`story '${key}' needs variant`)
  if (!Array.isArray(story.viewport) || story.viewport.length !== 2) fail(`story '${key}' needs viewport [width,height]`)
  if (story.viewport.some((value) => !Number.isInteger(value) || value <= 0 || value > 8192)) fail(`story '${key}' has invalid viewport`)
  if ('title' in story && (typeof story.title !== 'string' || story.title.trim() === '')) fail(`story '${key}' title must be a non-empty string`)
  if ('description' in story && typeof story.description !== 'string') fail(`story '${key}' description must be a string`)
  if ('tags' in story && (!Array.isArray(story.tags) || story.tags.some((tag) => typeof tag !== 'string' || tag.trim() === ''))) fail(`story '${key}' has invalid tags`)
  for (const field of ['source', 'docs']) if (field in story) validateRelativePath(story[field], `story '${key}.${field}'`)
  // A unit is the story's harness, resolved through this field rather than
  // through a hardcoded list of story keys inside the host. Naming it here is
  // what lets a provider add a story without editing the harness, and what
  // lets the check below prove every story has a real, reachable harness.
  if ('unit' in story) {
    validateRelativePath(story.unit, `story '${key}.unit`)
    if (!story.unit.toLowerCase().endsWith('.qml')) fail(`story '${key}.unit must be a .qml file`)
  }
  if ('tests' in story) {
    if (!Array.isArray(story.tests)) fail(`story '${key}' tests must be an array`)
    for (const [index, test] of story.tests.entries()) {
      if (!isPlainObject(test)) fail(`story '${key}' test ${index} must be an object`)
      if (typeof test.label !== 'string' || test.label.trim() === '') fail(`story '${key}' test ${index} label must be a non-empty string`)
      validateRelativePath(test.path, `story '${key}.tests[${index}].path'`)
    }
  }
}

function validateStoriesDocument(doc) {
  if (!isPlainObject(doc)) fail('stories must be a JSON object')
  for (const field of Object.keys(doc)) if (!storiesFields.has(field)) fail(`stories has unknown field '${field}'`)
  if (doc.version !== PROVIDER_VERSION) fail(`stories version must be exactly ${PROVIDER_VERSION}`)
  if (!isPlainObject(doc.stories) || Object.keys(doc.stories).length === 0) fail('stories.stories must be a non-empty object')
  for (const [key, story] of Object.entries(doc.stories)) validateStoryEntry(key, story)
  return doc.stories
}

function tagFrom(value) {
  return String(value).trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
}

export function withAutoTags(stories) {
  return Object.fromEntries(Object.entries(stories).map(([key, story]) => {
    if ('tags' in story)
      return [key, story]
    const tags = [...new Set([tagFrom(story.component), tagFrom(story.variant)].filter(Boolean))]
    return [key, { ...story, tags }]
  }))
}

export function resolveProviderRoot(value = process.env.QSM_WORKBENCH_PROVIDER_ROOT) {
  if (typeof value !== 'string' || value.trim() === '') fail('provider root must be supplied with --provider or QSM_WORKBENCH_PROVIDER_ROOT')
  if (value.startsWith('file:')) return fileURLToPath(value)
  return value
}

export function loadProvider(providerRoot) {
  if (typeof providerRoot !== 'string' || providerRoot.trim() === '') fail('root must be a non-empty path')
  const root = resolve(providerRoot)
  assertDirectory(root, 'root')
  const workbenchDir = resolve(root, 'workbench')
  if (workbenchDir !== root && !workbenchDir.startsWith(root + sep)) fail(`workbench path escapes provider root: ${root}`)
  assertDirectory(workbenchDir, 'workbench directory')

  const paths = Object.fromEntries(Object.entries(providerFiles).map(([key, name]) => [key, resolve(workbenchDir, name)]))
  for (const [key, path] of Object.entries(paths)) {
    if (path !== workbenchDir && !path.startsWith(workbenchDir + sep)) fail(`${key} escapes provider workbench directory`)
  }
  assertFile(paths.manifest, 'manifest')
  assertFile(paths.adapter, 'adapter')
  assertFile(paths.stories, 'stories')
  if (existsSync(paths.shell))
    assertFile(paths.shell, 'provider shell entry')

  const manifest = readJson(paths.manifest, 'manifest')
  validateManifest(manifest)
  const stories = validateStoriesDocument(readJson(paths.stories, 'stories'))
  if (manifest.capabilities.includes('compositions'))
    assertFile(paths.compositionTypes, 'composition descriptor')
  if (manifest.capabilities.includes('tasks'))
    assertFile(paths.tasks, 'tasks')

  // The flow host is the harness's: a provider contributes an adapter and the
  // adapter is the whole seam, so a provider host would be a second state
  // machine that can do less and disagree with the first.
  if (existsSync(resolve(workbenchDir, 'FlowHost.qml')))
    fail('provider ships FlowHost.qml but the flow host belongs to the harness; remove it')

  const tasks = manifest.capabilities.includes('tasks') ? readJson(paths.tasks, 'tasks') : null
  if (tasks) validateTaskDefinitions(tasks)

  return {
    root,
    qmlImportPath: resolve(root, 'qml'),
    workbenchDir,
    manifest,
    stories: withAutoTags(stories),
    paths,
    tasks,
    shellEntry: existsSync(paths.shell) ? paths.shell : null,
  }
}
