#!/bin/zsh
# HyperForge installer — builds, packages as .app, optional LaunchAgent.
# Adapted from the production install_hyperkey.sh flow.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${HOME}/Applications/HyperForge.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
BIN="${MACOS_DIR}/HyperForge"
PLIST="${HOME}/Library/LaunchAgents/app.hyperforge.plist"
BUNDLE_ID="app.hyperforge.HyperForge"
LABEL="app.hyperforge"

echo "→ Building HyperForge (release)…"
cd "$ROOT"
swift build -c release

BUILD_BIN="$(swift build -c release --show-bin-path)/HyperForge"
if [[ ! -x "$BUILD_BIN" ]]; then
  echo "Build product not found at $BUILD_BIN" >&2
  exit 1
fi

echo "→ Packaging ${APP_DIR}…"
mkdir -p "$MACOS_DIR" "${APP_DIR}/Contents/Resources"
cp "$BUILD_BIN" "$BIN"
chmod +x "$BIN"

# Bundle Info.plist (menu bar accessory, Accessibility description)
cp "${ROOT}/Supporting/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Ad-hoc sign with stable identifier so TCC Accessibility persists across rebuilds.
codesign --force --deep --sign - \
  --identifier "${BUNDLE_ID}" \
  --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
  "$APP_DIR"

# Optional Karabiner rule pack (Caps→F18 + F19 help + F20 dashboard)
if [[ -d "${HOME}/.config/karabiner" ]]; then
  ASSET_DIR="${HOME}/.config/karabiner/assets/complex_modifications"
  mkdir -p "$ASSET_DIR"
  cp "${ROOT}/Config/karabiner-caps-to-f18.json" "${ASSET_DIR}/hyperforge_caps_to_f18.json"
  if [[ -f "${ROOT}/Config/karabiner-hyper-slash-to-f19.json" ]]; then
    cp "${ROOT}/Config/karabiner-hyper-slash-to-f19.json" "${ASSET_DIR}/hyperforge_help_f19.json"
  fi
  if [[ -f "${ROOT}/Config/karabiner-hyper-comma-to-f20.json" ]]; then
    cp "${ROOT}/Config/karabiner-hyper-comma-to-f20.json" "${ASSET_DIR}/hyperforge_dashboard_f20.json"
  fi
  echo "→ Installed Karabiner pack (Caps→F18, F19 help, F20 dashboard) — enable in Karabiner UI"
fi

# LaunchAgent (login start)
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/hyperforge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/hyperforge.err</string>
</dict>
</plist>
EOF

UID_NUM="$(id -u)"
# Drop legacy label if present
launchctl bootout "gui/${UID_NUM}/dev.jasonreis.hyperforge" 2>/dev/null || true
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
: > /tmp/hyperforge.log
: > /tmp/hyperforge.err
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}"

cat <<MSG

✓ HyperForge installed.

  App:     ${APP_DIR}
  Engine:  F18 / 4-mod Hyper (Caps via Karabiner) · Right ⌘ Vim
  Logs:    /tmp/hyperforge.log  /tmp/hyperforge-events.log

Grant Accessibility to:
  ${APP_DIR}

Karabiner → Complex Modifications — enable:
  • Caps Lock to F18 (or your existing 4-mod Caps Hyper)
  • Hyper + / help (F19) and Hyper + , dashboard (F20) if using 4-mod
  Tap Caps alone → Escape · hold Caps + key → Hyper

Open Doctor in the app for a setup health check.
Open dashboard anytime from the menu bar flame icon.
MSG
