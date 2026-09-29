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
    package = pkgs.kodi.withPackages (p: [ p.jellyfin ]);
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "kiosk";
  };
  services.displayManager.defaultSession = "kodi";
}
