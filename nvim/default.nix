{ pkgs, lib, ... }:

let
  treeSitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (treesitter-plugins:
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
      hurl
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

in {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
    plugins =
      with pkgs.vimPlugins; [
      treeSitter 
    ];
  };
}
