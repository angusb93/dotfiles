# The cold copy: a third home on a USB SSD that lives at work, offline.
#
# Rule 0 gives everything two homes, morty and Google. Both are online, and
# both answer to the same Google account and the same root on morty, so one
# bad day - a compromised account, a sync that deletes, a fire - can reach
# both. This disk is the copy nothing online can touch: filled here every
# month or two, then unplugged and carried to the work off-site kit.
#
# Layout, chosen 2026-10-02 so the disaster restore needs only a Mac:
#
#   p1  64 GiB  APFS (encrypted)  "mac-1pux"    - the 1Password .1pux export.
#                                                 Formatted and written by the
#                                                 Mac; morty never mounts it.
#   p2  rest    exFAT             "morty-cold"  - two restic repositories,
#                                                 written by this unit.
#
#   morty/   restic `copy` of the Drive repository (fast/*, tank/archive,
#            /var/lib/agent) - same snapshots, same chunker, so a copy is
#            incremental and the Drive repository is proved readable each time.
#   google/  restic backup of tank/backup/google (Drive, Mail, Photos,
#            Takeout) - Google's data, so a dead Google account is survivable.
#
# Both repositories use the restic repository password morty already holds,
# so nothing new reaches morty: the disk is safe to lose because restic
# encrypts every byte on p2, and the .1pux is behind the APFS passphrase
# ("morty cold SSD encryption key"), which only the Mac ever sees.
#
# exFAT has no journal. The unit runs fsck before mounting and unmounts
# itself at the end; only unplug once the alert says it is safe.
#
# Run: plug the disk into morty, `sudo systemctl start cold-copy`, wait for
# "Cold copy done" in 🚨 Alerts. Restore drill: wiki/projects/data-migration-weekend.md.
{
  config,
  lib,
  pkgs,
  morty-alert,
  ...
}:
let
  mnt = "/mnt/cold";
  part = "/dev/disk/by-partlabel/morty-cold";
  pass = "/var/lib/morty-backup/restic.pass";
  drive = "rclone:gdrive:morty-backup";
  snap = "cold";

  # Google's data. The source of truth is Google itself; this is the copy for
  # the day the account is gone.
  google = [
    "tank/backup/google/drive"
    "tank/backup/google/mail"
    "tank/backup/google/photos"
    "tank/backup/google/takeout"
  ];

  # The disk is refreshed every month or two, so every run is worth keeping a
  # while: the last few, then one a month for two years.
  keep = [
    "--keep-last"
    "6"
    "--keep-monthly"
    "24"
    "--keep-yearly"
    "10"
  ];

  copy = pkgs.writeShellApplication {
    name = "cold-copy";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      exfatprogs
      restic
      rclone
      jq
      config.boot.zfs.package
      morty-alert
    ];
    text = ''
      export RESTIC_PASSWORD_FILE=${pass}
      export RESTIC_FROM_PASSWORD_FILE=${pass}
      export RCLONE_CONFIG=/var/lib/morty-backup/rclone.conf
      export RESTIC_CACHE_DIR=/var/cache/cold-copy

      fail() {
        echo "$1" | morty-alert "Cold copy FAILED" || true
        echo "$1" >&2
        exit 1
      }

      [ -b ${part} ] || fail "No partition labelled morty-cold - is the cold SSD plugged in?"

      cleanup() {
        for ds in ${toString google}; do
          zfs destroy "$ds@${snap}" 2>/dev/null || true
        done
        if mountpoint -q ${mnt}; then
          sync
          umount ${mnt} || echo "umount ${mnt} failed - do NOT unplug" >&2
        fi
      }
      trap cleanup EXIT

      # No journal: repair anything an earlier unclean unplug left behind
      # before restic writes another byte.
      fsck.exfat -p ${part} || fail "fsck.exfat found errors it could not repair on ${part}"
      mkdir -p ${mnt}
      mount -t exfat -o noatime ${part} ${mnt}

      # morty/: a copy of the Drive repository. Initialised with its chunker
      # parameters so the two deduplicate identically and copy stays incremental.
      if [ ! -f ${mnt}/morty/config ]; then
        restic -r ${mnt}/morty init --from-repo ${drive} --copy-chunker-params
      fi
      restic -r ${mnt}/morty copy --from-repo ${drive}

      # google/: one consistent point in time for each dataset.
      for ds in ${toString google}; do
        zfs destroy "$ds@${snap}" 2>/dev/null || true
        zfs snapshot "$ds@${snap}"
      done
      if [ ! -f ${mnt}/google/config ]; then
        restic -r ${mnt}/google init
      fi
      restic -r ${mnt}/google backup --compression auto --host morty --tag cold \
        ${lib.concatMapStringsSep " " (ds: "/${ds}/.zfs/snapshot/${snap}") google}

      for repo in morty google; do
        restic -r ${mnt}/$repo forget --prune ${toString keep}
        # A tenth of the data re-read each time, so over a year of refreshes
        # most of the disk has been proved readable, not just the index.
        restic -r ${mnt}/$repo check --read-data-subset=10%
      done

      summary=$(
        for repo in morty google; do
          latest=$(restic -r ${mnt}/$repo snapshots --latest 1 --json | jq -r 'map(.time) | max // "none"')
          echo "$repo: latest snapshot ''${latest%%.*}"
        done
        df -h --output=used,avail ${mnt} | tail -1 | awk '{print "disk: " $1 " used, " $2 " free"}'
      )

      cleanup
      trap - EXIT
      mountpoint -q ${mnt} && fail "Copy finished but ${mnt} would not unmount - do not unplug"

      printf '%s\n\nUnmounted - safe to unplug and take to work.\n' "$summary" \
        | morty-alert "Cold copy done"
    '';
  };
in
{
  environment.systemPackages = [ pkgs.exfatprogs ];

  systemd.tmpfiles.rules = [ "d /var/cache/cold-copy 0700 root root -" ];

  # Started by hand when the disk is attached - never on a timer, because the
  # disk is only here a day or so every month or two. staleness.nix nags when
  # a refresh is overdue, which doubles as the reminder to bring it home.
  systemd.services.cold-copy = {
    description = "Refresh the cold off-site SSD";
    after = [
      "network-online.target"
      "zfs.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe copy;
      TimeoutStartSec = "infinity";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
}
