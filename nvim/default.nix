{ pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
    plugins =
      with pkgs.vimPlugins; [
    ];
  };
}
