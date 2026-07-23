#!/bin/zsh
# Build HyperForge.app and wrap it in a local-install DMG (drag → Applications).
# Usage:
#   ./Scripts/package-dmg.sh
#   ./Scripts/package-dmg.sh --open   # open Finder to the DMG when done
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="app.hyperforge.HyperForge"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${ROOT}/Supporting/Info.plist" 2>/dev/null || echo "0.1.0")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${ROOT}/Supporting/Info.plist" 2>/dev/null || echo "1")"

DIST="${ROOT}/dist"
STAGE="${DIST}/dmg-stage"
APP_NAME="HyperForge.app"
APP_STAGE="${STAGE}/${APP_NAME}"
DMG_NAME="HyperForge-${VERSION}.dmg"
DMG_PATH="${DIST}/${DMG_NAME}"
VOL_NAME="HyperForge ${VERSION}"

OPEN_WHEN_DONE=0
for arg in "$@"; do
  case "$arg" in
    --open|-o) OPEN_WHEN_DONE=1 ;;
    -h|--help)
      echo "Usage: $0 [--open]"
      exit 0
      ;;
  esac
done

echo "→ Building HyperForge (release)…"
cd "$ROOT"
swift build -c release

BUILD_BIN="$(swift build -c release --show-bin-path)/HyperForge"
if [[ ! -x "$BUILD_BIN" ]]; then
  echo "Build product not found at $BUILD_BIN" >&2
  exit 1
fi

echo "→ Staging ${APP_NAME}…"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "${APP_STAGE}/Contents/MacOS" "${APP_STAGE}/Contents/Resources"

cp "$BUILD_BIN" "${APP_STAGE}/Contents/MacOS/HyperForge"
chmod +x "${APP_STAGE}/Contents/MacOS/HyperForge"
cp "${ROOT}/Supporting/Info.plist" "${APP_STAGE}/Contents/Info.plist"
if [[ -f "${ROOT}/Supporting/AppIcon.icns" ]]; then
  cp "${ROOT}/Supporting/AppIcon.icns" "${APP_STAGE}/Contents/Resources/AppIcon.icns"
fi

# Strip Finder resource forks before codesign (setIcon leaves these behind).
find "${APP_STAGE}" \( -name $'Icon\r' -o -name 'Icon?' -o -name '._*' \) -delete 2>/dev/null || true
xattr -cr "${APP_STAGE}" 2>/dev/null || true

# Optional: ship Karabiner pack next to the app for easy enable
KARABINER_DIR="${STAGE}/Karabiner Rules (optional)"
mkdir -p "$KARABINER_DIR"
cp "${ROOT}/Config/karabiner-caps-to-f18.json" \
  "${KARABINER_DIR}/hyperforge_caps_to_f18.json"
cp "${ROOT}/Config/karabiner-hyper-slash-to-f19.json" \
  "${KARABINER_DIR}/hyperforge_help_f19.json" 2>/dev/null || true
cp "${ROOT}/Config/karabiner-hyper-comma-to-f20.json" \
  "${KARABINER_DIR}/hyperforge_dashboard_f20.json" 2>/dev/null || true

cat > "${STAGE}/Install Notes.txt" <<EOF
HyperForge ${VERSION} (${BUILD})
Local-first Hyper Key automation for macOS

Install
=======
1. Drag HyperForge.app into Applications (or ~/Applications).
2. Open HyperForge once (menu bar flame icon).
3. System Settings → Privacy & Security → Accessibility → enable HyperForge.
4. Karabiner-Elements (optional but recommended):
   • Copy JSON from "Karabiner Rules (optional)" into
     ~/.config/karabiner/assets/complex_modifications/
   • Or open HyperForge → Karabiner / Doctor → Install recommended pack
   • Enable Caps→F18 (or your 4-mod Caps rule) + F19/F20 bridges if needed

Launch at login (optional)
==========================
  open -a HyperForge
  # or re-run Scripts/install.sh from the source tree for a LaunchAgent

Logs
====
  /tmp/hyperforge.log
  /tmp/hyperforge-events.log

© Jason Reis · MIT
EOF

# Drag-to-install convenience
ln -sf /Applications "${STAGE}/Applications"

echo "→ Ad-hoc codesign (${BUNDLE_ID})…"
codesign --force --deep --sign - \
  --identifier "${BUNDLE_ID}" \
  --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
  "$APP_STAGE"

echo "→ Creating ${DMG_PATH}…"
mkdir -p "$DIST"
# UDZO = compressed read-only disk image suitable for local install
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Optional: sign the DMG the same ad-hoc way (Gatekeeper still warns; fine for local)
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true

# Clean stage (keep DMG)
rm -rf "$STAGE"

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "✓ DMG ready"
echo "  ${DMG_PATH}  (${SIZE})"
echo ""
echo "Install: open the DMG → drag HyperForge.app to Applications"
echo "Then grant Accessibility to HyperForge."

if [[ "$OPEN_WHEN_DONE" -eq 1 ]]; then
  open -R "$DMG_PATH"
fi
