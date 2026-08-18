load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

# Cache the rate for 10 minutes (matches the recommended render interval).
CACHE_TTL_SECONDS = 600

# Frankfurter API endpoint. Returns JSON like:
#   {"amount":1.0,"base":"USD","date":"2026-08-17","rates":{"KRW":1411.91}}
API_URL = "https://api.frankfurter.dev/v1/latest"

# Default base/quote currencies.
DEFAULT_BASE = "USD"
DEFAULT_QUOTE = "KRW"

# Fallback text shown when the API fails or the rate is missing.
FALLBACK_TEXT = "Rate unavailable"

# Fixed-size pixel-art flags for a few common currencies. Pixlet renders emoji
# flags at their native sprite size (e.g. US 7x5, KR 4x4) regardless of the
# Text/Emoji height, so they appear different sizes. Drawing each flag as a
# fixed 10x10 grid of colored Boxes guarantees equal visual size. Currencies
# not listed here fall back to their 3-letter code.

# 10x10 pixel-art flag rows for the most common currencies. Each entry is a
# list of 10 rows; each row is a list of (width, color) segments summing to 10.
FLAG_PIXELS = {
    "USD": [
        [(3, "#0a3161"), (7, "#b31942")],
        [(3, "#0a3161"), (7, "#ffffff")],
        [(3, "#0a3161"), (7, "#b31942")],
        [(3, "#0a3161"), (7, "#ffffff")],
        [(3, "#0a3161"), (7, "#b31942")],
        [(10, "#ffffff")],
        [(10, "#b31942")],
        [(10, "#ffffff")],
        [(10, "#b31942")],
        [(10, "#ffffff")],
    ],
    "KRW": [
        [(10, "#ffffff")],
        [(10, "#ffffff")],
        [(4, "#ffffff"), (2, "#cd2e3a"), (4, "#ffffff")],
        [(3, "#ffffff"), (2, "#cd2e3a"), (2, "#0047a0"), (3, "#ffffff")],
        [(3, "#ffffff"), (1, "#cd2e3a"), (2, "#ffffff"), (1, "#0047a0"), (3, "#ffffff")],
        [(3, "#ffffff"), (1, "#0047a0"), (2, "#ffffff"), (1, "#cd2e3a"), (3, "#ffffff")],
        [(3, "#ffffff"), (2, "#0047a0"), (2, "#cd2e3a"), (3, "#ffffff")],
        [(4, "#ffffff"), (2, "#0047a0"), (4, "#ffffff")],
        [(10, "#ffffff")],
        [(10, "#ffffff")],
    ],
    "EUR": [
        [(10, "#003399")],
        [(10, "#003399")],
        [(10, "#003399")],
        [(10, "#ffcc00")],
        [(10, "#ffcc00")],
        [(10, "#ffcc00")],
        [(10, "#ffcc00")],
        [(10, "#ffcc00")],
        [(10, "#ffcc00")],
        [(10, "#ffcc00")],
    ],
    "JPY": [
        [(10, "#ffffff")],
        [(10, "#ffffff")],
        [(10, "#ffffff")],
        [(3, "#ffffff"), (4, "#bc002d"), (3, "#ffffff")],
        [(3, "#ffffff"), (4, "#bc002d"), (3, "#ffffff")],
        [(3, "#ffffff"), (4, "#bc002d"), (3, "#ffffff")],
        [(3, "#ffffff"), (4, "#bc002d"), (3, "#ffffff")],
        [(10, "#ffffff")],
        [(10, "#ffffff")],
        [(10, "#ffffff")],
    ],
    "GBP": [
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
        [(10, "#012169")],
    ],
}

# The screen is split exactly in half: header 16 rows, body 16 rows.
HEADER_HEIGHT = 16
BODY_HEIGHT = 16

def main(config):
    base = config.get("base", DEFAULT_BASE).upper()
    quote = config.get("quote", DEFAULT_QUOTE).upper()

    rate = fetch_rate(base, quote)

    return render.Root(
        child = render.Column(
            children = [
                render.Box(
                    width = 64,
                    height = HEADER_HEIGHT,
                    color = "#333333",
                    child = render.Marquee(
                        width = 64,
                        scroll_direction = "horizontal",
                        offset_start = 0,
                        offset_end = 0,
                        align = "center",
                        child = render.Padding(
                            pad = (0, 3, 0, 3),
                            child = render.Row(
                                main_align = "center",
                                cross_align = "center",
                                children = [
                                    flag_widget(base),
                                    spacer(1),
                                    render.Text(base, color = "#ffffff", font = "tom-thumb"),
                                    spacer(1),
                                    render.Text("→", color = "#ffffff", font = "tom-thumb"),
                                    spacer(1),
                                    flag_widget(quote),
                                    spacer(1),
                                    render.Text(quote, color = "#ffffff", font = "tom-thumb"),
                                ],
                            ),
                        ),
                    ),
                ),
                render.Box(
                    width = 64,
                    height = BODY_HEIGHT,
                    color = "#000000",
                    child = render.Text(
                        rate,
                        color = "#ffffff",
                        font = "6x10",
                    ),
                ),
            ],
        ),
    )

def spacer(width):
    # A transparent spacer Box to add horizontal breathing room between
    # header elements. Transparent (no color) so it doesn't paint over the
    # header background.
    return render.Box(width = width, height = 1)

def flag_widget(code):
    # Render a fixed 10x10 pixel-art flag for known currencies, or fall back
    # to the 3-letter code for unknown ones.
    if code in FLAG_PIXELS:
        return render.Column(
            children = [
                render.Row(children = [
                    render.Box(width = seg[0], height = 1, color = seg[1])
                    for seg in row
                ])
                for row in FLAG_PIXELS[code]
            ],
        )
    return render.Text(code, color = "#ffffff", font = "tom-thumb")

def fetch_rate(base, quote):
    # Guard against empty/invalid currency codes.
    if base == "" or quote == "":
        return FALLBACK_TEXT

    res = http.get(
        url = "%s?base=%s&symbols=%s" % (API_URL, base, quote),
        ttl_seconds = CACHE_TTL_SECONDS,
    )
    if res.status_code != 200:
        return FALLBACK_TEXT

    data = res.json()
    rates = data.get("rates")
    if rates == None:
        return FALLBACK_TEXT
    rate = rates.get(quote)
    if rate == None:
        return FALLBACK_TEXT

    return format_rate(rate)

def format_rate(rate):
    # Show 2 decimals for most currencies, but KRW/JPY-style rates are large
    # and look better with no decimals. Starlark's % formatting does not
    # support precision or zero-padding, so use %g for small rates (natural
    # formatting) and %d for large rates.
    if rate >= 100:
        return "%d" % rate
    return "%g" % rate

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "base",
                name = "Base Currency",
                desc = "The base (first) currency code, e.g. USD.",
                icon = "dollarSign",
                default = DEFAULT_BASE,
            ),
            schema.Text(
                id = "quote",
                name = "Quote Currency",
                desc = "The quote (second) currency code, e.g. KRW.",
                icon = "dollarSign",
                default = DEFAULT_QUOTE,
            ),
        ],
    )
