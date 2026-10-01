# NixOS system config for the London NAS.
# Deploy: nixos-rebuild switch --sudo --flake ~/dotfiles/nix#nas
# (--sudo: the automations input is a private repo, so evaluation runs
#  as angus, whose SSH key GitHub knows, while activation still runs as root.)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # One way for anything on morty to reach Angus: `morty-alert SUBJECT` with the
  # body on stdin, posted by the telegram-agent bot into the "🚨 Alerts" topic
  # of the morty group.
  #
  # The topic's ids live in alerts.json in the bridge's state dir, deliberately
  # not in threads.json: that map is persona routing, and the bridge's /setup
  # rewrites it. A reply typed in the Alerts topic goes to the general persona,
  # so "what does this mean?" gets an answer. If alerts.json is missing the
  # alert falls back to Angus's DM rather than going nowhere.
  #
  # The bot token is read from the same state dir, so this runs as root (zed
  # and smartd both do). When S3 of the security plan moves bridge secrets into
  # 1Password, this has to move with them.
  #
  # The token goes to curl on stdin (--config -), never in argv, so it cannot
  # be read from the process list.
  morty-alert = pkgs.writeShellApplication {
    name = "morty-alert";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      util-linux
    ];
    text = ''
      subject=''${1:?usage: morty-alert SUBJECT < body}
      state=/var/lib/agent/telegram-agent

      # Telegram caps a message at 4096 characters.
      body=$(head -c 3500)
      text=$(printf '🚨 %s\n\n%s' "$subject" "$body")

      target=()
      if chat=$(jq -er .chat_id "$state/alerts.json" 2>/dev/null) \
        && thread=$(jq -er .thread_id "$state/alerts.json" 2>/dev/null); then
        target=(--data-urlencode "chat_id=$chat" --data-urlencode "message_thread_id=$thread")
      else
        logger -p daemon.warning -t morty-alert "no usable $state/alerts.json; sending to the owner DM"
        target=(--data-urlencode "chat_id=$(cat "$state/owner")")
      fi

      if ! printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$(cat "$state/token")" \
        | curl --silent --show-error --fail --max-time 20 --retry 3 --retry-all-errors \
            --config - \
            "''${target[@]}" \
            --data-urlencode "text=$text" >/dev/null; then
        logger -p daemon.err -t morty-alert "Telegram delivery FAILED: $subject"
        exit 1
      fi
      logger -p daemon.notice -t morty-alert "sent: $subject"
    '';
  };

  # smartd's `-M exec` hook. smartd names the kernel device (/dev/sdb), which
  # reshuffles between boots, so the alert also carries the stable by-id names.
  # The WWN is what the bay map in the vault joins to a tray label.
  smartd-alert = pkgs.writeShellApplication {
    name = "smartd-alert";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      config.boot.zfs.package
      morty-alert
    ];
    text = ''
      dev=''${SMARTD_DEVICE##*/}
      ids=$(find /dev/disk/by-id -lname "*/$dev" -printf '%f\n' 2>/dev/null | sort || true)
      {
        echo "''${SMARTD_FULLMESSAGE:-''${SMARTD_MESSAGE:-}}"
        echo
        echo "device:  ''${SMARTD_DEVICESTRING:-$SMARTD_DEVICE}"
        echo "failure: ''${SMARTD_FAILTYPE:-unknown}"
        echo "by-id:"
        echo "''${ids:-  (none found)}"
        echo
        echo "Map the WWN to a tray with the bay table in wiki/projects/home-lab.md,"
        echo "and confirm against zpool status before pulling anything."
        echo
        zpool status -x
      } | morty-alert "''${SMARTD_SUBJECT:-SMART warning on morty}"
    '';
  };

  # Every smartd entry runs the same checks, the same self-test schedule and
  # the same alert hook. Only -W differs, so the thresholds stay out of here.
  smartd-common = [
    "-a"
    "-s (S/../.././02|L/../15/./03)"
    "-m <nomailer>"
    "-M exec ${lib.getExe smartd-alert}"
    "-M daily"
  ];

  smartd-nvme = lib.concatStringsSep " " (
    smartd-common
    ++ [
      "-d nvme"
      "-W 0,70,75"
    ]
  );
in
{
  imports = [
    ./hardware-configuration.nix
    ./backup.nix
    ./snapshots.nix
    ./google-pull.nix
    ./gmail-pull.nix
    ./kiwix.nix
    ./kiwix-fetch.nix
    ./immich.nix
    ./media.nix
    ./agent.nix
    ./tv.nix
    ./vpn.nix
    ./homepage.nix
    ./uptime-kuma.nix
    ./paperless.nix
    ./paperless-ingest.nix
    ./staleness.nix
  ];

  # morty-alert is defined in the let above and used by smartd and ZED here.
  # staleness.nix needs the same one-way channel to Angus, so pass it as a
  # module argument rather than building a second copy of it.
  _module.args.morty-alert = morty-alert;

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Encrypted root (storage-migration 1.5) - uncomment on the live USB, after
  # nixos-generate-config has written the "cryptroot" device into
  # hardware-configuration.nix. Declaring these without that device fails to
  # evaluate, which is why they cannot land before the reinstall.
  boot.initrd.systemd.enable = true; # required for TPM2 unlock
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "tpm2-device=auto" ];
  boot.kernelModules = [
    "amd64_edac" # ECC monitoring (PRO 4650G + ECC UDIMM)
    "nct6775" # B550M Pro4 Super I/O (NCT6798D): fan tach + PWM, not autoloaded
  ];

  # --- Storage: ZFS on the 4TB KIOXIA NVMe (pool "fast" = fast NVMe app data / vault) ---
  # Named "fast" (not "tank") since it's the quick NVMe drive; the 8TB HDD
  # array is "tank". Root is ext4 inside LUKS2 on the Intel 660p (M2_2),
  # unlocked by TPM2; this adds ZFS support and auto-imports both data pools.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [
    "fast" # 4TB KIOXIA NVMe (M2_1): app data, the vault
    "tank" # 6x HGST He10 8TB SAS (D1-D6), RAIDZ2, ~29TB: bulk storage
  ];
  # Both pools are natively encrypted (aes-256-gcm) from the pool root down,
  # each with its own 64-char hex key at /etc/zfs/keys/{tank,fast}.key (root
  # 0400) on the encrypted root - deliberately NOT in this flake, since they
  # are secrets - with copies in 1Password ("Morty drive encryption key",
  # "morty fast pool key"); lose both copies and that pool is unrecoverable. It is loaded at import
  # by boot.zfs.requestEncryptionCredentials (default true), so both unlock
  # unattended. This protects drives that leave the house (RMA, resale,
  # disposal), not theft of the whole box.
  # Created 2026-09-13 with: ashift=12 compression=zstd atime=off xattr=sa
  # acltype=posixacl dnodesize=auto, members by /dev/disk/by-id/wwn-*.
  # No spindown (yet): RAIDZ wakes all six at once, a runtime surge the single
  # backplane Molex cable should not carry. Revisit after the second cable.

  # The 26.11 default. Never force-import a pool that looks claimed by another
  # host - a force import there risks corrupting it.
  boot.zfs.forceImportRoot = false;
  services.zfs.autoScrub.enable = true; # monthly integrity scrub
  services.zfs.trim.enable = true; # periodic SSD TRIM (NVMe health)

  # --- Dead-disk alerts, to Telegram ---
  # A RAIDZ2 that loses a drive keeps serving data, so without an alert it looks
  # exactly like a healthy one until the next two drives go. And all six are
  # one batch, so correlated failures are the expected shape, not the unlucky one.
  # Two sources, both delivered by morty-alert above:
  #
  # ZED reports what ZFS itself sees: a vdev FAULTED, DEGRADED, REMOVED or
  # UNAVAIL, checksum and I/O errors, and a scrub or resilver that finished
  # with errors. ZED only knows how to email, so morty-alert stands in as the
  # "mail program": with @SUBJECT@ in the options the subject arrives as $1 and
  # the body on stdin. ZED_EMAIL_ADDR is never used, but ZED skips email
  # entirely without one. Repeats are rate-limited per event (ZED default, 1h).
  services.zfs.zed.settings = {
    ZED_EMAIL_ADDR = "angus";
    ZED_EMAIL_PROG = lib.getExe morty-alert;
    ZED_EMAIL_OPTS = "'@SUBJECT@'";
  };

  # smartd reports what the drives say before ZFS notices: SMART health failing,
  # a growing defect list, failed self-tests, over-temperature. It scans every
  # disk: the six SAS drives, plus the two NVMe (Intel 660p boot, KIOXIA pool).
  # - `-s`: short self-test daily at 02:00, long self-test on the 15th at 03:00,
  #   clear of the monthly scrub on the 1st. A long test is a full sequential
  #   read, about 12h per drive, and the drives run it in parallel.
  # - `-M daily`: repeat a standing problem once a day rather than only once.
  # No `-o on`: that is ATA-only.
  #
  # `-W DIFF,INFO,CRIT` is per drive class, because flash and spinning rust do
  # not share a temperature scale:
  # - SAS (via DEVICESCAN), 50/55: the He10s are rated to 60C and the fan curve
  #   is flat out at 45C, so 55C means cooling has failed.
  # - NVMe (listed explicitly), 70/75: the boot SSD idles at 27C but touches
  #   56C most nights with nothing running, and the pool NVMe sits at ~46C
  #   constantly. Both are unremarkable for flash - the kernel reports
  #   composite critical at 79.85C for the 660p and 84.85C for the KIOXIA - but
  #   50/55 alerted on them nightly, which is how a monitor gets ignored.
  #
  # The explicit entries come before DEVICESCAN, which then covers the SAS
  # drives. Worth a look after a drive change: `journalctl -u smartd | grep
  # 'Adding to'` should list each device exactly once.
  services.smartd = {
    enable = true;
    autodetect = true;
    # The module turns X11 popups on whenever xserver is enabled (GNOME, here),
    # and that injects its own `-m`/`-M exec` ahead of ours on every line.
    notifications.x11.enable = false;
    notifications.wall.enable = false;
    devices = [
      {
        device = "/dev/nvme0";
        options = smartd-nvme;
      }
      {
        device = "/dev/nvme1";
        options = smartd-nvme;
      }
    ];
    defaults.autodetected = lib.concatStringsSep " " (
      smartd-common
      ++ [
        "-W 0,50,55"
      ]
    );
  };

  # --- Drive-chamber fans follow HDD temperature ---
  # The Sagittarius has two chambers. The drive-cage fans are on CHA_FAN2
  # (nct6798 pwm4), the motherboard-chamber fans on CHA_FAN3 (pwm5); both
  # pairs share one header each via splitters, so there is one tach per pair.
  # The BIOS curve keys off SYSTIN, a board sensor that cannot see the disks,
  # so the drive pair is driven from the hottest disk instead. pwm5 stays on
  # the BIOS curve.
  #
  # "scsi" selects every /dev/disk/by-id/scsi-* disk, i.e. exactly the SAS
  # drives on the HBA (the boot and pool NVMe are both nvme-*), so a
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

  # --- Power: SAS drive idle states and PCIe ASPM (2026-09-24) ---
  # The He10s shipped with every power condition timer off, so they sat in
  # full active idle forever. These are not spindown: IDLE_A idles the
  # electronics (2s), IDLE_B unloads the heads (2min), IDLE_C also drops RPM
  # (10min). Recovery is sub-second from B and a few seconds from C, and none
  # of it wakes all six at once the way a spin-up does, so it does not need the
  # second backplane cable. Set without --save, so the drives' own NVRAM stays
  # at factory and this rule is the only source of truth; re-applied on every
  # add, so a replacement drive picks it up. Load/unload budget is 600k; the
  # baseline on 2026-09-24 was ~2,790 per drive - watch it in smartctl.
  # Measured 2026-09-24 (sg_logs -p 0x1a): these NE03-firmware drives enter
  # IDLE_A and stay there through hddfancontrol's polling, but never enter
  # IDLE_B or IDLE_C - not with 10s timers, not with PM_BG=2, not with the fan
  # controller and smartd stopped. Almost certainly OEM firmware. Kept on
  # because they are harmless here and take effect on a replacement drive.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ATTRS{model}=="HUH721008AL5204*", RUN+="${pkgs.sdparm}/bin/sdparm --quiet --page=po --set=IDLE_A=1,IACT=20,IDLE_B=1,IBCT=1200,IDLE_C=1,ICCT=6000 $devnode"
    # Realtek RTL8111 (enp5s0): r8169 leaves L1 off by default. Tested stable
    # on this rev 15 chip 2026-09-24; if the NIC ever drops, this is the first
    # suspect.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10ec", ATTR{device}=="0x8168", ATTR{link/l1_aspm}="1"
  '';
  # Kernel-managed ASPM with L1 substates wherever a link supports it. The
  # KIOXIA stays at L0 regardless: its CPU root port (00:02.2) reports ASPM
  # unsupported, which is firmware, not Linux.
  boot.kernelParams = [ "pcie_aspm.policy=powersupersave" ];

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

    # Runs as its own user since 2026-09-29, not as `angus` - see agent.nix
    # for the reasoning, including the correction that this unit could never
    # have used sudo anyway: NoNewPrivileges blocks setuid.
    #
    # The masking list that used to live here has gone with it. It existed to
    # keep a Telegram-driven session out of ~angus/.config/op, which unlocks
    # the whole 1Password Morty vault. Separate homes mean there is nothing
    # left to mask - the agent cannot see that directory at all.
    user = "agent";
    group = "agent";
    homeDir = "/var/lib/agent";
    stateDir = "/var/lib/agent/telegram-agent";
    vaultDir = "/fast/vault";

    checkins = {
      # TWO pushes, deliberately: one a day, and one per workout.
      #
      # This replaced four scheduled messages (planner evening + morning, pt
      # daily + weekly) on 2026-09-30. Four fixed pushes a day arrive whether or
      # not they have anything to say, and a check-in that does that is how
      # these get muted. The 07:30 morning card restated what was already on the
      # calendar, and pt-daily asked about training at 20:00 whether or not any
      # had happened.
      #
      # Design + the evidence behind it:
      #   /fast/vault/wiki/projects/life-balance-system.md
      #   /fast/vault/wiki/self/planning-psychology.md
      #   /fast/vault/wiki/projects/marathon-periodization.md  (the weekly rule)

      # The one scheduled message of the day. Decides tomorrow and writes it
      # straight to the Planning calendar rather than opening with a question -
      # composing an answer costs Angus more than editing a draft, and lowering
      # that cost is the whole point. Also logs the day's training, and on
      # Sundays runs the weekly GREEN/AMBER/RED reconciliation that keeps
      # running-plan.md honest.
      daily = {
        description = "morty daily message";
        persona = "planner";
        mode = "daily";
        onCalendar = "*-*-* 20:45:00 Europe/London";
      };

      # One response per workout. Event-driven in effect, polled in
      # implementation: Garmin is only reachable through the MCP tools inside a
      # claude session, so there is nothing to subscribe to from systemd. It
      # runs hourly and the silence guard does the work - checkin.py drops a
      # NOTHING reply, so on a normal day this fires 16 times and sends nothing,
      # then sends once shortly after a run or a lift appears in Garmin.
      # Bounded to waking hours to keep that cost sane.
      activity = {
        description = "morty per-workout response";
        persona = "pt";
        mode = "activity";
        onCalendar = "*-*-* 06..22:00:00 Europe/London";
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
    # systemd.user units are enabled for every user manager, including the
    # gdm-greeter one, where there are no Claude credentials and the unit
    # crash-loops on "You must be logged in to use Remote Control".
    unitConfig.ConditionUser = "angus";
    # Stable profile path, not a /nix/store path, so spawned sessions keep a
    # working PATH across rebuilds. mkForce because the user-service module sets
    # its own minimal PATH; the system profile is a superset of it.
    # /run/wrappers/bin first: it holds the setuid sudo. Without it, sessions
    # resolve sw/bin's plain sudo, which fails with "must be owned by uid 0".
    environment.PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:/home/angus/.npm-global/bin";
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
    unitConfig.ConditionUser = "angus";
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
    unitConfig.ConditionUser = "angus";
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "2min";
      AccuracySec = "15s";
      Unit = "claude-remote-control-healthcheck.service";
    };
  };

  # --- paseo: supervise the coding agents so the phone can drive them ---
  # paseo ships no agent of its own. It launches the first-party CLIs already on
  # the box - pi, claude-code - as ordinary subprocesses, streams their output,
  # and gives desktop/web/mobile clients a way to steer them. That is what makes
  # it the replacement for opencode here: opencode was an agent you had to be sat
  # at a terminal to use, and this is the same work driven from anywhere.
  #
  # It listens on loopback only and is reached through `paseo daemon pair
  # --relay`, which is end-to-end encrypted, so no port is published to the LAN
  # or the tailnet. Pairing is interactive and one-time:
  #   systemctl --user start paseo
  #   paseo daemon pair --relay
  # then open the offer URL it prints on the phone.
  #
  # The agents this launches run as angus, who still has NOPASSWD: ALL. Until the
  # agent-user work lands, a paired client is root on morty in practice - which
  # is exactly why it is not bound to a network interface.
  #
  # A user service, like claude-remote-control above: it needs angus's agent
  # credentials in ~/.claude and ~/.config/pi. Lingering is enabled for angus, so
  # it starts at boot with nobody logged in.
  systemd.user.services.paseo = {
    description = "paseo agent supervisor for morty";
    wantedBy = [ "default.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # Never stop retrying - the point of the unit is to always be there.
    unitConfig.StartLimitIntervalSec = 0;
    # As with claude-remote-control: user units are enabled for every user
    # manager, including the gdm-greeter one, which has no agent credentials.
    unitConfig.ConditionUser = "angus";
    environment = {
      PASEO_HOME = "/home/angus/.paseo";
      # Both default to on with the "local" provider, which makes the daemon
      # download ~700 MB of sherpa speech models (parakeet, kokoro) in the
      # background the first time it starts. Nothing on a headless NAS dictates
      # into it, and that download would compete with the Google pulls.
      PASEO_VOICE_MODE_ENABLED = "false";
      PASEO_DICTATION_ENABLED = "false";
      # Stable profile path, not a /nix/store path, so the agents paseo spawns
      # keep a working PATH across rebuilds - paseo resolves `pi` and `claude`
      # from it. /run/wrappers/bin first: it holds the setuid sudo.
      PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:/home/angus/.npm-global/bin";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/fast/vault";
      # paseo keeps its settings in $PASEO_HOME/config.json, which it writes
      # itself (pairing keys, daemon state), so the file cannot simply be a
      # symlink into this repo. Re-asserting the parts that matter on every start
      # is the declarative equivalent: a fresh morty comes up configured, and a
      # client that changed one of them gets corrected on the next restart.
      #
      # The provider block exists for exactly one reason: paseo's built-in
      # default model for pi is claude-3-haiku, which Anthropic deprecated on
      # 2026-09-10 - every agent errored with a 404 until a default was set.
      # It deliberately does NOT enumerate models; see the comment on the block.
      # The JSON goes through a file so no shell quoting has to survive Nix
      # string escaping.
      ExecStartPre = lib.getExe (
        pkgs.writeShellApplication {
          name = "paseo-config";
          runtimeInputs = [ pkgs.paseo ];
          text =
            let
              providers = pkgs.writeText "paseo-providers.json" (
                builtins.toJSON {
                  pi = {
                    extends = "pi";
                    label = "pi (OpenRouter)";
                    # `additionalModels`, never `models`. They are not variants of
                    # one setting: in provider-registry.js, a non-empty `models`
                    # is a REPLACEMENT for pi's discovered catalogue (the code
                    # returns profileModels and throws the base list away, and
                    # `profileModelsAreAdditive` is hardcoded false in 0.9.1 with
                    # no config key to flip it). `additionalModels` merges into
                    # that catalogue by id instead.
                    #
                    # pi already knows every OpenRouter model - 398 of them in
                    # ~/.pi/agent/models-store.json, refreshed by `pi update` -
                    # and paseo asks it for the list at runtime. So nothing here
                    # needs to enumerate models. Listing three of them is how the
                    # phone ended up with a three-item picker.
                    #
                    # The single entry exists only to move the default off
                    # claude-3-haiku, which Anthropic deprecated on 2026-09-10 and
                    # which 404s every new agent. One `isDefault = true` addition
                    # is enough: mergeModelAdditions rewrites isDefault to false on
                    # everything else, so this wins without hiding anything.
                    #
                    # `label` is required by the config schema even here, where
                    # the entry only carries a default - omitting it makes
                    # `paseo daemon config set` reject the whole file and the unit
                    # refuses to start. It fails loudly, which is the good case.
                    additionalModels = [
                      {
                        id = "openrouter/anthropic/claude-sonnet-5";
                        label = "Sonnet 5";
                        isDefault = true;
                      }
                    ];
                  };
                }
              );
            in
            ''
              # Loopback only. Making this routable is a security decision, not a
              # convenience one - see above. Moved off paseo's own default 6767
              # because Bazarr also defaults there and its NixOS module exposes
              # no port option - so paseo is the one that can move. The CLI
              # needs --host for anything not on the default now.
              paseo daemon config set --string daemon.listen 127.0.0.1:6799
              paseo daemon config set agents.providers "$(cat ${providers})"
            '';
        }
      );
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "paseo-daemon";
          runtimeInputs = with pkgs; [
            paseo
            _1password-cli
            coreutils
          ];
          # pi reads OPENROUTER_API_KEY and registers the OpenRouter provider
          # from it. A daemon has no interactive shell, so the zshrc wrapper
          # cannot help here: resolve the key once at start and let paseo pass it
          # down to the agents it launches. Failing to read it is not fatal -
          # claude-code sessions authenticate through ~/.claude and still work.
          text = ''
            token_file="$HOME/.config/op/service-account-token"
            key_ref="op://6ozvud25wxpywiml26e3a53hxu/esxkxlfzue6n6iwnk6s4udvmp4/credential"

            if [ -s "$token_file" ]; then
              if key=$(OP_SERVICE_ACCOUNT_TOKEN="$(cat "$token_file")" \
                         op read --no-newline "$key_ref" 2>/dev/null); then
                export OPENROUTER_API_KEY="$key"
              else
                echo "could not read the OpenRouter key from 1Password; starting without it" >&2
              fi
            else
              echo "no 1Password service account token at $token_file; starting without OpenRouter" >&2
            fi

            mkdir -p "$PASEO_HOME"

            # `paseo daemon run` is broken in 0.9.1: the published package names
            # ./dist/server/server/exports.js as @getpaseo/server's entry point
            # but never ships that file, so the CLI subcommands that load the
            # server module die on "Cannot find module". paseo-server is the
            # supervisor entrypoint `daemon run` wraps and it starts fine; the
            # rest of the CLI (status, pair, config, run) talks to the daemon
            # over $PASEO_HOME and is unaffected. Revisit when nixpkgs carries a
            # fixed paseo.
            exec paseo-server
          '';
        }
      );
      Restart = "always";
      RestartSec = 5;
      RestartSteps = 5;
      RestartMaxDelaySec = 120;
      # Unlike claude-remote-control, the whole cgroup goes: paseo *is* the
      # supervisor of the agents it starts, so leaving them behind a dead daemon
      # would strand sessions no client can reach. A rebuild that changes this
      # unit therefore ends any live paseo session.
      TimeoutStopSec = 30;
    };
  };

  # Angus is in London, and two things here render in the server's local
  # timezone rather than his: Immich's storage template, which decides the dated
  # folder a photo is filed under, and every timestamp in the journal. On UTC a
  # photo taken at 00:30 BST files under the previous day, permanently, unless
  # the storage-template migration is re-run. The backup timers move with it,
  # which is what was wanted anyway - 02:00 should mean 2am where Angus sleeps,
  # not 2am in a timezone the machine happens to default to.
  time.timeZone = "Europe/London";

  # --- Networking ---
  networking.hostName = "morty";
  networking.hostId = "c05f1be5"; # required by ZFS (identifies the pool's host)
  networking.networkmanager.enable = true;

  # --- Tailscale: remote access mesh (reach the NAS from phone / work laptop) ---
  # After deploy, run once: sudo tailscale up
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  # The tailnet registered this machine as "nas" from an older hostname, so
  # http://morty:8090 resolved to nothing while every doc said to use it.
  # `tailscale set` is re-applied on every rebuild, so the name cannot drift
  # back. Note extraUpFlags would not do: it only fires when authKeyFile is set,
  # and this machine was brought up by hand.
  services.tailscale.extraSetFlags = [ "--hostname=morty" ];

  # --- A NAS must never sleep ---
  # Masks sleep at the systemd level, so it holds regardless of GNOME's
  # power settings (which suspended the box on idle before this).
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # --- Remote management: key-only SSH + passwordless sudo for wheel ---
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    # PasswordAuthentication alone is not key-only. With PAM, keyboard-interactive
    # still prompts for the account password, and NixOS leaves it on by default:
    # until 2026-09-13 sshd offered "publickey,keyboard-interactive" here.
    KbdInteractiveAuthentication = false;
    # Nothing logs in as root; deploys go through angus with --sudo.
    PermitRootLogin = "no";
  };
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

  # --- Docker: local dev services ---
  # polymarket-platform runs its local Postgres with docker-compose
  # (docker compose up -d from the repo root).
  virtualisation.docker.enable = true;

  # --- Prisma: no prebuilt engines for linux-nixos ---
  # The Prisma CLI downloads engines from binaries.prisma.sh, which publishes
  # no linux-nixos target, so generate/validate/migrate all 404 and die. Point
  # the CLI at the nixpkgs-built schema engine instead. (Prisma 7's client no
  # longer needs a query-engine binary, so this is the only engine missing.)
  environment.variables.PRISMA_SCHEMA_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/schema-engine";

  # --- User ---
  users.users.angus = {
    isNormalUser = true;
    # Pinned, not allocated: everything on fast and in the tank/state archive is
    # owned by 1001, and a fresh install would otherwise hand out 1000.
    uid = 1001;
    group = "users";
    # obsidian-sync and claude-remote-control are user units: without linger
    # they silently never start at boot. Was set imperatively until 2026-09-23.
    linger = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    # No initialPassword: it was "changeme" in plaintext in this public repo, and
    # only ever applied at account creation, so removing it changes nothing live.
    # Set the real password with `passwd`.
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
    jq
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
    # ad-hoc; services.smartd (above) is the monitoring on top of it.
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
    # Google Takeout delivers .tgz for the big products and .zip for the small
    # ones, so unpacking a monthly export needs both.
    unzip
    # runtimes / env
    mise
    direnv
    # personal-agent PoC (Claude Agent SDK)
    python3
    uv
    nodejs_22
    claude-code
    # pi is the agent; paseo supervises it (and claude-code) so the phone can
    # drive a session on morty - see the paseo unit below. paseo ships no agent
    # of its own, it launches whatever CLI is on PATH.
    pi-coding-agent
    paseo
    # The pi wrapper in zshrc, and the paseo unit below, read morty's OpenRouter
    # key through a 1Password service account scoped read-only to the Morty vault.
    _1password-cli
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # Do not change after install (data-compat marker).
  system.stateVersion = "26.05";
}
