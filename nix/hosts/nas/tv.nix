# Kodi on morty's HDMI output, as a kiosk.
#
# The design constraint is not "get Kodi running", it is *which account runs
# it*. `angus` has passwordless sudo, so auto-logging that account in on a
# screen in the living room would make physical access to the TV equivalent to
# root. A dedicated `kiosk` user with no password, no wheel and no shell worth
# having means someone who walks up to the TV gets a media player.
#
# GNOME is untouched and still selectable: log out of Kodi and GDM offers the
# normal greeter. That keeps Angus's 2026-09-24 call - GNOME stays until it is
# proven unnecessary - rather than quietly making the decision for him.
#
# Jellyfin remains the server. Kodi is only a client here, so nothing about
# the library, the arr stack or [[vpn-network-namespace]] changes. If this
# turns out to be worse than a £40 streaming stick, deleting this file is the
# whole rollback.
{ config, lib, pkgs, ... }:
{
  users.users.kiosk = {
    isNormalUser = true;
    description = "TV kiosk - runs Kodi on the HDMI output and nothing else";
    home = "/var/lib/kiosk";
    createHome = true;
    # No wheel. No password either: autologin goes through PAM's autologin
    # path, so a locked account is both sufficient and preferable - it cannot
    # be used to log in from a console or over SSH.
    extraGroups = [ "audio" "video" "render" ];
  };

  services.xserver.desktopManager.kodi = {
    enable = true;
    # The Jellyfin addon is what makes Kodi a client of morty rather than a
    # second, competing library.
    #
    # typing_extensions is listed because nixpkgs' plugin.video.jellyfin 2.2.0
    # does not declare it, and the addon imports `deprecated` from it at
    # module load. Without it the addon is installed, enabled, and silently
    # dead: Kodi starts fine, the addon's settings dialog opens with every
    # field blank, and the only evidence is a ModuleNotFoundError buried in
    # kodi.log. Upstream bug, one-line workaround here.
    package = pkgs.kodi.withPackages (p: [ p.jellyfin p.typing_extensions ]);
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "kiosk";
  };
  services.displayManager.defaultSession = "kodi";

  # Kodi's remote-control settings cannot live in the flake directly: Kodi
  # owns guisettings.xml and rewrites it on exit, so anything written there
  # declaratively is discarded the first time the session ends.
  #
  # Instead this re-asserts them before the session starts, while Kodi is not
  # running. It is ordered before display-manager for exactly that reason -
  # patching the file underneath a live Kodi is how the settings got lost the
  # first time round.
  #
  # The web-server password is read from /var/lib/morty-backup/kodi-web.password
  # rather than the flake, same as the restic, rclone and NordVPN credentials.
  systemd.services.kodi-settings = {
    description = "Re-assert Kodi's remote-control settings before the session starts";
    wantedBy = [ "display-manager.service" ];
    before = [ "display-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${./kodi-settings.py}";
    };
  };

  # The TV has gone silent twice in two days after the audio stack sat idle
  # (2026-09-29: the pipewire sink accepted a stream and never started the
  # hardware; 2026-09-30: Kodi's own audio engine went stale after ~24h and
  # could not create a stream at all). Same symptom, different layer. Two
  # defenses:
  #
  # 1. Never suspend the HDMI sink. Suspend-on-idle is the one thing both
  #    failures share a night with, and an always-open PCM costs effectively
  #    nothing on a machine that is always on. This is the Arch-wiki-standard
  #    session.suspend-timeout-seconds = 0, applied to all ALSA outputs
  #    (there is exactly one here).
  # 2. Bounce the session at 04:30 daily, before anyone is near the TV, so no
  #    stale audio state can survive more than a day. Restarting
  #    display-manager restarts the whole kiosk session - Kodi *and* its
  #    pipewire - which is the one move that has fixed both failure modes
  #    (and re-reads the wireplumber config above into the bargain).
  services.pipewire.wireplumber.configPackages = [
    (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-tv-no-suspend.conf" ''
      monitor.alsa.rules = [
        {
          matches = [
            { node.name = "~alsa_output.*" }
          ]
          actions = {
            update-props = {
              session.suspend-timeout-seconds = 0
            }
          }
        }
      ]
    '')
  ];

  systemd.services.tv-session-refresh = {
    description = "Bounce the Kodi kiosk session so no audio state survives more than a day";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart display-manager.service";
    };
  };

  systemd.timers.tv-session-refresh = {
    description = "Nightly kiosk session bounce at 04:30";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
    };
  };
}
