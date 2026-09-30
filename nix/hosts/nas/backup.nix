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
  # tank/archive is the one dataset whose original exists nowhere else, so it
  # is the one that most needs an offsite copy. Recordings still live in
  # fast/media and are covered by it; when they move to tank/media/recordings
  # that path replaces fast/media here.
  datasets = [
    "fast/vault"
    "fast/data"
    "fast/media"
    "tank/archive"
  ];
  snap = "restic";

  # ⚠️ Not everything that matters is on ZFS. /var/lib lives on the ext4
  # cryptroot, which has no snapshots, no syncoid leg and - until this line -
  # no offsite copy at all. /var/lib/agent is the telegram bot's entire
  # configuration: threads.json (persona routing), alerts.json (the topic ids
  # morty-alert posts into), personas.d and its workspace. Small, irreplaceable
  # by hand, and it was being backed up only by an ad-hoc tarball somebody made
  # once, which sat on the same unbacked-up filesystem.
  #
  # Backed up live rather than from a snapshot. These are small JSON files
  # written rarely, so a torn read is a far smaller risk than having no copy.
  #
  # ⚠️ /var/lib/morty-backup is deliberately NOT here. It is the secret store -
  # restic.pass, rclone.conf, the API tokens - and every item in it is meant to
  # be reproducible from 1Password. Putting it in the repository would make one
  # password the key to all of them. See wiki/concepts/infra/data-map.md.
  livePaths = [ "/var/lib/agent" ];
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
    paths = map (ds: "/${ds}/.zfs/snapshot/${snap}") datasets ++ livePaths;

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
