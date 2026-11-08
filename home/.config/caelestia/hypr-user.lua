-- caelestia-rice: raw Hyprland (lua) config + custom binds. Loaded last, so this wins.
-- Ported from the niri setup.
local home = os.getenv("HOME")

-- Cursor speed, matched to the niri rice (libinput accel-speed 0.25)
hl.config({
    input = {
        sensitivity = 0.25,
    },
})

-- Custom keybinds for standalone tools carried over from niri.
-- (Module binds — Ask Claude, Memorize, mitch.pro — arrive with the shell port.)
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd(home .. "/.local/bin/explain-shot")) -- explain a screen region (Claude)
hl.bind("SUPER + grave", hl.dsp.exec_cmd(home .. "/.local/bin/scratch"))        -- scratch terminal

-- NOTE: niri-style scrollable tiling (hyprscroller) is NOT enabled: it fails to
-- build against Hyprland 0.57.1. The scroller layout/plugin/binds were removed so
-- the config stays clean. We'll re-add them once a scrolling plugin builds for
-- this Hyprland version (likely the official hyprscrolling plugin).
