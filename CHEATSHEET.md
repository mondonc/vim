# Cheat Sheet — Config vim/nvim

Leader = `Espace`

## Navigation fichiers

| Raccourci | Action | Plugin | vim | nvim |
|-----------|--------|--------|-----|------|
| `Ctrl+x` | Ouvrir/fermer l'arbre de fichiers | NERDTree | ✓ | ✓ |
| `Enter` | Ouvrir dans un nouvel onglet (dans NERDTree) | NERDTree | ✓ | ✓ |
| `s` | Ouvrir en split vertical (dans NERDTree) | NERDTree | ✓ | ✓ |
| `i` | Ouvrir en split horizontal (dans NERDTree) | NERDTree | ✓ | ✓ |
| `m` | Menu NERDTree (créer/supprimer/renommer fichier) | NERDTree | ✓ | ✓ |
| `gt` / `gT` | Onglet suivant / précédent | vim natif | ✓ | ✓ |
| `:tabc` | Fermer l'onglet courant | vim natif | ✓ | ✓ |

## Recherche (Telescope — nvim uniquement)

| Raccourci | Action |
|-----------|--------|
| `Espace ff` | Chercher un fichier par nom |
| `Espace fg` | Grep dans tous les fichiers (nécessite ripgrep) |
| `Espace fb` | Lister les buffers ouverts |
| `Espace fd` | Lister tous les diagnostics/erreurs du projet |

Dans Telescope : `Ctrl+j` / `Ctrl+k` pour naviguer, `Enter` pour ouvrir, `Ctrl+t` ouvrir dans un onglet, `Esc` pour fermer.

## Complétion

### Neovim (nvim-cmp + pyright)

La complétion se déclenche automatiquement en tapant. Elle propose des noms de variables, fonctions, méthodes, modules, chemins de fichiers.

| Raccourci | Action |
|-----------|--------|
| `Ctrl+Espace` | Forcer l'ouverture du menu de complétion |
| `Tab` | Sélectionner l'entrée suivante |
| `Shift+Tab` | Sélectionner l'entrée précédente |
| `Enter` | Confirmer la sélection |

Sources (par priorité) :
1. **LSP (pyright)** — méthodes, attributs, types, imports Python
2. **Buffer** — mots déjà présents dans le fichier
3. **Path** — chemins de fichiers (`./`, `../`, `/`)

### Vim (omni completion native)

Pas de complétion automatique — tout est manuel :

| Raccourci | Action |
|-----------|--------|
| `Ctrl+x Ctrl+o` | **Omni completion** — complétion intelligente (Python, HTML…) |
| `Ctrl+x Ctrl+f` | Complétion de chemins de fichiers |
| `Ctrl+x Ctrl+n` | Complétion par mots du fichier courant |
| `Ctrl+x Ctrl+l` | Complétion de lignes entières |
| `Ctrl+n` / `Ctrl+p` | Complétion basique (mots de tous les buffers) |

**Comment utiliser `Ctrl+x Ctrl+o` :**
1. Tu tapes `os.` puis `Ctrl+x Ctrl+o` → liste des méthodes de `os`
2. Tu tapes `import j` puis `Ctrl+x Ctrl+o` → propose `json`, `jinja2`, etc.
3. `Ctrl+n` / `Ctrl+p` pour naviguer dans le menu, `Enter` pour valider

Note : omni completion Python dépend de `filetype plugin on` (déjà activé).

## LSP — Intelligence du code (nvim uniquement)

| Raccourci | Action |
|-----------|--------|
| `gd` | Aller à la définition |
| `gr` | Voir toutes les références |
| `K` | Documentation/hover (sur le mot sous le curseur) |
| `Espace rn` | Renommer le symbole partout |
| `Espace ca` | Actions de code (imports, quickfix…) |

## Linting / Erreurs

### Neovim

Les erreurs s'affichent dans la **loclist** (fenêtre en bas, hauteur 3 lignes). Un popup apparaît quand le curseur reste sur une ligne en erreur.

| Raccourci | Action |
|-----------|--------|
| `:lnext` / `:lprev` | Erreur suivante / précédente |
| `Ctrl+w j` | Aller dans la fenêtre loclist |
| `Enter` | (dans loclist) Sauter à l'erreur |

Linter : **ruff** (vérifie au save et à l'ouverture).

### Vim (syntastic)

Même loclist en bas. Vérifie à l'ouverture et au save.

| Raccourci | Action |
|-----------|--------|
| `:lnext` / `:lprev` | Erreur suivante / précédente |
| `:SyntasticCheck` | Relancer manuellement |
| `:Errors` | Ouvrir la liste d'erreurs |

Linters : pyflakes, flake8, vulture (E501 ignoré).

## Git

### Fugitive (vim + nvim)

| Commande | Action |
|----------|--------|
| `:Git` | Fenêtre de statut git (comme `git status`) |
| `:Git diff` | Diff du fichier |
| `:Git blame` | Blame ligne par ligne |
| `:Git log` | Log du dépôt |
| `:Gwrite` | `git add` le fichier courant |
| `:Gread` | Revenir à la version git (annule les modifs) |

### Signes dans la gouttière

| Signe | Signification |
|-------|---------------|
| `+` | Ligne ajoutée |
| `~` | Ligne modifiée |
| `-` | Ligne supprimée |

Plugin : **vim-gitgutter** (vim) / **gitsigns.nvim** (nvim).

## Tagbar — Navigation par symboles

| Raccourci | Action |
|-----------|--------|
| `:TagbarToggle` | Ouvrir/fermer le panneau de symboles |

Affiche classes, fonctions, méthodes du fichier courant. Nécessite `ctags`.

## Apparence

| Raccourci | Action | vim | nvim |
|-----------|--------|-----|------|
| `Espace hc` | Toggle contraste élevé (blanc pur) | ✓ | ✓ |
| `Ctrl+↑` / `Ctrl+↓` | Taille de police (GUI uniquement) | ✓ | ✓ |

Thème : **tokyonight** (night par défaut).

## Divers

| Raccourci | Action |
|-----------|--------|
| `Ctrl+l` | Rafraîchir l'écran |
| `:noh` | Enlever le surlignage de recherche |
| `u` / `Ctrl+r` | Undo / Redo (persistant entre sessions) |
