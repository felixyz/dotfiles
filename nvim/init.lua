local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  "airblade/vim-gitgutter",
  "itchyny/lightline.vim",
  "Shatur/neovim-ayu",
  "neovim/nvim-lspconfig",
  "preservim/nerdtree",
  "preservim/nerdcommenter",
  "Xuyuanp/nerdtree-git-plugin",
  "tpope/vim-sensible",
  "tpope/vim-fugitive",
  "tpope/vim-sleuth",
  "ryanoasis/vim-devicons",
  "junegunn/fzf.vim",
  "mileszs/ack.vim",
  "nvim-treesitter/nvim-treesitter"
}, {
  -- Track these, and change once merged:
  -- https://github.com/folke/lazy.nvim/pull/1276
  -- https://github.com/folke/lazy.nvim/pull/1157
  performance = {
    reset_packpath = false,
    rtp = {
      reset = false
    }
  }
})

-- Splits navigation
vim.api.nvim_set_keymap('n', '<C-J>', '<C-W><C-J>', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-K>', '<C-W><C-K>', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-L>', '<C-W><C-L>', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-H>', '<C-W><C-H>', { noremap = true })

vim.o.splitbelow = true
vim.o.splitright = true

-- Disable arrow keys
vim.api.nvim_set_keymap('', '<Up>', '<NOP>', { noremap = true })
vim.api.nvim_set_keymap('', '<Down>', '<NOP>', { noremap = true })
vim.api.nvim_set_keymap('', '<Left>', '<NOP>', { noremap = true })
vim.api.nvim_set_keymap('', '<Right>', '<NOP>', { noremap = true })

vim.wo.number = true
vim.cmd('filetype plugin on')

-- Termguicolors
if vim.fn.exists('+termguicolors') == 1 then
  vim.o.termguicolors = true
end

-- Theme
vim.o.background = 'dark'
vim.g.ayucolor = 'dark'
vim.cmd('colorscheme ayu')

-- Lightline configuration
vim.g.lightline = {
  active = {
    left = { { 'mode', 'paste' },
      { 'gitbranch', 'readonly', 'relativepath', 'modified' } }
  },
  component = { helloworld = 'Hello, world!' },
  component_function = { gitbranch = 'FugitiveHead' },
}

vim.o.showmode = false -- lightline shows mode

-- Auto-start NERDTree
vim.cmd([[
  autocmd StdinReadPre * let s:std_in=1
  autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
]])

-- Refresh NERDTree
vim.api.nvim_set_keymap('n', '<Leader>r', ':NERDTreeFocus<cr>R<c-w><c-p>', { noremap = true })

vim.api.nvim_set_keymap('n', '<c-p>', ':FZF<cr>', { noremap = true })
vim.api.nvim_set_keymap('n', '<c-s>', ':w<cr>', { noremap = true })

vim.api.nvim_set_keymap('i', '<Tab>', '<C-P>', { noremap = true })

vim.api.nvim_set_keymap('i', 'kj', '<Esc>', { noremap = true })

vim.o.expandtab = true

-- Ripgrep configuration
vim.g.ackprg = 'rg --vimgrep --type-not csv --smart-case --context 2'
vim.g.ack_autoclose = 1
vim.g.ack_use_cword_for_empty_search = 1
vim.cmd("cnoreabbrev Ack Ack!")

vim.api.nvim_set_keymap('n', '<Leader>/', ':Ack!<Space>', { noremap = true })

-- Navigate quickfix list
vim.api.nvim_set_keymap('n', '[q', ':cprevious<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', ']q', ':cnext<CR>', { noremap = true, silent = true })

-- Copy to clipboard
vim.api.nvim_set_keymap('n', '<C-y>', ':w !xclip -sel c <CR><CR>', { noremap = true })

-- LSP config
local lspconfig = require('lspconfig')

lspconfig.elixirls.setup {
  cmd = { "/home/felix/.nix-profile/bin/elixir-ls" },
}
lspconfig.gleam.setup {}
lspconfig.ocamllsp.setup {}
lspconfig.ruby_ls.setup {}
lspconfig.tsserver.setup {}

lspconfig.lua_ls.setup {
  settings = {
    Lua = {
      diagnostics = {
        globals = { 'vim' }
      }
    }
  }
}

vim.lsp.set_log_level("debug")

-- https://github.com/neovim/nvim-lspconfig#suggested-configuration
-- Global mappings.
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
vim.keymap.set('n', '<space>e', vim.diagnostic.open_float)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next)
vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist)

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    -- Enable completion triggered by <c-x><c-o>
    vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

    -- Buffer local mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
    vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<leader>f', function()
      vim.lsp.buf.format { async = true }
    end, opts)
  end,
})

require 'nvim-treesitter.configs'.setup {
  -- Install parsers synchronously (only applied to `ensure_installed`)
  sync_install = false,

  -- Automatically install missing parsers when entering buffer
  -- Recommendation: set to false if you don't have `tree-sitter` CLI installed locally
  auto_install = false,

  -- List of parsers to ignore installing (or "all")
  -- ignore_install = { "javascript" },

  ---- If you need to change the installation directory of the parsers (see -> Advanced Setup)
  -- parser_install_dir = "/some/path/to/store/parsers", -- Remember to run vim.opt.runtimepath:append("/some/path/to/store/parsers")!

  highlight = {
    enable = true,

    -- NOTE: these are the names of the parsers and not the filetype. (for example if you want to
    -- disable highlighting for the `tex` filetype, you need to include `latex` in this list as this is
    -- the name of the parser)
    -- list of language that will be disabled
    -- disable = { "c", "rust" },
    -- Or use a function for more flexibility, e.g. to disable slow treesitter highlight for large files
    disable = function(lang, buf)
      local max_filesize = 100 * 1024 -- 100 KB
      local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
      if ok and stats and stats.size > max_filesize then
        return true
      end
    end,

    -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
    -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
    -- Using this option may slow down your editor, and you may see some duplicate highlights.
    -- Instead of true it can also be a list of languages
    additional_vim_regex_highlighting = false,
  },
}

vim.api.nvim_create_augroup('AutoFormatting', {})
vim.api.nvim_create_autocmd('BufWritePre', {
  group = 'AutoFormatting',
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})
