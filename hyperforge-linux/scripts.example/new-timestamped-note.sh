#!/usr/bin/env bash
# New timestamped note — hf_launch_app + hf_sleep + hf_paste_text.
# Adjust the editor command for whatever's installed on this machine.
set -euo pipefail
source "${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}/lib/hf-bridge.sh"

stamp="$(date '+%Y-%m-%d %H:%M:%S')"
hf_launch_app gedit
hf_sleep 0.4
hf_paste_text "Note — ${stamp}"$'\n'
