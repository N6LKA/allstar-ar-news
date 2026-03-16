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

	# All user-configurable settings are in ar-news.conf in the same directory
	# as this script. Edit that file to change settings.

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

# ===== Set audio playback directory =====

	# Determine which audio directory to use based on AUDIOMODE.
	if [ "$AUDIOMODE" == "tts" ]; then
		PLAYVOICEDIR="$VOICEDIR/tts"
		# If TTS directory is empty or missing, run generate_audio.sh first.
		if [ ! -d "$PLAYVOICEDIR" ] || [ -z "$(ls -A "$PLAYVOICEDIR" 2>/dev/null)" ]; then
			echo "TTS audio files not found. Running generate_audio.sh to generate them..."
			if ! "$SCRIPT_DIR/generate_audio.sh"; then
				echo "Error: Failed to generate TTS audio files. Check generate_audio.sh."
				exit 1
			fi
		fi
	else
		PLAYVOICEDIR="$VOICEDIR"
	fi

# ===== End audio directory setup =====

# Define a variable to keep track of elapsed time
elapsed_time=0

# Define usage function
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

# Parse command line arguments
if [ "$1" == "--help" ]; then
	usage
	exit 0
elif [ $# -ne 3 ] && [ $# -ne 4 ]; then
	echo "Missing required variables"
	usage
	exit 1	
fi

# NEWSTYPE is either ARRL or ARN, Always required as parameter 1
if [ -z "$1" ]
	then
		echo "No Play type given - ARN or ARRL"
		 
		exit 1
	else
		NEWSTYPE="${1^^}"
		if [ "$NEWSTYPE" != "ARN" ] && [ "$NEWSTYPE" != "ARRL" ]
			then 
				echo "Play type must be ARRL or ARN"
				usage
				exit 1
		fi
fi

# Set NEWSNODE variable based on NEWSTYPE.
if [ "$NEWSTYPE" == "ARRL" ]; then 
	NEWSNODE=$ARRLNEWSNODE
elif [ "$NEWSTYPE" == "ARN" ]; then
	NEWSNODE=$ARNNEWSNODE
fi
echo "News type = $NEWSTYPE and News Node = $NEWSNODE"

# Time to start - 24 hour time - required 2nd command line parameter
# Time example 03:19 = 3:19 AM, 22:45 = 10:45 PM 
if [ -z "${2}" ]; then
    echo "No Time supplied - Enter 24 hour time to play as 00:00 - (7 PM = 19:00)"
	echo "or NOW for immediate play."
    usage
    exit 1
elif [ "${2^^}" != "NOW" ] && [[ ! "$2" =~ ^[0-9][0-9]:[0-9][0-9]$ ]]; then
    echo "Invalid Time format - Enter 24 hour time to play as 00:00 - (7 PM = 19:00)"
	echo "or NOW for immediate play."
    usage
    exit 1
fi
TIME="$2"

# Verify Node # to Control
if [[ ! $3 =~ ^-?[0-9]+$ ]]
	then
		echo "Error - Node number required"
		echo "${USAGE_MESSAGE}"
		exit 1
	 else
		NODE=$3
fi

# Set Variables for playback mode local/global
if [ -z $4 ]
	then
		MODE="localplay"
	elif
		[ "${4^^}" == "L" ]
			then
				MODE="localplay"
	elif
		[ "${4^^}" == "G" ]
		then
			MODE="playback"
		else
			echo "Wrong mode type - L for Local play, G or null for global play"
			echo "${USAGE_MESSAGE}"
    exit 1
fi

if [ $MODE == "playback" ]
	then
		MODETYPE="(global)"
	else
		MODETYPE="(local)"
fi

# Verify the path to voice files is correct and files exist.
if [ ! -f "$PLAYVOICEDIR/${NEWSTYPE}start.ul" ] || [ ! -f "$PLAYVOICEDIR/${NEWSTYPE}stop.ul" ]; then
	echo "Error - play_news audio files not found in $PLAYVOICEDIR"
	echo "Check VOICEDIR and AUDIOMODE in ar-news.conf."
	exit 1
fi

# === Play News Announcements Sequence ===

# If start time is not NOW, play 10-minute and 5-minute announcements before start time.
if [ "${TIME^^}" != "NOW" ]
	then
		echo "$NEWSTYPE news will start at $TIME and use $MODE $MODETYPE mode on"
		echo "node - $NODE  with 5 and 10 minute pre-announcements"
	 
		# Last warning time - 5 minutes before
		TIME5=`date --date "$TIME now 5 minutes ago" +%H:%M`
		# First warning time - 10 minutes before
		TIME10=`date --date "$TIME now 10 minutes ago" +%H:%M`

		# Wait and Send 10 minute announcement
		echo "Waiting to send 10 minute warning"
		while [ "$(date +%H:%M)" != "$TIME10" ]; do sleep 1; done
			# Start 10 minute message, add 3 second delay to beginning
			cat "$VOICEDIR/silence3.ul" "$PLAYVOICEDIR/${NEWSTYPE}start10.ul" > "$TMPDIR/news.ul"
			/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/news"

		# Wait and Send 5 minute announcement
		echo "Waiting to send 5 minute warning"
		while [ "$(date +%H:%M)" != "$TIME5" ]; do sleep 1; done
			# Start 5 minute message, add 3 second delay to beginning
			cat "$VOICEDIR/silence3.ul" "$PLAYVOICEDIR/${NEWSTYPE}start5.ul" > "$TMPDIR/news.ul"
			/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/news"

		# Wait for start time
		echo "Waiting for start time"
		while [ "$(date +%H:%M)" != "$TIME" ]; do sleep 1; done

	else

		clear
		echo "$NEWSTYPE news will start $TIME and use $MODE $MODETYPE mode on node - $NODE"
		echo -n "Press any key to start news..."
		read -n 1 
fi

# === Play News Sequence ===

# Disable Local Telemetry Output
echo "Disabling telemetry."
/usr/sbin/asterisk -rx "rpt cmd $NODE cop 34"

# Disable Link Activity Timer
if [ $LNKACTTIMER == "1" ]; then
	echo "Disabling Link Activity Timer"
	if [ "$LNKACTTYPE" == "native" ]; then
		# Native ASL3 link activity timer
		/usr/sbin/asterisk -rx "rpt cmd $NODE cop 46"
	else
		# asl3-link-activity-monitor by N6LKA
		/usr/local/bin/lnkact disable
	fi
fi

#If Mode = localplay, then Disconnect from other nodes.
if [ "$MODE" == "localplay" ]
	then
		# Disconnect from All nodes
		echo "Disconnecting node $NODE from All other nodes."
		/usr/sbin/asterisk -rx "rpt cmd $NODE ilink 6"
fi

# Send Repeater ID
echo "Sending Repeater ID"
/usr/sbin/asterisk -rx "rpt fun $NODE *80"

sleep 6
	
# Send QST Announcment
echo "Playing QST Announcment"
cat "$VOICEDIR/silence1.ul" "$PLAYVOICEDIR/${NEWSTYPE,,}-qst-news.ul" > "$TMPDIR/QST.ul"
/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/QST"

sleep 35
		
# Connect to node NEWSNODE to play News
echo "Connecting $NODE to $NEWSNODE"
/usr/sbin/asterisk -rx "rpt fun $NODE *2$NEWSNODE"
	

# Loop to wait for the news node to disconnect
while true; do
    if tail -n 1 "$logfile" | grep -q "disconnected from $NEWSNODE"; then
        echo "Node $NEWSNODE disconnected"
        break
    fi
    sleep 1
    ((elapsed_time++))
    if [ $elapsed_time -gt 1500 ]; then
        echo "Backup timer exceeded. Assuming news has finished."
        break
    fi
done

# Check if the news node disconnected or backup timer exceeded
if [ $elapsed_time -le 1500 ]; then
    echo "Node $NEWSNODE disconnected"
else
    echo "Backup timer exceeded. Assuming news has finished."
fi

# Re-Enable Link Activity Timer
if [ $LNKACTTIMER == "1" ]; then
	echo "Enabling Link Activity Timer"
	if [ "$LNKACTTYPE" == "native" ]; then
		# Native ASL3 link activity timer
		/usr/sbin/asterisk -rx "rpt cmd $NODE cop 45"
	else
		# asl3-link-activity-monitor by N6LKA
		/usr/local/bin/lnkact enable
	fi
fi


#If Mode = Localplay, then reconnect disconnected nodes.
if [ "$MODE" == "localplay" ]; then	 
    # Reconnect previously disconnected nodes
    echo "Reconnecting previously disconnected nodes."
    /usr/sbin/asterisk -rx "rpt cmd $NODE ilink 16"
    sleep 1
fi

# Enable Local Telemetry Output
echo "Enabling telemetry."
/usr/sbin/asterisk -rx "rpt cmd $NODE cop 35"

# Send News Stop Announcement
echo "Playing News Stop Announcement"
/usr/sbin/asterisk -rx "rpt $MODE $NODE $PLAYVOICEDIR/${NEWSTYPE}stop"

# Done
exit 0
