# Unpack a verified Google Takeout export onto tank.
#
# No shebang: takeout-extract.nix wraps this with writeShellScriptBin, which
# supplies one and puts bash, tar, unzip and rsync on PATH.
#
# The archives are hash-checked against Drive before this runs; tar/unzip will
# fail loudly on a corrupt member anyway, and errexit stops the whole run.
#
# First extract of a given export goes straight into extracted/. From the second
# monthly export on, unpack to staging/ and rsync into extracted/ instead, so
# tank only grows by what actually changed rather than rewriting 356 GiB into
# every snapshot.
set -eu

src=/tank/backup/google/takeout/archives
dst=/tank/backup/google/takeout/extracted
photos=/tank/backup/google/photos

mkdir -p "$dst"

# Four at a time: gzip decompression of one stream is single-threaded, so the
# parallelism has to come from running separate archives concurrently.
pids=""
n=0
for a in "$src"/*.tgz "$src"/*.zip; do
  [ -e "$a" ] || continue
  case "$a" in
    *.tgz) tar -xzf "$a" -C "$dst" & ;;
    *.zip) unzip -q -o "$a" -d "$dst" & ;;
  esac
  pids="$pids $!"
  n=$((n + 1))
  if [ "$((n % 4))" -eq 0 ]; then
    for p in $pids; do wait "$p"; done
    pids=""
    echo "== $n archives done"
  fi
done
for p in $pids; do wait "$p"; done
echo "== all $n archives extracted"

du -sh "$dst" || true
ls "$dst" || true

# Google Photos is 181 GB of the export and has its own dataset in the layout,
# separate from the rest of Takeout. rsync rather than mv: the two are different
# datasets, so this is a copy either way, and --remove-source-files lets it be
# resumed if it is interrupted.
if [ -d "$dst/Takeout/Google Photos" ]; then
  echo "== moving Google Photos to $photos"
  mkdir -p "$photos"
  rsync -a --remove-source-files "$dst/Takeout/Google Photos/" "$photos/"
  find "$dst/Takeout/Google Photos" -type d -empty -delete
  du -sh "$photos"
fi

echo "== done"
