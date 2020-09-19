#!/bin/bash

DIR_VIM_GIT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installing Vundle"
mkdir -p "${HOME}/.vim/bundle"
[ -d ~/.vim/bundle/Vundle.vim ] || git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim

echo "Installing ${HOME}/.vimrc"
[ -e ${HOME}/.vimrc ] && rm ${HOME}/.vimrc
ln -s "${DIR_VIM_GIT}/vimrc" "${HOME}"/.vimrc 

vim +PluginInstall +qall

sudo apt-get -y install pyflakes flake8 python-flake8 vulture

# Neovim compatibility
if ![ -d .config/nvim ] ; then
    cp -r $HOME/.vim $HOME/.config/nvim
    cp -r $HOME/.vimrc $HOME/.config/nvim/init.vim
fi
