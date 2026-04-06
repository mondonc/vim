#!/bin/bash
set -euo pipefail

DIR_VIM_GIT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Vérification qu'on est bien dans ~/.vim
if [ "$(realpath "$DIR_VIM_GIT")" != "$(realpath "$HOME/.vim")" ]; then
    echo "ERREUR : ce dépôt doit être cloné dans ~/.vim"
    echo "  Emplacement actuel : $DIR_VIM_GIT"
    echo "  Attendu :            $HOME/.vim"
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

# --- IA (optionnel : ./install.sh ia) ---
if [ "${1:-}" = "ia" ]; then
    echo ""
    echo "=== Activation de l'IA (CodeCompanion) ==="
    touch "$DIR_VIM_GIT/.ai-enabled"

    # Config API key
    mkdir -p "$HOME/.config/codecompanion"
    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -f "$HOME/.config/codecompanion/anthropic_key" ]; then
        echo ""
        echo "Clé API Anthropic non trouvée."
        echo "Tu peux soit :"
        echo "  1. Exporter ANTHROPIC_API_KEY dans ~/.bashrc"
        echo "  2. La saisir maintenant (sera stockée dans ~/.config/codecompanion/anthropic_key)"
        echo ""
        read -rp "Coller ta clé API (ou Enter pour passer) : " api_key
        if [ -n "$api_key" ]; then
            echo "$api_key" > "$HOME/.config/codecompanion/anthropic_key"
            chmod 600 "$HOME/.config/codecompanion/anthropic_key"
            echo "Clé sauvegardée dans ~/.config/codecompanion/anthropic_key"
        else
            echo "Pas de clé configurée. Pense à exporter ANTHROPIC_API_KEY."
        fi
    else
        echo "Clé API déjà configurée."
    fi

    # Réinstaller les plugins nvim avec CodeCompanion
    echo "=== Installation des plugins IA (lazy.nvim) ==="
    nvim --headless "+Lazy! sync" +qa

    echo ""
    echo "=== IA activée ==="
    echo "  Space ac  — ouvrir/fermer le chat IA"
    echo "  Space aa  — actions IA"
    echo "  Space ae  — édition inline (en mode visuel)"
    echo ""
    echo "  Pour utiliser Ollama local : modifier 'adapter' dans ai.lua"
    echo "  Pour désactiver : supprimer ~/.vim/.ai-enabled et relancer nvim"
fi
