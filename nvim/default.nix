{ pkgs, lib, ... }:

let
  fromGitHub = import ./functions/fromGitHub.nix;

in {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
    plugins = with pkgs.vimPlugins; [
      ack-vim
      coc-css
      coc-json
      coc-nvim
      coc-tslint
      coc-yaml
      elm-vim
      fzf-vim
      gleam-vim
      lightline-vim
      neovim-ayu
      nerdcommenter
      nerdtree
      nerdtree-git-plugin
      vim-devicons
      vim-elixir
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
