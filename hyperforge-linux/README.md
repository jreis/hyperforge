# HyperForge for Linux

**Caps → Hyper · Space-layer HJKL · window snaps** for Linux — same muscle memory as the macOS app.

This is **not** a Swift/AppKit port. It is a small, honest stack:

| Piece | Role |
|-------|------|
| **[kanata](https://github.com/jtroo/kanata)** (preferred) | Caps Hyper layer + Space nav layer |
| **[keyd](https://github.com/rvaiya/keyd)** (optional) | Same idea as a system service |
| **`hyperforge-snap`** | Half / quarter / max for **Hyprland**, **Sway**, or **X11** |
| **`hyperforge-action`** | Apps, lock, date, google clipboard |
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
| Hyper + 7 / 8 / 9 / 0 | Quarters TL TR BL BR |
| Hyper + C | Center |
| Hyper + X | Close |
| Hyper + Z | Undo / untile (best-effort) |
| Hyper + T | Terminal |
| Hyper + F | Files |
| Hyper + 1 / 2 | Browser / Editor |
| Hyper + Esc | Lock session |
| Hyper + . | Type ISO date |
| Hyper + G | Google clipboard |
| Hyper + M | Copy hostname |

### Space = nav layer (hold) · space (tap)

| Chord | Action |
|-------|--------|
| Space + H/J/K/L | ← ↓ ↑ → |
| Space + B / W | Word back / forward (Ctrl+arrows on nav layer via keyd; kanata: use arrows) |
| Space + 0 / 4 (home/end keys on layer) | Line edges |

Hold threshold default **200ms** (same idea as macOS SpaceFN). Edit `$tap` in `kanata/hyperforge.kbd`.

---

## Compositor notes

| Environment | Snaps |
|-------------|--------|
| **Hyprland** | `hyprctl` + `jq` geometry (primary) |
| **Sway** | `swaymsg` floating resize |
| **X11** | `wmctrl` + `xdotool` |
| GNOME / KDE Wayland | Limited — use kanata for keys; snaps may need extensions |

Wayland will never match macOS `CGEvent` globally in a portable way. This stack stays below the compositor (kanata) and talks to **one** WM API for windows.

---

## Layout

```
hyperforge-linux/
├── README.md
├── install.sh
├── bin/
│   ├── hyperforge-snap      # window geometry
│   ├── hyperforge-action    # Hyper command targets
│   └── hyperforge-doctor
├── kanata/
│   └── hyperforge.kbd       # primary config
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
| Space layer | Built into app | kanata `nav` layer |
| Windows | AX / AppKit | hyprctl / sway / wmctrl |
| UI | SwiftUI + Infernal skin | CLI + notify-send |
| Goal | Same chords | Same chords |

---

## Privacy

- No network by default (except optional `google-clip` → browser).  
- No telemetry.  
- Configs live under `~/.config` and `~/.local/share`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| kanata can’t open devices | input group, uinput udev, log out |
| Snaps do nothing on Hyprland | install `jq`; run `hyperforge-snap left` in a terminal |
| Space layer feels sticky | lower `$tap` (e.g. 120) in `hyperforge.kbd` |
| Want 4-mod Hyper for apps | use a separate kanata alias with `(multi lctl lalt lmet lsft)` instead of a layer |

Doctor:

```bash
hyperforge-doctor
```
