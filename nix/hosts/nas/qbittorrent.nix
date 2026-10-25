# qBittorrent: the torrent half of acquisition, added for books.
#
# Why at all, when SABnzbd already works: usenet is structurally thin for
# books. Of Prowlarr's 657 indexer definitions, 356 carry a Book category and
# only **16** of those are usenet - the book ecosystem is a torrent ecosystem.
# A one-indexer usenet setup returning nothing for a famous novel is that
# ratio showing, not a fault (see wiki/projects/home-lab.md).
#
# Where it sits: inside the VPN namespace (vpn.nix), which is the case that
# file was built for in the first place - its own comment says the calculus
# "changes completely the day a torrent client is added". Unlike usenet, where
# the transfer is TLS to a paid provider, a torrent swarm shows the IP to every
# peer in it. So this service is in `nsServices` and gets the structural kill
# switch: if wg0 goes away the namespace has no default route and the client
# simply cannot talk to a tracker.
#
# ⚠️ No port forwarding. NordVPN does not offer it, so there is no inbound
# path to the torrenting port and qBittorrent will report itself **not
# connectable**. Downloads work; seeding only ever reaches peers who connect
# out to us. That makes ratio-building on a private tracker hard and is a
# provider question, not a config one - documented rather than worked around.
{ config, lib, pkgs, nixpkgsApproved, ... }:
let
  state = "/fast/data/qbittorrent";

  # Completed torrents land in the SAME directory SABnzbd uses, which is also
  # Bindery's BINDERY_DOWNLOAD_DIR. Bindery takes a single download root and
  # asks the client where a job landed; one root for both clients means no
  # second path to keep in sync. On tank beside the library so an import stays
  # a hardlink - the constraint the whole downloads tree is shaped by
  # (media.nix).
  complete = "/tank/media/library/downloads/complete/books";

  # In-progress torrents, kept apart so a half-downloaded file is never
  # visible in the directory Bindery imports from.
  incomplete = "/tank/media/library/downloads/incomplete/torrents";

  # ⚠️ Not 8080. SABnzbd already holds 8080 *inside this same namespace*, and
  # the module's default would be a bind failure that reads like a crash.
  webuiPort = 8089;

  # Fixed rather than random so the figure in a tracker's "not connectable"
  # diagnostics means something.
  torrentingPort = 51413;

  # ⚠️ The client version is tracker-constrained, not a free choice.
  # MyAnonaMouse only permits clients on its approved list, and at the time of
  # writing its site banner reads "qBittorrent 5.3.0 just released, don't
  # update yet". The package comes from nixpkgs, so a routine `nix flake
  # update` would carry a new version in silently and leave an unapproved
  # client talking to the tracker without anyone touching this file.
  #
  # The assertion below turns that into a build failure instead. It does not
  # pin the source - it makes an unexpected bump loud, so a person decides.
  # To clear it: check MAM's approved-client list, then raise this string.
  approvedVersion = "5.2.4";

  # ⚠️ TEMPORARY PIN (2026-10-25): this nixpkgs carries qbittorrent-nox
  # 5.3.0, and 5.3.0's MAM approval is UNVERIFIED - the session cookie below
  # (dated 2026-10-21) is stale and bounces to login.php even from inside the
  # vpn namespace, so the approved-client list could not be read. Rather than
  # raise approvedVersion on a guess, the client stays on the
  # last-known-approved 5.2.4 via the nixpkgs-approved flake input (rev
  # f20cd90e28fe - what the running system was built from, so the store paths
  # were already local). A fetchTarball pin is NOT the shape for this: github
  # regenerates archive bytes, so a file-hash pin rots (seen same-day,
  # 2026-10-25); the flake input locks the narHash instead. To clear: with a
  # fresh MAM session, check the approved-client list - if 5.3.0 is approved,
  # raise approvedVersion above and delete this pin and the input; the
  # assertion guards either way.

  # The MAM session cookie. Kept out of the flake for the same reason
  # qBittorrent has no password in it: this repository is public.
  mamSession = "/var/lib/morty-backup/mam-session.id";

  categoriesJson = pkgs.writeText "qbittorrent-categories.json" (
    builtins.toJSON { books = { save_path = complete; }; }
  );
in
{
  assertions = [
    {
      # The EFFECTIVE package (services.qbittorrent.package), not ambient
      # pkgs: since the 5.2.4 pin above, what nixpkgs ships and what this
      # service runs can differ, and what MAM sees is what runs. With the pin
      # removed this is identical to the old pkgs.qbittorrent-nox check.
      assertion = config.services.qbittorrent.package.version == approvedVersion;
      message = ''
        qbittorrent-nox is ${pkgs.qbittorrent-nox.version}, but ${approvedVersion} is the
        version approved on MyAnonaMouse (see qbittorrent.nix). Running an
        unapproved client gets grabs rejected with "Unauthorized Client" and
        is a rule 2.3 breach. Check MAM's approved-client list before raising
        `approvedVersion`.
      '';
    }
  ];

  services.qbittorrent = {
    enable = true;

    # The pin above - read it before changing. Upstream default would be
    # pkgs.qbittorrent-nox (5.3.0), which is not verified approved.
    package = nixpkgsApproved.legacyPackages.${pkgs.stdenv.hostPlatform.system}.qbittorrent-nox;

    # qbittorrent:media. The media group is what lets Bindery - which runs as
    # calibre-web with `--group-add media` - read a finished torrent in order
    # to import it. The module only creates its own group when group is left
    # at "qbittorrent", so naming media here reuses the existing one.
    user = "qbittorrent";
    group = "media";

    profileDir = state;

    inherit webuiPort torrentingPort;

    # ⚠️ Deliberately false, like every other acquisition service. The web UI
    # is reached over the tailnet through vpn.nix's DNAT, not from the LAN.
    openFirewall = false;

    # The legal notice is a blocking stdin prompt on first start, and a service
    # has no stdin. Accepted both ways: the flag covers the first start before
    # any config file exists, the key covers every start after.
    extraArgs = [ "--confirm-legal-notice" ];

    # ⚠️ Setting serverConfig at all makes the config DECLARATIVE-ONLY. The
    # module's ExecStartPre does `install -Dm600` of this file over
    # qBittorrent.conf on *every* start, so anything changed in the web UI is
    # silently lost on the next restart. Exactly the trap sabnzbd.ini had in
    # media.nix, arriving from the opposite direction: there the module
    # rewrote a file the UI needed to own, here the UI edits a file the module
    # owns. Settings that matter therefore live here, and the web UI is for
    # looking at torrents rather than for configuring the client.
    serverConfig = {
      LegalNotice.Accepted = true;

      BitTorrent.Session = {
        DefaultSavePath = complete;
        TempPath = incomplete;
        TempPathEnabled = true;
        Port = torrentingPort;

        # Bindery decides what to keep; the client should not also be deleting
        # or pausing things on a rule of its own.
        GlobalMaxRatio = -1;
        GlobalMaxSeedingMinutes = -1;
        QueueingSystemEnabled = false;

        # Nothing here is on a metered line and the namespace has one route
        # out, so no rate limits. Encryption preferred rather than forced:
        # forced drops peers that would otherwise connect, and with no inbound
        # port we are already short of them.
        Encryption = 1;

        # DHT and peer exchange are how a public torrent finds peers at all.
        # A private tracker's torrents carry the private flag, which disables
        # both per-torrent regardless of what is set here, so this is not a
        # privacy decision being made on a tracker's behalf.
        DHTEnabled = true;
        PeXEnabled = true;
        LSDEnabled = true;

        # Anonymous mode off: it suppresses the peer ID and user agent, which
        # some trackers read as a client trying to hide and which breaks
        # nothing here. The VPN is the anonymity layer.
        AnonymousModeEnabled = false;

        # Bind to the tunnel itself, not merely to whatever the routing table
        # says. The namespace already has no route out except wg0, so this is
        # defence in depth rather than the kill switch: with the interface
        # named, a missing wg0 means qBittorrent refuses to bind at all,
        # instead of relying on the absence of a route to stop it. Both keys
        # are set because qBittorrent matches on the system name and displays
        # the friendly one.
        Interface = "wg0";
        InterfaceName = "wg0";
      };

      Preferences = {
        WebUI = {
          # All interfaces *within the namespace*. The namespace has exactly
          # two: wg0 and the veth. There is nothing else in it to expose this
          # to, and the DNAT arrives on the veth.
          Address = "*";
          Port = webuiPort;

          # ⚠️ Auth by source address, not a password, because this flake is
          # a public repo and a Password_PBKDF2 hash has no business in it.
          #
          # This is sound rather than a shortcut: vpn.nix MASQUERADEs
          # everything entering the namespace on veth-vpn, so every request -
          # whether it came from the tailnet via PREROUTING, from morty
          # itself, or from the Bindery container on the docker bridge -
          # arrives with the source rewritten to 10.200.0.1. The /30 is
          # therefore the complete set of addresses that can ever reach this
          # port, and the tailnet is the real trust boundary, exactly as it is
          # for Sonarr, Radarr and Prowlarr.
          LocalHostAuth = false;
          AuthSubnetWhitelistEnabled = true;
          AuthSubnetWhitelist = "10.200.0.0/30, fd00:200::/126";

          # Same class of trap as sabnzbd's host_whitelist: the DNAT means
          # every request arrives with a Host header qBittorrent has never
          # seen, and it answers 401 on the header alone. The CSRF check reads
          # Origin and Referer, which an API client does not send.
          HostHeaderValidation = false;
          CSRFProtection = false;
        };

        General.Locale = "en_GB";

        # One copy of a book is enough; a .torrent kept after the fact is not
        # state anything reads.
        Downloads.SaveResumeDataInterval = 60;
      };
    };
  };

  # /fast/data is root-owned, so a service that makes its own profile
  # directory cannot create one - the same failure Sonarr and Bazarr hit in
  # media.nix ("Access to the path is denied"). The download directories are
  # setgid media so what lands in them is group-readable to Bindery.
  #
  # ${complete} is also declared in bindery.nix; identical tmpfiles lines are
  # a duplicate-path conflict, so it is deliberately absent here and that
  # file remains its single owner.
  systemd.tmpfiles.rules = [
    "d ${state} 0750 qbittorrent media -"
    "d ${incomplete} 2775 root media -"
    "d ${state}/qBittorrent 0755 qbittorrent media -"
    "d ${state}/qBittorrent/config 0755 qbittorrent media -"

    # ⚠️ Categories are NOT part of qBittorrent.conf - they live in their own
    # categories.json, which the module does not manage. Bindery requires the
    # category named in its download-client config to already exist and fails
    # the client outright otherwise:
    #   qBittorrent category "books" was not found
    # It also silently defaults the field to "books" when sent empty, so there
    # is no way to opt out of having one. Seeded with `C` (copy only if
    # absent) rather than `L`, because qBittorrent rewrites this file itself
    # when a category is edited in the web UI and a symlink into the store
    # would make that write fail.
    "C ${state}/qBittorrent/config/categories.json 0644 qbittorrent media - ${categoriesJson}"
  ];

  # --- MyAnonaMouse: keep this machine's IP authorised ---
  #
  # The problem, in MAM's own words: a home server behind a VPN, browsed from
  # a different address, has to call their Dynamic Seedbox API "to keep this
  # device's IP address authorized to download". Without it the tracker
  # answers Unrecognized Host / Passkey errors and nothing downloads.
  #
  # ⚖️ This is sanctioned automation, not a workaround. MAM rule 1.7 bans
  # automating site functions "except those specifically listed in the API
  # Documentation", and this endpoint is one of them - it authenticates with
  # exactly the mam_id session cookie that page tells you to generate.
  #
  # Runs INSIDE the namespace, which is the whole point: the call has to come
  # from the address being authorised, and that is the tunnel's exit, not
  # morty's.
  #
  # ⚠️ Deliberately not a blind hourly POST. The exit IP is stable while the
  # tunnel holds, so hammering a third party's API every hour to tell it
  # nothing changed is rude and is the sort of traffic rule 1.7 exists to stop.
  # It calls only when the exit IP has actually moved, or when the last
  # success is over 12h old - at most twice a day when idle.
  systemd.services.mam-seedbox = {
    description = "Keep morty's VPN IP authorised on MyAnonaMouse";
    after = [ "netns-vpn.service" ];
    bindsTo = [ "netns-vpn.service" ];

    serviceConfig = {
      Type = "oneshot";
      NetworkNamespacePath = "/var/run/netns/vpn";
      BindReadOnlyPaths = [ "/etc/netns/vpn/resolv.conf:/etc/resolv.conf" ];

      # The session cookie is root-only in the secret store, and its only
      # other copy is the 1Password Morty vault - /var/lib/morty-backup is
      # excluded from restic by design (backup.nix).
      LoadCredential = [ "mam:${mamSession}" ];
      StateDirectory = "mam-seedbox";

      # No reason for this to reach anything but the tracker.
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      NoNewPrivileges = true;
    };

    path = [ pkgs.curl pkgs.coreutils pkgs.gnugrep ];

    script = ''
      set -uo pipefail
      state="$STATE_DIRECTORY/last"
      now=$(date +%s)

      ip=$(curl -fsS --max-time 20 https://ipinfo.io/ip || true)
      if [ -z "$ip" ]; then
        echo "no egress from the vpn namespace; the tunnel is down" >&2
        exit 0          # netns-vpn and vpn-check own that failure, not this.
      fi

      last_ip=""; last_at=0
      if [ -r "$state" ]; then read -r last_ip last_at < "$state" || true; fi

      if [ "$ip" = "$last_ip" ] && [ $((now - last_at)) -lt 43200 ]; then
        echo "exit ip unchanged ($ip) and refreshed recently; nothing to do"
        exit 0
      fi

      out=$(curl -fsS --max-time 30 \
        --cookie "mam_id=$(cat "$CREDENTIALS_DIRECTORY/mam")" \
        https://t.myanonamouse.net/json/dynamicSeedbox.php || true)

      if [ -z "$out" ]; then
        echo "no response from the dynamic seedbox API" >&2
        exit 1
      fi

      # ⚠️ Matched case-insensitively on purpose: the endpoint answers
      # {"Success":true,...} with a capital S, and a lowercase-only match
      # reports every successful authorisation as a refusal.
      if printf '%s' "$out" | grep -qiE '"success"[[:space:]]*:[[:space:]]*true'; then
        printf '%s %s\n' "$ip" "$now" > "$state"
        echo "authorised $ip on MyAnonaMouse"
      else
        # Their errors clear by themselves within 24h, and a failure here
        # must not take the unit into a restart loop against a third party.
        echo "dynamic seedbox API refused: $out" >&2
        exit 1
      fi
    '';
  };

  systemd.timers.mam-seedbox = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3m";
      OnUnitActiveSec = "1h";
      RandomizedDelaySec = "5m";
      Persistent = true;
    };
  };

  # State lives under /fast/data, so the nightly restic run to Drive, the
  # syncoid leg to tank/backup/morty/data and sanoid's policy cover it with no
  # backup code here - same reasoning as calibre-web.nix and bindery.nix.
  #
  # The namespace, the kill switch, the tailnet DNAT for ${toString webuiPort}
  # and the stop-on-leak are all handled by vpn.nix via nsServices. The only
  # thing this file owes it is the port and the service name, both of which
  # are listed there.
}
