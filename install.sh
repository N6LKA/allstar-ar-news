#!/bin/bash
# =============================================================================
# install.sh - Installer for allstar-ar-news
# https://github.com/N6LKA/allstar-ar-news
# =============================================================================

INSTALL_DIR="/etc/asterisk/scripts/ar-news"
REPO="https://raw.githubusercontent.com/N6LKA/allstar-ar-news/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=============================================="
echo "  AllStar AR News Player - Installer"
echo "  https://github.com/N6LKA/allstar-ar-news"
echo "=============================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This installer must be run as root or with sudo.${NC}"
    exit 1
fi

# --- Detect existing install ---
if [[ -f "$INSTALL_DIR/play_news.sh" ]]; then
    echo -e "${YELLOW}Existing installation detected. Updating scripts and audio files...${NC}"
    UPDATING=true
else
    UPDATING=false
fi

# --- Check/install asl-tts dependency ---
echo ""
echo "--- Checking dependencies ---"
if ! command -v asl-tts &>/dev/null; then
    echo "asl-tts not found. Installing asl3-tts..."
    if ! apt-get install -y asl3-tts; then
        echo -e "${RED}ERROR: Failed to install asl3-tts. Install it manually and re-run.${NC}"
        exit 1
    fi
    echo -e "${GREEN}asl3-tts installed.${NC}"
else
    echo -e "${GREEN}asl-tts found.${NC}"
fi

# --- Collect user inputs ---
echo ""
echo "--- Configuration ---"
echo ""

while true; do
    read -rp "Enter your ASL3 node number: " NODE
    NODE=$(echo "$NODE" | tr -d ' ')
    [[ "$NODE" =~ ^[0-9]+$ ]] && break
    echo -e "${RED}Node number must be numeric.${NC}"
done

if [[ "$UPDATING" == "false" ]]; then
    while true; do
        read -rp "Enter your station callsign: " CALLSIGN
        CALLSIGN=$(echo "$CALLSIGN" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        [[ -n "$CALLSIGN" ]] && break
        echo -e "${RED}Callsign is required.${NC}"
    done

    echo "Station type:"
    echo "  1) Repeater"
    echo "  2) Node"
    while true; do
        read -rp "Select [1-2, default: 1]: " STTYPE
        STTYPE=${STTYPE:-1}
        case "$STTYPE" in
            1) STATIONTYPE="Repeater"; break ;;
            2) STATIONTYPE="Node"; break ;;
            *) echo -e "${RED}Enter 1 or 2.${NC}" ;;
        esac
    done
fi

echo ""
echo "--- News Slot 1 (defaults: ARRL / Saturday / 07:30) ---"
echo ""
echo "  News type:"
echo "    1) ARRL Audio News"
echo "    2) Amateur Radio Newsline (ARN)"
while true; do
    read -rp "  Select [1-2, default: 1]: " _CHOICE
    _CHOICE=${_CHOICE:-1}
    case "$_CHOICE" in
        1) SLOT1_TYPE="ARRL"; break ;;
        2) SLOT1_TYPE="ARN";  break ;;
        *) echo -e "${RED}Enter 1 or 2.${NC}" ;;
    esac
done
read -rp "  Day of week [default: Saturday]: " SLOT1_DAY
SLOT1_DAY=${SLOT1_DAY:-Saturday}
read -rp "  Play time in 24h format HH:MM [default: 07:30]: " SLOT1_TIME
SLOT1_TIME=${SLOT1_TIME:-07:30}

echo ""
echo "--- News Slot 2 (defaults: ARN / Sunday / 07:30) ---"
echo ""
echo "  News type:"
echo "    1) ARRL Audio News"
echo "    2) Amateur Radio Newsline (ARN)"
while true; do
    read -rp "  Select [1-2, default: 2]: " _CHOICE
    _CHOICE=${_CHOICE:-2}
    case "$_CHOICE" in
        1) SLOT2_TYPE="ARRL"; break ;;
        2) SLOT2_TYPE="ARN";  break ;;
        *) echo -e "${RED}Enter 1 or 2.${NC}" ;;
    esac
done
read -rp "  Day of week [default: Sunday]: " SLOT2_DAY
SLOT2_DAY=${SLOT2_DAY:-Sunday}
read -rp "  Play time in 24h format HH:MM [default: 07:30]: " SLOT2_TIME
SLOT2_TIME=${SLOT2_TIME:-07:30}

# --- Helper: convert 24h time to 12h AM/PM ---
convert_time_12h() {
    local time24="$1"
    local h="${time24%%:*}"
    local m="${time24##*:}"
    local h10=$((10#$h))
    local ampm="AM"
    if [ $h10 -eq 0 ]; then
        h10=12
    elif [ $h10 -eq 12 ]; then
        ampm="PM"
    elif [ $h10 -gt 12 ]; then
        h10=$((h10 - 12))
        ampm="PM"
    fi
    echo "${h10}:${m} ${ampm}"
}

# --- Helper: day name to cron day number ---
day_to_cron() {
    case "${1,,}" in
        sunday)    echo 0 ;;
        monday)    echo 1 ;;
        tuesday)   echo 2 ;;
        wednesday) echo 3 ;;
        thursday)  echo 4 ;;
        friday)    echo 5 ;;
        saturday)  echo 6 ;;
        *)         echo "" ;;
    esac
}

# --- Helper: compute HH MM cron fields 30 minutes before a given HH:MM play time ---
compute_cron_start() {
    local playtime="$1"
    local h="${playtime%%:*}"
    local m="${playtime##*:}"
    local total_min=$(( 10#$h * 60 + 10#$m - 30 ))
    [[ $total_min -lt 0 ]] && total_min=$(( total_min + 1440 ))
    printf "%02d %02d" $(( total_min % 60 )) $(( total_min / 60 ))
}

SLOT1_TIME_12H=$(convert_time_12h "$SLOT1_TIME")
SLOT2_TIME_12H=$(convert_time_12h "$SLOT2_TIME")
SLOT1_CRON_DAY=$(day_to_cron "$SLOT1_DAY")
SLOT2_CRON_DAY=$(day_to_cron "$SLOT2_DAY")

if [[ -z "$SLOT1_CRON_DAY" ]]; then
    echo -e "${YELLOW}WARNING: Unrecognized day '$SLOT1_DAY', defaulting to Saturday.${NC}"
    SLOT1_DAY="Saturday"; SLOT1_CRON_DAY=6
fi
if [[ -z "$SLOT2_CRON_DAY" ]]; then
    echo -e "${YELLOW}WARNING: Unrecognized day '$SLOT2_DAY', defaulting to Sunday.${NC}"
    SLOT2_DAY="Sunday"; SLOT2_CRON_DAY=0
fi

echo ""
echo "--- Downloading files ---"

# --- Create install directories ---
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/audio_files"
mkdir -p "$INSTALL_DIR/audio_files/tts"

# --- Download scripts ---
for script in play_news.sh cancel_news.sh generate_audio.sh test_audio.sh; do
    echo "Downloading $script..."
    curl -fsSL "$REPO/$script" -o "$INSTALL_DIR/$script"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}ERROR: Failed to download $script${NC}"
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$script"
done

# --- Download configuration file ---
if [[ "$UPDATING" == "true" ]]; then
    # On update, preserve existing user config; download as .new for reference
    echo "Downloading ar-news.conf.new (preserving your existing ar-news.conf)..."
    curl -fsSL "$REPO/ar-news.conf" -o "$INSTALL_DIR/ar-news.conf.new"
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}WARNING: Failed to download ar-news.conf.new${NC}"
    else
        chmod 644 "$INSTALL_DIR/ar-news.conf.new"
    fi
else
    echo "Downloading ar-news.conf..."
    curl -fsSL "$REPO/ar-news.conf" -o "$INSTALL_DIR/ar-news.conf"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}ERROR: Failed to download ar-news.conf${NC}"
        exit 1
    fi
    chmod 644 "$INSTALL_DIR/ar-news.conf"
fi

# --- Download audio files (non-QST only; QST files are generated below) ---
AUDIO_FILES=(
    ARRLstart.ul ARRLstart10.ul ARRLstart5.ul ARRLstop.ul
    ARNstart.ul  ARNstart10.ul  ARNstart5.ul  ARNstop.ul
    silence1.ul silence2.ul silence3.ul
)
for f in "${AUDIO_FILES[@]}"; do
    echo "Downloading $f..."
    curl -fsSL "$REPO/$f" -o "$INSTALL_DIR/audio_files/$f"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}ERROR: Failed to download $f${NC}"
        exit 1
    fi
    chmod 644 "$INSTALL_DIR/audio_files/$f"
done

# --- Download text transcript files (non-QST; QST .txt files are generated below) ---
TEXT_FILES=(
    ARRLstart.txt ARRLstart10.txt ARRLstart5.txt ARRLstop.txt
    ARNstart.txt  ARNstart10.txt  ARNstart5.txt  ARNstop.txt
)
for f in "${TEXT_FILES[@]}"; do
    echo "Downloading $f..."
    curl -fsSL "$REPO/$f" -o "$INSTALL_DIR/audio_files/$f"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}ERROR: Failed to download $f${NC}"
        exit 1
    fi
    chmod 644 "$INSTALL_DIR/audio_files/$f"
done

# --- Fresh install: update ar-news.conf with user values and generate QST files ---
if [[ "$UPDATING" == "false" ]]; then

    echo ""
    echo "--- Configuring ar-news.conf ---"
    sed -i "s/^LOCALNODE=.*/LOCALNODE=\"$NODE\"/" "$INSTALL_DIR/ar-news.conf"
    sed -i "s/^CALLSIGN=.*/CALLSIGN=\"$CALLSIGN\"/" "$INSTALL_DIR/ar-news.conf"
    sed -i "s/^STATIONTYPE=.*/STATIONTYPE=\"$STATIONTYPE\"/" "$INSTALL_DIR/ar-news.conf"
    echo -e "${GREEN}ar-news.conf updated.${NC}"

    echo ""
    echo "--- Generating QST announcement text files ---"

    # Generate a QST txt file for a given news type using the supplied day/time.
    generate_qst_txt() {
        local type="$1" day="$2" time_12h="$3"
        if [[ "$type" == "ARRL" ]]; then
            cat > "$INSTALL_DIR/audio_files/arrl-qst-news.txt" << EOF
QST QST QST

Please stand by for a re-transmission of the most recent eh R R L Audio News.

When available, the eh R R L Audio News is re-transmitted on this $CALLSIGN $STATIONTYPE every $day morning at $time_12h Local Time.

If you have Emergency or Priority traffic during an automated playback, use * 9 9 9 to cancel it.

The Re-Transmission of the eh R R L Audio News will begin momentarily.
EOF
            chmod 644 "$INSTALL_DIR/audio_files/arrl-qst-news.txt"
            echo -e "${GREEN}arrl-qst-news.txt generated.${NC}"
        else
            cat > "$INSTALL_DIR/audio_files/arn-qst-news.txt" << EOF
QST QST QST

Please stand by for a re-transmission of the most recent Amateur Radio Newsline.

When available, Amateur Radio Newsline is re-transmitted on this $CALLSIGN $STATIONTYPE every $day morning at $time_12h Local Time.

If you have Emergency or Priority traffic during an automated playback, use * 9 9 9 to cancel it.

The Re-Transmission of the Amateur Radio Newsline will begin momentarily.
EOF
            chmod 644 "$INSTALL_DIR/audio_files/arn-qst-news.txt"
            echo -e "${GREEN}arn-qst-news.txt generated.${NC}"
        fi
    }

    # Generate QST audio for a given type using its installed txt file.
    generate_qst_audio() {
        local type="$1"
        local base="${type,,}-qst-news"
        local text
        text=$(cat "$INSTALL_DIR/audio_files/${base}.txt")
        if ! sudo -u asterisk asl-tts -n "$NODE" -t "$text" -f "$INSTALL_DIR/audio_files/$base"; then
            echo -e "${YELLOW}WARNING: Failed to generate ${base}.ul via asl-tts.${NC}"
            echo "         Run generate_audio.sh manually after installation."
        else
            echo -e "${GREEN}${base}.ul generated.${NC}"
        fi
    }

    # Generate QST files for slot 1, then slot 2 (skip if slot 2 is same type as slot 1 —
    # the QST file already reflects that type; user can edit and re-run generate_audio.sh).
    generate_qst_txt "$SLOT1_TYPE" "$SLOT1_DAY" "$SLOT1_TIME_12H"
    if [[ "$SLOT2_TYPE" != "$SLOT1_TYPE" ]]; then
        generate_qst_txt "$SLOT2_TYPE" "$SLOT2_DAY" "$SLOT2_TIME_12H"
    fi

    echo ""
    echo "--- Generating QST audio files with asl-tts ---"
    echo "    (This may take a moment...)"

    generate_qst_audio "$SLOT1_TYPE"
    if [[ "$SLOT2_TYPE" != "$SLOT1_TYPE" ]]; then
        generate_qst_audio "$SLOT2_TYPE"
    fi

else
    echo ""
    echo -e "${YELLOW}Update: QST files preserved. Run generate_audio.sh to regenerate them.${NC}"
fi

# --- Set ownership ---
chown -R root:asterisk "$INSTALL_DIR"
echo ""
echo -e "${GREEN}Files installed to: $INSTALL_DIR${NC}"

# --- Cron setup (asterisk user) ---
echo ""
echo "--- Setting up cron jobs (asterisk user) ---"
echo ""

SLOT1_CRON_START=$(compute_cron_start "$SLOT1_TIME")
SLOT2_CRON_START=$(compute_cron_start "$SLOT2_TIME")

CRON_COMMENT="# ARRL/ARN Audio News"
SLOT1_CRON_JOB="$SLOT1_CRON_START * * $SLOT1_CRON_DAY $INSTALL_DIR/play_news.sh $SLOT1_TYPE $SLOT1_TIME $NODE L >/dev/null 2>&1"
SLOT2_CRON_JOB="$SLOT2_CRON_START * * $SLOT2_CRON_DAY $INSTALL_DIR/play_news.sh $SLOT2_TYPE $SLOT2_TIME $NODE L >/dev/null 2>&1"

# Remove any existing play_news.sh lines (and their comment), then add the two slots fresh.
(crontab -u asterisk -l 2>/dev/null \
    | grep -v "play_news\.sh" \
    | grep -v "# ARRL/ARN Audio News"; \
    echo ""; echo "$CRON_COMMENT"; echo "$SLOT1_CRON_JOB"; echo "$SLOT2_CRON_JOB") \
    | crontab -u asterisk -
echo -e "${GREEN}Cron jobs configured for asterisk user.${NC}"

echo ""
echo "=============================================="
if [[ "$UPDATING" == "true" ]]; then
    echo -e "${GREEN}Update complete!${NC}"
else
    echo -e "${GREEN}Installation complete!${NC}"
fi
echo ""
echo "Install directory:  $INSTALL_DIR"
echo "Audio files:        $INSTALL_DIR/audio_files/"
echo "TTS audio files:    $INSTALL_DIR/audio_files/tts/"
echo ""
echo "Cron schedule (asterisk user):"
echo "  Slot 1: $SLOT1_TYPE  ${SLOT1_DAY}s at $SLOT1_TIME  (cron starts 30 min early)"
echo "  Slot 2: $SLOT2_TYPE  ${SLOT2_DAY}s at $SLOT2_TIME  (cron starts 30 min early)"
echo ""
echo "Configuration file:"
echo "  $INSTALL_DIR/ar-news.conf"
echo ""
echo "Manual usage (run as root or asterisk):"
echo "  $INSTALL_DIR/play_news.sh ARRL|ARN HH:MM|NOW <NodeNumber> L|G"
echo "  $INSTALL_DIR/cancel_news.sh <NodeNumber>"
echo "  $INSTALL_DIR/generate_audio.sh"
echo "  $INSTALL_DIR/test_audio.sh <txtfile>"
echo "=============================================="
echo ""
