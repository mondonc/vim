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
