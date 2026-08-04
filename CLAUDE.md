# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

HyperForge is a native macOS menu-bar app (Swift/SwiftUI) that turns Caps Lock into a "Hyper" key via a global `CGEvent` tap, plus a TouchCursor-style Space navigation layer, window tiling, snippets, clipboard tools, and a Doctor health checker. It's local-first: no cloud, no telemetry, optional AI only talks to a local Ollama instance on `127.0.0.1`. Companion kits for Windows (AutoHotkey, `hyperforge-win/`) and Linux (kanata/keyd, `hyperforge-linux/`) live alongside the macOS app but are separate toolchains — treat them independently unless a task explicitly touches them.

## Build / test / run

```bash
swift build                    # debug build of all targets
swift build -c release         # release build (used by install.sh)
swift run HyperForgeSmoke      # pure-logic smoke tests — works with Command Line Tools only, no Xcode needed
swift run                      # launch the app from the build product
```

XCTest (`Tests/HyperForgeTests`) requires **full Xcode**, not just Command Line Tools:

```bash
swift test                                    # all XCTest tests (needs Xcode)
swift test --filter HyperChordRoutingTests    # single test class
```

If only Command Line Tools are installed (check with `xcode-select -p`), `swift test` will fail to build — rely on `swift run HyperForgeSmoke` instead, and treat the XCTest files under `Tests/HyperForgeTests` as the documentation of expected behavior even if you can't execute them locally. Every case in `HyperForgeSmoke/main.swift` mirrors a case in the XCTest suite; when adding logic to `HyperForgeKit`, add coverage to **both**.

No linter/formatter config is checked in (no SwiftLint/swift-format). Match surrounding style.

### Installing / packaging (do not run without asking)

`./Scripts/install.sh` builds a release binary, code-signs it as a stable-identity `.app` bundle, and installs a LaunchAgent — it also `killall HyperForge`s any running instance first. `./Scripts/install.sh --update` is the fast path (swap binary + re-sign only). **Never** copy the raw `.build/release/HyperForge` binary over the installed `.app` — the linker's ad-hoc signature changes every build and macOS will re-prompt for Accessibility permission. Always go through `sign_app` in `install.sh` (stable bundle id `app.hyperforge.HyperForge` + designated requirement).

`./Scripts/package-dmg.sh --open` builds a distributable DMG under `dist/` (gitignored).

## Architecture

### Two-target split: `HyperForgeKit` vs `HyperForge`

- **`Sources/HyperForgeKit/`** — pure logic, zero AppKit/UIKit dependency, fully unit-testable without Accessibility permissions or a running event tap. This is where chord-routing decisions, Karabiner config parsing, window-identification heuristics, and Ollama model-fitness math live (`HyperBindingResolver`, `HyperChordRouting`, `KarabinerDetection`, `KarabinerConfigPatch`, `DashboardWindowPolicy`, `ModelFitness`, `CatalogPolicy`). When adding a new keybinding or policy decision, prefer putting the *decision* here and the *side effect* (CGEvent synthesis, window manipulation, AppKit calls) in `HyperForge`.
- **`Sources/HyperForge/`** — the app itself: CGEvent tap engine, SwiftUI views, AppKit glue, all stateful services.
- **`Sources/HyperForgeSmoke/`** — CLI-only smoke tests exercising `HyperForgeKit`, runnable without Xcode (see above).

### Event flow: CGEvent tap → routing → action

`HyperKeyEngine` (`Sources/HyperForge/Engine/HyperKeyEngine.swift`) owns the global `CGEvent` tap — this is the heart of the app. It tracks physical Hyper-key state (F18 or 4-mod `⌘⌃⌥⇧`) and Space-layer hold/armed state, and delegates actual key routing to the pure functions in `HyperForgeKit` (`HyperBindingResolver.resolve`, `HyperChordRouting`). Resolved actions are dispatched to `HyperKeyActions.swift`. `VimNavigation.swift` owns the separate Space-held navigation layer (HJKL, word motions, kill/copy/paste), which is intentionally decoupled from the Hyper-chord path since Space is a *typing* key that must still type a space on tap.

Two Hyper trigger styles are supported and must both be considered when touching chord logic:
- **F18** (Caps→F18 via Karabiner, recommended): plain `/` → link hints, `⇧/` → cheat sheet.
- **4-mod** (Caps→`⌘⌃⌥⇧`): Shift is *always* physically down while Hyper is held, so Shift can't be used to disambiguate chords the same way — routing functions take a `hyperConsumesShift` flag to compensate, and F19/F20 Karabiner bridges stand in for the help/dashboard chords that would otherwise collide.

Timing-sensitive state in `HyperKeyEngine` (grace windows, `to_if_alone` Escape suppression, menu-session depth) has hard-won constants with comments explaining the specific bug each guards against (e.g. `hyperGraceSeconds`, `capsAloneEscapeSuppressSeconds`) — read the comment before changing a timing constant, and if you must change one, understand what real-world Karabiner event-ordering quirk it was tuned against.

### Escape key: single priority pipeline

`EscapeCoordinator` (`Sources/HyperForge/App/EscapeCoordinator.swift`) is the single dispatcher for the Esc key across all HyperForge UI surfaces. Handlers register per `Layer` (region selection → floating pins → link hints → clipboard history → command bar → cheat sheet → dashboard, innermost/most-transient wins) and the first layer that reports it consumed the key stops the chain. When adding new dismissable UI, register a handler here rather than adding a local Esc listener — a second independent Esc handler will race this one.

### Window/state model

- `AppState` (`Sources/HyperForge/App/AppState.swift`) is the `@MainActor` root `ObservableObject`, a singleton (`AppState.shared`) wiring together the engine and all services, and owning dashboard window show/hide logic (including retry logic for SwiftUI's `WindowGroup` being slow to materialize, and dropping to `.accessory` activation policy when menu-bar-only mode is on).
- Because the CGEvent tap and `MenuBarExtra` buttons can call in from non-main-actor contexts, cross-actor entry points are centralized in the nonisolated `AppCommands` enum at the bottom of `AppState.swift` (`AppCommands.openMainWindow()`, etc.) — always route through these rather than reaching for `AppState.shared` directly from tap/menu-bar code.
- `Services/*Store.swift` files (`ProfileStore`, `SnippetStore`, `AppOverrideStore`, `SpaceNavStore`, `HyperAppSlotStore`, `BindingChecklistStore`, `FirstRunChallengeStore`) are `@MainActor` singletons persisting to `UserDefaults`/JSON, generally following the same shape: `static let shared`, `@Published` state, load/save methods. `ConfigBackupService` handles export/import of most of these as a single JSON blob (Settings → Privacy).
- `Profile` (Coding / Browsing / Music / Minimal, `Models/Profile.swift`) determines the enabled-action-ID set consumed by `HyperChordRouting.isAllowed` — an empty/nil set means "allow everything" (the default/Coding-equivalent state).

### Concurrency

Swift 6 strict concurrency is in effect — most engine/service singletons are `@MainActor`; `HyperKeyEngine` itself is `@unchecked Sendable` with a manual `NSLock` guarding state read from the CGEvent tap thread (`enabledIDsCopy` etc.), since the tap callback runs off the main actor and can't wait on `Task { @MainActor in }` hops for hot-path key handling. When adding state to the engine that's read from the tap callback, follow the existing lock-and-copy pattern rather than introducing new actor hops on the hot path.

### Karabiner integration

HyperForge doesn't remap Caps Lock itself — it depends on Karabiner-Elements complex-modification rules (Caps→F18 or Caps→4-mod) and detects/patches that external config. `KarabinerDetection` parses `karabiner.json` heuristically to figure out which style is active; `KarabinerConfigPatch` performs *upsert* patches (remove-then-write) when enabling the HyperForge rule pack, so re-running install/Doctor doesn't stack duplicate rules under renamed descriptions. `Config/*.json` holds the shipped Karabiner rule assets; `Scripts/karabiner-enable-pack.py` enables them on the active profile during install.

## Commit style

Short, imperative-mood, present-tense summaries of the fix/change (e.g. "Fix Hyper+T cold-start when Ghostty is quit", "Focus cheatsheet window and search field on open") — no body text in typical commits.
