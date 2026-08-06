# HyperForge for Windows

**AHK v2 Hyper Key companion** — Caps → Hyper, window snaps, apps, paste transforms, Explorer power moves.

**Parity target:** current macOS HyperForge window pad (halves/quarters/**thirds/two-thirds/almost-max**/tile-all/undo/monitors), `{{token}}` snippets, and a persisted/pinned/searchable clipboard history. App launch chords stay Windows-native (letter keys differ by design). Not ported — no Windows equivalent shipped here: **OCR region**, **region pin**, the **Ollama command bar**, **Shortcuts** integration, and **AX recipe recording** (all macOS-API-specific).

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

Caps is held as **Ctrl+Alt+Shift+Win** (same chord family as 4-mod Hyper on macOS).

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
| Hyper + B | Minimize (also XButton1) |
| Hyper + P | Clipboard history (pinned/searchable) |

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
| Hyper + K | Keep-alive toggle (also Win + J) |
| Win + Esc | Pause / resume Hyper (default 30s) |
| Ctrl+Alt+Shift+V | Paste transform menu |
| XButton2 | Quick menu (windows + favorites) |

**Per-app mute:** Hyper is off in RDP and processes listed under `[mute]` in `config.ini` (game-friendly). Caps→Hyper is muted there too when `mute.caps_too=1`.

**Doctor:** tray → **Doctor — health check** (AHK version, config, TouchCursor process, mute list, clipboard history count, macOS-parity tips).

### Clipboard history (Hyper + P)

Persisted, pinned-first, searchable — mirrors macOS's Hyper+V panel. Every text
copy is recorded (`OnClipboardChange`) to `%APPDATA%\HyperForge\clipboard-history.dat`;
unpinned entries are capped at `[clipboard] max_items` (default 20), pinned entries
never evict. Hyper+P opens a small window: type to filter, **Enter** pastes the
top/selected match, double-click pastes a specific row, **Pin / unpin** toggles pin
on the selected row, Esc closes.

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
└── legacy/                 # local-only original dump (gitignored)
```

## Privacy

- Do **not** commit `config.ini`, `work/work.ahk`, or `legacy/*`.  
- Use Windows Credential Manager for passwords (`CredRead` helper available).  
- Defaults ship with placeholder email only.

## Relation to macOS HyperForge

| | macOS | Windows |
|--|-------|---------|
| Hyper | F18 / 4-mod + Karabiner | Caps → `#^!+` in AHK (always includes Shift) |
| Window pad | Arrows · numpad · thirds/2-thirds/almost-max · 6 tile · Z undo | **Same chords**, 2/3 + almost-max on I/O/U (no Shift disambiguation) |
| Snippets | `{{date/clipboard/hostname/uuid/lan-ip}}` hotstrings | **Same tokens**, AHK `:*:` hotstrings |
| Clipboard history | Hyper+V panel, persisted/pinned/searchable | Hyper+P Gui panel, persisted/pinned/searchable |
| Space layer | Built-in (TouchCursor-style) | **TouchCursor** (external) |
| Profiles / auto-triggers | Wi‑Fi / app / time, per-app overrides | Not ported — use `[mute]` for a coarse per-process on/off instead |
| OCR / region pin / command bar / Shortcuts / AX recipes | Built-in (Vision, Ollama, AppleScript, Accessibility) | Not ported — macOS-API-specific |
| UI | SwiftUI dashboard / Doctor | Tray + config.ini + Doctor |
| Engine | Swift CGEvent | AutoHotkey v2 |
| App keys | 1–5, T, F, … | Letter chords (N/V/C/T/E…) — intentional |

## License

MIT — same spirit as the main HyperForge repo. © Jason Reis
