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

# Color of the YTD sparkline drawn behind the rate text. A dark, low-contrast
# gray that is visible on the black body background but does not overpower the
# bright rate text.
SPARKLINE_COLOR = "#555555"

# Color of the rate text drawn on top of the sparkline. Bright so it stays
# readable over the graph.
RATE_COLOR = "#ffffff"

def main(config):
    base = config.get("base", DEFAULT_BASE).upper()
    quote = config.get("quote", DEFAULT_QUOTE).upper()

    rate = fetch_rate(base, quote)
    now = time.now()
    ytd_data = fetch_ytd(base, quote, now)

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
                            sparkline(ytd_data, now.year),
                            # Full-width Box centers the opaque panel + rate text
                            # horizontally in the body.
                            render.Box(
                                width = 64,
                                height = BODY_HEIGHT,
                                child = render.Box(
                                    width = 24,
                                    height = 10,
                                    color = "#000000",
                                    child = render.Text(
                                        rate,
                                        color = RATE_COLOR,
                                        font = "6x10",
                                    ),
                                ),
                            ),
                        ],
                    ),
                ),
            ],
        ),
    )

def sparkline(data, year):
    # Draw the YTD rate series as a line plot filling the 16px body. The x-axis
    # is fixed to the full year: Jan 1 = x 0, Dec 31 = x 365 (or 366 in a leap
    # year). Data points are placed at their day-of-year position, so today's
    # data only reaches the elapsed fraction of the year and the future region
    # stays empty. If there are fewer than 2 points (or the fetch failed),
    # render an empty box so the rate text still shows.
    if data == None or len(data) < 2:
        return render.Box(width = 64, height = BODY_HEIGHT)
    last_doy = 365 if is_leap(year) else 364
    return render.Plot(
        data = data,
        width = 64,
        height = BODY_HEIGHT,
        color = SPARKLINE_COLOR,
        x_lim = (0, last_doy),
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

def fetch_ytd(base, quote, now):
    # Fetch daily rates from Jan 1 of the current year to today, and return a
    # list of (day_of_year, rate) tuples for the Plot widget. The x value is the
    # day-of-year (0-based) so the plot maps Jan 1 to x=0 and Dec 31 to the last
    # day of the year. Returns None on any failure so the caller can fall back
    # to showing just the rate text.
    if base == "" or quote == "":
        return None

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

    # Build a list of (day_of_year, rate) in date order. Parse each date string
    # (YYYY-MM-DD) safely and map it to its 0-based day-of-year. The API may
    # return the previous trading day (e.g. Dec 31 of the prior year) as the
    # first date, so skip any date not in the current year.
    points = []
    for date in sorted(rates.keys()):
        r = rates[date].get(quote)
        if r != None:
            t = time.parse_time(date, "2006-01-02", "UTC")
            if t.year != now.year:
                continue
            points.append((day_of_year(t.year, t.month, t.day), r))

    if len(points) < 2:
        return None
    return points

def day_of_year(year, month, day):
    # 0-based day-of-year, handling leap years correctly.
    days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if is_leap(year):
        days_in_month[1] = 29
    doy = 0
    for m in range(0, month - 1):
        doy = doy + days_in_month[m]
    return doy + day - 1

def is_leap(year):
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

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
