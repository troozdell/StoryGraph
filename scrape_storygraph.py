#!/usr/bin/env python3
"""
scrape_storygraph.py

Pulls reading stats from a PUBLIC StoryGraph profile (no login) and writes
a compact JSON file for the Tidbyt app to consume.

IMPORTANT: this only works if the profile's stats/reading activity are set
to public in StoryGraph's privacy settings. If the pages redirect to a
sign-in wall, this will fail loudly rather than silently.

This scrapes plain server-rendered HTML. It does NOT get the mood/pace/
genre/author breakdown charts, since those load via JavaScript after the
page renders and a plain HTTP request can't see them.

Usage:
    python3 scrape_storygraph.py <storygraph_username> <output.json>

Note: this is a screen-scraper, not an API client. StoryGraph can change
their page layout at any time, which will break the text patterns below.
If it starts returning None for things it used to find, that's the first
place to look.
"""

import json
import re
import sys
import time
from datetime import datetime

import requests
from bs4 import BeautifulSoup

try:
    import cloudscraper
    _SCRAPER = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "darwin", "mobile": False}
    )
except ImportError:
    _SCRAPER = None

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

BROWSER_HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
}


def fetch(url, max_attempts=3):
    client = _SCRAPER if _SCRAPER is not None else requests
    last_status = None

    for attempt in range(1, max_attempts + 1):
        resp = client.get(url, headers=BROWSER_HEADERS, timeout=20)
        last_status = resp.status_code

        if resp.status_code == 403:
            if attempt < max_attempts:
                wait = 20 * attempt
                print(f"  ({url} got 403, retrying in {wait}s — attempt {attempt}/{max_attempts})")
                time.sleep(wait)
                continue
            hint = (
                "still 403 after retries — this site's bot-protection is "
                "tougher than the usual Cloudflare challenge cloudscraper "
                "handles, or your IP has been temporarily flagged from "
                "repeated requests. Wait 15-20 minutes with no requests at "
                "all, then try once. If it still fails after a real cool-down "
                "period, the next step would be a real headless browser "
                "(e.g. Playwright) instead of a plain HTTP client."
                if _SCRAPER is not None else
                "403 Forbidden, and 'cloudscraper' isn't installed — install "
                "it with `python3 -m pip install cloudscraper` and try again."
            )
            raise RuntimeError(f"{url} returned 403 Forbidden. {hint}")

        resp.raise_for_status()
        if resp.status_code in (401,) or "sign_in" in resp.url:
            raise RuntimeError(f"{url} appears to require sign-in — is the profile public?")
        return resp.text


def text_of(soup):
    return soup.get_text(separator=" ", strip=True)


def first_int(pattern, text, group=1, flags=re.IGNORECASE):
    m = re.search(pattern, text, flags)
    if not m:
        return None
    return int(m.group(group).replace(",", ""))


def parse_stats_page(html):
    soup = BeautifulSoup(html, "html.parser")
    text = text_of(soup)

    total_books = first_int(r"([\d,]+)\s+books\s*,\s*[\d,]+\s+pages", text)
    total_pages = first_int(r"[\d,]+\s+books\s*,\s*([\d,]+)\s+pages", text)

    current_streak = first_int(r"Current streak\D{0,40}?(\d+)", text)
    longest_streak = first_int(r"Longest streak\D{0,40}?(\d+)", text)

    avg_finish = None
    m = re.search(r"Average time to finish\s*(\d+\s+\w+)", text)
    if m:
        avg_finish = m.group(1).strip()

    avg_rating = None
    m = re.search(r"Average rating:\s*([\d.]+)", text)
    if m:
        avg_rating = float(m.group(1))

    review_count = first_int(r"([\d,]+)\s+reviews", text)

    # Per-year books/pages, pulled from the line chart's accessible text
    # caption: "...books read per year are as follows: 2024 - 4 books, 2025
    # - 12 books..." and the matching pages sentence.
    books_by_year = {}
    m = re.search(r"books read per year are as follows:\s*(.+?)\.\s*The data for pages", text)
    if m:
        for year, count in re.findall(r"(\d{4})\s*-\s*([\d,]+)\s*books?", m.group(1)):
            books_by_year[year] = int(count.replace(",", ""))

    pages_by_year = {}
    m = re.search(r"pages read per year are as follows:\s*(.+?)\.\s*$", text)
    if not m:
        m = re.search(r"pages read per year are as follows:\s*(.+)", text)
    if m:
        for year, count in re.findall(r"(\d{4})\s*-\s*([\d,]+)\s*pages?", m.group(1)):
            pages_by_year[year] = int(count.replace(",", ""))

    return {
        "total_books_all_time": total_books,
        "total_pages_all_time": total_pages,
        "current_streak_days": current_streak,
        "longest_streak_days": longest_streak,
        "average_time_to_finish": avg_finish,
        "average_rating": avg_rating,
        "review_count": review_count,
        "books_by_year": books_by_year,
        "pages_by_year": pages_by_year,
    }


def parse_profile_page(html):
    soup = BeautifulSoup(html, "html.parser")
    text = text_of(soup)

    books_this_year = first_int(r"([\d,]+)\s+This Year", text)

    personality = None
    m = re.search(r"Mainly reads[^.]*\.[^.]*\.", text)
    if m:
        personality = re.sub(r"\s+([,.])", r"\1", m.group(0)).strip()

    currently_reading_count = first_int(r"Currently Reading\s*\((\d+)\)", text)
    to_read_count = first_int(r"To-Read Pile\s*\((\d+)\)", text)
    five_star_count = first_int(r"Five-Star Reads\s*\((\d+)\)", text)
    dnf_count = first_int(r"Did Not Finish\D{0,10}(\d+)", text)
    reviews_count = first_int(r"Reviews\D{0,10}(\d+)", text)

    currently_reading_titles = []
    heading = soup.find(string=re.compile(r"Currently Reading"))
    if heading:
        # Titles are carried in image alt text near the "Currently Reading" section.
        section = heading.find_parent()
        if section:
            for img in section.find_all_next("img", limit=10):
                alt = img.get("alt", "")
                if " by " in alt:
                    currently_reading_titles.append(alt.split(" by ")[0].strip())
                if currently_reading_count and len(currently_reading_titles) >= currently_reading_count:
                    break

    return {
        "books_this_year": books_this_year,
        "reading_personality": personality,
        "currently_reading_count": currently_reading_count,
        "currently_reading_titles": currently_reading_titles,
        "to_read_count": to_read_count,
        "five_star_count": five_star_count,
        "dnf_count": dnf_count,
        "reviews_count": reviews_count,
    }


def scrape(username):
    stats_html = fetch(f"https://app.thestorygraph.com/stats/{username}")
    time.sleep(3)  # small gap between requests rather than hitting back-to-back
    profile_html = fetch(f"https://app.thestorygraph.com/profile/{username}")

    # Debug dumps — always written so we can see exactly what the scraper
    # received if the parsed fields come back empty. Safe to delete once
    # everything's working.
    with open("debug_stats.html", "w", encoding="utf-8") as f:
        f.write(stats_html)
    with open("debug_profile.html", "w", encoding="utf-8") as f:
        f.write(profile_html)

    stats = parse_stats_page(stats_html)
    profile = parse_profile_page(profile_html)

    this_year = str(datetime.now().year)
    combined = {
        "username": username,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "year": int(this_year),
        "pages_this_year": stats["pages_by_year"].get(this_year),
        **stats,
        **profile,
    }
    return combined


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <storygraph_username> <output.json>")
        sys.exit(1)

    username, out_path = sys.argv[1], sys.argv[2]
    data = scrape(username)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    print(f"Wrote {out_path}:")
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
