-- =============================================================================
-- ai.lua — Plugins IA : CodeCompanion + OpenCode
-- Chargé par init.lua si ~/.vim/.ai-enabled existe
--
-- Modèle lu depuis ~/.vim/.ai-model (écrit par install.sh ia)
-- Ollama tourne sur l'hôte KVM : 192.168.122.1:11434
-- =============================================================================

local OLLAMA_URL = "http://192.168.122.1:11434"

-- Lire le modèle sélectionné lors de l'installation
-- Retourne le contenu de ~/.vim/.ai-model, ou un fallback lisible
local function read_model()
    local model_file = vim.fn.expand("~/.vim/.ai-model")
    local f = io.open(model_file, "r")
    if f then
        local model = f:read("*l")
        f:close()
        if model and #model > 0 then
            return vim.trim(model)
        end
    end
    -- Si le fichier n'existe pas : avertissement et fallback
    vim.notify(
        "[IA] ~/.vim/.ai-model introuvable.\n"
        .. "Relance ./install.sh ia pour sélectionner un modèle.",
        vim.log.levels.WARN
    )
    return "qwen2.5-coder:14b"
end

local AI_MODEL = read_model()

-- =============================================================================
return {

    -- =========================================================================
    -- CodeCompanion — assistant IA intégré dans Neovim
    -- https://github.com/olimorris/codecompanion.nvim
    -- =========================================================================
    {
        "olimorris/codecompanion.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        config = function()
            require("codecompanion").setup({

                -- Adapter : Ollama sur l'hôte KVM
                adapters = {
                    ollama_host = function()
                        return require("codecompanion.adapters").extend("ollama", {
                            env = {
                                url = OLLAMA_URL,
                            },
                            schema = {
                                model = {
                                    default = AI_MODEL,
                                },
                                -- Fenêtre de contexte large pour les gros modèles
                                num_ctx = {
                                    default = 32768,
                                },
                                -- Température basse pour du code
                                temperature = {
                                    default = 0.1,
                                },
                            },
                        })
                    end,
                },

                -- Utiliser ollama_host pour toutes les stratégies
                strategies = {
                    chat   = { adapter = "ollama_host" },
                    inline = { adapter = "ollama_host" },
                    agent  = { adapter = "ollama_host" },
                },

                display = {
                    chat = {
                        window = {
                            layout = "vertical", -- panneau latéral droit
                            width  = 0.35,
                        },
                        -- Affiche le modèle dans le titre du buffer
                        show_header_separator = true,
                    },
                    action_palette = {
                        provider = "telescope",
                    },
                    diff = {
                        provider = "mini_diff", -- ou "default"
                    },
                },

                -- Comportement général
                opts = {
                    -- Log level pour debug : "DEBUG" | "INFO" | "WARN" | "ERROR"
                    log_level = "WARN",
                    -- Langue des réponses
                    language = "French",
                },
            })

            -- Raccourcis CodeCompanion
            -- <Space>ac — ouvrir/fermer le chat
            vim.keymap.set({ "n", "v" }, "<leader>ac",
                "<cmd>CodeCompanionChat Toggle<CR>",
                { desc = "CodeCompanion: chat" })

            -- <Space>aa — palette d'actions (résumer, expliquer, corriger…)
            vim.keymap.set({ "n", "v" }, "<leader>aa",
                "<cmd>CodeCompanionActions<CR>",
                { desc = "CodeCompanion: actions" })

            -- <Space>ae — édition inline sur la sélection visuelle
            vim.keymap.set("v", "<leader>ae",
                "<cmd>CodeCompanion<CR>",
                { desc = "CodeCompanion: édition inline" })

            -- <Space>am — afficher le modèle et l'URL actifs dans la cmdline
            vim.keymap.set("n", "<leader>am",
                function()
                    vim.notify(
                        string.format("[IA] Modèle : %s\n     URL    : %s", AI_MODEL, OLLAMA_URL),
                        vim.log.levels.INFO,
                        { title = "CodeCompanion" }
                    )
                end,
                { desc = "CodeCompanion: modèle actif" })
        end,
    },

    -- =========================================================================
    -- opencode.nvim — panneau OpenCode dans Neovim
    -- https://github.com/sudo-tee/opencode.nvim
    --
    -- Nécessite que le binaire `opencode` soit dans le PATH
    -- (installé par install.sh ia via npm install -g opencode-ai)
    -- =========================================================================
    {
        "sudo-tee/opencode.nvim",
        -- Ne charger que si opencode est installé
        cond = function()
            return vim.fn.executable("opencode") == 1
        end,
        event = "VeryLazy",
        config = function()
            require("opencode").setup({
                window = {
                    -- Panneau latéral droit, même largeur que CodeCompanion
                    position        = "right",
                    split_ratio     = 0.35,
                    enter_insert    = true,
                    hide_numbers    = true,
                    hide_signcolumn = true,
                },
                -- Tuer le serveur opencode quand le dernier nvim se ferme
                auto_kill = true,
            })

            -- <Space>oc — ouvrir/fermer le panneau OpenCode
            vim.keymap.set("n", "<leader>oc",
                "<cmd>Opencode toggle<cr>",
                { desc = "OpenCode: toggle panneau" })

            -- <Space>os — envoyer la sélection comme contexte
            vim.keymap.set("v", "<leader>os",
                "<cmd>OpencodeAddSelection<cr>",
                { desc = "OpenCode: envoyer sélection" })

            -- <Space>on — nouvelle session OpenCode
            vim.keymap.set("n", "<leader>on",
                "<cmd>Opencode new<cr>",
                { desc = "OpenCode: nouvelle session" })

            -- <Space>ol — lister les sessions passées
            vim.keymap.set("n", "<leader>ol",
                "<cmd>Opencode sessions<cr>",
                { desc = "OpenCode: sessions" })
        end,
    },
}
