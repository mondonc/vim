set nocompatible              " be iMproved, required
filetype off                  " required

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'VundleVim/Vundle.vim' " let Vundle manage Vundle, required
Bundle 'tpope/vim-fugitive'
Bundle 'scrooloose/nerdtree'
"Bundle 'jistr/vim-nerdtree-tabs'
Bundle 'cschlueter/vim-mustang'
Bundle 'majutsushi/tagbar'
"Bundle 'scrooloose/syntastic'
Bundle 'vim-syntastic/syntastic'
Bundle 'airblade/vim-gitgutter'
Bundle "Shougo/neocomplcache"
"Bundle 'nvie/vim-flake8'
"Bundle 'vim-scripts/pep8'
Bundle 'vim-scripts/Pydiction'
Bundle "vim-scripts/indentpython.vim"
call vundle#end()            " required
filetype plugin indent on    " required

"source ~/.vimrc_nerdtree

syntax enable " enable syntax highlighting
set number " show line numbers
set ts=4 " set tabs to have 4 spaces
set autoindent " indent when moving to the next line while writing code
set expandtab " expand tabs into spaces
set shiftwidth=4 " when using the >> or << commands, shift lines by 4 spaces
set history=1000 " Sets how many lines of history VIM has to remember
set wildignore=*.swp,*.bak,*.pyc,*.class " Ignore some file
set autowrite " Set to auto read when a file is changed from the outside
set showmatch " show the matching part of the pair for [] {} and ()
set ai "Auto indent
set si "Smart indet
set so=7            " Set 7 lines to the curors - when moving vertical..
set ruler           "Always show current position
set hid             "Change buffer - without saving
set nohidden
set mouse=a
" Set backspace config
set backspace=eol,start,indent
set whichwrap+=<,>,h,l

set nolazyredraw "Don't redraw while executing macros 
set magic "Set magic on, for regular expressions

set showmatch "Show matching bracets when text indicator is over them

" No sound on errors
set noerrorbells
set novisualbell
set tm=500

set nobackup
set nowb
set noswapfile

set undodir=~/.vim/undodir
set undofile
set undolevels=1000 "maximum number of changes that can be undone
set undoreload=10000 "maximum number lines to save for undo on a buffer reload
set title                     " show title in console title bar

map <leader>bd :Bclose<cr>

set wildmode=list:longest,full

set nowrap          " no line wrapping;
set guioptions+=b   " add a horizontal scrollbar to the bottom

"--- search options ------------
set incsearch       " show 'best match so far' as you type
set hlsearch        " hilight the items found by the search
set ignorecase      " ignores case of letters on searches
set smartcase       " Override the 'ignorecase' option if the search pattern contains upper case characters

" Search and error color highlights
hi Search guifg=#ffffff guibg=#0000ff gui=none ctermfg=white ctermbg=darkblue
hi IncSearch guifg=#ffffff guibg=#8888ff gui=none ctermfg=white
highlight SpellBad guifg=#ffffff guibg=#8888ff gui=none ctermfg=black ctermbg=darkred

" Use UTF-8 as the default buffer encoding
set enc=utf-8

" Always show status line, even for one window
set laststatus=2

" Scroll when cursor gets within 3 characters of top/bottom edge
set scrolloff=3

" Round indent to multiple of 'shiftwidth' for > and < commands
set shiftround

" Show (partial) commands (or size of selection in Visual mode) in the status line
set showcmd

" Don't request terminal version string (for xterm)
set t_RV=


" enable all Python syntax highlighting features
let python_highlight_all = 1

"set guioptions-=T
set background=dark
let g:CSApprox_attr_map = { 'bold' : 'bold', 'italic' : '', 'sp' : '' }
colorscheme mustang
highlight Normal ctermbg=NONE
highlight nonText ctermbg=NONE

set statusline=%<%m\ %f\ %y\ %{&ff}\ \%=\ row:%l\ of\ %L\ col:%c%V\ %P
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*


let g:syntastic_python_checkers = ['pyflakes', 'flake8', 'vulture', 'pep8']
"let g:syntastic_python_checkers = ['pylint']
"let g:syntastic_python_checkers = ['pep8']
"let g:syntastic_python_checkers = ['vulture']
let g:syntastic_python_checker_args='--ignore=E501,E402'
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_loc_list_height = 3
let g:syntastic_python_flake8_args='--ignore=E501'
let g:syntastic_python_pep8_args='--ignore=E501'
let g:syntastic_python_pyflakes_args='--ignore=E501'
let g:syntastic_python_pylint_args='--rcfile=remidsi/pylintrc'
let g:flake8_max_line_length=160



filetype plugin on
let g:pydiction_location = '/home/mondonna/.vim/bundle/Pydiction/complete-dict'

if has("autocmd")
  au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$")
    \| exe "normal! g'\"" | endif
endif

" autocmd vimenter * NERDTree
map <C-x> :NERDTreeToggle<CR>
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

let s:fontsize = 11
function! AdjustFontSize(amount)
  let s:fontsize = s:fontsize+a:amount
  :execute "GuiFont! DejaVu Sans Mono:h" . s:fontsize
endfunction

noremap <C-Up> :call AdjustFontSize(1)<CR>
noremap <C-Down> :call AdjustFontSize(-1)<CR>
inoremap <C-Up> <Esc>:call AdjustFontSize(1)<CR>a
inoremap <C-Down> <Esc>:call AdjustFontSize(-1)<CR>a

" trigger `autoread` when files changes on disk
set autoread
autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * if mode() != 'c' | checktime | endif
" notification after file change
autocmd FileChangedShellPost *
\ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None
