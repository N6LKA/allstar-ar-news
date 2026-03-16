#!/bin/bash
# generate_audio.sh - Generate TTS audio announcement files for ar-news.
# Copyright (c) 2026 Larry K. Aycock (N6LKA)
# https://github.com/N6LKA/allstar-ar-news
#
# Reads transcript (.txt) files from VOICEDIR and generates .ul audio files
# using asl-tts (piper TTS engine). Always overwrites existing files.
#
# Run this script:
#   - After switching AUDIOMODE to "tts" in ar-news.conf
#   - After editing any .txt transcript file to update the audio
#   - To refresh QST announcements after changing CALLSIGN or STATIONTYPE
#
# Output:
#   Non-QST files  -> VOICEDIR/tts/   (used when AUDIOMODE=tts)
#   QST files      -> VOICEDIR/        (used by both AUDIOMODE=files and tts)
#                  -> VOICEDIR/tts/    (used when AUDIOMODE=tts)
#
# Usage: generate_audio.sh

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

# Run asl-tts as asterisk user if running as root
if [ "$(id -u)" -eq 0 ]; then
	TTS_CMD="sudo -u asterisk asl-tts"
else
	TTS_CMD="asl-tts"
fi

TTS_DIR="$VOICEDIR/tts"
mkdir -p "$TTS_DIR"

echo ""
echo "Generating TTS audio files..."
echo "Source directory : $VOICEDIR"
echo "TTS output       : $TTS_DIR"
echo ""

# --- Non-QST announcement files: generate into VOICEDIR/tts/ only ---
NON_QST_FILES=(
	ARRLstart ARRLstart5 ARRLstart10 ARRLstop
	ARNstart  ARNstart5  ARNstart10  ARNstop
)

for name in "${NON_QST_FILES[@]}"; do
	txtfile="$VOICEDIR/${name}.txt"
	if [ ! -f "$txtfile" ]; then
		echo "WARNING: $txtfile not found, skipping."
		continue
	fi
	text=$(cat "$txtfile")
	echo "Generating $name.ul -> tts/"
	if ! $TTS_CMD -n "$LOCALNODE" -t "$text" -f "$TTS_DIR/$name"; then
		echo "Error: Failed to generate $name.ul"
		exit 1
	fi
done

echo ""

# --- QST announcement files: generate into both VOICEDIR/ and VOICEDIR/tts/ ---
QST_FILES=(
	arrl-qst-news
	arn-qst-news
)

for name in "${QST_FILES[@]}"; do
	txtfile="$VOICEDIR/${name}.txt"
	if [ ! -f "$txtfile" ]; then
		echo "WARNING: $txtfile not found, skipping."
		continue
	fi
	text=$(cat "$txtfile")

	echo "Generating $name.ul -> audio_files/ (for AUDIOMODE=files)"
	if ! $TTS_CMD -n "$LOCALNODE" -t "$text" -f "$VOICEDIR/$name"; then
		echo "Error: Failed to generate $VOICEDIR/$name.ul"
		exit 1
	fi

	echo "Generating $name.ul -> tts/ (for AUDIOMODE=tts)"
	if ! $TTS_CMD -n "$LOCALNODE" -t "$text" -f "$TTS_DIR/$name"; then
		echo "Error: Failed to generate $TTS_DIR/$name.ul"
		exit 1
	fi
done

echo ""
echo "Done! All TTS audio files generated successfully."
echo ""
echo "To use TTS audio, set AUDIOMODE=\"tts\" in ar-news.conf."
echo ""
exit 0
