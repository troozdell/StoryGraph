#!/bin/bash
# Runs the StoryGraph scraper, commits stats.json to GitHub (kept for
# historical record / anyone else consuming the raw URL), and independently
# renders + pushes a fresh image straight to the Tidbyt device using the
# just-scraped values passed directly into pixlet — no dependency on
# GitHub's raw-content CDN having caught up, and no in-app cache to wait
# out. Mirrors how SpotifyStats does it (see ../SpotifyStats/update_stats.py).
#
# Triggered on a schedule by cron (see `crontab -l`), since this needs to
# run from a normal residential IP rather than a cloud/datacenter one to
# get past StoryGraph's bot protection. Every external command below uses
# a full path rather than relying on $PATH, since cron's environment is
# even more minimal than an interactive shell's (this bit us once already
# with a launchd job that couldn't find `pixlet`).

# Deliberately NOT using `set -e` here — a GitHub hiccup shouldn't prevent
# the Tidbyt device from still getting updated with the values we just
# scraped. Each risky step below checks its own exit status instead.

PYTHON3="/usr/bin/python3"
GIT="/usr/bin/git"
PIXLET="/opt/homebrew/bin/pixlet"

cd "/Users/eric/Tidbyt/StoryGraph"

LOG_FILE="update.log"
echo "---- $(date) ----" >> "$LOG_FILE"

"$PYTHON3" scrape_storygraph.py hopebales stats.json >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: scrape failed, skipping this run entirely." >> "$LOG_FILE"
    exit 1
fi

# --- GitHub (historical record — failures here are logged but non-fatal) ---
"$GIT" add stats.json
if "$GIT" diff --staged --quiet; then
    echo "No changes to stats.json, nothing to push to GitHub." >> "$LOG_FILE"
else
    if "$GIT" commit -m "Update StoryGraph stats" >> "$LOG_FILE" 2>&1 && "$GIT" push >> "$LOG_FILE" 2>&1; then
        echo "Pushed updated stats.json to GitHub." >> "$LOG_FILE"
    else
        echo "WARNING: failed to commit/push stats.json to GitHub (continuing to Tidbyt push anyway)." >> "$LOG_FILE"
    fi
fi

# --- Tidbyt device — always render + push fresh values, every run ---------
source "$(dirname "$0")/.tidbyt_credentials.sh"

STATS_ARGS=$("$PYTHON3" -c "
import json
with open('stats.json') as f:
    d = json.load(f)
def val(k):
    v = d.get(k)
    return str(v) if v is not None else '0'
print('pages_this_year=' + val('pages_this_year') + ' books_this_year=' + val('books_this_year') + ' total_pages_all_time=' + val('total_pages_all_time'))
")

if "$PIXLET" render storygraph.star $STATS_ARGS -o storygraph.webp >> "$LOG_FILE" 2>&1; then
    if "$PIXLET" push \
        --installation-id StoryGraphStats \
        --api-token "$TIDBYT_API_TOKEN" \
        "$TIDBYT_DEVICE_ID" \
        storygraph.webp >> "$LOG_FILE" 2>&1; then
        echo "Pushed to Tidbyt." >> "$LOG_FILE"
    else
        echo "WARNING: pixlet push to Tidbyt failed." >> "$LOG_FILE"
    fi
else
    echo "WARNING: pixlet render failed; skipping Tidbyt push." >> "$LOG_FILE"
fi
