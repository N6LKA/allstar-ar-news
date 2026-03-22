#!/bin/bash
# cancel_news.sh - Emergency cancellation of ARRL/ARN news playback on an ASL3 node.
# Copyright (c) 2026 Larry K. Aycock (N6LKA)
# https://github.com/N6LKA/allstar-ar-news
#
# Usage: cancel_news.sh <NodeNumber>
#
# Designed to be triggered by a DTMF macro for immediate cancellation during
# news playback. This script will:
#   1. Disconnect the ARRL and ARN news nodes
#   2. Kill the play_news.sh process
#   3. Play a "cancelled" announcement
#   4. Reconnect any previously linked nodes
#   5. Re-enable the link activity timer (if configured in ar-news.conf)
#   6. Restore normal repeater telemetry
#
# All user configuration is in ar-news.conf in the same directory as this script.

# ===== Load user configuration =====

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/ar-news.conf"

if [ ! -f "$CONFIG_FILE" ]; then
	echo "Error: Configuration file not found: $CONFIG_FILE"
	echo "Make sure ar-news.conf exists in the same directory as this script."
	exit 1
fi
# shellcheck source=ar-news.conf
source "$CONFIG_FILE"

# ===== End configuration load =====

# ===== Logging setup =====

newslog() {
	local msg="$1"
	local ts
	ts=$(date '+%Y-%m-%d %H:%M:%S')
	echo "[$ts] $msg"
	if [[ -n "$NEWSLOGFILE" ]]; then
		echo "[$ts] $msg" >> "$NEWSLOGFILE"
	fi
}

# Ensure log file is writable by both root and asterisk user.
touch "$NEWSLOGFILE" 2>/dev/null
if [[ $EUID -eq 0 ]]; then
    chown root:asterisk "$NEWSLOGFILE" 2>/dev/null
    chmod 664 "$NEWSLOGFILE" 2>/dev/null
fi

# ===== End logging setup =====

# Validate node number
NODE=$1
if ! [[ $NODE =~ ^[0-9]+$ ]]; then
	echo "Error: Invalid node number"
	echo "Usage: $0 <node_number>"
	exit 1
fi

newslog "cancel_news.sh triggered on node $NODE"

clear

# Disable Local Telemetry Output
newslog "Disabling telemetry."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 34"; then
	newslog "Error: Failed to disable telemetry"
	exit 1
fi

# Disconnect news nodes
newslog "Disconnecting node $ARRLNEWSNODE"
if ! /usr/sbin/asterisk -rx "rpt fun $NODE *1$ARRLNEWSNODE"; then
	newslog "Error: Failed to disconnect node $ARRLNEWSNODE"
	exit 1
fi

sleep 1

newslog "Disconnecting node $ARNNEWSNODE"
if ! /usr/sbin/asterisk -rx "rpt fun $NODE *1$ARNNEWSNODE"; then
	newslog "Error: Failed to disconnect node $ARNNEWSNODE"
	exit 1
fi

# Kill play_news script and clean up temp files
if pgrep play_news > /dev/null; then
	newslog "Killing play_news process"
	pkill play_news
	rm -f "$TMPDIR/news.ul" "$TMPDIR/QST.ul"
	if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 24"; then
		newslog "Error: Failed to run Asterisk command"
		exit 1
	fi
else
	newslog "play_news process is not running"
fi

sleep 2

# Play Cancelled announcement
if ! /usr/sbin/asterisk -rx "rpt localplay $NODE /usr/share/asterisk/sounds/en/cancelled"; then
	newslog "Error: Failed to play cancelled sound"
	exit 1
fi

newslog "News cancelled."
sleep 3

# Reconnect previously disconnected nodes
newslog "Reconnecting previously disconnected nodes."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE ilink 16"; then
	newslog "Error: Failed to reconnect previously disconnected nodes"
	exit 1
fi

sleep 1

# Re-Enable Link Activity Timer
if [ "$LNKACTTIMER" == "1" ]; then
	newslog "Enabling Link Activity Timer"
	if [ "$LNKACTTYPE" == "native" ]; then
		/usr/sbin/asterisk -rx "rpt cmd $NODE cop 45"
	else
		/usr/local/bin/lnkact enable
	fi
fi

# Enable Local Telemetry Output
newslog "Enabling telemetry."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 35"; then
	newslog "Error: Failed to enable telemetry"
	exit 1
fi

newslog "cancel_news.sh complete."
exit 0
