{ pkgs, lib, ... }:

let
  fromGitHub = import ./functions/fromGitHub.nix;

in {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
    plugins = let
    nvim-treesitter-with-plugins = pkgs.vimPlugins.nvim-treesitter.withPlugins (treesitter-plugins:
      with treesitter-plugins; [
        astro
        bash
        c
        cpp
        css
        diff
        eex
        elixir
        elm
        erlang
        fish
        git_rebase
        gitcommit
        gitignore
        gleam
        graphql
        haskell
        heex
        html
        java
        javascript
        jq
        json
        lua
        make
        markdown
        markdown_inline
        nix
        ocaml
        ocaml_interface
        python
        query
        ruby
        scss
        sql
        toml
        typescript
        vim
        vimdoc
        vue
        yaml
      ]);
    in
      with pkgs.vimPlugins; [
      ack-vim
      fzf-vim
      lightline-vim
      neovim-ayu
      nerdcommenter
      nerdtree
      nerdtree-git-plugin
      nvim-lspconfig
      nvim-treesitter-with-plugins
      vim-devicons
      vim-fugitive
      vim-gitgutter
      vim-nix
      vim-sensible
      vim-sleuth
      (fromGitHub {user = "wuelnerdotexe"; repo = "vim-astro";})
      (fromGitHub {user = "NoahTheDuke"; repo = "vim-just";})
    ];
    extraConfig = builtins.readFile ./extra-config.vim;
  };
}
