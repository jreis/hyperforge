#!/usr/bin/env bash
# Say hello — minimal example: one HF call.
set -euo pipefail
source "${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}/lib/hf-bridge.sh"

hf_notify "Hello from HyperForge"
