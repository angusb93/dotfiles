#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

WORKSPACES=(1 A B C D E F G I M N O P Q R S T U V W X Y Z)
FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)
OCCUPIED=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

app_for_workspace() {
  aerospace list-windows --workspace "$1" 2>/dev/null \
    | head -1 \
    | awk -F' \\| ' '{print $2}' \
    | sed 's/^ *//;s/ *$//'
}

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
