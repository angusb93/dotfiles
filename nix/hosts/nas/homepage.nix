# Homepage: one operator view of every service on morty.
#
# Ten services across two network zones on ports nobody memorises. Jellyseerr
# deliberately hides the machinery because its users should not care; this is
# the other half, for the person who does.
#
# Tailnet only. No openFirewall, so the port is reachable over tailscale0 (a
# trusted interface) and from the host itself, and from nowhere else.
{ config, lib, ... }:

let
  # Where a *widget* polls from. Homepage runs on the host, so half of these
  # services are a veth hop away.
  #
  # ⚠️ The four arr/sab services live in the VPN namespace (see vpn.nix) and
  # MUST be addressed as 10.200.0.2. The host's DNAT rule carries
  # `! -d 127.0.0.0/8`, so 127.0.0.1:8989 does NOT reach sonarr - it reaches
  # nothing. A widget pointed at loopback reads "unknown" with no error
  # anywhere to explain why. siteMonitor is server-side too, so it takes the
  # same address.
  #
  # ⚠️ The three *arr apps answer 401 at `/`, so their monitors point at
  # `/ping` - the unauthenticated health endpoint every *arr exposes. Pointed
  # at the root they paint a permanent red "401" on services that are up.
  ns = "http://10.200.0.2";
  host = "http://127.0.0.1";

  # Where a *link* points. Resolved by the browser on Angus's laptop or phone,
  # not by homepage, so it is the host's tailnet name in both cases - the
  # namespace address means nothing off-box.
  link = "http://morty";
in
{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082; # 8080 is DNATed to sabnzbd, 8081 is kodi's web ui

    # ⚠️ Not a list. It becomes HOMEPAGE_ALLOWED_HOSTS verbatim, and a request
    # whose Host header is missing from it is refused outright.
    allowedHosts = lib.concatStringsSep "," [
      "morty:8082"
      "morty.taile1ace0.ts.net:8082"
      "100.121.123.8:8082"
      "localhost:8082"
      "127.0.0.1:8082"
    ];

    # Seven API keys as HOMEPAGE_VAR_*, referenced below as {{HOMEPAGE_VAR_x}}.
    # Root-only 0600 and outside the flake, like every other secret on morty.
    # systemd reads it as PID 1 before dropping to the DynamicUser, so the
    # service never needs to be able to read the file itself.
    environmentFiles = [ "/var/lib/morty-backup/homepage.env" ];

    settings = {
      title = "morty";
      headerStyle = "clean";
      theme = "dark";
      color = "slate";
      hideVersion = true;

      # The green dot. Without this every siteMonitor renders as its literal
      # HTTP status text ("200") next to the name, which is noise - the only
      # thing worth seeing at a glance is up or not up.
      statusStyle = "dot";

      # ⚠️ A list, not an attrset. Nix sorts attribute names, so `layout` as an
      # attrset would put the columns in alphabetical order (Arr, Downloads,
      # Media, Services happens to be alphabetical today, which would hide the
      # bug until the first group that is not).
      #
      # Grouped by what a thing *is*, not by what you want to do with it, and
      # each group is a column. Four columns of stacked cards reads better than
      # wide rows of verbs, and it leaves room for the queue to grow - Uptime
      # Kuma, Vaultwarden, Paperless and the rest land in Services without the
      # shape changing.
      layout = [
        {
          Arr = {
            header = true;
            style = "column";
          };
        }
        {
          Downloads = {
            header = true;
            style = "column";
          };
        }
        {
          Media = {
            header = true;
            style = "column";
          };
        }
        {
          Services = {
            header = true;
            style = "column";
          };
        }
      ];
    };

    # Borrowed from notthebee's nix-config, which is where the layout above
    # came from too. Heavier type, a little air around the top widgets and
    # under each column, and the version footer gone.
    #
    # Upstream's last rule ends `};` - a stray brace that browsers skip
    # silently. Dropped rather than copied.
    customCSS = ''
      body,
      html {
        font-family: SF Pro Display, Inter, Helvetica, Arial, sans-serif !important;
      }
      .font-medium {
        font-weight: 700 !important;
      }
      .font-light {
        font-weight: 500 !important;
      }
      .font-thin {
        font-weight: 400 !important;
      }
      #information-widgets {
        padding-left: 1.5rem;
        padding-right: 1.5rem;
      }
      div#footer {
        display: none;
      }
      .services-group.basis-full.flex-1.px-1.-my-1 {
        padding-bottom: 3rem;
      }
    '';

    services = [
      {
        Arr = [
          {
            Sonarr = {
              icon = "sonarr.png";
              href = "${link}:8989";
              description = "TV show collection manager";
              siteMonitor = "${ns}:8989/ping";
              widget = {
                type = "sonarr";
                url = "${ns}:8989";
                key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
                enableQueue = true;
              };
            };
          }
          {
            Radarr = {
              icon = "radarr.png";
              href = "${link}:7878";
              description = "Movie collection manager";
              siteMonitor = "${ns}:7878/ping";
              widget = {
                type = "radarr";
                url = "${ns}:7878";
                key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
                enableQueue = true;
              };
            };
          }
          {
            Prowlarr = {
              icon = "prowlarr.png";
              href = "${link}:9696";
              description = "Indexer manager. If grabs dry up, look here first";
              siteMonitor = "${ns}:9696/ping";
              widget = {
                type = "prowlarr";
                url = "${ns}:9696";
                key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
              };
            };
          }
          {
            Bazarr = {
              icon = "bazarr.png";
              href = "${link}:6767";
              description = "Subtitle manager";
              siteMonitor = "${host}:6767";
              widget = {
                type = "bazarr";
                url = "${host}:6767";
                key = "{{HOMEPAGE_VAR_BAZARR_KEY}}";
              };
            };
          }
        ];
      }
      {
        Downloads = [
          {
            SABnzbd = {
              icon = "sabnzbd.png";
              href = "${link}:8080";
              description = "Usenet downloader. Speed here is speed through the VPN";
              siteMonitor = "${ns}:8080";
              widget = {
                type = "sabnzbd";
                url = "${ns}:8080";
                key = "{{HOMEPAGE_VAR_SAB_KEY}}";
              };
            };
          }
        ];
      }
      {
        Media = [
          {
            Jellyfin = {
              icon = "jellyfin.png";
              href = "${link}:8096";
              description = "The library itself";
              siteMonitor = "${host}:8096";
              # ⚠️ NOT `type = "jellyfin"`. Homepage 2.3.0's jellyfin widget is
              # the emby one: it calls `/emby/Sessions?api_key=...`. Jellyfin 12
              # removed both halves of that - the /emby path alias is a 404 and
              # api_key as a query parameter is a 401. The widget therefore
              # cannot work here at all, and its only symptom is a tile reading
              # "unknown".
              #
              # `Authorization: MediaBrowser Token="..."` is the one scheme
              # Jellyfin 12 still accepts (X-Emby-Token is gone too). customapi
              # can send it, which also keeps the key out of the URL and so out
              # of the journal - the native widget logged it in plaintext on
              # every failure.
              #
              # Revisit if homepage ships a Jellyfin-12-aware widget; the
              # library counts here are a narrower readout than the real one.
              widget = {
                type = "customapi";
                url = "${host}:8096/Items/Counts";
                method = "GET";
                headers = {
                  Authorization = "MediaBrowser Token=\"{{HOMEPAGE_VAR_JELLYFIN_KEY}}\"";
                };
                mappings = [
                  {
                    field = "MovieCount";
                    label = "Films";
                    format = "number";
                  }
                  {
                    field = "SeriesCount";
                    label = "Shows";
                    format = "number";
                  }
                  {
                    field = "EpisodeCount";
                    label = "Episodes";
                    format = "number";
                  }
                ];
              };
            };
          }
          {
            Jellyseerr = {
              icon = "jellyseerr.png";
              href = "${link}:5055";
              description = "Request portal. The front door for everyone else";
              siteMonitor = "${host}:5055";
              widget = {
                type = "jellyseerr";
                url = "${host}:5055";
                key = "{{HOMEPAGE_VAR_SEERR_KEY}}";
              };
            };
          }
          {
            Immich = {
              icon = "immich.png";
              href = "${link}:2283";
              description = "Self-hosted photo and video library";
              siteMonitor = "${host}:2283";
              # An immich widget exists upstream but wants its own API key,
              # which is not staged in homepage.env yet.
            };
          }
          {
            Kodi = {
              icon = "kodi.png";
              href = "${link}:8081";
              description = "The TV on HDMI, driven from Kore on your phone";
              # ⚠️ Deliberately no siteMonitor. Kodi's web server answers 401 to
              # everything including /, and homepage 2.3.0 has no
              # expectedStatus option, so a monitor here would paint a red dot
              # on a service that is working. No dot beats a dot that lies.
            };
          }
        ];
      }
      {
        Services = [
          {
            Kiwix = {
              icon = "kiwix.png";
              href = "${link}:8090";
              description = "Offline Wikipedia and Project Gutenberg";
              siteMonitor = "${host}:8090";
            };
          }
        ];
      }
    ];

    # ⚠️ The module sets ProcSubset = "pid" unless some widget declares
    # `resources.cpu = true`, and the cpu/memory readouts then come back blank
    # with nothing logged. Removing cpu here silently breaks memory too.
    widgets = [
      {
        resources = {
          label = "morty";
          cpu = true;
          # CPU package temperature, read from k10temp at
          # /sys/class/hwmon/hwmon3. ⚠️ /sys/class/thermal/thermal_zone* is
          # empty on this board, so anything looking there finds nothing - the
          # hwmon path is the one that works.
          cputemp = true;
          units = "celsius";
          # tempmax is what the bar fills toward, so it should be the number
          # that means "look at this", not the shutdown trip point.
          tempmin = 20;
          tempmax = 90;
          memory = true;
          uptime = true;
        };
      }
      {
        resources = {
          label = "fast (NVMe)";
          disk = "/fast";
        };
      }
      {
        resources = {
          label = "tank (RAIDZ2)";
          disk = "/tank";
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];
  };

  # The module writes every config file into /etc and puts no restartTriggers on
  # the unit, so `nixos-rebuild switch` after a change here activates the new
  # /etc and leaves the old process serving the old dashboard. It looks like the
  # edit did nothing. Tie the unit to its own config.
  systemd.services.homepage-dashboard.restartTriggers = map (f: config.environment.etc.${f}.source) [
    "homepage-dashboard/services.yaml"
    "homepage-dashboard/settings.yaml"
    "homepage-dashboard/widgets.yaml"
    "homepage-dashboard/bookmarks.yaml"
    "homepage-dashboard/custom.css"
  ];
}
