# Calibre-Web: the ebook catalogue, and the first service on morty that is
# deliberately reachable from the LAN.
#
# Why the LAN: this exists to feed KOReader on the jailbroken Kindle
# (wiki/projects/kindle.md), and a Kindle cannot run Tailscale. Every other
# service here is tailnet-only via networking.firewall.trustedInterfaces in
# default.nix, and that rule is not being relaxed - the port is opened on
# enp5s0 *only*, with an interface-scoped rule rather than the module's
# openFirewall, which would also expose it on veth-vpn and the docker bridges.
# OPDS itself is authenticated: anonymous browsing stays off and the Kindle
# gets its own non-admin account.
#
# Library data: everything below lives under /fast/data, so the nightly restic
# run to Drive (03:30), the syncoid leg to tank/backup/morty/data (04:30) and
# sanoid's 30-daily/12-monthly policy all cover it with no code here. Same
# reasoning as paperless.nix: an agent-compiled epub exists on morty and
# nowhere else, which puts it in the same tier as the vault.
#
# ⚠️ The library must already exist before the unit first starts. The module's
# ExecStartPre runs `test -f ${library}/metadata.db || exit 1`, so a missing or
# empty library is a hard start failure, not an empty catalogue. Create it out
# of band once:
#   calibredb add --library-path=/fast/data/calibre-web/library some.epub
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Layout:
  #   root/      0755 - traversable, so the inbox below is reachable
  #     app/     0700 - dataDir: app.db (users, passwords), gdrive.db, .key
  #     library/ 2750 - the Calibre library
  #     inbox/   2770 - the drop folder
  #
  # ⚠️ dataDir is a *subdirectory* of root, not root itself. The module chmods
  # dataDir to 0700 through its own tmpfiles.settings, so when dataDir was the
  # parent nothing could traverse into a sibling inbox no matter how it was
  # permissioned - the inbox looked group-writable and was simply unreachable.
  root = "/fast/data/calibre-web";
  state = "${root}/app";
  library = "${root}/library";

  # Where things get dropped to be filed into the library. Calibre-Web has no
  # watched-folder feature of its own - that is a Calibre thing, not a
  # Calibre-Web thing - so the watcher below supplies it. This is the drop
  # point the claw agent's epub pipeline is specced against
  # (wiki/projects/claw-agent.md).
  inbox = "${root}/inbox";

  # The LAN NIC. 192.168.1.96/24 on wutangLAN; the Kindle is on the same /24.
  lanInterface = "enp5s0";
  port = 8083;
in
{
  services.calibre-web = {
    enable = true;

    listen = {
      # All interfaces, with the firewall deciding who may actually reach it -
      # the same shape as paperless and uptime-kuma. The module's default of
      # ::1 would make it unreachable from both the Kindle and the tailnet.
      ip = "0.0.0.0";
      inherit port;
    };

    dataDir = state;

    # ⚠️ Deliberately false. It would add allowedTCPPorts at the top level,
    # i.e. on every interface. See the interface-scoped rule below.
    openFirewall = false;

    options = {
      calibreLibrary = library;

      # The "upload a random book" path: the web UI accepts a file and files it
      # into the library. Needs conversion available for anything that is not
      # already epub.
      enableBookUploading = true;

      # Puts Calibre's ebook-convert on the record in app.db, so a mobi or pdf
      # upload is converted rather than rejected. Pulls the full ~1.5 GB
      # calibre closure, which is the price of accepting more than one format.
      enableBookConversion = true;

      # ⚠️ Not enableKepubify: kepub is a Kobo format. Nothing here reads it.
    };
  };

  # ⚠️ Interface-scoped, not global. This is the only port open on the LAN on
  # this machine; everything else is tailscale0-only.
  networking.firewall.interfaces.${lanInterface}.allowedTCPPorts = [ port ];

  # The module creates dataDir itself (tmpfiles.settings, 0700), but not the
  # library or the inbox - and ProtectSystem=strict can only make an *existing*
  # directory writable, so they have to be created here rather than on first
  # use. ${state} is deliberately absent: declaring it twice in tmpfiles is a
  # duplicate-path conflict, and the module's own entry already covers it.
  #
  # The inbox is 2770: group-writable so Angus can drop a book in without sudo,
  # and setgid so what he drops is group-owned calibre-web and the watcher can
  # read and delete it. Without the setgid bit a file arrives owned angus:users
  # and the add fails on a directory the service cannot clean up.
  systemd.tmpfiles.rules = [
    # 0755 so a non-owner can traverse into library/ and inbox/ below. It holds
    # no secrets itself - app/ keeps its own 0700 from the module.
    "d ${root} 0755 calibre-web calibre-web -"
    # 2750: readable by the calibre-web group, setgid so anything calibredb
    # writes stays group-owned.
    "d ${library} 2750 calibre-web calibre-web -"
    "d ${inbox} 2770 calibre-web calibre-web -"
  ];

  # The other half of that: group membership. /fast/data is otherwise
  # root-owned, so dropping a book in would need sudo on every single book.
  users.users.angus.extraGroups = [ "calibre-web" ];

  environment.systemPackages = [
    # calibredb, for the watcher and for filing books in by hand.
    config.services.calibre-web.calibrePackage

    # Pull a book out of the 71.6 GiB Gutenberg ZIM on tank and drop it in the
    # inbox. The ZIM holds a real .epub per book, but kiwix-serve's OPDS
    # catalogue advertises the three ZIM *files* rather than their contents, so
    # KOReader cannot browse it directly - this is the bridge between the two.
    (pkgs.writers.writePython3Bin "gutenberg-add" { flakeIgnore = [ "E501" ]; } (
      builtins.replaceStrings [ "@INBOX@" ] [ inbox ]
        (builtins.readFile ./gutenberg-add.py)
    ))
  ];

  # --- The watched folder Calibre-Web does not have ---
  #
  # Anything dropped in ${inbox} is added to the library and the original
  # removed. Driven by a path unit rather than a timer so a drop is picked up
  # within seconds, which is what makes the agent pipeline feel immediate.
  systemd.paths.calibre-web-inbox = {
    description = "Watch the Calibre-Web inbox for new books";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      # DirectoryNotEmpty rather than PathChanged: a file copied in slowly
      # fires PathChanged repeatedly, and this way the unit simply re-runs
      # until the directory is actually empty.
      DirectoryNotEmpty = inbox;
    };
  };

  systemd.services.calibre-web-inbox = {
    description = "File books dropped in the Calibre-Web inbox into the library";

    serviceConfig = {
      Type = "oneshot";
      User = "calibre-web";
      Group = "calibre-web";
      ReadWritePaths = [
        library
        inbox
      ];
      # calibredb wants somewhere to put its own config; without this it tries
      # the service user's home, which ProtectHome has made unavailable.
      Environment = [ "HOME=%T" ];
    };

    script = ''
      set -euo pipefail
      shopt -s nullglob

      # ⚠️ Wait for writes to finish. A path unit fires on the first byte, so
      # adding immediately can file a half-copied epub - which calibredb
      # accepts, producing a corrupt book rather than an error.
      sleep 5

      for f in ${inbox}/*; do
        [ -f "$f" ] || continue
        if ${config.services.calibre-web.calibrePackage}/bin/calibredb add \
             --library-path=${library} "$f"; then
          rm -f "$f"
        else
          # Leave a failure where it can be seen rather than deleting the only
          # copy. Renamed so the unit does not retry it forever - the path unit
          # fires on DirectoryNotEmpty, and a file it can never consume would
          # otherwise loop.
          mv "$f" "$f.failed"
          echo "calibredb add failed for $f - renamed to $f.failed" >&2
        fi
      done
    '';
  };
}
