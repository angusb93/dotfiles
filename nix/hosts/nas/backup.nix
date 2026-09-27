# Offsite backup: morty-authoritative data -> Google Drive, encrypted.
#
# Rule 0 of wiki/projects/data-migration-weekend.md: everything that matters
# has two homes, morty and Google. For data whose original lives on morty
# (the vault, app state, recordings) the Google home is this restic
# repository in My Drive/morty-backup, encrypted before it leaves the box.
#
# Secrets, both root-only and deliberately not in this flake:
# - /var/lib/morty-backup/rclone.conf - Drive token via our own OAuth client
#   (Google Cloud project "morty-backup"; copy in 1Password Private)
# - /var/lib/morty-backup/restic.pass - repository password (1Password
#   Private "morty restic repository password" + the handwritten
#   break-glass sheet). Without it the offsite copy is unrecoverable.
#
# A Drive token that can write can also delete, so this backup is only as
# safe as root on morty - see A1 in morty-security-hardening.
{ pkgs, ... }:
let
  datasets = [ "fast/vault" "fast/data" "fast/media" ];
  snap = "restic";
in
{
  services.restic.backups.drive = {
    repository = "rclone:gdrive:morty-backup";
    passwordFile = "/var/lib/morty-backup/restic.pass";
    rcloneConfigFile = "/var/lib/morty-backup/rclone.conf";
    extraOptions = [ "rclone.program=${pkgs.rclone}/bin/rclone" ];
    initialize = true;

    # Back up a ZFS snapshot, not the live tree, so each run is one
    # consistent point in time even if Obsidian Sync is mid-write.
    backupPrepareCommand = ''
      for ds in ${toString datasets}; do
        ${pkgs.zfs}/bin/zfs destroy "$ds@${snap}" 2>/dev/null || true
        ${pkgs.zfs}/bin/zfs snapshot "$ds@${snap}"
      done
    '';
    paths = map (ds: "/${ds}/.zfs/snapshot/${snap}") datasets;

    timerConfig = {
      OnCalendar = "03:30";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 8"
      "--keep-monthly 12"
      "--keep-yearly 10"
    ];
    runCheck = true;
  };
}
