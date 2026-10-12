import { readdirSync, symlinkSync } from 'node:fs'
import { basename, resolve } from 'node:path'

// Quickshell resolves qs.* beside its entry file and pre-scans uppercase QML
// there before loading the adapter. Mirror namespaces and the adapter into the
// isolated host root without writing to the provider. Import segments cannot
// contain dots, so dot-free names are precisely its namespace roots.
export function mirrorQuickshellConfigRoot(dir, provider) {
  const namespaces = readdirSync(provider.workbenchDir).filter(name => !name.includes('.'))
  for (const name of [...namespaces, basename(provider.paths.adapter)])
    symlinkSync(resolve(provider.workbenchDir, name), resolve(dir, name))
}
