# Fetch the offline reference library onto tank.
#
# These were originally pulled by a hand-rolled `systemd-run` transient unit,
# which is how the Gutenberg download came to die at 63% with nothing watching
# and no way to resume it. A declared unit is resumable, idempotent and
# re-runnable, which matters when one file is 119 GB.
#
# No timer. ZIMs are dated snapshots, not a feed - refreshing means editing the
# list below to a newer date and running the unit again, not re-downloading
# 122 GB on a schedule.
#
# Run it with: systemctl start kiwix-fetch
{ pkgs, ... }:
let
  dir = "/tank/reference/kiwix";
  zims = [
    "https://download.kiwix.org/zim/ifixit/ifixit_en_all_2025-12.zim"
    "https://download.kiwix.org/zim/wikipedia/wikipedia_en_all_maxi_2026-08.zim"
    "https://download.kiwix.org/zim/gutenberg/gutenberg_en_all_2023-08.zim"
  ];
in
{
  systemd.services.kiwix-fetch = {
    description = "Download and verify the Kiwix ZIMs in tank/reference/kiwix";
    after = [ "network-online.target" "zfs.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      # 119 GB from a mirror that gives about 1 MiB/s on a bad day.
      TimeoutStartSec = "48h";
      ExecStart = pkgs.writeShellScript "kiwix-fetch" ''
        set -u
        export PATH=${
          pkgs.lib.makeBinPath (with pkgs; [
            wget
            curl
            coreutils
          ])
        }

        mkdir -p ${dir}
        cd ${dir}

        rc=0
        for url in ${pkgs.lib.escapeShellArgs zims}; do
          file=$(basename "$url")

          # The published checksum is the source of truth for "already done".
          # Size is not: a truncated download has a plausible size.
          want=$(curl -fsSL --max-time 60 "$url.sha256" | cut -d' ' -f1 || true)
          if [ -z "$want" ]; then
            echo "FAILED could not fetch checksum for $file"
            rc=1
            continue
          fi

          if [ -f "$file" ] && [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$want" ]; then
            echo "OK $file (already verified, skipping)"
            continue
          fi

          # -c resumes a partial file rather than starting over, which is the
          # whole point. The mirror redirects to lb.download.kiwix.org and
          # advertises Accept-Ranges, so a resume picks up where it stopped.
          #
          # The outer loop exists because wget's own --tries does not help when
          # a mirror starts refusing connections outright: it burns all twenty
          # attempts against the same dead host and gives up. Gutenberg died
          # that way at 60.96 GiB when ftp.nluug.nl stopped answering. Going
          # back through download.kiwix.org re-runs the load balancer and
          # usually lands on a different mirror.
          echo "fetching $file"
          for attempt in 1 2 3 4 5; do
            wget -c --progress=dot:giga --tries=5 --waitretry=30 \
                 --read-timeout=120 --timeout=60 "$url" && break
            echo "attempt $attempt for $file ended early; re-resolving the mirror"
            sleep 30
          done

          if [ "$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)" = "$want" ]; then
            echo "OK $file"
          else
            echo "FAILED $file (checksum mismatch or incomplete - re-run to resume)"
            rc=1
          fi
        done
        exit "$rc"
      '';
    };
  };
}
