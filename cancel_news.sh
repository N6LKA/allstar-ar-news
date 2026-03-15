#!/bin/bash
# Cancels playback of ARRL/ARN news.
# You need to do several things to stop it.
# Make the killall the full name of the play_news you are running.
# To run script, enter "cancel_news.sh xxxxxx" where xxxxxx is the node number.
# This script will cancel playnews script written by Doug Crompton, as well as
# the play_news.sh script written by Larry Aycock, N6LKA.
# Modified by N6LKA 2025-11-20 for ASL3

# Cancel News
NODE=$1
if ! [[ $NODE =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid node number"
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
echo "Disconnecting node 516229"
if ! /usr/sbin/asterisk -rx "rpt fun $NODE *1516229"; then
  echo "Error: Failed to disconnect node 516229"
  exit 1
fi

sleep 1

echo "Disconnecting node 3006397"
if ! /usr/sbin/asterisk -rx "rpt fun $NODE *13006397"; then
  echo "Error: Failed to disconnect node 3006397"
  exit 1
fi

# Kill play_news script
if pgrep play_news > /dev/null; then
  echo "Killing play_news process"
  pkill play_news
  if [ -d "/tmp/news*" ]; then
    echo "Removing /tmp/news* directory"
    rm -rf /tmp/news*
  fi
  if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 24"; then
    echo "Error: Failed to run Asterisk command"
    exit 1
  fi
else
  echo "play_news process is not running"
fi

sleep 2

# Play Cancelled
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
if [ $LNKACTTIMER == "1" ]; then
    echo "Enabling Link Activity Timer"
    # Legacy method - native ASL3 link activity timer (kept for reference)
    # /usr/sbin/asterisk -rx "rpt cmd $NODE cop 45"
    # Use lnkact-monitor instead
    /usr/local/bin/lnkact enable
fi

# Enable Local Telemetry Output
echo "Enabling telemetry."
if ! /usr/sbin/asterisk -rx "rpt cmd $NODE cop 35"; then
  echo "Error: Failed to enable telemetry"
  exit 1
fi

#End
exit 0