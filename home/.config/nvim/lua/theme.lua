-- Colour scheme built from lua/palette.lua. matugen rewrites that file on every wallpaper change and
-- the watcher below re-applies it live in every running Neovim.
local M = {}

local function hex2rgb(h) h = h:gsub("#", ""); return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) end
local function mix(a, b, t)
  local ar, ag, ab = hex2rgb(a); local br, bg, bb = hex2rgb(b)
  return string.format("#%02x%02x%02x", ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

local function palette()
  package.loaded["palette"] = nil
  local ok, p = pcall(require, "palette")
  if ok then return p end
  return { mode = "dark", bg = "#191d24", bg_low = "#1e222a", bg_mid = "#242933", bg_high = "#2e3440", fg = "#d8dee9", fg_dim = "#aab1c0",
    outline = "#616e88", outline_var = "#3b4252", primary = "#88c0d0", on_primary = "#191d24", primary_container = "#3b4a5a",
    on_primary_container = "#d8dee9", secondary = "#81a1c1", tertiary = "#b48ead", error = "#bf616a", red = "#bf616a",
    green = "#a3be8c", yellow = "#ebcb8b", blue = "#81a1c1", magenta = "#b48ead", cyan = "#88c0d0" }
end

M.palette = palette()

function M.apply()
  local c = palette()
  M.palette = c
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
  vim.o.background = c.mode == "light" and "light" or "dark"
  vim.g.colors_name = "wallpaper"

  local function hl(group, spec) vim.api.nvim_set_hl(0, group, spec) end
  local none = "NONE"   -- let kitty's (translucent, blurred) background show through

  -- editor
  hl("Normal", { fg = c.fg, bg = none })
  hl("NormalNC", { fg = c.fg, bg = none })
  hl("NormalFloat", { fg = c.fg, bg = c.bg_low })
  hl("FloatBorder", { fg = c.primary, bg = c.bg_low })
  hl("FloatTitle", { fg = c.on_primary, bg = c.primary, bold = true })
  hl("Cursor", { fg = c.on_primary, bg = c.primary })
  hl("CursorInsert", { fg = c.on_primary, bg = c.tertiary })
  hl("CursorReplace", { fg = c.on_primary, bg = c.red })
  hl("lCursor", { link = "Cursor" })
  hl("TermCursor", { link = "Cursor" })
  hl("CursorLine", { bg = mix(c.bg, c.bg_high, 0.55) })
  hl("CursorColumn", { link = "CursorLine" })
  hl("ColorColumn", { bg = c.bg_low })
  hl("LineNr", { fg = c.outline })
  hl("CursorLineNr", { fg = c.primary, bold = true })
  hl("SignColumn", { bg = none })
  hl("FoldColumn", { fg = c.outline, bg = none })
  hl("Folded", { fg = c.fg_dim, bg = c.bg_low })
  hl("VertSplit", { fg = c.outline_var }); hl("WinSeparator", { fg = c.outline_var })
  hl("EndOfBuffer", { fg = c.bg })
  hl("NonText", { fg = c.outline_var }); hl("Whitespace", { fg = c.outline_var }); hl("SpecialKey", { fg = c.outline_var })
  hl("Visual", { bg = c.primary_container }); hl("VisualNOS", { link = "Visual" })
  hl("Search", { fg = c.on_primary_container, bg = mix(c.primary_container, c.yellow, 0.35) })
  hl("CurSearch", { fg = c.on_primary, bg = c.primary, bold = true }); hl("IncSearch", { link = "CurSearch" })
  hl("Substitute", { fg = c.on_primary, bg = c.red })
  hl("MatchParen", { fg = c.primary, bold = true, underline = true })
  hl("StatusLine", { fg = c.fg, bg = c.bg_low }); hl("StatusLineNC", { fg = c.fg_dim, bg = c.bg_low })
  hl("WinBar", { fg = c.fg_dim, bg = none }); hl("WinBarNC", { fg = c.outline, bg = none })
  hl("TabLine", { fg = c.fg_dim, bg = c.bg_low }); hl("TabLineSel", { fg = c.on_primary, bg = c.primary, bold = true }); hl("TabLineFill", { bg = c.bg_low })
  hl("Pmenu", { fg = c.fg, bg = c.bg_low }); hl("PmenuSel", { fg = c.on_primary_container, bg = c.primary_container, bold = true })
  hl("PmenuSbar", { bg = c.bg_mid }); hl("PmenuThumb", { bg = c.outline })
  hl("WildMenu", { link = "PmenuSel" })
  hl("MsgArea", { fg = c.fg }); hl("ModeMsg", { fg = c.primary, bold = true }); hl("MoreMsg", { fg = c.green }); hl("Question", { fg = c.cyan })
  hl("ErrorMsg", { fg = c.red, bold = true }); hl("WarningMsg", { fg = c.yellow })
  hl("Directory", { fg = c.blue }); hl("Title", { fg = c.primary, bold = true })
  hl("SpellBad", { undercurl = true, sp = c.red }); hl("SpellCap", { undercurl = true, sp = c.yellow })
  hl("SpellLocal", { undercurl = true, sp = c.cyan }); hl("SpellRare", { undercurl = true, sp = c.magenta })
  hl("QuickFixLine", { bg = c.primary_container, bold = true })

  -- syntax
  hl("Comment", { fg = c.outline, italic = true })
  hl("Constant", { fg = c.yellow }); hl("String", { fg = c.green }); hl("Character", { fg = c.green })
  hl("Number", { fg = c.tertiary }); hl("Boolean", { fg = c.tertiary }); hl("Float", { fg = c.tertiary })
  hl("Identifier", { fg = c.fg }); hl("Function", { fg = c.blue })
  hl("Statement", { fg = c.primary }); hl("Conditional", { fg = c.primary, italic = true }); hl("Repeat", { fg = c.primary, italic = true })
  hl("Label", { fg = c.primary }); hl("Operator", { fg = c.secondary }); hl("Keyword", { fg = c.primary, italic = true }); hl("Exception", { fg = c.red })
  hl("PreProc", { fg = c.magenta }); hl("Include", { fg = c.magenta }); hl("Define", { fg = c.magenta }); hl("Macro", { fg = c.magenta }); hl("PreCondit", { fg = c.magenta })
  hl("Type", { fg = c.cyan }); hl("StorageClass", { fg = c.cyan }); hl("Structure", { fg = c.cyan }); hl("Typedef", { fg = c.cyan })
  hl("Special", { fg = c.secondary }); hl("SpecialChar", { fg = c.tertiary }); hl("Tag", { fg = c.primary }); hl("Delimiter", { fg = c.fg_dim })
  hl("SpecialComment", { fg = c.outline, italic = true }); hl("Debug", { fg = c.red })
  hl("Underlined", { underline = true }); hl("Error", { fg = c.red }); hl("Todo", { fg = c.on_primary, bg = c.yellow, bold = true })
  hl("@variable", { fg = c.fg }); hl("@variable.builtin", { fg = c.red, italic = true }); hl("@variable.parameter", { fg = mix(c.fg, c.tertiary, 0.35) })
  hl("@property", { fg = mix(c.fg, c.cyan, 0.4) }); hl("@field", { link = "@property" })
  hl("@constructor", { fg = c.cyan }); hl("@punctuation", { fg = c.fg_dim }); hl("@tag.attribute", { fg = c.yellow })
  hl("@markup.heading", { fg = c.primary, bold = true }); hl("@markup.link", { fg = c.blue, underline = true })
  hl("@markup.strong", { bold = true }); hl("@markup.italic", { italic = true }); hl("@markup.raw", { fg = c.green })

  -- diagnostics / lsp / diff
  hl("DiagnosticError", { fg = c.red }); hl("DiagnosticWarn", { fg = c.yellow }); hl("DiagnosticInfo", { fg = c.blue }); hl("DiagnosticHint", { fg = c.cyan })
  hl("DiagnosticOk", { fg = c.green })
  for k, col in pairs({ Error = c.red, Warn = c.yellow, Info = c.blue, Hint = c.cyan }) do
    hl("DiagnosticUnderline" .. k, { undercurl = true, sp = col })
    hl("DiagnosticVirtualText" .. k, { fg = col, bg = mix(c.bg, col, 0.12) })
  end
  hl("LspReferenceText", { bg = c.bg_mid }); hl("LspReferenceRead", { bg = c.bg_mid }); hl("LspReferenceWrite", { bg = c.bg_high })
  hl("DiffAdd", { bg = mix(c.bg, c.green, 0.2) }); hl("DiffChange", { bg = mix(c.bg, c.blue, 0.18) })
  hl("DiffDelete", { bg = mix(c.bg, c.red, 0.2) }); hl("DiffText", { bg = mix(c.bg, c.blue, 0.38) })
  hl("Added", { fg = c.green }); hl("Changed", { fg = c.blue }); hl("Removed", { fg = c.red })

  -- plugins
  hl("TelescopeNormal", { fg = c.fg, bg = c.bg_low }); hl("TelescopeBorder", { fg = c.outline_var, bg = c.bg_low })
  hl("TelescopePromptNormal", { fg = c.fg, bg = c.bg_mid }); hl("TelescopePromptBorder", { fg = c.bg_mid, bg = c.bg_mid })
  hl("TelescopePromptTitle", { fg = c.on_primary, bg = c.primary, bold = true }); hl("TelescopePreviewTitle", { fg = c.on_primary, bg = c.green, bold = true })
  hl("TelescopeResultsTitle", { fg = c.bg_low, bg = c.bg_low }); hl("TelescopeSelection", { bg = c.primary_container, bold = true })
  hl("TelescopeMatching", { fg = c.primary, bold = true })
  hl("GitSignsAdd", { fg = c.green }); hl("GitSignsChange", { fg = c.blue }); hl("GitSignsDelete", { fg = c.red })
  hl("IblIndent", { fg = mix(c.bg, c.outline_var, 0.7) }); hl("IblScope", { fg = c.primary })
  hl("WhichKey", { fg = c.primary }); hl("WhichKeyGroup", { fg = c.blue }); hl("WhichKeyDesc", { fg = c.fg }); hl("WhichKeySeparator", { fg = c.outline })
  hl("WhichKeyNormal", { bg = c.bg_low }); hl("WhichKeyBorder", { fg = c.primary, bg = c.bg_low })
  hl("OilDir", { fg = c.blue, bold = true }); hl("OilFile", { fg = c.fg }); hl("OilLink", { fg = c.cyan }); hl("OilCreate", { fg = c.green })
  hl("OilDelete", { fg = c.red }); hl("OilMove", { fg = c.yellow }); hl("OilChange", { fg = c.blue })
  hl("LazyNormal", { bg = c.bg_low }); hl("LazyButton", { bg = c.bg_mid }); hl("LazyButtonActive", { fg = c.on_primary, bg = c.primary, bold = true })
  hl("LazyH1", { fg = c.on_primary, bg = c.primary, bold = true })

  vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
end

function M.reload()
  M.apply()
  pcall(function() require("lualine").setup(require("lualine_opts")()) end)
  vim.notify("theme reloaded", vim.log.levels.INFO)
end

local watcher
function M.setup()
  M.apply()
  -- re-apply live when matugen rewrites the palette (rename-based writes, so watch the directory)
  local dir = vim.fn.stdpath("config") .. "/lua"
  watcher = vim.uv.new_fs_event()
  local timer = vim.uv.new_timer()
  watcher:start(dir, {}, function(err, fname)
    if err or fname ~= "palette.lua" then return end
    timer:stop()
    timer:start(120, 0, vim.schedule_wrap(function()
      M.apply()
      pcall(function() require("lualine").setup(require("lualine_opts")()) end)
    end))
  end)
end

return M
