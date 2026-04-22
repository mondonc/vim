-- =============================================================================
-- init.lua — Config Neovim (lazy.nvim)
-- =============================================================================

-- Source des options partagées
vim.cmd("source " .. vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h") .. "/common.vim")

vim.g.mapleader = " "

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local uv = vim.uv or vim.loop
if not uv.fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

local plugins = {
    -- Git
    "tpope/vim-fugitive",

    -- File explorer (NERDTree compatible keybind)
    {
        "scrooloose/nerdtree",
        keys = { { "<C-x>", "<cmd>NERDTreeToggle<CR>" } },
        cmd = { "NERDTree", "NERDTreeToggle" },
        init = function()
            vim.g.NERDTreeMapOpenInTab = "<CR>"
        end,
    },

    -- Colorschemes
    "cschlueter/vim-mustang",
    {
        "folke/tokyonight.nvim",
        priority = 1000,
        config = function()
            require("tokyonight").setup({
                style = "night",
                transparent = true,
            })
            vim.cmd.colorscheme("tokyonight")

            -- Blanc pur par défaut
            local function apply_white()
                vim.api.nvim_set_hl(0, "Normal", { fg = "#ffffff", bg = "NONE" })
                vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#ffffff" })
                vim.api.nvim_set_hl(0, "Comment", { fg = "#888888", italic = true })
            end
            apply_white()

            -- Toggle blanc pur / blanc bleuté (Space+hc)
            local bluish_mode = false
            vim.keymap.set("n", "<leader>hc", function()
                bluish_mode = not bluish_mode
                vim.cmd.colorscheme("tokyonight")
                if bluish_mode then
                    print("Mode bleuté (tokyonight natif)")
                else
                    apply_white()
                    print("Mode blanc pur")
                end
            end, { desc = "Toggle white/bluish" })
        end,
    },

    -- Tagbar
    {
        "majutsushi/tagbar",
        cmd = "TagbarToggle",
    },

    -- Git signs in gutter (remplace vim-gitgutter)
    {
        "lewis6991/gitsigns.nvim",
        config = true,
    },

    -- Treesitter (branche main — nouvelle API sans configs.lua)
    -- build = ":TSUpdate" installe les parsers (à lancer manuellement la 1ère fois
    -- via :Lazy build nvim-treesitter si les parsers ne sont pas encore présents).
    -- Le highlighting et l'indent utilisent l'API native Neovim (vim.treesitter),
    -- ce qui évite tout appel à setup()/install() qui crashe avec config.list nil.
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "master",
        lazy = false,
        build = ":TSUpdate",

        config = function()
            require("nvim-treesitter.configs").setup({
                ensure_installed = {
                    "python", "lua", "bash", "html", "css",
                    "javascript", "json", "yaml", "toml", "dockerfile", "make",
                    "markdown", "markdown_inline",
                },
                highlight = { enable = true },
                indent    = { enable = true },
            })
        end,
    },

    -- Complétion
    {
        "hrsh7th/nvim-cmp",
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
        },
        config = function()
            local cmp = require("cmp")
            cmp.setup({
                sources = cmp.config.sources({
                    { name = "nvim_lsp" },
                    { name = "buffer" },
                    { name = "path" },
                }),
                mapping = cmp.mapping.preset.insert({
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                    ["<Tab>"] = cmp.mapping.select_next_item(),
                    ["<S-Tab>"] = cmp.mapping.select_prev_item(),
                }),
            })
        end,
    },

    -- Linting (remplace syntastic)
    {
        "mfussenegger/nvim-lint",
        event = { "BufReadPre", "BufNewFile" },
        config = function()
            local lint = require("lint")
            lint.linters_by_ft = {
                python = { "ruff" },
            }
            vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
                callback = function() lint.try_lint() end,
            })
        end,
    },

    -- Telescope (fuzzy finder)
    {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<CR>",  desc = "Find files" },
            { "<leader>fg", "<cmd>Telescope live_grep<CR>",   desc = "Live grep" },
            { "<leader>fb", "<cmd>Telescope buffers<CR>",     desc = "Buffers" },
            { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Diagnostics" },
        },
        config = function()
            local actions = require("telescope.actions")
            require("telescope").setup({
                pickers = {
                    find_files  = { mappings = { i = { ["<CR>"] = actions.select_tab }, n = { ["<CR>"] = actions.select_tab } } },
                    live_grep   = { mappings = { i = { ["<CR>"] = actions.select_tab }, n = { ["<CR>"] = actions.select_tab } } },
                    buffers     = { mappings = { i = { ["<CR>"] = actions.select_tab }, n = { ["<CR>"] = actions.select_tab } } },
                    diagnostics = { mappings = { i = { ["<CR>"] = actions.select_tab }, n = { ["<CR>"] = actions.select_tab } } },
                },
            })
        end,
    },
}

-- Chargement conditionnel de l'IA (si ./install.sh ia a été exécuté)
local vimdir = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h")
if uv.fs_stat(vimdir .. "/.ai-enabled") then
    vim.list_extend(plugins, dofile(vimdir .. "/ai.lua"))
end

require("lazy").setup(plugins)

-- =============================================================================
-- Diagnostics — loc list en bas (comme syntastic)
-- =============================================================================

vim.diagnostic.config({
    virtual_text = false,
    signs = true,
    underline = true,
    float = { border = "rounded" },
})

-- Affiche le diagnostic de la ligne courante dans la cmdline
vim.api.nvim_create_autocmd("CursorHold", {
    callback = function()
        vim.diagnostic.open_float(nil, { scope = "line", focusable = false })
    end,
})

-- Réactivité du CursorHold (ms)
vim.opt.updatetime = 300

-- Ouvre/ferme la loclist automatiquement
vim.api.nvim_create_autocmd("DiagnosticChanged", {
    callback = function()
        if vim.v.exiting ~= vim.NIL then return end
        local ok, diags = pcall(vim.diagnostic.get, 0)
        if not ok then return end
        if #diags > 0 then
            pcall(function()
                vim.diagnostic.setloclist({ open = false })
                vim.cmd("lopen 3")
                vim.cmd("wincmd p")
            end)
        else
            pcall(vim.cmd, "lclose")
        end
    end,
})

-- Ferme la loclist avant de quitter (évite le double :q)
vim.api.nvim_create_autocmd("QuitPre", {
    callback = function()
        pcall(vim.cmd, "lclose")
    end,
})

-- =============================================================================
-- LSP natif (vim.lsp.config, Neovim 0.11+)
-- =============================================================================

if vim.lsp.config then
    vim.lsp.config("pyright", {
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", ".git" },
    })
    vim.lsp.enable("pyright")
else
    vim.api.nvim_create_autocmd("FileType", {
        pattern = { "python" },
        callback = function()
            vim.lsp.start({
                name = "pyright",
                cmd = { "pyright-langserver", "--stdio" },
                root_dir = vim.fs.root(0, { "pyproject.toml", "setup.py", "setup.cfg", ".git" }),
            })
        end,
    })
end

-- Keymaps LSP
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local opts = { buffer = ev.buf }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    end,
})
