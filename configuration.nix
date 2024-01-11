# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
 
  nixpkgs.config.allowUnfree = true;

  imports =
    [ # Include the results of the hardware scan.
      /etc/nixos/hardware-configuration.nix
    ];

  hardware.pulseaudio.enable = true;
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

  # networking.networkmanager.unmanaged = [ "*" "except:type:wwan" "except:type:gsm"];
  networking.hostName = "felix-nixos"; # Define your hostname.
  networking.wireless.enable = false;  # Enables wireless support via wpa_supplicant.
  # For Prodigy dev
  networking.hosts = {
    "127.0.0.1" = ["sso.prodigygame.xyz"];
  };

  # Set your time zone.
  time.timeZone = "Europe/Stockholm";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp2s0.useDHCP = true;
  networking.interfaces.wlp3s0.useDHCP = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  # };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.xkbOptions = "ctrl:swapcaps";  
  console.useXkbConfig = true;

  # Configure keymap in X11 services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

#  services.udev.extraRules = ''
#  '';

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.felix = {
    isNormalUser = true;
    home = "/home/felix";
    description = "Felix Holmgren";
    extraGroups = [ "wheel" "networkmanager" "docker" "plugdev" ];
  };

  users.extraUsers.felix = {
    shell = pkgs.fish;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    alacritty
    discord
    dropbox
    exercism
    file
    firefox
    gimp
    gnumake
    google-chrome
    inkscape
    libreoffice
    ripcord
    signal-desktop
    slack
    speedcrunch
    spotify
    sublime-merge
    unixtools.ping
    vlc
    wget
    zoom-us
  ];

  programs.fish.enable = true;
 
  virtualisation.docker.enable = true;
  
  programs.ssh.extraConfig = ''
    Host tt-enspirit
      HostName 167.99.34.71
      User felix
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "21.11"; # Did you read the comment?

}

