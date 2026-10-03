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
let
  # The one recovery primitive. Restarting the kiosk session while the TV is
  # *on* is the move that has fixed every silent evening (2026-09-29, 09-30,
  # 10-02), and everything below is just a way of deciding when to call it.
  #
  # ⚠️ The pipewire half is the part the old nightly refresh got wrong. The
  # kiosk user manager survives a display-manager restart - the new autologin
  # session reuses it - so pipewire and wireplumber kept the *same PIDs from
  # 2026-09-29 to 10-02* while this file's comment claimed the nightly bounce
  # restarted them. Stopping user@ explicitly is what makes the refresh real.
  tv-session-bounce = pkgs.writeShellApplication {
    name = "tv-session-bounce";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      set -uo pipefail
      uid=$(id -u kiosk)

      echo "bouncing the kiosk session (Kodi + pipewire)"
      systemctl stop display-manager.service
      systemctl stop "user@$uid.service" || true
      systemctl start display-manager.service
    '';
  };

  # The TV's HDMI audio link, as ALSA sees it. Note this is *not* the DRM
  # connector: the SONY TV keeps the HDMI link and its EDID alive in standby
  # (so /sys/class/drm says "connected" all night, which is why video was
  # never the symptom) while dropping the audio ELD. monitor_present is the
  # only honest signal for "the TV can take sound", and it is what the
  # existence of the pipewire HDMI sink follows.
  tv-hdmi-watch = pkgs.writeShellApplication {
    name = "tv-hdmi-watch";
    runtimeInputs = [
      pkgs.alsa-utils
      pkgs.pipewire
      pkgs.util-linux
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      set -uo pipefail

      uid=$(id -u kiosk)

      present() {
        for f in /proc/asound/card*/eld#*; do
          [ -r "$f" ] || continue
          if grep -qE 'monitor_present[[:space:]]+1' "$f"; then
            return 0
          fi
        done
        return 1
      }

      # The condition that actually matters: wireplumber has republished the
      # HDMI sink. Waiting for *this* rather than sleeping a fixed guess means
      # the bounce lands as early as it can and never lands too early.
      sink_present() {
        XDG_RUNTIME_DIR=/run/user/$uid runuser -u kiosk -- pw-dump 2>/dev/null \
          | grep -q 'alsa_output\..*hdmi'
      }

      react() {
        echo "TV HDMI audio link came up; waiting for the sink"
        for _ in $(seq 1 30); do
          if sink_present; then
            # wireplumber has the sink; give it a moment to finish wiring the
            # default-node links before Kodi enumerates.
            sleep 2
            ${tv-session-bounce}/bin/tv-session-bounce
            return
          fi
          sleep 1
        done
        echo "sink never appeared after 30s - leaving it for tv-watchdog" >&2
      }

      # `unknown` on the first pass, so starting this service does not itself
      # bounce the TV - only a genuine off -> on transition does.
      prev=unknown
      check() {
        if present; then cur=on; else cur=off; fi
        [ "$prev" = off ] && [ "$cur" = on ] && react
        prev=$cur
      }

      check

      # ALSA publishes the HDMI jack as a kcontrol ('HDMI/DP,pcm=3 Jack' and
      # three siblings), and `alsactl monitor` blocks until one of them
      # changes - so this reacts the instant the TV offers audio instead of
      # discovering it up to a poll-interval late. The 60s read timeout is a
      # heartbeat, not a poll: it only exists so a missed or coalesced event
      # cannot strand the TV until someone presses play.
      while :; do
        rc=0
        read -r -t 60 _event || rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -gt 128 ]; then
          # 0 = a jack control changed, >128 = the heartbeat timeout
          check
        else
          echo "alsactl monitor ended (rc=$rc); exiting for a restart" >&2
          exit 1
        fi
      done < <(alsactl monitor hw:0)
    '';
  };

  # The backstop, for anything the HDMI transition misses. Both known audio
  # failures are explicit in kodi.log, and a stranded greeter is visible in
  # the process table, so this checks for all three.
  tv-watchdog = pkgs.writeShellApplication {
    name = "tv-watchdog";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils pkgs.procps pkgs.gnugrep ];
    text = ''
      set -uo pipefail

      log=/var/lib/kiosk/.kodi/temp/kodi.log
      state=''${STATE_DIRECTORY:-/var/lib/tv-watchdog}
      offset_file=$state/offset
      stamp=$state/last-bounce
      stranded=$state/stranded-passes

      bounce_if_allowed() {
        reason=$1
        # Never loop. If one bounce did not fix it, a second one 90s later
        # will not either, and a restart storm on the TV is worse than
        # silence - it also destroys the evidence.
        now=$(date +%s)
        if [ -f "$stamp" ] && [ "$((now - $(cat "$stamp")))" -lt 900 ]; then
          echo "detected: $reason - bounced less than 15 min ago, leaving it alone" >&2
          exit 0
        fi
        echo "$now" > "$stamp"
        echo "detected: $reason - bouncing"
        ${tv-session-bounce}/bin/tv-session-bounce
        exit 0
      }

      # 1. GDM has stranded its greeter on the living-room TV. This is what
      #    2026-10-02 left behind when Kodi was killed: the session ended,
      #    nothing respawned it, and the greeter sat there until someone
      #    noticed.
      #
      #    The test is who owns *seat0* - the TV - and not whether an `angus`
      #    session exists anywhere. angus has a lingering systemd session on
      #    this box at all times (agents, ssh), so "is angus logged in" would
      #    suppress this check permanently.
      #
      #    The greeter is also the legitimate state when Angus has logged out
      #    of Kodi to pick GNOME, so it has to persist across two passes
      #    (3 minutes) before this acts. That is longer than it takes to
      #    choose a session and shorter than anyone's patience.
      active=$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null || true)
      owner=""
      [ -n "$active" ] && owner=$(loginctl show-session "$active" -p Name --value 2>/dev/null || true)

      case $owner in
        kiosk|angus)
          rm -f "$stranded"
          ;;
        *)
          seen=0
          [ -f "$stranded" ] && seen=$(cat "$stranded")
          seen=$((seen + 1))
          echo "$seen" > "$stranded"
          if [ "$seen" -ge 2 ]; then
            bounce_if_allowed "seat0 belongs to $owner - greeter stranded on the TV"
          fi
          echo "seat0 belongs to $owner (pass $seen of 2) - waiting one more pass" >&2
          ;;
      esac

      # 2. Kodi's own report, read forward from wherever the last pass got to.
      [ -f "$log" ] || exit 0
      size=$(stat -c %s "$log")
      offset=0
      [ -f "$offset_file" ] && offset=$(cat "$offset_file")
      # Kodi truncates its log on start, so a shrinking file means a new run.
      [ "$size" -lt "$offset" ] && offset=0
      echo "$size" > "$offset_file"

      [ "$size" -gt "$offset" ] || exit 0
      new=$(tail -c "+$((offset + 1))" "$log")

      case $new in
        *"MakeStream - could not create stream"*)
          bounce_if_allowed "Kodi could not create an audio stream" ;;
        *"AddPacketsRenderer - timeout"*)
          bounce_if_allowed "the audio sink took a stream and stalled" ;;
      esac
    '';
  };
in
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

  # 📌 Running Kodi as a supervised unit of its own (Restart=always, its own
  # tty, no GDM) was tried on 2026-10-03 and backed out. It would be the
  # better shape - self-healing, and `systemctl restart kodi` as the recovery
  # primitive instead of a whole-session bounce - but rootless X on a
  # systemd-managed VT never becomes the active session on seat0, so logind
  # hands X a *paused* DRM fd ("Error systemd-logind returned paused fd for
  # drm node") and X dies with "no screens found". Making that work means
  # owning the VT handoff GDM currently does. Worth revisiting with cage +
  # kodi-wayland, where there is no X server to hand a seat to.

  # Kodi's remote-control and audio settings cannot live in the flake
  # directly: Kodi owns guisettings.xml and rewrites it on exit, so anything
  # written there declaratively is discarded the first time the session ends.
  #
  # Instead this re-asserts them before the session starts, while Kodi is not
  # running. It is ordered before display-manager for exactly that reason -
  # patching the file underneath a live Kodi is how the settings got lost the
  # first time round.
  #
  # The web-server password is read from /var/lib/morty-backup/kodi-web.password
  # rather than the flake, same as the restic, rclone and NordVPN credentials.
  systemd.services.kodi-settings = {
    description = "Re-assert Kodi's remote-control and audio settings before the session starts";
    wantedBy = [ "display-manager.service" ];
    before = [ "display-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${./kodi-settings.py}";
    };
  };

  # --- why the TV goes silent, and what actually fixes it ---
  #
  # Three silent evenings (2026-09-29, 09-30, 10-02) had one cause, found on
  # 2026-10-03: **the HDMI audio sink does not exist while the TV is in
  # standby.**
  #
  # The TV drops the audio ELD in standby, so ALSA reports every HDMI profile
  # `available = no`, wireplumber switches the card to its `off` profile and
  # removes the sink, and pipewire publishes `auto_null` - a Dummy Output - in
  # its place. Kodi, whose device setting is `Default`, binds that dummy sink;
  # it even rewrites its own setting to point at it
  # ("ValidateOutputDevices: audio output device setting has been updated").
  #
  # When the TV wakes, the HDMI sink returns and the dummy sink disappears
  # *underneath Kodi*. Kodi reopens a sink that no longer exists and
  # `ActiveAE::MakeStream` fails: video plays, nothing comes out. Restarting
  # the session while the TV is on fixes it instantly, every time, because the
  # enumeration then finds the real sink.
  #
  # ⚠️ Neither defense added on 2026-09-30 could have worked, and one was a
  # cause. `session.suspend-timeout-seconds = 0` cannot keep a node alive that
  # has been *removed* rather than suspended. And the 04:30 nightly bounce
  # guaranteed Kodi started every single day while the TV was off - which is
  # exactly the state that produces the bug. It is gone.
  #
  # Forcing the HDMI profile on regardless of availability was tried on
  # 2026-10-03 and rejected: the sink does appear, but pipewire will not route
  # into a sink whose ALSA route is unavailable ("no target node available"),
  # so the box is left with no usable output at all.
  #
  # What is left is to react to the TV rather than fight it.

  # Keep the PCM open for as long as the TV is actually on, so nothing has to
  # cold-open a sink mid-evening. No longer load-bearing - it cannot survive
  # standby - but it is free and removes one more reopen.
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

  # Defense 1, proactive: bounce when the TV's audio link returns, so Kodi is
  # already bound to the real sink by the time anyone presses play.
  systemd.services.tv-hdmi-watch = {
    description = "Bounce the kiosk session when the TV's HDMI audio link returns";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${tv-hdmi-watch}/bin/tv-hdmi-watch";
      Restart = "always";
      RestartSec = 10;
    };
  };

  # Defense 2, reactive: Kodi's own audio failures, and a greeter left
  # stranded on the TV.
  systemd.services.tv-watchdog = {
    description = "Bounce the kiosk session if the TV is silent or stranded";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "tv-watchdog";
      ExecStart = "${tv-watchdog}/bin/tv-watchdog";
    };
  };

  systemd.timers.tv-watchdog = {
    description = "Check the TV session every 90s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "90s";
      AccuracySec = "10s";
    };
  };
}
