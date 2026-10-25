-- Neovim: lazy.nvim, a colour scheme generated from the wallpaper (lua/palette.lua, rewritten by matugen).
vim.g.mapleader = " "
vim.g.maplocalleader = ","

local o = vim.opt
o.number = true
o.relativenumber = true
o.cursorline = true
o.termguicolors = true
o.signcolumn = "yes"
o.scrolloff = 8
o.sidescrolloff = 8
o.splitright = true
o.splitbelow = true
o.ignorecase = true
o.smartcase = true
o.undofile = true
o.swapfile = false
o.updatetime = 200
o.timeoutlen = 300
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false
o.mouse = "a"
o.showmode = false
o.laststatus = 3
o.pumheight = 12
o.pumblend = 10
o.winblend = 10
o.clipboard = "unnamedplus"
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.fillchars = { eob = " ", vert = "│", horiz = "─" }
pcall(function() o.winborder = "rounded" end)
-- cursor: block in normal, bar in insert, underline in replace; colours come from the palette (Cursor* groups)
o.guicursor = "n-v-c-sm:block-Cursor,i-ci-ve:ver25-CursorInsert,r-cr-o:hor20-CursorReplace,a:blinkon0"

local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<cr>")
map({ "i", "n", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save" })
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<C-h>", "<C-w>h"); map("n", "<C-j>", "<C-w>j"); map("n", "<C-k>", "<C-w>k"); map("n", "<C-l>", "<C-w>l")
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("v", "<", "<gv"); map("v", ">", ">gv")
map("v", "J", ":m '>+1<cr>gv=gv"); map("v", "K", ":m '<-2<cr>gv=gv")
map("n", "<leader>tt", function() require("theme").reload() end, { desc = "Reload theme" })

vim.api.nvim_create_autocmd("TextYankPost", { callback = function() vim.hl.on_yank({ timeout = 150 }) end })
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(ev)
    local m = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if m[1] > 0 and m[1] <= vim.api.nvim_buf_line_count(ev.buf) then pcall(vim.api.nvim_win_set_cursor, 0, m) end
  end,
})
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local b = { buffer = ev.buf }
    map("n", "gd", vim.lsp.buf.definition, b); map("n", "gr", vim.lsp.buf.references, b)
    map("n", "K", vim.lsp.buf.hover, b); map("n", "<leader>rn", vim.lsp.buf.rename, b)
    map("n", "<leader>ca", vim.lsp.buf.code_action, b)
  end,
})
vim.diagnostic.config({ virtual_text = { prefix = "●" }, severity_sort = true, float = { border = "rounded" } })

-- plugins
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup("plugins", {
  install = { colorscheme = { "wallpaper" } },
  checker = { enabled = false },
  change_detection = { notify = false },
  ui = { border = "rounded" },
})

require("theme").setup()
