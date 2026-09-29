import { readFileSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadProvider, resolveProviderRoot } from './provider.mjs'

// Version 1 composition document validator. Direct, dependency-free, and kept
// in this one module: strict allowlists at every level, bounded ids/viewport/
// depth/count, descriptor-typed props, child policy, named links only, and no
// executable content (no source paths, scripts, expressions, or link args).

const root = resolve(import.meta.dirname, '..')

export const COMPOSITION_VERSION = 1
export const MAX_NODES = 64
export const MAX_DEPTH = 8
export const VIEWPORT_BOUNDS = { minWidth: 320, maxWidth: 3840, minHeight: 240, maxHeight: 2160 }

const idPattern = /^[a-z0-9][a-z0-9-]{0,63}$/
const documentFields = new Set(['version', 'key', 'viewport', 'root', 'links'])
const nodeFields = new Set(['id', 'type', 'props', 'children'])
const linkFields = new Set(['from', 'to'])
const endpointFields = { from: new Set(['node', 'event']), to: new Set(['node', 'action']) }

// Field names that never appear in a data-only document. The strict allowlists
// below already reject them; this list only produces a clearer diagnostic.
const executableFieldPattern = /^(source|sourceurl|qml|url|path|file|script|javascript|js|expression|binding|command|exec|shell|eval|args|arguments|code|payload|handler|callback|component|loader|import|require)$/i

// Payload markers that have no business inside declared free-text props.
const executableValuePatterns = [/\.qml(\W|$)/i, /file:\/\//i, /\bqrc:/i, /import\s+Qt\w*/, /<script/i, /javascript:/i, /\$\{/, /function\s*\(/, /__proto__/, /constructor\s*\./]

export function resolveDescriptorPath(providerRoot = resolveProviderRoot()) {
  return loadProvider(providerRoot).paths.compositionTypes
}

export function loadDescriptor(descriptorPath = resolveDescriptorPath()) {
  return JSON.parse(readFileSync(descriptorPath, 'utf8'))
}

export function resolveCompositionPath(value) {
  if (typeof value !== 'string' || value.trim() === '') return null
  return isAbsolute(value) ? resolve(value) : resolve(root, value)
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
    if (!allowed.has(field)) {
      errors.push({
        path: at,
        message: executableFieldPattern.test(field)
          ? `${at} is executable content and is not allowed in composition documents`
          : `${at} is not a known field`,
      })
    }
  }
}

function checkPropValue(prop, spec, value, path, tokens, errors) {
  checkExecutableValue(value, path, errors)
  switch (spec.type) {
    case 'boolean':
      if (typeof value !== 'boolean') errors.push({ path, message: `${path} must be a boolean` })
      break
    case 'string':
      if (typeof value !== 'string') errors.push({ path, message: `${path} must be a string` })
      else if (spec.maxLength !== undefined && value.length > spec.maxLength)
        errors.push({ path, message: `${path} exceeds max length ${spec.maxLength}` })
      break
    case 'number': {
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        errors.push({ path, message: `${path} must be a finite number` })
        break
      }
      if (spec.integer && !Number.isInteger(value)) errors.push({ path, message: `${path} must be an integer` })
      if (spec.min !== undefined && value < spec.min) errors.push({ path, message: `${path} is below minimum ${spec.min}` })
      if (spec.max !== undefined && value > spec.max) errors.push({ path, message: `${path} is above maximum ${spec.max}` })
      break
    }
    case 'enum':
      if (typeof value !== 'string' || !spec.values.includes(value))
        errors.push({ path, message: `${path} must be one of: ${spec.values.join(', ')}` })
      break
    case 'spacing':
      if (typeof value !== 'string' || !tokens.includes(value))
        errors.push({ path, message: `${path} must be one of: ${tokens.join(', ')}` })
      break
    default:
      errors.push({ path, message: `${path} has an unknown descriptor type '${spec.type}'` })
  }
}

export function validateDocument(doc, descriptor) {
  const errors = []
  const fail = (path, message) => errors.push({ path, message })
  if (!isPlainObject(doc)) {
    fail('$', 'composition document must be a JSON object')
    return { ok: false, errors }
  }
  checkFields(doc, documentFields, '', errors)

  if (doc.version !== COMPOSITION_VERSION)
    fail('version', `version must be exactly ${COMPOSITION_VERSION}`)

  if (typeof doc.key !== 'string' || !idPattern.test(doc.key))
    fail('key', 'key must be stable kebab-case (lowercase alphanumerics and dashes, max 64 chars)')
  else checkExecutableValue(doc.key, 'key', errors)

  const vp = doc.viewport
  if (!Array.isArray(vp) || vp.length !== 2) {
    fail('viewport', 'viewport must be a two-number array [width, height]')
  } else {
    const [w, h] = vp
    const b = VIEWPORT_BOUNDS
    if (!Number.isInteger(w) || w < b.minWidth || w > b.maxWidth)
      fail('viewport[0]', `viewport width must be an integer ${b.minWidth}..${b.maxWidth}`)
    if (!Number.isInteger(h) || h < b.minHeight || h > b.maxHeight)
      fail('viewport[1]', `viewport height must be an integer ${b.minHeight}..${b.maxHeight}`)
  }

  const types = isPlainObject(descriptor?.types) ? descriptor.types : {}
  const tokens = Array.isArray(descriptor?.tokens) ? descriptor.tokens : []
  const seen = new Map()
  const nodeTypes = new Map()
  let count = 0

  function checkNode(node, path, depth) {
    count += 1
    if (count > MAX_NODES) {
      fail(path, `composition exceeds ${MAX_NODES} nodes`)
      return
    }
    if (depth > MAX_DEPTH) {
      fail(path, `composition exceeds depth ${MAX_DEPTH}`)
      return
    }
    if (!isPlainObject(node)) {
      fail(path, 'node must be an object')
      return
    }
    checkFields(node, nodeFields, path, errors)

    const at = (field) => (path ? `${path}.${field}` : field)
    if (typeof node.id !== 'string' || !idPattern.test(node.id)) {
      fail(at('id'), 'node id must be stable kebab-case (lowercase alphanumerics and dashes, max 64 chars)')
    } else {
      checkExecutableValue(node.id, at('id'), errors)
      if (seen.has(node.id)) fail(at('id'), `duplicate node id '${node.id}' (first seen at ${seen.get(node.id)})`)
      else seen.set(node.id, path || 'root')
    }

    const spec = types[node.type]
    if (typeof node.type !== 'string' || !spec) {
      fail(at('type'), `unknown node type '${node.type}'`)
      return
    }
    nodeTypes.set(node.id, node.type)

    const props = node.props ?? {}
    if (!isPlainObject(props)) {
      fail(at('props'), 'props must be an object')
    } else {
      const declared = isPlainObject(spec.props) ? spec.props : {}
      for (const field of Object.keys(props)) {
        const fieldPath = `${at('props')}.${field}`
        if (!Object.hasOwn(declared, field)) {
          fail(fieldPath, executableFieldPattern.test(field)
            ? `${fieldPath} is executable content and is not allowed in composition documents`
            : `${fieldPath} is not a declared property of type '${node.type}'`)
        } else {
          checkPropValue(field, declared[field], props[field], fieldPath, tokens, errors)
        }
      }
    }

    const allowsChildren = spec.children === 'many'
    if (node.children === undefined) return
    if (!Array.isArray(node.children)) {
      fail(at('children'), 'children must be an array')
      return
    }
    if (!allowsChildren && node.children.length > 0) {
      fail(at('children'), `type '${node.type}' does not accept children`)
      return
    }
    node.children.forEach((child, index) => checkNode(child, `${at('children')}[${index}]`, depth + 1))
  }

  if (!isPlainObject(doc.root)) fail('root', 'root must be a node object')
  else checkNode(doc.root, 'root', 1)

  const links = doc.links ?? []
  if (!Array.isArray(links)) {
    fail('links', 'links must be an array')
  } else {
    links.forEach((link, index) => {
      const path = `links[${index}]`
      if (!isPlainObject(link)) {
        fail(path, 'link must be an object')
        return
      }
      checkFields(link, linkFields, path, errors)
      for (const end of ['from', 'to']) {
        const ep = link[end]
        const epPath = `${path}.${end}`
        if (!isPlainObject(ep)) {
          fail(epPath, `link ${end} must be an object`)
          continue
        }
        checkFields(ep, endpointFields[end], epPath, errors)
        if (typeof ep.node !== 'string' || !seen.has(ep.node)) {
          fail(`${epPath}.node`, `link ${end} references unknown node '${ep.node}'`)
          continue
        }
        checkExecutableValue(ep.node, `${epPath}.node`, errors)
        const type = nodeTypes.get(ep.node)
        const declared = (type && types[type]?.[end === 'from' ? 'events' : 'actions']) ?? []
        const name = end === 'from' ? ep.event : ep.action
        const nameField = end === 'from' ? 'event' : 'action'
        if (typeof name !== 'string' || !declared.includes(name)) {
          fail(`${epPath}.${nameField}`, `link ${end} names undeclared ${nameField} '${name}' for node '${ep.node}' of type '${type}'`)
        } else {
          checkExecutableValue(name, `${epPath}.${nameField}`, errors)
        }
      }
    })
  }

  return { ok: errors.length === 0, errors }
}

export function validateFile(docPath, descriptorPath = resolveDescriptorPath()) {
  let descriptor
  try {
    descriptor = loadDescriptor(descriptorPath)
  } catch (error) {
    return { ok: false, errors: [{ path: descriptorPath, message: `could not read descriptor: ${error.message}` }] }
  }
  let doc
  try {
    doc = JSON.parse(readFileSync(docPath, 'utf8'))
  } catch (error) {
    return { ok: false, errors: [{ path: docPath, message: `could not read composition file: ${error.message}` }] }
  }
  return validateDocument(doc, descriptor)
}

export function formatErrors(errors) {
  return errors.map((error) => `${error.path}: ${error.message}`).join('\n')
}

const invokedAsCli = process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (invokedAsCli) {
  const raw = process.argv.slice(2)
  const providerIndex = raw.indexOf('--provider')
  const providerRoot = providerIndex >= 0 ? raw[providerIndex + 1] : undefined
  if (providerIndex >= 0) raw.splice(providerIndex, 2)
  const [command, fileArg] = raw
  if (command !== 'check' || !fileArg) {
    console.error('usage: node scripts/composition.mjs check <composition.json> --provider <provider-root>')
    process.exit(1)
  }
  const docPath = resolveCompositionPath(fileArg)
  if (!docPath.toLowerCase().endsWith('.json')) {
    console.error(`qsm-workbench composition: not a JSON document: ${fileArg}`)
    process.exit(1)
  }
  const result = validateFile(docPath, resolveDescriptorPath(providerRoot ? resolveProviderRoot(providerRoot) : undefined))
  if (!result.ok) {
    console.error(`qsm-workbench composition: invalid ${docPath}\n${formatErrors(result.errors)}`)
    process.exit(1)
  }
  console.log(`composition ok: ${docPath}`)
}
