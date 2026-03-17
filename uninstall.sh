#!/bin/bash
# uninstall.sh - Remove allstar-ar-news from the system.
# Copyright (c) 2026 Larry K. Aycock (N6LKA)
# https://github.com/N6LKA/allstar-ar-news
#
# Usage: sudo uninstall.sh
#
# This script will:
#   1. Remove cron jobs for play_news.sh (asterisk user)
#   2. Remove the installation directory
#   3. Optionally remove the playback log file

INSTALL_DIR="/etc/asterisk/scripts/ar-news"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=============================================="
echo "  AllStar AR News Player - Uninstaller"
echo "  https://github.com/N6LKA/allstar-ar-news"
echo "=============================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This uninstaller must be run as root or with sudo.${NC}"
    exit 1
fi

# Check that it is actually installed
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}NOTE: $INSTALL_DIR does not exist. Nothing to uninstall.${NC}"
    exit 0
fi

# Load config so we know the NEWSLOGFILE path
NEWSLOGFILE=""
CONFIG_FILE="$INSTALL_DIR/ar-news.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=ar-news.conf
    source "$CONFIG_FILE"
fi

echo "This will remove:"
echo "  - Cron jobs for play_news.sh (asterisk user)"
echo "  - Installation directory: $INSTALL_DIR"
if [[ -n "$NEWSLOGFILE" && -f "$NEWSLOGFILE" ]]; then
    echo "  - Playback log (optional): $NEWSLOGFILE"
fi
echo ""
read -rp "Are you sure you want to uninstall? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && echo "Uninstall cancelled." && exit 0

# --- Remove cron jobs ---
echo ""
echo "--- Removing cron jobs ---"
if crontab -u asterisk -l 2>/dev/null | grep -q "play_news\.sh"; then
    (crontab -u asterisk -l 2>/dev/null \
        | grep -v "play_news\.sh" \
        | grep -v "# ARRL/ARN Audio News") \
        | crontab -u asterisk -
    echo -e "${GREEN}Cron jobs removed.${NC}"
else
    echo "No play_news.sh cron jobs found."
fi

# --- Remove log file (optional) ---
if [[ -n "$NEWSLOGFILE" && -f "$NEWSLOGFILE" ]]; then
    echo ""
    read -rp "Remove playback log $NEWSLOGFILE? [y/N]: " RMLOG
    if [[ "${RMLOG,,}" == "y" ]]; then
        rm -f "$NEWSLOGFILE"
        echo -e "${GREEN}Log file removed.${NC}"
    else
        echo "Log file kept."
    fi
fi

# --- Remove installation directory ---
echo ""
echo "--- Removing $INSTALL_DIR ---"
rm -rf "$INSTALL_DIR"
echo -e "${GREEN}Installation directory removed.${NC}"

echo ""
echo "=============================================="
echo -e "${GREEN}Uninstall complete.${NC}"
echo "=============================================="
echo ""
exit 0
