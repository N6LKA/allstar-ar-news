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

echo ""
echo "--- Downloading files ---"

# --- Create install directories ---
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/audio_files"

# --- Download scripts ---
for script in play_news.sh cancel_news.sh; do
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

# --- Download audio files ---
AUDIO_FILES=(
    ARRLstart.ul ARRLstart10.ul ARRLstart5.ul ARRLstop.ul
    ARNstart.ul  ARNstart10.ul  ARNstart5.ul  ARNstop.ul
    arrl-qst-news.ul arn-qst-news.ul
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
    ARRLstart ARRLstart10 ARRLstart5 ARRLstop
    ARNstart  ARNstart10  ARNstart5  ARNstop
    arrl-qst-news.txt arn-qst-news.txt
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

# --- Set ownership ---
chown -R root:asterisk "$INSTALL_DIR"
echo -e "${GREEN}Files installed to: $INSTALL_DIR${NC}"

# --- Cron setup (asterisk user) ---
echo ""
echo "--- Setting up cron jobs (asterisk user) ---"
echo ""

# Helper: compute HH MM cron fields 30 minutes before a given HH:MM play time
compute_cron_start() {
    local playtime="$1"
    local h="${playtime%%:*}"
    local m="${playtime##*:}"
    local total_min=$(( 10#$h * 60 + 10#$m - 30 ))
    [[ $total_min -lt 0 ]] && total_min=$(( total_min + 1440 ))
    printf "%02d %02d" $(( total_min % 60 )) $(( total_min / 60 ))
}

while true; do
    read -rp "Enter your ASL3 node number: " NODE
    NODE=$(echo "$NODE" | tr -d ' ')
    [[ -n "$NODE" ]] && break
    echo -e "${RED}Node number is required.${NC}"
done

read -rp "Enter ARRL news play time in 24h format HH:MM [default: 07:30]: " ARRL_TIME
ARRL_TIME=${ARRL_TIME:-07:30}

read -rp "Enter ARN news play time in 24h format HH:MM  [default: 07:30]: " ARN_TIME
ARN_TIME=${ARN_TIME:-07:30}

ARRL_CRON_START=$(compute_cron_start "$ARRL_TIME")
ARN_CRON_START=$(compute_cron_start "$ARN_TIME")

CRON_COMMENT="# ARRL/ARN Audio News"
ARRL_CRON_JOB="$ARRL_CRON_START * * 6 $INSTALL_DIR/play_news.sh ARRL $ARRL_TIME $NODE L >/dev/null 2>&1"
ARN_CRON_JOB="$ARN_CRON_START * * 7 $INSTALL_DIR/play_news.sh ARN $ARN_TIME $NODE L >/dev/null 2>&1"

CURRENT_CRON=$(crontab -u asterisk -l 2>/dev/null)

if echo "$CURRENT_CRON" | grep -q "play_news.sh"; then
    # Entry exists — update the comment and both cron lines in-place
    NEW_CRON=$(echo "$CURRENT_CRON" | awk \
        -v comment="$CRON_COMMENT" \
        -v arrl_job="$ARRL_CRON_JOB" \
        -v arn_job="$ARN_CRON_JOB" '
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (lines[i] ~ /play_news\.sh ARRL/) {
                    if (i > 1 && lines[i-1] ~ /ARRL|ARN|[Aa][Rr].*[Nn]ews/) {
                        lines[i-1] = comment
                    }
                    lines[i] = arrl_job
                } else if (lines[i] ~ /play_news\.sh ARN/) {
                    lines[i] = arn_job
                }
            }
            for (i = 1; i <= NR; i++) print lines[i]
        }')
    echo "$NEW_CRON" | crontab -u asterisk -
    echo -e "${GREEN}Cron jobs updated for asterisk user.${NC}"
else
    # No existing entry — append blank line, comment, and both cron lines
    (crontab -u asterisk -l 2>/dev/null; echo ""; echo "$CRON_COMMENT"; echo "$ARRL_CRON_JOB"; echo "$ARN_CRON_JOB") | crontab -u asterisk -
    echo -e "${GREEN}Cron jobs added for asterisk user.${NC}"
fi

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
echo ""
echo "Cron schedule (asterisk user):"
echo "  ARRL news: Saturdays  at $ARRL_TIME  (cron starts 30 min early)"
echo "  ARN news:  Sundays    at $ARN_TIME  (cron starts 30 min early)"
echo ""
echo "Configuration file:"
echo "  $INSTALL_DIR/ar-news.conf"
echo ""
echo "Manual usage (run as root or asterisk):"
echo "  $INSTALL_DIR/play_news.sh ARRL|ARN HH:MM|NOW <NodeNumber> L|G"
echo "  $INSTALL_DIR/cancel_news.sh <NodeNumber>"
echo "=============================================="
echo ""
