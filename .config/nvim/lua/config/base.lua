-- Interface Settings
vim.opt.number = true -- Show absolute line numbers
vim.opt.relativenumber = true -- Show relative line numbers
vim.opt.cursorline = true -- Highlight current line
vim.wo.signcolumn = "yes" -- Always show signcolumn (for Git, LSP, etc.)
vim.opt.wrap = false -- Don't wrap long lines
vim.opt.scrolloff = 10 -- Minimum lines above/below cursor
vim.opt.colorcolumn = "80" -- Style Guide Vertical Line to guide lenght of code

-- Visuals & Characters
vim.o.termguicolors = true -- Enable full RGB color support
vim.opt.list = true -- Show invisible characters
vim.opt.listchars = {
	tab = "» ", -- Show tabs as »
	trail = "·", -- Show trailing spaces
	nbsp = "␣", -- Show non-breaking space
}

-- Tabs & Indentation
vim.o.tabstop = 2 -- Tab character = 2 spaces (visually)
vim.o.expandtab = true -- Pressing <Tab> inserts spaces
vim.o.softtabstop = 2 -- Tab key = 2 spaces
vim.o.shiftwidth = 2 -- Indentation = 2 spaces
vim.o.breakindent = true -- Indent wrapped lines properly

-- Search Behavior
vim.o.hlsearch = true -- Highlight search matches (<Esc> clears them — see key.lua)
vim.o.ignorecase = true -- Ignore case when searching...
vim.o.smartcase = true -- ...unless capital letters are used

-- Clipboard & Undo
vim.o.clipboard = "unnamedplus" -- Use system clipboard (works with Ctrl+C / Ctrl+V)
vim.o.undofile = true -- Save undo history to disk
vim.o.swapfile = false -- Disable swap file

-- Mouse & Splits
vim.o.mouse = "a" -- Enable mouse in all modes
vim.opt.splitright = true -- Vertical splits open to the right
vim.opt.splitbelow = true -- Horizontal splits open below

-- Command Behavior
vim.opt.inccommand = "split" -- Show live preview of substitutions eg. %s/foo/bar/g open new split at bottom with live preview
vim.o.completeopt = "menuone,noselect" -- Better completion experience

-- Performance Tweaks
vim.o.updatetime = 250 -- Faster CursorHold, LSP updates, etc.
vim.o.timeoutlen = 300 -- Timeout for mapped sequence

-- Relative to :pwd
vim.api.nvim_create_user_command("CopyRFP", function()
	vim.fn.setreg("+", vim.fn.expand("%:."))
end, {})

vim.api.nvim_create_user_command("CopyRDP", function()
	vim.fn.setreg("+", vim.fn.expand("%:.:h"))
end, {})

vim.api.nvim_create_user_command("CopyRCWD", function()
	vim.fn.setreg("+", ".")
end, {})

-- Absolute paths
vim.api.nvim_create_user_command("CopyFP", function()
	vim.fn.setreg("+", vim.fn.expand("%:p"))
end, {})

vim.api.nvim_create_user_command("CopyFDP", function()
	vim.fn.setreg("+", vim.fn.expand("%:p:h"))
end, {})

vim.api.nvim_create_user_command("CopyCWD", function()
	vim.fn.setreg("+", vim.uv.cwd())
end, {})

-- =========================
-- Plugin manager: vim.pack
-- =========================
-- Neovim 0.12's built-in manager (`:help vim.pack`). It clones into
-- stdpath("data")/site/pack/core/opt and records revisions in
-- config/nvim/nvim-pack-lock.json — commit that file, and every host installs
-- the exact same plugin revisions. `:lua vim.pack.update()` fetches updates and
-- opens a confirmation buffer (:write to accept, :quit to discard).
--
-- Unlike lazy.nvim there is no lazy-loading and no dependency resolution: every
-- plugin below loads at startup, and dependencies must be listed before the
-- plugin that needs them.

---@param repo string
---@return string
local function gh(repo)
	return "https://github.com/" .. repo
end

-- Build hooks. Must be registered BEFORE the first vim.pack.add() so they also
-- fire on a first-run install, not just on later updates (`:help vim.pack-events`).
vim.api.nvim_create_autocmd("PackChanged", {
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if kind ~= "install" and kind ~= "update" then
			return
		end

		if name == "nvim-treesitter" then
			-- the plugin may not be loaded yet when installing from the lockfile
			if not ev.data.active then
				vim.cmd.packadd("nvim-treesitter")
			end
			vim.cmd("TSUpdate")
		elseif name == "LuaSnip" and vim.fn.executable("make") == 1 then
			-- optional regex-transform support for snippets; harmless if it fails
			vim.system({ "make", "install_jsregexp" }, { cwd = ev.data.path })
		end
	end,
})

----------------------------------------------------------------------
-- COLOURSCHEME
----------------------------------------------------------------------
do
	vim.pack.add({ gh("folke/tokyonight.nvim") })
	require("tokyonight").setup({
		-- transparent so the terminal's own backdrop (and its opacity) shows
		-- through. Use the theme's options rather than clearing Normal/NormalFloat
		-- by hand: these propagate to every group tokyonight defines, so float
		-- borders, popups and notifications stay consistent with the editor
		-- instead of keeping a solid background.
		transparent = true,
		styles = {
			comments = { italic = false },
			floats = "transparent",
			sidebars = "transparent",
		},
	})
	vim.cmd.colorscheme("tokyonight-night")
end

----------------------------------------------------------------------
-- UI / UX
----------------------------------------------------------------------
do
	vim.pack.add({
		gh("folke/which-key.nvim"),
		gh("folke/todo-comments.nvim"),
		gh("NMAC427/guess-indent.nvim"),
		gh("nvim-lua/plenary.nvim"), -- dependency of todo-comments + lazygit.nvim
	})

	require("which-key").setup({ delay = 0 })
	require("guess-indent").setup({}) -- match a file's existing indentation
	require("todo-comments").setup({ signs = false })
end

----------------------------------------------------------------------
-- NAVIGATION
----------------------------------------------------------------------
do
	vim.pack.add({
		gh("nvim-tree/nvim-web-devicons"), -- dependency of fzf-lua
		gh("ibhagwan/fzf-lua"),
		gh("cbochs/grapple.nvim"),
	})

	-- "fzf-native" profile — uses the real fzf binary (system closure) rather
	-- than the Lua fuzzy matcher
	require("fzf-lua").setup({ "fzf-native" })
	require("grapple").setup({ icons = false })
end

----------------------------------------------------------------------
-- LSP + MASON
----------------------------------------------------------------------
do
	-- Servers to install and enable. The table key is the lspconfig name;
	-- mason-lspconfig translates it to the mason package name.
	local servers = {
		lua_ls = {
			settings = {
				Lua = {
					runtime = { version = "LuaJIT" },
					diagnostics = { globals = { "vim", "require" } },
					workspace = { library = vim.api.nvim_get_runtime_file("", true) },
					telemetry = { enable = false },
					format = { enable = false }, -- stylua does the formatting (see FORMATTING)
				},
			},
		},
		ts_ls = {},
		tailwindcss = {},
		clangd = {},
	}

	vim.pack.add({
		gh("neovim/nvim-lspconfig"),
		gh("mason-org/mason.nvim"),
		gh("mason-org/mason-lspconfig.nvim"),
		gh("WhoIsSethDaniel/mason-tool-installer.nvim"),
	})

	require("mason").setup({})
	-- automatic_enable = false: the loop below enables servers explicitly, so
	-- what runs is exactly what's in `servers` above
	require("mason-lspconfig").setup({ automatic_enable = false })

	local ensure_installed = vim.tbl_keys(servers)
	vim.list_extend(ensure_installed, {
		"stylua", -- lua formatter
		"prettierd", -- js/ts/css/json/yaml/markdown formatter daemon
	})
	require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

	for name, server in pairs(servers) do
		vim.lsp.config(name, server)
		vim.lsp.enable(name)
	end
end

----------------------------------------------------------------------
-- FORMATTING
----------------------------------------------------------------------
do
	vim.pack.add({ gh("stevearc/conform.nvim") })

	local prettier = { "prettierd", "prettier", stop_after_first = true }
	require("conform").setup({
		notify_on_error = false,
		-- lsp_format = "fallback": use a formatter below when the filetype has one,
		-- otherwise fall back to the LSP (so c/cpp still go through clangd) and do
		-- nothing at all when neither exists.
		default_format_opts = { lsp_format = "fallback" },
		format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
		formatters_by_ft = {
			lua = { "stylua" },
			javascript = prettier,
			javascriptreact = prettier,
			typescript = prettier,
			typescriptreact = prettier,
			css = prettier,
			html = prettier,
			json = prettier,
			yaml = prettier,
			markdown = prettier,
		},
	})
end

----------------------------------------------------------------------
-- AUTOCOMPLETE + SNIPPETS
----------------------------------------------------------------------
do
	vim.pack.add({
		{ src = gh("L3MON4D3/LuaSnip"), version = vim.version.range("2.*") },
		gh("rafamadriz/friendly-snippets"),
		{ src = gh("saghen/blink.cmp"), version = vim.version.range("1.*") },
		gh("monkoose/neocodeium"),
	})

	require("luasnip.loaders.from_vscode").lazy_load()

	require("blink.cmp").setup({
		-- without this blink uses its own snippet engine and the friendly-snippets
		-- loaded into LuaSnip above never surface in the menu
		snippets = { preset = "luasnip" },
		signature = { enabled = true },
		completion = {
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 500,
			},
			menu = {
				auto_show = true,
				draw = {
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon", "label", "label_description", gap = 1 },
						{ "kind" },
					},
				},
			},
		},
	})

	local neocodeium = require("neocodeium")
	neocodeium.setup()
	vim.keymap.set("i", "<A-f>", neocodeium.accept, { desc = "Accept neocodeium suggestion" })
end

----------------------------------------------------------------------
-- TREESITTER
----------------------------------------------------------------------
do
	-- The `main` branch generates each parser with the tree-sitter CLI and then
	-- compiles it with `cc` — both from pacman (tree-sitter-cli, gcc from
	-- base-devel), NOT from npm.
	vim.pack.add({ { src = gh("nvim-treesitter/nvim-treesitter"), version = "main" } })

	local parsers = {
		"bash",
		"c",
		"diff",
		"html",
		"lua",
		"luadoc",
		"markdown",
		"markdown_inline",
		"query",
		"vim",
		"vimdoc",
		"typescript",
		"javascript",
		"css",
		"elixir",
		"json",
		"rust",
		"toml",
		"yaml",
		"tsx",
	}
	require("nvim-treesitter").install(parsers)

	---@param buf integer
	---@param language string
	local function try_attach(buf, language)
		if not vim.treesitter.language.add(language) then
			return
		end
		-- syntax highlighting and other treesitter features
		vim.treesitter.start(buf, language)

		-- treesitter based folds — see `:help folds`
		-- vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
		-- vim.wo.foldmethod = 'expr'

		-- only override indentexpr when the language actually ships an indent
		-- query, otherwise Vim's built-in indenting is the better fallback
		if vim.treesitter.query.get(language, "indents") ~= nil then
			vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end
	end

	local available = require("nvim-treesitter").get_available()
	vim.api.nvim_create_autocmd("FileType", {
		callback = function(args)
			local buf, filetype = args.buf, args.match

			local language = vim.treesitter.language.get_lang(filetype)
			if not language then
				return
			end

			local installed = require("nvim-treesitter").get_installed("parsers")
			if vim.tbl_contains(installed, language) then
				try_attach(buf, language)
			elseif vim.tbl_contains(available, language) then
				-- not installed yet but upstream has it — fetch, then attach
				require("nvim-treesitter").install(language):await(function()
					try_attach(buf, language)
				end)
			else
				-- parser may exist outside nvim-treesitter (e.g. shipped with Nvim)
				try_attach(buf, language)
			end
		end,
	})
end

----------------------------------------------------------------------
-- GIT
----------------------------------------------------------------------
do
	vim.pack.add({
		gh("lewis6991/gitsigns.nvim"),
		gh("kdheepak/lazygit.nvim"), -- plenary added in the UI section above
	})

	require("gitsigns").setup({})
	-- lazygit.nvim only defines :LazyGit commands; the keymap was previously
	-- declared through lazy.nvim's `keys` spec, so it has to live here now
	vim.keymap.set("n", "<leader>lg", "<cmd>LazyGit<cr>", { desc = "LazyGit" })
end
