# allstar-ar-news

A bash script to play the **ARRL Audio News** or **Amateur Radio Newsline (ARN)** on an [ASL3](https://allstarlink.org/) repeater node. Rather than downloading and playing a local audio file, the script connects to the live AllStar news node in Monitor Only mode — allowing the repeater to break for proper IDs during playback instead of cutting at arbitrary points.

Includes 10-minute and 5-minute pre-announcements, QST announcements, automatic link activity monitor management, playback logging, and a cancel script for emergency use during playback.

---

## How It Works

- **ARRL News** connects to AllStar node `516229`
- **ARN News** connects to Echolink node `6397` (`3006397` in AllStar format)
- The script waits for the news node to disconnect before cleaning up
- Disconnect is detected by monitoring the `asl3-connection-log` connection log — only new log entries written after connecting are checked, preventing false matches on old entries
- A 25-minute (1500-second) backup timer prevents the script from hanging indefinitely if the log entry is missed
- All activity is timestamped and logged to a log file in the install directory

---

## Requirements

- ASL3 installed and configured
- `asterisk` — included with ASL3
- `asl3-tts` — required for QST announcement audio generation and optional TTS mode
  - Installed automatically by the installer if not present
- `asl3-connection-log` — required for disconnect detection via `connectlog`
  - See: [https://github.com/N6LKA/asl3-connection-log](https://github.com/N6LKA/asl3-connection-log)
- `asl3-link-activity-monitor` (optional) — if `LNKACTTIMER` is enabled in `ar-news.conf`
  - See: [https://github.com/N6LKA/asl3-link-activity-monitor](https://github.com/N6LKA/asl3-link-activity-monitor)

---

## Installation & Updates

Run the following command as root or with sudo for both fresh installs and updates:

```bash
bash <(curl -fsSL -H "Cache-Control: no-cache" https://raw.githubusercontent.com/N6LKA/allstar-ar-news/master/install.sh)
```

The installer will:
- Check for a newer version of allstar-ar-news and notify you if one is available
- Check for and install `asl3-tts`, `asl3-link-activity-monitor`, and `asl3-connection-log` if missing
- Prompt for your node number, callsign, and station type
- Let you configure **one or more** scheduled news slots — each with its own news type, day, and time
- Download all scripts and `ar-news.conf` to `/etc/asterisk/scripts/ar-news/`
- Download audio and transcript files to `/etc/asterisk/scripts/ar-news/audio_files/`
- Generate personalized QST announcement text and audio files using `asl-tts`
- Add or update cron entries in the **asterisk user's** crontab

> **On updates:** `ar-news.conf` is not overwritten — your settings are preserved. A copy of the new default config is saved as `ar-news.conf.new` for comparison. QST files are not regenerated on update; run `generate_audio.sh` manually to refresh them.

---

## Usage

Must be run as **root** or the **asterisk** user.

```bash
# Play ARRL news immediately
/etc/asterisk/scripts/ar-news/play_news.sh ARRL NOW <NodeNumber> L

# Play ARN news at a scheduled time (with pre-announcements)
/etc/asterisk/scripts/ar-news/play_news.sh ARN 07:30 <NodeNumber> L

# Cancel news during playback (emergency use)
/etc/asterisk/scripts/ar-news/cancel_news.sh <NodeNumber>

# Generate TTS audio files (run after editing .txt files or switching AUDIOMODE)
/etc/asterisk/scripts/ar-news/generate_audio.sh

# Test how a transcript file sounds before generating audio
/etc/asterisk/scripts/ar-news/test_audio.sh /etc/asterisk/scripts/ar-news/audio_files/arrl-qst-news.txt

# Show current playback status and upcoming schedule
/etc/asterisk/scripts/ar-news/status.sh

# Remove allstar-ar-news from the system
sudo /etc/asterisk/scripts/ar-news/uninstall.sh
```

### Arguments

| Argument | Description |
|---|---|
| `ARRL` or `ARN` | News source |
| `HH:MM` or `NOW` | Scheduled play time (24h format) or immediate start |
| `<NodeNumber>` | Your ASL3 node number |
| `L` or `G` | `L` = local play only, `G` = global (all connected nodes). Defaults to `L`. |

> ⚠️ **Do not use `NOW` in a cron job.**

---

## Cron Schedule

The installer adds entries to the **asterisk user's** crontab. You can configure any number of slots during installation — each with its own news type (ARRL or ARN), day of the week, and time. The cron job starts the script 30 minutes before the play time to allow for pre-announcements.

Example with two slots:

```
# ARRL/ARN Audio News
00 07 * * 6 /etc/asterisk/scripts/ar-news/play_news.sh ARRL 07:30 <NodeNumber> L >/dev/null 2>&1
00 07 * * 0 /etc/asterisk/scripts/ar-news/play_news.sh ARN  07:30 <NodeNumber> L >/dev/null 2>&1
```

To modify the schedule after install, edit the asterisk user's crontab directly, or re-run the installer:

```bash
sudo crontab -u asterisk -e
```

---

## Audio Files

All audio and transcript files are installed to `audio_files/`. TTS-generated files are stored in `audio_files/tts/`.

| File | Description |
|---|---|
| `ARRLstart10.ul` / `ARNstart10.ul` | 10-minute pre-announcement |
| `ARRLstart5.ul` / `ARNstart5.ul` | 5-minute pre-announcement |
| `ARRLstart.ul` / `ARNstart.ul` | News start announcement |
| `ARRLstop.ul` / `ARNstop.ul` | News end announcement |
| `arrl-qst-news.ul` / `arn-qst-news.ul` | QST pre-announcement (generated during install) |
| `silence1.ul`, `silence2.ul`, `silence3.ul` | Silence padding |
| `*.txt` | Text transcripts for each announcement — edit and regenerate as needed |

---

## Configuration

All user settings are in **`ar-news.conf`**, located in the same directory as the scripts (`/etc/asterisk/scripts/ar-news/ar-news.conf`). All scripts read from this file.

| Variable | Default | Description |
|---|---|---|
| `VOICEDIR` | `/etc/asterisk/scripts/ar-news/audio_files` | Path to audio files |
| `TMPDIR` | `/tmp` | Temporary file storage |
| `LNKACTTIMER` | `1` | `1` = manage link activity timer during playback, `0` = leave it alone |
| `LNKACTTYPE` | `monitor` | `monitor` = use asl3-link-activity-monitor; `native` = use ASL3 cop 46/45 |
| `ARRLNEWSNODE` | `516229` | AllStar node for ARRL news |
| `ARNNEWSNODE` | `3006397` | AllStar/Echolink node for ARN news |
| `logfile` | `/var/log/asterisk/connectlog` | Connection log used for disconnect detection |
| `NEWSLOGFILE` | `/etc/asterisk/scripts/ar-news/ar-news.log` | Playback activity log |
| `LOCALNODE` | *(required)* | Your node number — set by the installer |
| `CALLSIGN` | `W1ABC` | Your callsign, used in QST announcement text |
| `STATIONTYPE` | `Repeater` | `Repeater` or `Node`, used in QST announcement text |
| `AUDIOMODE` | `tts` | `files` = use pre-recorded audio; `tts` = use TTS-generated audio |

> **Do not edit the scripts directly for configuration** — all settings belong in `ar-news.conf`.

---

## TTS Audio Mode

By default, the script uses TTS-generated `.ul` audio files produced by the `asl-tts` / piper TTS engine for a modern-sounding voice. Older pre-recorded `.ul` files are also included in `audio_files/` as a fallback — these are the original recordings and can be used by setting `AUDIOMODE="files"` in `ar-news.conf`.

TTS files are generated once and stored in `audio_files/tts/`. If TTS files are missing when `play_news.sh` runs, it will call `generate_audio.sh` automatically before proceeding.

To manually regenerate TTS audio (e.g. after editing transcript files):

```bash
sudo /etc/asterisk/scripts/ar-news/generate_audio.sh
```

The wait time between the QST announcement and connecting to the news node is calculated automatically from the actual audio file size (ulaw = 8000 bytes/second), so the timing adjusts correctly if you customize the QST text.

### Switching to pre-recorded mode

If you prefer to use the older pre-recorded audio files instead of TTS:

1. Set `AUDIOMODE="files"` in `ar-news.conf`

### Updating announcement text

All announcements are driven by `.txt` transcript files in `audio_files/`. Edit these to customize what is said, then run `generate_audio.sh` to rebuild the audio.

### Testing announcements

Use `test_audio.sh` to hear how a transcript sounds before committing to a full regeneration:

```bash
sudo /etc/asterisk/scripts/ar-news/test_audio.sh /etc/asterisk/scripts/ar-news/audio_files/arrl-qst-news.txt
```

The node used for playback is `LOCALNODE` from `ar-news.conf`.

> **Note:** QST announcement audio is always written to both `audio_files/` and `audio_files/tts/` when `generate_audio.sh` runs, so QST announcements stay current regardless of which `AUDIOMODE` you use.

---

## Playback Logging

All playback activity is timestamped and written to the log file defined by `NEWSLOGFILE` in `ar-news.conf` (default: `/etc/asterisk/scripts/ar-news/ar-news.log`). This includes pre-announcement timing, QST playback, connect/disconnect events, timer expiry, and cancellations.

Since `play_news.sh` runs from cron with output redirected to `/dev/null`, the log file is the primary way to verify that a scheduled broadcast ran correctly.

To view recent activity:

```bash
tail -f /etc/asterisk/scripts/ar-news/ar-news.log
```

---

## Cancelling Playback

The `cancel_news.sh` script is designed to be triggered by a DTMF macro (e.g. `*999`) for emergency cancellation during playback:

```bash
/etc/asterisk/scripts/ar-news/cancel_news.sh <NodeNumber>
```

It will disconnect the news nodes, kill the `play_news.sh` process, restore normal repeater operation, and log the cancellation. The cancel script reads `ar-news.conf` to correctly re-enable the link activity timer using whatever `LNKACTTIMER` and `LNKACTTYPE` settings you have configured.

---

## Status

The `status.sh` script shows the current state of the system at a glance:

```bash
/etc/asterisk/scripts/ar-news/status.sh
```

It displays:
- Whether `play_news.sh` is currently running (with PID and start time)
- All scheduled broadcasts from the asterisk user's crontab
- The last 10 entries from the playback log

---

## Uninstalling

To completely remove allstar-ar-news:

```bash
sudo /etc/asterisk/scripts/ar-news/uninstall.sh
```

The uninstaller will remove the cron entries from the asterisk user's crontab, delete the install directory, and optionally remove the log file. It will ask for confirmation before taking any action.

---

## License

MIT License — Copyright 2026 Larry K. Aycock (N6LKA)

See [LICENSE](LICENSE) for details.
