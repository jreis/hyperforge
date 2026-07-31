#!/bin/zsh
# Build HyperForge.app and wrap it in a DMG (drag → Applications).
#
# Usage:
#   ./Scripts/package-dmg.sh
#   ./Scripts/package-dmg.sh --open
#   CODESIGN_IDENTITY="Developer ID Application: …" ./Scripts/package-dmg.sh --notarize
#
# Signing
#   Default: ad-hoc (`-`). Fine for local install; Gatekeeper blocks *downloaded* ad-hoc apps.
#   For GitHub / web downloads without “macOS cannot verify” warnings you need:
#     1. Apple Developer Program ($99/yr)
#     2. Developer ID Application certificate in the keychain
#     3. notarytool credentials (once):  xcrun notarytool store-credentials hyperforge …
#     4. CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#          ./Scripts/package-dmg.sh --notarize
#
# Env
#   CODESIGN_IDENTITY   codesign -s identity (default: -)
#   NOTARY_PROFILE      notarytool keychain profile (default: hyperforge)
#   SKIP_NOTARIZE=1     with --notarize, only sign (skip upload)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="app.hyperforge.HyperForge"
ENTITLEMENTS="${ROOT}/Supporting/HyperForge.entitlements"
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

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-hyperforge}"

OPEN_WHEN_DONE=0
DO_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --open|-o) OPEN_WHEN_DONE=1 ;;
    --notarize) DO_NOTARIZE=1 ;;
    -h|--help)
      cat <<'HELP'
Usage: package-dmg.sh [--open] [--notarize]

  --open       Reveal the DMG in Finder when done
  --notarize   Notarize + staple (requires Developer ID + notarytool profile)

Environment:
  CODESIGN_IDENTITY   Signing identity (default: - ad-hoc)
  NOTARY_PROFILE      notarytool keychain profile (default: hyperforge)
  SKIP_NOTARIZE=1     Sign for distribution but skip notary upload

Ad-hoc DMGs work for local installs. Downloads need Developer ID + notarization
or users must right-click → Open / clear quarantine (see Install Notes).
HELP
      exit 0
      ;;
  esac
done

is_adhoc() {
  [[ "$CODESIGN_IDENTITY" == "-" || "$CODESIGN_IDENTITY" == "ad-hoc" || -z "$CODESIGN_IDENTITY" ]]
}

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
if [[ -f "$ENTITLEMENTS" ]]; then
  cp "$ENTITLEMENTS" "${APP_STAGE}/Contents/Resources/HyperForge.entitlements"
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

if is_adhoc; then
  GATEKEEPER_NOTES=$(cat <<'EOF'
If macOS says HyperForge “cannot be opened” / “developer cannot be verified”
============================================================================
This build is ad-hoc signed (open source / local). Downloaded copies are
quarantined by macOS Gatekeeper. Pick one:

  A) Right-click HyperForge.app → Open → Open (once)

  B) Terminal (after dragging to Applications):
       xattr -cr /Applications/HyperForge.app
       open /Applications/HyperForge.app

  C) System Settings → Privacy & Security → scroll to the blocked-app
     message → “Open Anyway”

To ship DMGs that open cleanly for everyone, the maintainer must sign with a
Developer ID certificate and notarize (see Scripts/package-dmg.sh --help).
EOF
)
else
  GATEKEEPER_NOTES=$(cat <<'EOF'
Gatekeeper
==========
This build is signed with a Developer ID certificate. After notarization it
should open without “unidentified developer” warnings. If something still
blocks it, run:  xattr -cr /Applications/HyperForge.app
EOF
)
fi

cat > "${STAGE}/Install Notes.txt" <<EOF
HyperForge ${VERSION} (${BUILD})
Local-first Hyper Key automation for macOS

Install
=======
1. Drag HyperForge.app into Applications (or ~/Applications).
2. Open HyperForge once (menu bar flame icon).
3. System Settings → Privacy & Security → Accessibility → enable HyperForge.
4. Karabiner-Elements (optional but recommended):
   • Open HyperForge → Doctor → Install recommended pack
     (enables Caps→F18 + F19/F20 on your active Karabiner profile)
   • Or copy JSON from "Karabiner Rules (optional)" into
     ~/.config/karabiner/assets/complex_modifications/ and
     enable via Complex Modifications → Add predefined rule
   • Enable Caps→F18 (or your 4-mod Caps rule) + F19/F20 bridges if needed

${GATEKEEPER_NOTES}

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

sign_app() {
  local app="$1"
  local identity="$2"
  echo "→ Codesign (${identity}) ${BUNDLE_ID}…"
  local -a extra=()
  if ! is_adhoc; then
    # Hardened Runtime required for notarization.
    extra+=(--options runtime --timestamp)
  fi
  if [[ -f "$ENTITLEMENTS" ]]; then
    extra+=(--entitlements "$ENTITLEMENTS")
  fi
  # Ad-hoc: stable identifier + designated requirement so Accessibility can stick.
  if is_adhoc; then
    codesign --force --deep --sign "$identity" \
      --identifier "${BUNDLE_ID}" \
      --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
      "${extra[@]}" \
      "$app"
  else
    codesign --force --deep --sign "$identity" \
      --identifier "${BUNDLE_ID}" \
      "${extra[@]}" \
      "$app"
  fi
  codesign --verify --verbose=2 "$app"
}

sign_app "$APP_STAGE" "$CODESIGN_IDENTITY"

echo "→ Creating ${DMG_PATH}…"
mkdir -p "$DIST"
# UDZO = compressed read-only disk image
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Sign the DMG itself (Developer ID Application; same identity as the app).
if is_adhoc; then
  codesign --force --sign - "$DMG_PATH" 2>/dev/null || true
else
  echo "→ Codesign DMG…"
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  if is_adhoc; then
    echo "error: --notarize requires CODESIGN_IDENTITY=Developer ID Application: …" >&2
    echo "  (ad-hoc signatures cannot be notarized by Apple)" >&2
    exit 1
  fi
  if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "→ SKIP_NOTARIZE=1 — signed only, not submitted"
  else
    echo "→ Notarizing with profile '${NOTARY_PROFILE}' (this can take a few minutes)…"
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
    echo "→ Stapling notarization ticket…"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH" || true
    # Also staple the app inside a temp mount so offline Gatekeeper is happy if
    # someone copies the .app out after mount (ticket is on the DMG primarily).
    echo "→ Gatekeeper assessment…"
    spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" 2>&1 || true
  fi
fi

# Clean stage (keep DMG)
rm -rf "$STAGE"

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "✓ DMG ready"
echo "  ${DMG_PATH}  (${SIZE})"
if is_adhoc; then
  echo "  Signing: ad-hoc (local/dev)"
  echo "  Downloads: users may need right-click → Open, or xattr -cr the .app"
  echo "  Clean download UX: set CODESIGN_IDENTITY + run with --notarize"
else
  echo "  Signing: ${CODESIGN_IDENTITY}"
  if [[ "$DO_NOTARIZE" -eq 1 && "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    echo "  Notarized + stapled"
  else
    echo "  Not notarized (re-run with --notarize for Gatekeeper-clean downloads)"
  fi
fi
echo ""
echo "Install: open the DMG → drag HyperForge.app to Applications"
echo "Then grant Accessibility to HyperForge."

if [[ "$OPEN_WHEN_DONE" -eq 1 ]]; then
  open -R "$DMG_PATH"
fi
