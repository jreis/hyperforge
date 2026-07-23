# HyperForge

<p align="center">
  <img src="docs/hyperforge-icon.png" alt="HyperForge icon" width="128" height="128" />
</p>

<p align="center">
  <strong>Local-first Hyper Key automation for macOS</strong><br/>
  Caps → Hyper · Space-layer navigation · window tiling · snippets · Doctor<br/>
  <em>No cloud · No telemetry · Built for restricted environments</em>
</p>

<p align="center">
  <code>macOS 14+</code>
  ·
  <code>Apple Silicon</code>
  ·
  <code>Swift / SwiftUI</code>
  ·
  <code>MIT</code>
</p>

---

## Why

When **Hammerspoon**, browser extensions, and heavy automation stacks are blocked, you still want power-user flow. HyperForge is a native companion for **Karabiner Hyper** plus a **TouchCursor-style Space layer** — all on-device.

| Constraint | Approach |
|------------|----------|
| No Hammerspoon | Swift `CGEvent` tap + Accessibility |
| No Vimium | Space + HJKL system-wide · optional link hints |
| Opaque remaps | Dashboard + live test + cheat sheet |
| Flaky help chords | Doctor · F19/F20 bridges for 4-mod Hyper |
| Privacy | Local only · optional Ollama on `127.0.0.1` |

---

## Quick start

```bash
git clone https://github.com/jreis/hyperforge.git
cd hyperforge
chmod +x Scripts/install.sh
./Scripts/install.sh
```

Then:

1. **System Settings → Privacy & Security → Accessibility** → enable **HyperForge**
2. **Karabiner-Elements → Complex Modifications** → enable Caps → Hyper (and F19/F20 if you use 4-mod)
3. Open the menu bar flame → **Doctor** and confirm green checks
4. Try **Hyper + ←** (snap) and **hold Space + H/J/K/L** (arrows)

Dev / smoke (no full Xcode required for Kit checks):

```bash
swift build
swift run HyperForgeSmoke
swift run   # launch the app from the build product
```

---

## Features (core)

- **Hyper Key Central** — searchable catalog, live test, engine status  
- **Doctor** — Accessibility, Karabiner rules, Hyper style, Space nav, Ollama fit  
- **Space navigation** — hold Space for vim-style motions + edit/clipboard chords; tap Space still types a space  
- **Per-app Space block list** — e.g. keep Terminal normal; allow Ghostty (editable in Settings)  
- **Profiles & auto-triggers** — Coding / Browsing / Music / Minimal; Wi‑Fi, app, or time  
- **Per-app Hyper overrides** — disable or remap chords per bundle ID  
- **Snippets** — local hotstrings; `{{date}}` with custom formats; clipboard / hostname tokens  
- **Shortcuts** — Hyper + `'` or ⇧S → run installed macOS Shortcuts  
- **Window tools** — snap, tile, undo, next display, always-on-top, region pin  
- **Command bar** — Hyper + Space; offline router + optional local Ollama  
- **Config backup** — Settings → Privacy → export/import JSON (profiles, snippets, Space nav, prefs)  
- **Cheat sheet** — Hyper + / or `` ` ``; Space bindings grouped (Move / Kill / Clipboard / Mac)

---

## Hyper trigger

HyperForge supports **either** style (with short sticky grace for Karabiner flag blips).

### A) F18 (recommended)

1. Karabiner: Caps Lock → `F18`, alone → `Escape`
2. HyperForge listens for F18 keyDown/keyUp  
3. **Hyper + /** → link hints · **Hyper + ⇧/** or **`** → cheat sheet  
4. **Hyper + ,** → dashboard (or menu bar / ⌘⇧D)

### B) 4-mod Hyper (⌘⌃⌥⇧)

1. Karabiner: Caps → left ⌘⌃⌥⇧, alone → Escape  
2. Shift is always held with Caps → install bridges:  
   - Hyper + `/` → **F19** (cheat sheet)  
   - Hyper + `,` → **F20** (dashboard)  
3. Menu bar **Keybindings…** always works without chords  

### Always available

| Input | Action |
|-------|--------|
| **Space** held | Navigation layer (HJKL, words, kill-to-EOL, copy/paste, …) |
| **Hyper + Space** | Command bar (not stolen by Space layer) |
| Menu bar flame | Dashboard, engine, cheat sheet |

Hold-before-layer (~160 ms default) and blocked apps: **Settings → Engine → Space navigation**. Keys during the hold window type a normal space + letter so fast typing isn’t stolen.

---

## Sample chords

| Chord | Action |
|-------|--------|
| Hyper + ←/→/↑/↓ | Snap half |
| Hyper + Return | Maximize |
| Hyper + 6 | Tile all windows |
| Hyper + H/J/L | Scroll |
| Hyper + K | Keep-alive |
| Hyper + Space | Command bar |
| Hyper + P | Pin screen region |
| Hyper + T / ⇧T | Terminal · terminal in Finder folder |
| Hyper + , | Dashboard |
| Hyper + ' | Run Shortcut |
| Space + H/J/K/L | Arrows |
| Space + X | Kill to end of line |
| Space + Y / P / U | Copy / paste / undo |

Full list: in-app **cheat sheet** or dashboard. Snippets: `,sig`, `@@`, `,date`, `,v`, `,host` (edit under Snippets).

---

## Requirements

- macOS 14+  
- Apple Silicon recommended  
- [Swift toolchain](https://swift.org) / Xcode CLT  
- [Karabiner-Elements](https://karabiner-elements.pqrs.org) for Caps → Hyper  
- **Accessibility** for the event tap and window actions  

---

## Install options

### Daily driver (recommended)

```bash
./Scripts/install.sh
```

Builds release, packages `~/Applications/HyperForge.app`, ad-hoc signs with stable id `app.hyperforge.HyperForge` (Accessibility survives rebuilds), writes Karabiner pack assets when config exists, optional LaunchAgent.

### Local DMG

```bash
./Scripts/package-dmg.sh --open
```

Output under `dist/` (gitignored). Ad-hoc signed — not notarized; Gatekeeper may prompt once.

### Event log (optional)

```bash
# enable “Write event log” in Settings → Privacy, then:
tail -f /tmp/hyperforge-events.log
```

---

## Project layout

```
HyperForge/
├── Package.swift
├── Config/                 # Karabiner pack JSON
├── Scripts/                # install.sh, package-dmg.sh
├── Sources/
│   ├── HyperForgeKit/      # Pure logic (routing, policy, model fitness)
│   ├── HyperForge/         # App UI + CGEvent engine
│   └── HyperForgeSmoke/    # CLI smoke tests (no full Xcode)
├── Tests/HyperForgeTests/  # XCTest (needs Xcode)
├── docs/                   # Icon assets
└── README.md
```

**Architecture:** SwiftUI shell + `AppState` / stores; event-tap engine stays off the main actor where it matters; testable policy in **HyperForgeKit**.

---

## Privacy

| Permission | Why |
|------------|-----|
| Accessibility | Event tap, window AX, key synthesis |
| AppleEvents (optional) | Terminal / notes automation |

Core Hyper Key never needs the network. Optional command-bar AI talks only to **local Ollama**. Config export is a file **you** choose to copy — nothing phones home.

---

## Distribution notes

A full CGEvent-tap engine fits **direct download / open source** better than the Mac App Store sandbox. Ad-hoc signing is for local/dev use; notarization is optional for wider distribution.

---

## Status

**Done:** Doctor, dual Hyper style, Space nav + per-app blocks, snippets, Shortcuts, region pin, profiles, overrides, config backup, Ollama model-fit, smoke tests.

**Maybe later:** MLX without Ollama, demo GIF capture, Sparkle updates.

---

## Windows (AutoHotkey)

A companion **AHK v2** toolkit lives in [`hyperforge-win/`](hyperforge-win/): Caps → Hyper, snaps, paste menu, Explorer helpers. **Space-layer nav stays with TouchCursor** on Windows.

```text
hyperforge-win/HyperForge.ahk   # run with AutoHotkey v2
hyperforge-win/README.md        # setup + chords
```

## Origin

HyperForge grew out of a personal Hyper Key CGEvent daemon: same Caps/F18 muscle memory, rebuilt as a local-first SwiftUI companion with Doctor, profiles, Space navigation, and a richer surface area. The Windows kit polishes a long-running AHK script in the same spirit.

---

## License

[MIT](LICENSE) · © Jason Reis · local-first
