load("http.star", "http")
load("re.star", "re")
load("render.star", "render")
load("schema.star", "schema")
load("xpath.star", "xpath")

# Cache the feed for 15 minutes to avoid hammering the server.
CACHE_TTL_SECONDS = 900

# Default example feed requested by the user.
DEFAULT_FEED_URL = "https://feeds.bbci.co.uk/news/rss.xml"

# Fallback text shown when the feed cannot be fetched or is empty.
FALLBACK_TEXT = "No feed available"

# Font used when the user has not selected one (or selects "Default").
DEFAULT_FONT = "tom-thumb"
FONT_DEFAULT = "default"

# Default header / text colors.
DEFAULT_HEADER_TEXT = "RSS"
DEFAULT_HEADER_COLOR = "#ffffff"
DEFAULT_HEADER_BG_COLOR = "#333333"
DEFAULT_TITLE_COLOR = "#ffffff"
DEFAULT_CONTENT_COLOR = "#aaaaaa"

# Default number of items to display.
DEFAULT_ARTICLE_COUNT = "3"

# Header occupies the top 8 rows; the body scrolls in the remaining 24.
HEADER_HEIGHT = 8
BODY_HEIGHT = 24

def main(config):
    feed_url = config.get("feed_url", DEFAULT_FEED_URL)
    header_text = config.get("header_text", DEFAULT_HEADER_TEXT)
    header_font = resolve_font(config.get("header_font"))
    header_color = config.get("header_color", DEFAULT_HEADER_COLOR)
    header_bg_color = config.get("header_bg_color", DEFAULT_HEADER_BG_COLOR)
    article_count = int(config.get("article_count", DEFAULT_ARTICLE_COUNT))
    title_font = resolve_font(config.get("title_font"))
    title_color = config.get("title_color", DEFAULT_TITLE_COLOR)
    content_font = resolve_font(config.get("content_font"))
    content_color = config.get("content_color", DEFAULT_CONTENT_COLOR)

    articles = fetch_articles(feed_url, article_count)

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Column(
            children = [
                render.Box(
                    width = 64,
                    height = HEADER_HEIGHT,
                    color = header_bg_color,
                    child = render.Text(header_text, color = header_color, font = header_font),
                ),
                render.Marquee(
                    height = BODY_HEIGHT,
                    scroll_direction = "vertical",
                    offset_start = BODY_HEIGHT,
                    child = render.Column(
                        main_align = "space_between",
                        children = render_articles(articles, title_font, title_color, content_font, content_color),
                    ),
                ),
            ],
        ),
    )

def resolve_font(font):
    if not font or font == FONT_DEFAULT:
        return DEFAULT_FONT
    return font

def render_articles(articles, title_font, title_color, content_font, content_color):
    widgets = []
    for article in articles:
        title = article[0]
        content = article[1]
        widgets.append(render.WrappedText(title, color = title_color, font = title_font))
        if content != "":
            widgets.append(render.WrappedText(content, color = content_color, font = content_font))
        widgets.append(render.Box(width = 64, height = 4, color = "#000000"))
    return widgets

def fetch_articles(feed_url, article_count):
    # Guard against an empty/whitespace URL.
    if feed_url == None or feed_url.strip() == "":
        return [(FALLBACK_TEXT, "")]

    res = http.get(url = feed_url, ttl_seconds = CACHE_TTL_SECONDS)
    if res.status_code != 200:
        return [(FALLBACK_TEXT, "")]

    doc = xpath.loads(res.body())
    articles = []
    for i in range(1, article_count + 1):
        title = doc.query("//item[%s]/title" % str(i))
        if title == None or title.strip() == "":
            break
        desc = doc.query("//item[%s]/description" % str(i))
        content = to_plain_text(desc) if desc != None else ""
        articles.append((to_plain_text(title), content))

    if len(articles) == 0:
        return [(FALLBACK_TEXT, "")]

    return articles

def to_plain_text(text):
    # Convert a description/title into displayable plain text.
    #
    # The XML parser already decodes the outer XML entities, so a Google News
    # description arrives here as literal HTML markup (e.g. "<ol><li><a ...>")
    # with HTML entities like &nbsp; still present. render.Text does not
    # interpret HTML, so we must NOT re-escape the final string; instead we
    # decode remaining entities and strip the markup so only readable text is
    # passed to render.Text.
    if text == None:
        return ""
    text = decode_entities(text)

    # Turn block/list/line-break closing tags into a space so adjacent items
    # don't run together, then remove all remaining tags and attributes.
    text = re.sub(r"</(li|ol|ul|p|div|tr|h[1-6]|br)>", " ", text)
    text = re.sub(r"<[^>]*>", "", text)

    # Collapse runs of whitespace (incl. newlines from markup) into single spaces.
    return re.sub(r"\s+", " ", text).strip()

def decode_entities(text):
    # Decode common HTML/XML entities. The XML parser already decoded the outer
    # XML entities, so these are the HTML entities that remain inside CDATA or
    # escaped HTML fragments. Decoding is idempotent for already-decoded text.
    text = text.replace("&nbsp;", " ")
    text = text.replace("&amp;", "&")
    text = text.replace("&lt;", "<")
    text = text.replace("&gt;", ">")
    text = text.replace("&quot;", "\"")
    text = text.replace("&#39;", "'")
    text = text.replace("&apos;", "'")
    text = text.replace("&hellip;", "\u2026")
    text = text.replace("&mdash;", "\u2014")
    text = decode_numeric_entities(text)
    return text

def decode_numeric_entities(text):
    # Decode decimal (&#65;) and hex (&#x42;) numeric entities. re.sub does not
    # support function replacers in this pixlet build, so find each entity and
    # replace it manually. re.findall returns the full match (e.g. "&#65;").
    for ent in re.findall(r"&#\d+;", text):
        code = int(ent[2:-1])
        text = text.replace(ent, chr(code))
    for ent in re.findall(r"&#x[0-9a-fA-F]+;", text):
        code = int(ent[3:-1], 16)
        text = text.replace(ent, chr(code))
    return text

def get_schema():
    fonts = [
        schema.Option(display = "Default", value = FONT_DEFAULT),
    ]
    fonts.extend([
        schema.Option(display = key, value = value)
        for key, value in sorted(render.fonts.items())
    ])

    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "feed_url",
                name = "RSS Feed URL",
                desc = "The URL of the RSS feed to display.",
                icon = "rss",
                default = DEFAULT_FEED_URL,
            ),
            schema.Text(
                id = "header_text",
                name = "Header Text",
                desc = "Text shown in the header bar.",
                icon = "font",
                default = DEFAULT_HEADER_TEXT,
            ),
            schema.Dropdown(
                id = "header_font",
                name = "Header Font",
                desc = "Font of the header text.",
                icon = "font",
                options = fonts,
                default = FONT_DEFAULT,
            ),
            schema.Color(
                id = "header_color",
                name = "Header Color",
                desc = "Color of the header text.",
                icon = "palette",
                default = DEFAULT_HEADER_COLOR,
            ),
            schema.Color(
                id = "header_bg_color",
                name = "Header Background",
                desc = "Background color of the header bar.",
                icon = "palette",
                default = DEFAULT_HEADER_BG_COLOR,
            ),
            schema.Dropdown(
                id = "article_count",
                name = "Items to Show",
                desc = "Number of latest items to display.",
                icon = "hashtag",
                default = DEFAULT_ARTICLE_COUNT,
                options = [
                    schema.Option(display = "1", value = "1"),
                    schema.Option(display = "2", value = "2"),
                    schema.Option(display = "3", value = "3"),
                    schema.Option(display = "4", value = "4"),
                    schema.Option(display = "5", value = "5"),
                ],
            ),
            schema.Dropdown(
                id = "title_font",
                name = "Title Font",
                desc = "Font of the article titles.",
                icon = "font",
                options = fonts,
                default = FONT_DEFAULT,
            ),
            schema.Color(
                id = "title_color",
                name = "Title Color",
                desc = "Color of the article titles.",
                icon = "palette",
                default = DEFAULT_TITLE_COLOR,
            ),
            schema.Dropdown(
                id = "content_font",
                name = "Content Font",
                desc = "Font of the article content.",
                icon = "font",
                options = fonts,
                default = FONT_DEFAULT,
            ),
            schema.Color(
                id = "content_color",
                name = "Content Color",
                desc = "Color of the article content.",
                icon = "palette",
                default = DEFAULT_CONTENT_COLOR,
            ),
        ],
    )
