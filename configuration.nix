# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{
  config,
  pkgs,
  lib,
  ...
}: let
  # latest nixpkgs-unstable, to get the newest signal-desktop
  unstable =
    import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
    }) {
      config.allowUnfree = true;
    };
in {
  nix = {
    settings.trusted-users = ["root" "felix"];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  nixpkgs.config.allowUnfree = true;

  imports = [
    # Include the results of the hardware scan.
    <nixos-hardware/lenovo/thinkpad/p52>
    /etc/nixos/hardware-configuration.nix
  ];

  hardware.bluetooth.enable = true;

  #hardware.keyboard.zsa.enable = true; # For ZSA Live Training
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "moonlander_udev";
      text = ''
        SUBSYSTEMS=="usb", ATTRS{idVendor}=="3297", ATTRS{idProduct}=="1969", MODE="0666", TAG+="uaccess", SYMLINK+="stm32_dfu", GROUP="plugdev"
      '';
      destination = "/etc/udev/rules.d/50-zsa.rules";
    })
  ];

  # ZFS support
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  # Pin kernel to ZFS-compatible version to prevent build failures
  boot.kernelPackages = pkgs.linuxPackages;

  # ZFS maintenance
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # ZFS /nix mount
  fileSystems."/nix" = {
    device = "tank/nix";
    fsType = "zfs";
    neededForBoot = true;
  };

  boot.zfs.extraPools = ["tank"];

  fileSystems."/boot" = {
    device = lib.mkForce "/dev/disk/by-uuid/AC04-D43D";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 8;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
    algorithm = "zstd";
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 100; # aggressively use swap as pressure buffer, high swappiness with zram is good
    "vm.watermark_scale_factor" = 200; # start reclaim earlier
    "vm.page-cluster" = 0; # lower latency reclaim
  };

  # --- OOM setup
  systemd.oomd.enable = true;

  systemd.oomd.settings.OOM = {
    DefaultMemoryPressureLimit = "60%";
    DefaultMemoryPressureDurationSec = "30s";
    DefaultSwapUsedLimit = "90%";
  };

  # Ensure user sessions are protected, kill leaf services first
  systemd.user.extraConfig = ''
    ManagedOOMMemoryPressure=kill
    ManagedOOMSwap=kill
  '';
  # ---

  # Dropbox
  systemd.user.services.dropbox = {
    wantedBy = ["graphical-session.target"];
    unitConfig.RequiresMountsFor = ["/data/Dropbox"];
    environment = {
      QT_PLUGIN_PATH = "/run/current-system/sw/${pkgs.qt5.qtbase.qtPluginPrefix}";
      QML2_IMPORT_PATH = "/run/current-system/sw/${pkgs.qt5.qtbase.qtQmlPrefix}";
    };
    serviceConfig = {
      ExecStart = "${lib.getBin pkgs.dropbox}/bin/dropbox";
      ExecReload = "${lib.getBin pkgs.coreutils}/bin/kill -HUP $MAINPID";
      KillMode = "control-group";
      Restart = "on-failure";
      RestartSec = "3";
      PrivateTmp = true;
      ProtectSystem = "full";
      Nice = 10;
    };
  };

  # Fix for Apple keyboard
  # https://discourse.nixos.org/t/setting-sys-module-hid-apple-parameters-fnmode-to-0-at-boot/15570/4
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=0
  '';

  # networking.networkmanager.unmanaged = [ "*" "except:type:wwan" "except:type:gsm"];
  networking.hostId = "baddcafe"; # Must be set for zfs to work
  networking.hostName = "felix-nixos"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "Europe/Stockholm";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  # quad9 DNS https://quad9.net/
  networking.nameservers = ["9.9.9.9" "149.112.112.112"];

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "sv_SE.UTF-8";
    LC_IDENTIFICATION = "sv_SE.UTF-8";
    LC_MEASUREMENT = "sv_SE.UTF-8";
    LC_MONETARY = "sv_SE.UTF-8";
    LC_NAME = "sv_SE.UTF-8";
    LC_NUMERIC = "sv_SE.UTF-8";
    LC_PAPER = "sv_SE.UTF-8";
    LC_TELEPHONE = "sv_SE.UTF-8";
    LC_TIME = "sv_SE.UTF-8";
  };

  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  # };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.desktopManager.plasma6.enable = true;
  programs.ssh.askPassword = lib.mkForce "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
  services.xserver.xkb.options = "ctrl:swapcaps";

  # https://discourse.nixos.org/t/setting-caps-lock-as-ctrl-not-working/11952/3
  # Run this and reboot:
  # gsettings reset org.gnome.desktop.input-sources xkb-options
  # gsettings reset org.gnome.desktop.input-sources sources
  services.xserver.xkbOptions = "ctrl:swapcaps"; # READ the comment above!
  console.useXkbConfig = true;

  # Configure keymap in X11 services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  #  services.udev.extraRules = ''
  #  '';

  users.groups.plugdev = {};
  users.groups.podman-dev = {};

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.felix = {
    isNormalUser = true;
    home = "/home/felix";
    description = "Felix Holmgren";
    extraGroups = ["wheel" "networkmanager" "plugdev" "podman-dev"];
  };

  # Dedicated user for sandboxed container operations. Podman runs as this user
  # so containers can’t access felix’s home directory (SSH keys, credentials, etc.).
  # Unix file permissions do the enforcement — no sandbox code needed.
  # SECURITY INVARIANT: /home/felix must remain mode 700 (the NixOS default).
  # The bwrap-podman isolation depends on this — if bwrap-podman can traverse
  # /home/felix, the podman socket becomes a sandbox escape (containers could
  # volume-mount felix’s files).
  users.users.bwrap-podman = {
    isSystemUser = true;
    group = "podman-dev";
    home = "/var/lib/bwrap-podman";
    createHome = true;
  };

  users.users.bwrap-podman.subUidRanges = [{startUid = 200000; count = 65536;}];
  users.users.bwrap-podman.subGidRanges = [{startGid = 200000; count = 65536;}];
  users.users.bwrap-podman.linger = true;

  users.extraUsers.felix = {
    shell = pkgs.fish;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    alacritty
    bubblewrap # Low-level unprivileged sandboxing (for sandboxing)
    devenv
    gnomeExtensions.appindicator
    gnomeExtensions.cronomix
    discord
    earlyoom
    exercism
    #eyedropper
    file
    firefox
    #gimp
    gnome-tweaks
    gnumake
    goldendict-ng
    ungoogled-chromium
    # inkscape
    joplin-desktop
    libreoffice
    #ngrok
    openfortivpn
    #pijul
    # planify
    # ripcord
    #remmina
    unstable.signal-desktop
    slack
    socat # bidirectional data transfer (for sandboxing)
    #speedcrunch
    spotify
    squid # HTTP proxy for domain filtering (for sandboxing)
    sublime-merge
    # tuba
    # tutanota-desktop
    unixtools.ping
    #vlc
    wget
    # zoom-us

    # niri environment
    # niri
    # fuzzel
    # waybar
  ];

  programs.fish.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # creates 'docker' -> 'podman' symlink
    dockerSocket.enable = true;
  };

  # Podman API socket for sandboxed container operations.
  # Runs as bwrap-podman user service (via linger) so containers can't access
  # felix's files (/home/felix is 700). User service gives podman natural access
  # to its own systemd instance for healthcheck timers — no D-Bus bridging needed.
  systemd.tmpfiles.rules = [
    "d /run/bwrap-podman 0775 bwrap-podman podman-dev -"
  ];

  systemd.user.sockets.bwrap-podman = {
    wantedBy = ["sockets.target"];
    unitConfig.ConditionUser = "bwrap-podman";
    socketConfig = {
      ListenStream = "/run/bwrap-podman/podman.sock";
      SocketMode = "0666";
    };
  };

  systemd.user.services.bwrap-podman = {
    requires = ["bwrap-podman.socket"];
    unitConfig.ConditionUser = "bwrap-podman";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.podman}/bin/podman system service --time=0";
      Environment = [
        "PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        "CONTAINERS_CONF=/etc/bwrap-podman/containers.conf"
      ];
    };
  };

  # containers.conf for bwrap-podman
  environment.etc."bwrap-podman/containers.conf".text = ''
    [engine]
    cgroup_manager = "cgroupfs"
  '';

  virtualisation.containers.containersConf.settings = {
    engine = {
      compose_providers = ["${pkgs.docker-compose}/bin/docker-compose"];
      compose_warning_logs = false;
    };
  };

  # Rootless podman needs subuid/subgid ranges for user namespaces
  users.users.felix.subUidRanges = [{startUid = 100000; count = 65536;}];
  users.users.felix.subGidRanges = [{startGid = 100000; count = 65536;}];

  programs.ssh.extraConfig = ''
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # DVC VPN certificate
  security.pki.certificates = [
    ''
      -----BEGIN CERTIFICATE-----
      MIIDjzCCAnegAwIBAgIQFyPb1YwQILpL7T81QR5wNzANBgkqhkiG9w0BAQsFADBZ
      MRUwEwYKCZImiZPyLGQBGRYFbG9jYWwxFjAUBgoJkiaJk/IsZAEZFgZkdmMtY28x
      KDAmBgNVBAMTH0RWQyBDZXJ0aWZpY2F0ZSBBdXRob3JpdGl5IC0gRzEwIBcNMjQw
      NjExMDgzOTQ1WhgPMjA3NDA2MTEwODQ5NDVaMFkxFTATBgoJkiaJk/IsZAEZFgVs
      b2NhbDEWMBQGCgmSJomT8ixkARkWBmR2Yy1jbzEoMCYGA1UEAxMfRFZDIENlcnRp
      ZmljYXRlIEF1dGhvcml0aXkgLSBHMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
      AQoCggEBAMXbnUvLQ/NLi+XIMWNK+qaMHf+oKmOnB3F9GbUfQaYiflXUsz42nzf2
      csMNzRhi4PpgqGPhsw5trx8YxvC/dlnlhHBv5Lv43l+nmL2FY5HcLImDIjtKO7wZ
      NzF/5pidUb0kvIX0onVwP5tGzJaUhfW7yH4ye2yFcMtFMPPPmEPGdLoZljpK3QQA
      yunANkd+hi2/HWPYGacx2aQhKsZOvPyDXntXB/xTh4K5Bxv1sBBWeMLiXY6A6xYO
      xwajF4rjcNWkXNLlyGufK98/oMCevrDvxdZLKDznif1FjopNpexGli2pAFDBpl+y
      eUOTPDbd1oOIq2j+FXOyFGys2Z/Jq8UCAwEAAaNRME8wCwYDVR0PBAQDAgGGMA8G
      A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFD3wY7I8ItbfULsSUkjIF/bP1WRbMBAG
      CSsGAQQBgjcVAQQDAgEAMA0GCSqGSIb3DQEBCwUAA4IBAQBdU6Q23FcolHGZy3lD
      mE1GhxUpZgc0uQBZMjafsTfFlTYafGdaDGKt4+W33wERcZ/sMA46F4LiJRSs6KAi
      CZX5g2Ere7TByROrT0w1KT31NR+JdQf6AGwIz+xwlqKSuBRZa41h+uzTzxD7OEgX
      wyQ4YJfBMnQEG8IhiozWWOOUZ5S1iAB9nZY59x3Qw5Uzl/P7NQVLYaCwtwibZ7Ix
      q6vnuK1wypvMP2gNhSDuzc3d6HXmV+aHFs5wAyGzK2/CXJzSv9Hs88tfxHMCoHTo
      nYhz0ptUQyB/DoAShVwdrfgjPbCP7py/DE34P0HYKJwyQvsO6FXO0WYM+x96JuvW
      MACf
      -----END CERTIFICATE-----
    ''
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "21.11"; # Did you read the comment?
}
