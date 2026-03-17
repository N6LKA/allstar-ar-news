#!/bin/bash
# status.sh - Show allstar-ar-news playback status and upcoming schedule.
# Copyright (c) 2026 Larry K. Aycock (N6LKA)
# https://github.com/N6LKA/allstar-ar-news
#
# Usage: status.sh

INSTALL_DIR="/etc/asterisk/scripts/ar-news"
CONFIG_FILE="$INSTALL_DIR/ar-news.conf"

echo ""
echo "=============================================="
echo "  AllStar AR News Player - Status"
echo "=============================================="
echo ""

# --- Check installation ---
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "ERROR: allstar-ar-news is not installed ($INSTALL_DIR not found)."
    echo ""
    exit 1
fi

# --- Load config ---
NEWSLOGFILE=""
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=ar-news.conf
    source "$CONFIG_FILE"
fi

# --- Check if play_news.sh is currently running ---
echo "--- Playback Status ---"
echo ""
PLAY_PID=$(pgrep -f "play_news.sh" 2>/dev/null | head -1)
if [[ -n "$PLAY_PID" ]]; then
    PLAY_CMD=$(ps -p "$PLAY_PID" -o args= 2>/dev/null)
    PLAY_START=$(ps -p "$PLAY_PID" -o lstart= 2>/dev/null)
    echo "  Status  : PLAYING"
    echo "  PID     : $PLAY_PID"
    echo "  Started : $PLAY_START"
    echo "  Command : $PLAY_CMD"
else
    echo "  Status  : Not playing"
fi

# --- Upcoming schedule from cron ---
echo ""
echo "--- Scheduled Broadcasts (asterisk crontab) ---"
echo ""

CRON_LINES=$(crontab -u asterisk -l 2>/dev/null | grep "play_news\.sh")
if [[ -z "$CRON_LINES" ]]; then
    echo "  No play_news.sh cron jobs found."
else
    DAY_NAMES=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
    slot=1
    while IFS= read -r line; do
        # Parse: MM HH * * DOW /path/play_news.sh TYPE TIME NODE MODE
        read -r cron_min cron_hr _ _ cron_dow rest <<< "$line"
        news_type=$(echo "$rest" | awk '{print $2}')
        play_time=$(echo "$rest" | awk '{print $3}')
        play_node=$(echo "$rest" | awk '{print $4}')
        play_mode=$(echo "$rest" | awk '{print $5}')
        day_name="${DAY_NAMES[$cron_dow]:-Day$cron_dow}"
        echo "  Slot $slot: $news_type  ${day_name}s at $play_time  (node $play_node, mode ${play_mode:-L})"
        ((slot++))
    done <<< "$CRON_LINES"
fi

# --- Recent log entries ---
echo ""
echo "--- Recent Activity (last 10 log entries) ---"
echo ""
if [[ -n "$NEWSLOGFILE" && -f "$NEWSLOGFILE" ]]; then
    tail -n 10 "$NEWSLOGFILE" | sed 's/^/  /'
else
    if [[ -z "$NEWSLOGFILE" ]]; then
        echo "  NEWSLOGFILE not set in ar-news.conf."
    else
        echo "  Log file not found: $NEWSLOGFILE"
    fi
fi

echo ""
echo "=============================================="
echo ""
exit 0
