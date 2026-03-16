#!/bin/bash
# test_audio.sh - Test TTS playback of a transcript file on the local node.
# Copyright (c) 2026 Larry K. Aycock (N6LKA)
# https://github.com/N6LKA/allstar-ar-news
#
# Reads the specified .txt transcript file and plays it immediately on your
# local node using asl-tts. Use this to hear how an announcement sounds
# before running generate_audio.sh to produce the final audio files.
#
# Usage: test_audio.sh <txtfile>
#
# Examples:
#   test_audio.sh /etc/asterisk/scripts/ar-news/audio_files/arrl-qst-news.txt
#   test_audio.sh /etc/asterisk/scripts/ar-news/audio_files/ARRLstart.txt
#
# The node used for playback is LOCALNODE from ar-news.conf.

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

# Check for asl-tts
if ! command -v asl-tts &>/dev/null; then
	echo "Error: asl-tts is not installed."
	echo "Install it with: sudo apt-get install asl3-tts"
	exit 1
fi

# Validate argument
if [ -z "$1" ]; then
	echo "Usage: $0 <txtfile>"
	echo ""
	echo "Examples:"
	echo "  $0 $VOICEDIR/arrl-qst-news.txt"
	echo "  $0 $VOICEDIR/ARRLstart.txt"
	exit 1
fi

TXTFILE="$1"

if [ ! -f "$TXTFILE" ]; then
	echo "Error: File not found: $TXTFILE"
	exit 1
fi

TEXT=$(cat "$TXTFILE")

echo ""
echo "Playing on node $LOCALNODE:"
echo "---"
echo "$TEXT"
echo "---"
echo ""

# Run asl-tts as asterisk user if running as root
if [ "$(id -u)" -eq 0 ]; then
	sudo -u asterisk asl-tts -n "$LOCALNODE" -t "$TEXT"
else
	asl-tts -n "$LOCALNODE" -t "$TEXT"
fi

exit 0
