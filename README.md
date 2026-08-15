# StoryGraph stats on Tidbyt

Flips through her StoryGraph reading stats — pages read, books this year,
streaks, currently reading, etc. — on a Tidbyt.

**Requires her StoryGraph stats/profile to be public** (Settings → Privacy).
If they're private or friends-only, this can't reach the data without a
logged-in session, which isn't something a Tidbyt app can do.

## How it fits together

1. `scrape_storygraph.py` — reads her public StoryGraph profile + stats
   pages and writes a small `stats.json`.
2. `.github/workflows/update-stats.yml` — a free GitHub Actions job that
   runs the scraper on a schedule and commits the updated `stats.json`
   back to this repo, so refreshing is fully automatic.
3. `storygraph.star` — the Pixlet/Tidbyt app. It fetches `stats.json` from
   a URL and cycles through frames showing each stat.

## Setup

### 1. Get the scraper running

```
pip install requests beautifulsoup4
python3 scrape_storygraph.py HER_STORYGRAPH_USERNAME stats.json
```

Check the printed JSON looks sane (real numbers, not `null` everywhere).
If fields come back empty, StoryGraph's page markup has likely shifted —
open `scrape_storygraph.py` and adjust the regex in `parse_stats_page` /
`parse_profile_page` to match what's actually on the page now.

### 2. Automate it with GitHub Actions

- Push this folder to a **public** GitHub repo (has to be public for the
  raw JSON URL to be fetchable without auth).
- Edit `.github/workflows/update-stats.yml` and replace
  `YOUR_STORYGRAPH_USERNAME` with her actual username.
- Push. The workflow runs every 6 hours (edit the `cron` line to change
  that) and commits a fresh `stats.json` each time it changes.
- You can also trigger it manually from the repo's Actions tab
  ("Run workflow") to get a stats.json in place immediately, instead of
  waiting for the first scheduled run.

### 3. Point the Tidbyt app at your stats.json

Once `stats.json` exists in the repo, its raw URL will be:

```
https://raw.githubusercontent.com/<you>/<repo>/main/stats.json
```

- Install [pixlet](https://github.com/tidbyt/pixlet) locally (`brew install
  tidbyt/tidbyt/pixlet` on Mac, or see their releases page for other
  platforms).
- Run `pixlet serve storygraph.star` to preview it in a browser and paste
  in the raw URL above when it asks for "Stats JSON URL".
- Once it looks right, push it to your Tidbyt with `pixlet push` (or
  install it as a community app via the Tidbyt mobile app if you'd rather
  not self-host the .star file).

## Notes / things that might need tweaking

- The scraper is regex-based screen scraping, not an API — it's fragile
  by nature. If StoryGraph changes their page layout, some fields will
  start coming back as `null`/empty until the patterns are updated.
- Mood, pace, genre, and "most read authors" breakdowns aren't included —
  those charts load via JavaScript after the page renders, so a plain
  HTTP fetch can't see them.
- Be a reasonable citizen: the GitHub Action only hits StoryGraph twice
  per run (one stats page, one profile page) every few hours — please
  don't turn the cron interval down to something aggressive.
