{ config, pkgs, lib, ... }:

{
  # https://github.com/nix-community/home-manager/issues/3342#issuecomment-1406637333
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "felix";
  home.homeDirectory = "/home/felix";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.11";

  home.packages = with pkgs; [
    bat
    ctop
    diff-so-fancy
    dive
    docker-compose
    fff
    fzf
    fontconfig
    git
    google-cloud-sdk
    inconsolata
    jq
    kubectl
    kubernetes-helm
    moreutils
    mosh
    nixfmt
    pgcli
    ripgrep
    scc
    tree
    xclip
    (pkgs.nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    FZF_DEFAULT_COMMAND = "rg --files --follow";
  };
  

  programs.direnv.enable = true;

  home.shellAliases = {
    bux = "bundle exec";
    cat = "bat";
    gplease = "git push --no-verify --force-with-lease";
    k = "kubectl";
  };

  programs.git = {
    enable = true;
    userName = "Felix ";
    userEmail = "felix@hinterstellar.io";
    lfs.enable = true;
    extraConfig = {
      core = {
        editor = "nvim";
        pager = "diff-so-fancy | less --tabs=4 -RFX";
      };
    };
  };

  programs = {
    exa = {
      enable = true;
      enableAliases = true;
    };
  };

  programs.fish = {
   enable = true;
  
   plugins = [
   {
       name="foreign-env";
       src = pkgs.fetchFromGitHub {
           owner = "oh-my-fish";
           repo = "plugin-foreign-env";
           rev = "dddd9213272a0ab848d474d0cbde12ad034e65bc";
           sha256 = "00xqlyl3lffc5l0viin1nyp819wf81fncqyz87jx8ljjdhilmgbs";
       };
   }
   {
       name="plugin-git";
       src = pkgs.fetchFromGitHub {
           owner = "jhillyerd";
           repo = "plugin-git";
           rev = "2df7fe23543fe8147c7be23bb85b6c6448ad023e";
           sha256 = "1c2grvkd8w4jybw5rs41w4lpq4c2yx1jcbnzfpnmc3c2445k9jlh"; #lib.fakeSha256; 
       };
   }
   {
       name="fish-kubectl-completions";
       src = pkgs.fetchFromGitHub {
           owner = "evanlucas";
           repo = "fish-kubectl-completions";
           rev = "ced676392575d618d8b80b3895cdc3159be3f628";
           sha256 = "OYiYTW+g71vD9NWOcX1i2/TaQfAg+c2dJZ5ohwWSDCc="; #lib.fakeSha256; 
       };
   }
   ];
  
   shellInit =
   ''
       # nix
       if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
           fenv source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
       end
  
       # home-manager
       if test -e /nix/var/nix/profiles/per-user/felix/profile/etc/profile.d/nix.sh 
           fenv source /nix/var/nix/profiles/per-user/felix/profile/etc/profile.d/nix.sh 
       end
   '';
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    # Configuration written to ~/.config/starship.toml
    settings = {
      # add_newline = false;

      # character = {
      #   success_symbol = "[➜](bold green)";
      #   error_symbol = "[➜](bold red)";
      # };

      # package.disabled = true;
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      shell.program = "${pkgs.fish}/bin/fish";
      window = {
        startup_mode = "Maximized";
      };
    };
  };

  programs.tmux = {
    enable = true;

    prefix = "C-a";
    clock24 = true;
    escapeTime = 0;
    extraConfig = ''
      set-option -ga terminal-overrides ",xterm-256color:Tc"
      set -s default-terminal "xterm-256color"
      set -g mouse on
      set -g focus-events off
      # Match postgresql URLs, default url_search doesn't
      set -g @copycat_search_C-p '(https?://|git@|git://|ssh://|ftp://|postgresql://|file:///)[[:alnum:]?=%/_.:,;~@!#$&()*+-]*'

      # Shift arrow to switch windows
      bind -n S-Left  previous-window
      bind -n S-Right next-window
    '';
    keyMode = "vi";
    plugins = with pkgs; [
      { plugin = tmuxPlugins.resurrect; }
      { plugin = tmuxPlugins.continuum; }
      { plugin = tmuxPlugins.pain-control; }
      { plugin = tmuxPlugins.yank; }
      # { plugin = tmuxPlugins.open; }
      # { plugin = tmuxPlugins.copycat; }
    ];
    shell = "${pkgs.fish}/bin/fish";
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
    plugins = with pkgs.vimPlugins; [
      ack-vim
      ale
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
    ];
    extraConfig = builtins.readFile ./nvim/extra-config.vim;
  };
}
