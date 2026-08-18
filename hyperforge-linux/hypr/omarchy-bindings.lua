-- HyperForge on Omarchy / Hyprland — firmware Hyper (Ctrl+Alt+Super).
--
-- Some boards (Keychron VIA/QMK) remap Caps to Ctrl+Alt+Super instead of
-- sending KEY_CAPSLOCK. The kanata Caps layer never sees that key; bind the
-- combo here instead. Copy into ~/.config/hypr/bindings.lua (or require this
-- file from it).
--
-- Do not use { launch = ... } — snaps must run in-process, not via uwsm-app.

-- Omarchy already binds a few of these; unbind first if you copy this in.
hl.unbind("SUPER + CTRL + ALT + B") -- was: Show battery remaining
hl.unbind("SUPER + CTRL + ALT + T") -- was: Show time
hl.unbind("SUPER + CTRL + ALT + Z") -- was: Reset zoom

do
  local hf = os.getenv("HOME") .. "/.local/bin/hyperforge-action"
  local function h(key, desc, id, opts)
    o.bind("CTRL + ALT + SUPER + " .. key, desc, hf .. " " .. id, opts)
  end
  h("LEFT", "Hyper snap left", "win-left")
  h("RIGHT", "Hyper snap right", "win-right")
  h("UP", "Hyper snap top", "win-top")
  h("DOWN", "Hyper snap bottom", "win-bottom")
  h("RETURN", "Hyper maximize", "win-max")
  h("C", "Hyper center", "win-center")
  h("X", "Hyper close", "win-close")
  h("Z", "Hyper undo snap", "win-undo")
  h("B", "Hyper minimize", "win-min")
  h("S", "Hyper minimize", "win-min")
  h("M", "Hyper next monitor", "win-next")
  h("BRACKETLEFT", "Hyper previous monitor", "win-prev")
  h("BRACKETRIGHT", "Hyper next monitor", "win-next")
  h("A", "Hyper always on top", "always-on-top")
  h("6", "Hyper tile all", "win-tile")
  h("7", "Hyper quarter TL", "win-tl")
  h("8", "Hyper quarter TR", "win-tr")
  h("9", "Hyper quarter BL", "win-bl")
  h("0", "Hyper quarter BR", "win-br")
  h("MINUS", "Hyper third left", "win-third-l")
  h("EQUAL", "Hyper third right", "win-third-r")
  h("BACKSLASH", "Hyper third center", "win-third-c")
  h("I", "Hyper two-thirds left", "win-2third-l")
  h("O", "Hyper two-thirds right", "win-2third-r")
  h("Y", "Hyper almost-max", "win-almost-max")
  h("N", "Hyper pin region", "region-pin", { repeating = false })
  h("COMMA", "Hyper snippet picker", "snippet-pick", { repeating = false })
  h("P", "Hyper clipboard history", "clip-show", { repeating = false })
  h("T", "Hyper terminal", "term")
  h("F", "Hyper files", "files")
  h("1", "Hyper browser", "browser")
  h("2", "Hyper editor", "editor")
  h("PERIOD", "Hyper insert date", "date")
  h("G", "Hyper google clipboard", "google-clip")
  h("E", "Hyper plain paste", "plain-paste")
  h("U", "Hyper open URL", "open-url")
  h("ESCAPE", "Hyper lock", "lock")
end
