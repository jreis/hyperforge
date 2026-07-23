#!/bin/zsh
# HyperForge installer — builds, packages as .app, optional LaunchAgent.
# Builds a signed .app under ~/Applications (or /Applications with flags).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer /Applications (what Dock/Spotlight often resolve) when writable.
if [[ -w /Applications ]] || [[ -w /Applications/HyperForge.app ]]; then
  APP_DIR="/Applications/HyperForge.app"
else
  APP_DIR="${HOME}/Applications/HyperForge.app"
fi
MACOS_DIR="${APP_DIR}/Contents/MacOS"
BIN="${MACOS_DIR}/HyperForge"
PLIST="${HOME}/Library/LaunchAgents/app.hyperforge.plist"
BUNDLE_ID="app.hyperforge.HyperForge"
LABEL="app.hyperforge"
UID_NUM="$(id -u)"
DOMAIN="gui/${UID_NUM}"
SERVICE="${DOMAIN}/${LABEL}"

echo "→ Building HyperForge (release)…"
cd "$ROOT"
swift build -c release

BUILD_BIN="$(swift build -c release --show-bin-path)/HyperForge"
if [[ ! -x "$BUILD_BIN" ]]; then
  echo "Build product not found at $BUILD_BIN" >&2
  exit 1
fi

# Quit so we can replace the bundle cleanly.
killall HyperForge 2>/dev/null || true
sleep 0.3

# Drop a stale twin so icons/launch don't point at the other copy.
if [[ "$APP_DIR" == "/Applications/HyperForge.app" && -d "${HOME}/Applications/HyperForge.app" ]]; then
  echo "→ Removing duplicate ${HOME}/Applications/HyperForge.app"
  rm -rf "${HOME}/Applications/HyperForge.app"
elif [[ "$APP_DIR" == "${HOME}/Applications/HyperForge.app" && -d "/Applications/HyperForge.app" ]]; then
  echo "→ Note: /Applications/HyperForge.app also exists — remove it if Dock shows the old icon"
fi

echo "→ Packaging ${APP_DIR}…"
# Full replace — avoids leftover Icon\r / xattrs that break codesign.
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "${APP_DIR}/Contents/Resources"
cp "$BUILD_BIN" "$BIN"
chmod +x "$BIN"

# Bundle Info.plist (menu bar accessory, Accessibility description)
cp "${ROOT}/Supporting/Info.plist" "${APP_DIR}/Contents/Info.plist"
# App icon (.icns inside Resources — CFBundleIconFile)
if [[ -f "${ROOT}/Supporting/AppIcon.icns" ]]; then
  cp "${ROOT}/Supporting/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# codesign rejects resource forks / FinderInfo (from prior setIcon or copy).
strip_codesign_detritus() {
  local app="$1"
  # Custom Finder icon is literally "Icon" + CR (Apple's convention).
  find "$app" \( -name $'Icon\r' -o -name 'Icon?' -o -name '._*' \) -delete 2>/dev/null || true
  rm -f "$app"/Icon$'\r' 2>/dev/null || true
  xattr -cr "$app" 2>/dev/null || true
}
strip_codesign_detritus "$APP_DIR"

# Ad-hoc sign with stable identifier so TCC Accessibility persists across rebuilds.
codesign --force --deep --sign - \
  --identifier "${BUNDLE_ID}" \
  --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
  "$APP_DIR"

# Finder custom icon AFTER signing (must not run before codesign).
# This can make `codesign -v` complain about unsealed Icon\r; the app still runs.
if [[ -f "${ROOT}/docs/hyperforge-icon.png" ]]; then
  swift -e "
import AppKit
let app = \"${APP_DIR}\"
let png = \"${ROOT}/docs/hyperforge-icon.png\"
if let img = NSImage(contentsOfFile: png) {
  _ = NSWorkspace.shared.setIcon(img, forFile: app, options: [])
}
" 2>/dev/null || true
fi

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

# LaunchAgent: open the .app (proper GUI/TCC path) rather than the raw binary.
# LimitLoadToSessionType as a string is more compatible than an array on newer launchd.
mkdir -p "${HOME}/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>${APP_DIR}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/hyperforge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/hyperforge.err</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null

install_launch_agent() {
  # Tear down any previous registration (ignore errors).
  launchctl bootout "${SERVICE}" 2>/dev/null || true
  # Older local installs used a different LaunchAgent label.
  launchctl bootout "gui/${UID_NUM}/app.hyperforge.legacy" 2>/dev/null || true
  launchctl unload "$PLIST" 2>/dev/null || true

  : > /tmp/hyperforge.log
  : > /tmp/hyperforge.err

  # Prefer modern bootstrap; fall back to load -w (still works in many sessions).
  if launchctl bootstrap "${DOMAIN}" "$PLIST" 2>/tmp/hyperforge-launchctl.err; then
    launchctl enable "${SERVICE}" 2>/dev/null || true
    launchctl kickstart -k "${SERVICE}" 2>/dev/null \
      || launchctl kickstart "${SERVICE}" 2>/dev/null \
      || true
    return 0
  fi

  if launchctl load -w "$PLIST" 2>>/tmp/hyperforge-launchctl.err; then
    return 0
  fi

  return 1
}

AGENT_OK=0
if install_launch_agent; then
  AGENT_OK=1
  echo "→ LaunchAgent loaded (${LABEL}) — starts at login"
else
  echo "→ LaunchAgent not loaded (login start skipped)"
  if [[ -s /tmp/hyperforge-launchctl.err ]]; then
    echo "  launchctl said: $(tr '\n' ' ' </tmp/hyperforge-launchctl.err)"
  fi
  echo "  You can still open the app now; add Login Items manually if you want auto-start."
fi

# Always launch (or activate) the packaged app — never force a second instance (-n).
echo "→ Opening HyperForge…"
open "$APP_DIR" || true

cat <<MSG

✓ HyperForge installed.

  App:     ${APP_DIR}
  Engine:  F18 / 4-mod Hyper (Caps via Karabiner) · Right ⌘ Vim
  Logs:    /tmp/hyperforge.log  /tmp/hyperforge-events.log
  Login:   $([[ "$AGENT_OK" -eq 1 ]] && echo "LaunchAgent enabled" || echo "manual — System Settings → Login Items, or re-run after reboot")

Grant Accessibility to:
  ${APP_DIR}

Karabiner → Complex Modifications — enable:
  • Caps Lock to F18 (or your existing 4-mod Caps Hyper)
  • Hyper + / help (F19) and Hyper + , dashboard (F20) if using 4-mod
  Tap Caps alone → Escape · hold Caps + key → Hyper

Open Doctor in the app for a setup health check.
Open dashboard anytime from the menu bar flame icon.
MSG
