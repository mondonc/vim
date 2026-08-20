" =============================================================================
" ginit.vim — Config spécifique nvim-qt (chargée par `runtime! ginit.vim`,
" APRÈS init.lua). Rien ici n'affecte nvim en terminal.
"
" Copier/coller à la souris : avec `set mouse=a`, la souris est capturée par
" nvim (sélection visuelle) — Qt ne voit donc JAMAIS de sélection native, et
" les raccourcis du cadre (Ctrl+Shift+C/V côté Qt) ne font rien. On route le
" clipboard par le GUI (GuiClipboard → registres + et * vers le presse-papiers
" Qt) et on mappe Ctrl+Shift+C / Ctrl+Shift+V dans nvim, comme en terminal.
" =============================================================================

" Route les registres + et * vers le presse-papiers Qt de nvim-qt
" (nécessaire : le menu contextuel et les mappings ci-dessous passent par "+)
if exists('*GuiClipboard')
    call GuiClipboard()
endif

" Yank/paste du registre sans nom → presse-papiers système (ici uniquement)
set clipboard=unnamedplus

" --- Copier la sélection (souris = mode visuel) : Ctrl+Shift+C ---
xnoremap <C-S-c> "+y
snoremap <C-S-c> "+y

" --- Coller depuis le presse-papiers : Ctrl+Shift+V ---
nnoremap <C-S-v> "+p
inoremap <C-S-v> <C-r>+
cnoremap <C-S-v> <C-r>+
xnoremap <C-S-v> "+P

" --- Menu contextuel au clic droit (Copier / Couper / Coller / Tout sélect.) ---
nnoremap <silent><RightMouse> :call GuiShowContextMenu()<CR>
inoremap <silent><RightMouse> <Esc>:call GuiShowContextMenu()<CR>
xnoremap <silent><RightMouse> :call GuiShowContextMenu()<CR>gv
snoremap <silent><RightMouse> <C-G>:call GuiShowContextMenu()<CR>gv
