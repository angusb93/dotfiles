#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

BATTERY_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATTERY_INFO" | grep -o "[0-9]*%" | head -1 | tr -d '%')
CHARGING=$(echo "$BATTERY_INFO" | grep -c "AC Power" || true)

if [ -z "$PERCENTAGE" ]; then
  sketchybar --set battery label="?"
  exit 0
fi

COLOR=$BAR_FG
if [ "$PERCENTAGE" -lt 20 ] && [ "$CHARGING" -eq 0 ]; then
  COLOR=$ACCENT_ORANGE
fi

if [ "$CHARGING" -gt 0 ]; then
  sketchybar --set battery label="⚡ ${PERCENTAGE}%" label.color=$COLOR
else
  sketchybar --set battery label="${PERCENTAGE}%" label.color=$COLOR
fi
