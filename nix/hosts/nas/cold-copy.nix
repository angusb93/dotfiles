# The cold copies: homes on USB drives that live elsewhere, offline.
#
# Rule 0 gives everything two homes, morty and Google. Both are online, and
# both answer to the same Google account and the same root on morty, so one
# bad day - a compromised account, a sync that deletes, a fire - can reach
# both. These disks are the copies nothing online can touch: filled here,
# then unplugged and carried away.
#
#   work  `cold-copy`      Micron 3400 2 TB in a USB enclosure. Lives in the
#                          work off-site kit, refreshed every month or two,
#                          keeps two years of history.
#   aus   `cold-copy-aus`  Samsung 860 EVO 500 GB. Lives in Australia and is
#                          refreshed only when somebody travels, so it keeps
#                          the latest state only - the one copy that is not in
#                          London.
#
# Layout of each disk, chosen 2026-10-02 so the disaster restore needs only a
# Mac:
#
#   p1  APFS (encrypted)  "mac-1pux"   - the 1Password .1pux export. Formatted
#                                        and written by the Mac; morty never
#                                        mounts it.
#   p2  exFAT             <partlabel>  - two restic repositories, written by
#                                        the unit.
#
#   morty/   restic `copy` of the Drive repository (fast/*, tank/archive,
#            /var/lib/agent) - same snapshots, same chunker, so a copy is
#            incremental and the Drive repository is proved readable each time.
#   google/  restic backup of tank/backup/google (Drive, Mail, Photos,
#            Takeout) - Google's data, so a dead Google account is survivable.
#
# Both repositories use the restic repository password morty already holds,
# so nothing new reaches morty: a disk is safe to lose because restic
# encrypts every byte on p2, and the .1pux is behind the APFS passphrase
# ("morty cold SSD encryption key"), which only the Mac ever sees.
#
# exFAT has no journal. The unit runs fsck before mounting and unmounts
# itself at the end; only unplug once the alert says it is safe.
#
# Run: plug the disk into morty, `sudo systemctl start cold-copy` (or
# `cold-copy-aus`), wait for "Cold copy done" in 🚨 Alerts.
{
  config,
  lib,
  pkgs,
  morty-alert,
  backup-stamp,
  ...
}:
let
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

  # morty/ mirrors the Drive repository, so it is pruned with the Drive
  # repository's own policy (backup.nix). Anything stricter would forget
  # snapshots that Drive still holds, and the next `copy` would fetch them
  # all over again.
  keepMorty = [
    "--keep-daily"
    "7"
    "--keep-weekly"
    "8"
    "--keep-monthly"
    "12"
    "--keep-yearly"
    "10"
  ];

  drives = {
    cold-copy = {
      label = "work";
      partlabel = "morty-cold";
      where = "take to work";
      # Refreshed every month or two, so every run is worth keeping a while:
      # the last few, then one a month for two years.
      keepGoogle = [
        "--keep-last"
        "6"
        "--keep-monthly"
        "24"
        "--keep-yearly"
        "10"
      ];
    };
    cold-copy-aus = {
      label = "aus";
      partlabel = "morty-cold-aus";
      where = "take to Australia";
      # 500 GB against ~310 GB of data: no room for history, and a disk that
      # is refreshed once a year has little use for it.
      keepGoogle = [
        "--keep-last"
        "1"
      ];
    };
  };

  mkCopy =
    name:
    {
      label,
      partlabel,
      where,
      keepGoogle,
    }:
    let
      mnt = "/mnt/${name}";
      part = "/dev/disk/by-partlabel/${partlabel}";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        util-linux
        exfatprogs
        restic
        rclone
        jq
        gawk
        config.boot.zfs.package
        morty-alert
        backup-stamp
      ];
      text = ''
        export RESTIC_PASSWORD_FILE=${pass}
        export RESTIC_FROM_PASSWORD_FILE=${pass}
        export RCLONE_CONFIG=/var/lib/morty-backup/rclone.conf
        export RESTIC_CACHE_DIR=/var/cache/cold-copy

        fail() {
          echo "$1" | morty-alert "Cold copy (${label}) FAILED" || true
          echo "$1" >&2
          exit 1
        }

        [ -b ${part} ] || fail "No partition labelled ${partlabel} - is the ${label} cold drive plugged in?"

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

        if other=$(findmnt -n -o TARGET -S "$(readlink -f ${part})"); then
          fail "${partlabel} is already mounted at $other - something else grabbed it; unmount it first"
        fi

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

        restic -r ${mnt}/morty forget --prune ${toString keepMorty}
        restic -r ${mnt}/google forget --prune ${toString keepGoogle}

        for repo in morty google; do
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

        # Only reached when every step above succeeded and the disk unmounted
        # cleanly, so this is the one honest record that the copy happened.
        # staleness.nix reads it because systemd does not keep a usable one for
        # a unit with no timer - see the cold-copy note in its watched table.
        backup-stamp ${name}

        printf '%s\n\nUnmounted - safe to unplug and ${where}.\n' "$summary" \
          | morty-alert "Cold copy (${label}) done"
      '';
    };

  # udisks must leave every cold partition alone - see below.
  hidden = [ "mac-1pux" ] ++ lib.mapAttrsToList (_: d: d.partlabel) drives;
in
{
  environment.systemPackages = [ pkgs.exfatprogs ];

  # The TV kiosk session auto-mounted the backup partition for the kiosk user
  # the first time it was plugged in, and UDISKS_IGNORE alone did not stop it:
  # Kodi asks udisks to mount removable filesystems itself rather than waiting
  # for a desktop to offer them. Marking the partitions as system devices moves
  # the mount behind polkit's admin check, which the kiosk user cannot pass.
  # Scoped to the cold drives' partition names - every other USB drive still
  # mounts in Kodi as before.
  services.udev.extraRules = lib.concatMapStrings (p: ''
    ENV{ID_PART_ENTRY_NAME}=="${p}", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_SYSTEM}="1", ENV{UDISKS_AUTO}="0"
  '') hidden;

  systemd.tmpfiles.rules = [ "d /var/cache/cold-copy 0700 root root -" ];

  # Started by hand when a disk is attached - never on a timer, because a disk
  # is only here a day or so at a time. staleness.nix nags when the work
  # drive's refresh is overdue, which doubles as the reminder to bring it
  # home; the Australian drive is refreshed when somebody travels, so it is
  # deliberately not watched.
  systemd.services = lib.mapAttrs (name: d: {
    description = "Refresh the cold off-site drive (${d.label})";
    after = [
      "network-online.target"
      "zfs.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe (mkCopy name d);
      TimeoutStartSec = "infinity";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  }) drives;
}
