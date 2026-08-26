#!/usr/bin/env bash
# hf-bridge.sh — HF_* shell functions for user Scripts (Hyper+J), mirrors macOS
# HyperForge's `HF.*` JavaScript bridge (and Windows lib/HFBridge.ahk) one-for-one
# where a Linux equivalent exists. Source this at the top of a scripts/*.sh file:
#
#   source "${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}/lib/hf-bridge.sh"
#
# hf_snap <position>       — left right top bottom max center tl tr bl br
#                             third-l third-c third-r twothird-l twothird-r almost-max
#                             (same vocabulary as hyperforge-snap; delegates to it)
# hf_notify <message>
# hf_log <message>         — appends to ~/.local/share/hyperforge-linux/scripts.log
# hf_clipboard_get
# hf_clipboard_set <text>
# hf_paste_text <text>     — set clipboard then send Ctrl+V into the focused window
# hf_press_key <keys>      — xdotool/ydotool key syntax, e.g. "ctrl+shift+4"
# hf_launch_app <command>  — fire-and-forget launch (no focus-or-minimize cycle here)
# hf_run_shortcut <name>   — run ~/.config/hyperforge-linux/shortcuts/<name>.sh
# hf_sleep <seconds>

HF_ROOT="${HYPERFORGE_LINUX_ROOT:-$HOME/.local/share/hyperforge-linux}"
HF_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyperforge-linux"
HF_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyperforge-linux"

_hf_have() { command -v "$1" >/dev/null 2>&1; }

hf_snap() {
  "$HF_ROOT/bin/hyperforge-snap" "$1"
}

hf_notify() {
  if _hf_have notify-send; then
    notify-send -a HyperForge -t 1500 "HyperForge" "$1" 2>/dev/null || true
  else
    echo "$1" >&2
  fi
}

hf_log() {
  mkdir -p "$HF_DATA_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$HF_DATA_DIR/scripts.log"
}

hf_clipboard_get() {
  if _hf_have wl-paste; then wl-paste --no-newline 2>/dev/null || true
  elif _hf_have xclip; then xclip -selection clipboard -o 2>/dev/null || true
  else echo ""
  fi
}

hf_clipboard_set() {
  local t="$1"
  if _hf_have wl-copy; then printf '%s' "$t" | wl-copy
  elif _hf_have xclip; then printf '%s' "$t" | xclip -selection clipboard
  else echo "$t"
  fi
}

hf_paste_text() {
  hf_clipboard_set "$1"
  sleep 0.05
  if _hf_have wtype; then wtype -M ctrl v -m ctrl
  elif _hf_have ydotool; then ydotool key ctrl+v
  elif _hf_have xdotool; then xdotool key --clearmodifiers ctrl+v
  fi
}

hf_press_key() {
  local keys="$1"
  if _hf_have xdotool; then xdotool key --clearmodifiers "$keys"
  elif _hf_have ydotool; then ydotool key "$keys"
  else hf_notify "No key sender (xdotool/ydotool) for hf_press_key"
  fi
}

hf_launch_app() {
  ( setsid "$1" >/dev/null 2>&1 & ) 2>/dev/null || true
}

hf_run_shortcut() {
  local name="$1" path="$HF_CONF_DIR/shortcuts/$name.sh"
  if [[ -x "$path" ]]; then
    "$path"
  else
    hf_notify "No shortcut \"$name\" — add $path"
  fi
}

hf_sleep() {
  sleep "$1"
}
