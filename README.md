# vim-config

A unified Vim 8+ / Neovim configuration for Python/Django development. Works with both editors from the same repository, sharing common settings while leveraging modern Neovim features (LSP, Treesitter, Telescope) when available.

## Structure

```
~/.vim/
├── common.vim      # Shared options (sourced by both vim and nvim)
├── vimrc           # Vim 8+ config (vim-plug, syntastic, NERDTree)
├── init.lua        # Neovim config (lazy.nvim, LSP, nvim-cmp, telescope)
├── install.sh      # One-shot installer (./install.sh ia for AI support)
├── ai.lua          # AI config (CodeCompanion, loaded only if enabled)
├── CHEATSHEET.md   # Keybindings reference
└── .gitignore
```

## Quick start

```bash
git clone <your-repo-url> ~/.vim
cd ~/.vim
./install.sh
```

The installer will:
- Create symlinks (`~/.vimrc`, `~/.config/nvim/init.lua`)
- Install [vim-plug](https://github.com/junegunn/vim-plug) and Vim plugins
- Install Neovim plugins via [lazy.nvim](https://github.com/folke/lazy.nvim) (auto-bootstrapped)
- Install Python tooling via `pipx` (ruff, pyright)
- Install system packages (pyflakes3, flake8, ripgrep)

## Requirements

- **Vim 8+** and/or **Neovim 0.11+**
- `git`, `curl`
- `pipx` (installed automatically)
- A terminal with true color support (recommended)

## Features

### Shared (Vim + Neovim)

- **NERDTree** — file explorer (`Ctrl+x` to toggle, `Enter` opens in a new tab)
- **vim-fugitive** — Git integration (`:Git`, `:Git blame`, `:Gwrite`, etc.)
- **Tokyonight** colorscheme with white-mode toggle (`Space hc`)
- Persistent undo (separate undo dirs to avoid format conflicts)
- Auto-reload files changed on disk
- Cursor position restored on file reopen
- Sane defaults: UTF-8, 4-space tabs, incremental search, smart case

### Neovim only

- **Pyright LSP** — go to definition (`gd`), hover (`K`), rename (`Space rn`), code actions (`Space ca`), references (`gr`)
- **nvim-cmp** — auto-completion from LSP, buffer words, and file paths
- **Telescope** — fuzzy file finder (`Space ff`), live grep (`Space fg`), buffer list (`Space fb`), diagnostics (`Space fd`). Results open in new tabs by default.
- **nvim-lint** — Python linting with ruff (runs on save/open)
- **gitsigns.nvim** — Git diff signs in the gutter
- **Treesitter** — syntax highlighting and indentation
- **Diagnostic loclist** — error window at the bottom (auto-opens/closes), floating popup on the current line

### Vim only

- **syntastic** — Python linting (pyflakes, flake8, vulture)
- **vim-gitgutter** — Git diff signs in the gutter
- **Tagbar** — symbol navigation (`:TagbarToggle`)

## Key bindings

Leader key is `Space`.

| Key | Action | Scope |
|-----|--------|-------|
| `Ctrl+x` | Toggle NERDTree | vim + nvim |
| `Space hc` | Toggle high contrast (pure white text) | vim + nvim |
| `Space ff` | Find files | nvim |
| `Space fg` | Live grep (requires ripgrep) | nvim |
| `Space fb` | List buffers | nvim |
| `Space fd` | List diagnostics | nvim |
| `gd` | Go to definition | nvim |
| `gr` | Find references | nvim |
| `K` | Hover documentation | nvim |
| `Space rn` | Rename symbol | nvim |
| `Space ca` | Code actions | nvim |
| `gt` / `gT` | Next / previous tab | vim + nvim |

See [CHEATSHEET.md](CHEATSHEET.md) for the full reference.

## AI assistant (optional)

AI support is **not installed by default**. To enable it:

```bash
./install.sh ia
```

This will:
- Enable [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) in Neovim
- Prompt for your Anthropic API key (or you can export `ANTHROPIC_API_KEY` in your shell)

The API key is stored locally in `~/.config/codecompanion/anthropic_key` (chmod 600) and never committed.

To disable AI, remove `~/.vim/.ai-enabled` and restart Neovim.

### AI key bindings (Neovim only)

| Key | Action |
|-----|--------|
| `Space ac` | Toggle AI chat window |
| `Space aa` | AI actions menu |
| `Space ae` | AI inline edit (visual mode) |

### Switching to local AI (Ollama)

Edit `ai.lua` and change the `adapter` values from `"anthropic"` to `"ollama"`. The default Ollama model is `qwen2.5-coder:14b`.

## Colorscheme

Default theme is **tokyonight night** with pure white text override for better contrast. Press `Space hc` to toggle between pure white and the native tokyonight bluish-white.

## Customization

- **Vim plugins**: edit the `plug#begin` / `plug#end` block in `vimrc`, then `:PlugInstall`
- **Neovim plugins**: edit the `lazy.setup` block in `init.lua`, restart nvim
- **Shared options**: edit `common.vim` (applies to both)

## License

MIT
