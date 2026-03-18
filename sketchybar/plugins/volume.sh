#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

VOLUME=$(osascript -e "output volume of (get volume settings)")
MUTED_STATE=$(osascript -e "output muted of (get volume settings)")

if [ "$MUTED_STATE" = "true" ]; then
  sketchybar --set volume label="vol: mute" label.color=$MUTED
else
  sketchybar --set volume label="vol: ${VOLUME}%" label.color=$BAR_FG
fi
