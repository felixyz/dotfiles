{ config, pkgs, lib, ... }:

let
  alacritty_colors = builtins.fromTOML (builtins.readFile ./melange_dark.toml);
  claude-code-latest = pkgs.claude-code.overrideAttrs (old: {
    version = "1.0.94";
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-1.0.94.tgz";
      hash = "sha256-TAGs9elamISvxeEH02w+TU+B7HTYtnWBqukTiSpikeU=";
    };
    npmDepsHash = "sha256-M6H6A4i4JBqcFTG/ZkmxpINa4lw8sO5+iu2YcBqmvi1=";
  });
in
{
  imports = [
    ./nvim
  ];

  # https://github.com/nix-community/home-manager/issues/3342#issuecomment-1406637333
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # home.extraSpecialArgs = { inherit unstable };

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
  home.stateVersion = "23.11";
  
  xdg = {
    configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nvim";
  };

  nixpkgs.config = { 
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };

  home.packages = with pkgs; [
    bat
    claude-code-latest
    ctop
    diff-so-fancy
    difftastic
    dive
    docker-compose
    fd
    fff
    fzf
    fontconfig
    git
    ijq
    inconsolata
    jq
    lazygit
    moreutils
    mosh
    neofetch
    pgcli
    pgformatter
    procs
    ripgrep
    scc
    tree
    #vscode
    xclip
    (google-cloud-sdk.withExtraComponents [google-cloud-sdk.components.gke-gcloud-auth-plugin])
    (pkgs.nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
    kubectl
    kubernetes-helm

    # LSPs
    elixir-ls
    lua-language-server
    ocamlPackages.lsp
    nodePackages.typescript-language-server
    ruby-lsp
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    FZF_DEFAULT_COMMAND = "rg --files --follow";
  };
  
  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  home.shellAliases = {
    bux = "bundle exec";
    cat = "bat";
    gplease = "git push --no-verify --force-with-lease";
    k = "kubectl";
    ks = "kubectl -n staging";
    kp = "kubectl -n production";
    dokku = "~/.dokku/contrib/dokku_client.sh";
    dk = "~/.dokku/contrib/dokku_client.sh";
  };

  programs.git = {
    enable = true;
    userName = "Felix ";
    userEmail = "felix@hinterstellar.io";
    lfs.enable = true;
    extraConfig = {
      pack.window = 1;
      core = {
        editor = "nvim";
        pager = "diff-so-fancy | less --tabs=4 -RFX";
      };
    };
  };

  #programs = {
    #exa = {
      #enable = true;
      #enableAliases = true;
    #};
  #};

  programs.fish = {
   enable = true;
  
   plugins = [
   {
       name="foreign-env";
       src = pkgs.fetchFromGitHub {
           owner = "oh-my-fish";
           repo = "plugin-foreign-env";
           rev = "7f0cf099ae1e1e4ab38f46350ed6757d54471de7";
           sha256 = "4+k5rSoxkTtYFh/lEjhRkVYa2S4KEzJ/IJbyJl+rJjQ=";
           # sha256 = lib.fakeSha256;
       };
   }
   {
       name="plugin-git";
       src = pkgs.fetchFromGitHub {
           owner = "jhillyerd";
           repo = "plugin-git";
           rev = "c2b38f53f0b04bc67f9a0fa3d583bafb3f558718";
           sha256 = "efKPbsXxjHm1wVWPJCV8teG4DgZN5dshEzX8PWuhKo4="; #lib.fakeSha256; 
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
      colors = alacritty_colors // {
        draw_bold_text_with_bright_colors = true;
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
}
