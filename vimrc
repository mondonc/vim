" =============================================================================
" vimrc — Config Vim 8+ (vim-plug)
" =============================================================================
set nocompatible
filetype off

" --- Source des options partagées ---
let s:vimdir = fnamemodify(resolve(expand('<sfile>:p')), ':h')
execute 'source ' . s:vimdir . '/common.vim'

" --- vim-plug ---
call plug#begin('~/.vim/bundle')

Plug 'tpope/vim-fugitive'
Plug 'scrooloose/nerdtree'
Plug 'cschlueter/vim-mustang'
Plug 'ghifarit53/tokyonight-vim'
Plug 'majutsushi/tagbar'
Plug 'vim-syntastic/syntastic'
Plug 'airblade/vim-gitgutter'

call plug#end()
filetype plugin indent on

" --- colorscheme ---
set termguicolors
let g:tokyonight_style = 'night'
colorscheme tokyonight
highlight Normal ctermbg=NONE guibg=NONE
highlight nonText ctermbg=NONE guibg=NONE

" --- Toggle dark/light pour extérieur (Space+hc) ---
function! ToggleHighContrast()
  if &background ==# 'dark'
    set background=light
    let g:tokyonight_style = 'day'
    echo "Mode clair (extérieur)"
  else
    set background=dark
    let g:tokyonight_style = 'night'
    echo "Mode sombre"
  endif
  colorscheme tokyonight
  highlight Normal ctermbg=NONE guibg=NONE
  highlight nonText ctermbg=NONE guibg=NONE
endfunction
nnoremap <leader>hc :call ToggleHighContrast()<CR>

" --- NERDTree ---
map <C-x> :NERDTreeToggle<CR>
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
let NERDTreeMapOpenInTab='<CR>'

" --- syntastic (Python) ---
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_python_checkers = ['pyflakes', 'flake8', 'vulture']
let g:syntastic_python_checker_args='--ignore=E501,E402'
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_loc_list_height = 3
let g:syntastic_python_flake8_args='--ignore=E501'
let g:syntastic_python_pyflakes_args='--ignore=E501'
let g:flake8_max_line_length=160
