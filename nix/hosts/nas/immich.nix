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
{ config, lib, ... }:
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
}
