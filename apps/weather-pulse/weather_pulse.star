load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

# Refresh every 60 minutes (matches the recommended render interval).
CACHE_TTL_SECONDS = 3600

# Geocoding results change rarely; cache them for a full day.
GEOCODE_CACHE_TTL_SECONDS = 86400

# Open-Meteo endpoints.
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

# Defaults.
DEFAULT_CITY = "Seoul"
DEFAULT_TEMP_UNIT = "celsius"
DEFAULT_WIND_UNIT = "ms"

# Fallback text shown when the API fails or the data is missing/malformed.
FALLBACK_TEXT = "Weather unavailable"

# Font used by the existing fx-pulse app. Only this name is referenced; the
# full font list is never enumerated.
FONT_SMALL = "tom-thumb"

# 3-column layout. Each column is 20px wide. The outer Row is centered with
# explicit 1px spacers on the left/right edges and 1px spacers between columns:
#   1 + 20 + 1 + 20 + 1 + 20 + 1 = 64
# This fills the full 64px width symmetrically instead of relying on
# space_between, so the three columns are evenly spaced and centered.
COL_WIDTH = 20
EDGE_SPACER = 1
GAP_SPACER = 1

# Day labels for the three columns. tom-thumb is a 5px pixel font with no
# Hangul glyphs, so short English labels are used instead of Korean.
DAY_LABELS = ["TODAY", "+1D", "+2D"]

# Dark navy background and high-contrast text colors.
BG = "#0a0e1a"
TEXT = "#ffffff"
TEXT_DIM = "#9aa4b2"

# Weather emoji per WMO state. Rendered with render.Emoji (the same built-in
# widget the fx-pulse app uses for flags), so no external assets are needed.
# Codes not listed here fall back to a cloud emoji.
WEATHER_EMOJI = {
    "sun": "☀️",
    "partly": "🌤️",
    "cloud": "☁️",
    "fog": "🌫️",
    "rain": "🌧️",
    "snow": "❄️",
    "thunder": "⛈️",
}

# Emoji render height. The emoji sprite is rendered at its native size scaled
# to this height; 14px keeps it large and readable.
EMOJI_HEIGHT = 14

# How many pixels to shift the emoji down within its column slot. The emoji is
# placed inside a transparent Box that is EMOJI_HEIGHT + EMOJI_OFFSET tall, with
# a top spacer of EMOJI_OFFSET, so the icon sits 2px lower without clipping at
# the bottom of the 32px screen or overlapping the low/high temp above it.
EMOJI_OFFSET = 2

def main(config):
    city = config.get("city", DEFAULT_CITY).strip()
    temp_unit = config.get("temperature_unit", DEFAULT_TEMP_UNIT)
    wind_unit = config.get("wind_speed_unit", DEFAULT_WIND_UNIT)

    # Guard against an empty/whitespace city name.
    if city == "":
        return fallback()

    coords = geocode(city)
    if coords == None:
        return fallback()

    data = fetch_forecast(coords[0], coords[1], temp_unit, wind_unit)
    if data == None:
        return fallback()

    return render.Root(child = layout(data))

def fallback():
    return render.Root(
        child = render.Box(
            width = 64,
            height = 32,
            color = BG,
            child = render.Text(FALLBACK_TEXT, color = TEXT, font = FONT_SMALL),
        ),
    )

def layout(data):
    current = data.get("current")
    daily = data.get("daily")
    codes = daily.get("weather_code")
    highs = daily.get("temperature_2m_max")
    lows = daily.get("temperature_2m_min")

    # Today's icon: prefer the current weather code, else today's daily code.
    today_code = None
    if current != None:
        today_code = current.get("weather_code")
    if today_code == None and codes != None and len(codes) > 0:
        today_code = codes[0]

    cells = []
    for i in range(0, 3):
        if codes == None or i >= len(codes):
            break
        code = codes[i]
        if i == 0 and today_code != None:
            code = today_code
        hi = highs[i] if highs != None and i < len(highs) else None
        lo = lows[i] if lows != None and i < len(lows) else None
        cells.append(column_cell(DAY_LABELS[i], format_temp(lo), format_temp(hi), emoji_widget(icon_key(code))))

    if len(cells) == 0:
        return fallback()

    # Build the centered row: 1px edge spacer, then each column separated by a
    # 1px gap spacer, then a 1px edge spacer. With 3 columns this is exactly
    # 64px wide and centered.
    children = [spacer(EDGE_SPACER)]
    for idx, cell in enumerate(cells):
        if idx > 0:
            children.append(spacer(GAP_SPACER))
        children.append(cell)
    children.append(spacer(EDGE_SPACER))

    return render.Row(
        main_align = "center",
        cross_align = "center",
        children = children,
    )

def column_cell(day, lo, hi, emoji):
    # One 20px-wide column: day label on top, low/high temp in the middle,
    # weather emoji at the bottom. The degree symbol is omitted because
    # "12/25°" (23px) does not fit a 20px column; "12/25" (19px) does.
    return render.Box(
        width = COL_WIDTH,
        height = 32,
        color = BG,
        child = render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Text(day, color = TEXT, font = FONT_SMALL),
                render.Text("%s/%s" % (lo, hi), color = TEXT, font = FONT_SMALL),
                emoji,
            ],
        ),
    )

def spacer(width):
    # A transparent spacer Box to add explicit horizontal breathing room.
    return render.Box(width = width, height = 1)

def emoji_widget(key):
    # Render the weather emoji at a fixed height, centered in the column, and
    # shifted down by EMOJI_OFFSET via a transparent top spacer inside a fixed
    # slot. The slot is EMOJI_HEIGHT + EMOJI_OFFSET tall so the icon is not
    # clipped at the bottom of the 32px screen.
    return render.Box(
        width = COL_WIDTH,
        height = EMOJI_HEIGHT + EMOJI_OFFSET,
        child = render.Column(
            main_align = "start",
            cross_align = "center",
            children = [
                render.Box(width = 1, height = EMOJI_OFFSET),
                render.Emoji(emoji = WEATHER_EMOJI[key], height = EMOJI_HEIGHT),
            ],
        ),
    )

def icon_key(code):
    # Map a WMO weather code to one of the emoji keys.
    if code == None:
        return "cloud"
    c = int(code)
    if c in (0, 1):
        return "sun"
    if c == 2:
        return "partly"
    if c == 3:
        return "cloud"
    if c in (45, 48):
        return "fog"
    if c in (51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82):
        return "rain"
    if c in (71, 73, 75, 77, 85, 86):
        return "snow"
    if c in (95, 96, 99):
        return "thunder"
    return "cloud"

def format_temp(value):
    # Round to the nearest integer for display.
    if value == None:
        return "--"
    return "%d" % int(value + 0.5)

def geocode(city):
    res = http.get(
        url = GEOCODE_URL,
        params = {
            "name": city,
            "count": "1",
            "language": "ko",
            "format": "json",
        },
        ttl_seconds = GEOCODE_CACHE_TTL_SECONDS,
    )
    if res.status_code != 200:
        return None

    data = res.json()
    results = data.get("results")
    if results == None or len(results) == 0:
        return None

    first = results[0]
    lat = first.get("latitude")
    lon = first.get("longitude")
    if lat == None or lon == None:
        return None

    return (lat, lon)

def fetch_forecast(lat, lon, temp_unit, wind_unit):
    res = http.get(
        url = FORECAST_URL,
        params = {
            "latitude": str(lat),
            "longitude": str(lon),
            "timezone": "auto",
            "forecast_days": "4",
            "current": "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "temperature_unit": temp_unit,
            "wind_speed_unit": wind_unit,
        },
        ttl_seconds = CACHE_TTL_SECONDS,
    )
    if res.status_code != 200:
        return None

    data = res.json()
    current = data.get("current")
    daily = data.get("daily")
    if current == None or daily == None:
        return None

    # Guard against missing/empty daily arrays.
    if daily.get("time") == None or len(daily.get("time")) == 0:
        return None

    return data

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "city",
                name = "City",
                desc = "City name to look up, e.g. Seoul.",
                icon = "mapPin",
                default = DEFAULT_CITY,
            ),
            schema.Dropdown(
                id = "temperature_unit",
                name = "Temperature Unit",
                desc = "Unit for temperature values.",
                icon = "thermometer",
                default = DEFAULT_TEMP_UNIT,
                options = [
                    schema.Option(display = "Celsius", value = "celsius"),
                    schema.Option(display = "Fahrenheit", value = "fahrenheit"),
                ],
            ),
            schema.Dropdown(
                id = "wind_speed_unit",
                name = "Wind Speed Unit",
                desc = "Unit for wind speed values.",
                icon = "wind",
                default = DEFAULT_WIND_UNIT,
                options = [
                    schema.Option(display = "m/s", value = "ms"),
                    schema.Option(display = "km/h", value = "kmh"),
                    schema.Option(display = "mph", value = "mph"),
                    schema.Option(display = "knots", value = "kn"),
                ],
            ),
        ],
    )
