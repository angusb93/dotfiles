# "A backup that stopped silently three months ago is the most common way
# backups fail." - wiki/projects/data-migration-weekend.md
#
# Every scheduled job records a timestamp when it succeeds, and one daily check
# reports anything overdue into the 🚨 Alerts topic. The point is not to watch a
# job fail - a failing unit is loud - it is to notice a job that stopped being
# scheduled at all, which is silent.
{
  lib,
  pkgs,
  morty-alert,
  ...
}:
let
  stampDir = "/var/lib/morty-backup/stamps";

  # unit name -> how many hours may pass between successes before it is overdue.
  # Daily jobs get 36h so one skipped night on a machine that was off does not
  # cry wolf; sanoid runs hourly and is the canary for the snapshot policy.
  watched = {
    sanoid = 6;
    restic-backups-drive = 36;
    drive-pull = 36;
    syncoid-fast-vault = 36;
    syncoid-fast-data = 36;
    # Added once the first full pull completed on 2026-09-29 - 118,175 of
    # 120,851 messages, above its own 95% bar. Wiring an alarm to a job that had
    # never finished would only have taught everyone to ignore it.
    gmail-pull = 36;
    # Paperless is the only data on morty with no second home, so its portable
    # export is watched like the backups themselves rather than like an app.
    paperless-export = 36;
    paperless-ingest = 36;
    # Run by hand when the off-site SSD comes home (cold-copy.nix). Refreshed
    # every month or two, so overdue after two months - the alert is the
    # reminder to bring it home.
    cold-copy = 24 * 62;
  };

  # No hook on the watched units. The first version of this wrote a stamp from
  # each unit's ExecStopPost, which meant sanoid and both syncoid units - all
  # ProtectSystem=strict - could not write it, their ExecStopPost exited
  # non-zero, and systemd failed the whole unit. sanoid reported failure every
  # hour for fourteen hours while doing its job perfectly well.
  #
  # Monitoring that breaks what it measures is worse than no monitoring, so the
  # observer now does the observing: this check reads systemd's own record of
  # each unit's last outcome and keeps the stamps itself. Nothing is added to
  # the watched units at all.
  table = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (unit: hours: "${unit} ${toString hours}") watched
  );

  check = pkgs.writeShellApplication {
    name = "backup-staleness";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      now=$(date +%s)
      overdue=""
      mkdir -p ${stampDir}

      while read -r unit hours; do
        [ -n "$unit" ] || continue
        stamp=${stampDir}/"$unit"

        # Refresh the stamp from systemd's own record. InactiveEnterTimestamp is
        # when the unit last finished; Result says how. A unit mid-run still
        # reports the previous run here, which is what we want.
        result=$(systemctl show "$unit" -p Result --value 2>/dev/null || echo unknown)
        when=$(systemctl show "$unit" -p InactiveEnterTimestamp --value 2>/dev/null || true)
        if [ "$result" = "success" ] && [ -n "$when" ]; then
          if epoch=$(date -d "$when" +%s 2>/dev/null); then
            echo "$epoch" > "$stamp"
          fi
        fi

        if [ ! -f "$stamp" ]; then
          overdue="$overdue"$'\n'"$unit: no success ever recorded"
          continue
        fi

        age=$(( (now - $(cat "$stamp")) / 3600 ))
        if [ "$age" -gt "$hours" ]; then
          last=$(date -d "@$(cat "$stamp")" '+%Y-%m-%d %H:%M')
          overdue="$overdue"$'\n'"$unit: last success $last, ''${age}h ago (limit ''${hours}h)"
        fi
      done <<'TABLE'
      ${table}
      TABLE

      [ -n "$overdue" ] || exit 0

      {
        echo "These jobs have not succeeded recently enough:"
        echo "$overdue"
        echo
        echo "Check with: systemctl status <unit> and journalctl -u <unit>"
      } | ${lib.getExe morty-alert} "Backup jobs overdue on morty"
    '';
  };
in
{
  # Created here rather than by the stamp script: a hardened unit can write
  # inside a ReadWritePaths directory but cannot create it.
  systemd.tmpfiles.rules = [
    "d /var/lib/morty-backup 0700 root root -"
    "d ${stampDir} 0700 root root -"
  ];

  # Attach the stamp to every watched unit. Done here rather than in each
  # module so the list of what is watched lives in exactly one place.
  systemd.services.backup-staleness = {
    description = "Report backup jobs that have not succeeded recently";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe check;
    };
  };

  systemd.timers.backup-staleness = {
    description = "Daily check for overdue backup jobs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # After the night's jobs have all had their turn (drive-pull 02:00,
      # sanoid 03:00, restic 03:30, syncoid 04:30).
      OnCalendar = "09:00";
      Persistent = true;
      Unit = "backup-staleness.service";
    };
  };
}
