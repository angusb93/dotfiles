# NixOS system config for the London NAS.
# Deploy: sudo nixos-rebuild switch --flake ~/dotfiles/nix#nas
{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "amd64_edac" ]; # ECC monitoring (PRO 4650G + ECC UDIMM)

  # --- Storage: ZFS on the 2TB NVMe (pool "fast" = fast NVMe app data / vault) ---
  # Named "fast" (not "tank") since it's the quick NVMe scratch drive; the future
  # 8TB HDD array can take a "tank"/bulk name. Root stays on ext4 (sda); this adds
  # ZFS support + auto-imports the data pool created on nvme0n1.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "fast" ]; # import the NVMe data pool at boot
  services.zfs.autoScrub.enable = true; # monthly integrity scrub
  services.zfs.trim.enable = true; # periodic SSD TRIM (NVMe health)

  # --- Syncthing: live two-way sync of the Obsidian vault (Mac <-> morty) ---
  # Runs as angus so it can read/write /fast/vault. GUI bound to localhost;
  # configure device/folder pairing via an SSH tunnel to :8384. Sync ports
  # (22000/tcp, 21027/udp) opened by openDefaultPorts.
  services.syncthing = {
    enable = true;
    user = "angus";
    group = "users";
    configDir = "/home/angus/.config/syncthing";
    dataDir = "/home/angus/.local/share/syncthing";
    openDefaultPorts = true;
    guiAddress = "127.0.0.1:8384";
  };

  # --- Personal agent: Telegram <-> Claude Code bridge (always-on) ---
  # Bridge + approval hook live in ~angus/telegram-agent (imperative for now;
  # candidate to move into its own repo like claw-agent later). This unit just
  # keeps it running across reboots, retiring the tmux session.
  systemd.services.telegram-agent = {
    description = "morty personal agent (Telegram <-> Claude Code bridge)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      python3
      claude-code
      uv
      nodejs_22
      git
      bash
      coreutils
      gnugrep
    ];
    serviceConfig = {
      User = "angus";
      Group = "users";
      WorkingDirectory = "/home/angus/telegram-agent";
      Environment = "HOME=/home/angus";
      ExecStart = "${pkgs.python3}/bin/python3 -u /home/angus/telegram-agent/bridge.py";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # --- Networking ---
  networking.hostName = "morty";
  networking.hostId = "c05f1be5"; # required by ZFS (identifies the pool's host)
  networking.networkmanager.enable = true;

  # --- Tailscale: remote access mesh (reach the NAS from phone / work laptop) ---
  # After deploy, run once: sudo tailscale up
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # --- A NAS must never sleep ---
  # Masks sleep at the systemd level, so it holds regardless of GNOME's
  # power settings (which suspended the box on idle before this).
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # --- Remote management: key-only SSH + passwordless sudo for wheel ---
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  security.sudo.wheelNeedsPassword = false;

  # --- Desktop ---
  # Kept for now; dropping GNOME for a lean headless NAS is a planned follow-up.
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # --- Shell ---
  programs.zsh.enable = true;

  # ssh forwards the client's TERM, so a Mac running ghostty arrives here as
  # TERM=xterm-ghostty. Without a matching terminfo entry zle cannot look up the
  # cursor-left capability and echoes a space for every backspace instead of
  # erasing, which makes the delete key append characters rather than remove
  # them. This installs the terminfo database for the common emulators (ghostty,
  # kitty, alacritty, wezterm, foot, tmux) so any client shell behaves.
  environment.enableAllTerminfo = true;

  # --- nix-ld: run prebuilt dynamic binaries on NixOS ---
  # The Claude Agent SDK bundles a prebuilt Claude Code binary; NixOS needs
  # nix-ld to provide a compatible dynamic linker for it (and for other
  # pip/npm-downloaded binaries).
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];

  # --- User ---
  users.users.angus = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "changeme";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPHOsJHKtJxBPCVrhttYSLcYm2Hy0SXoplKlrX0rJYH7"
    ];
  };

  # --- CLI environment (the reusable core, shared in spirit with the Mac) ---
  environment.systemPackages = with pkgs; [
    # shell & terminal
    bash
    btop
    fd
    fzf
    ripgrep
    sesh
    starship
    tmux
    zoxide
    # git
    gh
    git
    git-lfs
    lazygit
    stow
    # editor
    # nvim-treesitter's main branch compiles parsers on the box, and LazyVim
    # runs with mason disabled here, so the toolchain has to come from nix:
    # gcc supplies the cc that builds each parser, tree-sitter is the CLI it
    # shells out to. Without these nvim opens with an unmet-requirements popup.
    neovim
    gcc
    tree-sitter
    # runtimes / env
    mise
    direnv
    # personal-agent PoC (Claude Agent SDK)
    python3
    uv
    nodejs_22
    claude-code
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # Do not change after install (data-compat marker).
  system.stateVersion = "26.05";
}
