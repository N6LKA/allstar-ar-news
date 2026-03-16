#!/bin/bash
# Cancels playback of ARRL/ARN news.
# Usage: cancel_news.sh <node_number>
#
# This script cancels the play_news.sh script written by Larry Aycock, N6LKA,
# as well as the legacy playnews script by Doug Crompton.
# Intended to be called via a DTMF command macro to interrupt news playback.
#
# Copyright (c) 2026 Larry K. Aycock (N6LKA)

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

# Validate node number
NODE=$1
if ! [[ $NODE =~ ^[0-9]+$ ]]; then
	echo "Error: Invalid node number"
	echo "Usage: $0 <node_number>"
	exit 1
fi

clear

# Disable Local Telemetry Output
echo "Disabling telemetry."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 34"; then
	echo "Error: Failed to disable telemetry"
	exit 1
fi

# Disconnect news nodes
echo "Disconnecting node $ARRLNEWSNODE"
if ! /usr/sbin/asterisk -rx "rpt fun $NODE *1$ARRLNEWSNODE"; then
	echo "Error: Failed to disconnect node $ARRLNEWSNODE"
	exit 1
fi

sleep 1

echo "Disconnecting node $ARNNEWSNODE"
if ! /usr/sbin/asterisk -rx "rpt fun $NODE *1$ARNNEWSNODE"; then
	echo "Error: Failed to disconnect node $ARNNEWSNODE"
	exit 1
fi

# Kill play_news script and clean up temp files
if pgrep play_news > /dev/null; then
	echo "Killing play_news process"
	pkill play_news
	rm -f "$TMPDIR/news.ul" "$TMPDIR/QST.ul"
	if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 24"; then
		echo "Error: Failed to run Asterisk command"
		exit 1
	fi
else
	echo "play_news process is not running"
fi

sleep 2

# Play Cancelled announcement
if ! /usr/sbin/asterisk -rx "rpt localplay $NODE /usr/share/asterisk/sounds/en/cancelled"; then
	echo "Error: Failed to play cancelled sound"
	exit 1
fi

echo "News Cancelled!"
sleep 3

# Reconnect previously disconnected nodes
echo "Reconnecting previously disconnected nodes."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE ilink 16"; then
	echo "Error: Failed to reconnect previously disconnected nodes"
	exit 1
fi

sleep 1

# Re-Enable Link Activity Timer
if [ "$LNKACTTIMER" == "1" ]; then
	echo "Enabling Link Activity Timer"
	if [ "$LNKACTTYPE" == "native" ]; then
		# Native ASL3 link activity timer
		/usr/sbin/asterisk -rx "rpt cmd $NODE cop 45"
	else
		# asl3-link-activity-monitor by N6LKA
		/usr/local/bin/lnkact enable
	fi
fi

# Enable Local Telemetry Output
echo "Enabling telemetry."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 35"; then
	echo "Error: Failed to enable telemetry"
	exit 1
fi

# End
exit 0
