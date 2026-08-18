load("http.star", "http")
load("images/eur_flag.png", EUR_FLAG = "file")
load("images/gbp_flag.webp", GBP_FLAG = "file")
load("images/jpy_flag.webp", JPY_FLAG = "file")

# Official flag images bundled as local assets (from the tronbyt/apps
# currencyconverter app). Loading them as "file" assets keeps them local so the
# app does not depend on a remote URL at render time.
load("images/krw_flag.webp", KRW_FLAG = "file")
load("images/usd_flag.webp", USD_FLAG = "file")
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

# Flag image assets for the supported currencies. Each is a full flag image
# (40x30 for the webp flags) that preserves the complete design, including the
# Korean taegeuk and the four trigrams (건곤감리). Currencies not listed here
# fall back to their 3-letter code.
FLAG_ASSETS = {
    "KRW": KRW_FLAG,
    "USD": USD_FLAG,
    "EUR": EUR_FLAG,
    "JPY": JPY_FLAG,
    "GBP": GBP_FLAG,
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
                            pad = (0, 0, 0, 0),
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
    # Render a fixed-size flag image for known currencies, or fall back to the
    # 3-letter code for unknown ones. The flag images are 40x30 (2:3 ratio);
    # render at 16x15 to fill the 16px header while preserving the full design
    # (taegeuk + trigrams for KRW) from the source asset.
    if code in FLAG_ASSETS:
        return render.Image(
            src = FLAG_ASSETS[code].readall(),
            width = 16,
            height = 15,
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
