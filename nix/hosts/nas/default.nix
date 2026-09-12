# NixOS system config for the London NAS.
# Deploy: nixos-rebuild switch --sudo --flake ~/dotfiles/nix#nas
# (--sudo: the automations input is a private repo, so evaluation runs
#  as angus, whose SSH key GitHub knows, while activation still runs as root.)
{ lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [
    "amd64_edac" # ECC monitoring (PRO 4650G + ECC UDIMM)
    "nct6775" # B550M Pro4 Super I/O (NCT6798D): fan tach + PWM, not autoloaded
  ];

  # --- Storage: ZFS on the 2TB NVMe (pool "fast" = fast NVMe app data / vault) ---
  # Named "fast" (not "tank") since it's the quick NVMe scratch drive; the future
  # 8TB HDD array can take a "tank"/bulk name. Root stays on ext4 (sda); this adds
  # ZFS support + auto-imports the data pool created on nvme0n1.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "fast" ]; # import the NVMe data pool at boot
  services.zfs.autoScrub.enable = true; # monthly integrity scrub
  services.zfs.trim.enable = true; # periodic SSD TRIM (NVMe health)

  # --- Drive-chamber fans follow HDD temperature ---
  # The Sagittarius has two chambers. The drive-cage fans are on CHA_FAN2
  # (nct6798 pwm4), the motherboard-chamber fans on CHA_FAN3 (pwm5); both
  # pairs share one header each via splitters, so there is one tach per pair.
  # The BIOS curve keys off SYSTIN, a board sensor that cannot see the disks,
  # so the drive pair is driven from the hottest disk instead. pwm5 stays on
  # the BIOS curve.
  #
  # "scsi" selects every /dev/disk/by-id/scsi-* disk, i.e. exactly the SAS
  # drives on the HBA (the boot SSD is ata-*, the pool NVMe nvme-*), so a
  # replacement or the spare is picked up without editing this.
  #
  # PWM thresholds (start 76, stop 40) are hand-measured: `pwm-test` cannot
  # calibrate this pair because the splitter tach reads garbage (~5000 rpm)
  # once the fans stall below ~PWM 40. 76 is the BIOS floor and starts them
  # reliably. 20% minimum = PWM 83 ~= 655 rpm, fully on at 45C. He10 operating
  # limit is 60C, trip 65C. If the daemon dies the fans are left at 100%.
  services.hddfancontrol = {
    enable = true;
    # Upstream (2.1.2, and master as of 2026-09-11) cannot cope with parked
    # SAS drives (`sg_start --stop`), which is where these sit until the pool
    # exists. Two bugs, both patched:
    # - `sdparm --command=ready` prints "Not ready" but exits 2, and the status
    #   check runs before the output is parsed, so a parked drive is a probe
    #   failure rather than asleep. The daemon exited after 5 probes and left
    #   the fans at 100%.
    # - startup needs the drive model from `hdparm -I` or `smartctl -i`, both
    #   of which fail on a stopped drive, so the daemon could not start at all.
    #   Falls back to the model the kernel cached in sysfs.
    # With both, parked drives read as asleep and the fans hold at the floor.
    package = pkgs.hddfancontrol.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./hddfancontrol-parked-sas.patch ];
    });
    settings.drives = {
      disks = [ "scsi" ];
      pwmPaths = [ "$(echo /sys/devices/platform/nct6775.656/hwmon/hwmon*)/pwm4:76:40" ];
      extraArgs = [
        "--drive-temp-range 35 45"
        "--min-fan-speed-prct=20"
        "--interval=20s"
        "--temp-log=/var/lib/hddfancontrol/temps.jsonl"
        "--temp-log-max-files=90"
      ];
    };
  };
  systemd.services.hddfancontrol-drives.serviceConfig = {
    StateDirectory = "hddfancontrol";
    # On exit the fans go to 100%, which is safe but loud; come back rather
    # than stay there until someone notices.
    Restart = "on-failure";
    RestartSec = "30s";
  };
  # The module also starts the hddtemp daemon and hands it `disks` as its
  # device list, which here is the "scsi" selector rather than paths, so it
  # could not start. hddfancontrol invokes hddtemp per disk on its own.
  hardware.sensor.hddtemp.enable = lib.mkForce false;

  # --- Obsidian vault sync: obsidian-headless (replaced Syncthing 2026-08-20) ---
  # Syncthing used to hold the Mac <-> morty half of vault sync, with the Mac
  # bridging to Obsidian Sync for the phone. That made the laptop - the one
  # machine that is usually asleep - the relay for the always-on box, so agent
  # writes on morty only reached the phone once the Mac was opened.
  #
  # Obsidian shipped an official headless Sync client in Feb 2026, so morty is
  # now a first-class Obsidian Sync peer and the Mac is out of the path
  # entirely. Syncthing is therefore removed on BOTH halves (the Mac launchd
  # agent went at the same time).
  #
  # NOT YET DECLARATIVE: the client is installed per-user via npm
  # (~/.npm-global/bin/ob) and driven by user units in ~/.config/systemd/user:
  #   obsidian-sync.service          - `ob sync --continuous` against /fast/vault
  #   obsidian-sync-watchdog.timer   - restarts it when it silently stalls
  # It is not in nixpkgs yet. Packaging it with buildNpmPackage is the follow-up,
  # and until that lands this is exactly the undeclared-dependency shape that
  # bit syncthing twice. See wiki/concepts/infra/obsidian-headless-sync.md
  #
  # The watchdog is not optional: upstream issue #50 has `sync --continuous`
  # stalling at "Connecting..." while the process stays alive, so systemd's
  # Restart=on-failure never fires.

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

  # --- Claude Code Remote Control (always-on target for the phone) ---
  # `claude remote-control` registers morty as an environment on claude.ai/code,
  # so it shows up as a target in the mobile app and new sessions can be started
  # on it from anywhere. Sessions are spawned on demand in /fast/vault.
  #
  # It is the SUBCOMMAND, not the `--remote-control` flag. The flag only attaches
  # one interactive session to the bridge and never registers the machine, so the
  # phone sees no target and prompts sent to it queue up unserved. The subcommand
  # is hidden from `claude --help`; `claude remote-control --help` documents it.
  #
  # A user service rather than a system one: it needs angus's Claude credentials
  # in ~/.claude. Lingering is enabled for angus, so it still starts at boot with
  # nobody logged in.
  systemd.user.services.claude-remote-control = {
    description = "Claude Code Remote Control host for morty";
    wantedBy = [ "default.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # Never stop retrying - the point of the unit is to always be there.
    unitConfig.StartLimitIntervalSec = 0;
    # Stable profile path, not a /nix/store path, so spawned sessions keep a
    # working PATH across rebuilds. mkForce because the user-service module sets
    # its own minimal PATH; the system profile is a superset of it.
    environment.PATH = lib.mkForce "/run/current-system/sw/bin:/home/angus/.npm-global/bin";
    serviceConfig = {
      Type = "simple";
      # Must already be trusted in ~/.claude.json, or startup blocks forever on
      # the workspace trust dialog with nobody at a keyboard to answer it.
      # /home/angus is explicitly NOT trusted; /fast/vault is.
      WorkingDirectory = "/fast/vault";
      # This is a server, not a TUI - it runs fine with no controlling terminal.
      ExecStart = "${pkgs.claude-code}/bin/claude remote-control --name morty";
      Restart = "always";
      RestartSec = 5;
      RestartSteps = 5;
      RestartMaxDelaySec = 120;
      # Signal the server only. The shared claude daemon reparents to PID 1 but
      # stays in this unit's cgroup, and it supervises every other background
      # session on the machine - a cgroup-wide kill would take them all down.
      KillMode = "process";
      TimeoutStopSec = 30;
    };
  };

  # systemd only supervises the process, but what makes morty a target is the
  # bridge. Claude gives up on it permanently after ~10 minutes of connection
  # errors (bridge_poll_give_up) and then keeps running with nothing on the other
  # end - the unit looks healthy while the target has silently vanished, which is
  # the same shape as the obsidian-sync stall above. The bridge holds one
  # long-lived TLS connection, so its absence is the signal to restart.
  systemd.user.services.claude-remote-control-healthcheck = {
    description = "Verify the Claude Remote Control host is still connected";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "claude-rc-healthcheck";
          runtimeInputs = with pkgs; [
            systemd
            iproute2
            procps
            gnugrep
            coreutils
          ];
          text = ''
            unit=claude-remote-control.service
            state="''${XDG_RUNTIME_DIR:-/tmp}/claude-rc-health.state"

            if ! systemctl --user is-active --quiet "$unit"; then
              exit 0
            fi

            main_pid=$(systemctl --user show "$unit" -p MainPID --value)
            if [ -z "$main_pid" ] || [ "$main_pid" = "0" ]; then
              exit 0
            fi

            conns=$(ss -tnp 2>/dev/null | grep -c "pid=$main_pid," || true)
            if [ "$conns" -gt 0 ]; then
              rm -f "$state"
              exit 0
            fi

            # Never interrupt sessions that are actually doing work.
            if pgrep -P "$main_pid" >/dev/null 2>&1; then
              echo "no bridge connection, but spawned sessions are active; deferring restart"
              exit 0
            fi

            # Require two consecutive misses so a momentary reconnect between
            # long-poll requests cannot trigger a pointless restart.
            fails=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
            echo "$fails" > "$state"
            if [ "$fails" -lt 2 ]; then
              echo "no bridge connection (strike $fails); waiting one more cycle"
              exit 0
            fi

            echo "no bridge connection after $fails checks; restarting $unit"
            rm -f "$state"
            exec systemctl --user restart "$unit"
          '';
        }
      );
    };
  };

  systemd.user.timers.claude-remote-control-healthcheck = {
    description = "Check the Claude Remote Control host every 2 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "2min";
      AccuracySec = "15s";
      Unit = "claude-remote-control-healthcheck.service";
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
    # storage / disk diagnostics (the 8x SAS array + LSI 9201-8i HBA)
    # smartmontools: the He10s are used data-centre pulls, so power-on hours,
    # the grown defect list and non-medium error count are what decide whether
    # a drive goes in the array or back to the seller. Needed permanently, not
    # ad-hoc - services.smartd on top of this is the follow-up once the pool
    # exists and there is somewhere for its alerts to go.
    # sg3_utils: SCSI generic tools. sg_format is the escape hatch if a pull
    # turns up with 520-byte sectors or T10 protection that has to be stripped.
    # lsscsi + pciutils: see what is actually on the SAS bus and in the PCIe
    # slots. lspci was missing entirely, which made identifying the HBA harder
    # than it should have been.
    smartmontools
    sg3_utils
    lsscsi
    pciutils
    hdparm
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
