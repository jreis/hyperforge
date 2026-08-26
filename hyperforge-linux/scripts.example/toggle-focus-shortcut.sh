#!/usr/bin/env bash
# Toggle Focus (Shortcut) — hf_run_shortcut runs a named script from the shortcuts/ folder.
set -euo pipefail
source "${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}/lib/hf-bridge.sh"

hf_run_shortcut "Toggle Focus"
hf_sleep 0.2
hf_notify "Focus toggled"
