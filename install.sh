#!/bin/bash

DIR_VIM_GIT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installing ${HOME}/.vimrc"

ln -s "${DIR_VIM_GIT}/vimrc" "${HOME}"/.vimrc 
