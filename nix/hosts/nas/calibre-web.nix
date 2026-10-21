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
      # ebook-convert also writes a fair amount of scratch while converting, so
      # PrivateTmp gives it a /tmp of its own rather than the host's.
      Environment = [ "HOME=%T" ];
      PrivateTmp = true;
    };

    # ⚠️ NixOS prepends `set -e` to a `script` block of its own accord, so the
    # flow below is written to survive it: every command whose failure is
    # expected is wrapped in an `if`, never left bare.
    script = ''
      set -uo pipefail
      shopt -s nullglob

      calibredb=${config.services.calibre-web.calibrePackage}/bin/calibredb
      convert=${config.services.calibre-web.calibrePackage}/bin/ebook-convert
      grep=${pkgs.gnugrep}/bin/grep

      # ⚠️ Wait for writes to finish. A path unit fires on the first byte, so
      # adding immediately can file a half-copied epub - which calibredb
      # accepts, producing a corrupt book rather than an error.
      sleep 5

      for f in ${inbox}/*; do
        [ -f "$f" ] || continue

        # ⚠️ Never reprocess our own rejects. The path unit fires on
        # DirectoryNotEmpty, so a .failed file left in place is a file the unit
        # picks up, fails on, and renames again - .failed.failed, forever. This
        # is the guard that makes the reject path terminal.
        case "$f" in *.failed) continue ;; esac

        rc=0
        out=$($calibredb add --library-path=${library} "$f" 2>&1) || rc=$?
        echo "$out"

        # ⚠️ calibredb exits NON-ZERO for a duplicate, which is not a failure -
        # it means the book is already in the library. Treated as done, and the
        # inbox copy dropped, or every re-drop of a book we already hold would
        # be quarantined as a reject.
        if printf '%s' "$out" | $grep -q 'already exist in the database'; then
          echo "already in the library: $(basename "$f")"
          rm -f "$f"
          continue
        fi

        if [ "$rc" -ne 0 ]; then
          # Leave a failure where it can be seen rather than deleting the only
          # copy, and in a name the loop above will not pick up again.
          mv -- "$f" "$f.failed" || echo "could not quarantine $f" >&2
          echo "calibredb add failed for $f - renamed to $f.failed" >&2
          continue
        fi

        id=$(printf '%s' "$out" | $grep -oP 'Added book ids:\s*\K[0-9]+' | head -1 || true)

        # --- make sure every book has an epub ---
        #
        # KOReader is the only reader on the Kindle and its AZW3/MOBI/LIT
        # handling is unreliable. Two books arrived unreadable before this
        # existed: Atlas Shrugged as a 2009 .lit, and a MacKay .azw3 whose
        # internal container name was Amazon's own `CR!...`, which rendered as
        # random characters on the device. Both were fine once converted, so
        # the conversion happens here rather than by hand each time.
        #
        # The original is kept too: add_format attaches the epub to the SAME
        # book, so OPDS offers both and nothing is thrown away.
        lower=''${f,,}
        case "$lower" in
          *.epub)
            : ;;
          *.pdf|*.cbz|*.cbr)
            # ⚠️ Deliberately not converted. PDF and comic archives are fixed
            # layout, and ebook-convert reflows them into something worse than
            # the original.
            echo "left $(basename "$f") as-is: fixed-layout format" ;;
          *)
            if [ -z "$id" ]; then
              echo "no book id in calibredb output; skipped converting $(basename "$f")" >&2
            else
              tmpdir=$(mktemp -d)
              if $convert "$f" "$tmpdir/converted.epub" >/dev/null 2>&1; then
                if $calibredb add_format --library-path=${library} "$id" "$tmpdir/converted.epub"; then
                  echo "converted $(basename "$f") to epub on book $id"
                else
                  echo "converted $(basename "$f") but add_format failed on book $id" >&2
                fi
              else
                # Not fatal: the original is in the library and readable on
                # something. Say so and carry on.
                echo "ebook-convert failed for $(basename "$f") - original kept, no epub" >&2
              fi
              rm -rf "$tmpdir"
            fi ;;
        esac

        rm -f "$f"
      done
    '';
  };
}