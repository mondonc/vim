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
