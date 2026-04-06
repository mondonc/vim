-- =============================================================================
-- ai.lua — CodeCompanion config (chargé uniquement si .ai-enabled existe)
-- =============================================================================

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          anthropic = function()
            return require("codecompanion.adapters").extend("anthropic", {
              schema = {
                model = {
                  default = "claude-sonnet-4-20250514",
                },
              },
              env = {
                api_key = function()
                  -- 1. Variable d'environnement (prioritaire)
                  local key = os.getenv("ANTHROPIC_API_KEY")
                  if key and key ~= "" then return key end
                  -- 2. Fichier local (fallback)
                  local f = io.open(vim.fn.expand("~/.config/codecompanion/anthropic_key"), "r")
                  if f then
                    key = f:read("*l")
                    f:close()
                    return key
                  end
                  vim.notify("ANTHROPIC_API_KEY non trouvée", vim.log.levels.ERROR)
                  return ""
                end,
              },
            })
          end,
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
        strategies = {
          chat = {
            adapter = "anthropic",
          },
          inline = {
            adapter = "anthropic",
          },
        },
      })

      -- Keymaps
      vim.keymap.set("n", "<leader>ac", "<cmd>CodeCompanionChat Toggle<CR>", { desc = "AI Chat toggle" })
      vim.keymap.set("v", "<leader>ac", "<cmd>CodeCompanionChat Toggle<CR>", { desc = "AI Chat toggle" })
      vim.keymap.set("n", "<leader>aa", "<cmd>CodeCompanionActions<CR>", { desc = "AI Actions" })
      vim.keymap.set("v", "<leader>aa", "<cmd>CodeCompanionActions<CR>", { desc = "AI Actions" })
      vim.keymap.set("v", "<leader>ae", "<cmd>CodeCompanion<CR>", { desc = "AI inline edit" })
    end,
  },
}
