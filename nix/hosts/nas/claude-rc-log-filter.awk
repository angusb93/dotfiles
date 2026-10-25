# Collapse `claude remote-control`'s live status screen into a change log.
#
# With no terminal attached it still redraws the whole status block (bridge
# state, capacity, one line per session, the "continue on your phone" footer)
# every second, which put ~65k lines an hour into the journal and buried
# everything else. Each redraw after the first opens with a cursor-up escape,
# so that marks a frame boundary; a line is printed only if it was not in the
# previous frame. What survives is the transitions - connect/disconnect,
# capacity changes, sessions appearing - plus any one-off message.
{
  line = $0
  if (line ~ /^\x1b\[[0-9]+A/) {
    delete prev
    for (k in cur) prev[k] = 1
    delete cur
  }
  # Session names are OSC 8 hyperlinks; keep the URL, drop the escapes.
  line = gensub(/\x1b\]8;;([^\x07\x1b]+)(\x07|\x1b\\)([^\x1b]*)\x1b\]8;;(\x07|\x1b\\)/, "\\3 <\\1>", "g", line)
  gsub(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/, "", line)
  gsub(/\x1b\[[0-9;?]*[A-Za-z]/, "", line)
  gsub(/\r/, "", line)
  if (line ~ /^[[:space:]]*$/) next
  cur[line] = 1
  if (!(line in prev)) { print line; fflush() }
}
