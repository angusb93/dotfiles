# Immich: the real-time photo path from the phone.
#
# Google Photos Takeout is scheduled monthly and each run is a full ~180 GB
# export, so a photo taken today is not on tank for up to a month. That is the
# weak link in the whole backup plan
# (wiki/projects/archived/data-migration-weekend.md). Immich closes it: the phone app
# uploads every new photo in original quality straight to morty over Tailscale
# as it is taken, and Takeout drops back to an occasional catch-all for
# Google-side edits and albums.
#
# It needs no offsite copy of its own. The phone uploads the same photo to
# Google Photos as well, so Google is the second home - rule 0 is satisfied
# without morty sending anything back out.
{ config, lib, pkgs, ... }:
let
  media = "/tank/media/photos";
  # Immich keeps thumbnails under mediaLocation, which would put a few tens of
  # GB of small random reads on the RAIDZ2 array and make the phone's grid view
  # feel like a NAS. The plan puts them on flash instead, so the directory is
  # bind-mounted out to fast/data while Immich still sees one tree.
  thumbs = "/fast/data/immich-thumbs";
  pgDataDir = "/fast/data/postgresql/${config.services.postgresql.package.psqlSchema}";
in
{
  services.immich = {
    enable = true;
    mediaLocation = media;
    port = 2283;

    # All interfaces, but the firewall is not opened - so this reaches the
    # tailnet through networking.firewall.trustedInterfaces and nothing else.
    # The default of "localhost" would make it unreachable from the phone, and
    # opening the port would put an unauthenticated-by-default photo library on
    # the LAN.
    host = "";
    openFirewall = false;

    # Postgres and Redis both over unix sockets, which is what lets the module
    # skip a secrets file entirely - no database password has to exist, so none
    # can leak.
    database.enable = true;
    redis.enable = true;

    machine-learning.enable = true;
  };

  # The database belongs on flash with the rest of the app state, not on the
  # array: it is small, it is written constantly, and fast/data is already the
  # dataset for exactly this.
  # The module namespaces the unit onto its dataDir, so the versioned directory
  # has to exist before postgres ever starts - otherwise the unit dies at step
  # NAMESPACE with "no such file or directory" and never reaches initdb.
  services.postgresql.dataDir = pgDataDir;

  # The dataset mountpoints are root-owned on purpose. systemd-tmpfiles refuses
  # to descend through an ownership change it considers an "unsafe path
  # transition" - angus-owned parent, service-owned child - and silently creates
  # nothing, which is what left postgres dying at step NAMESPACE on a dataDir
  # that was never made.
  systemd.tmpfiles.rules = [
    "d /fast/data 0755 root root -"
    "d /tank/media 0755 root root -"
    "d ${media} 0750 immich immich -"
    "d ${thumbs} 0750 immich immich -"
    "d ${media}/thumbs 0750 immich immich -"
    "d /fast/data/postgresql 0750 postgres postgres -"
    "d ${pgDataDir} 0750 postgres postgres -"
  ];

  fileSystems."${media}/thumbs" = {
    device = thumbs;
    fsType = "none";
    options = [ "bind" ];
  };

  # Without this the server can start before the bind mount is up and write
  # thumbnails onto the array underneath it, where they would then be shadowed
  # and invisible - the failure that looks like "Immich regenerates every
  # thumbnail on restart".
  systemd.services.immich-server.unitConfig.RequiresMountsFor = [ media "${media}/thumbs" ];

  # A 30-minute keepalive for Immich's ML job queues (ocr, smartSearch).
  #
  # ⚠️ The original comment here said the queues "pause silently" - that was a
  # misdiagnosis (2026-09-30), corrected 2026-10-14. The 18.8k "pending" assets
  # counted that day were overwhelmingly `visibility = hidden` **videos** -
  # 18.7k of them live-photo MOV components paired to a visible still - which
  # `streamForOcrJob` excludes by design. Zero hidden images. The image library
  # was OCR-complete all along; new uploads OCR inline. The queues never paused.
  #
  # What the timer is actually for: `start` re-queues every asset whose OCR/CLIP
  # job previously *failed* (the 172 stragglers - missing preview files, etc.),
  # so a failed index entry self-heals within 30 minutes instead of sitting
  # until someone notices. It also re-kicks the queues after ML restarts. It
  # treats a busy queue (400 "already running") as healthy and stays quiet.
  # ⚠️ A deliberate queue pause in the UI loses to this timer within 30 minutes;
  # a wanted pause should stop the timer instead.
  systemd.services.immich-queue-keepalive = {
    description = "Re-kick Immich's ML job queues (ocr, smartSearch)";
    after = [ "immich-server.service" ];
    wants = [ "immich-server.service" ];
    path = [ pkgs.curl ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "immich-queue-keepalive" ''
        key=$(cat /var/lib/morty-backup/immich-pipeline.key) || {
          echo "immich-queue-keepalive: no API key file" >&2; exit 0;
        }
        for queue in ocr smartSearch; do
          out=$(curl -sS -w '\n%{http_code}' -X PUT "http://127.0.0.1:2283/api/jobs/$queue" \
            -H "x-api-key: $key" -H "Content-Type: application/json" \
            -d '{"command":"start"}' 2>&1) || {
            echo "immich-queue-keepalive: $queue: request failed (server up?)" >&2; continue;
          }
          code=$(echo "$out" | tail -n1)
          if [ "$code" != "200" ] && ! echo "$out" | grep -q "already running"; then
            echo "immich-queue-keepalive: $queue: HTTP $code" >&2
          fi
        done
      '';
    };
  };

  systemd.timers.immich-queue-keepalive = {
    description = "Keep Immich's ML job queues running";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      Persistent = true;
    };
  };
}
