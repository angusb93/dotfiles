# Unpack a monthly Google Takeout export onto tank.
#
# The script is takeout-extract.sh next to this file; its header explains the
# incremental-extract decision.
#
# ⚠️ Why this exists as a module at all: the script spent its first month living
# only in /var/lib/morty-backup, which is the one directory deliberately
# excluded from restic - the exclusion is reasoned about as "secrets", and a
# non-secret put inside it inherits the exclusion silently. It was therefore
# the only copy in existence, on a machine whose whole point is that nothing is
# the only copy. Found by walking that directory against 1Password on
# 2026-10-01; see wiki/concepts/infra/data-map.md.
#
# No timer, deliberately. Takeout delivery is scheduled in Google but is not
# automatic to *verify* (see morty-backup-system), so a human confirms the
# archives landed and then runs:
#
#     sudo systemctl start takeout-extract
{ pkgs, ... }:
let
  script = pkgs.writeShellScriptBin "takeout-extract" (builtins.readFile ./takeout-extract.sh);
in
{
  systemd.services.takeout-extract = {
    description = "Unpack a verified Google Takeout export onto tank";
    # tank, not the root filesystem, at both ends.
    after = [ "zfs.target" ];

    # Extracting is only half the job: until Immich's importPaths are refreshed
    # and the album structure rebuilt, a new export is on disk but invisible.
    # Chained rather than left to a human so the two cannot drift apart.
    # ⚠️ `wants`, not `requires`: a failure there must not retroactively fail a
    # good extract, and the sync is safely re-runnable on its own.
    wants = [ "takeout-photos-sync.service" ];
    before = [ "takeout-photos-sync.service" ];

    # Does nothing rather than failing if there is no export waiting, so a
    # mistimed run is a no-op instead of a red unit.
    unitConfig.ConditionPathExists = "/tank/backup/google/takeout/archives";

    path = with pkgs; [ gnutar gzip unzip rsync findutils coreutils ];

    serviceConfig = {
      Type = "oneshot";
      # Root: the Takeout datasets are root-owned, and the extract has to
      # preserve the uid/gid the rest of tank/backup/google already uses.
      User = "root";
      ExecStart = "${script}/bin/takeout-extract";

      # A 356 GiB export takes hours and systemd's default would kill it
      # part-way, which on an extract means a half-unpacked tree rather than a
      # clean failure.
      TimeoutStartSec = "infinity";

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      # The only two datasets it touches. tank/backup/google/photos is separate
      # from the Takeout tree because Google Photos has its own dataset in the
      # layout - see photo-library-layout.
      ReadWritePaths = [
        "/tank/backup/google/takeout"
        "/tank/backup/google/photos"
      ];
    };
  };
}
