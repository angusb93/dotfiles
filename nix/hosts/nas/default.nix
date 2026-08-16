# NixOS system config for the London NAS.
# Deploy: sudo nixos-rebuild switch --flake ~/dotfiles/nix#nas
{ pkgs, ... }:

let
  # Everything the agent units need on PATH: python runs the bridge and the
  # check-ins, claude-code is the agent itself, uv launches the Garmin MCP
  # servers, node is claude-code's runtime.
  agentPath = with pkgs; [
    python3
    claude-code
    uv
    nodejs_22
    git
    bash
    coreutils
    gnugrep
  ];

  # --- Sandbox: bound what an autonomous agent can reach ---
  # Shared by every unit that runs claude-code, so the always-on bridge and the
  # scheduled planning check-ins cannot drift apart. They execute the same binary
  # with the same credentials, so a weaker sandbox on any one of them becomes the
  # new weakest link - defining this once is a security property, not tidiness.
  #
  # Context: these units run Claude with --dangerously-skip-permissions, gated
  # only by a best-effort, fail-open PreToolUse hook. They run as `angus`, and
  # `security.sudo.wheelNeedsPassword = false` below gives angus passwordless
  # root - so without this block the agent effectively has root.
  #
  # NoNewPrivileges is the load-bearing line: it stops the process tree from
  # gaining privileges via setuid binaries, which is how sudo works. Even if
  # the approval hook is bypassed, the agent cannot escalate.
  agentSandbox = {
    User = "angus";
    Group = "users";
    Environment = "HOME=/home/angus";

    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    RestrictSUIDSGID = true;

    # Read-only filesystem except the paths the agent genuinely writes to.
    # Enumerated generously on purpose: claude-code writes cache/config/state
    # under $HOME, and a missing path here is a silent runtime failure.
    # NOT setting ProtectHome - the bridge, its token and the agent's whole
    # state live under /home/angus, so protecting it would break the service.
    ProtectSystem = "strict";
    ReadWritePaths = [
      "/home/angus/telegram-agent"
      "/home/angus/.claude"
      "/home/angus/.cache"
      "/home/angus/.config"
      "/home/angus/.local"
      "/fast/vault"
    ];

    # ProtectSystem bounds writes but not reads, and the agent shares angus's
    # home - so mask the credential stores explicitly. This gets most of the
    # benefit of a dedicated service user without migrating the agent's Claude
    # auth and vault ownership, which is a riskier change done separately.
    # Verified safe: bridge.py, approve-hook.py and checkin.py contain no git/
    # ssh/push/clone/remote references against these paths, and the vault is not
    # a git repo, so the agent has no reason to touch any of them.
    # Note .config is in ReadWritePaths above for claude-code's state, which
    # is exactly why gh and syncthing need masking rather than being left to
    # inherit it.
    # The systemd entries close an escape hatch created by making .config and
    # .local writable above: a user unit dropped in ~/.config/systemd/user
    # runs under the *user* manager, which is a separate process tree and does
    # NOT inherit this unit's NoNewPrivileges - so it could sudo freely. Same
    # reasoning for ~/.local/bin, which can shadow binaries on angus's PATH.
    # The "-" prefix marks each path optional. Without it, systemd fails
    # namespace setup with 226/NAMESPACE if the path does not exist, taking the
    # whole service down - which is exactly what happened on 2026-08-15 when
    # ~/.config/systemd was masked before it existed.
    InaccessiblePaths = [
      "-/home/angus/.ssh"
      "-/home/angus/.config/gh"
      "-/home/angus/.config/syncthing"
      "-/home/angus/.config/systemd"
      "-/home/angus/.local/share/systemd"
      "-/home/angus/.local/bin"
    ];

    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    RestrictRealtime = true;
    LockPersonality = true;
    # Deliberately NOT set: RestrictNamespaces, MemoryDenyWriteExecute,
    # SystemCallFilter. Each can break claude-code's own sandboxing or the
    # Node JIT, and the value here is bounding privilege, not syscalls.
  };
in

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
    path = agentPath;
    serviceConfig = agentSandbox // {
      WorkingDirectory = "/home/angus/telegram-agent";
      ExecStart = "${pkgs.python3}/bin/python3 -u /home/angus/telegram-agent/bridge.py";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # --- Planning check-ins ---
  # Evening opens the nightly planning conversation, morning restates what was
  # agreed. Both run checkin.py, which posts into the Planner forum topic so
  # replies route back to the same persona and continue the same claude session.
  # Design + the evidence behind it:
  #   /fast/vault/wiki/projects/life-balance-system.md
  #   /fast/vault/wiki/self/planning-psychology.md
  #
  # These reuse agentSandbox deliberately: same binary, same credentials, same
  # blast radius as the bridge, so they get the same bounds.
  #
  # NOTE ON TIME: morty's clock is UTC and Angus is in London, so the timezone
  # is named explicitly. An unqualified "20:45" would fire at 21:45 BST - an
  # hour later than intended for the whole of summer.
  systemd.services.morty-checkin = {
    description = "morty evening planning check-in";
    after = [ "network-online.target" "telegram-agent.service" ];
    wants = [ "network-online.target" ];
    path = agentPath;
    serviceConfig = agentSandbox // {
      Type = "oneshot";
      WorkingDirectory = "/home/angus/telegram-agent";
      ExecStart = "${pkgs.python3}/bin/python3 -u /home/angus/telegram-agent/checkin.py planner evening";
      # MCP round-trips make this slow; checkin.py caps claude at 30 min itself.
      TimeoutStartSec = "35min";
    };
  };

  systemd.timers.morty-checkin = {
    description = "Nightly planning check-in at 20:45 London";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 20:45:00 Europe/London";
      # Deliberately not Persistent: a missed check-in is worthless later, and a
      # 3am "plan your day" push after a reboot is how a system gets muted.
      Persistent = false;
    };
  };

  systemd.services.morty-morning = {
    description = "morty morning card";
    after = [ "network-online.target" "telegram-agent.service" ];
    wants = [ "network-online.target" ];
    path = agentPath;
    serviceConfig = agentSandbox // {
      Type = "oneshot";
      WorkingDirectory = "/home/angus/telegram-agent";
      ExecStart = "${pkgs.python3}/bin/python3 -u /home/angus/telegram-agent/checkin.py planner morning";
      TimeoutStartSec = "35min";
    };
  };

  systemd.timers.morty-morning = {
    description = "Morning card at 07:30 London";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 07:30:00 Europe/London";
      Persistent = false;
    };
  };

  # --- PT check-ins ---
  # The training plan silently drifting out of step with reality is the failure
  # these prevent: running-plan.md sat for six weeks claiming "Week 3 of 13"
  # while the actual training was 1.2 runs/week. So the daily job is to write
  # any new Garmin session into running-log.md, and the weekly job is to make
  # running-plan.md tell the truth about where the block actually is.
  #
  # Daily runs at 20:00, before the 20:45 planner check-in, so the day's
  # training is already logged when the planner reads it. It stays SILENT when
  # there is nothing new - checkin.py suppresses a NOTHING reply.
  systemd.services.morty-pt-daily = {
    description = "morty PT daily training sync";
    after = [ "network-online.target" "telegram-agent.service" ];
    wants = [ "network-online.target" ];
    path = agentPath;
    serviceConfig = agentSandbox // {
      Type = "oneshot";
      WorkingDirectory = "/home/angus/telegram-agent";
      ExecStart = "${pkgs.python3}/bin/python3 -u /home/angus/telegram-agent/checkin.py pt daily";
      TimeoutStartSec = "35min";
    };
  };

  systemd.timers.morty-pt-daily = {
    description = "PT training sync at 20:00 London";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 20:00:00 Europe/London";
      Persistent = false;
    };
  };

  systemd.services.morty-pt-weekly = {
    description = "morty PT weekly reconciliation";
    after = [ "network-online.target" "telegram-agent.service" ];
    wants = [ "network-online.target" ];
    path = agentPath;
    serviceConfig = agentSandbox // {
      Type = "oneshot";
      WorkingDirectory = "/home/angus/telegram-agent";
      ExecStart = "${pkgs.python3}/bin/python3 -u /home/angus/telegram-agent/checkin.py pt weekly";
      TimeoutStartSec = "35min";
    };
  };

  systemd.timers.morty-pt-weekly = {
    description = "PT weekly reconciliation, Sunday 19:00 London";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 19:00:00 Europe/London";
      Persistent = false;
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
