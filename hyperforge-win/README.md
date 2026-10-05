# HyperForge for Windows

**AHK v2 Hyper Key companion** — Caps → Hyper, window snaps, apps, paste transforms, Explorer power moves.

**Parity target:** current macOS HyperForge window pad, `{{token}}` snippets, clipboard history, **region pin**, **OCR**, command bar, and cheat sheet. App launch chords stay Windows-native. Not ported: **Shortcuts** and **AX recipe recording**.

Pairs with **[TouchCursor](https://code.google.com/archive/p/touchcursor/)** (or similar) for Space-layer navigation. This project **does not** reimplement SpaceFN.

Evolved from a long-running personal AutoHotkey toolkit; core is open and config-driven. Work-specific automation stays in a private `work/` module.

> Sibling of the macOS app: [jreis/hyperforge](https://github.com/jreis/hyperforge)

## Requirements

- Windows 10/11  
- [AutoHotkey v2](https://www.autohotkey.com/)  
- Optional: TouchCursor for Space + HJKL  

## Quick start

1. Install AutoHotkey v2.  
2. Copy `config.example.ini` → `config.ini` and set your app paths.  
3. Run `HyperForge.ahk` (double-click or “Open with AutoHotkey”).  
4. Add to Startup if you want it always on:  
   shell:startup → shortcut to `HyperForge.ahk`.

## Hyper (Caps Lock)

Caps is held as **Ctrl+Alt+Shift+Win** (same chord family as 4-mod Hyper on macOS). A bare tap sends **Escape**. The Win key-up is masked, so the tap does not open the Start menu. Set `general.caps_tap_escape=0` to make a tap do nothing.

### Window pad (macOS-aligned)

| Chord | Action |
|-------|--------|
| Hyper + ←/→/↑/↓ | Snap half |
| Hyper + Enter | Maximize |
| Hyper + **6** | Tile all windows on this monitor |
| Hyper + 7 / 8 / 9 / 0 | Quarters TL / TR / BL / BR |
| Hyper + - / = / \\ | Left / right / center **third** |
| Hyper + I / O | Left / right **two-thirds** |
| Hyper + U | **Almost-max** (~90% centered) |
| Hyper + . | Center window (keep size) |
| Hyper + Z | Undo last snap or tile layout |
| Hyper + ] / [ | Next / previous monitor |
| Hyper + A | Always on top (also Ctrl+Shift+Space) |
| Hyper + B | Minimize |
| Hyper + P | Clipboard history (pinned/searchable) |
| Hyper + Y | **Pin screen region** (Win+Shift+S, then stay-on-top) |
| Hyper + J | **Scripts** — run `scripts\*.ahk` |
| Hyper + L | **Workspaces** — save/restore named window layouts |
| Hyper + Q | **OCR region** → clipboard |
| Hyper + / | Cheat sheet |
| Hyper + ; | Command bar (search + run) |
| Hyper + F | Warp mouse to active window |

macOS disambiguates the third vs. two-thirds chord with Shift (`-` vs `⇧-`). Windows'
Hyper is a fixed Win+Ctrl+Alt+**Shift** chord (see `CapsHyper.ahk` — Shift is always
down while Caps is held), so it can't use Shift the same way; two-thirds and
almost-max get their own keys (I / O / U) instead.

**Numpad (Hyper held)** — full spatial pad (same as macOS):

```text
7 TL    8 Top    9 TR
4 Left  5 Max    6 Right
1 BL    2 Bot    3 BR
0 Center
```

### Apps & utilities (Windows-native)

| Chord | Action |
|-------|--------|
| Hyper + N / V / C / T / E / 4 | Notepad / VS Code / Chrome / Teams / Explorer / Outlook |
| Hyper + G | Google clipboard text |
| Hyper + D | Close window |
| Hyper + X | Windows Terminal in Explorer folder |
| Hyper + R | Optional search tool in folder (`paths.search`) |
| Hyper + H | Edit `edit_target` or this script in VS Code |
| Hyper + M | Copy hostname |
| Hyper + W | ARIN whois on clipboard |
| Command bar | Copy LAN IPv4 address |
| Hyper + K | Keep-alive toggle (also Win + J) |
| Win + Esc | Pause / resume Hyper (default 30s) |
| Ctrl+Alt+Shift+V | Paste transform menu |
| XButton2 | Quick menu (windows + favorites) |

Snaps land on the **visible** window frame. Windows draws an invisible resize border around most windows; HyperForge measures it and compensates, so a half-snap sits flush with the work area. Hyper+Z undoes the last snap, or the whole tile if that was the last layout change. A window that was maximized is maximized again on undo.

**Left alone on purpose:** Win+I (Settings) and Win+W (Widgets). Hyper+L is Workspaces; copy the LAN address from the command bar. Clipboard → temp file in the editor is Ctrl+Alt+Shift+W. Mouse Back does not minimize unless `general.xbutton1_minimize=1` (Hyper+B always does). Chrome is not started with a remote-debugging port unless `paths.chrome_debug_port` is set.

**Per-app mute:** Hyper is off in RDP and processes listed under `[mute]` in `config.ini` (game-friendly). Caps→Hyper is muted there too when `mute.caps_too=1`.

**Doctor:** tray → **Doctor — health check** (admin rights, Caps tap, Startup shortcut, Chrome debug port, TouchCursor, mute list, clipboard history). Tray → **Install Startup shortcut** adds a Startup link without an admin prompt. Hyper chords do not reach elevated windows unless HyperForge itself is running elevated; Doctor says so when it isn't.

### Clipboard history (Hyper + P)

Persisted, pinned-first, searchable — mirrors macOS's Hyper+V panel. Every text
copy is recorded (`OnClipboardChange`) to `%APPDATA%\HyperForge\clipboard-history.dat`;
unpinned entries are capped at `[clipboard] max_items` (default 20), pinned entries
never evict. Hyper+P opens a window over the full history: type to filter, ↑↓ move
the selection while the filter keeps focus, **Enter** pastes, double-click pastes a
row, **Pin / unpin** toggles pin, **Delete** or Ctrl+Del removes the row, Esc closes.
History is stored as one base64 line per entry (no mid-line wrapping).

The older Ctrl+Alt+Shift+V **paste transform menu** (linefeeds↔commas, base64,
URL encode, …) is unchanged and separate from history.

### Snippets

Configure under `[snippets]` in `config.ini` (`@@`, `tj`, `,v`, `,sig`, …). Expansions
support the same `{{token}}` set as macOS HyperForge:

| Token | Expands to |
|-------|------------|
| `{{date}}` | Today, formatted per `[snippets] date_format` (default `yyyy-MM-dd`) |
| `{{date:MM/dd/yyyy}}` | Today, with a per-snippet format override |
| `{{clipboard}}` | Current clipboard text |
| `{{hostname}}` | This machine's name |
| `{{uuid}}` | A fresh random UUID |
| `{{lan-ip}}` | First non-loopback IPv4 address |

`\n` / `\t` still expand to a real newline/tab for multi-line snippets.

## Layout

```
hyperforge-win/
├── HyperForge.ahk          # entry point
├── config.example.ini
├── config.ini              # your machine (gitignored)
├── lib/                    # public core modules
├── work/                   # optional private includes (work.ahk gitignored)
│   ├── work.example.ahk
│   └── README.md
├── tests/
│   └── smoke.ahk           # pure-logic checks (AutoHotkey v2, no hotkeys fired)
└── legacy/                 # local-only original dump (gitignored)
```

## Checks

With AutoHotkey v2 installed:

```bat
AutoHotkey64.exe tests\smoke.ahk
```

The script exits 0 and prints `ok`. It covers snap-border math, undo order, clipboard history round-trip, backup JSON (including Windows paths), UUID layout, command ranking, the cheat sheet, and registration of every chord. It does not press keys or move windows. Checked with AutoHotkey 2.0.28.

## Privacy

- Do **not** commit `config.ini`, `work/work.ahk`, or `legacy/*`.  
- Use Windows Credential Manager for passwords (`CredRead` helper available).  
- Defaults ship with placeholder email only.

## Relation to macOS HyperForge

| | macOS | Windows |
|--|-------|---------|
| Hyper | F18 / 4-mod + Karabiner, tap = Escape | Caps → `#^!+`, tap = Escape |
| Window pad | Arrows · numpad · thirds/2-thirds/almost-max · 6 tile · Z undo | **Same chords**, 2/3 + almost-max on I/O/U (no Shift disambiguation) |
| Snippets | `{{date/clipboard/hostname/uuid/lan-ip}}` hotstrings | **Same tokens**, AHK `:*:` hotstrings |
| Clipboard history | Hyper+V panel, persisted/pinned/searchable | Hyper+P Gui panel, persisted/pinned/searchable |
| Space layer | Built-in (TouchCursor-style) | **TouchCursor** (external) |
| Profiles / auto-triggers | Wi‑Fi / app / time, per-app overrides | Not ported — use `[mute]` for a coarse per-process on/off instead |
| Region pin / OCR | Hyper+P / Hyper+O | Hyper+Y / Hyper+Q (Win+Shift+S + WinRT OCR) |
| Command bar / cheat sheet | Hyper+Space / Hyper+/ | Hyper+; / Hyper+/ |
| Shortcuts / AX recipes | Built-in | Not ported — macOS-API-specific |
| UI | SwiftUI dashboard / Doctor | Tray + config.ini + Doctor |
| Engine | Swift CGEvent | AutoHotkey v2 |
| App keys | 1–5, T, F, … | Letter chords (N/V/C/T/E…) — intentional |

## License

MIT — same spirit as the main HyperForge repo. © Jason Reis
