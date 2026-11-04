# LaraPaper: the self-hosted server for the TRMNL X ePaper display by the
# front door (wiki/concepts/infra/trmnl-epaper-dashboard.md). TRMNL's "BYOS"
# route - the device is pointed at this box from its WiFi captive portal and
# never talks to trmnl.com again. LaraPaper renders the screens (catalogue
# recipes, our own Liquid recipes, and later images pushed by a recipe app)
# and serves them on /api/display.
#
# Why the LAN: like Calibre-Web for the Kindle, the TRMNL cannot run Tailscale,
# so it has to reach this port on enp5s0. The admin UI is behind LaraPaper's
# own login; registration is closed after the first account.
#
# State is a SQLite file plus the generated PNGs, both under /fast/data, so the
# nightly restic run, syncoid and sanoid cover it with no code here - the same
# reasoning as bindery.nix.
{ pkgs, ... }:
let
  state = "/fast/data/larapaper";
  port = 4567;

  lanAddr = "192.168.1.96";
  tsAddr = "100.121.123.8";

  # APP_KEY encrypts sessions and stored plugin settings. Generated once on
  # first start and kept with the data, so it survives image upgrades and is
  # restored alongside the database it encrypts. Not in the flake because the
  # flake is public.
  envFile = "${state}/app.env";

  doorPython = pkgs.python3.withPackages (p: [
    p.google-auth
    p.requests
  ]);
in
{
  virtualisation.oci-containers.containers.larapaper = {
    # v0.45.1. Pinned by digest; bump deliberately.
    image = "ghcr.io/usetrmnl/larapaper@sha256:cde6a1f47f181260a0dc0d5d0c5fa3ad9cad2a225cb5cd242d5c369afba34785";

    environment = {
      # The device downloads screens from the image_url this builds, so it
      # must be an address the TRMNL can reach - the LAN one, not the tailnet.
      APP_URL = "http://${lanAddr}:${toString port}";
      DB_DATABASE = "database/storage/database.sqlite";
      PHP_OPCACHE_ENABLE = "1";

      # Closed: the admin account exists, and the port is open on the LAN.
      REGISTRATION_ENABLED = "false";
      PHP_DATE_TIMEZONE = "Europe/London";
      TZ = "Europe/London";
    };
    environmentFiles = [ envFile ];

    # The image runs as www-data, uid/gid 82; tmpfiles below matches it.
    volumes = [
      "${state}/database:/var/www/html/database/storage"
      "${state}/generated:/var/www/html/storage/app/public/images/generated"
    ];

    # ⚠ Docker publishes ports with its own nftables chain, bypassing the
    # NixOS firewall, so the bind addresses ARE the access control: LAN for
    # the device, tailnet and loopback for the admin UI. Never a bare
    # "4567:8080", which would also expose it on every docker bridge.
    # The LAN bind assumes 192.168.1.96 stays put (it is also the address the
    # Kindle and the TRMNL are configured with).
    ports = [
      "127.0.0.1:${toString port}:8080"
      "${lanAddr}:${toString port}:8080"
      "${tsAddr}:${toString port}:8080"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${state} 0750 root root -"
    "d ${state}/database 0750 82 82 -"
    "d ${state}/generated 0750 82 82 -"
  ];

  # The door screen. trmnl-door.liquid is the Door plugin's markup; LaraPaper
  # keeps its own copy in its database, so a change there is pasted into the
  # plugin (or pushed with tinker), not deployed by this flake.
  #
  # Its feed (trmnl-door.py): calendar, weather, Windrush and,
  # once Miniflux exists, headlines, pushed to the "Door" webhook plugin.
  #
  # A user unit for angus because the 1Password service account token lives in
  # ~angus/.config/op, the same arrangement as paseo-daemon in default.nix.
  # The webhook URL is in ~/.config/trmnl-door/env, not here: the plugin UUID
  # is the only thing guarding that endpoint, and this flake is public.
  systemd.user.services.trmnl-door = {
    description = "Push calendar, weather and trains to the TRMNL door screen";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "%h/.config/trmnl-door/env";
    };
    script = ''
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$HOME/.config/op/service-account-token")" \
        ${pkgs._1password-cli}/bin/op document get trmnl-calendar-sa --vault Morty \
        | ${doorPython}/bin/python3 -I ${./trmnl-door.py}
    '';
  };

  systemd.user.timers.trmnl-door = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Matches the device's 5-minute refresh, so each wake finds fresh data.
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };

  systemd.services.docker-larapaper = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    preStart = ''
      if [ ! -s ${envFile} ]; then
        umask 077
        echo "APP_KEY=base64:$(${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64)" > ${envFile}
      fi
    '';
  };
}
