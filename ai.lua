-- =============================================================================
-- ai.lua — Plugins IA : CodeCompanion + OpenCode
-- Chargé par init.lua si ~/.vim/.ai-enabled existe
--
-- Modèle lu depuis ~/.vim/.ai-model (écrit par install.sh ia)
-- Ollama tourne sur l'hôte KVM : 192.168.122.1:11434
-- =============================================================================

local OLLAMA_URL = vim.g.ollama_url or "http://192.168.122.1:11434"

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
        tag = "v18.7.0",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        config = function()
            require("codecompanion").setup({

                adapters = {
                    http = {                          -- ← nouveau niveau obligatoire
                        ollama_host = function()
                            return require("codecompanion.adapters").extend("ollama", {
                                env = {
                                    url = OLLAMA_URL,
                                },
                                schema = {
                                    model       = { default = AI_MODEL },
                                    num_ctx     = { default = 32768 },
                                    temperature = { default = 0.1 },
                                    num_thread  = { default = 20 },
                                },
                            })
                        end,
                    },
                },

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
                        provider = "default",
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
                { desc = "CodeCompanion: inlinei edition" })

            -- <Space>am — afficher le modèle et l'URL actifs dans la cmdline
            vim.keymap.set("n", "<leader>am",
                function()
                    vim.notify(
                        string.format("[IA] Modèle : %s\n     URL    : %s", AI_MODEL, OLLAMA_URL),
                        vim.log.levels.INFO,
                        { title = "CodeCompanion" }
                    )
                end,
                { desc = "CodeCompanion: active model" })

            -- Spinner partagé (commit + CodeCompanion)
            local spinner       = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
            local spinner_idx   = 0
            local spinner_timer = nil

            local function start_spinner(label)
                if spinner_timer then return end
                spinner_idx = 0
                spinner_timer = vim.uv.new_timer()
                spinner_timer:start(0, 80, vim.schedule_wrap(function()
                    spinner_idx = (spinner_idx % #spinner) + 1
                    vim.o.statusline = " " .. spinner[spinner_idx] .. " " .. (label or "En cours…")
                    vim.cmd("redrawstatus")
                end))
            end

            local function stop_spinner()
                if spinner_timer then
                    spinner_timer:stop()
                    spinner_timer:close()
                    spinner_timer = nil
                end
                vim.o.statusline = ""
                vim.cmd("redrawstatus")
            end

            -- Générateur de message de commit
            local function open_commit_buffer(message, files, elapsed_ms)
                local buf = vim.api.nvim_create_buf(false, true)
                vim.bo[buf].filetype = "gitcommit"

                local lines = vim.split(message, "\n")
                table.insert(lines, "")
                table.insert(lines, "# Modifie le message ci-dessus.")
                table.insert(lines, "# <leader>cc  — valider et commiter")
                table.insert(lines, "# q           — annuler")
                table.insert(lines, string.format("# Généré en %.1fs — Fichiers : %s",
                    (elapsed_ms or 0) / 1000, table.concat(files, ", ")))
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

                local width  = math.floor(vim.o.columns * 0.65)
                local height = math.min(#lines + 2, 24)
                local win = vim.api.nvim_open_win(buf, true, {
                    relative  = "editor",
                    width     = width,
                    height    = height,
                    row       = math.floor((vim.o.lines - height) / 2),
                    col       = math.floor((vim.o.columns - width) / 2),
                    style     = "minimal",
                    border    = "rounded",
                    title     = " Message de commit ",
                    title_pos = "center",
                })

                -- Valider et commiter
                vim.keymap.set("n", "<leader>cc", function()
                    local msg_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                    local msg = table.concat(
                        vim.tbl_filter(function(l) return not l:match("^#") end, msg_lines),
                        "\n"
                    ):gsub("^%s+", ""):gsub("%s+$", "")

                    if msg == "" then
                        vim.notify("[Git] Message vide, commit annulé.", vim.log.levels.WARN)
                        return
                    end

                    vim.api.nvim_win_close(win, true)

                    local add_cmd = "git add -- " .. table.concat(
                        vim.tbl_map(function(f) return vim.fn.shellescape(f) end, files), " ")
                    local add_out = vim.fn.system(add_cmd)
                    if vim.v.shell_error ~= 0 then
                        vim.notify("[Git] git add échoué :\n" .. add_out, vim.log.levels.ERROR)
                        return
                    end

                    local commit_out = vim.fn.system("git commit -m " .. vim.fn.shellescape(msg))
                    if vim.v.shell_error ~= 0 then
                        vim.notify("[Git] git commit échoué :\n" .. commit_out, vim.log.levels.ERROR)
                    else
                        vim.notify("[Git] ✓ Commit effectué\n" .. vim.trim(commit_out), vim.log.levels.INFO)
                    end
                end, { buffer = buf, desc = "Valider et commiter" })

                -- Annuler
                vim.keymap.set("n", "q", function()
                    vim.api.nvim_win_close(win, true)
                    vim.notify("[Git] Commit annulé.", vim.log.levels.INFO)
                end, { buffer = buf })
            end

            local function generate_and_open(diff, files)
                local t0 = vim.uv.now()
                start_spinner("Génération du message de commit…")
                require("plenary.curl").post(OLLAMA_URL .. "/api/generate", {
                    headers  = { ["Content-Type"] = "application/json" },
                    body     = vim.json.encode({
                        model  = AI_MODEL,
                        options = { num_thread = 20 },
                        prompt = "Voici le diff git des fichiers sélectionnés :\n\n```diff\n"
                            .. diff
                            .. "\n```\n\n"
                            .. "Génère un message de commit en respectant exactement ce format :\n"
                            .. "ligne 1 : message conventionnel (type: description courte en anglais)\n"
                            .. "ligne 2 : (with codecompanion@neovim)\n\n"
                            .. "Réponds uniquement avec ces deux lignes, sans explication ni texte supplémentaire.",
                        stream = false,
                    }),
                    callback = function(response)
                        vim.schedule(function()
                            stop_spinner()
                            if response.status ~= 200 then
                                vim.notify("[IA] Erreur : " .. tostring(response.status), vim.log.levels.ERROR)
                                return
                            end
                            local ok, data = pcall(vim.json.decode, response.body)
                            if ok and data and data.response then
                                open_commit_buffer(vim.trim(data.response), files, vim.uv.now() - t0)
                            else
                                vim.notify("[IA] Réponse invalide.", vim.log.levels.ERROR)
                            end
                        end)
                    end,
                })
            end

            vim.keymap.set("n", "<leader>ag", function()
                local files = vim.fn.systemlist("git diff --name-only HEAD 2>/dev/null")
                local staged = vim.fn.systemlist("git diff --name-only --cached 2>/dev/null")

                local seen, all_files = {}, {}
                for _, f in ipairs(staged) do
                    if not seen[f] then seen[f] = true; table.insert(all_files, f) end
                end
                for _, f in ipairs(files) do
                    if not seen[f] then seen[f] = true; table.insert(all_files, f) end
                end

                if #all_files == 0 then
                    vim.notify("[IA] Aucun fichier modifié trouvé.", vim.log.levels.WARN)
                    return
                end

                local pickers      = require("telescope.pickers")
                local finders      = require("telescope.finders")
                local conf         = require("telescope.config").values
                local actions      = require("telescope.actions")
                local action_state = require("telescope.actions.state")

                pickers.new({}, {
                    prompt_title = "Files to be commited (Tab = toggle, Enter = valid)",
                    finder  = finders.new_table({ results = all_files }),
                    sorter  = conf.generic_sorter({}),
                    attach_mappings = function(buf, map)
                        vim.api.nvim_create_autocmd("User", {
                            pattern  = "TelescopePreviewerLoaded",
                            once     = true,
                            callback = function() actions.toggle_all(buf) end,
                        })

                        map("i", "<CR>", function()
                            local picker   = action_state.get_current_picker(buf)
                            local selected = {}
                            for _, entry in ipairs(picker:get_multi_selection()) do
                                table.insert(selected, entry[1])
                            end
                            if #selected == 0 then selected = all_files end
                            actions.close(buf)

                            local escaped = table.concat(
                                vim.tbl_map(function(f) return vim.fn.shellescape(f) end, selected), " ")
                            local diff = vim.fn.system("git diff HEAD -- " .. escaped)
                            if diff == "" then
                                diff = vim.fn.system("git diff --cached -- " .. escaped)
                            end

                            generate_and_open(diff, selected)
                        end)
                        return true
                    end,
                }):find()
            end, { desc = "CodeCompanion: commit message generator" })

            -- Spinner CodeCompanion (réutilise les fonctions partagées)
            vim.api.nvim_create_autocmd("User", {
                pattern  = "CodeCompanionRequestStarted",
                callback = function() start_spinner("CodeCompanion generating…") end,
            })

            vim.api.nvim_create_autocmd("User", {
                pattern  = "CodeCompanionRequestFinished",
                callback = function() stop_spinner() end,
            })
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
