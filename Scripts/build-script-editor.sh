#!/bin/zsh
# Rebuilds the CodeMirror + vim-mode bundle used by the Scripts settings pane.
# Not part of `swift build` — run this after changing WebAssets/script-editor/src/editor.js,
# then commit the regenerated Sources/HyperForge/Resources/ScriptEditor/editor.bundle.js.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}/WebAssets/script-editor"

if [[ ! -d node_modules ]]; then
  echo "→ Installing editor build dependencies…"
  npm install
fi

echo "→ Building editor.bundle.js…"
npm run build
echo "✓ Wrote Sources/HyperForge/Resources/ScriptEditor/editor.bundle.js"
