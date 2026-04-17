{
  config,
  pkgs,
  ...
}: let
  # Separate nixpkgs pin for packages where we want a newer version
  # than the system channel provides. Update the sha256 to bump.
  nixpkgs-latest-base = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz";
    sha256 = "19mppaiq05h4xrpch4i0jkkca4nnfdksc2fkhssplawggsj57id6";
  }) {config.allowUnfree = true;};
  # Override nixpkgs (stuck at 0.7.3) — older versions still trigger the
  # "third-party app" billing notice. Fetch the prebuilt npm tarball to
  # bypass the upstream pnpm/tsc toolchain (same pattern as claude-code-latest).
  opencode-claude-auth-latest = pkgs.stdenv.mkDerivation rec {
    pname = "opencode-claude-auth";
    version = "1.5.0";
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/opencode-claude-auth/-/opencode-claude-auth-${version}.tgz";
      hash = "sha256-wZat/OG/6dTIRO/HXq+xfXl7kgxTYCyVmI6JkAO9SIg=";
    };
    installPhase = ''
      mkdir -p $out/lib/node_modules/opencode-claude-auth
      cp -r dist opencode-claude-auth.js package.json \
        $out/lib/node_modules/opencode-claude-auth/
    '';
  };
  nixpkgs-latest =
    nixpkgs-latest-base
    // {
      opencode-claude-auth = opencode-claude-auth-latest;
    };
  alacritty_colors = fromTOML (builtins.readFile ./melange_dark.toml);
  claude-code-latest = pkgs.stdenv.mkDerivation {
    pname = "claude-code";
    version = "2.1.112";
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.112.tgz";
      hash = "sha256-SJJqU7XHbu9IRGPMJNUg6oaMZiQUKqJhI2wm7BnR1gs=";
    };
    nativeBuildInputs = [pkgs.makeWrapper];
    installPhase = ''
      mkdir -p $out/lib/claude-code $out/bin
      cp -r . $out/lib/claude-code/
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/claude \
        --add-flags "$out/lib/claude-code/cli.js"
    '';
  };
in {
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
    allowUnfreePredicate = _: true;
  };

  home.packages = with pkgs; [
    (writeShellScriptBin "bwrap-sandbox" (builtins.readFile ./scripts/bwrap-sandbox.sh))
    (writeShellScriptBin "bwrap-allow-host" (builtins.readFile ./scripts/bwrap-allow-host.sh))
    (writeShellScriptBin "bwrap-allow-port" (builtins.readFile ./scripts/bwrap-allow-port.sh))
    (writeShellScriptBin "podman-build" (builtins.readFile ./scripts/podman-build.sh))
    awscli2
    bat
    claude-code-latest
    nixpkgs-latest.devenv
    nixpkgs-latest.signal-desktop
    ctop
    diff-so-fancy
    difftastic
    dive
    fastfetch
    fd # Simple, fast and user-friendly alternative to find
    fff
    fx # Terminal JSON viewer
    fzf
    fontconfig
    git
    git-absorb # git commit --fixup, but automatic
    ijq
    inconsolata
    jujutsu
    jq
    lazygit
    lsof
    mergiraf # syntax-aware git merge driver
    moreutils
    nodejs # npx needed for chrome-devtools MCP
    ngrok
    nixpkgs-latest.opencode
    nixpkgs-latest.opencode-claude-auth
    pgcli
    pgformatter
    procs
    python313
    ripgrep
    scc
    shellcheck
    tree
    wl-clipboard # wl-paste/wl-copy for Wayland clipboard (image paste in Claude)
    xclip
    (google-cloud-sdk.withExtraComponents [google-cloud-sdk.components.gke-gcloud-auth-plugin])
    pkgs.nerd-fonts.hack
    kubectl
    kubernetes-helm

    # LSPs / formatters
    alejandra # "The Uncompromising Nix Code Formatter"
    elixir-ls
    lua-language-server
    nixd # Nix language server, based on nix libraries
    nodePackages.typescript-language-server
    ruby-lsp
    vscode-langservers-extracted
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    FZF_DEFAULT_COMMAND = "rg --files --follow";
    DOCKER_BUILD = "podman-build"; # dereferences symlinks in build context for podman compat
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
    dk = "~/.dokku/contrib/dokku_client.sh";
    dokku = "~/.dokku/contrib/dokku_client.sh";
    dv = "devenv";
    jean-claude = "BWRAP_PERSONA=claude bwrap-sandbox $(command -v claude) --dangerously-skip-permissions";
    jean-luc = "BWRAP_PERSONA=opencode bwrap-sandbox $(command -v opencode) --agent yolo";
    sbd = "env CONTAINER_HOST=unix:///run/bwrap-podman/podman.sock podman --remote";
    sb-nuke = "env CONTAINER_HOST=unix:///run/bwrap-podman/podman.sock podman --remote rm -af";
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = "Felix Holmgren";
        email = "felix@hinterstellar.io";
      };
      pack.window = 1;
      core = {
        editor = "nvim";
        pager = "diff-so-fancy | less --tabs=4 -RFX";
      };
      merge.conflictStyle = "diff3";
      merge.mergiraf = {
        name = "mergiraf";
        driver = "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L";
      };
    };
    attributes = [
      "* merge=mergiraf"
    ];
  };

  programs.difftastic = {
    enable = true;
    git.enable = true;
  };

  xdg.configFile."pijul/config.toml".source = (pkgs.formats.toml {}).generate "pijul-config" {
    author = {
      name = "felixyz";
      full_name = "Felix Holmgren";
      email = "felix@hinterstellar.io";
    };
  };

  # Plugin file is a tiny re-export so opencode treats claude-auth as a
  # local plugin (from plugins/) instead of fetching "@latest" from npm.
  # This pins the version to whatever Nix resolves for opencode-claude-auth.
  xdg.configFile."opencode/opencode.json".source = ./opencode/config.json;
  xdg.configFile."opencode/plugins/claude-auth.js".text = ''
    export { ClaudeAuthPlugin, default } from "${nixpkgs-latest.opencode-claude-auth}/lib/node_modules/opencode-claude-auth/dist/index.js";
  '';
  xdg.configFile."opencode/agents/yolo.md".source = ./opencode/yolo.md;
  xdg.configFile."opencode/tui.json".source = ./opencode/tui.json;

  programs.jujutsu.settings = {
    user = {
      email = "felix@hinterstellar.io";
      name = "Felix Holmgren";
    };
  };

  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "foreign-env";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-foreign-env";
          rev = "7f0cf099ae1e1e4ab38f46350ed6757d54471de7";
          sha256 = "4+k5rSoxkTtYFh/lEjhRkVYa2S4KEzJ/IJbyJl+rJjQ=";
          # sha256 = lib.fakeSha256;
        };
      }
      {
        name = "plugin-git";
        src = pkgs.fetchFromGitHub {
          owner = "jhillyerd";
          repo = "plugin-git";
          rev = "09db2a91510ca8b6abc2ad23c6484f56b3cd72be";
          sha256 = "2+CX9ZGNkois7h3m30VG19Cf4ykRdoiPpEVxJMk75I4="; #lib.fakeSha256;
        };
      }
      {
        name = "fish-kubectl-completions";
        src = pkgs.fetchFromGitHub {
          owner = "evanlucas";
          repo = "fish-kubectl-completions";
          rev = "ced676392575d618d8b80b3895cdc3159be3f628";
          sha256 = "OYiYTW+g71vD9NWOcX1i2/TaQfAg+c2dJZ5ohwWSDCc="; #lib.fakeSha256;
        };
      }
    ];

    shellInit = ''
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

    settings = {
      add_newline = true;
      format = "$directory$git_branch$git_status\n$character";

      character = {
        success_symbol = "[❯](bold white)";
        error_symbol = "[❯](bold red)";
      };

      directory = {
        truncate_to_repo = true;
        format = "[$path]($style) ";
        style = "bold bright-blue";
      };

      git_branch = {
        symbol = "";
        format = "[$symbol$branch]($style) ";
        style = "bold green";
      };

      git_status = {
        format = "([$all_status$ahead_behind]($style)) ";
        style = "bold red";
        untracked = "";
      };

      status.disabled = true;
    };
  };

  xdg.configFile."alacritty/alacritty.toml".force = true;

  programs.alacritty = {
    enable = true;
    settings = {
      shell.program = "${pkgs.fish}/bin/fish";
      window = {
        startup_mode = "Maximized";
      };
      font = {
        normal = {
          family = "Hack Nerd Font";
          style = "Regular";
        };
        size = 11.0;
      };
      colors =
        alacritty_colors
        // {
          draw_bold_text_with_bright_colors = true;
        };
    };
  };

  programs.ghostty = {
    enable = true;
    package = null; # installed system-wide
    enableFishIntegration = true;
    systemd.enable = false;
    installBatSyntax = false;
    settings = {
      command = "${pkgs.fish}/bin/fish";
      maximize = true;
      font-family = "Hack Nerd Font";
      font-size = 11;
      background = alacritty_colors.primary.background;
      foreground = alacritty_colors.primary.foreground;
      palette = let
        c = alacritty_colors;
      in [
        "0=${c.normal.black}"
        "1=${c.normal.red}"
        "2=${c.normal.green}"
        "3=${c.normal.yellow}"
        "4=${c.normal.blue}"
        "5=${c.normal.magenta}"
        "6=${c.normal.cyan}"
        "7=${c.normal.white}"
        "8=${c.bright.black}"
        "9=${c.bright.red}"
        "10=${c.bright.green}"
        "11=${c.bright.yellow}"
        "12=${c.bright.blue}"
        "13=${c.bright.magenta}"
        "14=${c.bright.cyan}"
        "15=${c.bright.white}"
      ];
    };
  };

  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "paperwm@paperwm.github.com"
        "appindicatorsupport@rgcjonas.gmail.com"
      ];
    };

    # PaperWM overrides these at runtime, but setting them here avoids
    # a flash of wrong behavior before the extension loads
    "org/gnome/mutter" = {
      workspaces-only-on-primary = false;
      edge-tiling = false;
      attach-modal-dialogs = false;
      dynamic-workspaces = true;
    };

    "org/gnome/shell/extensions/paperwm" = {
      selection-border-size = 3;
      selection-border-radius-top = 5;
      selection-border-radius-bottom = 0;
      window-gap = 5;
      horizontal-margin = 0;
      vertical-margin = 0;
      vertical-margin-bottom = 0;
    };
  };

  programs.tmux = {
    enable = true;

    prefix = "C-a";
    clock24 = true;
    escapeTime = 0;
    historyLimit = 10000;
    extraConfig = ''
      # sync: buffers TUI output to reduce flicker (e.g. process-compose).
      # Won't fully work until bubbletea emits sync sequences. Track:
      #   https://github.com/charmbracelet/bubbletea/issues/850
      #   https://github.com/charmbracelet/bubbletea/pull/1027
      set -as terminal-features ",xterm-256color:RGB:sync"
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
      {plugin = tmuxPlugins.resurrect;}
      {plugin = tmuxPlugins.continuum;}
      {plugin = tmuxPlugins.pain-control;}
      {plugin = tmuxPlugins.yank;}
      # { plugin = tmuxPlugins.open; }
      # { plugin = tmuxPlugins.copycat; }
    ];
    shell = "${pkgs.fish}/bin/fish";
  };
}
