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
  };

  # Called from ExecStopPost, where systemd exports SERVICE_RESULT. Writing the
  # stamp from the job itself would record an attempt; writing it here records
  # an outcome.
  stamp = pkgs.writeShellApplication {
    name = "backup-stamp";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      [ "''${SERVICE_RESULT:-}" = "success" ] || exit 0
      mkdir -p ${stampDir}
      date +%s > ${stampDir}/"$1"
    '';
  };

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

      while read -r unit hours; do
        [ -n "$unit" ] || continue
        stamp=${stampDir}/"$unit"

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
      # The same morty-alert smartd and ZED use, passed in as a module argument
      # so there is one channel to Angus rather than three copies of one.
      } | ${lib.getExe morty-alert} "Backup jobs overdue on morty"
    '';
  };
in
{
  systemd.tmpfiles.rules = [ "d ${stampDir} 0700 root root -" ];

  # Attach the stamp to every watched unit. Done here rather than in each
  # module so the list of what is watched lives in exactly one place.
  systemd.services =
    lib.mapAttrs' (
      unit: _:
      lib.nameValuePair unit {
        serviceConfig.ExecStopPost = [ "${lib.getExe stamp} ${unit}" ];
      }
    ) watched
    // {
      backup-staleness = {
        description = "Report backup jobs that have not succeeded recently";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe check;
        };
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
