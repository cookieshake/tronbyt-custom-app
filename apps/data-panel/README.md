# Data Panel

Generic 64×32 display of externally formatted JSON. The producer supplies final text and optional per-segment colors; the app does not interpret domains, evaluate expressions, or accept coordinates. The same `.star` renders both `fixtures/feeding.json` and `fixtures/server-status.json`.

## Configuration

- `url`: HTTP(S) GET endpoint. Leave empty to show the intentional `NO SIGNAL / BACK SOON` status image. Use a trusted endpoint; do not place secrets in its URL.
- `default_color`: fallback for segments without a color, default `#FFFFFF`.
- `alignment`: `left`, `center`, or `right`, applied to the **whole row** when it fits. Default `left`.
- `overflow`: `clip` (default) hides text outside 64 pixels; `scroll` moves joined segments together horizontally when wider than 64 pixels. Animation is subject to the host's maximum render duration.
- `font`: dropdown generated at schema evaluation from **all** `render.fonts` registered in that Pixlet runtime; default `tom-thumb`. A saved name no longer registered shows `FONT NOT FOUND`, not a silent fallback. Per-row height is measured with `render.Text(...).size()[1]` for the actual text and selected font (at least 10px), including emoji; rows exceeding 32px together show `FONT TOO BIG` in the compact safe font. This does not infer height from the font name: nonnumeric names such as `Galmuri7` work. For example, 6x10 fits three rows; 10x20 fits one but not three. Tall fonts remain selectable for suitable row counts.

The local Korean Pixlet v0.54.0-korean.2 build used for testing exposes 31 embedded fonts (including Galmuri7/9/11 and dalmoori-8). The production server image's actual registered names have **not** been enumerated in its running process; its revision and pinned Pixlet dependency alone do not prove which user-installed custom names, if any, are available there. The dropdown reads the runtime registry rather than a frozen local list. The approved feeding fixture's second row exceeds 64px in 6x10 and is horizontally clipped with the default `clip` setting; use `scroll` to see all of that row at this size.
- `stale_age_seconds`: source age threshold, default `900`. An absent `updated_at` has **unknown** age, not age zero. Invalid setting falls back to 900.

`manifest.yaml` recommends a 60-second render interval; `http.get(..., ttl_seconds=60)` requests a 60-second HTTP response cache TTL. The host controls actual scheduling and cache lifetime. HTTP caching stores responses, **not validated JSON or per-instance last-known-good data**; a cached response is not evidence of freshness. The source timestamp, never the fetch time, controls the stale indicator.

## JSON contract (version 1)

```json
{"version":1,"updated_at":"2026-10-05T12:00:00Z","lines":[{"segments":[{"text":"FEED ","color":"#AAAAAA"},{"text":"1H20M","color":"#FFFFFF"}]},{"text":"NAS OK"}]}
```

`lines` must contain 1–3 rows. Each row may be a string, `{ "text": "NAS OK" }`, or `{ "segments": [{ "text": "...", "color": "#RRGGBB" }] }`. Segment `color` is optional; it belongs to the segment, not the row. At most eight segments and 48 characters per row are accepted. Tabs and line breaks in display text are rejected. `updated_at`, when supplied, must be a valid RFC3339-style ISO 8601 date-time with `Z` or numeric timezone offset. Old timestamps show a `STALE` badge (one or two rows) or a two-pixel amber bottom stripe (three rows). Missing timestamp has no badge. Future timestamps are not treated as old.

`data-panel.schema.json` is a producer-facing JSON Schema for the basic shape. The runtime also enforces a **combined** 48-character segment-text limit per row, excludes tabs and line breaks, and caps the fetched body; those checks are not fully expressible in that schema. `get_schema()` in `data_panel.star` separately defines the Pixlet **app configuration** fields.

The app checks the **entire** decoded document before displaying any of its rows. Semantically invalid documents, HTTP non-200 responses, empty URL, and post-fetch bodies over 4,096 characters show a deliberate, generic `NO SIGNAL / BACK SOON` image; they do not retain earlier successful rows. Invalid font names show `FONT NOT FOUND` and too-tall row combinations show `FONT TOO BIG`, both rendered with the safe compact font. This is not a pre-download body limit: Pixlet reads the response first and its runtime HTTP limit defaults to 20 MiB (subject to host configuration). In the actual Pixlet/Starlark API, HTTP connection/read failures and JSON syntax errors from `response.json()` raise errors that this app cannot catch: rendering may abort without an image. They are not treated as recoverable and are not promised to display the status image. There is no supported per-instance persistent validated-data API, so last-known-good fallback is **not implemented**. Do not infer that HTTP TTL caching provides it. A later valid response can render normally; this is not LKG recovery. Authentication-header configuration is deliberately omitted because secure handling of configured secrets has not been established.

## Local verification and previews

From the repository root, with `uv` and a local build of the server's Pixlet v0.54.0-korean.2 installed:

```sh
uv run --with pillow python apps/data-panel/tests/render_fixtures.py --pixlet /path/to/korean-pixlet
uv run --with pillow python apps/data-panel/tests/render_fixtures.py --pixlet /path/to/korean-pixlet --preview-dir /Users/cookieshake/.hermes/cache/scratch
```

The test serves only loopback fixtures, renders through the actual Pixlet runtime, checks pixel dimensions/colors/geometry and scroll frames, checks runtime-discovered font choices/default, unregistered-font error, Korean custom glyphs and tall-font guard, and verifies that malformed JSON and transport failure are explicit runtime failures rather than falsely handled errors. The optional preview command writes native 64×32 PNG/WebP and 640×320 nearest-neighbor PNGs for the feeding fixture, status/error image, 6x10 alternative, Galmuri7 custom-font sample, and server-status. The compact `tom-thumb` default keeps the approved three data rows within 32 pixels; actual glyph bounds including `°C` and `%` are tested. Example fixture timestamps are static and will eventually display the stale indicator.
