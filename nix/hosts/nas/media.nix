# Jellyfin and the arr stack.
#
# Layers, from wiki/concepts/media/media-server-stack.md: clients play, Jellyfin
# serves, the arr stack acquires. They are independent - Jellyfin works fine
# against a hand-filled library, and the arr tools only ever write into folders
# Jellyfin watches.
#
# ⚖️ Scope, Angus's own line in that page: "Configuring Usenet providers or
# indexers for copyrighted downloads is out of scope." This file installs and
# wires the software. Which indexers Prowlarr talks to, and which Usenet
# provider SABnzbd authenticates against, are Angus's to enter and are not
# configured here.
{ config, lib, ... }:
let
  library = "/tank/media/library";
  state = "/fast/data";
in
{
  # One group shared by every service that touches the library. This is what
  # lets Sonarr and Radarr *hardlink* a finished download into movies/ or tv/
  # rather than copying it - instant, and no second copy of a 40 GB file.
  # Hardlinks cannot cross datasets, which is why downloads/ and the library
  # live together on tank/media/library rather than on separate datasets.
  users.groups.media = { };
  users.users.angus.extraGroups = [ "media" ];

  # 2775: setgid, so anything created inside inherits the media group rather
  # than the creating service's own. Without it a file written by Sonarr is
  # unreadable to Jellyfin.
  systemd.tmpfiles.rules = [
    "d ${library} 2775 root media -"
    "d ${library}/movies 2775 root media -"
    "d ${library}/tv 2775 root media -"
    "d ${library}/music 2775 root media -"
    "d ${library}/downloads 2775 root media -"

    # SABnzbd creates these on its first download, but Sonarr and Radarr check
    # at startup that they can *see* the completed-download folder and raise a
    # health error if they cannot. Creating them up front means a fresh deploy
    # comes up clean rather than with a warning that resolves itself later -
    # and a warning people learn to ignore is worse than no warning.
    "d ${library}/downloads/incomplete 2775 root media -"
    "d ${library}/downloads/complete 2775 root media -"
    "d ${library}/downloads/complete/tv 2775 root media -"
    "d ${library}/downloads/complete/movies 2775 root media -"

    # /fast/data is root-owned, so a service that creates its own dataDir
    # rather than letting systemd's StateDirectory do it cannot make one.
    # Jellyfin and Radarr managed; Sonarr and Bazarr died with "Access to the
    # path is denied". Creating them here removes the difference.
    "d ${state}/sonarr 0700 sonarr media -"
    "d ${state}/bazarr 0700 bazarr media -"
    "d ${state}/sabnzbd 0700 sabnzbd media -"
  ];

  # --- the media server ---
  services.jellyfin = {
    enable = true;
    group = "media";
    # Library metadata and the transcode cache on flash, so browsing does not
    # wake the RAIDZ2 - the He10s have idle states now (see storage-migration).
    dataDir = "${state}/jellyfin";
    cacheDir = "${state}/jellyfin-cache";
    openFirewall = false;
  };

  # VAAPI on the 4650G's Vega iGPU: free hardware transcoding for H.264 and
  # HEVC including 10-bit. jellyfin needs the render node to use it.
  hardware.graphics.enable = true;
  users.users.jellyfin.extraGroups = [ "render" "video" ];

  # --- acquisition ---
  # Every one of these is tailnet-only: no openFirewall anywhere. They are
  # unauthenticated-by-default web UIs that can reach into the library and the
  # download client, and they have no business on the LAN.
  services.sonarr = {
    enable = true;
    group = "media";
    dataDir = "${state}/sonarr";
    openFirewall = false;
  };
  services.radarr = {
    enable = true;
    group = "media";
    dataDir = "${state}/radarr";
    openFirewall = false;
  };
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };
  services.bazarr = {
    enable = true;
    group = "media";
    openFirewall = false;
  };

  # Usenet client. Installed and running; the provider it talks to is Angus's
  # to configure, per the scope note above.
  services.sabnzbd = {
    enable = true;
    group = "media";
    openFirewall = false;

    # The module regenerates sabnzbd.ini from `settings` on every start and
    # installs it mode 400. Left at the default that is a trap: the web UI
    # accepts a Usenet provider, writes nothing, logs "Cannot write to INI
    # file" where nobody looks, and loses it on the next rebuild. Since the
    # provider is Angus's to enter and does not belong in a public flake, the
    # config has to be writeable.
    allowConfigWrite = true;

    settings.misc = {
      # "::" is sabnzbd's dual-stack bind. It lives in the VPN namespace (see vpn.nix) and
      # the host reaches it across a veth. 127.0.0.1 there is the namespace's
      # own loopback, which nothing else can address. The namespace has
      # exactly one neighbour, so this exposes it to nobody new.
      host = "::";
      port = 8080;

      # sabnzbd rejects a request whose Host header it does not recognise, and
      # the DNAT means every request arrives with one it has never seen.
      host_whitelist = "morty,morty.taile1ace0.ts.net,localhost,10.200.0.2,fd00:200::2,100.121.123.8,fd7a:115c:a1e0::5033:7b09";
      local_ranges = "10.200.0.0/30,100.64.0.0/10,fd00:200::/126,fd7a:115c:a1e0::/48";

      # SABnzbd creates completed job folders 0700 by default, which locks
      # out the whole point of the shared `media` group: Sonarr runs as
      # sonarr:media, cannot traverse into the folder, and reports "No files
      # found are eligible for import" - which reads like a parsing problem
      # rather than a permissions one. 775 restores group access so the
      # hardlink import works.
      permissions = "775";

      # On tank, next to the library, because Sonarr and Radarr *hardlink* a
      # finished download into movies/ or tv/ and a hardlink cannot cross a
      # filesystem. The default put these under /var/lib/sabnzbd, which would
      # have silently degraded every import into a full copy of a 40 GB file.
      download_dir = "/tank/media/library/downloads/incomplete";
      complete_dir = "/tank/media/library/downloads/complete";
    };
  };

  # The request front end - a Netflix-shaped UI in front of Sonarr and Radarr,
  # tied to Jellyfin's own users. Named `seerr` in nixpkgs.
  services.seerr = {
    enable = true;
    openFirewall = false;
  };
}
