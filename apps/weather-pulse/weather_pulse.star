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

# Temperature accent colors: cool blue for the low, warm orange for the high.
# These visually distinguish the two values while staying readable on the
# dark navy background.
TEMP_LOW = "#6fb3ff"
TEMP_HIGH = "#ff9a4d"

# Icon palette (refined, from the later historical pixel-icon commit). A dark
# navy background with bright yellow/orange for sun/lightning, white/gray for
# clouds, and blue/cyan for rain/snow.
SUN = "#ffd700"
SUN_RAY = "#ffb300"
CLOUD = "#d8dee9"
CLOUD_DARK = "#8a94a6"
RAIN = "#4fc3f7"
SNOW = "#ffffff"
LIGHTNING = "#ffd700"
FOG = "#9aa4b2"

# Pixel-art weather icons, each a 12x12 grid. Every row is a list of
# (width, color) segments summing to 12; a color of None is transparent.
# Icons are assembled from render.Box/Row/Column primitives (no image files,
# no emoji, no unicode symbols). 12x12 keeps the column (day label + low/high
# + icon) within the 32px height.
ICONS = {
    "sun": [
        [(5, None), (2, SUN_RAY), (5, None)],
        [(5, None), (2, SUN_RAY), (5, None)],
        [(2, None), (2, SUN_RAY), (4, SUN), (2, SUN_RAY), (2, None)],
        [(1, None), (2, SUN_RAY), (6, SUN), (2, SUN_RAY), (1, None)],
        [(1, SUN_RAY), (4, None), (6, SUN), (1, None)],
        [(1, SUN_RAY), (4, None), (6, SUN), (1, None)],
        [(2, SUN_RAY), (8, SUN), (2, SUN_RAY)],
        [(2, SUN_RAY), (8, SUN), (2, SUN_RAY)],
        [(1, SUN_RAY), (4, None), (6, SUN), (1, None)],
        [(1, None), (2, SUN_RAY), (6, SUN), (2, SUN_RAY), (1, None)],
        [(2, None), (2, SUN_RAY), (4, SUN), (2, SUN_RAY), (2, None)],
        [(5, None), (2, SUN_RAY), (5, None)],
    ],
    "partly": [
        [(3, None), (4, SUN), (5, None)],
        [(3, None), (4, SUN), (5, None)],
        [(2, None), (6, SUN), (4, None)],
        [(1, None), (8, SUN), (3, None)],
        [(1, None), (8, SUN), (3, None)],
        [(2, None), (6, SUN), (4, None)],
        [(12, None)],
        [(4, None), (4, CLOUD), (4, None)],
        [(3, None), (6, CLOUD), (3, None)],
        [(2, None), (8, CLOUD), (2, None)],
        [(1, None), (10, CLOUD), (1, None)],
        [(12, CLOUD)],
    ],
    "cloud": [
        [(12, None)],
        [(12, None)],
        [(4, None), (4, CLOUD), (4, None)],
        [(3, None), (6, CLOUD), (3, None)],
        [(2, None), (8, CLOUD), (2, None)],
        [(1, None), (10, CLOUD), (1, None)],
        [(12, CLOUD)],
        [(12, CLOUD)],
        [(12, CLOUD)],
        [(12, None)],
        [(12, None)],
        [(12, None)],
    ],
    "rain": [
        [(12, None)],
        [(4, None), (4, CLOUD), (4, None)],
        [(3, None), (6, CLOUD), (3, None)],
        [(2, None), (8, CLOUD), (2, None)],
        [(1, None), (10, CLOUD), (1, None)],
        [(12, CLOUD)],
        [(12, CLOUD)],
        [(12, None)],
        [(2, None), (2, RAIN), (2, None), (2, RAIN), (2, None), (2, RAIN)],
        [(2, None), (2, RAIN), (2, None), (2, RAIN), (2, None), (2, RAIN)],
        [(2, None), (2, RAIN), (2, None), (2, RAIN), (2, None), (2, RAIN)],
        [(12, None)],
    ],
    "snow": [
        [(12, None)],
        [(4, None), (4, CLOUD), (4, None)],
        [(3, None), (6, CLOUD), (3, None)],
        [(2, None), (8, CLOUD), (2, None)],
        [(1, None), (10, CLOUD), (1, None)],
        [(12, CLOUD)],
        [(12, CLOUD)],
        [(12, None)],
        [(2, None), (2, SNOW), (2, None), (2, SNOW), (2, None), (2, SNOW)],
        [(2, None), (2, SNOW), (2, None), (2, SNOW), (2, None), (2, SNOW)],
        [(2, None), (2, SNOW), (2, None), (2, SNOW), (2, None), (2, SNOW)],
        [(12, None)],
    ],
    "thunder": [
        [(12, None)],
        [(4, None), (4, CLOUD), (4, None)],
        [(3, None), (6, CLOUD), (3, None)],
        [(2, None), (8, CLOUD), (2, None)],
        [(1, None), (10, CLOUD), (1, None)],
        [(12, CLOUD)],
        [(12, CLOUD)],
        [(12, None)],
        [(5, None), (2, LIGHTNING), (5, None)],
        [(4, None), (3, LIGHTNING), (5, None)],
        [(3, None), (4, LIGHTNING), (5, None)],
        [(2, None), (5, LIGHTNING), (5, None)],
    ],
    "fog": [
        [(12, None)],
        [(12, None)],
        [(12, None)],
        [(2, None), (8, FOG), (2, None)],
        [(12, None)],
        [(2, None), (8, FOG), (2, None)],
        [(12, None)],
        [(2, None), (8, FOG), (2, None)],
        [(12, None)],
        [(2, None), (8, FOG), (2, None)],
        [(12, None)],
        [(12, None)],
    ],
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
        cells.append(column_cell(DAY_LABELS[i], format_temp(lo), format_temp(hi), icon_widget(ICONS[icon_key(code)])))

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

def column_cell(day, lo, hi, icon):
    # One 20px-wide column: day label on top, low/high temp in the middle,
    # weather icon at the bottom. The degree symbol is omitted because
    # "12/30°" (23px) does not fit a 20px column; "12/30" (20px) does.
    # The low/high is a compact split Row: low (blue) "/" (dim) high (orange).
    # With tom-thumb, "12" (8px) + "/" (4px) + "30" (8px) = 20px, so it fills
    # the column exactly like the previous single "12/30" text and never
    # overflows the 64px-wide 3-column layout.
    return render.Box(
        width = COL_WIDTH,
        height = 32,
        color = BG,
        child = render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Text(day, color = TEXT_DIM, font = FONT_SMALL),
                render.Row(
                    main_align = "center",
                    cross_align = "center",
                    children = [
                        render.Text(lo, color = TEMP_LOW, font = FONT_SMALL),
                        render.Text("/", color = TEXT_DIM, font = FONT_SMALL),
                        render.Text(hi, color = TEMP_HIGH, font = FONT_SMALL),
                    ],
                ),
                icon,
            ],
        ),
    )

def spacer(width):
    # A transparent spacer Box to add explicit horizontal breathing room.
    return render.Box(width = width, height = 1)

def icon_widget(rows):
    # Assemble a 12x12 pixel-art icon from Box/Row/Column primitives. Each row
    # is a list of (width, color) segments; None color means transparent.
    return render.Column(
        children = [
            render.Row(children = [
                seg_box(seg)
                for seg in row
            ])
            for row in rows
        ],
    )

def seg_box(seg):
    if seg[1] == None:
        return render.Box(width = seg[0], height = 1)
    return render.Box(width = seg[0], height = 1, color = seg[1])

def icon_key(code):
    # Map a WMO weather code to one of the pixel-art icon names.
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
