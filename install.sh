#!/bin/bash
# =============================================================================
# install.sh - Installer for allstar-ar-news
# https://github.com/N6LKA/allstar-ar-news
# =============================================================================

VERSION="1.1.5"
INSTALL_DIR="/etc/asterisk/scripts/ar-news"
REPO="https://raw.githubusercontent.com/N6LKA/allstar-ar-news/master"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=============================================="
echo "  AllStar AR News Player - Installer"
echo "  Version $VERSION"
echo "  https://github.com/N6LKA/allstar-ar-news"
echo "=============================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This installer must be run as root or with sudo.${NC}"
    exit 1
fi

# --- Version check ---
echo "--- Checking for updates ---"
REMOTE_VERSION=$(curl -fsSL "$REPO/version.txt" 2>/dev/null | tr -d '[:space:]')
if [[ -n "$REMOTE_VERSION" ]]; then
    if [[ "$REMOTE_VERSION" != "$VERSION" ]]; then
        echo -e "${YELLOW}NOTE: A newer version ($REMOTE_VERSION) is available.${NC}"
        echo "      You are running version $VERSION."
        echo "      Re-download install.sh from the repo to get the latest version."
        echo ""
    else
        echo -e "${GREEN}You are running the latest version ($VERSION).${NC}"
    fi
else
    echo -e "${YELLOW}WARNING: Could not check for updates (no network or repo unreachable).${NC}"
fi
echo ""

# --- Detect existing install ---
if [[ -f "$INSTALL_DIR/play_news.sh" ]]; then
    echo -e "${YELLOW}Existing installation detected. Updating scripts and audio files...${NC}"
    UPDATING=true
else
    UPDATING=false
fi

# --- Ask about cron update if existing install ---
if [[ "$UPDATING" == "true" ]]; then
    echo ""
    read -rp "Update cron schedule? [y/N]: " _UPDATE_CRON
    [[ "${_UPDATE_CRON,,}" == "y" ]] && UPDATE_CRON=true || UPDATE_CRON=false
else
    UPDATE_CRON=true
fi

# --- Check/install dependencies ---
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

if ! command -v lnkact &>/dev/null; then
    echo "asl3-link-activity-monitor not found. Installing..."
    if apt-get install -y asl3-link-activity-monitor; then
        echo -e "${GREEN}asl3-link-activity-monitor installed.${NC}"
    else
        echo -e "${YELLOW}WARNING: Could not install asl3-link-activity-monitor.${NC}"
        echo "         Install it manually: https://github.com/N6LKA/asl3-link-activity-monitor"
        echo "         Or set LNKACTTIMER=0 (or LNKACTTYPE=native) in ar-news.conf."
    fi
else
    echo -e "${GREEN}asl3-link-activity-monitor found.${NC}"
fi

if [[ ! -f "/etc/asterisk/scripts/conlog.sh" ]]; then
    echo "asl3-connection-log not found. Installing..."
    _tmp=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/N6LKA/asl3-connection-log/main/install.sh -o "$_tmp" && bash "$_tmp"; _rc=$?; rm -f "$_tmp"
    if [[ $_rc -eq 0 ]]; then
        echo -e "${GREEN}asl3-connection-log installed.${NC}"
    else
        echo -e "${RED}ERROR: Could not install asl3-connection-log.${NC}"
        echo "       This package is required — play_news.sh depends on its log format"
        echo "       to detect when the news node disconnects."
        echo "       Install it manually: https://github.com/N6LKA/asl3-connection-log"
        exit 1
    fi
else
    echo -e "${GREEN}asl3-connection-log found.${NC}"
fi

# =============================================================================
# Helper functions (defined before user input so they can be called in the loop)
# =============================================================================

# Return "morning", "afternoon", or "evening" for a given HH:MM time
time_of_day() {
    local hour="${1%%:*}"
    hour=$((10#$hour))
    if [[ $hour -ge 5 && $hour -lt 12 ]]; then
        echo "morning"
    elif [[ $hour -ge 12 && $hour -lt 18 ]]; then
        echo "afternoon"
    else
        echo "evening"
    fi
}

# Day name to cron day number
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

# Compute MM HH cron fields 30 minutes before a given HH:MM play time
compute_cron_start() {
    local playtime="$1"
    local h="${playtime%%:*}"
    local m="${playtime##*:}"
    local total_min=$(( 10#$h * 60 + 10#$m - 30 ))
    [[ $total_min -lt 0 ]] && total_min=$(( total_min + 1440 ))
    printf "%02d %02d" $(( total_min % 60 )) $(( total_min / 60 ))
}

# =============================================================================
# Collect user inputs
# =============================================================================

if [[ "$UPDATE_CRON" == "true" ]]; then

echo ""
echo "--- Configuration ---"
echo ""

# Pre-fill node number from existing config when updating
_DEFAULT_NODE=""
if [[ "$UPDATING" == "true" && -f "$INSTALL_DIR/ar-news.conf" ]]; then
    _DEFAULT_NODE=$(grep '^LOCALNODE=' "$INSTALL_DIR/ar-news.conf" | head -1 | sed 's/LOCALNODE="\(.*\)"/\1/')
fi

while true; do
    if [[ -n "$_DEFAULT_NODE" ]]; then
        read -rp "Enter your ASL3 node number [default: $_DEFAULT_NODE]: " NODE
        NODE=$(echo "$NODE" | tr -d ' ')
        NODE="${NODE:-$_DEFAULT_NODE}"
    else
        read -rp "Enter your ASL3 node number: " NODE
        NODE=$(echo "$NODE" | tr -d ' ')
    fi
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

# --- News slot loop ---
echo ""
echo "--- News Slots ---"
echo "Configure one or more scheduled news broadcasts."
echo ""

declare -a SLOT_TYPES=()
declare -a SLOT_DAYS=()
declare -a SLOT_TIMES=()
declare -a SLOT_CRON_DAYS=()

# Suggested default days for the first two slots
_DEFAULT_DAYS=("Saturday" "Sunday")

slot_num=1
while true; do
    # After the first slot, ask if another should be added
    if [[ $slot_num -gt 1 ]]; then
        echo ""
        read -rp "Add another news slot? [y/N]: " ADD_MORE
        [[ "${ADD_MORE,,}" != "y" ]] && break
        echo ""
    fi

    echo "--- Slot $slot_num ---"
    echo ""

    echo "  News type:"
    echo "    1) ARRL Audio News"
    echo "    2) Amateur Radio Newsline (ARN)"
    while true; do
        read -rp "  Select [1-2, default: 1]: " _CHOICE
        _CHOICE=${_CHOICE:-1}
        case "$_CHOICE" in
            1) _TYPE="ARRL"; break ;;
            2) _TYPE="ARN";  break ;;
            *) echo -e "${RED}  Enter 1 or 2.${NC}" ;;
        esac
    done

    # Pick a sensible default day
    if [[ $slot_num -le ${#_DEFAULT_DAYS[@]} ]]; then
        _DEFAULT_DAY="${_DEFAULT_DAYS[$((slot_num - 1))]}"
    else
        _DEFAULT_DAY="Saturday"
    fi

    while true; do
        read -rp "  Day of week [default: $_DEFAULT_DAY]: " _DAY
        _DAY=${_DAY:-$_DEFAULT_DAY}
        _CRON_DAY=$(day_to_cron "$_DAY")
        if [[ -n "$_CRON_DAY" ]]; then
            break
        fi
        echo -e "${RED}  Unrecognized day '$_DAY'. Enter a full day name (e.g. Saturday).${NC}"
    done

    while true; do
        read -rp "  Play time in 24h format HH:MM [default: 07:30]: " _TIME
        _TIME=${_TIME:-07:30}
        if [[ "$_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
            break
        fi
        echo -e "${RED}  Invalid time format. Use HH:MM (e.g. 07:30).${NC}"
    done

    SLOT_TYPES+=("$_TYPE")
    SLOT_DAYS+=("$_DAY")
    SLOT_TIMES+=("$_TIME")
    SLOT_CRON_DAYS+=("$_CRON_DAY")

    echo -e "  ${GREEN}Slot $slot_num added: $_TYPE  ${_DAY}s at $_TIME${NC}"

    ((slot_num++))
done

TOTAL_SLOTS=${#SLOT_TYPES[@]}
if [[ $TOTAL_SLOTS -eq 0 ]]; then
    echo -e "${RED}ERROR: At least one news slot is required.${NC}"
    exit 1
fi

fi # end UPDATE_CRON

echo ""
echo "--- Downloading files ---"

# --- Create install directories ---
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/audio_files"
mkdir -p "$INSTALL_DIR/audio_files/tts"
# Allow asterisk user to write audio files during install (asl-tts runs as asterisk)
chown root:asterisk "$INSTALL_DIR/audio_files" "$INSTALL_DIR/audio_files/tts"
chmod 775 "$INSTALL_DIR/audio_files" "$INSTALL_DIR/audio_files/tts"

# --- Download scripts ---
for script in play_news.sh cancel_news.sh generate_audio.sh test_audio.sh uninstall.sh status.sh; do
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

# --- Download audio files ---
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

# --- Download text transcript files ---
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

# --- Fresh install: configure and generate QST files ---
if [[ "$UPDATING" == "false" ]]; then

    echo ""
    echo "--- Configuring ar-news.conf ---"
    sed -i "s/^LOCALNODE=.*/LOCALNODE=\"$NODE\"/" "$INSTALL_DIR/ar-news.conf"
    sed -i "s/^CALLSIGN=.*/CALLSIGN=\"$CALLSIGN\"/" "$INSTALL_DIR/ar-news.conf"
    sed -i "s/^STATIONTYPE=.*/STATIONTYPE=\"$STATIONTYPE\"/" "$INSTALL_DIR/ar-news.conf"
    echo -e "${GREEN}ar-news.conf updated.${NC}"

    echo ""
    echo "--- Generating QST announcement text files ---"

    # Generate QST txt for a given type using the supplied day/time
    generate_qst_txt() {
        local type="$1" day="$2" time="$3"
        local tod
        tod=$(time_of_day "$time")
        if [[ "$type" == "ARRL" ]]; then
            cat > "$INSTALL_DIR/audio_files/arrl-qst-news.txt" << EOF
QST, QST, QST,

Please stand by for a re-transmission of the most recent eh R R L Audio News.

When available, the eh R R L Audio News is re-transmitted on this $CALLSIGN $STATIONTYPE every $day $tod at $time Local Time.

If you have Emergency or Priority traffic during an automated playback, use asterisk 9 9 9 to cancel it.

The Re-Transmission of the eh R R L Audio News will begin momentarily.
EOF
            chmod 644 "$INSTALL_DIR/audio_files/arrl-qst-news.txt"
            echo -e "${GREEN}arrl-qst-news.txt generated.${NC}"
        else
            cat > "$INSTALL_DIR/audio_files/arn-qst-news.txt" << EOF
QST, QST, QST,

Please stand by for a re-transmission of the most recent Amateur Radio Newsline.

When available, Amateur Radio Newsline is re-transmitted on this $CALLSIGN $STATIONTYPE every $day $tod at $time Local Time.

If you have Emergency or Priority traffic during an automated playback, use asterisk 9 9 9 to cancel it.

The Re-Transmission of the Amateur Radio Newsline will begin momentarily.
EOF
            chmod 644 "$INSTALL_DIR/audio_files/arn-qst-news.txt"
            echo -e "${GREEN}arn-qst-news.txt generated.${NC}"
        fi
    }

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

    # Generate QST files for each unique news type (using the first slot of that type)
    declare -A _SEEN_TYPES=()
    for i in "${!SLOT_TYPES[@]}"; do
        _TYPE="${SLOT_TYPES[$i]}"
        if [[ -z "${_SEEN_TYPES[$_TYPE]+x}" ]]; then
            _SEEN_TYPES[$_TYPE]=1
            generate_qst_txt "$_TYPE" "${SLOT_DAYS[$i]}" "${SLOT_TIMES[$i]}"
        fi
    done

    echo ""
    echo "--- Generating QST audio files with asl-tts ---"
    echo "    (This may take a moment...)"

    for _TYPE in "${!_SEEN_TYPES[@]}"; do
        generate_qst_audio "$_TYPE"
    done

else
    echo ""
    echo "--- Updating node number in ar-news.conf ---"
    sed -i "s/^LOCALNODE=.*/LOCALNODE=\"$NODE\"/" "$INSTALL_DIR/ar-news.conf"
    echo -e "${GREEN}LOCALNODE updated to $NODE.${NC}"
    echo ""
    echo -e "${YELLOW}Update: QST files preserved. Run generate_audio.sh to regenerate them.${NC}"
fi

# --- Set ownership ---
chown -R root:asterisk "$INSTALL_DIR"
echo ""
echo -e "${GREEN}Files installed to: $INSTALL_DIR${NC}"

# --- Cron setup ---
if [[ "$UPDATE_CRON" == "true" ]]; then
    echo ""
    echo "--- Setting up cron jobs (asterisk user) ---"
    echo ""

    CRON_COMMENT="# ARRL/ARN Audio News"

    # Build new cron lines for all slots
    NEW_CRON_LINES=""
    for i in "${!SLOT_TYPES[@]}"; do
        _CRON_START=$(compute_cron_start "${SLOT_TIMES[$i]}")
        NEW_CRON_LINES+="$_CRON_START * * ${SLOT_CRON_DAYS[$i]} $INSTALL_DIR/play_news.sh ${SLOT_TYPES[$i]} ${SLOT_TIMES[$i]} $NODE L >/dev/null 2>&1"$'\n'
    done

    # Remove existing play_news.sh lines and their comment, strip trailing blank
    # lines, then append new ones with exactly one blank line separator
    (crontab -u asterisk -l 2>/dev/null \
        | grep -v "play_news\.sh" \
        | grep -v "# ARRL/ARN Audio News" \
        | awk '/[[:graph:]]/{found=NR} {lines[NR]=$0} END{for(i=1;i<=found;i++) print lines[i]}'; \
        echo ""; echo "$CRON_COMMENT"; printf "%s" "$NEW_CRON_LINES") \
        | crontab -u asterisk -

    echo -e "${GREEN}Cron jobs configured for asterisk user.${NC}"
else
    echo ""
    echo -e "${YELLOW}Cron schedule unchanged.${NC}"
fi

# --- Summary ---
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
for i in "${!SLOT_TYPES[@]}"; do
    echo "  Slot $((i+1)): ${SLOT_TYPES[$i]}  ${SLOT_DAYS[$i]}s at ${SLOT_TIMES[$i]}  (cron starts 30 min early)"
done
echo ""
echo "Configuration file:"
echo "  $INSTALL_DIR/ar-news.conf"
echo ""
echo "Manual usage (run as root or asterisk):"
echo "  $INSTALL_DIR/play_news.sh ARRL|ARN HH:MM|NOW <NodeNumber> L|G"
echo "  $INSTALL_DIR/cancel_news.sh <NodeNumber>"
echo "  $INSTALL_DIR/generate_audio.sh"
echo "  $INSTALL_DIR/test_audio.sh <txtfile>"
echo "  $INSTALL_DIR/status.sh"
echo "  $INSTALL_DIR/uninstall.sh"
echo "=============================================="
echo ""
