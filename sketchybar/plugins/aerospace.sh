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

# Collect visible workspaces in order
VISIBLE=()
for ws in "${WORKSPACES[@]}"; do
  if [ "$ws" = "$FOCUSED" ] || echo "$OCCUPIED" | grep -qx "$ws"; then
    VISIBLE+=("$ws")
  fi
done

# Split visible workspaces evenly: first half → q (left of notch), second half → e (right of notch)
TOTAL=${#VISIBLE[@]}
HALF=$(( (TOTAL + 1) / 2 ))

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

# Assign positions: first half to q, second half to e
for i in "${!VISIBLE[@]}"; do
  ws="${VISIBLE[$i]}"
  if [ "$i" -lt "$HALF" ]; then
    sketchybar --set space.$ws position=q
  else
    sketchybar --set space.$ws position=e
  fi
done
