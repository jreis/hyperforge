# HyperForge for Windows

**AHK v2 Hyper Key companion** — Caps → Hyper, window snaps, apps, paste transforms, Explorer power moves.

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
| Hyper + ←/→/↑/↓ / Enter | Snap half / maximize |
| Hyper + 7 / 8 / 9 / 0 | Quarters (TL / TR / BL / BR) |
| Hyper + . | Center window (keep size) |
| Hyper + Z | Undo last snap for this window |
| Hyper + ] / [ | Move window to next / previous monitor |
| Win + J | Keep-alive toggle |
| Win + Esc | Pause / resume Hyper (default 30s) |
| Ctrl+Shift+Space | Always on top |
| Ctrl+Alt+Shift+V | Paste transform menu |
| XButton2 | Quick menu (windows + favorites) |
| XButton1 | Minimize |

**Per-app mute:** Hyper is off in RDP and processes listed under `[mute]` in `config.ini` (games-friendly). Caps→Hyper is muted there too when `mute.caps_too=1`.

**Doctor:** tray → **Doctor — health check** (AHK version, config, TouchCursor process, mute list).

Snippets: configure under `[snippets]` in `config.ini` (`@@`, `tj`, `,v`, …).

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
| Hyper | F18 / 4-mod + Karabiner | Caps → `#^!+` in AHK |
| Space layer | Built-in (TouchCursor-style) | **TouchCursor** (external) |
| UI | SwiftUI dashboard / Doctor | Tray + config.ini |
| Engine | Swift CGEvent | AutoHotkey v2 |

## License

MIT — same spirit as the main HyperForge repo. © Jason Reis
