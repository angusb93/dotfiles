# Gmail -> tank/backup/google/mail.
#
# Rule 0: Gmail is authoritative in Google, so its second home is tank and it
# needs no offsite copy. Rule 3: morty pulls.
#
# GYB rather than IMAP. mbsync would need either an app password - a bearer
# credential that walks straight past the YubiKeys the weekend was spent
# installing - or XOAUTH2, which is the same OAuth dance with worse label
# handling: IMAP turns Gmail labels into folders and duplicates a message into
# each one. GYB talks to the Gmail API, keeps labels as labels, and is properly
# incremental.
#
# The credentials are the same shape as the rclone ones and live beside them,
# root-only, deliberately not in this flake:
#   /var/lib/morty-backup/gyb/client_secrets.json        OAuth client
#   /var/lib/morty-backup/gyb/angusbuick@gmail.com.cfg  the token itself
#
# GYB names the token after the account, not oauth2.txt as GAM does - which is
# worth stating because the condition below depends on it, and a condition on a
# filename that is never created makes this unit skip itself forever while
# looking perfectly healthy.
#
# Both are produced by authorising once on the Mac and copying the files over,
# the same route the Drive token took - morty has no browser, and a token minted
# elsewhere is no less valid.
#
# ⚠️ GYB defaults its config folder to its own install directory, which under
# Nix is a read-only store path, so every action fails with "Please configure a
# project" until --config-folder points somewhere writable. That is why this
# unit passes it explicitly, and why the authorising step on the Mac has to pass
# it too.
#
# ⚠️ A Google password change revokes Gmail-scoped tokens. If this unit starts
# failing with an auth error after a password reset, that is why, and it needs
# the authorise-and-copy step again rather than a fix here.
{ pkgs, ... }:
let
  configFolder = "/var/lib/morty-backup/gyb";
in
{
  systemd.services.gmail-pull = {
    description = "Pull Gmail down to tank/backup/google/mail";
    after = [ "network-online.target" "zfs.target" ];
    wants = [ "network-online.target" ];

    # Until the token has been placed by hand this unit does nothing at all,
    # rather than failing nightly and training everyone to ignore it.
    unitConfig.ConditionPathExists = "${configFolder}/angusbuick@gmail.com.cfg";

    serviceConfig = {
      Type = "oneshot";

      # Gmail rate-limits hard on a first full pull and GYB logs every rejected
      # request, at ~2,300 lines a minute - about 1.4 million over a ten-hour
      # run, which would bury smartd, ZED and every backup unit in the journal.
      # The errors are transient and GYB retries them, so a sample is enough:
      # anything that is actually wrong will still show up within the burst.
      LogRateLimitIntervalSec = "30s";
      LogRateLimitBurst = 200;
      ExecStart = pkgs.writeShellScript "gmail-pull" ''
        set -u
        export PATH=${pkgs.lib.makeBinPath (with pkgs; [ gyb coreutils findutils gnugrep gawk ])}

        dir=/tank/backup/google/mail
        target=""

        # A single pass does not finish a large mailbox. Gmail rate-limits by
        # "Total Query Cost", GYB retries ten times and then moves on, and -
        # this is the part that matters - it still exits 0. The first run here
        # reported success having fetched 10,159 of 120,851 messages.
        #
        # So: run repeatedly until a pass stops adding anything. GYB is
        # incremental against its own index, so each pass picks up where the
        # last gave up, and a finished mailbox costs one cheap no-op pass.
        for pass in $(seq 1 12); do
          before=$(find "$dir" -name '*.eml' 2>/dev/null | wc -l)

          out=$(gyb --email angusbuick@gmail.com \
                    --action backup \
                    --config-folder ${configFolder} \
                    --local-folder "$dir" \
                    --fast-incremental 2>&1)
          printf '%s\n' "$out" | grep -v 'HttpError 403' | tail -5

          # The server-side total, taken from GYB's own first report.
          if [ -z "$target" ]; then
            target=$(printf '%s\n' "$out" | grep -oE 'needs to backup [0-9]+' | grep -oE '[0-9]+' | head -1)
          fi

          after=$(find "$dir" -name '*.eml' 2>/dev/null | wc -l)
          echo "pass $pass: $before -> $after messages"
          [ "$after" -gt "$before" ] || break
        done

        final=$(find "$dir" -name '*.eml' 2>/dev/null | wc -l)
        echo "backed up $final messages"

        # Fail loudly on a materially short backup rather than exiting 0 with a
        # tenth of the mailbox, which is what made the first run look fine.
        if [ -n "$target" ] && [ "$target" -gt 0 ]; then
          want=$(( target * 95 / 100 ))
          if [ "$final" -lt "$want" ]; then
            echo "INCOMPLETE: $final of $target messages (under 95%)" >&2
            exit 1
          fi
        fi
      '';
    };
  };

  systemd.timers.gmail-pull = {
    description = "Nightly Gmail pull";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Between the Drive pull (02:00) and sanoid's 03:00 daily, so the night's
      # snapshot covers both pulls.
      OnCalendar = "02:30";
      Persistent = true;
      RandomizedDelaySec = "10m";
      Unit = "gmail-pull.service";
    };
  };

  # gyb on PATH so the one-off authorise/estimate/count actions are available
  # without digging a store path out.
  environment.systemPackages = [ pkgs.gyb ];
}
