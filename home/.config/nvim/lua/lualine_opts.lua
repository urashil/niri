-- lualine options, built from the live palette (re-run by theme.lua when the wallpaper changes)
return function()
  local c = require("theme").palette
  local function mode(bg)
    return {
      a = { fg = c.on_primary, bg = bg, gui = "bold" },
      b = { fg = c.fg, bg = c.bg_mid },
      c = { fg = c.fg_dim, bg = c.bg_low },
    }
  end
  local theme = {
    normal = mode(c.primary), insert = mode(c.tertiary), visual = mode(c.yellow),
    replace = mode(c.red), command = mode(c.green), terminal = mode(c.cyan),
    inactive = { a = { fg = c.outline, bg = c.bg_low }, b = { fg = c.outline, bg = c.bg_low }, c = { fg = c.outline, bg = c.bg_low } },
  }
  return {
    options = {
      theme = theme,
      globalstatus = true,
      component_separators = "",
      section_separators = { left = "\u{e0b4}", right = "\u{e0b6}" },
      disabled_filetypes = { statusline = { "lazy" } },
    },
    sections = {
      lualine_a = { { "mode", separator = { left = "\u{e0b6}", right = "\u{e0b4}" }, right_padding = 2 } },
      lualine_b = { "branch", { "diff", symbols = { added = " ", modified = " ", removed = " " } } },
      lualine_c = { { "filename", path = 1 }, { "diagnostics", symbols = { error = " ", warn = " ", info = " ", hint = "󰌵 " } } },
      lualine_x = { "encoding", { "filetype", icon_only = false } },
      lualine_y = { "progress" },
      lualine_z = { { "location", separator = { left = "\u{e0b6}", right = "\u{e0b4}" }, left_padding = 2 } },
    },
  }
end
