#!/bin/bash

# This script is based on the playnews script that was originally written by Doug Crompton
#for HamVOIP. It has been completely re-written to work by connecting to the ARRL/ARN news nodes
# for playback rather than downloading the audio file and breaking it up on the local device. 
# This allows the repeater breaks for ID at the proper times during the playback, instead of 
# breaking at odd times.

# This script can be used to play either the ARRL Audio News or the Amatuer Radio Newsline.
# This script will connect to node 516229 (AllStar ARRL News) or Echolink node 6397 (ARN News) 
# in Monitor Only mode to play the news.
# If scheduling to play via CRON, it includes voice announcements 10 and 5 minutes
# before the scheduled play time.

# WARNING - This script can be configured for global playback! 
# DO NOT run this on a multi-node connected circuit without consideration. 
# Change MODE to localplay for strictly local node play.
#
# This code is written to work on the hamvoip.org BBB/RPi2 Allstar releases
# and ASL3.
# All required packages are pre-installed on those systems.
# 
# You can run this script from a cron job or from the command line at least
# 15 minutes before the defined run time (TIME value) but it can be scheduled
# anytime within 24 hours prior to the run time.
#
# This can be used in a CRON command to schedule the ARRL News or ARN to play.
# CRON Example:
#  
# The below example will play the ARRL Audio News every Saturday at 9:00 PM 
# Actual playtime set by defined comand line TIME parameter.
# If Playtime is 9PM (2100) this would send announcements at 8:50 and 8:55 PM. 
#
# Start a cron job every Saturday at 8:30 PM to play news at 9:00 PM the same day
# and play ARRL news on node 501260, Locally
#
	# Play ARRL Audio News on Saturday at 9:00 PM local time on node 501260, - Schedule script at 8:30 PM
	# 30 20 * * 6 /etc/asterisk/local/AR_News/AR_News.sh ARRL 21:00 501260 L &> /dev/null 2>&1

# The audio files ARRLstart5, ARRLstart10, ARRLstart, ARRLstop
# and ARNstart, ARNstart10, ARNstart, ARNstop
# are supplied but could be customized for your needs. The audio
# files must be in the directory defined by VOICEDIR
#
# ARRLstart10 or ARNstart10   - voice message at ten minutes before start
# ARRLstart5 or ARNstart5     - voice message at five minutes before start
# ARRLstart or ARNstart       - voice message at start of play
# ARRLstop or ARNstop         - voice message at end of play

#	- Requires that all parameters be entered
#     except mode which defualts to global
#   - Time can be set to "NOW" for immediate start
#
#   Usage: play_news.sh ARRL|ARN 24hTime|NOW NODE# L|G
#
#   Options:
#		ARRL or ARN for type of news
#		Specific 24 hour time or "NOW"
#		Node number to play news on, and
#   	Local "L" or Global "G" play mode
#
#   DO NOT use the the "NOW" time parameter in a cron !!!

# ===== The following variable needs to be set if different for your install =====

	# VOICEDIR - Directory for playnews voice files
	# Usually in the same directory as the play_news script.
	
	VOICEDIR="/etc/asterisk/local/AR_News/"

	# TMPDIR - Directory for temporary file storage
	# Note if at all possible this should not be on the SD card.
	# Use of /tmp or a USB mounted stick is preferred
	# Note that the BBB may not have enough memory in /tmp to process

	TMPDIR="/tmp" 
	
	# The following will enable/disable use of the repeater link activity timer.
	# If enabled (1) the script will disable the link activity timer (LAT) while playing
	# the audio news, then re-enable LAT after the news is finished playing.
	# If your repeater/node uses the LAT, set the following to "1" to enable.
	# Otherwise, set to "0" to disable this function.
	
	LNKACTTIMER="1"

	# Set the node numbers to connect to for ARRL and ARN news.
	# At the time of writing this script, AllStar node 516229 
	# will play ARRL News, and Echolink node 6397 (3006397)
	# will play ARN.
	
	ARRLNEWSNODE="516229"
	ARNNEWSNODE="3006397"

	# Path to logfile so script can monitor connection and disconnect notifications.
	
	logfile="/var/log/asterisk/connectlog"

# ===== End User defines =====

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
		MODE="playback"
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
if [ ! -f $VOICEDIR/${NEWSTYPE}start ] || [ ! -f $VOICEDIR/${NEWSTYPE}stop ]
  then
    echo "Error - play_news voice files not found."
	echo "Check VOICEDIR in script and that the files exist."
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
			cat $VOICEDIR/silence3.ul "$VOICEDIR/${NEWSTYPE}start10.ul" > $TMPDIR/news.ul
			/usr/sbin/asterisk -rx "rpt $MODE $NODE $TMPDIR/news"

		# Wait and Send 5 minute announcement
		echo "Waiting to send 5 minute warning"
		while [ "$(date +%H:%M)" != "$TIME5" ]; do sleep 1; done
			# Start 5 minute message, add 3 second delay to beginning
			cat $VOICEDIR/silence3.ul "$VOICEDIR/${NEWSTYPE}start5.ul" > $TMPDIR/news.ul
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
if [ $LNKACTTIMER == "1" ]
	then
	echo "Disabling Link Activity Timer"
	# Legacy method - native ASL3 link activity timer (kept for reference)
	# /usr/sbin/asterisk -rx "rpt cmd $NODE cop 46"
	# Use lnkact-monitor instead
	/usr/local/bin/lnkact disable
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
cat $VOICEDIR/silence1.ul "$VOICEDIR/${NEWSTYPE}-QST-NEWS.ul" > $TMPDIR/QST.ul
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
    if [ $elapsed_time -gt 1200 ]; then
        echo "Backup timer exceeded. Assuming news has finished."
        break
    fi
done

# Check if the news node disconnected or backup timer exceeded
if [ $elapsed_time -le 1200 ]; then
    echo "Node $NEWSNODE disconnected"
else
    echo "Backup timer exceeded. Assuming news has finished."
fi

# Re-Enable Link Activity Timer
if [ $LNKACTTIMER == "1" ]; then
    echo "Enabling Link Activity Timer"
    # Legacy method - native ASL3 link activity timer (kept for reference)
    # /usr/sbin/asterisk -rx "rpt cmd $NODE cop 45"
    # Use lnkact-monitor instead
    /usr/local/bin/lnkact enable
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
/usr/sbin/asterisk -rx "rpt $MODE $NODE /$VOICEDIR/${NEWSTYPE}stop"

# Done
exit 0
