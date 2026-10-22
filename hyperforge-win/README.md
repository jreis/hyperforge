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

> **Work laptop? Ask IT first.** Many endpoint-security tools (Defender for Endpoint, CrowdStrike, SentinelOne) and AppLocker/WDAC policies flag or block AutoHotkey. HyperForge also installs a global keyboard hook, sends synthetic input, and runs hidden PowerShell for Pin/OCR (see [PowerShell use](#powershell-use)). Get AutoHotkey approved or allow-listed before you run it, rather than finding out from a security alert. Don't compile it to an `.exe` and don't run it as administrator.

1. **Get AutoHotkey v2 without admin rights.** Use either:
   - the official installer from [autohotkey.com](https://www.autohotkey.com/), choosing the **current user** install option (no UAC prompt), or
   - the **portable zip** from the same download page, extracted to e.g. `%USERPROFILE%\Tools\AutoHotkey\`. Use `AutoHotkey64.exe` from there.
2. **Put HyperForge under your profile**, e.g. `%USERPROFILE%\hyperforge-win\`. Not under Program Files (HyperForge writes `config.ini` and `scripts\` next to itself, and those writes fail there) and not in a OneDrive-synced Documents folder.
3. **If either came from a downloaded zip, unblock it before extracting**, or Windows marks every file (Mark-of-the-Web) and SmartScreen prompts. Right-click the zip → Properties → **Unblock**, or in PowerShell:
   ```powershell
   Unblock-File -Path "$env:USERPROFILE\Downloads\hyperforge-win.zip"
   # already extracted? unblock the folder's files instead:
   Get-ChildItem "$env:USERPROFILE\hyperforge-win" -Recurse | Unblock-File
   ```
4. **Run `HyperForge.ahk`** (double-click, or drag it onto `AutoHotkey64.exe` for the portable build). On first run it copies `config.example.ini` to `config.ini`.
5. **Edit `config.ini`** for your machine (app paths are optional; blanks use defaults), then tray → **Reload HyperForge**. Clipboard history and keep-alive are off until you turn them on there.
6. **Add it to Startup:** tray → **Install Startup shortcut**. That writes `HyperForge.lnk` into your Startup folder (`shell:startup`), pointing at the AutoHotkey you ran it with. No admin prompt. To undo, delete that `.lnk`.
7. **Run Doctor:** tray → **Doctor — health check**. It shows whether Caps→Hyper is on, the Startup shortcut, the Chrome debug port, clipboard-history and keep-alive state, and warnings such as an old Roaming clipboard-history file.

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
| Hyper + N / V / C / T / E / 4 / 5 | Editor (LazyVim/Neovim if installed, else Notepad) / VS Code / Chrome / Teams / Explorer / Outlook / localhost URL menu |
| Hyper + G | Google clipboard text |
| Hyper + D | Close window |
| Hyper + X | Windows Terminal in Explorer folder |
| Hyper + R | Optional search tool in folder (`paths.search`) |
| Hyper + H | Edit `edit_target` or this script in VS Code |
| Hyper + M | Copy hostname |
| Hyper + W | ARIN whois on clipboard |
| Command bar | Copy LAN IPv4 address |
| Hyper + K | Keep-alive toggle (also Win + J) — **off unless `general.keepalive_enabled=1`** |
| Win + Esc | Pause / resume Hyper (default 30s) |
| Ctrl+Alt+Shift+V | Paste transform menu |
| XButton2 | Quick menu (windows + favorites) |

`Hyper + 5` reads `[apps] local_urls` in `config.ini` (comma-separated, scheme optional) and shows a quick launcher menu for common local dev endpoints.

If `Hyper + N` opens Neovim but compilers/toolchains are missing, set `[apps] editor_env_bootstrap` in `config.ini` to a command that prepares your shell environment before launch (for example `call "%USERPROFILE%\dev\env.cmd"`). HyperForge runs that bootstrap in `cmd.exe` and then starts your preferred editor.

When the preferred editor is Neovim/LazyVim, HyperForge launches it through your configured terminal (`paths.terminal`, default `wt`) and shell (`paths.terminal_shell`, default `powershell.exe`) so it inherits shell/profile environment closer to manual terminal launches.

If `apps.editor_env_bootstrap` is set, HyperForge launches Neovim via a generated `cmd` script (`<bootstrap>` then `nvim`) inside Windows Terminal, so compiler/toolchain environment from the bootstrap command is applied in the same session.

Snaps land on the **visible** window frame. Windows draws an invisible resize border around most windows; HyperForge measures it and compensates, so a half-snap sits flush with the work area. Hyper+Z undoes the last snap, or the whole tile if that was the last layout change. A window that was maximized is maximized again on undo.

**Left alone on purpose:** Win+I (Settings) and Win+W (Widgets). Hyper+L is Workspaces; copy the LAN address from the command bar. Clipboard → temp file is Ctrl+Alt+Shift+W (opens LazyVim/Neovim if available). Mouse Back does not minimize unless `general.xbutton1_minimize=1` (Hyper+B always does). Chrome is not started with a remote-debugging port unless `paths.chrome_debug_port` is set.

**Keep-alive (off by default):** Hyper+K / Win+J nudge the mouse 1px when you've been idle, which keeps the screen from locking and Teams from going Away. That circumvents screen-lock and presence controls, which most corporate acceptable-use and security policies forbid, and EDR/UEBA tools look for the pattern. The chords aren't registered at all unless you set `[general] keepalive_enabled=1`. Don't turn it on on a work machine without written OK from IT.

**Per-app mute:** Hyper is off in RDP and processes listed under `[mute]` in `config.ini` (game-friendly). Caps→Hyper is muted there too when `mute.caps_too=1`.

**Doctor:** tray → **Doctor — health check** (admin rights, Caps tap, Startup shortcut, Chrome debug port, TouchCursor, mute list, clipboard history). Tray → **Install Startup shortcut** adds a Startup link without an admin prompt. Hyper chords do not reach elevated windows unless HyperForge itself is running elevated; Doctor says so when it isn't.

### Hotkeys that send data off this machine

These send text you've copied to a third party. Don't use them on internal hostnames, ticket text or anything confidential:

| Chord / entry | Sends | To |
|---|---|---|
| Hyper + W, command bar "ARIN whois" | The clipboard text (HTTP POST), **only** if it's a single IPv4 or IPv6 address (optionally CIDR, e.g. `10.0.0.0/8`) or an AS number (e.g. `AS12345`); domains and hostnames are refused | `whois.arin.net` (or `network.arin_whois`) |
| Hyper + G, command bar "Google clipboard", Ctrl+Alt+Shift+V → "Google clipboard" | The clipboard text as a search URL opened in Chrome, **only** if it's one line of at most 200 characters **and** you click Yes in a confirm prompt that previews the first 80 characters | `google.com` |
| Hyper + S | Nothing from the clipboard; opens `apps.hyper_s_url` in Chrome | wherever that URL points |

Nothing else makes network calls. Reverse DNS (Win+Ctrl+I) uses your normal DNS resolver. If `paths.chrome_debug_port` is set, Chrome opens a local debugging port that any local process can use; leave it blank on work machines.

### PowerShell use

Some features shell out to `powershell.exe -NoProfile -ExecutionPolicy Bypass -File …`. Security tools often flag that pattern, and it fails where PowerShell is in Constrained Language Mode or blocked by AppLocker:

- **Hyper + Y (pin region) and Hyper + Q (OCR)** write short helper `.ps1` files to `%TEMP%` and run them hidden, to save the snipped image and to run Windows' built-in OCR (`lib/Pin.ahk`).
- **Scripts `HF_RunShortcut(name)`** runs `shortcuts\<name>.ps1` (`lib/HFBridge.ahk`).
- **Quick menu → Toggle Focus** runs `shortcuts\Toggle Focus.ps1` if you created it (`lib/SystemControls.ahk`).

Nothing else uses PowerShell. If your IT blocks it, those features fail and the rest of HyperForge still works.

### Clipboard history (Hyper + P)

**Off by default.** Turn it on with `[clipboard] enabled=1` in `config.ini`. When on,
it is pinned-first and searchable, mirroring macOS's Hyper+V panel. Text copies are
recorded (`OnClipboardChange`) **except** copies the source app marks as private: if
`ExcludeClipboardContentFromMonitorProcessing` or `Clipboard Viewer Ignore` is present,
or `CanIncludeInClipboardHistory` / `CanUploadToCloudClipboard` is `0`, the copy is
skipped. KeePass is documented to set these when it copies a password; other password managers may or may not, so check yours before relying on it.

History lives **in memory only** unless `[clipboard] persist=1`, which saves it to
`%LOCALAPPDATA%\HyperForge\clipboard-history.dat` (local, not Roaming; base64, which is
*not* encryption). It is never included in Tray → Export. Older builds wrote to
`%APPDATA%\HyperForge\clipboard-history.dat`; Doctor flags that file. Delete it.

Unpinned entries are capped at `[clipboard] max_items` (default 20), pinned entries
never evict. Hyper+P opens a window over the full history: type to filter, ↑↓ move
the selection while the filter keeps focus, **Enter** pastes, double-click pastes a
row, **Pin / unpin** toggles pin, **Delete** or Ctrl+Del removes the row, Esc closes.

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
| `{{env:NAME}}` | That variable from this process (`[A-Za-z_][A-Za-z0-9_]*`). An unset or illegal name is left as written. |

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
AutoHotkey64.exe /ErrorStdOut tests\smoke.ahk
```

On success it prints `ok <number of checks>` and exits 0; assertion failures print `FAIL …` lines and exit 1, and an unexpected runtime error prints `ERROR …` and exits 2. `#Warn` output goes to stdout too, and `/ErrorStdOut` sends load-time errors (syntax, a missing `#Include`) to stdout instead of a dialog. To see the exit code from `cmd`, run it with `start /wait` and then `echo %ERRORLEVEL%` (in PowerShell: `Start-Process -Wait -PassThru` and read `.ExitCode`), because AutoHotkey is a GUI-subsystem program and the console doesn't wait for it. To capture the output, pipe it: `AutoHotkey64.exe /ErrorStdOut tests\smoke.ahk | more`. It covers snap-border math, undo order, clipboard history round-trip, backup JSON (including Windows paths), UUID layout, command ranking, the cheat sheet, and registration of every chord (including the opt-in keep-alive, Scripts, Workspaces and Backup). It registers real hotkeys briefly, so close a running HyperForge first. It does not press keys or move windows.

## Privacy

- Do **not** commit `config.ini`, `work/work.ahk`, or `legacy/*`.  
- Use Windows Credential Manager for passwords (`CredRead` helper available).  
- Defaults ship with placeholder email only.

## Relation to macOS HyperForge

| | macOS | Windows |
|--|-------|---------|
| Hyper | F18 / 4-mod + Karabiner, tap = Escape | Caps → `#^!+`, tap = Escape |
| Window pad | Arrows · numpad · thirds/2-thirds/almost-max · 6 tile · Z undo | **Same chords**, 2/3 + almost-max on I/O/U (no Shift disambiguation) |
| Snippets | `{{date/clipboard/hostname/uuid/lan-ip/env}}` hotstrings | **Same tokens**, AHK `:*:` hotstrings |
| Clipboard history | Hyper+V panel, persisted/pinned/searchable | Hyper+P Gui panel, opt-in, memory-only by default, pinned/searchable |
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
