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

# Flag emoji for a few common currencies. Pixlet's Text widget renders flag
# emojis natively (verified against the official docs and a render probe).
# Currencies not listed here fall back to their 3-letter code.
FLAGS = {
    "USD": "🇺🇸",
    "KRW": "🇰🇷",
    "EUR": "🇪🇺",
    "GBP": "🇬🇧",
    "JPY": "🇯🇵",
    "CNY": "🇨🇳",
    "AUD": "🇦🇺",
    "CAD": "🇨🇦",
    "CHF": "🇨🇭",
    "INR": "🇮🇳",
    "BRL": "🇧🇷",
    "MXN": "🇲🇽",
}

# Header occupies the top 11 rows. Flags render at 10x10 px regardless of font,
# and the header text is 9px tall, so 11px centers it with a 1px margin above
# and below (verified via pixel analysis). The body uses the remaining 21 rows.
HEADER_HEIGHT = 11
BODY_HEIGHT = 21

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
                        child = render.Text(
                            "%s %s → %s %s" % (flag_for(base), base, flag_for(quote), quote),
                            color = "#ffffff",
                            font = "tom-thumb",
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

def flag_for(code):
    return FLAGS.get(code, code)

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
