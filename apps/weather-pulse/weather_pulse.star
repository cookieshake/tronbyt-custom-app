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

# Fonts used by the existing fx-pulse app. Only these names are referenced;
# the full font list is never enumerated.
FONT_SMALL = "tom-thumb"

# 3-column layout. Each column is 20px wide; the Row uses space_between so the
# three 20px columns (60px) are spread across 64px with 2px gaps between them.
COL_WIDTH = 20

# Day labels for the three columns. tom-thumb is a 5px pixel font with no
# Hangul glyphs, so short English labels are used instead of Korean.
DAY_LABELS = ["TODAY", "TMRW", "2DAY"]

# Short, emoji-free 3-4 char abbreviations for WMO weather codes. Codes not
# listed here fall back to a generic "???" marker. All fit within a 20px column.
WEATHER_LABELS = {
    0: "CLR",
    1: "CLR",
    2: "PRT",
    3: "OVC",
    45: "FOG",
    48: "FOG",
    51: "DRZ",
    53: "DRZ",
    55: "DRZ",
    56: "DRZ",
    57: "DRZ",
    61: "RAIN",
    63: "RAIN",
    65: "RAIN",
    66: "RAIN",
    67: "RAIN",
    71: "SNOW",
    73: "SNOW",
    75: "SNOW",
    77: "SNOW",
    80: "SHWR",
    81: "SHWR",
    82: "SHWR",
    85: "SNOW",
    86: "SNOW",
    95: "TNR",
    96: "TNR",
    99: "TNR",
}

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
            color = "#000000",
            child = render.Text(FALLBACK_TEXT, color = "#ffffff", font = FONT_SMALL),
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
        cells.append(column_cell(DAY_LABELS[i], format_temp(lo), format_temp(hi), weather_label(code)))

    if len(cells) == 0:
        return fallback()

    return render.Row(
        main_align = "space_between",
        cross_align = "center",
        children = cells,
    )

def column_cell(day, lo, hi, weather):
    # One 20px-wide column: day label on top, low/high temp in the middle,
    # weather abbreviation at the bottom. The degree symbol is omitted because
    # "12/25°" (23px) does not fit a 20px column; "12/25" (19px) does.
    return render.Box(
        width = COL_WIDTH,
        height = 32,
        child = render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Text(day, color = "#ffffff", font = FONT_SMALL),
                render.Text("%s/%s" % (lo, hi), color = "#ffffff", font = FONT_SMALL),
                render.Text(weather, color = "#aaaaaa", font = FONT_SMALL),
            ],
        ),
    )

def weather_label(code):
    if code == None:
        return "???"
    return WEATHER_LABELS.get(int(code), "???")

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
