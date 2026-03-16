# allstar-ar-news

A bash script to play the **ARRL Audio News** or **Amateur Radio Newsline (ARN)** on an [ASL3](https://allstarlink.org/) repeater node. Rather than downloading and playing a local audio file, the script connects to the live AllStar news node in Monitor Only mode — allowing the repeater to break for proper IDs during playback instead of cutting at arbitrary points.

Includes 10-minute and 5-minute pre-announcements, QST announcements, automatic link activity monitor management, and a cancel script for emergency use during playback.

---

## How It Works

- **ARRL News** connects to AllStar node `516229`
- **ARN News** connects to Echolink node `6397` (`3006397` in AllStar format)
- The script waits for the news node to disconnect before cleaning up
- A 20-minute backup timer prevents the script from hanging indefinitely

---

## Requirements

- ASL3 installed and configured
- `asterisk` — included with ASL3
- `asl3-connection-log` — required for disconnect detection via `connectlog`
  - See: [https://github.com/N6LKA/asl3-connection-log](https://github.com/N6LKA/asl3-connection-log)
- `asl3-link-activity-monitor` (optional) — if `LNKACTTIMER` is enabled in `ar-news.conf`
  - See: [https://github.com/N6LKA/asl3-link-activity-monitor](https://github.com/N6LKA/asl3-link-activity-monitor)

---

## Installation & Updates

Run the following command as root or with sudo for both fresh installs and updates:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/N6LKA/allstar-ar-news/main/install.sh)
```

The installer will:
- Download all scripts and `ar-news.conf` to `/etc/asterisk/scripts/ar-news/`
- Download audio and transcript files to `/etc/asterisk/scripts/ar-news/audio_files/`
- Prompt for your node number and desired play times
- Add or update cron entries in the **asterisk user's** crontab

> **On updates:** `ar-news.conf` is not overwritten — your settings are preserved. A copy of the new default config is saved as `ar-news.conf.new` for comparison.

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
```

### Arguments

| Argument | Description |
|---|---|
| `ARRL` or `ARN` | News source |
| `HH:MM` or `NOW` | Scheduled play time (24h) or immediate start |
| `<NodeNumber>` | Your ASL3 node number |
| `L` or `G` | `L` = local play only, `G` = global (all connected nodes) |

> ⚠️ **Do not use `NOW` in a cron job.**

---

## Cron Schedule

The installer adds entries to the **asterisk user's** crontab. The cron starts the script 30 minutes before the play time to allow for pre-announcements.

Default schedule (customizable during install):

```
# ARRL/ARN Audio News
00 07 * * 6 /etc/asterisk/scripts/ar-news/play_news.sh ARRL 07:30 <NodeNumber> L >/dev/null 2>&1
00 07 * * 7 /etc/asterisk/scripts/ar-news/play_news.sh ARN  07:30 <NodeNumber> L >/dev/null 2>&1
```

To modify times after install, edit the asterisk user's crontab:

```bash
sudo crontab -u asterisk -e
```

---

## Audio Files

Pre-recorded announcement files are included and installed with the script. The extensionless files (e.g. `ARRLstart`, `ARNstop`) contain the text transcripts used to generate the corresponding `.ul` audio files.

| File | Description |
|---|---|
| `ARRLstart10.ul` / `ARNstart10.ul` | 10-minute pre-announcement |
| `ARRLstart5.ul` / `ARNstart5.ul` | 5-minute pre-announcement |
| `ARRLstart.ul` / `ARNstart.ul` | News start announcement |
| `ARRLstop.ul` / `ARNstop.ul` | News end announcement |
| `ARRL-QST-NEWS.ul` / `ARN-QST-NEWS.ul` | QST pre-announcement played before connecting |
| `silence1.ul`, `silence2.ul`, `silence3.ul` | Silence padding |

---

## Configuration

All user settings are in **`ar-news.conf`**, located in the same directory as the scripts (`/etc/asterisk/scripts/ar-news/ar-news.conf`). Both `play_news.sh` and `cancel_news.sh` read from this file, so you only need to edit one place.

| Variable | Default | Description |
|---|---|---|
| `VOICEDIR` | `/etc/asterisk/scripts/ar-news/audio_files` | Path to audio files |
| `TMPDIR` | `/tmp` | Temporary file storage |
| `LNKACTTIMER` | `1` | `1` = manage link activity timer during playback, `0` = leave it alone |
| `LNKACTTYPE` | `monitor` | `monitor` = use asl3-link-activity-monitor; `native` = use ASL3 cop 46/45 |
| `ARRLNEWSNODE` | `516229` | AllStar node for ARRL news |
| `ARNNEWSNODE` | `3006397` | AllStar/Echolink node for ARN news |
| `logfile` | `/var/log/asterisk/connectlog` | Connection log for disconnect detection |

> **Do not edit the scripts directly for configuration** — all settings belong in `ar-news.conf`.

---

## Cancelling Playback

The `cancel_news.sh` script is designed to be triggered by a DTMF macro (e.g. `*999`) for emergency cancellation during playback:

```bash
/etc/asterisk/scripts/ar-news/cancel_news.sh <NodeNumber>
```

It will disconnect the news nodes, kill the `play_news.sh` process, and restore normal repeater operation. The cancel script reads `ar-news.conf` to correctly re-enable the link activity timer using whatever `LNKACTTIMER` and `LNKACTTYPE` settings you have configured.

---

## License

MIT License — Copyright 2026 Larry K. Aycock (N6LKA)

See [LICENSE](LICENSE) for details.
