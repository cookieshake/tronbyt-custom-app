load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

# Cache the calendar for 10 minutes (matches the recommended render interval).
CACHE_TTL_SECONDS = 600

# Default example calendar URL (a public Google Calendar iCal feed).
DEFAULT_CALENDAR_URL = "https://calendar.google.com/calendar/ical/en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics"

# Fallback text shown when the calendar cannot be fetched or has no events.
FALLBACK_TEXT = "No events"

# Font used when the user has not selected one (or selects "Default").
DEFAULT_FONT = "tom-thumb"
FONT_DEFAULT = "default"

# Default text / background colors.
DEFAULT_TEXT_COLOR = "#ffffff"
DEFAULT_DIM_COLOR = "#aaaaaa"
DEFAULT_BG_COLOR = "#000000"

# Default number of upcoming events to display.
DEFAULT_EVENT_COUNT = "3"

# Default header label shown at the top of the app.
DEFAULT_HEADER_TEXT = "UPCOMING"

# Default display timezone. iCal feeds may carry UTC (trailing Z), a TZID, or
# floating (no zone) values. We interpret them in this zone for display and
# filtering. Asia/Seoul is the author's locale; users can change it in config.
DEFAULT_TZ = "Asia/Seoul"

# IANA zones we are willing to pass to time.time(location=...). Starlark has no
# try/except, so we only use names we know are valid to avoid a crash on a bad
# TZID from a feed. Unknown TZIDs fall back to DEFAULT_TZ.
KNOWN_ZONES = [
    "UTC",
    "Asia/Seoul",
    "Asia/Tokyo",
    "Asia/Shanghai",
    "Asia/Hong_Kong",
    "Asia/Taipei",
    "Asia/Singapore",
    "Asia/Manila",
    "Asia/Bangkok",
    "Asia/Jakarta",
    "Asia/Kolkata",
    "Asia/Dubai",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Europe/Moscow",
    "America/New_York",
    "America/Chicago",
    "America/Denver",
    "America/Phoenix",
    "America/Los_Angeles",
    "America/Toronto",
    "America/Sao_Paulo",
    "Africa/Cairo",
    "Africa/Johannesburg",
    "Australia/Sydney",
    "Australia/Melbourne",
    "Pacific/Auckland",
]

# Upper bound on recurrence expansion to avoid unbounded loops on malformed
# RRULEs (e.g. a DAILY rule with no COUNT/UNTIL).
MAX_OCCURRENCES = 200

# Header occupies the top 7 rows; the body scrolls in the remaining 25.
HEADER_HEIGHT = 7
BODY_HEIGHT = 25

def main(config):
    calendar_url = config.get("calendar_url", DEFAULT_CALENDAR_URL)
    font = resolve_font(config.get("font"))
    text_color = config.get("text_color", DEFAULT_TEXT_COLOR)
    dim_color = config.get("dim_color", DEFAULT_DIM_COLOR)
    bg_color = config.get("bg_color", DEFAULT_BG_COLOR)
    event_count = int(config.get("event_count", DEFAULT_EVENT_COUNT))
    tz = config.get("timezone", DEFAULT_TZ)
    header_text = config.get("header_text", DEFAULT_HEADER_TEXT)

    events = fetch_events(calendar_url, event_count, tz)

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Column(
            children = [
                render.Box(
                    width = 64,
                    height = HEADER_HEIGHT,
                    color = bg_color,
                    # Render the configurable header label with the fixed small
                    # DEFAULT_FONT rather than the user-selected body font. Font
                    # metrics are unavailable at runtime, so this prevents
                    # clipping when a Korean-capable/tall font is selected.
                    child = render.Text(header_text, color = text_color, font = DEFAULT_FONT),
                ),
                render.Box(
                    width = 64,
                    height = BODY_HEIGHT,
                    color = bg_color,
                    child = render.Marquee(
                        height = BODY_HEIGHT,
                        scroll_direction = "vertical",
                        offset_start = BODY_HEIGHT,
                        offset_end = BODY_HEIGHT,
                        child = render.Column(
                            main_align = "space_between",
                            children = render_events(events, font, text_color, dim_color, bg_color),
                        ),
                    ),
                ),
            ],
        ),
    )

def resolve_font(font):
    if not font or font == FONT_DEFAULT:
        return DEFAULT_FONT
    return font

def render_events(events, font, text_color, dim_color, bg_color):
    widgets = []
    for event in events:
        summary = event[0]
        when = event[1]
        widgets.append(render.WrappedText(summary, color = text_color, font = font))
        if when != "":
            widgets.append(render.WrappedText(when, color = dim_color, font = font))
        widgets.append(render.Box(width = 64, height = 4, color = bg_color))
    return widgets

def fetch_events(calendar_url, event_count, tz):
    # Guard against an empty/whitespace URL.
    if calendar_url == None or calendar_url.strip() == "":
        return [(FALLBACK_TEXT, "")]

    res = http.get(url = calendar_url, ttl_seconds = CACHE_TTL_SECONDS)
    if res.status_code != 200:
        return [(FALLBACK_TEXT, "")]

    body = res.body()
    if body == None or body.strip() == "":
        return [(FALLBACK_TEXT, "")]

    events = parse_ical(body)
    if len(events) == 0:
        return [(FALLBACK_TEXT, "")]

    now = time.now()
    today = (now.year, now.month, now.day)

    # Expand each event to its next upcoming occurrence (recurring events are
    # expanded from their series DTSTART, so a past DTSTART does not hide future
    # occurrences). All-day events stay visible through their end day.
    upcoming = []
    for ev in events:
        occ = next_occurrence(ev, now, today, tz)
        if occ != None:
            upcoming.append(occ)

    if len(upcoming) == 0:
        return [(FALLBACK_TEXT, "")]

    upcoming = sorted(upcoming, key = lambda o: o[0].unix)
    upcoming = upcoming[:event_count]

    # Build display tuples: (summary, when-string).
    out = []
    for t, all_day, summary in upcoming:
        out.append((summary, format_when(t, all_day)))
    return out

def parse_ical(body):
    # Unfold continuation lines: a line beginning with a space or tab is a
    # continuation of the previous line.
    lines = []
    for raw in body.split("\n"):
        line = raw.rstrip("\r")
        if line.startswith(" ") or line.startswith("\t"):
            if len(lines) > 0:
                lines[-1] = lines[-1] + line[1:]
        else:
            lines.append(line)

    # Collect VEVENT blocks. Property names may carry parameters (e.g.
    # "DTSTART;VALUE=DATE" or "DTSTART;TZID=Asia/Seoul"); we store the base name
    # and the parsed parameters separately so the value is parsed correctly.
    events = []
    current = None
    for line in lines:
        if line == "BEGIN:VEVENT":
            current = {}
        elif line == "END:VEVENT":
            if current != None:
                events.append(current)
            current = None
        elif current != None:
            name, _, value = line.partition(":")
            base, params = split_prop(name)
            current[base] = value
            current[base + "_PARAMS"] = params

    # Parse each event, skipping cancelled events.
    parsed = []
    for ev in events:
        status = ev.get("STATUS", "").upper()
        if status == "CANCELLED":
            continue
        start_raw = ev.get("DTSTART")
        if start_raw == None:
            continue
        start = parse_dt(start_raw, ev.get("DTSTART_PARAMS", {}))
        if start == None:
            continue
        summary = unescape(ev.get("SUMMARY", ""))
        end = None
        end_raw = ev.get("DTEND")
        if end_raw != None:
            end = parse_dt(end_raw, ev.get("DTEND_PARAMS", {}))
        rrule = None
        rrule_raw = ev.get("RRULE")
        if rrule_raw != None:
            rrule = parse_rrule(rrule_raw)
        parsed.append({
            "summary": summary,
            "start": start["ts"],
            "start_tz": start["tz"],
            "all_day": start["all_day"],
            "end": end["ts"] if end != None else None,
            "rrule": rrule,
        })

    return parsed

def split_prop(name):
    # Split "DTSTART;VALUE=DATE;TZID=Asia/Seoul" into base "DTSTART" and a
    # params dict {"VALUE": "DATE", "TZID": "Asia/Seoul"}.
    base, _, params_str = name.partition(";")
    params = {}
    if params_str != "":
        for p in params_str.split(";"):
            k, _, v = p.partition("=")
            params[k.strip().upper()] = v.strip()
    return base, params

def parse_dt(value, params):
    # Parse a DTSTART/DTEND value into a (ts, tz, all_day) descriptor.
    # all_day is True only when the value is explicitly a DATE (VALUE=DATE or a
    # date-only YYYYMMDD). A timed value at 00:00 is NOT treated as all-day.
    v = value.strip()
    is_utc = v.endswith("Z")
    if is_utc:
        v = v[:-1]
    tzid = params.get("TZID")

    if "T" in v:
        date_part, _, time_part = v.partition("T")
        if len(date_part) != 8 or len(time_part) < 6:
            return None
        year = int(date_part[0:4])
        month = int(date_part[4:6])
        day = int(date_part[6:8])
        hour = int(time_part[0:2])
        minute = int(time_part[2:4])
        tz = "UTC" if is_utc else (tzid if tzid != None else "floating")
        return {"ts": (year, month, day, hour, minute), "tz": tz, "all_day": False}

    if len(v) == 8:
        year = int(v[0:4])
        month = int(v[4:6])
        day = int(v[6:8])
        tz = "UTC" if is_utc else (tzid if tzid != None else "floating")
        return {"ts": (year, month, day, 0, 0), "tz": tz, "all_day": True}
    return None

def parse_rrule(s):
    # Parse a minimal RRULE: FREQ, INTERVAL, COUNT, UNTIL. Other keys are
    # ignored (see next_occurrence for the safe fallback on unsupported FREQ).
    r = {"freq": None, "interval": 1, "count": None, "until": None}
    for part in s.split(";"):
        k, _, v = part.partition("=")
        k = k.strip().upper()
        v = v.strip()
        if k == "FREQ":
            r["freq"] = v
        elif k == "INTERVAL":
            r["interval"] = int(v)
        elif k == "COUNT":
            r["count"] = int(v)
        elif k == "UNTIL":
            r["until"] = parse_until(v)
    return r

def parse_until(v):
    # UNTIL may be a date (YYYYMMDD) or date-time (YYYYMMDDTHHMMSS[Z]); we only
    # need the day for comparison.
    v = v.strip()
    if v.endswith("Z"):
        v = v[:-1]
    if "T" in v:
        v = v.partition("T")[0]
    if len(v) == 8:
        return (int(v[0:4]), int(v[4:6]), int(v[6:8]))
    return None

def next_occurrence(ev, now, today, tz):
    # Return the next upcoming occurrence as (time_obj, all_day, summary), or
    # None if the event has no upcoming occurrence.
    start = ev["start"]
    all_day = ev["all_day"]
    rrule = ev["rrule"]

    if rrule == None:
        return single_occurrence(ev, now, today, tz)

    freq = rrule["freq"]
    interval = rrule["interval"]
    count = rrule["count"]
    until = rrule["until"]

    if freq == "DAILY":
        step = interval
    elif freq == "WEEKLY":
        # Simple weekly expansion on the DTSTART weekday. BYDAY/BYDAY-specific
        # rules are not expanded precisely; see the limitation note in the
        # manifest. This still surfaces future occurrences rather than hiding
        # the whole series.
        step = interval * 7
    else:
        # Unsupported FREQ (MONTHLY/YEARLY/etc.): fall back to showing the
        # series DTSTART if it is still upcoming, so we never hide a recurring
        # event entirely.
        return single_occurrence(ev, now, today, tz)

    occ = start
    for idx in range(MAX_OCCURRENCES):
        if count != None and idx >= count:
            break
        if until != None and day_cmp((occ[0], occ[1], occ[2]), until) > 0:
            break
        t = to_time(occ, ev["start_tz"], tz)
        if all_day:
            if day_cmp((occ[0], occ[1], occ[2]), today) >= 0:
                return (t, all_day, ev["summary"])
        elif t.unix > now.unix:
            return (t, all_day, ev["summary"])
        occ = add_days(occ, step)
    return None

def single_occurrence(ev, now, today, tz):
    # Non-recurring event (or unsupported recurrence fallback).
    start = ev["start"]
    all_day = ev["all_day"]
    t = to_time(start, ev["start_tz"], tz)
    if all_day:
        # Keep all-day events visible through their end day (or start day if no
        # DTEND), so today's all-day event is not dropped.
        end_day = ev["end"] if ev["end"] != None else start
        if day_cmp((end_day[0], end_day[1], end_day[2]), today) < 0:
            return None
        return (t, all_day, ev["summary"])
    if t.unix <= now.unix:
        return None
    return (t, all_day, ev["summary"])

def to_time(ts, tz, default_tz):
    # Build a time value in a safe location. Unknown TZIDs fall back to the
    # configured default so a bad feed value cannot crash the app.
    y, m, d, h, min = ts
    loc = safe_location(tz, default_tz)
    return time.time(year = y, month = m, day = d, hour = h, minute = min, second = 0, location = loc)

def safe_location(tz, default_tz):
    if tz in KNOWN_ZONES:
        return tz
    return default_tz

def format_when(t, all_day):
    # Format a time value (already in the display timezone) as a short readable
    # string, e.g. "08/22 14:30" or "08/22" for all-day events.
    if all_day:
        return "%s/%s" % (pad2(t.month), pad2(t.day))
    return "%s/%s %s:%s" % (pad2(t.month), pad2(t.day), pad2(t.hour), pad2(t.minute))

def pad2(n):
    # Zero-pad a number to two digits (e.g. 5 -> "05").
    if n < 10:
        return "0%d" % n
    return "%d" % n

def unescape(text):
    # Decode common iCal escaped sequences: \\, \;, \,, \N, \n.
    text = text.replace("\\n", " ")
    text = text.replace("\\N", " ")
    text = text.replace("\\,", ",")
    text = text.replace("\\;", ";")
    text = text.replace("\\\\", "\\")
    return text

def add_days(ts, days):
    # Add days to a (y, m, d, h, min) tuple, handling month/year rollover.
    y, m, d, h, min = ts
    for _ in range(days):
        dim = days_in_month(y, m)
        if d < dim:
            d = d + 1
        else:
            d = 1
            m = m + 1
            if m > 12:
                m = 1
                y = y + 1
    return (y, m, d, h, min)

def days_in_month(y, m):
    if m in [1, 3, 5, 7, 8, 10, 12]:
        return 31
    if m in [4, 6, 9, 11]:
        return 30
    if is_leap(y):
        return 29
    return 28

def is_leap(y):
    if y % 400 == 0:
        return True
    if y % 100 == 0:
        return False
    return y % 4 == 0

def day_cmp(a, b):
    # Compare two (y, m, d) tuples: -1, 0, or 1.
    if a[0] < b[0]:
        return -1
    if a[0] > b[0]:
        return 1
    if a[1] < b[1]:
        return -1
    if a[1] > b[1]:
        return 1
    if a[2] < b[2]:
        return -1
    if a[2] > b[2]:
        return 1
    return 0

def get_schema():
    fonts = [
        schema.Option(display = "Default", value = FONT_DEFAULT),
    ]
    fonts.extend([
        schema.Option(display = key, value = value)
        for key, value in sorted(render.fonts.items())
    ])

    tz_options = [
        schema.Option(display = z, value = z)
        for z in KNOWN_ZONES
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "header_text",
                name = "Header Text",
                desc = "The label shown at the top of the app.",
                icon = "heading",
                default = DEFAULT_HEADER_TEXT,
            ),
            schema.Text(
                id = "calendar_url",
                name = "Calendar iCal URL",
                desc = "The public or secret Google Calendar iCal URL to display.",
                icon = "calendar",
                default = DEFAULT_CALENDAR_URL,
            ),
            schema.Dropdown(
                id = "timezone",
                name = "Timezone",
                desc = "Timezone used to interpret and display event times. UTC and TZID values are converted to this zone.",
                icon = "globe",
                default = DEFAULT_TZ,
                options = tz_options,
            ),
            schema.Dropdown(
                id = "font",
                name = "Font",
                desc = "Font of the event text (use a Korean-compatible font for Hangul).",
                icon = "font",
                options = fonts,
                default = FONT_DEFAULT,
            ),
            schema.Color(
                id = "text_color",
                name = "Text Color",
                desc = "Color of the event titles.",
                icon = "palette",
                default = DEFAULT_TEXT_COLOR,
            ),
            schema.Color(
                id = "dim_color",
                name = "Dim Color",
                desc = "Color of the event date/time lines.",
                icon = "palette",
                default = DEFAULT_DIM_COLOR,
            ),
            schema.Color(
                id = "bg_color",
                name = "Background",
                desc = "Background color of the app.",
                icon = "palette",
                default = DEFAULT_BG_COLOR,
            ),
            schema.Dropdown(
                id = "event_count",
                name = "Events to Show",
                desc = "Number of upcoming events to display.",
                icon = "hashtag",
                default = DEFAULT_EVENT_COUNT,
                options = [
                    schema.Option(display = "1", value = "1"),
                    schema.Option(display = "2", value = "2"),
                    schema.Option(display = "3", value = "3"),
                    schema.Option(display = "4", value = "4"),
                    schema.Option(display = "5", value = "5"),
                ],
            ),
        ],
    )
