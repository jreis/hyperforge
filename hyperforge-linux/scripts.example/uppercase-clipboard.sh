#!/usr/bin/env bash
# Uppercase clipboard — hf_clipboard_get / hf_clipboard_set round-trip.
set -euo pipefail
source "${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}/lib/hf-bridge.sh"

text="$(hf_clipboard_get)"
if [[ -n "$text" ]]; then
  hf_clipboard_set "${text^^}"
  hf_notify "Clipboard uppercased"
else
  hf_notify "Clipboard is empty"
fi
