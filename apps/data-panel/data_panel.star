load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

MAX_ROWS = 3
MAX_SEGMENTS = 8
MAX_TEXT = 48
MAX_BODY = 4096
DEFAULT_FONT = "tom-thumb"
FONT_DEFAULT = "default"
ERROR_TEXT = "NO SIGNAL / BACK SOON"

def main(config):
    color = config.get("default_color", "#FFFFFF")
    align = config.get("alignment", "left")
    overflow = config.get("overflow", "clip")
    font = resolve_font(config.get("font"))
    if font not in render.fonts:
        return render.Root(child = render_error("FONT NOT FOUND"))
    age_setting = config.get("stale_age_seconds", "900")
    stale_age = int(age_setting) if digits(age_setting) and len(age_setting) <= 7 else 900
    rows, warning, failed = fetch_rows(config.get("url", ""), color, stale_age)
    if failed:
        return render.Root(child = render_error())
    children = []
    total_height = 0
    for row in rows:
        child, height, too_wide = render_row(row, align, overflow, font)
        if too_wide:
            return render.Root(child = render_error("ROW TOO WIDE"))
        total_height += height
        children.append(child)
    if total_height > 32:
        return render.Root(child = render_error("FONT TOO BIG"))
    panel = render.Column(main_align = "center", children = children)
    if warning:
        # With three rows, reserve the bottom two pixels for a stale stripe;
        # a fourth text row would cover the third data row.
        badge = render.Box(width = 64, height = 2, color = "#FFAA00") if len(rows) == 3 else render.Box(width = 27, height = 6, color = "#332200", child = render.Text("STALE", color = "#FFAA00", font = "tom-thumb"))
        panel = render.Stack(children = [panel, render.Box(width = 64, height = 32, child = render.Column(main_align = "end", cross_align = "end", expanded = True, children = [badge]))])
    return render.Root(child = panel)

def fetch_rows(url, default_color, stale_age):
    if not url:
        return ([], False, True)
    response = http.get(url = url, ttl_seconds = 60)
    if response.status_code != 200:
        return ([], False, True)
    body = response.body()
    if len(body) > MAX_BODY or len(body) == 0:
        return ([], False, True)

    # JSON decoding errors in this runtime abort the render; producers must
    # supply syntactically valid JSON. Semantic errors below are recoverable.
    data = response.json()
    if type(data) != "dict" or data.get("version") != 1 or type(data.get("lines")) != "list":
        return ([], False, True)
    lines = data["lines"]
    if len(lines) < 1 or len(lines) > MAX_ROWS:
        return ([], False, True)
    updated = data.get("updated_at")
    if updated != None and not valid_iso8601(updated):
        return ([], False, True)
    rows = []
    for line in lines:
        row = validate_line(line, default_color)
        if row == None:
            return ([], False, True)
        rows.append(row)
    stale = updated != None and time.now() - time.parse_time(updated) > time.parse_duration(str(stale_age) + "s")
    return (rows, stale, False)

def validate_line(line, default_color):
    if type(line) == "string":
        if len(line) > MAX_TEXT or not valid_text(line):
            return None
        return {"parts": [segment(line, default_color)], "split": False}
    if type(line) != "dict":
        return None
    if "text" in line:
        if "segments" in line or "left" in line or "right" in line or type(line["text"]) != "string" or len(line["text"]) > MAX_TEXT or not valid_text(line["text"]):
            return None
        return {"parts": [segment(line["text"], default_color)], "split": False}
    has_parts = "segments" in line
    has_split = "left" in line or "right" in line
    if has_parts == has_split:
        return None
    if has_split:
        for key in line:
            if key not in ["left", "right"]:
                return None
        if type(line.get("left", [])) != "list" or type(line.get("right", [])) != "list":
            return None
        groups = []
        for group in [line.get("left", []), line.get("right", [])]:
            if len(group) > MAX_SEGMENTS:
                return None
            parsed, total = [], 0
            for part in group:
                if type(part) != "dict":
                    return None
                for key in part:
                    if key not in ["text", "color"]:
                        return None
                if type(part.get("text")) != "string" or not valid_text(part["text"]):
                    return None
                total += len(part["text"])
                color = part.get("color", default_color)
                if total > MAX_TEXT or not valid_color(color):
                    return None
                parsed.append(segment(part["text"], color))
            groups.append(parsed)
        if len(groups[0]) + len(groups[1]) == 0:
            return None
        return {"left": groups[0], "right": groups[1], "split": True}
    parts = line.get("segments")
    if "text" in line or type(parts) != "list" or len(parts) < 1 or len(parts) > MAX_SEGMENTS:
        return None
    result = []
    total = 0
    for part in parts:
        if type(part) != "dict" or type(part.get("text")) != "string":
            return None
        text = part["text"]
        if not valid_text(text):
            return None
        total += len(text)
        if total > MAX_TEXT:
            return None
        part_color = part.get("color", default_color)
        if not valid_color(part_color):
            return None
        result.append(segment(text, part_color))
    return {"parts": result, "split": False}

def segment(text, color):
    return {"text": text, "color": color}

def simple_row(text, color):
    return [segment(text, color)]

def render_row(row, align, overflow, font):
    if row["split"]:
        left, right = row["left"], row["right"]
        left_width, left_height = measure_group(left, font)
        right_width, right_height = measure_group(right, font)
        height = max(10, left_height, right_height)
        if not left_width and not right_width:
            return (None, height, True)
        if left_width + right_width + (1 if left_width and right_width else 0) > 64:
            return (None, height, True)
        children = []
        if left_width:
            children.append(render.Box(width = left_width, child = render.Row(children = [render.Text(p["text"], color = p["color"], font = font) for p in left])))
        if right_width:
            children.append(render.Box(width = right_width, child = render.Row(children = [render.Text(p["text"], color = p["color"], font = font) for p in right])))

        # Box centers its child; the expanded row must distribute the two
        # measured groups across the full 64px width instead of using padding.
        placement = "space_between" if left_width and right_width else ("end" if right_width else "start")
        return (render.Box(width = 64, height = height, child = render.Row(main_align = placement, expanded = True, children = children)), height, False)
    parts = row["parts"]
    widgets = []
    height = 10
    for part in parts:
        widget = render.Text(part["text"], color = part["color"], font = font)
        height = max(height, widget.size()[1])
        widgets.append(widget)
    content = render.Row(children = widgets, main_align = {"left": "start", "center": "center", "right": "end"}.get(align, "start"), expanded = overflow != "scroll")
    if overflow == "scroll":
        content = render.Marquee(width = 64, scroll_direction = "horizontal", offset_start = 0, offset_end = 0, align = {"left": "start", "center": "center", "right": "end"}.get(align, "start"), child = content)
    return (render.Box(width = 64, height = height, child = content), height, False)

def measure_group(parts, font):
    width, height = 0, 10
    for part in parts:
        size = render.Text(part["text"], color = part["color"], font = font).size()
        width += size[0]
        height = max(height, size[1])
    return (width, height)

def resolve_font(value):
    if not value or value == FONT_DEFAULT:
        return DEFAULT_FONT
    return value

def render_error(message = ERROR_TEXT):
    # Deliberate high-contrast, quiet status card; use compact font regardless
    # of the selected font so invalid sizing can never clip this message.
    lines = [message] if message != ERROR_TEXT else ["NO SIGNAL", "BACK SOON"]
    text = [render.Text(line, color = "#8FD3C8", font = DEFAULT_FONT) for line in lines]
    return render.Box(width = 64, height = 32, color = "#101820", child = render.Column(main_align = "center", children = text))

def valid_color(value):
    if type(value) != "string" or len(value) != 7 or value[0] != "#":
        return False
    for i in range(1, 7):
        ch = value[i]
        if ch not in "0123456789abcdefABCDEF":
            return False
    return True

def valid_text(value):
    for i in range(len(value)):
        if value[i] in "\n\r\t":
            return False
    return True

def digits(value):
    if type(value) != "string" or not value:
        return False
    for i in range(len(value)):
        if value[i] not in "0123456789":
            return False
    return True

def valid_iso8601(value):
    if type(value) != "string" or len(value) < 20 or value[4] != "-" or value[7] != "-" or value[10] != "T" or value[13] != ":" or value[16] != ":":
        return False
    for part in [value[:4], value[5:7], value[8:10], value[11:13], value[14:16], value[17:19]]:
        if not digits(part):
            return False
    year, month, day = int(value[:4]), int(value[5:7]), int(value[8:10])
    if year < 1 or month < 1 or month > 12 or int(value[11:13]) > 23 or int(value[14:16]) > 59 or int(value[17:19]) > 59:
        return False
    days = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if day < 1 or day > days[month - 1]:
        return False
    rest = value[19:]
    if rest.startswith("."):
        i = 1
        for position in range(1, len(rest)):
            if rest[position] not in "0123456789":
                break
            i = position + 1
        if i == 1:
            return False
        rest = rest[i:]
    if rest == "Z":
        return True
    return len(rest) == 6 and rest[0] in "+-" and rest[3] == ":" and digits(rest[1:3]) and digits(rest[4:6]) and int(rest[1:3]) <= 23 and int(rest[4:6]) <= 59

def get_schema():
    return schema.Schema(version = "1", fields = [
        schema.Text(id = "url", name = "JSON URL", desc = "URL returning the version 1 data-panel JSON document.", icon = "link", default = ""),
        schema.Color(id = "default_color", name = "Default color", desc = "Color for uncolored text segments.", icon = "palette", default = "#FFFFFF"),
        schema.Dropdown(id = "alignment", name = "Alignment", desc = "Horizontal alignment for each row.", icon = "alignLeft", default = "left", options = [schema.Option(display = "Left", value = "left"), schema.Option(display = "Center", value = "center"), schema.Option(display = "Right", value = "right")]),
        schema.Dropdown(id = "overflow", name = "Overflow", desc = "Clip row at screen edge or scroll its joined segments.", icon = "arrowsLeftRight", default = "clip", options = [schema.Option(display = "Clip", value = "clip"), schema.Option(display = "Scroll", value = "scroll")]),
        schema.Dropdown(id = "font", name = "Font", desc = "Server-registered Pixlet font. Rows too tall for 32 pixels show FONT TOO BIG.", icon = "font", default = DEFAULT_FONT, options = [schema.Option(display = key, value = value) for key, value in sorted(render.fonts.items())]),
        schema.Text(id = "stale_age_seconds", name = "Stale age (seconds)", desc = "Mark source timestamps older than this threshold; absent timestamps have unknown age.", icon = "clock", default = "900"),
    ])
