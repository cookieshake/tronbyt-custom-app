#!/usr/bin/env python3
"""Run synthetic calendar fixtures through the real Pixlet/Starlark runtime."""
import argparse
import pathlib
import subprocess
import tempfile

APP = pathlib.Path(__file__).resolve().parents[1]
DRIVER = r'''
def event(start, params = "", end = None, rule = None):
    lines = ["BEGIN:VCALENDAR", "BEGIN:VEVENT", "DTSTART%s:%s" % (params, start)]
    if end != None:
        lines.append("DTEND;VALUE=DATE:%s" % end)
    if rule != None:
        lines.append("RRULE:%s" % rule)
    lines.extend(["SUMMARY:synthetic fixture", "END:VEVENT", "END:VCALENDAR"])
    return "\n".join(lines)

def check(actual, expected, label):
    if actual != expected:
        fail("%s: got %s, want %s" % (label, actual, expected))

def run(body, zone, now, expected, label):
    check(fetch_events_from_ical(body, 4, zone, now), [("synthetic fixture", expected)], label)

def main(config):
    run(event("20240102T030000Z"), "Asia/Seoul", time.time(year=2024, month=1, day=1, hour=0, location="UTC"), "01/02 12:00", "UTC 03:00Z -> Seoul 12:00")
    run(event("20240101T153000Z"), "Asia/Seoul", time.time(year=2024, month=1, day=1, hour=15, location="UTC"), "01/02 00:30", "previous UTC day -> Seoul next day")
    run(event("20240309T123000", ";TZID=America/New_York"), "Asia/Seoul", time.time(year=2024, month=3, day=9, hour=0, location="UTC"), "03/10 02:30", "New York standard time before DST")
    run(event("20240102T120000"), "Asia/Seoul", time.time(year=2024, month=1, day=1, hour=0, location="UTC"), "01/02 12:00", "floating value in display zone")
    all_day = event("20240102", ";VALUE=DATE", end="20240103")
    run(all_day, "Asia/Seoul", time.time(year=2024, month=1, day=2, hour=0, location="UTC"), "01/02", "all-day civil date")
    run(all_day, "UTC", time.time(year=2024, month=1, day=2, hour=0, location="UTC"), "01/02", "all-day civil date in UTC")
    run(all_day, "Asia/Seoul", time.time(year=2024, month=1, day=3, hour=0, location="UTC"), "01/02", "existing inclusive DTEND date")
    first = event("20240101", ";VALUE=DATE").replace("BEGIN:VCALENDAR\n", "").replace("\nEND:VCALENDAR", "")
    second = event("20240102", ";VALUE=DATE").replace("BEGIN:VCALENDAR\n", "").replace("\nEND:VCALENDAR", "")
    combined = "BEGIN:VCALENDAR\n%s\n%s\nEND:VCALENDAR" % (first, second)
    run(combined, "Asia/Seoul", time.time(year=2024, month=1, day=1, hour=15, minute=30, location="UTC"), "01/02", "Seoul calendar-day filtering at UTC Jan 1 / Seoul Jan 2")
    run(event("20240309T123000", ";TZID=America/New_York", rule="FREQ=DAILY;COUNT=3"), "Asia/Seoul", time.time(year=2024, month=3, day=10, hour=15, location="UTC"), "03/11 01:30", "daily source-wall-clock recurrence")
    run(event("20240303T123000", ";TZID=America/New_York", rule="FREQ=WEEKLY;COUNT=3"), "Asia/Seoul", time.time(year=2024, month=3, day=10, hour=15, location="UTC"), "03/11 01:30", "weekly source-wall-clock recurrence")
    run(event("20240303T123000", ";TZID=America/New_York", rule="FREQ=WEEKLY;COUNT=3"), "Asia/Seoul", time.time(year=2024, month=3, day=11, hour=0, location="UTC"), "03/18 01:30", "weekly next occurrence retains source hour")
    run(event("20240102T030000", ";TZID=Not/AZone"), "Asia/Seoul", time.time(year=2024, month=1, day=1, hour=0, location="UTC"), "01/02 03:00", "unknown TZID fallback")
    run(event("20240102T030000Z"), "Not/AZone", time.time(year=2024, month=1, day=1, hour=0, location="UTC"), "01/02 12:00", "invalid display timezone fallback")
    return render.Root(child=render.Text("13 synthetic calendar checks passed"))
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pixlet", default="pixlet")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="calendar-pulse-test-") as temp:
        work = pathlib.Path(temp)
        driver = work / "calendar_pulse_test.star"
        source = (APP / "calendar_pulse.star").read_text()
        # Pixlet loads every .star in the directory and rejects duplicate main().
        # Run the real app functions in the same module with a synthetic entrypoint.
        if source.count("def main(config):") != 1:
            raise SystemExit("Expected exactly one app entrypoint")
        driver.write_text(source.replace("def main(config):", "def app_main(config):", 1) + "\n" + DRIVER)
        output = work / "fixtures.webp"
        result = subprocess.run([args.pixlet, "render", str(driver), "-o", str(output)], text=True, capture_output=True, timeout=90)
        if result.returncode:
            raise SystemExit(result.stderr or result.stdout)
        if not output.is_file() or output.stat().st_size == 0:
            raise SystemExit("Pixlet completed without producing the fixture render")
        print("PASS: 13 synthetic ICS cases executed in Pixlet; WebP rendered")


if __name__ == "__main__":
    main()
