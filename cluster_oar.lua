-- =============================================================================
-- cluster_oar.lua — Gestion automatique d'un nœud OAR (Abaca/Grid5000)
-- Chargé par init.lua si ~/.vim/.cluster-oar-enabled existe
--
-- Config  : ~/.vim/.cluster_oar.conf  (non commité — voir .cluster_oar.conf.example)
-- State   : ~/.vim/.cluster_oar_state (non commité)
--
-- Modèles fixés pour 2x RTX A5000 (48 GB total) :
--   Chat  : qwen2.5-coder:32b   (~19 GB Q4 — meilleur modèle code à ce VRAM)
--   Embed : mxbai-embed-large   (670 MB — haute qualité)
--
-- Keymaps :
--   <leader>aC  toggle cluster (start / stop)
--   <leader>aS  afficher le statut
--
-- Commands :
--   :ClusterStart   démarrer / se reconnecter
--   :ClusterStop    arrêter (oardel + fermer tunnel)
--   :ClusterStatus  fenêtre de statut
--
-- Comportement automatique :
--   • Au démarrage de nvim : reconnecte le tunnel si un job est encore vivant
--   • Quand <leader>aq / ar / aR est appelé sans cluster actif : démarre d'abord
-- =============================================================================

-- ============================================================
-- Constantes
-- ============================================================
local CHAT_MODEL  = "qwen2.5-coder:32b"
local EMBED_MODEL = "mxbai-embed-large"
local LOCAL_PORT  = 11434

local VIMDIR      = vim.fn.fnamemodify(
                        vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h")
local CONF_FILE   = VIMDIR .. "/.cluster_oar.conf"
local STATE_FILE  = VIMDIR .. "/.cluster_oar_state"
local NODE_SCRIPT = VIMDIR .. "/cluster_oar_node.sh"

-- ============================================================
-- Spinner dans la barre d'état
-- ============================================================
local SP       = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" }
local sp_i     = 0
local sp_timer = nil
local sp_msg   = ""

local function sp_start(msg)
    sp_msg = msg; sp_i = 0
    if sp_timer then sp_timer:stop(); sp_timer:close() end
    sp_timer = vim.loop.new_timer()
    sp_timer:start(0, 100, vim.schedule_wrap(function()
        sp_i = (sp_i % #SP) + 1
        vim.api.nvim_echo({{ SP[sp_i] .. "  " .. sp_msg, "DiagnosticInfo" }}, false, {})
    end))
end

local function sp_set(msg) sp_msg = msg end

local function sp_stop(msg, level)
    if sp_timer then sp_timer:stop(); sp_timer:close(); sp_timer = nil end
    vim.schedule(function()
        vim.api.nvim_echo({{"", "Normal"}}, false, {})
        if msg then vim.notify(msg, level or vim.log.levels.INFO) end
    end)
end

-- ============================================================
-- Config (lu une seule fois, cachée en mémoire)
-- ============================================================
local _conf = nil

local function read_conf()
    if _conf then return _conf end
    local c = { login=nil, site="nancy", gateway="access.grid5000.fr",
                gpu_model="RTX A5000", walltime="4:00:00" }
    local f = io.open(CONF_FILE, "r")
    if not f then
        error("[ClusterOAR] Config manquante : " .. CONF_FILE ..
              "\n  cp ~/.vim/.cluster_oar.conf.example ~/.vim/.cluster_oar.conf")
    end
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)%s*=%s*\"?([^\"]-)\"?%s*$")
        if k and v and not line:match("^%s*#") then
            c[k:lower()] = v
        end
    end
    f:close()
    -- Accepte les deux formes de clé : "G5K_LOGIN" (install.sh) et "login" (historique)
    c.login = c.login or c.g5k_login
    assert(c.login and c.login ~= "",
        "[ClusterOAR] G5K_LOGIN manquant dans " .. CONF_FILE)
    _conf = c
    return c
end

-- ============================================================
-- State (persisté entre sessions nvim)
-- ============================================================
local S = { job_id=nil, node=nil, deadline=nil, tunnel_jid=nil }

local function save_state()
    local f = io.open(STATE_FILE, "w"); if not f then return end
    f:write(("job_id=%s\nnode=%s\ndeadline=%s\n"):format(
        S.job_id or "", S.node or "", S.deadline and tostring(S.deadline) or ""))
    f:close()
end

local function load_state()
    S.job_id = nil; S.node = nil; S.deadline = nil
    local f = io.open(STATE_FILE, "r"); if not f then return end
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k and v and v ~= "" then
            if     k == "job_id"   then S.job_id   = v
            elseif k == "node"     then S.node      = v
            elseif k == "deadline" then S.deadline  = tonumber(v)
            end
        end
    end
    f:close()
end

local function job_valid()
    return S.job_id ~= nil
       and S.deadline ~= nil
       and os.time() < S.deadline - 300  -- marge de 5 min
end

-- ============================================================
-- Helpers SSH
-- ============================================================
local function frontend_fqdn(conf)
    return "f" .. conf.site .. ".grid5000.fr"
end

local function node_fqdn(conf, node)
    if node:find("%.") then return node end
    return node .. "." .. conf.site .. ".grid5000.fr"
end

-- Lance cmd sur le frontend via SSH, appelle cb(code, stdout)
-- stderr est redirigé sur stdout (2>&1) pour ne pas perdre les messages d'erreur
-- de commandes comme oarstat qui écrivent parfois sur stderr.
local function ssh_run(conf, cmd, cb)
    local out = {}
    vim.fn.jobstart({
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=15",
        "-J", conf.login .. "@" .. conf.gateway,
        conf.login .. "@" .. frontend_fqdn(conf),
        cmd .. " 2>&1",   -- ← stderr → stdout pour ne rien perdre
    }, {
        on_stdout = function(_, data)
            for _, l in ipairs(data or {}) do
                if l ~= "" then out[#out+1] = l end
            end
        end,
        on_exit = function(_, code)
            cb(code, table.concat(out, "\n"))
        end,
    })
end

-- ============================================================
-- Tunnel SSH
-- ============================================================
local function tunnel_ok()
    -- Teste si le port local répond (max 1s)
    local r = vim.fn.system(
        "curl -sf --max-time 1 http://localhost:" .. LOCAL_PORT .. "/api/tags 2>/dev/null")
    return vim.v.shell_error == 0 and r ~= ""
end

local function open_tunnel(conf, node, on_ready)
    if S.tunnel_jid then pcall(vim.fn.jobstop, S.tunnel_jid) end
    sp_set("Ouverture du tunnel SSH…")

    -- Tunnel : localhost:LOCAL_PORT → node:11434
    -- via gateway → frontend (le frontend peut joindre le nœud en interne)
    local jid = vim.fn.jobstart({
        "ssh", "-N",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=15",
        "-o", "ServerAliveInterval=30",
        "-o", "ExitOnForwardFailure=yes",
        "-L", LOCAL_PORT .. ":" .. node_fqdn(conf, node) .. ":11434",
        "-J", conf.login .. "@" .. conf.gateway,
        conf.login .. "@" .. frontend_fqdn(conf),
    }, {
        on_exit = function(_, code)
            S.tunnel_jid = nil
            if code ~= 0 and code ~= 130 then
                vim.schedule(function()
                    vim.notify("[ClusterOAR] Tunnel interrompu (code " .. code .. ")",
                               vim.log.levels.WARN)
                end)
            end
        end,
    })
    S.tunnel_jid = jid

    -- Attente que le port local réponde (max 30s)
    local tries = 0
    local t = vim.loop.new_timer()
    t:start(500, 1000, vim.schedule_wrap(function()
        tries = tries + 1
        if tunnel_ok() then
            t:stop(); t:close()
            on_ready()
        elseif tries > 30 then
            t:stop(); t:close()
            sp_stop("[ClusterOAR] Tunnel injoignable après 30s", vim.log.levels.ERROR)
        end
    end))
end

-- ============================================================
-- Soumission et suivi OAR
-- ============================================================
local function walltime_to_secs(wt)
    local h, m, s = wt:match("(%d+):(%d+):(%d+)")
    return (tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(s)
end

local function submit_job(conf, on_done)
    sp_set("Copie du script sur le frontend…")

    -- scp du node script vers le frontend
    vim.fn.jobstart({
        "scp",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=15",
        "-J", conf.login .. "@" .. conf.gateway,
        NODE_SCRIPT,
        conf.login .. "@" .. frontend_fqdn(conf) .. ":~/cluster_oar_node.sh",
    }, {
        on_exit = function(_, scp_code)
            if scp_code ~= 0 then
                sp_stop("[ClusterOAR] Échec scp du script nœud", vim.log.levels.ERROR)
                return
            end
            sp_set("Soumission du job OAR…")
            local oar_cmd = table.concat({
                "chmod +x ~/cluster_oar_node.sh &&",
                "oarsub -q abaca",
                "-p \"gpu_model='" .. conf.gpu_model .. "'\"",
                "-l \"host=1/gpu=2,walltime=" .. conf.walltime .. "\"",
                "-n nvim_cluster",
                "\"$HOME/cluster_oar_node.sh\"",
            }, " ")
            ssh_run(conf, oar_cmd, function(code, out)
                if code ~= 0 then
                    sp_stop("[ClusterOAR] Erreur OAR:\n" .. out, vim.log.levels.ERROR)
                    return
                end
                local job_id = out:match("OAR_JOB_ID=(%d+)")
                if not job_id then
                    sp_stop("[ClusterOAR] OAR_JOB_ID introuvable:\n" .. out,
                            vim.log.levels.ERROR)
                    return
                end
                S.job_id   = job_id
                S.deadline = os.time() + walltime_to_secs(conf.walltime)
                save_state()
                sp_set("Job " .. job_id .. " soumis, attente du nœud…")
                on_done(job_id)
            end)
        end,
    })
end

local function poll_until_running(conf, job_id, on_running)
    local tries = 0
    local function poll()
        tries = tries + 1
        if tries > 40 then  -- 10 min max (40 × 15s)
            sp_stop("[ClusterOAR] Timeout : nœud non alloué", vim.log.levels.ERROR)
            S.job_id = nil; save_state()
            return
        end
        sp_set(("Job %s en attente… (%d/40)"):format(job_id, tries))
        ssh_run(conf, "oarstat -j " .. job_id .. " -f", function(_, out)
            -- Debug : affiche la sortie brute la première fois pour aider au diagnostic
            if tries == 1 and out ~= "" then
                vim.schedule(function()
                    vim.notify("[ClusterOAR] oarstat output (debug):\n" .. out:sub(1, 500),
                               vim.log.levels.DEBUG)
                end)
            end

            -- Matching robuste : insensible à la casse, trim des espaces
            local st = out:match("[Ss]tate%s*=%s*(%w+)")
            -- Le champ s'appelle assigned_hostnames (pas assigned_network_address)
            local nd = out:match("[Aa]ssigned_hostnames%s*=%s*(%S+)")

            if st and st:lower() == "running" and nd and nd ~= "" then
                S.node = nd; save_state()
                sp_set("Nœud alloué : " .. nd)
                on_running(nd)
            elseif st and (st:lower() == "error"
                        or st:lower() == "finishing"
                        or st:lower() == "terminated") then
                sp_stop("[ClusterOAR] Job en état '" .. st .. "'", vim.log.levels.ERROR)
                S.job_id = nil; S.node = nil; save_state()
            else
                -- Ni Running ni état terminal : on repolling
                -- Si out est vide, c'est probablement un problème SSH/oarstat
                if out == "" then
                    vim.schedule(function()
                        vim.notify("[ClusterOAR] oarstat a retourné une sortie vide (essai "
                                   .. tries .. "). Vérifie la connexion SSH au frontend.",
                                   vim.log.levels.WARN)
                    end)
                end
                vim.defer_fn(poll, 15000)
            end
        end)
    end
    poll()
end

local function check_job_alive(conf, job_id, cb)
    ssh_run(conf, "oarstat -j " .. job_id .. " -f 2>/dev/null; echo __END__",
        function(_, out)
            local st = out:match("[Ss]tate%s*=%s*(%w+)")
            local nd = out:match("[Aa]ssigned_hostnames%s*=%s*(%S+)")
            cb(st ~= nil and st:lower() == "running" and nd ~= nil, nd)
        end)
end

-- ============================================================
-- Attente des modèles (pull en cours sur le nœud)
-- ============================================================
local function wait_models(on_ready)
    local tries = 0
    local function check()
        tries = tries + 1
        if tries > 60 then  -- 10 min max (60 × 10s)
            sp_stop("[ClusterOAR] Timeout pull modèles", vim.log.levels.ERROR)
            return
        end
        -- Appel curl async pour ne pas bloquer l'event loop
        local out_buf = {}
        vim.fn.jobstart({
            "curl", "-sf", "--max-time", "3",
            "http://localhost:" .. LOCAL_PORT .. "/api/tags",
        }, {
            on_stdout = function(_, d)
                for _, l in ipairs(d or {}) do
                    if l ~= "" then out_buf[#out_buf+1] = l end
                end
            end,
            on_exit = function(_, code)
                if code ~= 0 then
                    sp_set("Attente ollama… (" .. tries .. "/60)")
                    vim.defer_fn(check, 10000)
                    return
                end
                local ok, data = pcall(vim.json.decode, table.concat(out_buf))
                if not ok then vim.defer_fn(check, 10000); return end

                local models = data.models or {}
                local chat_ok, embed_ok = false, false
                for _, m in ipairs(models) do
                    local n = (m.name or ""):lower()
                    if n:find("qwen2.5%-coder") and n:find("32") then chat_ok  = true end
                    if n:find("mxbai")                             then embed_ok = true end
                end

                if chat_ok and embed_ok then
                    -- Activer l'URL pour ai.lua et rag.lua
                    vim.g.ollama_url = "http://localhost:" .. LOCAL_PORT
                    sp_stop("✓ Cluster prêt — " .. CHAT_MODEL)
                    on_ready()
                else
                    local missing = {}
                    if not chat_ok  then missing[#missing+1] = CHAT_MODEL  end
                    if not embed_ok then missing[#missing+1] = EMBED_MODEL end
                    sp_set("Pull : " .. table.concat(missing, ", ") .. " …")
                    vim.defer_fn(check, 10000)
                end
            end,
        })
    end
    check()
end

-- ============================================================
-- Point d'entrée principal
-- ============================================================
local _starting = false

local function ensure_ready(on_done)
    -- Déjà prêt ?
    if S.tunnel_jid and tunnel_ok() then
        on_done(); return
    end
    if _starting then
        vim.notify("[ClusterOAR] Déjà en cours de démarrage…", vim.log.levels.INFO)
        return
    end

    local ok, conf = pcall(read_conf)
    if not ok then vim.notify(conf, vim.log.levels.ERROR); return end

    _starting = true
    load_state()
    sp_start("Vérification cluster OAR…")

    local function on_node(node)
        open_tunnel(conf, node, function()
            wait_models(function()
                _starting = false
                on_done()
            end)
        end)
    end

    if job_valid() then
        sp_set("Vérification du job " .. S.job_id .. "…")
        check_job_alive(conf, S.job_id, function(alive, node)
            if alive then
                if node then S.node = node; save_state() end
                on_node(S.node)
            else
                S.job_id = nil; S.node = nil; save_state()
                submit_job(conf, function(jid)
                    poll_until_running(conf, jid, on_node)
                end)
            end
        end)
    else
        if S.job_id then S.job_id = nil; S.node = nil; save_state() end
        submit_job(conf, function(jid)
            poll_until_running(conf, jid, on_node)
        end)
    end
end

-- ============================================================
-- Stop cluster
-- ============================================================
local function stop_cluster()
    if S.tunnel_jid then
        pcall(vim.fn.jobstop, S.tunnel_jid); S.tunnel_jid = nil
    end
    vim.g.ollama_url = nil
    _starting = false

    if S.job_id then
        local ok, conf = pcall(read_conf)
        if ok then
            ssh_run(conf, "oardel " .. S.job_id, function() end)
        end
        vim.notify("[ClusterOAR] Job " .. S.job_id .. " annulé", vim.log.levels.INFO)
        S.job_id = nil; S.node = nil; save_state()
    else
        vim.notify("[ClusterOAR] Aucun job actif", vim.log.levels.INFO)
    end
end

-- ============================================================
-- Fenêtre de statut
-- ============================================================
local function show_status()
    load_state()
    local ok, conf = pcall(read_conf)

    local function yesno(v) return v and "✓" or "✗" end
    local t_ok = S.tunnel_jid ~= nil and tunnel_ok()

    local lines = {
        "",
        "  ╔═════════════════════════════════════╗",
        "  ║       Cluster OAR — Statut          ║",
        "  ╠═════════════════════════════════════╣",
    }
    if ok then
        lines[#lines+1] = ("  ║  Login   : %-26s║"):format(conf.login)
        lines[#lines+1] = ("  ║  Site    : %-26s║"):format(conf.site)
        lines[#lines+1] = ("  ║  GPU     : 2x %-24s║"):format(conf.gpu_model)
        lines[#lines+1] = "  ╠═════════════════════════════════════╣"
    end
    if S.job_id then
        local deadline_str = S.deadline and
            os.date("%H:%M le %d/%m", S.deadline) or "?"
        lines[#lines+1] = ("  ║  Job ID  : %-26s║"):format(S.job_id)
        lines[#lines+1] = ("  ║  Nœud    : %-26s║"):format(S.node or "en attente")
        lines[#lines+1] = ("  ║  Expire  : %-26s║"):format(deadline_str)
    else
        lines[#lines+1] = "  ║  Aucun job actif                    ║"
    end
    lines[#lines+1] = "  ╠═════════════════════════════════════╣"
    lines[#lines+1] = ("  ║  Tunnel  : %s localhost:%-15d║"):format(
        t_ok and "✓" or "✗", LOCAL_PORT)
    lines[#lines+1] = ("  ║  Modèle  : %-26s║"):format(
        t_ok and CHAT_MODEL or "(inactif)")
    lines[#lines+1] = "  ╠═════════════════════════════════════╣"
    lines[#lines+1] = "  ║  <leader>aC  toggle start/stop      ║"
    lines[#lines+1] = "  ║  q / <Esc>   fermer                 ║"
    lines[#lines+1] = "  ╚═════════════════════════════════════╝"
    lines[#lines+1] = ""

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("buftype",    "nofile", { buf = buf })

    local w = 44
    local win = vim.api.nvim_open_win(buf, true, {
        relative  = "editor",
        width     = w,
        height    = #lines,
        row       = math.floor((vim.o.lines   - #lines) / 2),
        col       = math.floor((vim.o.columns - w)      / 2),
        style     = "minimal",
        border    = "none",
    })
    vim.api.nvim_set_option_value(
        "winhl", "Normal:Normal", { win = win })
    for _, key in ipairs({ "q", "<Esc>", "<leader>aS" }) do
        vim.keymap.set("n", key, "<cmd>close<CR>",
            { buffer = buf, nowait = true, silent = true })
    end
end

-- ============================================================
-- Auto-reconnexion au démarrage de nvim
-- Logique :
--   • Pas de state file               → rien (premier lancement ou après ClusterStop)
--   • State file + deadline dépassée  → état purgé silencieusement
--   • State file + deadline OK        → on vérifie que le job tourne RÉELLEMENT
--     via oarstat (SSH asynchrone, n'ajoute pas de latence perceptible au démarrage)
--     puis on ouvre le tunnel seulement si c'est confirmé
-- ============================================================
load_state()
if job_valid() and S.node then
    -- Vérification asynchrone : on ne bloque pas le démarrage de nvim
    vim.schedule(function()
        local ok, conf = pcall(read_conf)
        if not ok then return end  -- config absente → silencieux au démarrage

        vim.notify(
            "[ClusterOAR] Job " .. S.job_id .. " en mémoire, vérification…",
            vim.log.levels.INFO)

        check_job_alive(conf, S.job_id, function(alive, node)
            if not alive then
                -- Job mort (OAR l'a tué, walltime dépassé côté cluster, etc.)
                vim.notify(
                    "[ClusterOAR] Job " .. S.job_id .. " terminé — lance :ClusterStart pour un nouveau.",
                    vim.log.levels.WARN)
                S.job_id = nil; S.node = nil; S.deadline = nil
                save_state()
                return
            end
            -- Job vivant → mettre à jour le nœud et ouvrir le tunnel
            if node then S.node = node; save_state() end
            vim.notify(
                "[ClusterOAR] Job actif sur " .. S.node .. " — reconnexion tunnel…",
                vim.log.levels.INFO)
            open_tunnel(conf, S.node, function()
                wait_models(function()
                    vim.notify("[ClusterOAR] ✓ Cluster reconnecté", vim.log.levels.INFO)
                end)
            end)
        end)
    end)
elseif S.job_id then
    -- State file présent mais deadline expirée → purge silencieuse
    S.job_id = nil; S.node = nil; S.deadline = nil
    save_state()
end

-- ============================================================
-- Auto-hook : intercepte <leader>aq / ar / aR pour démarrer
-- le cluster si nécessaire (s'enregistre après LazyDone)
-- ============================================================
vim.api.nvim_create_autocmd("User", {
    pattern  = "LazyDone",
    once     = true,
    callback = function()
        local function wrap(lhs)
            local m = vim.fn.maparg(lhs, "n", false, true)
            if not (m and m.callback) then return end
            local orig = m.callback
            vim.keymap.set("n", lhs, function()
                if tunnel_ok() then
                    orig()
                else
                    ensure_ready(orig)
                end
            end, { desc = (m.desc or lhs) .. " [cluster]", silent = true })
        end
        for _, lhs in ipairs({ "<leader>aq", "<leader>ar", "<leader>aR" }) do
            wrap(lhs)
        end
    end,
})

-- ============================================================
-- Commands & Keymaps
-- ============================================================
vim.api.nvim_create_user_command("ClusterStart", function()
    ensure_ready(function()
        vim.notify("[ClusterOAR] ✓ Prêt", vim.log.levels.INFO)
    end)
end, { desc = "Démarrer le cluster OAR (Abaca)" })

vim.api.nvim_create_user_command("ClusterStop",
    stop_cluster,
    { desc = "Arrêter le cluster OAR et fermer le tunnel" })

vim.api.nvim_create_user_command("ClusterStatus",
    show_status,
    { desc = "Statut du cluster OAR" })

vim.keymap.set("n", "<leader>aC", function()
    if S.tunnel_jid and tunnel_ok() then
        stop_cluster()
    else
        ensure_ready(function()
            vim.notify("[ClusterOAR] ✓ Cluster prêt", vim.log.levels.INFO)
        end)
    end
end, { desc = "Cluster: toggle (start/stop)", silent = true })

vim.keymap.set("n", "<leader>aS", show_status,
    { desc = "Cluster: statut", silent = true })

-- Compatibilité avec le pattern dofile() de init.lua
return {}
