# NixOS system config for the London NAS.
# Deploy: nixos-rebuild switch --sudo --flake ~/dotfiles/nix#nas
# (--sudo: the automations input is a private repo, so evaluation runs
#  as angus, whose SSH key GitHub knows, while activation still runs as root.)
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
  # The bridge, the approval hook, the check-in prompts and the systemd units
  # that run them all live together in the automations repo, so a code change
  # and the unit change it needs land in one commit:
  #   github.com/angusb93/automations -> apps/telegram-agent
  #
  # Only the machine-specific policy stays here: who it runs as, where the vault
  # is, and when the check-ins fire. Secrets and runtime state are NOT
  # declarative - they live in ~angus/telegram-agent (see the app README).
  #
  # NOTE ON TIME: morty's clock is UTC and Angus is in London, so every schedule
  # names the timezone explicitly. An unqualified "20:45" would fire at 21:45
  # BST - an hour later than intended for the whole of summer.
  services.telegram-agent = {
    enable = true;
    user = "angus";
    group = "users";
    vaultDir = "/fast/vault";

    checkins = {
      # Evening opens the nightly planning conversation, morning restates what
      # was agreed. Both post into the Planner forum topic so replies route back
      # to the same persona and continue the same claude session.
      # Design + the evidence behind it:
      #   /fast/vault/wiki/projects/life-balance-system.md
      #   /fast/vault/wiki/self/planning-psychology.md
      planner-evening = {
        description = "morty evening planning check-in";
        persona = "planner";
        mode = "evening";
        onCalendar = "*-*-* 20:45:00 Europe/London";
      };

      planner-morning = {
        description = "morty morning card";
        persona = "planner";
        mode = "morning";
        onCalendar = "*-*-* 07:30:00 Europe/London";
      };

      # The training plan silently drifting out of step with reality is the
      # failure these prevent: running-plan.md sat for six weeks claiming
      # "Week 3 of 13" while the actual training was 1.2 runs/week. So the daily
      # job is to write any new Garmin session into running-log.md, and the
      # weekly job is to make running-plan.md tell the truth about where the
      # block actually is.
      #
      # Daily runs at 20:00, before the 20:45 planner check-in, so the day's
      # training is already logged when the planner reads it. It stays SILENT
      # when there is nothing new - checkin.py suppresses a NOTHING reply.
      pt-daily = {
        description = "morty PT daily training sync";
        persona = "pt";
        mode = "daily";
        onCalendar = "*-*-* 20:00:00 Europe/London";
      };

      pt-weekly = {
        description = "morty PT weekly reconciliation";
        persona = "pt";
        mode = "weekly";
        onCalendar = "Sun *-*-* 19:00:00 Europe/London";
      };
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
