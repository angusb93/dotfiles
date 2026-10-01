# Keep Paperless fed, nightly, from the two places documents actually arrive:
# PDF attachments in the Gmail mirror, and photographs of documents in Immich.
#
# The script is paperless-ingest.py next to this file; its header explains the
# design. The short version of the one real decision: Paperless has its own
# IMAP mail rules and they are NOT used here, because they want a Gmail app
# password or a second OAuth client. That is a new bearer credential to expire,
# monitor and revoke, for mail that gmail-pull already puts on disk every night
# and that backup-staleness already watches.
{ config, pkgs, ... }:
let
  script = pkgs.writers.writePython3Bin "paperless-ingest" { libraries = [ ]; doCheck = false; }
    (builtins.readFile ./paperless-ingest.py);
in
{
  systemd.services.paperless-ingest = {
    description = "Import new document PDFs and document photos into Paperless";
    # zfs.target because both sources live on pools, not on the root filesystem.
    after = [ "paperless-web.service" "immich-server.service" "zfs.target" ];

    # Until both API credentials are in place this does nothing rather than
    # failing nightly and training everyone to ignore it - the same bargain
    # gmail-pull makes with its token.
    unitConfig.ConditionPathExists = [
      "/var/lib/morty-backup/paperless-api.token"
      "/var/lib/morty-backup/immich-pipeline.key"
    ];

    # runuser and psql for the Immich OCR query, find for the mtime scan.
    path = with pkgs; [ postgresql util-linux findutils ];

    serviceConfig = {
      Type = "oneshot";
      # Root: it reads the Gmail mirror on tank (root-only), both credential
      # files, and shells out to psql as postgres. Narrowed by ProtectSystem
      # below rather than by a service user.
      User = "root";
      ExecStart = "${script}/bin/paperless-ingest";

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = false; # runuser needs to drop to postgres
      # The only thing it writes is its own state: the two seen-sets and the
      # watermark. Everything else is read-only.
      ReadWritePaths = [ "/fast/data/paperless-backfill" ];
      ReadOnlyPaths = [ "/tank/backup/google/mail" "/var/lib/morty-backup" ];
    };
  };

  systemd.timers.paperless-ingest = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # The nightly chain is gmail-pull 02:30 -> this -> paperless-export ->
      # restic 03:30, so a document that arrives by email today is offsite
      # tonight. gmail-pull's duration varies and nothing here waits on it:
      # if it overruns, these messages are simply picked up tomorrow, which
      # the content-hash seen-set makes free.
      OnCalendar = "02:50";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  systemd.tmpfiles.rules = [
    "d /fast/data/paperless-backfill 0750 root root -"
  ];
}
