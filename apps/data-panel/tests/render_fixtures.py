#!/usr/bin/env python3
"""Exercise the real Pixlet renderer with loopback-only HTTP and inspect pixels.

Run with: uv run --with pillow python apps/data-panel/tests/render_fixtures.py
Optional: --preview-dir /path/to/approved/directory
"""
import argparse
import datetime
import http.server
import json
import pathlib
import shutil
import socketserver
import subprocess
import tempfile
import threading
import urllib.parse

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
NOW = datetime.datetime.now(datetime.timezone.utc)
PIXLET = "pixlet"


def document(lines, updated_at=None):
    value = {"version": 1, "lines": lines}
    if updated_at is not None:
        value["updated_at"] = updated_at
    return json.dumps(value).encode()


def stamp(delta):
    return (NOW + delta).isoformat(timespec="seconds").replace("+00:00", "Z")


class Handler(http.server.BaseHTTPRequestHandler):
    routes = {}

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        status, body = self.routes.get(path, (404, b"missing"))
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def pixels(image):
    return list(image.convert("RGB").get_flattened_data())


def lit(image, predicate=lambda rgb: max(rgb) > 70):
    rgb = image.convert("RGB")
    return [(x, y) for y in range(rgb.height) for x in range(rgb.width) if predicate(rgb.getpixel((x, y)))]


def colored(image, channel):
    index = {"red": 0, "green": 1, "blue": 2}[channel]
    return lit(image, lambda p: p[index] > 110 and p[index] > max(p[(index + 1) % 3], p[(index + 2) % 3]) * 1.5)


def check(condition, message):
    assert condition, message
    print("PASS", message)


def render(base, out, name, endpoint, *settings, success=True):
    target = out / (name + ".webp")
    args = [PIXLET, "render", str(ROOT / "data_panel.star"), "url=" + base + "/" + endpoint, *settings, "-o", str(target)]
    result = subprocess.run(args, text=True, capture_output=True, timeout=45)
    if not success:
        check(result.returncode != 0, name + ": expected runtime failure")
        return None, None
    check(result.returncode == 0 and target.is_file(), name + ": real Pixlet render " + result.stderr[-400:])
    image = Image.open(target)
    check(image.size == (64, 32), name + ": 64x32")
    return target, image


def main():
    global PIXLET
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview-dir", type=pathlib.Path)
    parser.add_argument("--pixlet", default="pixlet", help="Pixlet executable (use the Korean server version for custom font coverage)")
    args = parser.parse_args()
    PIXLET = args.pixlet
    if args.preview_dir:
        check(args.preview_dir.is_dir(), "preview parent exists")
    Handler.routes = {
        "/feeding": (200, (ROOT / "fixtures/feeding.json").read_bytes()),
        "/status": (200, (ROOT / "fixtures/server-status.json").read_bytes()),
        "/plain": (200, document([{"text": "NAS OK"}], stamp(datetime.timedelta(minutes=-1)))),
        "/colors": (200, document([{"segments": [{"text": "RED ", "color": "#FF0000"}, {"text": "GREEN", "color": "#00FF00"}]}])),
        "/long": (200, document([{"segments": [{"text": "RED LONG TEXT RED LONG TEXT ", "color": "#FF0000"}, {"text": "GREEN END", "color": "#00FF00"}]}])),
        "/short": (200, document(["OK"])),
        "/units": (200, document([{"segments": [{"text": "°C", "color": "#0000FF"}, {"text": "%", "color": "#FF0000"}]}])),
        "/split": (200, document([
            {"left": [{"text": "A", "color": "#F2F2F2"}], "right": [{"text": "B", "color": "#8D98A5"}]},
            {"left": [{"text": "C", "color": "#F2F2F2"}], "right": [{"text": "D", "color": "#8D98A5"}]},
            {"left": [{"text": "E", "color": "#F2F2F2"}], "right": [{"text": "F", "color": "#8D98A5"}]},
        ])),
        "/legacy-feeding": (200, (ROOT / "fixtures/feeding-legacy.json").read_bytes()),
        "/split-detail": (200, document([{"left": [{"text": "13:12"}, {"text": "L10R8"}], "right": [{"text": "OR140mL"}]}])),
        "/split-negative": (200, document([{"left": [{"text": "-23.5°C"}], "right": [{"text": "100%"}]}])),
        "/split-wide": (200, document([{"left": [{"text": "X" * 16}], "right": [{"text": "Y" * 2}]}])),
        # Galmuri7 BDF advances: 0=5px, '('=3px, so 10*5 + (5+5+3) + 1 = 64.
        "/split-exact": (200, document([{"left": [{"text": "0" * 10, "color": "#F2F2F2"}], "right": [{"text": "00(", "color": "#FFC66D"}]}])),
        "/split-left": (200, document([{"left": [{"text": "A", "color": "#F2F2F2"}]}])),
        "/split-right": (200, document([{"right": [{"text": "B", "color": "#FFC66D"}]}])),
        "/split-empty": (200, document([{"left": [], "right": []}])),
        "/split-mixed": (200, document(["OLD", {"left": [{"text": "A"}], "right": [{"text": "B"}]}, {"segments": [{"text": "NEW"}]}])),
        "/korean": (200, document(["한글 온도", "정상", "23.5°C60%"])),
        "/invalid": (200, document([{"segments": [{"text": "ok", "color": "red"}]}])),
        "/partial": (200, document(["SAFE", {"segments": [{"text": "bad", "color": "red"}]}])),
        "/empty": (200, document([])),
        "/oversized": (200, document(["X" * 4500])),
        "/stale": (200, document(["OLD"], stamp(datetime.timedelta(days=-2)))),
        "/fresh": (200, document(["OLD"], stamp(datetime.timedelta(minutes=-1)))),
        "/stale-three": (200, document(["A", "B", "C"], stamp(datetime.timedelta(days=-2)))),
        "/bad-time": (200, document(["OLD"], "2026-02-31T00:00:00Z")),
        "/error": (503, b"unavailable"),
        "/recover": (503, b"unavailable"),
        "/malformed": (200, b'{"version":1,'),
    }
    with socketserver.TCPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % server.server_address[1]
        with tempfile.TemporaryDirectory(prefix="data-panel-test-") as temp:
            out = pathlib.Path(temp)
            targets = {}
            images = {}
            for name in ("feeding", "legacy-feeding", "status", "plain", "colors", "long", "short", "units", "split", "split-wide", "split-left", "split-right", "split-empty", "split-mixed", "invalid", "partial", "empty", "oversized", "stale", "fresh", "stale-three", "bad-time", "error"):
                targets[name], images[name] = render(base, out, name, name)
            error_pixels = pixels(images["empty"])
            for name in ("invalid", "partial", "oversized", "bad-time", "error", "split-empty"):
                check(pixels(images[name]) == error_pixels, name + ": intentional error image")
            check(bool(lit(images["empty"])) and (16, 24, 32) in set(images["empty"].convert("RGB").get_flattened_data()), "error image has dark background and visible text")
            check(pixels(images["plain"]) != error_pixels and len(lit(images["plain"])) > 0, "plain text rendered")
            check(bool(colored(images["colors"], "red")) and bool(colored(images["colors"], "green")), "adjacent segment colors visible")
            check(bool(colored(images["status"], "green")), "server-status fixture green segment rendered")
            check(bool(colored(images["units"], "red")) and bool(colored(images["units"], "blue")), "°C and % glyphs have visible colored pixels")
            check((16, 24, 32) in set(images["split-wide"].convert("RGB").get_flattened_data()), "overwide split returns deliberate ROW TOO WIDE error")
            check((16, 24, 32) not in set(images["feeding"].convert("RGB").get_flattened_data()), "approved feeding rows fit the selected font")
            _, exact = render(base, out, "split-exact-Galmuri7", "split-exact", "font=Galmuri7")
            check((16, 24, 32) not in set(exact.convert("RGB").get_flattened_data()), "Galmuri7 exact-fit 50+13+1=64 is accepted")
            exact_left = lit(exact, lambda p: p == (242, 242, 242))
            exact_right = lit(exact, lambda p: p == (255, 198, 109))
            check(bool(exact_left) and bool(exact_right) and min(x for x, _ in exact_left) == 0 and min(x for x, _ in exact_right) >= 51 and max(x for x, _ in exact_right) >= 62, "exact-fit groups retain both anchors without clipping")
            for route in ("split-detail", "split-negative"):
                _, alt = render(base, out, route + "-6x10", route, "font=6x10")
                check((16, 24, 32) in set(alt.convert("RGB").get_flattened_data()), route + " explicitly rejects width beyond selected font bounds")
            split = images["split"].convert("RGB")
            for top, bottom in ((0, 10), (10, 20), (20, 30)):
                left_pixels = [(x, y) for x, y in lit(split, lambda p: p == (242, 242, 242)) if top <= y < bottom]
                right_pixels = [(x, y) for x, y in lit(split, lambda p: p == (141, 152, 165)) if top <= y < bottom]
                check(bool(left_pixels) and bool(right_pixels), "split fixture groups visible")
                check(min(x for x, _ in left_pixels) == 0 and max(x for x, _ in right_pixels) >= 60, "split groups anchor at left and right panel edges")
                check(min(x for x, _ in right_pixels) - max(x for x, _ in left_pixels) - 1 >= 1, "split groups have at least one blank pixel gap")
            check(min(x for x, _ in lit(images["split-left"])) == 0 and max(x for x, _ in lit(images["split-right"])) >= 60, "one-sided split groups retain their anchors")
            check(pixels(images["split-mixed"]) != error_pixels, "legacy and split rows coexist")
            feed = images["feeding"].convert("RGB")
            expected_rows = [("14:32", "1H20M", 0, 10), ("13:12", "L10R8", 10, 20), ("23.5°C", "60%", 20, 30)]
            expected_colors = [((242, 242, 242), (255, 198, 109)), ((141, 152, 165), (136, 216, 176)), ((244, 165, 138), (128, 191, 255))]
            for (left, right, top, bottom), (lc, rc) in zip(expected_rows, expected_colors):
                points = [(x, y) for x, y in lit(feed) if top <= y < bottom]
                lp = [(x, y) for x, y in points if feed.getpixel((x, y)) == lc]
                rp = [(x, y) for x, y in points if feed.getpixel((x, y)) == rc]
                check(bool(lp) and bool(rp), "feeding row colors visible: " + left + " / " + right)
                check(min(x for x, _ in lp) == 0 and max(x for x, _ in rp) >= 60, "feeding row left/right anchors: " + left + " / " + right)
                check(min(x for x, _ in rp) - max(x for x, _ in lp) > 1, "feeding row groups separated: " + left + " / " + right)
                check(all(top <= y < bottom for _, y in points), "feeding row bounds: " + left + " / " + right)
                print("GEOMETRY", left, right, "font=tom-thumb", "left-x", min(x for x, _ in lp), max(x for x, _ in lp), "right-x", min(x for x, _ in rp), max(x for x, _ in rp))
            legacy = images["legacy-feeding"].convert("RGB")
            for text, top, bottom in (("FEED1H20M", 0, 10), ("13:12 L10R8", 10, 20), ("23.5°C60%", 20, 30)):
                check(bool([(x, y) for x, y in lit(legacy) if top <= y < bottom]), "original legacy feeding row remains visible: " + text)
            check(all(c in set(legacy.get_flattened_data()) for c in ((170, 170, 170), (255, 255, 255), (85, 204, 255), (255, 170, 0))), "original legacy segment colors preserved")
            check(pixels(images["stale"]) != pixels(images["fresh"]) and bool(lit(images["stale"], lambda p: p[0] > 110 and p[1] > 50 and p[2] < 50)), "old source marked stale; fresh identical text not marked")
            _, high_age = render(base, out, "high-age", "stale", "stale_age_seconds=9999999")
            check(pixels(high_age) == pixels(images["fresh"]), "configurable stale threshold uses source timestamp")
            check(all(max(images["stale-three"].convert("RGB").getpixel((x, 31))) > 80 for x in range(64)), "three-row stale stripe stays in bounds")
            _, failed = render(base, out, "recover-failed", "recover")
            check(pixels(failed) == error_pixels, "HTTP 503 displays intentional error image")
            Handler.routes["/recover"] = (200, document(["RECOVERED"]))
            _, recovered = render(base, out, "recover-success", "recover")
            check(pixels(recovered) != error_pixels, "next successful response recovers (no validated LKG storage)")

            _, font_default = render(base, out, "font-default", "feeding")
            _, font_invalid = render(base, out, "font-invalid", "feeding", "font=unknown-custom-font")
            check(pixels(font_default) == pixels(images["feeding"]), "font schema default uses tom-thumb")
            check(pixels(font_invalid) != error_pixels and pixels(font_invalid) != pixels(font_default) and bool(lit(font_invalid)), "unregistered font shows explicit FONT NOT FOUND, not silent fallback")
            _, font_alt = render(base, out, "font-alt", "feeding", "font=6x10")
            check(len(lit(font_alt)) > 0 and (16, 24, 32) not in set(font_alt.convert("RGB").get_flattened_data()) and pixels(font_alt) != pixels(font_default), "6x10 approved split fixture actually renders")
            _, custom = render(base, out, "font-custom", "korean", "font=Galmuri7")
            check(pixels(custom) != error_pixels and len(lit(custom)) > 0, "registered Korean Galmuri7 renders three rows despite nonnumeric font name")
            check(bool(lit(custom, lambda p: p[0] > 100 and p[1] > 100 and p[2] > 100)), "Korean custom font glyph pixels visible")
            _, custom_tall = render(base, out, "font-custom-tall", "korean", "font=Galmuri11")
            check(pixels(custom_tall) != pixels(custom) and (16, 24, 32) in set(custom_tall.convert("RGB").get_flattened_data()), "custom font over height budget shows FONT TOO BIG")
            _, too_tall = render(base, out, "font-too-tall", "feeding", "font=10x20")
            check((16, 24, 32) in set(too_tall.convert("RGB").get_flattened_data()) and bool(lit(too_tall)), "too-tall three-row font returns FONT TOO BIG using safe compact font")
            _, tall_one = render(base, out, "font-tall-one", "plain", "font=10x20")
            check(len(lit(tall_one)) > 0, "10x20 single row fits vertically")

            clip = {}
            scroll = {}
            for alignment in ("left", "center", "right"):
                _, image = render(base, out, alignment + "-clip", "short", "alignment=" + alignment, "overflow=clip")
                clip[alignment] = lit(image)
                _, image = render(base, out, alignment + "-scroll", "short", "alignment=" + alignment, "overflow=scroll")
                scroll[alignment] = lit(image)
                check(pixels(image) == pixels(Image.open(out / (alignment + "-clip.webp"))), alignment + ": short scroll does not move")
            lefts = [min(x for x, _ in clip[a]) for a in ("left", "center", "right")]
            check(lefts[0] < lefts[1] < lefts[2], "left/center/right whole-row geometry")
            _, long_clip = render(base, out, "long-clip", "long", "overflow=clip")
            _, long_scroll = render(base, out, "long-scroll", "long", "overflow=scroll")
            check(not colored(long_clip, "green"), "clip hides off-screen second segment")
            check(long_scroll.n_frames > 1, "scroll creates animation frames")
            seen_green = False
            for frame in range(long_scroll.n_frames):
                long_scroll.seek(frame)
                assert long_scroll.size == (64, 32), "scroll frame exceeds panel bounds"
                if colored(long_scroll, "green"):
                    seen_green = True
                    break
            check(seen_green, "scroll moves joined segments into view")
            render(base, out, "malformed", "malformed", success=False)
            transport = subprocess.run([PIXLET, "render", str(ROOT / "data_panel.star"), "url=http://127.0.0.1:1/unreachable", "-o", str(out / "transport.webp")], text=True, capture_output=True, timeout=45)
            check(transport.returncode != 0, "HTTP transport failure is an explicit uncaught Pixlet runtime failure")
            schema = json.loads(subprocess.check_output([PIXLET, "schema", str(ROOT / "data_panel.star")], text=True))
            font_field = next(field for field in schema["schema"] if field["id"] == "font")
            choices = {option["value"] for option in font_field["options"]}
            check(font_field["default"] == "tom-thumb" and font_field["type"] == "dropdown" and {"Galmuri7", "Galmuri11", "6x10", "tom-thumb"} <= choices, "schema enumerates runtime registered fonts with tom-thumb default")
            import jsonschema
            contract = json.loads((ROOT / "data-panel.schema.json").read_text())
            jsonschema.Draft202012Validator.check_schema(contract)
            validator = jsonschema.Draft202012Validator(contract)
            for good in ((ROOT / "fixtures/feeding.json").read_bytes(), (ROOT / "fixtures/feeding-legacy.json").read_bytes(), document(["plain", {"text": "legacy"}, {"left": [{"text": "L"}], "right": [{"text": "R"}]}]), document([{"right": [{"text": "R"}]}])):
                check(not list(validator.iter_errors(json.loads(good))), "JSON Schema accepts valid payload")
            for bad_row in ({"text": "x", "segments": [{"text": "y"}]}, {"left": [], "right": []}, {"left": "not-list"}, {"left": [{"text": "X", "unknown": 1}]}, {"left": [{"text": "X"}], "unknown": 1}):
                check(bool(list(validator.iter_errors({"version": 1, "lines": [bad_row]}))), "JSON Schema rejects invalid row contract: " + str(bad_row))
            _, split_alt = render(base, out, "feeding-6x10", "feeding", "font=6x10")
            _, split_galmuri = render(base, out, "feeding-Galmuri7", "feeding", "font=Galmuri7")
            for font_name, alternative in (("6x10", split_alt), ("Galmuri7", split_galmuri)):
                check((16, 24, 32) not in set(alternative.convert("RGB").get_flattened_data()), "feeding " + font_name + " preview is data, not an error")
                for (left, right, top, bottom), (lc, rc) in zip(expected_rows, expected_colors):
                    lp = [(x, y) for x, y in lit(alternative, lambda p: p == lc) if top <= y < bottom]
                    rp = [(x, y) for x, y in lit(alternative, lambda p: p == rc) if top <= y < bottom]
                    check(bool(lp) and bool(rp) and min(x for x, _ in lp) == 0 and max(x for x, _ in rp) >= 60 and min(x for x, _ in rp) > max(x for x, _ in lp) + 1, "feeding " + font_name + " split colors/anchors/gap: " + left + " / " + right)
                    print("GEOMETRY", left, right, "font=" + font_name, "left-x", min(x for x, _ in lp), max(x for x, _ in lp), "right-x", min(x for x, _ in rp), max(x for x, _ in rp))
            if args.preview_dir:
                for name, source, image in (("feeding", targets["feeding"], images["feeding"]), ("feeding-6x10", out / "feeding-6x10.webp", split_alt), ("feeding-Galmuri7", out / "feeding-Galmuri7.webp", split_galmuri), ("error", targets["empty"], images["empty"]), ("font-Galmuri7", out / "font-custom.webp", custom)):
                    image = image.convert("RGB")
                    prefix = args.preview_dir / ("data-panel-" + name)
                    shutil.copyfile(source, prefix.with_suffix(".webp"))
                    image.save(prefix.with_suffix(".png"))
                    image.resize((640, 320), Image.Resampling.NEAREST).save(args.preview_dir / ("data-panel-" + name + "-10x.png"))
                    print("PREVIEW", prefix.with_suffix(".webp"), prefix.with_suffix(".png"), args.preview_dir / ("data-panel-" + name + "-10x.png"))
                name = "status"
                source = targets[name]
                image = images[name].convert("RGB")
                prefix = args.preview_dir / ("data-panel-" + name)
                shutil.copyfile(source, prefix.with_suffix(".webp"))
                image.save(prefix.with_suffix(".png"))
                image.resize((640, 320), Image.Resampling.NEAREST).save(args.preview_dir / ("data-panel-" + name + "-10x.png"))
                print("PREVIEW", prefix.with_suffix(".webp"), prefix.with_suffix(".png"), args.preview_dir / ("data-panel-" + name + "-10x.png"))
        server.shutdown()


if __name__ == "__main__":
    main()
