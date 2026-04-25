-- =============================================================================
-- gitlab.lua — Workflow IA autour des issues GitLab
-- Chargé par init.lua si ~/.vim/.gitlab-enabled existe
--
-- Dépend de : ai.lua (CodeCompanion), telescope, plenary
-- Utilise   : API REST GitLab directe (pas de plugin gitlab.nvim pour l'instant)
--
-- Auth :
--   - lit .gitlab.nvim à la racine du projet (format key=value),
--     OU les variables d'env GITLAB_TOKEN / GITLAB_URL
--
-- Keymaps (mode normal) :
--   <leader>gi  — choisir une issue (Telescope picker)
--   <leader>gw  — démarrer le workflow IA sur l'issue courante (chat CodeCompanion)
--   <leader>gC  — effacer l'issue courante (vim.g.current_issue)
--
-- Commands :
--   :GitlabIssue       équivalent de <leader>gi
--   :GitlabIssueWork   équivalent de <leader>gw
--   :GitlabIssueClear  équivalent de <leader>gC
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Lecture de la config GitLab (token + URL)
-- Priorité : fichier .gitlab.nvim > variables d'env > défaut https://gitlab.com
-- ----------------------------------------------------------------------------
local function read_gitlab_config()
    local cfg = { token = nil, url = nil }

    -- 1. Fichier .gitlab.nvim à la racine du projet (format key=value)
    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    if git_root and git_root ~= "" then
        local f = io.open(git_root .. "/.gitlab.nvim", "r")
        if f then
            for line in f:lines() do
                local k, v = line:match("^%s*([%w_]+)%s*=%s*(.+)%s*$")
                if k == "token" then cfg.token = vim.trim(v) end
                if k == "gitlab_url" then cfg.url = vim.trim(v) end
            end
            f:close()
        end
    end

    -- 2. Variables d'environnement (fallback)
    cfg.token = cfg.token or vim.env.GITLAB_TOKEN
    cfg.url   = cfg.url   or vim.env.GITLAB_URL or "https://gitlab.com"

    -- Nettoyage : enlève le slash final
    cfg.url = cfg.url:gsub("/+$", "")

    return cfg
end

-- ----------------------------------------------------------------------------
-- Détection du projet GitLab depuis `git remote get-url origin`
-- Retourne l'identifiant URL-encodé (ex: "group%2Fsubgroup%2Fproject")
-- ----------------------------------------------------------------------------
local function detect_project_path()
    local remote = vim.fn.systemlist("git remote get-url origin 2>/dev/null")[1]
    if not remote or remote == "" then return nil end

    -- Formats possibles :
    --   git@gitlab.example.com:group/sub/project.git
    --   https://gitlab.example.com/group/sub/project.git
    --   ssh://git@gitlab.example.com:22/group/sub/project.git
    local path
    if remote:match("^git@") then
        path = remote:match("^git@[^:]+:(.+)$")
    elseif remote:match("^ssh://") then
        path = remote:match("^ssh://[^/]+/(.+)$")
    else
        path = remote:match("^https?://[^/]+/(.+)$")
    end

    if not path then return nil end
    path = path:gsub("%.git$", "")
    -- URL-encode les / en %2F (requis par l'API GitLab)
    return path:gsub("/", "%%2F")
end

-- ----------------------------------------------------------------------------
-- Appel REST GitLab (GET) — async via plenary.curl
-- ----------------------------------------------------------------------------
local function gitlab_get(path, on_done)
    local cfg = read_gitlab_config()
    if not cfg.token then
        vim.notify("[GitLab] Token introuvable. Définis GITLAB_TOKEN ou .gitlab.nvim",
            vim.log.levels.ERROR)
        return
    end

    local ok, curl = pcall(require, "plenary.curl")
    if not ok then
        vim.notify("[GitLab] plenary.curl indisponible", vim.log.levels.ERROR)
        return
    end

    curl.get(cfg.url .. "/api/v4" .. path, {
        headers = { ["PRIVATE-TOKEN"] = cfg.token },
        callback = function(response)
            vim.schedule(function()
                if response.status ~= 200 then
                    vim.notify(string.format("[GitLab] HTTP %d sur %s\n%s",
                        response.status, path, response.body or ""),
                        vim.log.levels.ERROR)
                    return
                end
                local ok_json, data = pcall(vim.json.decode, response.body)
                if not ok_json then
                    vim.notify("[GitLab] JSON invalide", vim.log.levels.ERROR)
                    return
                end
                on_done(data)
            end)
        end,
    })
end

-- ----------------------------------------------------------------------------
-- Récupère la liste des issues OUVERTES du projet courant
-- ----------------------------------------------------------------------------
local function fetch_open_issues(on_done)
    local proj = detect_project_path()
    if not proj then
        vim.notify("[GitLab] Impossible de détecter le projet (git remote origin manquant)",
            vim.log.levels.ERROR)
        return
    end

    -- per_page=100 : suffisant pour la plupart des projets, paginer si besoin
    gitlab_get("/projects/" .. proj .. "/issues?state=opened&per_page=100&order_by=updated_at",
        on_done)
end

-- ----------------------------------------------------------------------------
-- Slug pour les noms de branche : minuscules, accents stripés, tirets
-- ----------------------------------------------------------------------------
local function slugify(s)
    s = s:lower()
    -- Remplace les caractères accentués courants (approximation)
    local accents = {
        ["à"]="a",["á"]="a",["â"]="a",["ã"]="a",["ä"]="a",
        ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",
        ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",
        ["ò"]="o",["ó"]="o",["ô"]="o",["õ"]="o",["ö"]="o",
        ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",
        ["ý"]="y",["ÿ"]="y",["ç"]="c",["ñ"]="n",
    }
    for k, v in pairs(accents) do s = s:gsub(k, v) end
    -- Tout sauf alphanum → tiret
    s = s:gsub("[^%w]+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    -- Tronque à 50 caractères pour la lisibilité
    if #s > 50 then s = s:sub(1, 50):gsub("%-+$", "") end
    return s
end

-- ----------------------------------------------------------------------------
-- Q1 (c) : demande à l'utilisateur s'il veut créer une branche pour cette issue
-- Crée `issue-<id>-<slug>` depuis HEAD si oui
-- ----------------------------------------------------------------------------
local function maybe_create_branch(issue, on_done)
    local branch_name = string.format("issue-%d-%s", issue.iid, slugify(issue.title))
    vim.ui.select({ "Oui (créer " .. branch_name .. ")", "Non (rester sur la branche courante)" },
        { prompt = "Créer une branche locale pour cette issue ?" },
        function(choice)
            if not choice then return end -- annulé
            if choice:match("^Oui") then
                local out = vim.fn.system("git checkout -b " .. vim.fn.shellescape(branch_name))
                if vim.v.shell_error ~= 0 then
                    vim.notify("[Git] Échec : " .. out, vim.log.levels.ERROR)
                    return
                end
                vim.notify("[Git] ✓ Branche créée et checkoutée : " .. branch_name,
                    vim.log.levels.INFO)
            end
            if on_done then on_done() end
        end)
end

-- ----------------------------------------------------------------------------
-- Telescope picker pour choisir une issue
-- ----------------------------------------------------------------------------
local function pick_issue()
    fetch_open_issues(function(issues)
        if not issues or #issues == 0 then
            vim.notify("[GitLab] Aucune issue ouverte", vim.log.levels.INFO)
            return
        end

        local pickers      = require("telescope.pickers")
        local finders      = require("telescope.finders")
        local conf         = require("telescope.config").values
        local actions      = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local previewers   = require("telescope.previewers")

        -- Format d'affichage : "#42 — Titre de l'issue"
        local entries = {}
        for _, issue in ipairs(issues) do
            table.insert(entries, {
                value   = issue,
                display = string.format("#%-4d %s", issue.iid, issue.title),
                ordinal = string.format("%d %s", issue.iid, issue.title),
            })
        end

        pickers.new({}, {
            prompt_title = "GitLab Issues (Enter = sélectionner)",
            finder = finders.new_table({
                results    = entries,
                entry_maker = function(e) return e end,
            }),
            sorter = conf.generic_sorter({}),

            -- Preview : description de l'issue
            previewer = previewers.new_buffer_previewer({
                title = "Description",
                define_preview = function(self, entry)
                    local issue = entry.value
                    local lines = { "# #" .. issue.iid .. " — " .. issue.title, "" }
                    if issue.labels and #issue.labels > 0 then
                        table.insert(lines, "**Labels** : " .. table.concat(issue.labels, ", "))
                        table.insert(lines, "")
                    end
                    if issue.description and issue.description ~= "" then
                        for line in (issue.description .. "\n"):gmatch("([^\n]*)\n") do
                            table.insert(lines, line)
                        end
                    else
                        table.insert(lines, "_(pas de description)_")
                    end
                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                    vim.bo[self.state.bufnr].filetype = "markdown"
                end,
            }),

            attach_mappings = function(buf, _)
                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(buf)
                    if not entry then return end
                    local issue = entry.value

                    -- Stocke l'issue (Q4 a : volatile, vim.g.*)
                    vim.g.current_issue = {
                        iid         = issue.iid,
                        title       = issue.title,
                        description = issue.description or "",
                        web_url     = issue.web_url,
                        labels      = issue.labels or {},
                    }

                    vim.notify(string.format("[GitLab] Issue sélectionnée : #%d %s",
                        issue.iid, issue.title), vim.log.levels.INFO)

                    -- Q1 (c) : proposer la création de branche
                    maybe_create_branch(issue, function()
                        vim.notify("[GitLab] :GitlabIssueWork pour démarrer le workflow IA",
                            vim.log.levels.INFO)
                    end)
                end)
                return true
            end,
        }):find()
    end)
end

-- ----------------------------------------------------------------------------
-- Construit l'arborescence du projet (utilisé en system prompt par le workflow IA)
-- Limité à 3 niveaux pour rester compact dans le contexte
-- ----------------------------------------------------------------------------
local function project_tree()
    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    if not git_root or git_root == "" then return "(pas dans un repo git)" end

    -- Si tree est dispo, on l'utilise (plus joli) ; sinon find
    local cmd
    if vim.fn.executable("tree") == 1 then
        cmd = string.format("cd %s && tree -L 3 -I '__pycache__|node_modules|.git|.venv|venv|dist|build|*.egg-info' --noreport 2>/dev/null",
            vim.fn.shellescape(git_root))
    else
        cmd = string.format("cd %s && find . -maxdepth 3 -type f -not -path './.git/*' -not -path '*/__pycache__/*' -not -path '*/node_modules/*' 2>/dev/null | head -200",
            vim.fn.shellescape(git_root))
    end

    local out = vim.fn.system(cmd)
    -- Limite à ~500 lignes pour ne pas exploser le contexte
    local lines = vim.split(out, "\n")
    if #lines > 500 then
        lines = vim.list_slice(lines, 1, 500)
        table.insert(lines, "... (tronqué)")
    end
    return table.concat(lines, "\n")
end

-- Exposé globalement pour que ai.lua puisse l'appeler depuis le prompt_library
_G.GitlabIssueProjectTree = project_tree

-- ----------------------------------------------------------------------------
-- Lance le workflow IA sur l'issue courante
-- → invoke le prompt "Issue Workflow" (défini dans ai.lua) qui lit vim.g.current_issue
-- ----------------------------------------------------------------------------
local function start_workflow()
    if not vim.g.current_issue then
        vim.notify("[GitLab] Aucune issue sélectionnée. Utilise :GitlabIssue d'abord.",
            vim.log.levels.WARN)
        return
    end

    -- Ouvre la palette d'actions de CodeCompanion ; le prompt "Issue Workflow"
    -- est enregistré dans ai.lua via prompt_library.
    -- Alternative possible : require("codecompanion").prompt("issue_workflow")
    -- mais l'API exacte varie selon la version, donc on utilise la palette
    -- qui est une interface stable.
    local ok = pcall(vim.cmd, "CodeCompanion /issue_workflow")
    if not ok then
        -- Fallback : ouvre la palette pour que l'utilisateur sélectionne
        vim.notify("[GitLab] Sélectionne 'Issue Workflow' dans la palette",
            vim.log.levels.INFO)
        vim.cmd("CodeCompanionActions")
    end
end

-- ----------------------------------------------------------------------------
-- Efface l'issue courante
-- ----------------------------------------------------------------------------
local function clear_issue()
    if vim.g.current_issue then
        vim.notify(string.format("[GitLab] Issue #%d effacée", vim.g.current_issue.iid),
            vim.log.levels.INFO)
        vim.g.current_issue = nil
    else
        vim.notify("[GitLab] Pas d'issue courante", vim.log.levels.INFO)
    end
end

-- ----------------------------------------------------------------------------
-- Commandes & keymaps
-- ----------------------------------------------------------------------------
vim.api.nvim_create_user_command("GitlabIssue",      pick_issue,     { desc = "GitLab: pick issue" })
vim.api.nvim_create_user_command("GitlabIssueWork",  start_workflow, { desc = "GitLab: start AI workflow" })
vim.api.nvim_create_user_command("GitlabIssueClear", clear_issue,    { desc = "GitLab: clear current issue" })

vim.keymap.set("n", "<leader>gi", pick_issue,     { desc = "GitLab: pick issue" })
vim.keymap.set("n", "<leader>gw", start_workflow, { desc = "GitLab: AI workflow" })
vim.keymap.set("n", "<leader>gC", clear_issue,    { desc = "GitLab: clear issue" })

-- Aucun plugin lazy à enregistrer : on utilise seulement des commandes/keymaps
return {}
