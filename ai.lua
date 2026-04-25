-- =============================================================================
-- ai.lua — Plugins IA : CodeCompanion + OpenCode
-- Chargé par init.lua si ~/.vim/.ai-enabled existe
--
-- Modèle lu depuis ~/.vim/.ai-model (écrit par install.sh ia)
-- Ollama tourne sur l'hôte KVM : 192.168.122.1:11434
-- =============================================================================

local OLLAMA_URL = vim.g.ollama_url or "http://192.168.122.1:11434"

-- ----------------------------------------------------------------------------
-- Lecture des modèles
--   ~/.vim/.ai-model       — modèle "coder" (utilisé par inline + agent)
--   ~/.vim/.ai-model-chat  — modèle "chat"  (utilisé par chat / clarification)
--                            si absent, fallback sur .ai-model
-- ----------------------------------------------------------------------------
local function read_one_model(filename, warn_if_missing)
    local f = io.open(vim.fn.expand("~/.vim/" .. filename), "r")
    if f then
        local model = f:read("*l")
        f:close()
        if model and #model > 0 then
            return vim.trim(model)
        end
    end
    if warn_if_missing then
        vim.notify(
            "[IA] ~/.vim/" .. filename .. " introuvable.\n"
            .. "Relance ./install.sh ia pour sélectionner un modèle.",
            vim.log.levels.WARN
        )
    end
    return nil
end

-- Modèle coder (commit msg, inline edit, agent edits)
local AI_MODEL = read_one_model(".ai-model", true) or "qwen2.5-coder:14b"

-- Modèle chat (clarification, dialogue) — fallback sur le coder si absent
local AI_MODEL_CHAT = read_one_model(".ai-model-chat", false) or AI_MODEL

-- Q3 (c) : warning si le modèle utilisé pour l'agent est < 14B
-- (le tool use sur Ollama est instable sous 14B)
local function check_model_size(model_name, role)
    local size_str = model_name:match(":(%d+)[bB]")
    if not size_str then return end -- pas de taille détectable, on ne dit rien
    local size = tonumber(size_str)
    if size and size < 14 then
        vim.notify(string.format(
            "[IA] ⚠ Modèle %s : %dB pour le rôle '%s'.\n"
            .. "Le tool use (lecture de fichiers, etc.) est instable sous 14B.\n"
            .. "Recommandation : 14B-32B pour un comportement fiable.",
            model_name, size, role), vim.log.levels.WARN)
    end
end
check_model_size(AI_MODEL, "coder/agent")
if AI_MODEL_CHAT ~= AI_MODEL then
    check_model_size(AI_MODEL_CHAT, "chat")
end

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
                        ollama_coder = function()
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
                        ollama_chat = function()
                            return require("codecompanion.adapters").extend("ollama", {
                                env = {
                                    url = OLLAMA_URL,
                                },
                                schema = {
                                    model       = { default = AI_MODEL_CHAT },
                                    num_ctx     = { default = 32768 },
                                    -- Légèrement plus créatif que le coder pour la
                                    -- phase de clarification / dialogue
                                    temperature = { default = 0.3 },
                                    num_thread  = { default = 20 },
                                },
                            })
                        end,
                    },
                },

                strategies = {
                    -- Q2 (a) : per-strategy automatique
                    -- chat : modèle "général"   (clarification, dialogue, tool use)
                    -- inline/agent : modèle "coder" (édition de code)
                    chat   = { adapter = "ollama_chat" },
                    inline = { adapter = "ollama_coder" },
                    agent  = { adapter = "ollama_coder" },
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

                -- =========================================================
                -- Prompt library : workflow IA sur une issue GitLab
                -- Invoqué depuis gitlab.lua via :CodeCompanion /issue_workflow
                -- ou la palette d'actions (:CodeCompanionActions)
                --
                -- Le system prompt est CONSTRUIT À L'INVOCATION (function),
                -- pour lire vim.g.current_issue à ce moment-là.
                -- =========================================================
                prompt_library = {
                    ["Issue Workflow"] = {
                        strategy = "chat",
                        description = "Workflow GitLab : clarifier une issue puis l'implémenter",
                        opts = {
                            short_name = "issue_workflow",
                            -- Auto-submit le premier message au lieu de juste l'afficher
                            auto_submit = true,
                            -- Ne pas demander confirmation avant ouverture
                            user_prompt = false,
                        },
                        prompts = {
                            {
                                role = "system",
                                content = function()
                                    local issue = vim.g.current_issue
                                    if not issue then
                                        return "ERREUR : aucune issue sélectionnée. "
                                            .. "Demande à l'utilisateur de lancer :GitlabIssue d'abord."
                                    end

                                    -- Project tree (fonction exposée par gitlab.lua)
                                    local tree = ""
                                    if _G.GitlabIssueProjectTree then
                                        tree = _G.GitlabIssueProjectTree()
                                    end

                                    local labels = ""
                                    if issue.labels and #issue.labels > 0 then
                                        labels = "Labels : " .. table.concat(issue.labels, ", ") .. "\n"
                                    end

                                    return table.concat({
                                        "Tu es un assistant de développement chargé d'aider à résoudre",
                                        "une issue GitLab. Tu réponds en FRANÇAIS.",
                                        "",
                                        "## Issue à traiter",
                                        "",
                                        "**#" .. issue.iid .. " — " .. issue.title .. "**",
                                        labels,
                                        "Description :",
                                        issue.description ~= "" and issue.description or "_(pas de description)_",
                                        "",
                                        "## Arborescence du projet",
                                        "",
                                        "```",
                                        tree,
                                        "```",
                                        "",
                                        "## Méthode (à suivre IMPÉRATIVEMENT en 3 phases)",
                                        "",
                                        "**Phase 1 — Exploration**",
                                        "Utilise les outils à ta disposition (@read_file, @grep_search,",
                                        "@file_search, etc.) pour lire le code pertinent. Ne pose pas",
                                        "de questions tant que tu n'as pas exploré ce qui est nécessaire.",
                                        "",
                                        "**Phase 2 — Clarification**",
                                        "Pose à l'utilisateur 1 à 5 questions précises (en français)",
                                        "pour lever les ambiguïtés et confirmer l'approche d'implémentation.",
                                        "Attends ses réponses avant de continuer.",
                                        "",
                                        "**Phase 3 — Reformulation et validation**",
                                        "Reformule en français ce que tu vas implémenter (fichiers",
                                        "concernés, changements prévus). Termine par : « Tape \"go\"",
                                        "quand tu valides cette approche. »",
                                        "",
                                        "**Phase 4 — Implémentation (UNIQUEMENT après le \"go\")**",
                                        "Utilise @insert_edit_into_file pour appliquer les changements.",
                                        "L'utilisateur validera chaque diff manuellement.",
                                        "",
                                        "Ne saute JAMAIS la phase 2 ni la phase 3.",
                                    }, "\n")
                                end,
                                opts = { visible = false }, -- system prompt non affiché dans le chat
                            },
                            {
                                role = "user",
                                content = "Démarre la phase 1 : explore le code pour comprendre cette issue.",
                            },
                        },
                    },
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
                        -- Q3 (b) : efface l'issue après commit réussi
                        if vim.g.current_issue then
                            vim.notify(string.format("[GitLab] Issue #%d marquée comme résolue (effacée)",
                                vim.g.current_issue.iid), vim.log.levels.INFO)
                            vim.g.current_issue = nil
                        end
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

                -- Q1 (a) : si une issue est en cours, le message DOIT commencer
                -- par "Fix #<iid>: " (format conventional commits avec issue ref)
                local issue = vim.g.current_issue
                local format_instruction
                if issue then
                    format_instruction = string.format(
                        "Génère un message de commit en respectant exactement ce format :\n"
                        .. "ligne 1 : Fix #%d: <description courte en anglais>\n"
                        .. "ligne 2 : (with codecompanion@neovim)\n\n"
                        .. "Contexte de l'issue (à utiliser pour rédiger la description) :\n"
                        .. "Titre : %s\n\n"
                        .. "Réponds uniquement avec ces deux lignes, sans explication ni texte supplémentaire.",
                        issue.iid, issue.title)
                else
                    format_instruction =
                        "Génère un message de commit en respectant exactement ce format :\n"
                        .. "ligne 1 : message conventionnel (type: description courte en anglais)\n"
                        .. "ligne 2 : (with codecompanion@neovim)\n\n"
                        .. "Réponds uniquement avec ces deux lignes, sans explication ni texte supplémentaire."
                end

                require("plenary.curl").post(OLLAMA_URL .. "/api/generate", {
                    headers  = { ["Content-Type"] = "application/json" },
                    body     = vim.json.encode({
                        model  = AI_MODEL,
                        options = { num_thread = 20 },
                        prompt = "Voici le diff git des fichiers sélectionnés :\n\n```diff\n"
                            .. diff
                            .. "\n```\n\n"
                            .. format_instruction,
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
