#!/usr/bin/env bash
# HyperForge Linux installer — configs + snap helpers (not a full GUI port).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/hyperforge-linux"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
KANATA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kanata"
SYSTEMD_USER="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "→ Installing HyperForge Linux → $SHARE"

HF_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyperforge-linux"

mkdir -p "$SHARE/bin" "$BIN_DIR" "$KANATA_DIR" "$HF_CONFIG_DIR"

# Scripts
for f in hyperforge-snap hyperforge-action hyperforge-doctor hyperforge-snippet hyperforge-clip hyperforge-pin hyperforge-paste hyperforge-bar hyperforge-config; do
  cp "$ROOT/bin/$f" "$SHARE/bin/$f"
  chmod +x "$SHARE/bin/$f"
  ln -sfn "$SHARE/bin/$f" "$BIN_DIR/$f"
done

# Snippets config (only seed it — never overwrite personal edits)
if [[ -f "$ROOT/snippets.example.conf" ]] && [[ ! -f "$HF_CONFIG_DIR/snippets.conf" ]]; then
  cp "$ROOT/snippets.example.conf" "$HF_CONFIG_DIR/snippets.conf"
  echo "→ snippets config: $HF_CONFIG_DIR/snippets.conf"
fi

# Kanata config with absolute bin path
if [[ -f "$ROOT/kanata/hyperforge.kbd" ]]; then
  sed "s|HF_BIN|$SHARE/bin|g" "$ROOT/kanata/hyperforge.kbd" >"$KANATA_DIR/hyperforge.kbd"
  echo "→ kanata config: $KANATA_DIR/hyperforge.kbd"
fi

# keyd template (system path — user must sudo)
if [[ -f "$ROOT/keyd/hyperforge.conf" ]]; then
  sed "s|HF_BIN|$SHARE/bin|g" "$ROOT/keyd/hyperforge.conf" >"$SHARE/keyd-hyperforge.conf"
  echo "→ keyd template: $SHARE/keyd-hyperforge.conf"
  echo "  (optional) sudo cp $SHARE/keyd-hyperforge.conf /etc/keyd/hyperforge.conf && sudo keyd reload"
fi

# systemd user unit
mkdir -p "$SYSTEMD_USER"
if [[ -f "$ROOT/systemd/hyperforge-kanata.service" ]]; then
  cp "$ROOT/systemd/hyperforge-kanata.service" "$SYSTEMD_USER/hyperforge-kanata.service"
  # cargo installs to ~/.cargo/bin, which is often missing from this script's PATH
  KANATA_PATH=""
  if command -v kanata >/dev/null 2>&1; then
    KANATA_PATH="$(command -v kanata)"
  elif [[ -x "$HOME/.cargo/bin/kanata" ]]; then
    KANATA_PATH="$HOME/.cargo/bin/kanata"
  elif [[ -x /usr/bin/kanata ]]; then
    KANATA_PATH="/usr/bin/kanata"
  fi
  if [[ -n "$KANATA_PATH" ]]; then
    sed -i.bak "s|%h/.local/bin/kanata|$KANATA_PATH|g" "$SYSTEMD_USER/hyperforge-kanata.service" 2>/dev/null \
      || sed -i '' "s|%h/.local/bin/kanata|$KANATA_PATH|g" "$SYSTEMD_USER/hyperforge-kanata.service" 2>/dev/null \
      || true
    rm -f "$SYSTEMD_USER/hyperforge-kanata.service.bak"
  fi
  echo "→ systemd user unit: hyperforge-kanata.service"
fi
if [[ -f "$ROOT/systemd/hyperforge-clipboard.service" ]]; then
  cp "$ROOT/systemd/hyperforge-clipboard.service" "$SYSTEMD_USER/hyperforge-clipboard.service"
  echo "→ systemd user unit: hyperforge-clipboard.service (clipboard history watcher)"
fi
if [[ -f "$ROOT/systemd/hyperforge-snippets.service" ]]; then
  cp "$ROOT/systemd/hyperforge-snippets.service" "$SYSTEMD_USER/hyperforge-snippets.service"
  echo "→ systemd user unit: hyperforge-snippets.service (compile typed snippet sequences)"
fi
if [[ -f "$ROOT/systemd/hyperforge-snippets.path" ]]; then
  cp "$ROOT/systemd/hyperforge-snippets.path" "$SYSTEMD_USER/hyperforge-snippets.path"
  echo "→ systemd user unit: hyperforge-snippets.path (recompile when snippets.conf changes)"
fi

export HYPERFORGE_LINUX_ROOT="$SHARE"
# macOS-default typed triggers (@@, ,sig, …) + kanata sequence file
if [[ -x "$SHARE/bin/hyperforge-snippet" ]]; then
  "$SHARE/bin/hyperforge-snippet" --seed || true
  "$SHARE/bin/hyperforge-snippet" --sync || true
fi
# Persist for shells
ENV_LINE="export HYPERFORGE_LINUX_ROOT=\"$SHARE\""
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rc" ]] && ! grep -q 'HYPERFORGE_LINUX_ROOT' "$rc" 2>/dev/null; then
    echo "" >>"$rc"
    echo "# HyperForge Linux" >>"$rc"
    echo "$ENV_LINE" >>"$rc"
  fi
done

echo
echo "✓ Installed."
echo
echo "Next steps:"
echo "  1. Install kanata:  https://github.com/jtroo/kanata/releases"
echo "     cargo:  cargo install kanata --features cmd"
echo "     (plain \`cargo install kanata\` cannot run HyperForge's (cmd ...) actions)"
echo "  2. Keyboard access: sudo usermod -aG input \"\$USER\"  (then log out)."
echo "     Without this, kanata often only sees a 'System Control' interface and"
echo "     Caps/Space chords do nothing. Also ensure /dev/uinput is writable."
echo "  3. Run once:       kanata -c $KANATA_DIR/hyperforge.kbd"
echo "  4. Autostart:      systemctl --user enable --now hyperforge-kanata.service"
echo "  5. Clipboard history (optional): systemctl --user enable --now hyperforge-clipboard.service"
echo "  6. Typed snippets (optional):    systemctl --user enable --now hyperforge-snippets.path"
echo "  7. Edit snippets:  $HF_CONFIG_DIR/snippets.conf   then: hyperforge-snippet --sync"
echo "  8. Health check:   hyperforge-doctor"
echo
echo "Try:"
echo "  • Hold Caps + ←/→/↑/↓  — window snap"
echo "  • Hold Caps + -/=/\\    — left/right third · i/o two-thirds · y almost-max"
echo "  • Type @@              — email snippet · Caps + , — snippet picker · Caps + P — clipboard"
echo "  • Hold Space + H/J/K/L — arrows"
echo "  • Tap Caps             — Escape"
echo "  • Tap Space            — space"
echo
hyperforge-doctor 2>/dev/null || "$SHARE/bin/hyperforge-doctor" || true
