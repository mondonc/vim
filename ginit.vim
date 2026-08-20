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

" --- Runtime nvim-qt (commandes Gui*) ---
" lazy.nvim retire le runtime nvim-qt du &rtp pendant init.lua, et nvim-qt ne
" le re-ajoute qu'à l'attache d'un nvim QU'IL A LUI-MÊME lancé (connexion à un
" serveur existant : pas de re-ajout). On s'en charge nous-mêmes si le shim
" (nvim_gui_shim.vim : GuiClipboard, GuiShowContextMenu…) n'est pas déjà là.
if !exists('g:GuiLoaded')
    let s:rt = getenv('NVIM_QT_RUNTIME_PATH')
    " Chemins standard de l'installation Debian/Ubuntu (si aucune var d'env)
    if empty(s:rt)
        for s:p in ['/usr/share/nvim-qt/runtime', '/usr/local/share/nvim-qt/runtime']
            if filereadable(s:p . '/plugin/nvim_gui_shim.vim')
                let s:rt = s:p
                break
            endif
        endfor
    endif
    " Repli : runtime relatif au binaire nvim-qt (même logique que nvim-qt)
    if empty(s:rt) && executable('nvim-qt')
        let s:bin = fnamemodify(exepath('nvim-qt'), ':h')
        for s:rel in ['../share/nvim-qt/runtime', '../Resources/runtime']
            let s:p = simplify(s:bin . '/' . s:rel)
            if filereadable(s:p . '/plugin/nvim_gui_shim.vim')
                let s:rt = s:p
                break
            endif
        endfor
    endif
    if !empty(s:rt) && filereadable(s:rt . '/plugin/nvim_gui_shim.vim')
        exec 'set rtp+=' . fnameescape(s:rt)
        runtime plugin/nvim_gui_shim.vim
    endif
    unlet! s:rt s:p s:rel s:bin
endif

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
" Uniquement si le shim a pu être chargé (sinon GuiShowContextMenu est inconnu)
if exists('*GuiShowContextMenu')
    nnoremap <silent><RightMouse> :call GuiShowContextMenu()<CR>
    inoremap <silent><RightMouse> <Esc>:call GuiShowContextMenu()<CR>
    xnoremap <silent><RightMouse> :call GuiShowContextMenu()<CR>gv
    snoremap <silent><RightMouse> <C-G>:call GuiShowContextMenu()<CR>gv
endif
