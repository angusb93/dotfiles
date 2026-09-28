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
      "tank/backup/morty" = {
        useTemplate = [ "none" ];
        recursive = true;
        processChildrenOnly = true;
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
      "tank/backup/google" = {
        useTemplate = [ "none" ];
        recursive = true;
        processChildrenOnly = true;
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

      # tank/media/photos gets a policy when Immich lands, and
      # tank/media/recordings once the recordings move off fast/media.
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
    commonArgs = [ "--no-privilege-elevation" ];
  };
}
