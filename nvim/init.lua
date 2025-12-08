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
  {
    "folke/trouble.nvim",
    opts = {},
    cmd = "Trouble",
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",                        desc = "Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",           desc = "Buffer Diagnostics (Trouble)" },
      { "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>",                desc = "Symbols (Trouble)" },
      { "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP Definitions / references / ..." },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>",                            desc = "Location List (Trouble)" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>",                             desc = "Quickfix List (Trouble)" },
    },
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    lazy = false,
    opts = {},
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        vue = { "prettier" },
        svelte = { "prettier" },

        nix = { "alejandra" },
      },

      -- try formatters in order until one succeeds, fall back to LSP
      format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
        quiet = true,
      },
    },
    config = function(_, opts)
      local conform = require("conform")
      conform.setup(opts)

      vim.keymap.set("n", "<leader>f", function()
        conform.format({ async = true })
      end, { desc = "Format with Conform/LSP" })
    end,
  },
  {
    "saghen/blink.cmp",
    dependencies = { "rafamadriz/friendly-snippets" },
    version = "1.*",
    opts = {
      keymap = { preset = "default" },
      appearance = { nerd_font_variant = "mono" },
      completion = { documentation = { auto_show = false } },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    opts_extend = { "sources.default" },
  },
  "itchyny/lightline.vim",
  "savq/melange-nvim",
  "neovim/nvim-lspconfig",
  "preservim/nerdcommenter",
  "tpope/vim-sensible",
  "tpope/vim-fugitive",
  "tpope/vim-sleuth",
  "ryanoasis/vim-devicons",
  "junegunn/fzf.vim",
  "mileszs/ack.vim",
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      highlight = { enable = true },
      indent = { enable = true },
      ensure_installed = {
        "astro", "awk", "bash", "c", "cpp", "css", "diff", "eex", "elixir", "elm", "elvish", "erlang", "fish",
        "git_rebase", "gitcommit", "gitignore", "gleam", "graphql", "haskell", "heex", "html", "hurl", "java",
        "javascript", "just", "jq", "json", "lua", "luadoc", "make", "markdown", "markdown_inline", "nix",
        "ocaml", "ocaml_interface", "python", "query", "ruby", "scss", "sql", "toml", "typescript", "vim",
        "vimdoc", "vue", "yaml",
      },
      sync_install = false,
      auto_install = false,
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}, {
  -- Track these, and change once merged:
  -- https://github.com/folke/lazy.nvim/pull/1276
  -- https://github.com/folke/lazy.nvim/pull/1157
  performance = {
    reset_packpath = false,
    rtp = { reset = false },
  },
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
vim.opt.termguicolors = true
vim.cmd.colorscheme 'melange'

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
vim.api.nvim_set_keymap('v', '<C-y>', ':w !xclip -sel c <CR><CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-y>', ':w !xclip -sel c <CR><CR>', { noremap = true })

vim.lsp.config('elixirls', {
  cmd = { 'elixir-ls' }
})

vim.lsp.config('ruby_lsp', {})
vim.lsp.config('ts_ls', {})
vim.lsp.config('eslint', {})

vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      diagnostics = {
        globals = { 'vim' }
      }
    }
  }
})

-- incremental analysis assistant for writing in Nix
vim.lsp.config('nil_ls', {})

-- Enable all configured LSP servers
vim.lsp.enable({ 'elixirls', 'ruby_lsp', 'ts_ls', 'eslint', 'lua_ls', 'nil_ls' })

--vim.lsp.enable('postgres_lsp')

--local lspconfig = require 'lspconfig'
--local configs = require 'lspconfig.configs'
--local lsp_util = require 'lspconfig.util'

--configs.lexical = {
--default_config = {
--name = 'Lexical',
--filetypes = { 'elixir', 'eelixir', 'heex' },
--cmd = { '/opt/elixir/lexical/bin/start_lexical.sh' },
--root_dir = function(fname)
--return lsp_util.root_pattern('mix.exs', '.git')(fname) or vim.loop.os_homedir()
--end,
--},
--}

--lspconfig.lexical.setup {}


-- Not working?
-- require 'lspconfig'.mdx_analyzer.setup {}

vim.filetype.add({
  extension = { mdx = 'mdx' }
})

--vim.treesitter.language.register('mdx', 'markdown')
--local ft_to_parser = require("nvim-treesitter.parsers").filetype_to_parsername
--ft_to_parser.mdx = "markdown"

-- vim.lsp.set_log_level("debug")

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
    vim.keymap.set('n', '<leader>k', vim.lsp.buf.signature_help, opts)
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
