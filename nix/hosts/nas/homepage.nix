# Homepage: one operator view of every service on morty.
#
# Nine services across two network zones on ports nobody memorises. Jellyseerr
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
  # anywhere to explain why.
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
      headerStyle = "boxed";
      theme = "dark";
      color = "slate";
      # Without this the groups are ordered by however the YAML lands.
      layout = {
        Watch.style = "row";
        Watch.columns = 2;
        Acquire.style = "row";
        Acquire.columns = 3;
      };
    };

    services = [
      {
        Watch = [
          {
            Jellyfin = {
              icon = "jellyfin.png";
              href = "${link}:8096";
              description = "Watch. The library itself.";
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
              description = "Ask for something. The front door for everyone else.";
              widget = {
                type = "jellyseerr";
                url = "${host}:5055";
                key = "{{HOMEPAGE_VAR_SEERR_KEY}}";
              };
            };
          }
        ];
      }
      {
        Acquire = [
          {
            SABnzbd = {
              icon = "sabnzbd.png";
              href = "${link}:8080";
              description = "The downloader. Speed here is speed through the VPN.";
              widget = {
                type = "sabnzbd";
                url = "${ns}:8080";
                key = "{{HOMEPAGE_VAR_SAB_KEY}}";
              };
            };
          }
          {
            Sonarr = {
              icon = "sonarr.png";
              href = "${link}:8989";
              description = "TV. Decides what to fetch and where it lands.";
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
              description = "Films. Same job as Sonarr.";
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
              description = "Indexers. If grabs dry up, look here first.";
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
              description = "Subtitles.";
              widget = {
                type = "bazarr";
                url = "${host}:6767";
                key = "{{HOMEPAGE_VAR_BAZARR_KEY}}";
              };
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

    bookmarks = [
      {
        Elsewhere = [
          {
            Kodi = [
              {
                abbr = "KO";
                href = "${link}:8081";
                description = "The TV. Controlled from Kore on your phone.";
              }
            ];
          }
          {
            Immich = [
              {
                abbr = "IM";
                href = "${link}:2283";
                description = "Photos.";
              }
            ];
          }
          {
            Kiwix = [
              {
                abbr = "KW";
                href = "${link}:8090";
                description = "Offline Wikipedia and Gutenberg.";
              }
            ];
          }
        ];
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
  ];
}
