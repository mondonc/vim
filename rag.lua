-- =============================================================================
-- rag.lua — RAG sur la codebase courante (Ollama + vim-rag CLI)
-- Chargé par init.lua si ~/.vim/.rag-enabled existe
--
-- Dépend de : vim-rag (installé par ./install.sh rag via pipx)
-- Modèle    : lu depuis ~/.vim/.ai-model (partagé avec ai.lua)
-- Ollama    : 192.168.122.1:11434 (hôte KVM)
--
-- Keymaps (mode normal) :
--   <leader>aq  — pose une question sur le projet (prompt)
--   <leader>ar  — question sur le buffer courant + son contexte projet
--   <leader>aR  — réindexer le projet courant
--
-- Commands :
--   :VimRagQuery <question>    équivalent de <leader>aq avec argument
--   :VimRagIndex [path]        réindexer (par défaut : projet courant)
--   :VimRagStatus              afficher l'état de l'index du projet
-- =============================================================================

local OLLAMA_URL = vim.g.ollama_url or "http://192.168.122.1:11434"
local RAG_CMD    = "vim-rag"
local TOP_K      = 6
local NUM_CTX    = 32768   -- cohérent avec ai.lua

-- ----------------------------------------------------------------------------
-- Modèle partagé avec ai.lua
-- ----------------------------------------------------------------------------
local function read_model()
    local f = io.open(vim.fn.expand("~/.vim/.ai-model"), "r")
    if f then
        local model = f:read("*l")
        f:close()
        if model and #model > 0 then
            return vim.trim(model)
        end
    end
    vim.notify(
        "[RAG] ~/.vim/.ai-model introuvable. Lance ./install.sh ia d'abord.",
        vim.log.levels.WARN
    )
    return "qwen2.5-coder:14b"
end

local AI_MODEL = read_model()

-- ----------------------------------------------------------------------------
-- Spinner (copie locale pour ne pas dépendre de ai.lua)
-- ----------------------------------------------------------------------------
local spinner       = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_idx   = 0
local spinner_timer = nil
local spinner_label = ""

local function start_spinner(label)
    spinner_label = label or "En cours…"
    if spinner_timer then return end
    spinner_idx = 0
    spinner_timer = (vim.uv or vim.loop).new_timer()
    spinner_timer:start(0, 80, vim.schedule_wrap(function()
        spinner_idx = (spinner_idx % #spinner) + 1
        vim.o.statusline = " " .. spinner[spinner_idx] .. " " .. spinner_label
        vim.cmd("redrawstatus")
    end))
end

local function update_spinner(label)
    if label and label ~= "" then spinner_label = label end
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

-- ----------------------------------------------------------------------------
-- Pré-conditions
-- ----------------------------------------------------------------------------
local function check_installed()
    if vim.fn.executable(RAG_CMD) ~= 1 then
        vim.notify(
            "[RAG] Commande '" .. RAG_CMD .. "' introuvable.\n"
            .. "Lance : cd ~/.vim && ./install.sh rag",
            vim.log.levels.ERROR
        )
        return false
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Détection de la racine projet
-- ----------------------------------------------------------------------------
local function project_root()
    local markers = {
        ".git", "pyproject.toml", "setup.py", "setup.cfg",
        "manage.py", "package.json", "Cargo.toml", "go.mod",
    }
    local buf_path = vim.api.nvim_buf_get_name(0)
    local start
    if buf_path ~= "" then
        start = vim.fn.fnamemodify(buf_path, ":p:h")
    else
        start = vim.fn.getcwd()
    end
    local ok, root = pcall(vim.fs.root, start, markers)
    if ok and root then return root end
    return vim.fn.getcwd()
end

-- ----------------------------------------------------------------------------
-- Floating window pour la réponse (pattern emprunté à ai.lua)
-- ----------------------------------------------------------------------------
local function open_response_window(title, text)
    local lines = vim.split(text, "\n", { plain = true })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly   = true

    local width  = math.floor(vim.o.columns * 0.75)
    local height = math.min(math.max(#lines + 2, 10), math.floor(vim.o.lines * 0.8))
    local win = vim.api.nvim_open_win(buf, true, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = math.floor((vim.o.lines - height) / 2),
        col       = math.floor((vim.o.columns - width) / 2),
        style     = "minimal",
        border    = "rounded",
        title     = " " .. title .. " ",
        title_pos = "center",
    })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = false

    -- q / <Esc> pour fermer
    vim.keymap.set("n", "q",     "<cmd>close<CR>", { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, nowait = true })

    -- y pour copier toute la réponse dans le presse-papiers système (si dispo)
    vim.keymap.set("n", "yy", function()
        vim.fn.setreg("+", text)
        vim.fn.setreg('"', text)
        vim.notify("[RAG] Réponse copiée", vim.log.levels.INFO)
    end, { buffer = buf, nowait = true })
end

-- ----------------------------------------------------------------------------
-- vim-rag query : appel CLI async, retourne les chunks via callback
-- ----------------------------------------------------------------------------
local function rag_retrieve(project, question, on_done)
    local cmd = { RAG_CMD, "query", question, "--project", project, "-k", tostring(TOP_K) }

    local stdout_chunks, stderr_chunks = {}, {}
    vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data) stdout_chunks = data or {} end,
        on_stderr = function(_, data) stderr_chunks = data or {} end,
        on_exit = function(_, code)
            vim.schedule(function()
                local stdout = table.concat(stdout_chunks, "\n")
                local stderr = table.concat(stderr_chunks, "\n")
                if stdout == "" then
                    on_done(nil, "vim-rag n'a rien renvoyé (code " .. code .. ")\n" .. stderr)
                    return
                end
                local ok, data = pcall(vim.json.decode, stdout)
                if not ok or type(data) ~= "table" then
                    on_done(nil, "JSON invalide de vim-rag:\n" .. stdout:sub(1, 500))
                    return
                end
                if data.error then
                    on_done(nil, "[" .. data.error .. "] " .. (data.message or ""))
                    return
                end
                on_done(data.results or {}, nil)
            end)
        end,
    })
end

-- ----------------------------------------------------------------------------
-- Formatage des chunks en section de contexte lisible
-- ----------------------------------------------------------------------------
local function format_context(chunks)
    if not chunks or #chunks == 0 then
        return "(aucun extrait trouvé dans le projet)"
    end
    local parts = {}
    for _, c in ipairs(chunks) do
        local header = string.format(
            "--- %s:%d-%d  (%s %s, score %.2f) ---",
            c.path, c.start_line, c.end_line, c.type, c.name, c.score
        )
        table.insert(parts, header)
        table.insert(parts, c.text)
        table.insert(parts, "")
    end
    return table.concat(parts, "\n")
end

-- ----------------------------------------------------------------------------
-- Ollama /api/generate : envoie le prompt final, affiche le résultat
-- ----------------------------------------------------------------------------
local function ask_ollama(prompt, title, chunks)
    local ok_curl, curl = pcall(require, "plenary.curl")
    if not ok_curl then
        stop_spinner()
        vim.notify("[RAG] plenary.curl indisponible", vim.log.levels.ERROR)
        return
    end

    local t0 = (vim.uv or vim.loop).now()
    update_spinner("RAG generating with " .. AI_MODEL .. "…")

    curl.post(OLLAMA_URL .. "/api/generate", {
        headers = { ["Content-Type"] = "application/json" },
        body = vim.json.encode({
            model   = AI_MODEL,
            prompt  = prompt,
            stream  = false,
            options = { num_thread = 20, num_ctx = NUM_CTX, temperature = 0.1 },
        }),
        callback = function(response)
            vim.schedule(function()
                stop_spinner()
                if not response or response.status ~= 200 then
                    vim.notify(
                        "[RAG] Erreur Ollama : " .. tostring(response and response.status or "?"),
                        vim.log.levels.ERROR
                    )
                    return
                end
                local ok, data = pcall(vim.json.decode, response.body)
                if not ok or not data or not data.response then
                    vim.notify("[RAG] Réponse Ollama invalide", vim.log.levels.ERROR)
                    return
                end

                local elapsed = ((vim.uv or vim.loop).now() - t0) / 1000
                -- Liste des sources (path:lines), dédupliquée
                local seen, sources = {}, {}
                for _, c in ipairs(chunks or {}) do
                    local key = c.path .. ":" .. c.start_line
                    if not seen[key] then
                        seen[key] = true
                        table.insert(sources, string.format("- %s:%d-%d", c.path, c.start_line, c.end_line))
                    end
                end

                local body = vim.trim(data.response)
                    .. "\n\n---\n"
                    .. "**Sources utilisées :**\n"
                    .. table.concat(sources, "\n")
                    .. string.format("\n\n*Généré en %.1fs avec %s (q/Esc ferme, yy copie)*", elapsed, AI_MODEL)

                open_response_window(title, body)
            end)
        end,
    })
end

-- ----------------------------------------------------------------------------
-- Flux principaux
-- ----------------------------------------------------------------------------

-- <leader>aq — question libre sur le projet
local function flow_query()
    if not check_installed() then return end
    vim.ui.input({ prompt = "RAG — question : " }, function(question)
        if not question or question == "" then return end
        local root = project_root()
        start_spinner("RAG retrieving from " .. vim.fn.fnamemodify(root, ":t") .. "…")
        rag_retrieve(root, question, function(chunks, err)
            if err then
                stop_spinner()
                vim.notify("[RAG] " .. err, vim.log.levels.ERROR)
                return
            end
            if #chunks == 0 then
                stop_spinner()
                vim.notify("[RAG] Aucun extrait pertinent. Le projet est-il indexé ?\n"
                    .. "→ <leader>aR pour indexer.", vim.log.levels.WARN)
                return
            end
            local prompt = table.concat({
                "Tu es un assistant expert d'une codebase. Utilise uniquement les extraits",
                "ci-dessous pour répondre. Si l'information n'y est pas, dis-le clairement.",
                "Cite les fichiers et numéros de ligne pertinents dans ta réponse.",
                "",
                "=== EXTRAITS DU PROJET ===",
                format_context(chunks),
                "=== FIN DES EXTRAITS ===",
                "",
                "Question : " .. question,
                "",
                "Réponds en français, de manière concise.",
            }, "\n")
            ask_ollama(prompt, "RAG — " .. question, chunks)
        end)
    end)
end

-- <leader>ar — question sur le buffer courant + contexte lié dans le projet
local function flow_query_buffer()
    if not check_installed() then return end
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path == "" then
        vim.notify("[RAG] Buffer sans nom de fichier.", vim.log.levels.WARN)
        return
    end
    local root = project_root()
    local rel_path = vim.fn.fnamemodify(buf_path, ":.")
    local content  = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

    -- Pour la requête RAG : on prend le buffer tronqué (les embeddings
    -- n'aiment pas les entrées énormes, et on ne cherche que des éléments liés)
    local retrieval_query = content
    if #retrieval_query > 4000 then
        retrieval_query = retrieval_query:sub(1, 4000)
    end

    vim.ui.input({
        prompt = "RAG — question sur " .. vim.fn.fnamemodify(buf_path, ":t") .. " : ",
        default = "Explique ce fichier et ses liens avec le reste du projet.",
    }, function(question)
        if not question or question == "" then return end
        start_spinner("RAG retrieving related code…")
        rag_retrieve(root, retrieval_query, function(chunks, err)
            if err then
                stop_spinner()
                vim.notify("[RAG] " .. err, vim.log.levels.ERROR)
                return
            end
            -- Filtrer les chunks du fichier courant (on l'a déjà en entier)
            local related = {}
            for _, c in ipairs(chunks) do
                if c.path ~= rel_path then table.insert(related, c) end
            end

            local prompt = table.concat({
                "Tu es un assistant expert d'une codebase. Voici le fichier sur lequel",
                "travaille l'utilisateur, puis des extraits d'autres fichiers du projet",
                "qui lui sont liés sémantiquement.",
                "",
                "=== FICHIER COURANT : " .. rel_path .. " ===",
                content,
                "=== FIN DU FICHIER COURANT ===",
                "",
                "=== EXTRAITS LIÉS DU PROJET ===",
                format_context(related),
                "=== FIN DES EXTRAITS ===",
                "",
                "Question : " .. question,
                "",
                "Réponds en français. Cite les fichiers et lignes pertinents.",
            }, "\n")
            ask_ollama(prompt, "RAG — " .. rel_path, related)
        end)
    end)
end

-- <leader>aR — réindexer le projet courant
local function flow_reindex(path)
    if not check_installed() then return end
    local root = path or project_root()
    vim.notify("[RAG] Indexation de " .. root, vim.log.levels.INFO)
    start_spinner("RAG indexing " .. vim.fn.fnamemodify(root, ":t") .. "…")

    local stderr_lines = {}
    vim.fn.jobstart({ RAG_CMD, "index", root }, {
        on_stderr = function(_, data)
            for _, line in ipairs(data or {}) do
                if line ~= "" then
                    table.insert(stderr_lines, line)
                    -- Met à jour le label du spinner avec la dernière ligne non vide
                    vim.schedule(function()
                        update_spinner("RAG: " .. line:sub(1, 60))
                    end)
                end
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                stop_spinner()
                if code == 0 then
                    -- Dernière ligne stderr contient typiquement "✓ Index : N chunks..."
                    local last = stderr_lines[#stderr_lines] or ""
                    vim.notify("[RAG] " .. last, vim.log.levels.INFO)
                else
                    local tail = {}
                    local n = math.max(1, #stderr_lines - 10)
                    for i = n, #stderr_lines do
                        table.insert(tail, stderr_lines[i])
                    end
                    vim.notify(
                        "[RAG] Échec (code " .. code .. ")\n" .. table.concat(tail, "\n"),
                        vim.log.levels.ERROR
                    )
                end
            end)
        end,
    })
end

-- ----------------------------------------------------------------------------
-- Keymaps (mode normal)
-- ----------------------------------------------------------------------------
vim.keymap.set("n", "<leader>aq", flow_query,        { desc = "RAG: query project" })
vim.keymap.set("n", "<leader>ar", flow_query_buffer, { desc = "RAG: query about buffer" })
vim.keymap.set("n", "<leader>aR", function() flow_reindex() end,
    { desc = "RAG: reindex project" })

-- ----------------------------------------------------------------------------
-- User commands
-- ----------------------------------------------------------------------------
vim.api.nvim_create_user_command("VimRagQuery", function(opts)
    if not check_installed() then return end
    local q = opts.args
    if q == "" then
        flow_query()
        return
    end
    local root = project_root()
    start_spinner("RAG retrieving…")
    rag_retrieve(root, q, function(chunks, err)
        if err then
            stop_spinner()
            vim.notify("[RAG] " .. err, vim.log.levels.ERROR)
            return
        end
        local prompt = "=== EXTRAITS ===\n" .. format_context(chunks)
            .. "\n=== FIN ===\n\nQuestion : " .. q .. "\n\nRéponds en français."
        ask_ollama(prompt, "RAG — " .. q, chunks)
    end)
end, { nargs = "*", desc = "RAG: query project" })

vim.api.nvim_create_user_command("VimRagIndex", function(opts)
    local target = (opts.args ~= "" and opts.args) or nil
    flow_reindex(target)
end, { nargs = "?", complete = "dir", desc = "RAG: index project" })

vim.api.nvim_create_user_command("VimRagStatus", function()
    if not check_installed() then return end
    local root = project_root()
    vim.fn.jobstart({ RAG_CMD, "status", root }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            local text = table.concat(data or {}, "\n")
            if text ~= "" then
                vim.notify("[RAG] " .. text, vim.log.levels.INFO)
            end
        end,
    })
end, { desc = "RAG: index status" })

-- Aucun plugin lazy à enregistrer : on utilise seulement des keymaps et commandes
return {}
