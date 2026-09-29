import { readFileSync } from 'node:fs'
import { isAbsolute, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  loadDescriptor,
  resolveDescriptorPath,
  validateDocument as validateCompositionDocument,
} from './composition.mjs'

// Version 1 integration-flow validator. Direct, dependency-free, and kept in
// this one module: strict top-level/step allowlists, bounded ids/scale/counts,
// project-relative path roots, JSON-safe evidence values, and no executable
// content (no source paths, scripts, expressions, property paths, selectors,
// loops, variables, or arbitrary waits). Composition shape and descriptor
// resolution are reused through scripts/composition.mjs; story keys come from
// the local workbench fixture (stories/metadata.json).

const root = resolve(import.meta.dirname, '..')

export const FLOW_VERSION = 1
export const MAX_STEPS = 64
export const MAX_CAPTURES = 4
export const FLOW_SCALE_MIN = 0.5
export const FLOW_SCALE_MAX = 3
export const WRITE_TEXT_MAX = 256
export const REASON_MAX = 256
export const JSON_STRING_MAX = 1024
export const JSON_ARRAY_MAX = 64
export const JSON_OBJECT_MAX = 32
export const JSON_DEPTH_MAX = 8
export const BASELINE_ROOT = 'tests/integration/baselines/'
export const COMPOSITION_ROOT = 'compositions/'

export const STEP_TYPES = [
  'reset',
  'emit',
  'control',
  'action',
  'write',
  'key',
  'expect',
  'expectEvent',
  'armCheckpoint',
  'awaitCheckpoint',
  'continueCheckpoint',
  'capture',
  'awaitIdle',
]

export const FLOW_KEYS = ['Enter', 'Escape', 'Space']
export const EXPECT_EVENT_ORIGINS = ['component', 'injected', 'route']

const idPattern = /^[a-z0-9][a-z0-9-]{0,63}$/
const checkpointPattern = /^[a-z0-9][a-z0-9-]{0,63}(\.[a-z0-9][a-z0-9-]{0,63}){0,3}$/
const documentFields = new Set(['version', 'key', 'target', 'scale', 'theme', 'steps'])
const targetFields = new Set(['story', 'composition'])
const stepFields = {
  reset: new Set(['type']),
  emit: new Set(['type', 'node', 'event', 'payload']),
  control: new Set(['type', 'node', 'group', 'option']),
  action: new Set(['type', 'node', 'name']),
  write: new Set(['type', 'node', 'text']),
  key: new Set(['type', 'node', 'key']),
  expect: new Set(['type', 'node', 'observable', 'equals']),
  expectEvent: new Set(['type', 'node', 'event', 'origin', 'targetNode']),
  armCheckpoint: new Set(['type', 'node', 'name']),
  awaitCheckpoint: new Set(['type', 'node', 'name']),
  continueCheckpoint: new Set(['type', 'node', 'name']),
  capture: new Set(['type', 'baseline', 'reason', 'colorFuzz', 'maxChangedRatio']),
  awaitIdle: new Set(['type', 'node']),
}
// Steps that address a per-node capability and therefore require `node` on
// composition targets (and forbid it on solo story targets).
const nodeAddressedTypes = new Set(['emit', 'control', 'action', 'write', 'key', 'expect', 'expectEvent'])
const optionalNodeTypes = new Set(['armCheckpoint', 'awaitCheckpoint', 'continueCheckpoint', 'awaitIdle'])

// Field names that never appear in a data-only document. The strict allowlists
// already reject them; this list only produces a clearer diagnostic.
const executableFieldPattern = /^(source|sourceurl|qml|url|path|file|script|javascript|js|expression|binding|command|exec|shell|eval|args|arguments|code|payload|handler|callback|component|loader|import|require|selector|loop|variable|variables|wait|timeout|delay|sleep|interval|while|for|if|else|then|template|render|query|find|css|xpath)$/i

// Payload markers that have no business inside flow data strings.
const executableValuePatterns = [/\.qml(\W|$)/i, /file:\/\//i, /\bqrc:/i, /import\s+Qt\w*/, /<script/i, /javascript:/i, /\$\{/, /function\s*\(/, /__proto__/, /constructor\s*\./, /=>/, /;.*;/, /\bdocument\./i, /\bwindow\./i, /process\.env/i]

const PROTOTYPE_KEYS = new Set(['__proto__', 'constructor', 'prototype'])

export function resolveFlowPath(value) {
  if (typeof value !== 'string' || value.trim() === '') return null
  return isAbsolute(value) ? resolve(value) : resolve(root, value)
}

export function loadFlow(flowPath) {
  return JSON.parse(readFileSync(flowPath, 'utf8'))
}

export function loadStoryKeys(storyPath = resolve(root, 'stories/metadata.json')) {
  try {
    const data = JSON.parse(readFileSync(storyPath, 'utf8'))
    return new Set(Object.keys(data))
  } catch {
    return null
  }
}

export function formatErrors(errors) {
  return errors.map((error) => `${error.path}: ${error.message}`).join('\n')
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function checkExecutableValue(value, path, errors) {
  if (typeof value !== 'string') return
  if (value.includes('\0')) errors.push({ path, message: `${path} contains a null byte` })
  for (const pattern of executableValuePatterns) {
    if (pattern.test(value)) {
      errors.push({ path, message: `${path} looks like executable content (rejected ${pattern})` })
      return
    }
  }
}

function checkFields(value, allowed, path, errors) {
  for (const field of Object.keys(value)) {
    const at = path ? `${path}.${field}` : field
    if (PROTOTYPE_KEYS.has(field)) {
      errors.push({ path: at, message: `${at} is a prototype key and is not allowed` })
    } else if (!allowed.has(field)) {
      errors.push({
        path: at,
        message: executableFieldPattern.test(field)
          ? `${at} is executable content and is not allowed in flow documents`
          : `${at} is not a known field`,
      })
    }
  }
}

function checkName(value, path, errors, pattern = idPattern) {
  if (typeof value !== 'string' || !pattern.test(value)) {
    errors.push({ path, message: `${path} must be a bounded stable name (lowercase alphanumerics, dashes, dots only for checkpoints)` })
    return false
  }
  checkExecutableValue(value, path, errors)
  return true
}

// Bounded JSON-safe evidence values: finite numbers, bounded strings/arrays/
// objects/depth, plain objects only, no prototype keys, no null bytes, and no
// executable-looking strings. Accepts any JSON type (equals may be a scalar).
function checkJsonSafe(value, path, errors, depth = 0) {
  if (depth > JSON_DEPTH_MAX) {
    errors.push({ path, message: `${path} exceeds maximum depth ${JSON_DEPTH_MAX}` })
    return
  }
  if (value === null || typeof value === 'boolean') return
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) errors.push({ path, message: `${path} must be a finite number` })
    return
  }
  if (typeof value === 'string') {
    if (value.length > JSON_STRING_MAX)
      errors.push({ path, message: `${path} exceeds max length ${JSON_STRING_MAX}` })
    checkExecutableValue(value, path, errors)
    return
  }
  if (Array.isArray(value)) {
    if (value.length > JSON_ARRAY_MAX)
      errors.push({ path, message: `${path} exceeds max items ${JSON_ARRAY_MAX}` })
    value.forEach((item, index) => checkJsonSafe(item, `${path}[${index}]`, errors, depth + 1))
    return
  }
  if (isPlainObject(value)) {
    const keys = Object.keys(value)
    if (keys.length > JSON_OBJECT_MAX)
      errors.push({ path, message: `${path} exceeds max keys ${JSON_OBJECT_MAX}` })
    for (const key of keys) {
      const at = `${path}.${key}`
      if (key.length === 0 || key.length > 64) errors.push({ path: at, message: `${at} has an invalid key length` })
      if (key.includes('\0')) errors.push({ path: at, message: `${at} contains a null byte` })
      if (PROTOTYPE_KEYS.has(key))
        errors.push({ path: at, message: `${at} is a prototype key and is not allowed` })
      checkJsonSafe(value[key], at, errors, depth + 1)
    }
    return
  }
  errors.push({ path, message: `${path} must be JSON-safe (no undefined, functions, or non-plain objects)` })
}

function checkRelativeUnderRoot(value, path, errors, expectedPrefix, expectedSuffix) {
  if (typeof value !== 'string' || value.trim() === '') {
    errors.push({ path, message: `${path} must be a non-empty project-relative path` })
    return null
  }
  if (value.includes('\0')) errors.push({ path, message: `${path} contains a null byte` })
  if (isAbsolute(value) || /^[A-Za-z]:[\\/]/.test(value) || value.startsWith('/') || value.includes('\\')) {
    errors.push({ path, message: `${path} must be a project-relative '${expectedPrefix}...' path` })
    return null
  }
  if (!value.startsWith(expectedPrefix)) {
    errors.push({ path, message: `${path} must stay under '${expectedPrefix}'` })
    return null
  }
  if (/(^|\/)\.\.(\/|$)/.test(value)) {
    errors.push({ path, message: `${path} must not escape its root` })
    return null
  }
  if (expectedSuffix && !value.toLowerCase().endsWith(expectedSuffix)) {
    errors.push({ path, message: `${path} must end with '${expectedSuffix}'` })
    return null
  }
  checkExecutableValue(value, path, errors)
  const resolved = resolve(root, value)
  const rootDir = resolve(root, expectedPrefix)
  if (resolved !== rootDir && !resolved.startsWith(rootDir + sep)) {
    errors.push({ path, message: `${path} must stay under '${expectedPrefix}'` })
    return null
  }
  return resolved
}

function collectCompositionNodes(doc) {
  const ids = new Map()
  const walk = (node) => {
    if (!isPlainObject(node)) return
    if (typeof node.id === 'string') ids.set(node.id, node.type)
    for (const child of node.children ?? []) walk(child)
  }
  if (isPlainObject(doc?.root)) walk(doc.root)
  return ids
}

export function validateDocument(doc, descriptor = null, storyKeys = null) {
  const errors = []
  const fail = (path, message) => errors.push({ path, message })
  if (!isPlainObject(doc)) {
    fail('$', 'flow document must be a JSON object')
    return { ok: false, errors }
  }
  checkFields(doc, documentFields, '', errors)

  if (doc.version !== FLOW_VERSION) fail('version', `version must be exactly ${FLOW_VERSION}`)

  if (typeof doc.key !== 'string' || !idPattern.test(doc.key))
    fail('key', 'key must be stable kebab-case (lowercase alphanumerics and dashes, max 64 chars)')
  else checkExecutableValue(doc.key, 'key', errors)

  if (doc.theme !== undefined) {
    if (typeof doc.theme !== 'string' || !idPattern.test(doc.theme))
      fail('theme', 'theme must be stable kebab-case (lowercase alphanumerics and dashes, max 64 chars)')
    else checkExecutableValue(doc.theme, 'theme', errors)
  }

  let scale = 1
  if (doc.scale !== undefined) {
    if (typeof doc.scale !== 'number' || !Number.isFinite(doc.scale))
      fail('scale', 'scale must be a finite number 0.5..3')
    else if (doc.scale < FLOW_SCALE_MIN || doc.scale > FLOW_SCALE_MAX)
      fail('scale', `scale must be within ${FLOW_SCALE_MIN}..${FLOW_SCALE_MAX}`)
    else scale = doc.scale
  }

  // Target: exactly one of story / composition.
  let isSolo = null
  let nodeIds = new Map()
  let compositionTypes = isPlainObject(descriptor?.types) ? descriptor.types : null
  if (!isPlainObject(doc.target)) {
    fail('target', 'target must be an object with exactly one of: story, composition')
  } else {
    checkFields(doc.target, targetFields, 'target', errors)
    const hasStory = doc.target.story !== undefined
    const hasComposition = doc.target.composition !== undefined
    if (hasStory === hasComposition) {
      fail('target', 'target must contain exactly one of story or composition')
    } else if (hasStory) {
      isSolo = true
      if (typeof doc.target.story !== 'string' || !idPattern.test(doc.target.story)) {
        fail('target.story', 'target.story must be a stable kebab-case story key')
      } else {
        checkExecutableValue(doc.target.story, 'target.story', errors)
        if (storyKeys && !storyKeys.has(doc.target.story))
          fail('target.story', `unknown story '${doc.target.story}'`)
      }
    } else {
      isSolo = false
      const resolved = checkRelativeUnderRoot(doc.target.composition, 'target.composition', errors, COMPOSITION_ROOT, '.json')
      if (resolved) {
        let compDoc = null
        try {
          compDoc = JSON.parse(readFileSync(resolved, 'utf8'))
        } catch (error) {
          fail('target.composition', `could not read composition file: ${error.message}`)
        }
        if (compDoc) {
          if (descriptor) {
            const checked = validateCompositionDocument(compDoc, descriptor)
            if (!checked.ok) fail('target.composition', `referenced composition is invalid: ${formatErrors(checked.errors)}`)
          }
          nodeIds = collectCompositionNodes(compDoc)
        }
      }
    }
  }

  if (!Array.isArray(doc.steps) || doc.steps.length === 0) {
    fail('steps', 'steps must be a non-empty array')
  } else if (doc.steps.length > MAX_STEPS) {
    fail('steps', `steps must contain at most ${MAX_STEPS} steps`)
  } else {
    let semanticCount = 0
    let captureCount = 0
    doc.steps.forEach((step, index) => {
      const path = `steps[${index}]`
      if (!isPlainObject(step)) {
        fail(path, 'step must be an object')
        return
      }
      if (typeof step.type !== 'string' || !STEP_TYPES.includes(step.type)) {
        fail(`${path}.type`, `unknown step type '${step.type}'`)
        return
      }
      checkFields(step, stepFields[step.type], path, errors)
      const at = (field) => `${path}.${field}`
      const needsNode = isSolo === false && nodeAddressedTypes.has(step.type)
      const forbidsNode = isSolo === true && Object.hasOwn(step, 'node')

      if (forbidsNode) fail(at('node'), 'solo story flows omit node')
      if (needsNode && step.node === undefined) fail(at('node'), 'composition flows require node for this step')

      if (step.node !== undefined && (nodeAddressedTypes.has(step.type) || optionalNodeTypes.has(step.type))) {
        if (typeof step.node !== 'string' || !idPattern.test(step.node)) {
          fail(at('node'), 'node must be a bounded stable name')
        } else {
          checkExecutableValue(step.node, at('node'), errors)
          if (isSolo === false && nodeIds.size > 0 && !nodeIds.has(step.node))
            fail(at('node'), `unknown node '${step.node}' for this composition target`)
        }
      }

      const nodeType = typeof step.node === 'string' ? nodeIds.get(step.node) : null
      const declaredFor = (kind) => (nodeType && compositionTypes?.[nodeType]?.[kind]) ?? null

      switch (step.type) {
        case 'reset':
        case 'awaitIdle':
          break
        case 'emit': {
          if (typeof step.event !== 'string' || !idPattern.test(step.event)) fail(at('event'), 'event must be a bounded stable name')
          else {
            checkExecutableValue(step.event, at('event'), errors)
            const declared = declaredFor('events')
            if (declared && !declared.includes(step.event))
              fail(at('event'), `undeclared event '${step.event}' for node '${step.node}' of type '${nodeType}'`)
          }
          if (step.payload !== undefined) checkJsonSafe(step.payload, at('payload'), errors)
          break
        }
        case 'control': {
          let groupOk = true
          let optionOk = true
          if (typeof step.group !== 'string' || !idPattern.test(step.group)) {
            fail(at('group'), 'group must be a bounded stable name')
            groupOk = false
          } else checkExecutableValue(step.group, at('group'), errors)
          if (typeof step.option !== 'string' || !idPattern.test(step.option)) {
            fail(at('option'), 'option must be a bounded stable name')
            optionOk = false
          } else checkExecutableValue(step.option, at('option'), errors)
          void groupOk
          void optionOk
          break
        }
        case 'action': {
          if (typeof step.name !== 'string' || !idPattern.test(step.name)) fail(at('name'), 'name must be a bounded stable name')
          else {
            checkExecutableValue(step.name, at('name'), errors)
            const declared = declaredFor('actions')
            if (declared && !declared.includes(step.name))
              fail(at('name'), `undeclared action '${step.name}' for node '${step.node}' of type '${nodeType}'`)
          }
          break
        }
        case 'write': {
          if (typeof step.text !== 'string') fail(at('text'), 'text must be a string')
          else if (step.text.length > WRITE_TEXT_MAX) fail(at('text'), `text exceeds max length ${WRITE_TEXT_MAX}`)
          else checkExecutableValue(step.text, at('text'), errors)
          break
        }
        case 'key': {
          if (typeof step.key !== 'string' || !FLOW_KEYS.includes(step.key))
            fail(at('key'), `key must be one of: ${FLOW_KEYS.join(', ')}`)
          break
        }
        case 'expect': {
          if (typeof step.observable !== 'string' || !idPattern.test(step.observable))
            fail(at('observable'), 'observable must be a bounded stable name')
          else checkExecutableValue(step.observable, at('observable'), errors)
          if (step.equals === undefined) fail(at('equals'), 'equals is required')
          else checkJsonSafe(step.equals, at('equals'), errors)
          semanticCount += 1
          break
        }
        case 'expectEvent': {
          if (typeof step.event !== 'string' || !idPattern.test(step.event)) fail(at('event'), 'event must be a bounded stable name')
          else {
            checkExecutableValue(step.event, at('event'), errors)
            const declared = step.node !== undefined && nodeIds.size > 0
              ? compositionTypes?.[nodeIds.get(step.node)]?.events ?? null
              : null
            if (declared && !declared.includes(step.event))
              fail(at('event'), `undeclared event '${step.event}' for node '${step.node}'`)
          }
          if (step.origin !== undefined && !EXPECT_EVENT_ORIGINS.includes(step.origin))
            fail(at('origin'), `origin must be one of: ${EXPECT_EVENT_ORIGINS.join(', ')}`)
          if (step.targetNode !== undefined) {
            if (isSolo === true) fail(at('targetNode'), 'solo story flows omit targetNode')
            else if (typeof step.targetNode !== 'string' || !idPattern.test(step.targetNode))
              fail(at('targetNode'), 'targetNode must be a bounded stable name')
            else {
              checkExecutableValue(step.targetNode, at('targetNode'), errors)
              if (nodeIds.size > 0 && !nodeIds.has(step.targetNode))
                fail(at('targetNode'), `unknown target node '${step.targetNode}' for this composition target`)
            }
          }
          semanticCount += 1
          break
        }
        case 'armCheckpoint':
        case 'awaitCheckpoint':
        case 'continueCheckpoint': {
          if (typeof step.name !== 'string' || !checkpointPattern.test(step.name))
            fail(at('name'), 'name must be a bounded stable checkpoint name (kebab segments, dots separate phases)')
          else checkExecutableValue(step.name, at('name'), errors)
          break
        }
        case 'capture': {
          captureCount += 1
          checkRelativeUnderRoot(step.baseline, at('baseline'), errors, BASELINE_ROOT, '.png')
          if (typeof step.reason !== 'string' || step.reason.trim() === '') fail(at('reason'), 'reason must be a non-empty string')
          else if (step.reason.length > REASON_MAX) fail(at('reason'), `reason exceeds max length ${REASON_MAX}`)
          else checkExecutableValue(step.reason, at('reason'), errors)
          if (step.colorFuzz !== undefined) {
            if (typeof step.colorFuzz !== 'number' || !Number.isFinite(step.colorFuzz) || step.colorFuzz < 0 || step.colorFuzz > 10)
              fail(at('colorFuzz'), 'colorFuzz must be a finite number 0..10')
          }
          if (step.maxChangedRatio !== undefined) {
            if (typeof step.maxChangedRatio !== 'number' || !Number.isFinite(step.maxChangedRatio) || step.maxChangedRatio < 0 || step.maxChangedRatio > 1)
              fail(at('maxChangedRatio'), 'maxChangedRatio must be a finite number 0..1')
          }
          break
        }
      }
    })
    if (semanticCount === 0)
      fail('steps', 'flows require at least one expect or expectEvent (semantic-first policy)')
    if (captureCount > MAX_CAPTURES)
      fail('steps', `flows allow at most ${MAX_CAPTURES} capture steps`)
  }

  void scale
  return { ok: errors.length === 0, errors }
}

export function validateFile(flowPath, descriptorPath = resolveDescriptorPath(), storyPath = resolve(root, 'stories/metadata.json')) {
  let descriptor = null
  try {
    descriptor = loadDescriptor(descriptorPath)
  } catch {
    descriptor = null
  }
  const storyKeys = loadStoryKeys(storyPath)
  let doc
  try {
    doc = JSON.parse(readFileSync(flowPath, 'utf8'))
  } catch (error) {
    return { ok: false, errors: [{ path: flowPath, message: `could not read flow file: ${error.message}` }] }
  }
  return validateDocument(doc, descriptor, storyKeys)
}

const invokedAsCli = process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (invokedAsCli) {
  const [command, fileArg] = process.argv.slice(2)
  if (command !== 'check' || !fileArg) {
    console.error('usage: node scripts/flow.mjs check <flow.json>')
    process.exit(1)
  }
  const flowPath = resolveFlowPath(fileArg)
  if (!flowPath.toLowerCase().endsWith('.json')) {
    console.error(`qsm-workbench flow: not a JSON document: ${fileArg}`)
    process.exit(1)
  }
  const result = validateFile(flowPath)
  if (!result.ok) {
    console.error(`qsm-workbench flow: invalid ${flowPath}\n${formatErrors(result.errors)}`)
    process.exit(1)
  }
  console.log(`flow ok: ${flowPath}`)
}
