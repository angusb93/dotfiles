#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

CACHE_FILE="/tmp/sketchybar-meetings"
CACHE_MAX_AGE=300 # 5 minutes

# Refresh cache if stale or missing
if [ ! -f "$CACHE_FILE" ] || [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE"))) -gt $CACHE_MAX_AGE ]; then
  gcalcli agenda \
    --tsv \
    --nodeclined \
    "$(date '+%Y-%m-%dT%H:%M')" \
    "$(date '+%Y-%m-%d')T23:59" \
    2>/dev/null > "$CACHE_FILE" || true
fi

NOW=$(date +%s)
NEXT_TIME=""
NEXT_TITLE=""

while IFS=$'\t' read -r start_date start_time end_date end_time title; do
  # Skip all-day events (no start time) and the TSV header row
  [ -z "$start_time" ] && continue

  # Parse event start time
  EVENT_TS=$(date -j -f "%Y-%m-%d %H:%M" "$start_date $start_time" +%s 2>/dev/null) || continue

  # Parse event end time
  EVENT_END=$(date -j -f "%Y-%m-%d %H:%M" "$end_date $end_time" +%s 2>/dev/null) || continue

  # Skip events that have already ended
  [ "$EVENT_END" -le "$NOW" ] && continue

  NEXT_TIME="$start_time"
  NEXT_TITLE="$title"
  NEXT_TS="$EVENT_TS"
  break
done < "$CACHE_FILE"

if [ -z "$NEXT_TIME" ]; then
  sketchybar --set meeting drawing=off
  exit 0
fi

# Truncate title to ~30 chars
[ ${#NEXT_TITLE} -gt 30 ] && NEXT_TITLE="${NEXT_TITLE:0:28}.."

# Format time as HH:MM
DISPLAY_TIME=$(date -j -f "%H:%M" "$NEXT_TIME" "+%-H:%M" 2>/dev/null || echo "$NEXT_TIME")

MINS_AWAY=$(( (NEXT_TS - NOW) / 60 ))

if [ "$MINS_AWAY" -le 5 ]; then
  COLOR=$ACCENT_ORANGE
elif [ "$MINS_AWAY" -le 30 ]; then
  COLOR=$ACCENT
else
  COLOR=$BAR_FG
fi

sketchybar --set meeting \
  drawing=on \
  label="󰤙 ${DISPLAY_TIME} ${NEXT_TITLE}" \
  label.color=$COLOR
