#!/bin/bash
# play_news.sh - Play ARRL Audio News or Amateur Radio Newsline on an ASL3 node.
# Copyright (c) 2026 Larry K. Aycock (N6LKA)
# https://github.com/N6LKA/allstar-ar-news
#
# Based on the original playnews script by Doug Crompton (HamVOIP).
# Rewritten to connect directly to the AllStar/Echolink news nodes in Monitor
# Only mode, allowing the repeater to break for proper IDs during playback.
#
# Usage: play_news.sh ARRL|ARN HH:MM|NOW <NodeNumber> [L|G]
#
#   ARRL|ARN      - News source: ARRL Audio News or Amateur Radio Newsline
#   HH:MM|NOW     - Scheduled play time in 24-hour format, or NOW for immediate start
#   <NodeNumber>  - Your ASL3 node number
#   L|G           - L = local play only, G = global (all connected nodes). Defaults to L.
#
# WARNING: Global mode (G) will play over all connected nodes.
# Use Local mode (L) unless you specifically intend global playback.
#
# When a scheduled time is given, the script plays 10-minute and 5-minute
# pre-announcements, then connects to the news node at the scheduled time.
# The script must be started at least 15 minutes before the play time,
# and can be scheduled up to 24 hours in advance.
#
# DO NOT use NOW in a cron job.
#
# Cron example - play ARRL news every Saturday at 9:00 PM, start cron at 8:30 PM:
#   30 20 * * 6 /etc/asterisk/scripts/ar-news/play_news.sh ARRL 21:00 <NodeNumber> L >/dev/null 2>&1
#
# Audio announcement files (configured via AUDIOMODE in ar-news.conf):
#   AUDIOMODE=files  uses pre-recorded files in VOICEDIR/
#   AUDIOMODE=tts    uses TTS-generated files in VOICEDIR/tts/
#                    Run generate_audio.sh to create TTS files.
#                    Missing TTS files are generated automatically on first run.
#
#   ARRLstart10.ul   / ARNstart10.ul    - 10-minute pre-announcement
#   ARRLstart5.ul    / ARNstart5.ul     - 5-minute pre-announcement
#   ARRLstop.ul      / ARNstop.ul       - News end announcement
#   arrl-qst-news.ul / arn-qst-news.ul  - QST announcement played before connecting
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

	# newslog: write a timestamped entry to NEWSLOGFILE and also print to stdout.
	newslog() {
		local msg="$1"
		local ts
		ts=$(date '+%Y-%m-%d %H:%M:%S')
		echo "[$ts] $msg"
		if [[ -n "$NEWSLOGFILE" ]]; then
			echo "[$ts] $msg" >> "$NEWSLOGFILE" 2>/dev/null
		fi
	}

# ===== End logging setup =====

# ===== Set audio playback directory =====

	if [ "$AUDIOMODE" == "tts" ]; then
		PLAYVOICEDIR="$VOICEDIR/tts"
		if [ ! -d "$PLAYVOICEDIR" ] || [ -z "$(ls -A "$PLAYVOICEDIR" 2>/dev/null)" ]; then
			newslog "TTS audio files not found. Running generate_audio.sh to generate them..."
			if ! "$SCRIPT_DIR/generate_audio.sh"; then
				newslog "Error: Failed to generate TTS audio files. Check generate_audio.sh."
				exit 1
			fi
		fi
	else
		PLAYVOICEDIR="$VOICEDIR"
	fi

# ===== End audio directory setup =====

# ===== Parse arguments =====

function usage {
	echo ""
	echo "Usage: $0 ARRL|ARN 24hTime|NOW NODE# L|G"
	echo ""
	echo "Options:"
	echo "  ARRL or ARN for type of news"
	echo "  Specific 24 hour time or \"NOW\""
	echo "  Node number to play news on"
	echo "  Local \"L\" or Global \"G\" play mode"
	echo ""
	exit 1
}

if [ "$1" == "--help" ]; then
	usage
fi

if [ $# -ne 3 ] && [ $# -ne 4 ]; then
	echo "Missing required variables"
	usage
fi

# NEWSTYPE
NEWSTYPE="${1^^}"
if [ "$NEWSTYPE" != "ARN" ] && [ "$NEWSTYPE" != "ARRL" ]; then
	echo "Play type must be ARRL or ARN"
	usage
fi

# Set NEWSNODE based on NEWSTYPE
if [ "$NEWSTYPE" == "ARRL" ]; then
	NEWSNODE=$ARRLNEWSNODE
elif [ "$NEWSTYPE" == "ARN" ]; then
	NEWSNODE=$ARNNEWSNODE
fi
newslog "News type = $NEWSTYPE, News Node = $NEWSNODE"

# TIME
if [ -z "${2}" ]; then
	echo "No Time supplied - Enter 24 hour time to play as 00:00 - (7 PM = 19:00)"
	echo "or NOW for immediate play."
	usage
elif [ "${2^^}" != "NOW" ] && [[ ! "$2" =~ ^[0-9][0-9]:[0-9][0-9]$ ]]; then
	echo "Invalid Time format - Enter 24 hour time to play as 00:00 - (7 PM = 19:00)"
	echo "or NOW for immediate play."
	usage
fi
TIME="$2"

# NODE
if [[ ! $3 =~ ^-?[0-9]+$ ]]; then
	echo "Error - Node number required"
	usage
fi
NODE=$3

# MODE
if [ -z "$4" ] || [ "${4^^}" == "L" ]; then
	MODE="localplay"
elif [ "${4^^}" == "G" ]; then
	MODE="playback"
else
	echo "Wrong mode type - L for Local play, G for global play"
	usage
fi

if [ "$MODE" == "playback" ]; then
	MODETYPE="(global)"
else
	MODETYPE="(local)"
fi

# ===== End argument parsing =====

# Verify audio files exist
if [ ! -f "$PLAYVOICEDIR/${NEWSTYPE}start.ul" ] || [ ! -f "$PLAYVOICEDIR/${NEWSTYPE}stop.ul" ]; then
	newslog "Error: play_news audio files not found in $PLAYVOICEDIR"
	newslog "Check VOICEDIR and AUDIOMODE in ar-news.conf."
	exit 1
fi

if [ ! -f "$PLAYVOICEDIR/${NEWSTYPE,,}-qst-news.ul" ]; then
	newslog "Error: QST audio file not found: $PLAYVOICEDIR/${NEWSTYPE,,}-qst-news.ul"
	newslog "Run generate_audio.sh to regenerate QST audio files."
	exit 1
fi

# ===== Audio duration helper =====

# Returns the estimated playback duration of a .ul file in seconds.
# ulaw audio = 8000 bytes per second. Adds a 2-second buffer.
audio_duration() {
	local file="$1"
	local size
	size=$(stat -c%s "$file" 2>/dev/null || echo 0)
	echo $(( size / 8000 + 2 ))
}

# ===== Pre-announcement sequence =====

if [ "${TIME^^}" != "NOW" ]; then
	newslog "$NEWSTYPE news scheduled at $TIME -- $MODE $MODETYPE on node $NODE"

	TIME5=$(date --date "$TIME now 5 minutes ago" +%H:%M)
	TIME10=$(date --date "$TIME now 10 minutes ago" +%H:%M)

	newslog "Waiting to send 10-minute warning at $TIME10"
	while [ "$(date +%H:%M)" != "$TIME10" ]; do sleep 1; done
	cat "$VOICEDIR/silence3.ul" "$PLAYVOICEDIR/${NEWSTYPE}start10.ul" > "$TMPDIR/news.ul"
	/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/news"
	newslog "10-minute warning sent."

	newslog "Waiting to send 5-minute warning at $TIME5"
	while [ "$(date +%H:%M)" != "$TIME5" ]; do sleep 1; done
	cat "$VOICEDIR/silence3.ul" "$PLAYVOICEDIR/${NEWSTYPE}start5.ul" > "$TMPDIR/news.ul"
	/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/news"
	newslog "5-minute warning sent."

	newslog "Waiting for start time $TIME"
	while [ "$(date +%H:%M)" != "$TIME" ]; do sleep 1; done

else
	newslog "$NEWSTYPE news starting NOW -- $MODE $MODETYPE on node $NODE"
fi

# ===== Play News Sequence =====

newslog "Disabling telemetry."
/usr/sbin/asterisk -rx "rpt cmd $NODE cop 34"

# Disable Link Activity Timer
if [ "$LNKACTTIMER" == "1" ]; then
	newslog "Disabling Link Activity Timer"
	if [ "$LNKACTTYPE" == "native" ]; then
		/usr/sbin/asterisk -rx "rpt cmd $NODE cop 46"
	else
		/usr/local/bin/lnkact disable
	fi
fi

# Disconnect from other nodes in local mode
if [ "$MODE" == "localplay" ]; then
	newslog "Disconnecting node $NODE from all other nodes."
	/usr/sbin/asterisk -rx "rpt cmd $NODE ilink 6"
fi

# Send Repeater ID
newslog "Sending Repeater ID"
/usr/sbin/asterisk -rx "rpt fun $NODE *80"
sleep 6

# Build and play QST announcement
newslog "Playing QST announcement"
cat "$VOICEDIR/silence1.ul" "$PLAYVOICEDIR/${NEWSTYPE,,}-qst-news.ul" > "$TMPDIR/QST.ul"
/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/QST"

# Wait for QST audio to finish based on actual file size (ulaw = 8000 bytes/sec)
QST_WAIT=$(audio_duration "$TMPDIR/QST.ul")
newslog "Waiting ${QST_WAIT}s for QST announcement to finish."
sleep "$QST_WAIT"

# Play start announcement
newslog "Playing News Start announcement"
cat "$VOICEDIR/silence1.ul" "$PLAYVOICEDIR/${NEWSTYPE}start.ul" > "$TMPDIR/start.ul"
/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/start"
START_WAIT=$(audio_duration "$TMPDIR/start.ul")
newslog "Waiting ${START_WAIT}s for Start announcement to finish."
sleep "$START_WAIT"

# Connect to news node
newslog "Connecting node $NODE to news node $NEWSNODE"
/usr/sbin/asterisk -rx "rpt fun $NODE *2$NEWSNODE"

# ===== Disconnect detection =====
# Record the current line count of the log before connecting so we only
# examine new entries. This prevents false matches on stale log lines.

LOG_START_LINE=$(wc -l < "$logfile" 2>/dev/null || echo 0)
elapsed_time=0

# ARRL is typically ~15 min; ARN can run up to ~25 min
if [ "$NEWSTYPE" == "ARRL" ]; then
	BACKUP_TIMER=1200
else
	BACKUP_TIMER=1500
fi

newslog "Monitoring for disconnect from node $NEWSNODE (backup timer: ${BACKUP_TIMER}s)"

while true; do
	if tail -n +"$((LOG_START_LINE + 1))" "$logfile" 2>/dev/null \
		| grep -q "disconnected from $NEWSNODE"; then
		newslog "Node $NEWSNODE disconnected -- news finished."
		break
	fi
	sleep 1
	((elapsed_time++))
	if [ $elapsed_time -gt $BACKUP_TIMER ]; then
		newslog "WARNING: Backup timer exceeded (${BACKUP_TIMER}s). Assuming news has finished."
		break
	fi
done

# ===== Post-playback cleanup =====

# Re-enable Link Activity Timer
if [ "$LNKACTTIMER" == "1" ]; then
	newslog "Enabling Link Activity Timer"
	if [ "$LNKACTTYPE" == "native" ]; then
		/usr/sbin/asterisk -rx "rpt cmd $NODE cop 45"
	else
		/usr/local/bin/lnkact enable
	fi
fi

# Reconnect previously disconnected nodes
if [ "$MODE" == "localplay" ]; then
	newslog "Reconnecting previously disconnected nodes."
	/usr/sbin/asterisk -rx "rpt cmd $NODE ilink 16"
	sleep 1
fi

# Re-enable telemetry
newslog "Enabling telemetry."
/usr/sbin/asterisk -rx "rpt cmd $NODE cop 35"

# Play News Stop Announcement
newslog "Playing News Stop announcement"
/usr/sbin/asterisk -rx "rpt $MODE $NODE $PLAYVOICEDIR/${NEWSTYPE}stop"

newslog "$NEWSTYPE news playback complete."
exit 0
