# HyperForge for Linux

**Caps → Hyper · Space-layer HJKL · window snaps** for Linux — same muscle memory as the macOS app.

**Parity target:** macOS HyperForge **0.4.x** (window pad, tile-all, Space nav subset). This is **not** a Swift/AppKit port.

| Piece | Role |
|-------|------|
| **[kanata](https://github.com/jtroo/kanata)** (preferred) | Caps Hyper layer + Space nav layer + numpad pad |
| **[keyd](https://github.com/rvaiya/keyd)** (optional) | Same idea as a system service |
| **`hyperforge-snap`** | Half / quarter / max / **tile** for **Hyprland**, **Sway**, or **X11** |
| **`hyperforge-action`** | Apps, lock, date, google clipboard, plain paste, open URL |
| **`hyperforge-doctor`** | Setup health check |

Sibling of:

- macOS: [jreis/hyperforge](https://github.com/jreis/hyperforge)
- Windows: [`hyperforge-win/`](../hyperforge-win/)

---

## Requirements

- Linux with either:
  - **Wayland:** Hyprland or Sway (best), or  
  - **X11:** `wmctrl` + `xdotool`
- **kanata** (or keyd)
- `jq` for Hyprland geometry snaps  
- Optional: `notify-send`, `wtype` / `ydotool`, `wl-clipboard`

---

## Quick start

```bash
cd hyperforge-linux
chmod +x install.sh bin/*
./install.sh
```

Install **kanata**, then:

```bash
# foreground test
kanata -c ~/.config/kanata/hyperforge.kbd

# or user service
systemctl --user daemon-reload
systemctl --user enable --now hyperforge-kanata.service
```

Health check:

```bash
hyperforge-doctor
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
| Hyper + C | Center |
| Hyper + A | Always on top / pin (best-effort) |
| Hyper + B / S | Minimize |
| Hyper + X | Close |
| Hyper + Z | Undo layout (Hyprland restores last snap batch) |
| Hyper + M | Next monitor / output |
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

Hold threshold default **200ms** (same idea as macOS SpaceFN). Edit `$tap` in `kanata/hyperforge.kbd`.

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
├── bin/
│   ├── hyperforge-snap      # window geometry + tile
│   ├── hyperforge-action    # Hyper command targets
│   └── hyperforge-doctor
├── kanata/
│   └── hyperforge.kbd       # primary config (numpad + Space nav)
├── keyd/
│   └── hyperforge.conf      # optional system keyd
└── systemd/
    └── hyperforge-kanata.service
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
| Window pad | Arrows · numpad · 6 tile · Z undo | **Same chords** |
| Windows | AX / AppKit | hyprctl / sway / wmctrl |
| UI | SwiftUI + Infernal skin | CLI + notify-send |
| Goal | Full companion | Same muscle memory |

---

## Privacy

- No network by default (except optional `google-clip` / `open-url` → browser).  
- No telemetry.  
- Configs live under `~/.config` and `~/.local/share`. Undo layout cache under `~/.cache/hyperforge-linux`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| kanata can’t open devices | input group, uinput udev, log out |
| Snaps do nothing on Hyprland | install `jq`; run `hyperforge-snap left` in a terminal |
| Numpad pad silent | ensure keyboard sends `kp0`–`kp9`; laptop may need Fn |
| Space layer feels sticky | lower `$tap` (e.g. 120) in `hyperforge.kbd` |
| Want 4-mod Hyper for apps | use a separate kanata alias with `(multi lctl lalt lmet lsft)` instead of a layer |

Doctor:

```bash
hyperforge-doctor
```
