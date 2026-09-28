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
#   /var/lib/morty-backup/gyb/client_secrets.json  OAuth client
#   /var/lib/morty-backup/gyb/oauth2.txt           the token itself
#
# Both are produced by authorising once on the Mac and copying the files over,
# the same route the Drive token took - morty has no browser, and a token minted
# elsewhere is no less valid.
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
    unitConfig.ConditionPathExists = "${configFolder}/oauth2.txt";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = toString [
        "${pkgs.gyb}/bin/gyb"
        "--email" "angusbuick@gmail.com"
        "--action" "backup"
        "--config-folder" configFolder
        "--local-folder" "/tank/backup/google/mail"
        # Trusts the local index instead of re-listing every message every
        # night. The plan's cadence is nightly and new mail only; a full
        # reconcile is what --noresume is for, run by hand if ever needed.
        "--fast-incremental"
      ];
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
