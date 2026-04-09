-- =============================================================================
-- ai.lua — CodeCompanion (Claude API + Ollama)
-- Chargé conditionnellement par init.lua si .ai-enabled existe
-- Retourne une liste de specs lazy.nvim
-- =============================================================================

-- Résolution de la clé API Anthropic :
-- 1. Variable d'environnement ANTHROPIC_API_KEY
-- 2. Fichier ~/.config/codecompanion/anthropic_key
local function get_anthropic_key()
    local key = os.getenv("ANTHROPIC_API_KEY")
    if key and key ~= "" then return key end
    local f = io.open(os.getenv("HOME") .. "/.config/codecompanion/anthropic_key", "r")
    if f then
        key = f:read("*l")
        f:close()
        return key
    end
    return nil
end

return {
    {
        "olimorris/codecompanion.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        keys = {
            { "<leader>ac", "<cmd>CodeCompanionChat Toggle<CR>", mode = { "n", "v" }, desc = "Chat IA" },
            { "<leader>aa", "<cmd>CodeCompanionActions<CR>",     mode = { "n", "v" }, desc = "Actions IA" },
            { "<leader>ae", "<cmd>CodeCompanion<CR>",            mode = "v",          desc = "Édition inline IA" },
        },
        cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
        config = function()
            require("codecompanion").setup({
                -- ─── Adapters ────────────────────────────────────
                adapters = {
                    http = {
                        -- Claude via API directe
                        anthropic = function()
                            return require("codecompanion.adapters").extend("anthropic", {
                                env = {
                                    api_key = get_anthropic_key(),
                                },
                                schema = {
                                    model = {
                                        -- claude-sonnet-4-20250514 est le modèle par défaut
                                        -- Changer ici pour opus/haiku selon besoin
                                        default = "claude-sonnet-4-20250514",
                                    },
                                },
                            })
                        end,

                        -- Ollama local
                        ollama = function()
                            return require("codecompanion.adapters").extend("ollama", {
                                schema = {
                                    model = {
                                        default = "qwen2.5-coder:14b",
                                    },
                                },
                            })
                        end,
                    },
                },

                -- ─── Stratégies (quel adapter pour quoi) ─────────
                -- Pour switcher : changer "anthropic" ↔ "ollama"
                strategies = {
                    chat = {
                        adapter = "anthropic",
                    },
                    inline = {
                        adapter = "anthropic",
                    },
                    cmd = {
                        adapter = "anthropic",
                    },
                },

                -- ─── Options générales ───────────────────────────
                opts = {
                    log_level = "ERROR",
                },
            })

            -- Commande pour switcher rapidement entre Claude et Ollama
            vim.api.nvim_create_user_command("AISwitch", function(opts)
                local target = opts.args
                if target ~= "anthropic" and target ~= "ollama" then
                    vim.notify("Usage: :AISwitch anthropic | ollama", vim.log.levels.WARN)
                    return
                end
                -- On reconfigure les stratégies à la volée
                require("codecompanion").setup({
                    strategies = {
                        chat = { adapter = target },
                        inline = { adapter = target },
                        cmd = { adapter = target },
                    },
                })
                vim.notify("IA → " .. target, vim.log.levels.INFO)
            end, {
                nargs = 1,
                complete = function()
                    return { "anthropic", "ollama" }
                end,
                desc = "Switch IA entre Claude et Ollama",
            })
        end,
    },
}
