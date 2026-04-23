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

## IA — CodeCompanion (nvim uniquement, si activé via `./install.sh ia`)

| Raccourci | Mode | Action |
|-----------|------|--------|
| `Espace ac` | normal / visuel | Ouvrir/fermer le chat IA |
| `Espace aa` | normal / visuel | Menu d'actions IA |
| `Espace ae` | visuel | Édition inline par l'IA |

### Utilisation du chat

- Ouvre le chat avec `Espace ac`, tape ta question, `Enter` pour envoyer
- Tu peux sélectionner du code en visuel puis `Espace ac` pour envoyer le code dans le chat
- `Espace aa` propose des actions prédéfinies : expliquer, refactorer, corriger, documenter, tests…

### Édition inline

1. Sélectionne du code en mode visuel (`v` ou `V`)
2. `Espace ae` puis tape ton instruction (ex: "ajoute des docstrings")
3. L'IA modifie le code directement dans le buffer

### Changer d'adapter

Par défaut : **Claude** (Anthropic API). Pour utiliser **Ollama** local, modifier `adapter = "ollama"` dans `ai.lua`.

### Désactiver l'IA

```bash
rm ~/.vim/.ai-enabled
# puis relancer nvim
```

## RAG — Assistant sur la codebase (nvim uniquement, si activé via `./install.sh rag`)

Le RAG permet à l'IA d'interroger **ton code** : il retrouve les extraits
pertinents d'un projet puis les envoie au modèle (celui configuré par
`./install.sh ia`) pour qu'il réponde en s'appuyant sur ces extraits.

### Raccourcis (mode normal)

| Raccourci | Action |
|-----------|--------|
| `Espace aq` | **Q**uestion libre sur le projet (prompt) |
| `Espace ar` | Question sur le buffer cou**r**ant + contexte projet |
| `Espace aR` | **R**éindexer le projet courant |

### Commandes

| Commande | Action |
|----------|--------|
| `:VimRagQuery <question>` | équivalent de `Espace aq` avec argument |
| `:VimRagIndex [path]` | indexer (par défaut le projet courant) |
| `:VimRagStatus` | état de l'index du projet courant |

### Dans la fenêtre de réponse

| Raccourci | Action |
|-----------|--------|
| `q` / `Esc` | fermer la fenêtre |
| `yy` | copier la réponse complète dans le presse-papiers |

### Première utilisation

```bash
# 1. Pull un ou plusieurs modèles d'embedding
docker exec ollama ollama pull mxbai-embed-large
# (ou nomic-embed-text pour un modèle plus léger)

# 2. Activer le RAG (menu interactif de choix du modèle d'embedding)
cd ~/.vim && ./install.sh rag

# 3. Indexer un projet
cd /chemin/vers/ton/projet && vim-rag index .

# 4. Lancer nvim dans le projet, appuyer sur Espace aq
```

Pour changer de modèle d'embedding plus tard : relance `./install.sh rag`.
Les projets indexés devront être réindexés (l'outil le détecte et te le dit).

### CLI en dehors de Neovim

```bash
vim-rag index <path>                         # indexer / mettre à jour
vim-rag query "question" --project <path>    # retrieval brut en JSON
vim-rag list                                 # projets indexés
vim-rag status <path>                        # infos sur un index
vim-rag clean <path>                         # supprimer un index
```

### Désactiver le RAG

```bash
rm ~/.vim/.rag-enabled
pipx uninstall vim-rag    # optionnel
# puis relancer nvim
```
