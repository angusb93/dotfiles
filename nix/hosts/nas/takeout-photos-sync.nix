# Reconstruct Google Photos album structure inside Immich after a Takeout extract.
#
# The script is takeout-photos-sync.py next to this file; its header explains the
# design and the one-way locking trap. The short version:
#
#   - Takeout files every photo twice, under "Photos from <year>" AND under each
#     album. Immich's external library indexes by path, so adding the album
#     folders to importPaths would have created ~8,900 duplicate assets. An
#     Immich album is a database row rather than a directory, so the structure is
#     rebuilt against the assets Immich already has. Only the album-only files
#     need uploading.
#
#   - ⚠️ It also regenerates importPaths from disk, which is the bug that
#     motivated the whole thing: the list was 19 hardcoded year folders covering
#     2005 and 2009-2026, so a photo taken in 2006-2008 landed on disk and was
#     SILENTLY invisible, and "Photos from 2027" would have been invisible from
#     January. Same shape as the /var/lib backup gap - an explicit list that
#     quietly stops covering reality.
#
# No timer of its own. It runs as part of the import, after takeout-extract, so
# a new export becomes visible in Immich in one step rather than two.
#
# ⚠️ --include-locked is deliberately NOT passed here. Setting an asset to
# visibility=locked is one-way from an API key: once locked, the key cannot see
# the asset and unlocking returns 400. That is the locked folder working as a
# boundary, not a bug, but it means locking must never happen unattended. Run it
# by hand when a Takeout brings new Locked Folder content:
#
#     sudo takeout-photos-sync --apply --include-locked
{ pkgs, ... }:
let
  script = pkgs.writers.writePython3Bin "takeout-photos-sync" { libraries = [ ]; doCheck = false; }
    (builtins.readFile ./takeout-photos-sync.py);
in
{
  # Available by hand for the locked-folder pass and for dry runs.
  environment.systemPackages = [ script ];

  systemd.services.takeout-photos-sync = {
    description = "Rebuild Google Photos albums inside Immich from the Takeout tree";
    after = [ "immich-server.service" "zfs.target" ];
    requires = [ "immich-server.service" ];

    # Without a Takeout tree there is nothing to read, and without the key
    # nothing can be written - do nothing rather than fail and train everyone to
    # ignore a red unit, the same bargain gmail-pull and paperless-ingest make.
    unitConfig.ConditionPathExists = [
      "/tank/backup/google/photos"
      "/var/lib/morty-backup/immich-takeout-sync.key"
    ];

    # psql for the asset index: reading 72k rows over the API would be many
    # paginated calls, and writes still go through the API so Immich maintains
    # its own invariants.
    path = with pkgs; [ postgresql util-linux ];

    serviceConfig = {
      Type = "oneshot";
      User = "root"; # the Takeout tree and the key are both root-only
      ExecStart = "${script}/bin/takeout-photos-sync --apply";

      # Uploading several hundred files off the array is slow enough that the
      # default would kill it part-way.
      TimeoutStartSec = "6h";

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = false; # runuser drops to postgres
      # Its own seen-set is the only thing it writes directly; everything else
      # goes through Immich's API.
      ReadWritePaths = [ "/fast/data/takeout-photos-sync" ];
      ReadOnlyPaths = [ "/tank/backup/google/photos" "/var/lib/morty-backup" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /fast/data/takeout-photos-sync 0750 root root -"
  ];
}
