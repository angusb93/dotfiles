# Local snapshots and pool-to-pool replication.
#
# The two halves of "sync is not backup" from wiki/projects/backup-architecture.md:
#
#   sanoid  - takes ZFS snapshots on a schedule and prunes them by policy, so a
#             deletion or a bad edit is recoverable from the state before it.
#   syncoid - wraps zfs send/recv to replicate those snapshots from the flash
#             pool onto tank's RAIDZ2, sending only the incremental difference.
#
# Retention follows the table in wiki/projects/data-migration-weekend.md. sanoid
# has no "forever", so where the plan says forever the count is simply large.
{ ... }:
{
  services.sanoid = {
    enable = true;
    # sanoid decides what is due each time it runs; hourly is its own default
    # and costs nothing when nothing is due.
    interval = "hourly";

    # sanoid's shipped defaults are hourly=48, daily=90, monthly=6, and they
    # apply to every bucket a dataset does not name. Without this template the
    # config below would quietly mean something other than what it says - the
    # media library asked for "4 weekly" and got 90 dailies and 6 monthlies on
    # top. Every dataset starts from zero and opts in to exactly the buckets in
    # the retention table.
    templates.none = {
      hourly = 0;
      daily = 0;
      weekly = 0;
      monthly = 0;
      yearly = 0;
    };

    datasets = {
      # --- morty-authoritative, replicated to tank below ---
      "fast/vault" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        autosnap = true;
        autoprune = true;
      };
      "fast/data" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        autosnap = true;
        autoprune = true;
      };

      # --- received copies of the above ---
      # autosnap off: these snapshots arrive from syncoid, they are not taken
      # here. Retention is deliberately longer than the source (90d vs 30d) so
      # the most recent common snapshot always survives pruning on this side -
      # lose that and the next run falls back to a full send.
      # Listed per child rather than as a recursive parent - see the note on
      # the google datasets below for why that distinction matters here.
      "tank/backup/morty/vault" = {
        useTemplate = [ "none" ];
        daily = 90;
        monthly = 24;
        autosnap = false;
        autoprune = true;
      };
      "tank/backup/morty/data" = {
        useTemplate = [ "none" ];
        daily = 90;
        monthly = 24;
        autosnap = false;
        autoprune = true;
      };

      # --- pulled copies of Google-authoritative data ---
      # The plan says "snapshot after each pull". The pulls run at 02:00, so the
      # daily snapshot is pinned to 03:00 rather than sanoid's 23:59 default:
      # close enough behind the pull to be the post-pull state, far enough that
      # a slow pull does not race it. This is what makes the Drive cleanup safe
      # to undo - the snapshot before it still has everything.
      # Named per child, not as a recursive parent. The module delegates zfs
      # permissions to a systemd DynamicUser for exactly the datasets listed
      # here, and a delegation on the parent did not reach the children: the
      # unit ran as sanoid, snapshotted nothing under tank/backup/google and
      # exited success, while the identical sanoid run as root took all four
      # immediately. It logged nothing either way.
      "tank/backup/google/drive" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        daily_hour = 3;
        daily_min = 0;
        autosnap = true;
        autoprune = true;
      };
      "tank/backup/google/mail" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        daily_hour = 3;
        daily_min = 0;
        autosnap = true;
        autoprune = true;
      };
      "tank/backup/google/photos" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        daily_hour = 3;
        daily_min = 0;
        autosnap = true;
        autoprune = true;
      };
      "tank/backup/google/takeout" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        daily_hour = 3;
        daily_min = 0;
        autosnap = true;
        autoprune = true;
      };

      # --- lives only on morty ---
      # archive/ is the one pool of data with no original anywhere else, so it
      # keeps monthlies indefinitely - sanoid has no "forever", hence the count.
      "tank/archive" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 1200;
        autosnap = true;
        autoprune = true;
      };

      # Replaceable: this guards against a bad rm, not against history.
      "tank/media/library" = {
        useTemplate = [ "none" ];
        weekly = 4;
        autosnap = true;
        autoprune = true;
      };

      # The Immich library. Google Photos is its second home - the phone
      # uploads to both - so this needs no offsite copy, but it does need
      # snapshots: they are the only thing standing between a mis-swipe in the
      # app and a photo that is gone from morty.
      #
      # Kept deliberately modest. If the Immich storage template is ever
      # changed, its migration job rewrites the path of every file in the
      # library, and every snapshot then pins a full copy of the old layout.
      "tank/media/photos" = {
        useTemplate = [ "none" ];
        daily = 30;
        monthly = 12;
        autosnap = true;
        autoprune = true;
      };

      # tank/media/recordings gets a policy once the recordings move off
      # fast/media.
    };
  };

  services.syncoid = {
    enable = true;
    # After sanoid's 03:00 daily and the restic run at 03:30, so the night's
    # snapshot is the one that gets replicated.
    interval = "04:30";

    # Both pools are encrypted and both keys are loaded at boot, so the stream
    # is decrypted on send and re-encrypted under tank's key on receive - never
    # at rest unencrypted. A raw send would skip the round trip but make each
    # received dataset its own encryption root, which is a restore-time trap
    # for no gain on a local replication.
    #
    # recvOptions "u": receive without mounting. These are copies, and the
    # layout rule is that nothing under backup/ is edited by hand - an
    # unmounted dataset cannot be. It also avoids mounting as the unprivileged
    # syncoid user, which needs privileges delegation alone does not grant.
    # Browse one with `zfs mount tank/backup/morty/vault` when needed.
    commands = {
      "fast/vault" = {
        target = "tank/backup/morty/vault";
        recvOptions = "u";
      };
      "fast/data" = {
        target = "tank/backup/morty/data";
        recvOptions = "u";
      };
    };

    # syncoid runs as its own unprivileged user here and the module delegates
    # the zfs permissions it needs, so stop it reaching for sudo.
    #
    # --exclude-snaps: `restic-backups-drive` takes a snapshot literally named
    # `@restic` before each run and destroys it afterwards, so the name is
    # reused nightly with a different GUID every time. Replicating it means the
    # target ends up holding a stale `@restic`, and the next incremental send
    # dies on:
    #
    #   cannot restore to tank/backup/morty/vault@restic: destination already exists
    #
    # That is exactly what happened on 2026-09-29 and 2026-09-30, silently
    # breaking vault replication for two nights. The snapshot is ephemeral
    # tooling state and has no business being replicated at all.
    commonArgs = [
      "--no-privilege-elevation"
      "--exclude-snaps=^restic$"
    ];
  };
}
