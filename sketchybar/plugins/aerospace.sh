#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

WORKSPACES=(1 A B C D E F G I M N O P Q R S T U V W X Y Z)
FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)
OCCUPIED=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

MAX_APP_LEN=5

app_for_workspace() {
  local app
  app=$(aerospace list-windows --workspace "$1" 2>/dev/null \
    | head -1 \
    | awk -F' \\| ' '{print $2}' \
    | sed 's/^ *//;s/ *$//')
  if [ "${#app}" -gt "$MAX_APP_LEN" ]; then
    app="${app:0:$MAX_APP_LEN}…"
  fi
  echo "$app"
}

# Detect if built-in (notch) display is active (cached for 60s)
NOTCH_CACHE="/tmp/sketchybar_has_notch"
if [ -f "$NOTCH_CACHE" ] && [ "$(( $(date +%s) - $(stat -f%m "$NOTCH_CACHE") ))" -lt 60 ]; then
  HAS_NOTCH=$(cat "$NOTCH_CACHE")
else
  HAS_NOTCH=false
  if /usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "built-in"; then
    HAS_NOTCH=true
  fi
  echo "$HAS_NOTCH" > "$NOTCH_CACHE"
fi

# Collect visible workspaces in order
VISIBLE=()
for ws in "${WORKSPACES[@]}"; do
  if [ "$ws" = "$FOCUSED" ] || echo "$OCCUPIED" | grep -qx "$ws"; then
    VISIBLE+=("$ws")
  fi
done

for ws in "${WORKSPACES[@]}"; do
  if [ "$ws" = "$FOCUSED" ]; then
    app=$(app_for_workspace "$ws")
    label="${ws}:${app}"
    sketchybar --set space.$ws \
      drawing=on \
      label="$label" \
      background.drawing=on \
      background.color=$ACCENT \
      label.color=0xff000000
  elif echo "$OCCUPIED" | grep -qx "$ws"; then
    app=$(app_for_workspace "$ws")
    label="${ws}:${app}"
    sketchybar --set space.$ws \
      drawing=on \
      label="$label" \
      background.drawing=on \
      background.color=$INACTIVE \
      label.color=$SUBTEXT
  else
    sketchybar --set space.$ws drawing=off
  fi
done

# Position items: q/e split for notch display, center for external
if [ "$HAS_NOTCH" = true ]; then
  TOTAL=${#VISIBLE[@]}
  HALF=$(( (TOTAL + 1) / 2 ))
  for i in "${!VISIBLE[@]}"; do
    ws="${VISIBLE[$i]}"
    if [ "$i" -lt "$HALF" ]; then
      sketchybar --set space.$ws position=q
    else
      sketchybar --set space.$ws position=e
    fi
  done
else
  for ws in "${VISIBLE[@]}"; do
    sketchybar --set space.$ws position=center
  done
fi

