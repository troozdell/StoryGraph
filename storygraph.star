"""
Applet: StoryGraph Stats
Summary: Flips through reading stats
Description: Renders directly from values passed in at render time (see
    update_and_push.sh) — no network fetch inside this app itself. Cycles
    through screens showing books/pages this year and all-time pages.
    Styled to roughly match StoryGraph's own teal-on-dark-blue look.
Author: you
"""

load("render.star", "render")
load("encoding/base64.star", "base64")

# Approximate StoryGraph brand palette (their site uses a teal-green accent
# on a dark blue-grey background — this isn't pulled from an official brand
# kit, just matched by eye, so nudge these if you want it closer).
TEAL = "#3AAF9A"
BG_DARK = "#000000"
CREAM = "#F2F2F0"
MUTED = "#7FA79D"

# Small original "ascending bars" mark in the brand teal — evokes the
# "Graph" half of StoryGraph without reproducing their actual trademarked
# logo artwork.
GRAPH_ICON = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABIAAAASCAYAAABWzo5XAAACgUlEQVR4nK1TTWsaQRjenVk3q6tltbKV9lpKUgrSi0YCQmiCrn8geEhJT/kRhV7yCyq9hUJ/gD1Igh60soEs9FCPJU1JUtqD9sPgWjfWrPNR3o1rcouhfeDdmXdm5+F5n3dGEP4TREmShJWVlXg4HFZgodVqfT87O2PZbPYu55xTSlmtVusQQoRkMhkyDOOxZVkfTdO0EUICY+yCKZFIoPF4/IdPsLW19WRjY+M+v4J0Oh02TfOln+/s7LyAsxjjqSIEH9u2v1FKXQgAIYTC/Pz8/DeM/X7f9Q8QQkapVGotEomIlFJBFMVLIoxxAGMsQ4gT+DnGWB4MBrRcLr/mnDPGGNF1/WEmk4l5BAhdEl0HRVFQvV7/JIoiggDCQqGQ9Uy+qug6qKqKDw8P3ZOTk71AIBACstXV1WfgEZQ3M5EkSd5/9Xp9G9SAT/Pz88bCwoLCOffKm4nIR61WewdqoAEIISmXyz2C9ZmJGGMcxv39/R+9Xu+LLMthyA3DWJvs34zo9PSUW5b1xjd8cXHxqa7raGYiH9CharX6Fuau6zqqqupLS0sJyD0iSukYDITwb6+fE0JGPhEY22g0PgMJqIK1YrHolQf3QojH4w8kSVIggsFgcG5uLgBzRVE0GDHG3mWBdh8dHY2Pj4/3wCfbtr92u92Op1aWZWFzczOpadotWNjd3f3Q6/XG6+vrmYkyUiqV3g+Hw2mJy8vL0Wg0Gmw2mx3btjmIEWOxmFipVF5pmgavnamqehshhB3H6foHNU27B88IiOH5OI7zy3XdYSQSuXNwcNDM5/PPpdFoxMvl8nYoFApO7AEvOMZ42gh4xFM5F/fG24P/2u32z6t7/4y/1SNta1ME7ZIAAAAASUVORK5CYII=")


def format_thousands(n):
    """Starlark's str.format doesn't support the ',' spec like Python does,
    so commas get inserted by hand. Starlark also has no while loop, so this
    uses a bounded for loop instead (10 iterations is far more than any
    realistic page/book count needs)."""
    negative = n < 0
    s = str(int(abs(n)))
    groups = []
    for _ in range(10):
        if len(s) <= 3:
            groups.insert(0, s)
            break
        groups.insert(0, s[-3:])
        s = s[:-3]
    result = ",".join(groups)
    return "-" + result if negative else result


def get_int(config, key):
    """Reads an integer straight out of the render-time config (passed in
    as key=value args by update_and_push.sh) — no fetch, no cache."""
    val = config.get(key)
    if val == None:
        return None
    return int(val)


def screen(category, timeframe, value):
    """One screen: small teal graph icon on the left, and centered text in
    the remaining space — category label, timeframe, then the number —
    e.g. 'Pages' / 'This Year' / '12,285'."""
    return render.Box(
        width = 64,
        height = 32,
        color = BG_DARK,
        child = render.Row(
            expanded = True,
            main_align = "start",
            cross_align = "center",
            children = [
                render.Padding(
                    pad = (4, 0, 2, 0),
                    child = render.Image(src = GRAPH_ICON, width = 18, height = 18),
                ),
                render.Box(
                    width = 39,  # 64 - icon(18) - padding(4+3)
                    child = render.Column(
                        main_align = "center",
                        cross_align = "center",
                        children = [
                            render.Text(content = category, color = TEAL, font = "tb-8"),
                            render.Text(content = timeframe, color = MUTED, font = "tb-8"),
                            render.Text(content = str(value), color = CREAM, font = "tb-8"),
                        ],
                    ),
                ),
            ],
        ),
    )


def build_frames(config):
    frames = []

    pages_this_year = get_int(config, "pages_this_year")
    if pages_this_year != None:
        frames.append(screen("Pages", "this year", format_thousands(pages_this_year)))

    books_this_year = get_int(config, "books_this_year")
    if books_this_year != None:
        frames.append(screen("Books", "this year", books_this_year))

    total_pages = get_int(config, "total_pages_all_time")
    if total_pages != None:
        frames.append(screen("Pages", "all-time", format_thousands(total_pages)))

    return frames


def error_frame(message):
    return render.Root(
        child = render.Box(
            width = 64,
            height = 32,
            color = BG_DARK,
            child = render.WrappedText(
                content = message,
                font = "tom-thumb",
                color = "#ff6b6b",
                align = "center",
            ),
        ),
    )


def main(config):
    frames = build_frames(config)
    if not frames:
        return error_frame("No stats to show yet")

    return render.Root(
        delay = 4000,
        child = render.Animation(children = frames),
    )
