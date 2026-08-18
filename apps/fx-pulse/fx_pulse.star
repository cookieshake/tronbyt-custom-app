load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

# Cache the rate for 10 minutes (matches the recommended render interval).
CACHE_TTL_SECONDS = 600

# Frankfurter API endpoints. Returns JSON like:
#   latest:  {"amount":1.0,"base":"USD","date":"2026-08-17","rates":{"KRW":1411.91}}
#   timeseries: {"amount":1.0,"base":"USD","start_date":"...","end_date":"...","rates":{"2026-01-01":{"KRW":...},...}}
API_URL = "https://api.frankfurter.dev/v1/latest"
TIMESERIES_URL = "https://api.frankfurter.dev/v1"

# Default base/quote currencies.
DEFAULT_BASE = "USD"
DEFAULT_QUOTE = "KRW"

# Fallback text shown when the API fails or the rate is missing.
FALLBACK_TEXT = "Rate unavailable"

# Flag emoji for the supported currencies. Pixlet's render.Emoji widget renders
# a single emoji at its native sprite size (10x10) regardless of the requested
# height, and different flags have slightly different visual bboxes. We use the
# natural sprite size/ratio (no forced square box). Currencies not listed here
# fall back to their 3-letter code.
FLAG_EMOJI = {
    "KRW": "🇰🇷",
    "USD": "🇺🇸",
    "EUR": "🇪🇺",
    "JPY": "🇯🇵",
    "GBP": "🇬🇧",
}

# Font for the currency codes. tb-8 is larger and more readable than tom-thumb
# while still fitting the 16px header.
CODE_FONT = "tb-8"

# The screen is split exactly in half: header 16 rows, body 16 rows.
HEADER_HEIGHT = 16
BODY_HEIGHT = 16

# Color of the YTD sparkline drawn behind the rate text. A mid-bright gray that
# is visible on the black body background but does not overpower the white rate
# text.
SPARKLINE_COLOR = "#888888"

def main(config):
    base = config.get("base", DEFAULT_BASE).upper()
    quote = config.get("quote", DEFAULT_QUOTE).upper()

    rate = fetch_rate(base, quote)
    ytd_data = fetch_ytd(base, quote)

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
                            pad = (0, 0, 0, 0),
                            child = render.Row(
                                main_align = "center",
                                cross_align = "center",
                                children = [
                                    flag_widget(base),
                                    spacer(1),
                                    render.Text(base, color = "#ffffff", font = CODE_FONT),
                                    spacer(1),
                                    render.Text("→", color = "#ffffff", font = CODE_FONT),
                                    spacer(1),
                                    flag_widget(quote),
                                    spacer(1),
                                    render.Text(quote, color = "#ffffff", font = CODE_FONT),
                                ],
                            ),
                        ),
                    ),
                ),
                render.Box(
                    width = 64,
                    height = BODY_HEIGHT,
                    color = "#000000",
                    child = render.Stack(
                        children = [
                            sparkline(ytd_data),
                            render.Text(
                                rate,
                                color = "#ffffff",
                                font = "6x10",
                            ),
                        ],
                    ),
                ),
            ],
        ),
    )

def sparkline(data):
    # Draw the YTD rate series as a line plot filling the 16px body. If there
    # are fewer than 2 points (or the fetch failed), render an empty box so the
    # rate text still shows.
    if data == None or len(data) < 2:
        return render.Box(width = 64, height = BODY_HEIGHT)
    return render.Plot(
        data = data,
        width = 64,
        height = BODY_HEIGHT,
        color = SPARKLINE_COLOR,
        y_lim = (min([d[1] for d in data]), max([d[1] for d in data])),
    )

def spacer(width):
    # A transparent spacer Box to add horizontal breathing room between
    # header elements. Transparent (no color) so it doesn't paint over the
    # header background.
    return render.Box(width = width, height = 1)

def flag_widget(code):
    # Render a flag emoji for known currencies, or fall back to the 3-letter
    # code for unknown ones. Uses the emoji's natural sprite size/ratio.
    if code in FLAG_EMOJI:
        return render.Emoji(emoji = FLAG_EMOJI[code], height = 10)
    return render.Text(code, color = "#ffffff", font = CODE_FONT)

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

def fetch_ytd(base, quote):
    # Fetch daily rates from Jan 1 of the current year to today, and return a
    # list of (index, rate) tuples for the Plot widget. Returns None on any
    # failure so the caller can fall back to showing just the rate text.
    if base == "" or quote == "":
        return None

    now = time.now()
    start = time.time(year = now.year, month = 1, day = 1)
    end = now
    url = "%s/%s..%s?base=%s&symbols=%s" % (
        TIMESERIES_URL,
        start.format("2006-01-02"),
        end.format("2006-01-02"),
        base,
        quote,
    )

    res = http.get(url = url, ttl_seconds = CACHE_TTL_SECONDS)
    if res.status_code != 200:
        return None

    data = res.json()
    rates = data.get("rates")
    if rates == None:
        return None

    # Build a list of (index, rate) in date order.
    points = []
    for date in sorted(rates.keys()):
        r = rates[date].get(quote)
        if r != None:
            points.append((len(points), r))

    if len(points) < 2:
        return None
    return points

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
