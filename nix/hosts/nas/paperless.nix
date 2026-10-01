# Paperless-ngx: scanned documents, OCR'd and searchable.
#
# ⚠️ This is the first service on morty whose data has **no other home**.
# Jellyfin's library can be re-downloaded, Immich's photos are also in Google
# Photos, the Google mirrors are copies by definition. A bank statement that
# was scanned and then shredded exists on morty and nowhere else, which puts
# Paperless in the same tier as the vault and tank/archive: it must go offsite.
#
# It does, without any code here, because everything below lives under
# /fast/data - and restic backs that dataset up to Drive nightly, encrypted
# before it leaves the box (backup.nix). See wiki/concepts/infra/data-map.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  state = "/fast/data/paperless";
  # The document exporter's output. Also under /fast/data, so it rides the same
  # nightly restic run.
  exportDir = "${state}/export";
in
{
  services.paperless = {
    enable = true;
    dataDir = state;
    # mediaDir defaults to ${dataDir}/media - the original PDFs and images.
    consumptionDir = "${state}/consume";

    # All interfaces, firewall closed everywhere but tailscale0. The default of
    # 127.0.0.1 would make it unreachable from the laptop that does the
    # scanning.
    address = "0.0.0.0";
    port = 28981;

    # Postgres rather than the default SQLite, into the cluster Immich already
    # runs - whose dataDir is /fast/data/postgresql, so it is already inside
    # the nightly restic snapshot. One database to back up, not two.
    database.createLocally = true;

    # ⚠️ Root-only 0600, created out of band, deliberately not in the flake.
    # Same handling as restic.pass, rclone.conf and the Kodi web password.
    passwordFile = "/var/lib/morty-backup/paperless-admin.password";

    settings = {
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_TIME_ZONE = "Europe/London";
      # Keep the untouched original alongside the OCR'd PDF. Storage is
      # trivial for documents and the original is the thing of record.
      PAPERLESS_OCR_MODE = "skip";
      # Filed by date and title rather than a flat pile of UUIDs, so the
      # directory tree is still navigable if Paperless itself is ever gone -
      # which is half the point of keeping the originals.
      PAPERLESS_FILENAME_FORMAT = "{created_year}/{correspondent}/{title}";

      # ⚠️ Django rejects a login POST whose Origin is not trusted, and the
      # NixOS module only sets PAPERLESS_URL when it is also configuring nginx
      # - which we are not. Unset, the trusted-origin list is empty, so a
      # browser that reaches Paperless by any name other than the one it first
      # loaded gets "Forbidden (CSRF cookie not set)" on every attempt. The
      # page renders fine, so it reads as a wrong password rather than a
      # configuration problem.
      PAPERLESS_URL = "http://morty:28981";
      PAPERLESS_CSRF_TRUSTED_ORIGINS = lib.concatStringsSep "," [
        "http://morty:28981"
        "http://morty.taile1ace0.ts.net:28981"
        "http://100.121.123.8:28981"
        "http://localhost:28981"
        "http://127.0.0.1:28981"
      ];
      PAPERLESS_ALLOWED_HOSTS = lib.concatStringsSep "," [
        "morty"
        "morty.taile1ace0.ts.net"
        "100.121.123.8"
        "localhost"
        "127.0.0.1"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${state} 0750 paperless paperless -"
    "d ${state}/consume 0750 paperless paperless -"
    "d ${exportDir} 0750 paperless paperless -"
  ];

  # A second, portable copy of everything Paperless knows.
  #
  # The restic run already captures mediaDir and the postgres cluster, which is
  # a complete backup but a version-coupled one: restoring it means standing up
  # a matching Paperless and a matching postgres. `document_exporter` writes
  # the files plus a manifest.json that any later Paperless can import, and it
  # is the restore path upstream actually documents. It lands under /fast/data
  # so the same nightly restic run carries it offsite.
  systemd.services.paperless-export = {
    description = "Export Paperless documents to a portable, version-independent tree";
    after = [ "paperless-web.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "paperless";
      Group = "paperless";
      # --delete prunes documents removed since the last export, so the export
      # tracks the library rather than growing forever.
      ExecStart = "${config.services.paperless.manage}/bin/paperless-manage document_exporter ${exportDir} --delete --no-progress-bar";
      ReadWritePaths = [ state ];
    };
  };

  systemd.timers.paperless-export = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 02:45, in the gap between the Google pulls and the 03:30 restic run, so
      # the night's restic snapshot always contains a fresh export rather than
      # yesterday's.
      OnCalendar = "02:45";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  environment.systemPackages = [ pkgs.ocrmypdf ];
}
