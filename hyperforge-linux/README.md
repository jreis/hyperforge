# HyperForge for Linux

**Caps → Hyper · Space-layer HJKL · window snaps · snippets · clipboard history** for Linux — same muscle memory as the macOS app.

**Parity target:** current macOS HyperForge window pad (halves/quarters/**thirds/two-thirds/almost-max**/tile-all/undo), `{{token}}` **snippets**, a persisted/pinned **clipboard history**, a **region pin** (stay-on-top capture), and the Space nav subset. This is **not** a Swift/AppKit port. Not ported: the **Ollama command bar**, **Shortcuts** integration, **AX recipe recording**, and **profiles/auto-triggers** (macOS-API-specific).

| Piece | Role |
|-------|------|
| **[kanata](https://github.com/jtroo/kanata)** (preferred) | Caps Hyper layer + Space nav layer + numpad pad |
| **[keyd](https://github.com/rvaiya/keyd)** (optional) | Same idea as a system service |
| **`hyperforge-snap`** | Half / quarter / **third / two-thirds / almost-max** / max / **tile** for **Hyprland**, **Sway**, or **X11** |
| **`hyperforge-action`** | Apps, lock, date, google clipboard, plain paste, open URL, snippet + clipboard dispatch |
| **`hyperforge-snippet`** | `{{token}}` text-expansion snippets — typed hotstrings (`@@`) or picker |
| **`hyperforge-clip`** | Persisted, pinned, searchable clipboard history |
| **`hyperforge-doctor`** | Setup health check |

Sibling of:

- macOS: [jreis/hyperforge](https://github.com/jreis/hyperforge)
- Windows: [`hyperforge-win/`](../hyperforge-win/)

---

## Requirements

- Linux with either:
  - **Wayland:** Hyprland or Sway (best), or  
  - **X11:** `wmctrl` + `xdotool`
- **kanata** built **with `cmd`** (or keyd). `cargo install kanata` is not enough — use `cargo install kanata --features cmd`. Distro packages named `kanata` / `kanata-bin` are often compiled *without* `cmd`; you want a `cmd`-allowed build.
- `jq` for Hyprland geometry snaps  
- Optional: `notify-send`, `wtype` / `ydotool`, `wl-clipboard`
- Optional: `rofi` or `wofi` for the snippet (Hyper+,) and clipboard (Hyper+P) pickers

---

## Quick start

```bash
cd hyperforge-linux
chmod +x install.sh bin/*
./install.sh
```

Install **kanata with `cmd` enabled**, then:

```bash
# foreground test
kanata -c ~/.config/kanata/hyperforge.kbd

# start with the desktop (Omarchy / UWSM / Hyprland)
systemctl --user daemon-reload
systemctl --user enable --now hyperforge-kanata.service

# optional: clipboard history watcher (Hyper+P)
systemctl --user enable --now hyperforge-clipboard.service
```

On Omarchy the units are `WantedBy=graphical-session.target`, so they start with Hyprland (not at the greeter) and inherit `WAYLAND_DISPLAY` / `HYPRLAND_*` — required for snaps and the clipboard watcher. Do **not** add kanata to `~/.config/hypr/autostart.lua`; the systemd unit already restarts on failure.

Edit `~/.config/hyperforge-linux/snippets.conf` (seeded by `install.sh`) to add your own snippets, then `hyperforge-snippet --sync`.

Health check:

```bash
hyperforge-doctor
```

Logic smoke tests (no compositor, uinput, or live kanata — same idea as macOS `swift run HyperForgeSmoke`):

```bash
./bin/hyperforge-smoke
```

### uinput / permissions

kanata needs to read keyboards and write to `/dev/uinput`. Typical fixes:

```bash
# group (distro-dependent)
sudo usermod -aG input "$USER"
# log out / in

# udev example — create /etc/udev/rules.d/99-uinput.rules
# KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
sudo modprobe uinput
```

See [kanata Linux docs](https://github.com/jtroo/kanata/blob/main/docs/setup-linux.md).

---

## Bindings (muscle memory)

### Caps = Hyper (hold) · Esc (tap)

| Chord | Action |
|-------|--------|
| Hyper + ←/→/↑/↓ | Snap half |
| Hyper + Enter | Maximize |
| Hyper + **6** | Tile all windows (macOS parity) |
| Hyper + 7 / 8 / 9 / 0 | Quarters TL TR BL BR |
| Hyper + - / = / \\ | Left / center / right **third** |
| Hyper + I / O | Left / right **two-thirds** |
| Hyper + Y | **Almost-max** (~90% centered) |
| Hyper + , | **Snippet picker** (rofi/wofi/fzf) |
| Hyper + P | **Clipboard history** (pinned/searchable picker) |
| Hyper + N | **Pin screen region** (stay-on-top; copy / save / OCR) |
| Hyper + Q | **OCR region** → clipboard |
| Hyper + V | **Paste transforms** (base64, URL, linefeeds…) |
| Hyper + W | Warp mouse to focused window |
| Hyper + K | Keep-alive toggle |
| Hyper + / | Cheat sheet / command catalog |
| Hyper + ' | **Command bar** (search + run) |
| Hyper + C | Center |
| Hyper + A | Always on top / pin (best-effort) |
| Hyper + B / S | Minimize |
| Hyper + X | Close |
| Hyper + Z | Undo layout (Hyprland restores last snap batch) |
| Hyper + M / ] | Next monitor (keeps the same relative snap) |
| Hyper + [ | Previous monitor |
| Hyper + T | Terminal |
| Hyper + F | Files |
| Hyper + 1 / 2 | Browser / Editor |
| Hyper + Esc | Lock session |
| Hyper + . | Type ISO date |
| Hyper + G | Google clipboard |
| Hyper + E | Paste as plain text |
| Hyper + U | Open first URL in clipboard |

**Numpad (Hyper held)** — full spatial pad (same as macOS):

```text
7 TL    8 Top    9 TR
4 Left  5 Max    6 Right
1 BL    2 Bot    3 BR
0 Center
```

macOS disambiguates the third vs. two-thirds chord with Shift (`-` vs `⇧-`).
kanata's Hyper layer doesn't force Shift down the way the 4-mod bridges do, but
sharing a physical key with an OS-level Shift press is still fragile, so
two-thirds and almost-max get their own keys (I / O / Y) instead.

### Snippets (typed hotstrings + Hyper + ,)

`hyperforge-snippet` expands `{{token}}` text the same way as macOS. Typing a
trigger like `@@` or `,sig` replaces itself (kanata `sequence-always-on` +
`visible-backspaced`). Hyper+, still opens a picker. Configure
`~/.config/hyperforge-linux/snippets.conf` (`trigger=expansion`, seeded from
`snippets.example.conf`):

| Token | Expands to |
|-------|------------|
| `{{date}}` | Today, formatted per the config's `date_format` (default `yyyy-MM-dd`) |
| `{{date:MM/dd/yyyy}}` | Today, with a per-snippet format override |
| `{{clipboard}}` | Current clipboard text |
| `{{hostname}}` | This machine's name |
| `{{uuid}}` | A fresh random UUID |
| `{{lan-ip}}` | First non-loopback IPv4 address |

`\n` expands to a real newline. Triggers that contain punctuation (`@@`, `,sig`,
`,date`) expand as you type; all-letter names stay picker-only so typing the
word "email" doesn't fire. After editing the config:

```bash
hyperforge-snippet --sync    # rewrite ~/.config/kanata/hyperforge-snippets.kbd
                             # and restart hyperforge-kanata if it is running
```

`install.sh` seeds the macOS defaults (`@@`, `,sig`, `,date`, `,v`, `,host`)
without overwriting keys you already have. Optional: `systemctl --user enable
--now hyperforge-snippets.path` recompiles when the file changes.

Hyper+, opens a picker (rofi/wofi); `hyperforge-snippet <name>` pastes one
directly. keyd has no typed-hotstring equivalent — picker/chord only.

### Region pin (Hyper + N)

Drag-select a screen region (same slurp/grim path as Omarchy screenshots). The
capture floats **always-on-top** — drag it, **Ctrl+C** or **Copy** to put the
image on the clipboard, **Save** to write a PNG under `~/Pictures`, **OCR**
(if `tesseract` is installed) copies recognized text, **Esc** closes. macOS
uses Hyper+P for this; Linux Hyper+P is clipboard history.

```bash
hyperforge-pin            # select + pin
hyperforge-pin --ocr      # select + OCR → clipboard
hyperforge-pin --file f.png
```

### Clipboard history (Hyper + P)

`hyperforge-clip watch` (via `hyperforge-clipboard.service`) records clipboard
text changes to `~/.local/share/hyperforge-linux/clipboard-history.dat` — same
persisted/pinned shape as the Windows and macOS history. Hyper+P opens a
pinned-first picker (rofi/wofi/fzf); picking an entry copies it and pastes into
the focused window. `hyperforge-clip pin` opens the same picker to toggle pin
instead of pasting. Unpinned entries are capped at 20 (edit `MAX_ITEMS` in the
script); pinned entries never evict.

### Space = nav layer (hold) · space (tap)

| Chord | Action |
|-------|--------|
| Space + H/J/K/L | ← ↓ ↑ → |
| Space + B / W | Word back / forward |
| Space + Y / P / C | Copy / paste / cut |
| Space + U / R | Undo / redo |
| Space + X | Kill to end of line (select EOL + backspace) |
| Space + A | Select line |
| Space + S / F | Save / find |
| Space + , / . | Page up / down |
| Space + 0 / 4 (or Home/End keys on layer) | Line edges |
| Space + Q / M | Escape / Return |

Hold threshold default **200ms** (same idea as macOS SpaceFN). Edit `$tap` / `$hold` in `kanata/hyperforge.kbd`.

---

## Compositor notes

| Environment | Snaps |
|-------------|--------|
| **Hyprland** | `hyprctl` + `jq` geometry (primary); tile + undo layout file |
| **Sway** | `swaymsg` floating resize; tile ≈ exit float / split |
| **X11** | `wmctrl` + `xdotool`; equal grid tile |
| GNOME / KDE Wayland | Limited — use kanata for keys; snaps may need extensions |

Wayland will never match macOS `CGEvent` globally in a portable way. This stack stays below the compositor (kanata) and talks to **one** WM API for windows.

---

## Layout

```
hyperforge-linux/
├── README.md
├── install.sh
├── snippets.example.conf    # seeds ~/.config/hyperforge-linux/snippets.conf
├── bin/
│   ├── hyperforge-snap      # window geometry + tile + thirds/2-thirds/almost-max
│   ├── hyperforge-action    # Hyper command targets (snaps, apps, snippets, clipboard)
│   ├── hyperforge-snippet   # {{token}} text expansion + typed hotstrings
│   ├── hyperforge-clip      # persisted/pinned clipboard history
│   ├── hyperforge-pin       # stay-on-top region capture
│   ├── hyperforge-paste     # clipboard transforms
│   ├── hyperforge-bar       # command bar + cheat sheet
│   ├── hyperforge-config    # export/import snippets + clip history
│   ├── hyperforge-doctor
│   └── hyperforge-smoke     # logic smoke tests (not installed to PATH)
├── kanata/
│   └── hyperforge.kbd       # primary config (numpad + Space nav)
├── keyd/
│   └── hyperforge.conf      # optional system keyd
└── systemd/
    ├── hyperforge-kanata.service
    ├── hyperforge-clipboard.service
    ├── hyperforge-snippets.service
    └── hyperforge-snippets.path
```

---

## keyd alternative

If you prefer a system daemon over user-space kanata:

```bash
./install.sh
sudo cp ~/.local/share/hyperforge-linux/keyd-hyperforge.conf /etc/keyd/hyperforge.conf
sudo keyd reload
```

Adjust `HF_BIN` paths if you install elsewhere (install.sh rewrites them).

---

## Relation to macOS HyperForge

| | macOS | Linux |
|--|-------|--------|
| Input | CGEvent + Karabiner | **kanata** / keyd |
| Space layer | Built into app | kanata `nav` layer (subset) |
| Window pad | Arrows · numpad · thirds/2-thirds/almost-max · 6 tile · Z undo | **Same chords**, 2/3 + almost-max on I/O/Y (no Shift disambiguation) |
| Snippets | Typed-trigger hotstrings, `{{token}}` set | **Same tokens + typed triggers** (`@@`, `,sig`) via kanata sequences; Hyper+, picker still works |
| Clipboard history | Hyper+V panel, persisted/pinned/searchable | Hyper+P picker, persisted/pinned/searchable |
| Profiles / auto-triggers | Wi‑Fi / app / time, per-app overrides | Not ported — no per-process/per-app layer switching here |
| Region pin | Hyper+P stay-on-top capture | Hyper+N (grim/slurp + GTK pin; copy / save / OCR) |
| OCR / command bar / cheat sheet | Built-in | Hyper+Q OCR · Hyper+' command bar · Hyper+/ cheat sheet |
| Shortcuts / AX recipes | Built-in | Not ported |
| Windows | AX / AppKit | hyprctl / sway / wmctrl |
| UI | SwiftUI + Infernal skin | CLI + notify-send |
| Goal | Full companion | Same muscle memory |

---

## Privacy

- No network by default (except optional `google-clip` / `open-url` → browser).  
- No telemetry.  
- Configs live under `~/.config` and `~/.local/share`. Undo layout cache under `~/.cache/hyperforge-linux`.
- Clipboard history is plain text at `~/.local/share/hyperforge-linux/clipboard-history.dat` (base64-encoded lines, not encrypted) — treat it like shell history.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `./bin/hyperforge-smoke` fails | logic regression — see the ✗ line; does not need a running compositor |
| `cmd is not enabled for this kanata executable` | rebuild with `cargo install kanata --features cmd` (or install a `cmd_allowed` binary) |
| Caps / Space / chords do nothing | Two common causes: (1) kanata grabbed `System Control` — `sudo usermod -aG input "$USER"` and log out. (2) **Keychron/VIA already maps Caps to Ctrl+Alt+Super** (no `KEY_CAPSLOCK`). On Omarchy, copy `hypr/omarchy-bindings.lua` into `~/.config/hypr/bindings.lua`. |
| kanata can’t open devices | input group, uinput udev, log out |
| Snaps do nothing on Hyprland | Hyprland 0.55+ needs Lua `hyprctl dispatch` (this kit now does). Run `hyperforge-snap left` in a terminal — it should float the focused window to the left half. If that works but Caps+arrow does not, hold Caps then press the arrow (or update to `tap-hold-press`). |
| Numpad pad silent | ensure keyboard sends `kp0`–`kp9`; laptop may need Fn |
| Space layer feels sticky | lower `$tap` / `$hold` (e.g. 120) in `hyperforge.kbd` |
| Want 4-mod Hyper for apps | use a separate kanata alias with `(multi lctl lalt lmet lsft)` instead of a layer |
| Hyper+, / Hyper+P do nothing | on Omarchy the overlay picker (`omarchy-menu-select`) is used; elsewhere install `rofi` or `wofi`. Release Caps before choosing — leftover Ctrl+Alt+Super turns each letter into another Hyper chord. |
| Clipboard history stays empty | `systemctl --user enable --now hyperforge-clipboard.service` (not started by `hyperforge-kanata.service`) |
| Snippet types nothing | check the trigger name matches a key in `~/.config/hyperforge-linux/snippets.conf` (not the reserved `date_format` key) |
| Typing `@@` does nothing | `@@=you@example.com` in snippets.conf, then `hyperforge-snippet --sync`, then restart kanata. Re-run `install.sh` if `hyperforge.kbd` has no `sequence-always-on`. Edit the email value to yours. |

Doctor (session / permissions / helpers):

```bash
hyperforge-doctor
```

Smoke (pure logic — action routing, snap math, snippets, clipboard store, kanata/keyd shape):

```bash
./bin/hyperforge-smoke
```
