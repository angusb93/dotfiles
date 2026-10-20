# Bindery: the book half of the arr stack.
#
# Readarr was archived in June 2025 (metadata service, not lack of interest),
# so this is its replacement: monitor authors, search indexers, hand downloads
# to SABnzbd, organise the result. Single Go binary, MIT, SQLite.
#
# ⚖️ Scope, the same line media.nix draws: this file installs and wires the
# software. Which indexers Prowlarr talks to, and which Usenet provider
# SABnzbd authenticates against, are Angus's to enter and are not configured
# here.
#
# ⚠️ The one Docker service on morty. Everything else is a native NixOS
# module; Bindery is not in nixpkgs, and a single static Go binary is a
# realistic thing to package later if it earns a permanent place. Declared
# through oci-containers so it is still described by the flake rather than by
# a docker run line somebody typed once.
#
# Where it sits relative to the VPN namespace (vpn.nix): outside it, and that
# is deliberate. Bindery never fetches content itself - Prowlarr performs the
# indexer queries and SABnzbd does the downloading, and both of those already
# live inside the namespace behind the kill switch. Bindery only speaks to
# their APIs across the veth, plus benign metadata lookups of its own.
{ config, ... }:
let
  state = "/fast/data/bindery";

  # Bindery's own organised library. Deliberately NOT the Calibre library:
  # calibredb and Calibre-Web own that tree's layout and metadata.db, and two
  # writers would fight over it. Bindery organises here and drops a copy into
  # the Calibre-Web inbox, which costs a second copy of each book - a few MB
  # apiece, against keeping both tools' invariants intact.
  books = "${state}/books";

  # SABnzbd's completed-downloads tree, mounted at the SAME path inside the
  # container. SABnzbd reports absolute host paths when Bindery asks where a
  # finished job landed, so any other mount point means Bindery is handed a
  # path it cannot see and every import is unverified. Identical paths on both
  # sides is the standard arr-stack convention for exactly this reason, and it
  # removes the need for a remap string that has to be kept in sync by hand.
  #
  # Under the existing downloads tree so a hardlink import stays on one
  # dataset, same constraint as the other arrs (see media.nix).
  sabComplete = "/tank/media/library/downloads/complete";
  downloads = "${sabComplete}/books";

  port = 8787;

  # morty on the tailnet.
  tsAddr = "100.121.123.8";

  calibreInbox = "/fast/data/calibre-web/inbox";
in
{
  # Pinned by digest, not :latest. A floating tag means the running version is
  # whatever was last pulled, which is not something the flake describes.
  # To bump: docker pull <new tag>, then paste its RepoDigest here.
  virtualisation.oci-containers = {
    backend = "docker";
    containers.bindery = {
      image = "ghcr.io/vavallee/bindery@sha256:27109c963f91a27f08d8825b406b2b5a5c59aed080bd9f3a7e585e235673d489";

      # uid 980 / gid 978 = calibre-web, so the drop into the Calibre-Web
      # inbox (2770 calibre-web:calibre-web) works without widening it.
      # --group-add 983 = media, for read access to SABnzbd's completed
      # downloads (2775 root:media). Docker drops supplementary groups when
      # --user is given, so the media group has to be added back explicitly or
      # every import fails on a directory it cannot traverse.
      user = "980:978";
      extraOptions = [ "--group-add=983" ];

      environment = {
        BINDERY_LOG_LEVEL = "info";
        TZ = "Europe/London";

        # ⚠ These default to /downloads and /books. The download dir has to
        # be the real host path, not a container-local one: SABnzbd reports
        # absolute host paths when asked where a finished job landed, so a
        # mismatch leaves every import "unverified" with nothing obviously
        # broken. The mount uses the same path on both sides for this reason.
        BINDERY_DOWNLOAD_DIR = downloads;
        BINDERY_LIBRARY_DIR = "/books";

        # Nothing on this box phones home.
        BINDERY_TELEMETRY_DISABLED = "true";
      };

      volumes = [
        "${state}/config:/config"
        "${books}:/books"
        "${sabComplete}:${sabComplete}"
        "${calibreInbox}:/calibre-inbox"
      ];

      # ⚠ Docker publishes ports by writing its own chain into nftables,
      # which bypasses the NixOS firewall entirely. Binding to the loopback and
      # tailnet addresses rather than 0.0.0.0 is what actually keeps this off
      # the LAN; a bare "8787:8787" would be reachable from the whole subnet.
      # Calibre-Web's LAN port stays the single exception on this box, because
      # only the Kindle needs one.
      ports = [
        "127.0.0.1:${toString port}:${toString port}"
        "${tsAddr}:${toString port}:${toString port}"
      ];
    };
  };

  # All of this lives under /fast/data, so the nightly restic run to Drive,
  # the syncoid leg to tank/backup/morty/data and sanoid's policy cover it
  # with no backup code here - the same reasoning as paperless.nix and
  # calibre-web.nix.
  systemd.tmpfiles.rules = [
    "d ${state} 0750 calibre-web calibre-web -"
    "d ${state}/config 0750 calibre-web calibre-web -"
    "d ${books} 2750 calibre-web calibre-web -"
    "d ${downloads} 2775 root media -"
  ];

  # ⚠ The SABnzbd download client's health will read **"unknown - Bindery
  # cannot check where sabnzbd puts completed downloads, so imports are
  # unverified"**, and that is correct, not a misconfiguration. Only
  # qbittorrent, nzbget and rtorrent expose a completed-downloads path for
  # introspection (internal/downloader/pathcheck.go, the `case` at line 65);
  # every other client type returns PathUnknown so the Test degrades to
  # connection-only. "Connection verified" in the test response is the part
  # that matters. Do not go looking for a path bug here - the paths are
  # mounted identically on both sides precisely so there is nothing to find.
  #
  # Prowlarr and SABnzbd live in the VPN namespace and are reached across the
  # veth, not on localhost:
  #   Prowlarr  http://10.200.0.2:9696
  #   SABnzbd   http://10.200.0.2:8080
  # Entered in Bindery's own settings with their API keys, which are not in
  # this flake for the same reason the indexers are not.
  systemd.services.docker-bindery.after = [ "netns-vpn.service" ];
}
