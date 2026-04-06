" =============================================================================
" common.vim — Options partagées Vim 8+ / Neovim
" Sourcé par vimrc ET init.lua
" =============================================================================

syntax enable
let mapleader = " "
set number
set ts=4
set autoindent
set expandtab
set shiftwidth=4
set history=1000
set wildignore=*.swp,*.bak,*.pyc,*.class
set autowrite
set showmatch
set ai
set si
set so=7
set ruler
set hid
set nohidden
set mouse=a
set backspace=eol,start,indent
set whichwrap+=<,>,h,l

set nolazyredraw
set magic

set noerrorbells
set novisualbell
set tm=500

set nobackup
set nowb
set noswapfile

if has("nvim")
  set undodir=~/.vim/undodir-nvim
else
  set undodir=~/.vim/undodir-vim
endif
set undofile
set undolevels=1000
set undoreload=10000
set title

set wildmode=list:longest,full

set nowrap
if has("gui_running") && !has("nvim")
  set guioptions+=b
endif

" --- search ---
set incsearch
set hlsearch
set ignorecase
set smartcase

hi Search guifg=#ffffff guibg=#0000ff gui=none ctermfg=white ctermbg=darkblue
hi IncSearch guifg=#ffffff guibg=#8888ff gui=none ctermfg=white
highlight SpellBad guifg=#ffffff guibg=#8888ff gui=none ctermfg=black ctermbg=darkred

set enc=utf-8
set laststatus=2
set scrolloff=3
set shiftround
set showcmd
if !has("nvim")
  set t_RV=
  set t_u7=
  set t_RF=
  set t_RB=
endif

let python_highlight_all = 1

set background=dark

set statusline=%<%m\ %f\ %y\ %{&ff}\ \%=\ row:%l\ of\ %L\ col:%c%V\ %P

" --- keymaps ---
map <leader>bd :Bclose<cr>

" --- autoread ---
set autoread
autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * if mode() != 'c' | checktime | endif
autocmd FileChangedShellPost *
  \ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None

" --- restore cursor position ---
if has("autocmd")
  au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$")
    \| exe "normal! g'\"" | endif
endif

" --- GUI font size (neovim-qt / gvim) ---
let s:fontsize = 11
function! AdjustFontSize(amount)
  let s:fontsize = s:fontsize+a:amount
  :execute "GuiFont! DejaVu Sans Mono:h" . s:fontsize
endfunction

noremap <C-Up> :call AdjustFontSize(1)<CR>
noremap <C-Down> :call AdjustFontSize(-1)<CR>
inoremap <C-Up> <Esc>:call AdjustFontSize(1)<CR>a
inoremap <C-Down> <Esc>:call AdjustFontSize(-1)<CR>a
