#!/usr/bin/env bash
# Snap left and notify — hf_snap + hf_notify together.
set -euo pipefail
source "${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}/lib/hf-bridge.sh"

hf_snap left
hf_notify "Snapped left"
