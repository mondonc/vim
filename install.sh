#!/bin/bash

set -euo pipefail

DIR_VIM_GIT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Vérification qu'on est bien dans ~/.vim
if [ "$(realpath "$DIR_VIM_GIT")" != "$(realpath "$HOME/.vim")" ]; then
    echo "ERREUR : ce dépôt doit être cloné dans ~/.vim"
    echo "  Emplacement actuel : $DIR_VIM_GIT"
    echo "  Attendu            : $HOME/.vim"
    exit 1
fi

# Répertoire undo persistant
mkdir -p "$HOME/.vim/undodir-vim" "$HOME/.vim/undodir-nvim"

# --- Vim : vim-plug ---
echo "=== Installation de vim-plug ==="
if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
    curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

echo "=== Lien ~/.vimrc ==="
ln -sfn "$DIR_VIM_GIT/vimrc" "$HOME/.vimrc"

echo "=== Installation des plugins Vim ==="
vim +PlugInstall +qall

# --- Neovim : lazy.nvim (s'auto-bootstrap au premier lancement) ---
echo "=== Lien ~/.config/nvim/init.lua ==="
mkdir -p "$HOME/.config/nvim"
ln -sfn "$DIR_VIM_GIT/init.lua" "$HOME/.config/nvim/init.lua"

echo "=== Installation des plugins Neovim (lazy.nvim) ==="
nvim --headless "+Lazy! sync" +qa

# --- Alias vim/vi → nvim dans .bashrc ---
echo "=== Alias vim/vi → nvim ==="
if command -v nvim &>/dev/null; then
    for rc in "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$rc" ]; then
            # Supprime les anciennes versions de ces alias s'ils existent
            sed -i '/^alias vim=.*nvim/d' "$rc"
            sed -i '/^alias vi=.*nvim/d' "$rc"
            echo 'alias vim="nvim"' >> "$rc"
            echo 'alias vi="nvim"'  >> "$rc"
            echo "  ✓ Alias ajoutés dans $rc"
        fi
    done
else
    echo "  ⚠ nvim non trouvé dans le PATH, alias ignorés"
fi

# --- Outils Python ---
echo "=== Installation des outils Python via pipx ==="
sudo apt-get -y install pipx
for tool in ruff pyright; do
    pipx install "$tool" 2>/dev/null || pipx upgrade "$tool"
done
pipx ensurepath

# --- Linters Vim (syntastic) ---
echo "=== Installation des linters pour Vim/syntastic ==="
sudo apt-get -y install pyflakes3 flake8 ripgrep

echo ""
echo "=== Terminé ==="
echo "  Vim  : lance vim, tout est prêt"
echo "  Nvim : lance nvim, lazy.nvim installera les plugins au premier lancement"

# =============================================================================
# IA (optionnel : ./install.sh ia)
# Configure CodeCompanion (dans Neovim) + OpenCode (CLI + panneau Neovim)
# Les deux utilisent Ollama sur l'hôte KVM (192.168.122.1:11434)
# =============================================================================
if [ "${1:-}" = "ia" ]; then

    OLLAMA_HOST="192.168.122.1"
    OLLAMA_PORT="11434"
    OLLAMA_BASE_URL="http://${OLLAMA_HOST}:${OLLAMA_PORT}"

    echo ""
    echo "=== Activation des outils IA (CodeCompanion + OpenCode) ==="
    echo "    Ollama : ${OLLAMA_BASE_URL}"

    # -------------------------------------------------------------------------
    # 1. Vérifier que Ollama est accessible
    # -------------------------------------------------------------------------
    echo ""
    echo "→ Connexion à Ollama..."
    if ! curl -sf --max-time 5 "${OLLAMA_BASE_URL}/api/tags" > /tmp/ollama_models.json 2>/dev/null; then
        echo ""
        echo "ERREUR : impossible de joindre Ollama sur ${OLLAMA_BASE_URL}"
        echo ""
        echo "  Vérifie que :"
        echo "    1. Le conteneur Docker 'ollama' tourne sur l'hôte"
        echo "       → docker start ollama"
        echo "    2. Il écoute sur 0.0.0.0 (pas seulement 127.0.0.1)"
        echo "       → dans docker-compose.yml : \"0.0.0.0:11434:11434\""
        echo "    3. Le firewall de l'hôte ne bloque pas virbr0"
        echo "       → sudo iptables -I FORWARD -i virbr0 -j ACCEPT"
        exit 1
    fi
    echo "  ✓ Ollama accessible"

    # -------------------------------------------------------------------------
    # 2. Lister les modèles disponibles et afficher le menu
    # -------------------------------------------------------------------------
    mapfile -t MODELS < <(python3 - <<'PYEOF'
import json, sys
try:
    with open('/tmp/ollama_models.json') as f:
        data = json.load(f)
    for m in data.get('models', []):
        print(m['name'])
except Exception as e:
    sys.exit(1)
PYEOF
)

    if [ ${#MODELS[@]} -eq 0 ]; then
        echo ""
        echo "ERREUR : aucun modèle trouvé dans Ollama."
        echo "  Lance d'abord : docker exec ollama ollama pull <modele>"
        echo "  Exemple       : docker exec ollama ollama pull qwen2.5-coder:14b"
        exit 1
    fi

    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│   Modèles disponibles dans Ollama        │"
    echo "├─────────────────────────────────────────┤"
    for i in "${!MODELS[@]}"; do
        printf "│  %2d. %-36s│\n" "$((i+1))" "${MODELS[$i]}"
    done
    echo "└─────────────────────────────────────────┘"
    echo ""

    SELECTED_MODEL=""
    while true; do
        read -rp "Choisir le modèle par défaut [1-${#MODELS[@]}] : " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] \
            && [ "$choice" -ge 1 ] \
            && [ "$choice" -le "${#MODELS[@]}" ]; then
            SELECTED_MODEL="${MODELS[$((choice-1))]}"
            break
        fi
        echo "  → Saisie invalide. Entre un numéro entre 1 et ${#MODELS[@]}."
    done

    echo ""
    echo "  ✓ Modèle sélectionné : ${SELECTED_MODEL}"

    # Persister le modèle choisi (lu par ai.lua au démarrage de nvim)
    echo "${SELECTED_MODEL}" > "${DIR_VIM_GIT}/.ai-model"

    # -------------------------------------------------------------------------
    # 3. Node.js (requis par opencode)
    # -------------------------------------------------------------------------
    if ! command -v node &>/dev/null; then
        echo ""
        echo "→ Installation de Node.js..."
        sudo apt-get install -y nodejs npm
    else
        echo "  ✓ Node.js $(node --version) déjà installé"
    fi

    # -------------------------------------------------------------------------
    # 4. OpenCode CLI
    # npm install -g échoue sans sudo si le prefix est /usr/local.
    # Solution : rediriger le prefix global npm vers ~/.npm-global (sans sudo).
    # -------------------------------------------------------------------------
    echo ""
    echo "→ Configuration du prefix npm (sans sudo)..."
    NPM_PREFIX="$HOME/.npm-global"
    mkdir -p "$NPM_PREFIX"
    npm config set prefix "$NPM_PREFIX"

    # Ajouter ~/.npm-global/bin au PATH si pas déjà présent
    PROFILE_LINE='export PATH="$HOME/.npm-global/bin:$PATH"'
    for rc in "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$rc" ] && ! grep -q '.npm-global/bin' "$rc"; then
            echo "" >> "$rc"
            echo "# npm global prefix (sans sudo)" >> "$rc"
            echo "$PROFILE_LINE" >> "$rc"
        fi
    done
    export PATH="$NPM_PREFIX/bin:$PATH"

    echo "→ Installation d'OpenCode..."
    npm install -g opencode-ai@latest
    echo "  ✓ OpenCode $(opencode --version 2>/dev/null || echo 'installé')"

    # Config OpenCode : provider ollama → hôte KVM
    mkdir -p "$HOME/.config/opencode"
    cat > "$HOME/.config/opencode/opencode.json" << JSONEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (hôte KVM)",
      "options": {
        "baseURL": "${OLLAMA_BASE_URL}/v1"
      },
      "models": {
        "${SELECTED_MODEL}": {
          "name": "${SELECTED_MODEL}",
          "tools": true
        }
      }
    }
  }
}
JSONEOF

    # auth.json : ollama n'a pas de clé, mais opencode exige l'entrée
    mkdir -p "$HOME/.local/share/opencode"
    if [ ! -f "$HOME/.local/share/opencode/auth.json" ]; then
        cat > "$HOME/.local/share/opencode/auth.json" << JSONEOF
{
  "ollama": {
    "type": "api",
    "key": "ollama"
  }
}
JSONEOF
    fi
    echo "  ✓ Config OpenCode écrite dans ~/.config/opencode/opencode.json"

    # -------------------------------------------------------------------------
    # 5. Plugins Neovim (CodeCompanion + opencode.nvim via ai.lua)
    # -------------------------------------------------------------------------
    touch "${DIR_VIM_GIT}/.ai-enabled"

    echo ""
    echo "→ Installation des plugins Neovim IA..."
    nvim --headless "+Lazy! sync" +qa
    echo "  ✓ Plugins IA installés"

    # -------------------------------------------------------------------------
    # Résumé
    # -------------------------------------------------------------------------
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║              Outils IA activés                   ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Modèle   : ${SELECTED_MODEL}"
    printf "║  %-49s║\n" "Ollama     : ${OLLAMA_BASE_URL}"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  CodeCompanion (dans Neovim) :                   ║"
    echo "║    <Space>ac  — chat IA                          ║"
    echo "║    <Space>aa  — actions IA                       ║"
    echo "║    <Space>ae  — édition inline (mode visuel)     ║"
    echo "║    <Space>am  — afficher le modèle actif         ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  OpenCode (dans Neovim) :                        ║"
    echo "║    <Space>oc  — toggle panneau OpenCode          ║"
    echo "║    <Space>os  — envoyer la sélection             ║"
    echo "║    <Space>on  — nouvelle session                 ║"
    echo "║  OpenCode (terminal) : opencode                  ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Changer de modèle : ./install.sh ia             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

fi

# =============================================================================
# RAG (optionnel : ./install.sh rag)
# Indexe une codebase via Ollama (mxbai-embed-large) + vim-rag CLI
# Utilisé par rag.lua dans Neovim (<Space>aq / <Space>ar / <Space>aR)
# =============================================================================
if [ "${1:-}" = "rag" ]; then

    OLLAMA_HOST_IP="192.168.122.1"
    OLLAMA_PORT="11434"
    OLLAMA_BASE_URL="http://${OLLAMA_HOST_IP}:${OLLAMA_PORT}"

    echo ""
    echo "=== Activation du RAG (indexation de codebase) ==="
    echo "    Ollama : ${OLLAMA_BASE_URL}"

    # -------------------------------------------------------------------------
    # 1. Prérequis : Ollama accessible
    # -------------------------------------------------------------------------
    echo ""
    echo "→ Connexion à Ollama..."
    if ! curl -sf --max-time 5 "${OLLAMA_BASE_URL}/api/tags" > /tmp/rag_ollama_tags.json 2>/dev/null; then
        echo ""
        echo "ERREUR : impossible de joindre Ollama sur ${OLLAMA_BASE_URL}"
        echo "  Vérifie que le conteneur tourne et écoute sur 0.0.0.0:11434"
        exit 1
    fi
    echo "  ✓ Ollama accessible"

    # -------------------------------------------------------------------------
    # 2. Sélection du modèle d'embedding (filtrage heuristique sur les noms)
    # -------------------------------------------------------------------------
    mapfile -t EMBED_MODELS < <(python3 - <<'PYEOF'
import json, sys
try:
    with open('/tmp/rag_ollama_tags.json') as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

# Patterns de noms typiques des modèles d'embedding
PATTERNS = [
    'embed', 'bge-', 'bge_', 'bge:', 'nomic-', 'mxbai-',
    'snowflake-', 'arctic-embed', 'all-minilm', 'paraphrase',
    'e5-', 'e5_', 'jina-embed', 'gte-',
]
for m in data.get('models', []):
    name = m['name']
    low  = name.lower()
    if any(p in low for p in PATTERNS):
        print(name)
PYEOF
)

    if [ ${#EMBED_MODELS[@]} -eq 0 ]; then
        echo ""
        echo "ERREUR : aucun modèle d'embedding détecté dans Ollama."
        echo ""
        echo "  Pull un modèle d'embedding, par exemple :"
        echo "    docker exec ollama ollama pull mxbai-embed-large"
        echo "    docker exec ollama ollama pull nomic-embed-text"
        echo ""
        echo "  Puis relance : ./install.sh rag"
        exit 1
    fi

    echo ""
    if [ ${#EMBED_MODELS[@]} -eq 1 ]; then
        SELECTED_EMBED="${EMBED_MODELS[0]}"
        echo "  ✓ Un seul modèle d'embedding détecté : ${SELECTED_EMBED}"
    else
        echo "┌─────────────────────────────────────────┐"
        echo "│   Modèles d'embedding disponibles        │"
        echo "├─────────────────────────────────────────┤"
        for i in "${!EMBED_MODELS[@]}"; do
            printf "│  %2d. %-36s│\n" "$((i+1))" "${EMBED_MODELS[$i]}"
        done
        echo "└─────────────────────────────────────────┘"
        echo ""
        echo "  Recommandation : mxbai-embed-large (qualité) ou"
        echo "                   nomic-embed-text (léger, rapide)"
        echo ""

        # Pré-sélection : modèle actuel s'il existe, sinon 1
        DEFAULT_IDX=1
        if [ -f "${DIR_VIM_GIT}/.rag-embed-model" ]; then
            CURRENT=$(cat "${DIR_VIM_GIT}/.rag-embed-model")
            for i in "${!EMBED_MODELS[@]}"; do
                if [ "${EMBED_MODELS[$i]}" = "${CURRENT}" ]; then
                    DEFAULT_IDX=$((i+1))
                    break
                fi
            done
        fi

        SELECTED_EMBED=""
        while true; do
            read -rp "Choisir le modèle d'embedding [1-${#EMBED_MODELS[@]}, défaut ${DEFAULT_IDX}] : " choice
            choice="${choice:-${DEFAULT_IDX}}"
            if [[ "$choice" =~ ^[0-9]+$ ]] \
                && [ "$choice" -ge 1 ] \
                && [ "$choice" -le "${#EMBED_MODELS[@]}" ]; then
                SELECTED_EMBED="${EMBED_MODELS[$((choice-1))]}"
                break
            fi
            echo "  → Saisie invalide. Entre un numéro entre 1 et ${#EMBED_MODELS[@]}."
        done
    fi

    echo "  ✓ Embedding sélectionné : ${SELECTED_EMBED}"

    # Si le modèle a changé, avertir que l'index sera à refaire
    if [ -f "${DIR_VIM_GIT}/.rag-embed-model" ]; then
        PREV=$(cat "${DIR_VIM_GIT}/.rag-embed-model")
        if [ "${PREV}" != "${SELECTED_EMBED}" ]; then
            echo ""
            echo "  ⚠  Modèle d'embedding changé (${PREV} → ${SELECTED_EMBED})."
            echo "     Les projets déjà indexés devront être réindexés :"
            echo "       cd /chemin/du/projet && vim-rag index ."
        fi
    fi

    # Persister le choix (lu par rag.py)
    echo "${SELECTED_EMBED}" > "${DIR_VIM_GIT}/.rag-embed-model"

    # -------------------------------------------------------------------------
    # 3. Vérifier que le modèle de génération (partagé avec ia) est configuré
    # -------------------------------------------------------------------------
    if [ ! -f "${DIR_VIM_GIT}/.ai-model" ]; then
        echo ""
        echo "⚠  ~/.vim/.ai-model n'existe pas."
        echo "   Le RAG l'utilise pour générer les réponses (via rag.lua)."
        echo "   Lance d'abord : ./install.sh ia"
        echo ""
        read -rp "Continuer quand même ? [y/N] : " answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) exit 1 ;;
        esac
    else
        echo "  ✓ Modèle de génération : $(cat "${DIR_VIM_GIT}/.ai-model")"
    fi

    # -------------------------------------------------------------------------
    # 4. Installer la CLI vim-rag via pipx (éditable, pour suivre git pull)
    # -------------------------------------------------------------------------
    echo ""
    echo "→ Installation de vim-rag via pipx (mode éditable)..."
    if pipx list --short 2>/dev/null | grep -q '^vim-rag '; then
        # Déjà installé : on réinstalle pour prendre en compte requirements.txt
        pipx reinstall vim-rag
    else
        pipx install --editable "${DIR_VIM_GIT}/rag"
    fi
    pipx ensurepath > /dev/null
    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v vim-rag >/dev/null 2>&1; then
        echo ""
        echo "ERREUR : la commande 'vim-rag' n'est pas dans le PATH après pipx install."
        echo "  Ouvre un nouveau terminal ou relance : source ~/.bashrc"
        exit 1
    fi
    echo "  ✓ vim-rag : $(command -v vim-rag)"

    # -------------------------------------------------------------------------
    # 5. Flag d'activation + plugins Neovim (rag.lua ne requiert rien de lazy,
    #    mais on lance Lazy! sync au cas où ai.lua ait changé)
    # -------------------------------------------------------------------------
    touch "${DIR_VIM_GIT}/.rag-enabled"

    echo ""
    echo "→ Rechargement des plugins Neovim..."
    nvim --headless "+Lazy! sync" +qa
    echo "  ✓ Plugins rechargés"

    # -------------------------------------------------------------------------
    # Résumé
    # -------------------------------------------------------------------------
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                RAG activé                        ║"
    echo "╠══════════════════════════════════════════════════╣"
    printf "║  Embed   : %-38s║\n" "${SELECTED_EMBED}"
    printf "║  Ollama  : %-38s║\n" "${OLLAMA_BASE_URL}"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Dans Neovim :                                   ║"
    echo "║    <Space>aq  — pose une question sur le projet  ║"
    echo "║    <Space>ar  — question sur le buffer + contexte║"
    echo "║    <Space>aR  — réindexer le projet              ║"
    echo "║    :VimRagIndex [path]   — indexer               ║"
    echo "║    :VimRagStatus         — état de l'index       ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Dans un terminal :                              ║"
    echo "║    vim-rag index <path>                          ║"
    echo "║    vim-rag query \"question\" --project <path>     ║"
    echo "║    vim-rag list                                  ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Premier pas :                                   ║"
    echo "║    cd /chemin/vers/ton/projet                    ║"
    echo "║    vim-rag index .                               ║"
    echo "║    puis <Space>aq dans Neovim                    ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Changer d'embedding : ./install.sh rag          ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

fi

# =============================================================================
# CLUSTER OAR (optionnel : ./install.sh cluster_oar)
# Configure le mode Abaca/Grid5000 dans Neovim
# =============================================================================
if [ "${1:-}" = "cluster_oar" ]; then

    echo "=== Configuration Cluster OAR (Abaca) ==="

    # 1. Fichier de config
    CONF="${DIR_VIM_GIT}/.cluster_oar.conf"
    EXAMPLE="${DIR_VIM_GIT}/.cluster_oar.conf.example"
    if [ ! -f "$CONF" ]; then
        cp "$EXAMPLE" "$CONF"
        echo ""
        echo "⚠  Fichier de config créé : $CONF"
        echo "   Éditez-le avant de continuer :"
        echo "     $EDITOR $CONF"
        echo ""
        read -r -p "Appuyez sur Entrée une fois la config éditée…"
    fi

    # 2. Vérifier que le login est renseigné
    G5K_LOGIN=$(grep '^G5K_LOGIN' "$CONF" | cut -d= -f2 | tr -d '"' | tr -d "'")
    if [ -z "$G5K_LOGIN" ] || [ "$G5K_LOGIN" = "votre_login" ]; then
        echo "ERREUR : G5K_LOGIN non configuré dans $CONF"
        exit 1
    fi
    echo "  ✓ Login Grid5000 : $G5K_LOGIN"

    # 3. Tester la connexion SSH au gateway
    echo "  Test de connexion à access.grid5000.fr…"
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -o BatchMode=yes \
            "$G5K_LOGIN@access.grid5000.fr" "echo ok" 2>/dev/null | grep -q ok; then
        echo "  ⚠  Connexion SSH échouée."
        echo "     Vérifiez que votre clé SSH est déposée sur Grid5000 :"
        echo "     https://www.grid5000.fr/w/Grid5000:Connect"
    else
        echo "  ✓ Connexion SSH Grid5000 OK"
    fi

    # 4. Rendre le script nœud exécutable
    chmod +x "${DIR_VIM_GIT}/cluster_oar_node.sh"
    echo "  ✓ cluster_oar_node.sh prêt"

    # 5. Flag d'activation
    touch "${DIR_VIM_GIT}/.cluster-oar-enabled"

    # 6. Reload Neovim plugins
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || true

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║            Mode Cluster OAR activé               ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Dans Neovim :                                   ║"
    echo "║    <leader>aC   — démarrer / arrêter le cluster  ║"
    echo "║    <leader>aS   — statut                         ║"
    echo "║    :ClusterStart / :ClusterStop / :ClusterStatus ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Les keymaps RAG existants (<leader>aq/ar/aR)    ║"
    echo "║  démarrent le cluster automatiquement si besoin. ║"
    echo "╚══════════════════════════════════════════════════╝"
fi

# =============================================================================
# GITLAB (optionnel : ./install.sh gitlab)
# Configure le workflow IA autour des issues GitLab (gitlab.lua)
#
# Pré-requis : .ai-enabled (cible 'ia' lancée d'abord)
# Détecte automatiquement si .cluster-oar-enabled est posé pour proposer
# le mode cluster ou local.
# =============================================================================
if [ "${1:-}" = "gitlab" ]; then

    echo ""
    echo "=== Configuration du workflow IA pour les issues GitLab ==="

    # -------------------------------------------------------------------------
    # 1. Pré-requis : la cible 'ia' doit avoir été lancée
    # -------------------------------------------------------------------------
    if [ ! -f "${DIR_VIM_GIT}/.ai-enabled" ]; then
        echo ""
        echo "ERREUR : la cible 'ia' doit être lancée d'abord."
        echo "  ./install.sh ia"
        echo ""
        echo "  La cible 'gitlab' s'appuie sur CodeCompanion configuré par 'ia'."
        exit 1
    fi
    echo "  ✓ Pré-requis 'ia' OK"

    # -------------------------------------------------------------------------
    # 2. Choix du mode (cluster / local)
    # -------------------------------------------------------------------------
    MODE=""
    if [ -f "${DIR_VIM_GIT}/.cluster-oar-enabled" ]; then
        echo ""
        echo "Mode cluster OAR détecté (.cluster-oar-enabled présent)."
        echo ""
        echo "  [c] cluster : utilise le modèle fixé par cluster_oar_node.sh"
        echo "                (recommandé si tu utilises systématiquement le cluster)"
        echo "  [l] local   : choisir parmi les modèles présents sur Ollama hôte KVM"
        echo "                (192.168.122.1:11434)"
        echo ""
        while true; do
            read -rp "Mode [c/l] (défaut: c) : " mode_choice
            mode_choice="${mode_choice:-c}"
            case "$mode_choice" in
                c|C) MODE="cluster"; break ;;
                l|L) MODE="local";   break ;;
                *) echo "  → Réponse invalide. Tape 'c' ou 'l'." ;;
            esac
        done
    else
        MODE="local"
    fi
    echo ""
    echo "→ Mode sélectionné : ${MODE}"

    # -------------------------------------------------------------------------
    # 3. Configuration des modèles
    # -------------------------------------------------------------------------
    if [ "$MODE" = "cluster" ]; then
        # ---------- Mode cluster : modèle fixé par cluster_oar_node.sh -----
        # On extrait CHAT_MODEL depuis le script de nœud (single source of truth)
        CLUSTER_MODEL=$(grep '^CHAT_MODEL=' "${DIR_VIM_GIT}/cluster_oar_node.sh" \
                         | head -1 | cut -d'"' -f2)
        if [ -z "$CLUSTER_MODEL" ]; then
            echo "ERREUR : impossible de lire CHAT_MODEL depuis cluster_oar_node.sh"
            exit 1
        fi

        echo ""
        echo "  Modèle cluster (depuis cluster_oar_node.sh) : ${CLUSTER_MODEL}"
        echo "  → utilisé pour TOUS les rôles (coder + chat) — cf. choix A(a)"
        echo "${CLUSTER_MODEL}" > "${DIR_VIM_GIT}/.ai-model"

        # Pas de .ai-model-chat → ai.lua fera le fallback sur .ai-model
        rm -f "${DIR_VIM_GIT}/.ai-model-chat"
        echo "  ✓ .ai-model       = ${CLUSTER_MODEL}"
        echo "  ✓ .ai-model-chat  (absent → fallback sur .ai-model)"

        echo ""
        echo "  ℹ Le pull du modèle se fait au démarrage du nœud OAR"
        echo "    (cluster_oar_node.sh, déclenché par <leader>aC dans nvim)"

        SELECTED_CODER="$CLUSTER_MODEL"
        SELECTED_CHAT="$CLUSTER_MODEL"

    else
        # ---------- Mode local : 2 menus interactifs -----------------------
        OLLAMA_HOST="192.168.122.1"
        OLLAMA_PORT="11434"
        OLLAMA_BASE_URL="http://${OLLAMA_HOST}:${OLLAMA_PORT}"

        echo ""
        echo "→ Connexion à Ollama (${OLLAMA_BASE_URL})..."
        if ! curl -sf --max-time 5 "${OLLAMA_BASE_URL}/api/tags" \
                > /tmp/ollama_models.json 2>/dev/null; then
            echo ""
            echo "ERREUR : impossible de joindre Ollama sur ${OLLAMA_BASE_URL}"
            echo "  Lance ./install.sh ia d'abord (qui vérifie tout le setup Ollama)."
            exit 1
        fi
        echo "  ✓ Ollama accessible"

        # Lister les modèles disponibles
        mapfile -t MODELS < <(python3 - <<'PYEOF'
import json, sys
try:
    with open('/tmp/ollama_models.json') as f:
        data = json.load(f)
    for m in data.get('models', []):
        print(m['name'])
except Exception:
    sys.exit(1)
PYEOF
)

        if [ ${#MODELS[@]} -eq 0 ]; then
            echo ""
            echo "ERREUR : aucun modèle dans Ollama."
            echo "  docker exec ollama ollama pull qwen2.5-coder:14b"
            exit 1
        fi

        # Helper : affiche le menu, lit un choix valide entre 1 et N (et
        # éventuellement 0 si allow_zero=1) ; renvoie le résultat dans la
        # variable globale __MENU_RESULT (entier choisi).
        show_menu_and_pick() {
            local title="$1"; shift
            local allow_zero="$1"; shift
            local options=("$@")
            local n=${#options[@]}

            echo ""
            echo "┌─────────────────────────────────────────┐"
            printf "│  %-39s│\n" "${title}"
            echo "├─────────────────────────────────────────┤"
            if [ "$allow_zero" = "1" ]; then
                printf "│   0. %-35s│\n" "(identique au coder)"
            fi
            local i
            for i in "${!options[@]}"; do
                printf "│  %2d. %-35s│\n" "$((i+1))" "${options[$i]}"
            done
            echo "└─────────────────────────────────────────┘"
            echo ""

            local min=1
            [ "$allow_zero" = "1" ] && min=0

            while true; do
                read -rp "Choix [${min}-${n}] : " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] \
                    && [ "$choice" -ge "$min" ] \
                    && [ "$choice" -le "$n" ]; then
                    __MENU_RESULT="$choice"
                    return 0
                fi
                echo "  → Saisie invalide. Entre un numéro entre ${min} et ${n}."
            done
        }

        # ---- Menu 1 : modèle CODER ------------------------------------
        show_menu_and_pick "Modèle CODER (commit / inline / agent)" 0 "${MODELS[@]}"
        SELECTED_CODER="${MODELS[$((__MENU_RESULT-1))]}"

        # ---- Menu 2 : modèle CHAT (option 0 = identique au coder) -----
        show_menu_and_pick "Modèle CHAT (clarification / dialogue)" 1 "${MODELS[@]}"
        if [ "$__MENU_RESULT" = "0" ]; then
            SELECTED_CHAT="$SELECTED_CODER"
            CHAT_FALLBACK=1
        else
            SELECTED_CHAT="${MODELS[$((__MENU_RESULT-1))]}"
            CHAT_FALLBACK=0
        fi

        # ---- Persistance ------------------------------------------------
        echo "${SELECTED_CODER}" > "${DIR_VIM_GIT}/.ai-model"
        if [ "$CHAT_FALLBACK" = "1" ]; then
            # Identique au coder → pas de .ai-model-chat (fallback transparent)
            rm -f "${DIR_VIM_GIT}/.ai-model-chat"
        else
            echo "${SELECTED_CHAT}" > "${DIR_VIM_GIT}/.ai-model-chat"
        fi

        echo ""
        echo "  ✓ .ai-model       = ${SELECTED_CODER}"
        if [ "$CHAT_FALLBACK" = "1" ]; then
            echo "  ✓ .ai-model-chat  (absent → fallback sur .ai-model)"
        else
            echo "  ✓ .ai-model-chat  = ${SELECTED_CHAT}"
        fi
    fi

    # -------------------------------------------------------------------------
    # 4. Flag d'activation
    # -------------------------------------------------------------------------
    touch "${DIR_VIM_GIT}/.gitlab-enabled"
    echo ""
    echo "  ✓ .gitlab-enabled posé"

    # -------------------------------------------------------------------------
    # 5. Reload Neovim plugins (par cohérence avec les autres cibles)
    # -------------------------------------------------------------------------
    echo ""
    echo "→ Mise à jour des plugins Neovim..."
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
    echo "  ✓ Plugins synchronisés"

    # -------------------------------------------------------------------------
    # 6. Aide à la configuration du token GitLab (informationnel uniquement)
    # -------------------------------------------------------------------------
    echo ""
    echo "→ Authentification GitLab :"
    if [ -n "${GITLAB_TOKEN:-}" ]; then
        echo "  ✓ Variable GITLAB_TOKEN détectée dans l'environnement"
    else
        echo "  ⚠ Aucun GITLAB_TOKEN dans l'environnement."
        echo ""
        echo "  Deux options pour authentifier :"
        echo ""
        echo "    1) Variable d'env globale (~/.bashrc) :"
        echo "         export GITLAB_TOKEN=\"glpat-xxxxxxxxxxxx\""
        echo "         export GITLAB_URL=\"https://gitlab.example.com\"  # si self-hosted"
        echo ""
        echo "    2) Fichier .gitlab.nvim à la racine du projet"
        echo "       (à AJOUTER DANS .gitignore !) :"
        echo "         token=glpat-xxxxxxxxxxxx"
        echo "         gitlab_url=https://gitlab.example.com"
        echo ""
        echo "  Crée un Personal Access Token sur :"
        echo "    <ton-instance>/-/user_settings/personal_access_tokens"
        echo "  Scopes requis : api (lecture+écriture issues)"
    fi

    # -------------------------------------------------------------------------
    # Résumé
    # -------------------------------------------------------------------------
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║       Workflow GitLab Issues activé              ║"
    echo "╠══════════════════════════════════════════════════╣"
    printf "║  %-49s║\n" "Mode      : ${MODE}"
    printf "║  %-49s║\n" "Coder     : ${SELECTED_CODER}"
    if [ "${CHAT_FALLBACK:-1}" = "1" ]; then
        printf "║  %-49s║\n" "Chat      : (= coder)"
    else
        printf "║  %-49s║\n" "Chat      : ${SELECTED_CHAT}"
    fi
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Dans Neovim :                                   ║"
    echo "║    <Space>gi  — choisir une issue                ║"
    echo "║    <Space>gw  — démarrer le workflow IA          ║"
    echo "║    <Space>gC  — effacer l'issue courante         ║"
    echo "║    <Space>ag  — générer le commit (Fix #N: …)    ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Reconfigurer : ./install.sh gitlab              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

fi
