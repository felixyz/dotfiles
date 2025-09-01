# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  nix = {
    settings.trusted-users = ["root" "felix"];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
 
  nixpkgs.config.allowUnfree = true;

  imports =
    [ # Include the results of the hardware scan.
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

  # boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.systemd-boot.configurationLimit = 4;

  # Fix for Apple keyboard
  # https://discourse.nixos.org/t/setting-sys-module-hid-apple-parameters-fnmode-to-0-at-boot/15570/4
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=0
  '';

  # networking.networkmanager.unmanaged = [ "*" "except:type:wwan" "except:type:gsm"];
  networking.hostName = "felix-nixos"; # Define your hostname.
  networking.wireless.enable = false;  # Enables wireless support via wpa_supplicant.

  # Set your time zone.
  time.timeZone = "Europe/Stockholm";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  # quad9 DNS https://quad9.net/
  networking.nameservers = [ "9.9.9.9" "149.112.112.112" ];

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
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.displayManager.sessionPackages = with pkgs; [ niri ];

  # https://discourse.nixos.org/t/setting-caps-lock-as-ctrl-not-working/11952/3
  # Run this and reboot:
  # gsettings reset org.gnome.desktop.input-sources xkb-options
  # gsettings reset org.gnome.desktop.input-sources sources
  services.xserver.xkbOptions = "ctrl:swapcaps";  # READ the comment above!
  console.useXkbConfig = true;

  # Configure keymap in X11 services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

#  services.udev.extraRules = ''
#  '';

  users.groups.plugdev = {};

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.felix = {
    isNormalUser = true;
    home = "/home/felix";
    description = "Felix Holmgren";
    extraGroups = [ "wheel" "networkmanager" "docker" "plugdev"];
  };

  users.extraUsers.felix = {
    shell = pkgs.fish;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    alacritty
    #(import (fetchTarball https://install.devenv.sh/latest)).default
    gnomeExtensions.cronomix
    discord
    #dropbox
    earlyoom
    exercism
    #eyedropper
    file
    firefox
    #gimp
    gnome-tweaks
    gnumake
    goldendict-ng
    # google-chrome
    ungoogled-chromium
    # inkscape
    joplin-desktop
    #libreoffice
    #ngrok
    openfortivpn
    #pijul
    planify
    # ripcord
    #remmina
    #signal-desktop
    slack
    #speedcrunch
    #spotify
    sublime-merge
    # tuba
    unixtools.ping
    #vlc
    wget
    zed-editor
    # zfs
    # zoom-us

    # niri environment
    niri
    fuzzel
    waybar
  ];

  programs.fish.enable = true;
 
  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_27;
  };
  
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

