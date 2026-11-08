-- caelestia-rice: variable overrides, merged over variables.lua by key.
-- Ported from the niri setup. Keep this a plain table of overrides only.
return {
    -- Apps (niri used kitty)
    terminal             = "kitty",

    -- Input feel, matched to the niri rice
    touchpadScrollFactor = 0.6, -- caelestia default 0.3; snappier, closer to niri

    -- Keybinds carried over from niri
    kbTerminal           = { "SUPER + Return", "SUPER + T" }, -- Mod+Return muscle memory, keep Super+T too
    kbMoveWinToWsSpecial = "CTRL + SUPER + SHIFT + Up",       -- free up SUPER+ALT+S for explain-shot below
}
