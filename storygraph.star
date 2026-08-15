"""
Applet: StoryGraph Stats
Summary: Flips through reading stats
Description: Fetches a small JSON stats file (generated from a StoryGraph
    library CSV export) and cycles through frames showing books read this
    year, average rating, top mood, currently reading, and more.
Author: you
"""

load("render.star", "render")
load("http.star", "http")
load("cache.star", "cache")
load("schema.star", "schema")
load("encoding/json.star", "json")

# Set this to your hosted stats.json URL, e.g. a GitHub Gist "raw" link
# WITHOUT a commit hash in it, so it always serves the latest revision:
#   https://gist.githubusercontent.com/<user>/<gist_id>/raw/stats.json
DEFAULT_JSON_URL = "https://gist.githubusercontent.com/YOUR_USERNAME/YOUR_GIST_ID/raw/stats.json"

CACHE_TTL_SECONDS = 60 * 30  # refetch at most every 30 minutes

PINK = "#e05a8f"
CREAM = "#fdf3e7"
DARK = "#241d2c"


def fetch_stats(url):
    cached = cache.get("storygraph_stats")
    if cached != None:
        return json.decode(cached)

    res = http.get(url)
    if res.status_code != 200:
        return None

    body = res.body()
    cache.set("storygraph_stats", body, ttl_seconds = CACHE_TTL_SECONDS)
    return json.decode(body)


def stat_frame(big_text, label, sub = ""):
    children = [
        render.Box(height = 2, width = 1),
        render.Text(content = big_text, font = "6x13", color = PINK),
        render.Text(content = label, font = "tom-thumb", color = CREAM),
    ]
    if sub:
        children.append(render.Text(content = sub, font = "tom-thumb", color = "#a9a9a9"))
    return render.Box(
        width = 64,
        height = 32,
        color = DARK,
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            expanded = True,
            children = children,
        ),
    )


def title_frame(title_text, label):
    return render.Box(
        width = 64,
        height = 32,
        color = DARK,
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            expanded = True,
            children = [
                render.Text(content = label, font = "tom-thumb", color = PINK),
                render.Box(height = 1, width = 1),
                render.Marquee(
                    width = 60,
                    child = render.Text(content = title_text, font = "tom-thumb", color = CREAM),
                ),
            ],
        ),
    )


def build_frames(stats):
    frames = []

    frames.append(stat_frame(
        str(stats.get("books_this_year", 0)),
        "books read in %s" % str(stats.get("year", "")),
    ))

    pages_this_year = stats.get("pages_this_year")
    if pages_this_year != None:
        frames.append(stat_frame(
            "{:,}".format(pages_this_year),
            "pages read in %s" % str(stats.get("year", "")),
        ))

    total_pages = stats.get("total_pages_all_time")
    if total_pages != None:
        frames.append(stat_frame(
            "{:,}".format(total_pages),
            "pages read all-time",
        ))

    avg = stats.get("average_rating")
    if avg != None:
        frames.append(stat_frame(str(avg) + " \u2605", "average rating"))

    if stats.get("five_star_count") != None:
        frames.append(stat_frame(
            str(stats["five_star_count"]),
            "five-star reads",
        ))

    if stats.get("current_streak_days") != None:
        frames.append(stat_frame(
            str(stats["current_streak_days"]),
            "day reading streak",
            "best: %s days" % str(stats.get("longest_streak_days", "?")),
        ))

    if stats.get("average_time_to_finish"):
        frames.append(stat_frame(
            stats["average_time_to_finish"],
            "avg. time to finish",
        ))

    if stats.get("to_read_count") != None:
        frames.append(stat_frame(
            str(stats["to_read_count"]),
            "books on the TBR",
        ))

    if stats.get("dnf_count") != None:
        frames.append(stat_frame(
            str(stats["dnf_count"]),
            "did-not-finish",
        ))

    reading_titles = stats.get("currently_reading_titles") or []
    if reading_titles:
        frames.append(title_frame(reading_titles[0], "currently reading"))

    if stats.get("reading_personality"):
        frames.append(title_frame(stats["reading_personality"], "reading style"))

    return frames


def error_frame(message):
    return render.Root(
        child = render.Box(
            width = 64,
            height = 32,
            color = DARK,
            child = render.WrappedText(
                content = message,
                font = "tom-thumb",
                color = "#ff6b6b",
                align = "center",
            ),
        ),
    )


def main(config):
    url = config.get("json_url", DEFAULT_JSON_URL)
    stats = fetch_stats(url)

    if not stats:
        return error_frame("Couldn't load StoryGraph stats")

    frames = build_frames(stats)
    if not frames:
        return error_frame("No stats to show yet")

    return render.Root(
        delay = 4000,
        child = render.Animation(children = frames),
    )


def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "json_url",
                name = "Stats JSON URL",
                desc = "Raw URL to the stats.json file (e.g. a GitHub Gist raw link)",
                icon = "link",
            ),
        ],
    )
