load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

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
FONT_LARGE = "6x10"

# Screen split: header shows location + current conditions, body shows the
# daily high/low forecast.
HEADER_HEIGHT = 12
BODY_HEIGHT = 20

# Short, emoji-free labels for WMO weather codes. Codes not listed here fall
# back to a generic "Weather" label.
WEATHER_LABELS = {
    0: "Clear",
    1: "Mainly Clear",
    2: "Partly Cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Fog",
    51: "Drizzle",
    53: "Drizzle",
    55: "Drizzle",
    56: "Freezing Drizzle",
    57: "Freezing Drizzle",
    61: "Rain",
    63: "Rain",
    65: "Rain",
    66: "Freezing Rain",
    67: "Freezing Rain",
    71: "Snow",
    73: "Snow",
    75: "Snow",
    77: "Snow Grains",
    80: "Showers",
    81: "Showers",
    82: "Showers",
    85: "Snow Showers",
    86: "Snow Showers",
    95: "Thunderstorm",
    96: "Thunderstorm",
    99: "Thunderstorm",
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

    return render.Root(
        child = render.Column(
            children = [
                header_widget(city, data),
                body_widget(data),
            ],
        ),
    )

def fallback():
    return render.Root(
        child = render.Box(
            width = 64,
            height = 32,
            color = "#000000",
            child = render.Text(FALLBACK_TEXT, color = "#ffffff", font = FONT_SMALL),
        ),
    )

def header_widget(city, data):
    current = data.get("current")
    status = weather_label(current.get("weather_code"))
    temp = format_temp(current.get("temperature_2m"))

    return render.Box(
        width = 64,
        height = HEADER_HEIGHT,
        color = "#333333",
        child = render.Column(
            main_align = "space_between",
            cross_align = "start",
            children = [
                render.Row(
                    main_align = "space_between",
                    cross_align = "center",
                    children = [
                        render.Text(city, color = "#ffffff", font = FONT_SMALL),
                        render.Text(temp, color = "#ffffff", font = FONT_LARGE),
                    ],
                ),
                render.Text(status, color = "#aaaaaa", font = FONT_SMALL),
            ],
        ),
    )

def body_widget(data):
    daily = data.get("daily")
    codes = daily.get("weather_code")
    highs = daily.get("temperature_2m_max")
    lows = daily.get("temperature_2m_min")
    precip = daily.get("precipitation_probability_max")
    dates = daily.get("time")

    rows = []
    for i in range(0, 3):
        if i >= len(dates):
            break
        rows.append(day_row(dates[i], codes[i], highs[i], lows[i], precip[i]))

    if len(rows) == 0:
        rows.append(render.Text(FALLBACK_TEXT, color = "#ffffff", font = FONT_SMALL))

    return render.Box(
        width = 64,
        height = BODY_HEIGHT,
        color = "#000000",
        child = render.Column(
            main_align = "space_between",
            cross_align = "start",
            children = rows,
        ),
    )

def day_row(date, code, high, low, precip):
    weekday = weekday_label(date)
    label = weather_label(code)
    hi = format_temp(high)
    lo = format_temp(low)

    # "Mon 27/22" plus a precip suffix when it is meaningful.
    text = "%s %s/%s" % (weekday, hi, lo)
    if precip != None and precip > 0:
        text = "%s %d%%" % (text, int(precip))

    return render.Row(
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Text(text, color = "#ffffff", font = FONT_SMALL),
            render.Text(label, color = "#aaaaaa", font = FONT_SMALL),
        ],
    )

def weekday_label(date):
    # daily.time entries are ISO dates like "2026-08-18" in the local timezone
    # (timezone=auto). Parse and format as a short weekday.
    t = time.parse_time(date, "2006-01-02")
    return t.format("Mon")

def weather_label(code):
    if code == None:
        return "Weather"
    return WEATHER_LABELS.get(int(code), "Weather")

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
