-- Leader Key Configuration
vim.g.mapleader = " "      -- Use <space> as the leader key
vim.g.maplocalleader = " " -- Same for local leader

-- Remove Search Highlight  See `:help hlsearch`
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Update Neovim
vim.keymap.set("n", "<leader>o", ":update<CR> :source<CR>")

-- Fzf — desc is what which-key shows in the popup
local fzf = function(fn)
  return function()
    require("fzf-lua")[fn]()
  end
end
-- NOTE: <C-h/j/k/l> are claimed by window movement further down this file, and
-- the later mapping wins. Pickers that would collide use <leader> + the same
-- letter instead, so the muscle memory carries over.
vim.keymap.set("n", "<C-\\>", fzf("buffers"), { desc = "Find buffers" })
vim.keymap.set("n", "<leader>k", fzf("builtin"), { desc = "Find fzf-lua pickers" })
vim.keymap.set("n", "<C-p>", fzf("files"), { desc = "Find files" })
vim.keymap.set("n", "<leader>l", fzf("live_grep"), { desc = "Live grep" })
vim.keymap.set("n", "<C-g>", fzf("grep_project"), { desc = "Grep project" })
vim.keymap.set("n", "<F1>", fzf("help_tags"), { desc = "Find help tags" })

-- Grapple
vim.keymap.set("n", "<leader>a", function()
  require("grapple").toggle()
end, { desc = "Grapple: toggle file tag" })
vim.keymap.set("n", "<C-e>", function()
  require("grapple").toggle_tags()
end, { desc = "Grapple: toggle tag list" })

-- Lsp
vim.keymap.set("n", "gd", ":lua vim.lsp.buf.definition()<CR>", { desc = "Go to definition" })
vim.keymap.set("n", "gD", ":lua vim.lsp.buf.declaration()<CR>", { desc = "Go to declaration" })
vim.keymap.set("n", "gi", ":lua vim.lsp.buf.implementation()<CR>", { desc = "Go to implementation" })
vim.keymap.set("n", "gr", ":lua vim.lsp.buf.references()<CR>", { desc = "List references" })
vim.keymap.set("n", "<leader>rn", ":lua vim.lsp.buf.rename()<CR>", { desc = "Rename symbol" })
vim.keymap.set("n", "<leader>ca", ":lua vim.lsp.buf.code_action()<CR>", { desc = "Code action" })
vim.keymap.set("n", "<leader>q", ":lua vim.diagnostic.setloclist()<CR>", { desc = "Set quickfix list" })
-- conform routes to stylua/prettierd per filetype and falls back to the LSP when
-- the filetype has no formatter configured (see FORMATTING in base.lua)
vim.keymap.set("n", "<leader>f", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })

local diagnostic_float_win = nil
local function toggle_diagnostic_float()
  local api = vim.api
  if diagnostic_float_win and api.nvim_win_is_valid(diagnostic_float_win) then
    api.nvim_set_current_win(diagnostic_float_win)
  else
    local bufnr = api.nvim_get_current_buf()
    local opts = { focus = false }
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.diagnostic.open_float(bufnr, opts)
    local wins = api.nvim_tabpage_list_wins(0)
    for _, w in ipairs(wins) do
      local config = api.nvim_win_get_config(w)
      if config.relative ~= '' then
        diagnostic_float_win = w
        break
      end
    end
  end
end

vim.keymap.set("n", "<leader>e", toggle_diagnostic_float, { desc = "Toggle diagnostic float and focus" })

--  Use CTRL+<hjkl> to switch between windows
--  See `:help wincmd` for a list of all window commands
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking (copying) text",
  group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
  callback = function()
    vim.hl.on_yank() -- vim.highlight was renamed to vim.hl (:help deprecated)
  end,
})

-- Move Code
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Overide default when centering
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
