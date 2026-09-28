# morty pulls Google-authoritative data down onto tank.
#
# Rule 3 of wiki/projects/backup-architecture.md: morty pulls, Google never
# gets credentials that reach into morty. Rule 0: Gmail, Drive and Photos are
# authoritative in Google, so their second home is tank - they need no offsite
# copy, because Google *is* the other copy.
#
# The Drive token is the same root-only rclone.conf the restic job uses, and it
# can write as well as read, so these units run as root and nothing else can
# read it - see backup.nix and A1 in morty-security-hardening.
{ pkgs, ... }:
{
  # Drive -> tank/backup/google/drive.
  #
  # `sync`, not `copy`: this is a mirror of what is in Drive today, and a file
  # deleted in Drive should disappear here too. That is safe precisely because
  # sanoid snapshots this dataset at 03:00, an hour after the pull - the
  # snapshot from before a deletion still has the file, which is the whole
  # difference between a sync and a backup.
  systemd.services.drive-pull = {
    description = "Pull Google Drive down to tank/backup/google/drive";
    after = [ "network-online.target" "zfs.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      Environment = [ "RCLONE_CONFIG=/var/lib/morty-backup/rclone.conf" ];
      ExecStart = toString [
        "${pkgs.rclone}/bin/rclone"
        "sync"
        "gdrive:"
        "/tank/backup/google/drive"
        # Takeout is pulled separately and is hundreds of GB; morty-backup is
        # morty's own restic repository, so pulling it would be a copy of a
        # copy of this machine.
        "--exclude" "Takeout/**"
        "--exclude" "morty-backup/**"
        # Google Docs/Sheets/Slides have no native download format, so they
        # come down as Office files. Stated rather than left to the default so
        # the restored shape of the backup does not change under us.
        "--drive-export-formats" "docx,xlsx,pptx,svg"
        # One recursive listing instead of one call per directory - a large
        # difference on a Drive this deep, and it stays well inside quota.
        "--fast-list"
        "--transfers" "8"
        # Deletions applied only once every transfer has succeeded, so an
        # interrupted run never leaves the copy shorter than the source.
        "--delete-after"
        "--stats" "1m"
        "--stats-one-line"
        "-v"
      ];
    };
  };

  systemd.timers.drive-pull = {
    description = "Nightly Google Drive pull";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Ahead of sanoid's 03:00 daily on tank/backup/google, so the snapshot
      # taken that night is the state this pull left behind.
      OnCalendar = "02:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
      Unit = "drive-pull.service";
    };
  };
}
