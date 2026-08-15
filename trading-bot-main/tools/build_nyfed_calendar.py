from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


MONTH_CODES = (
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
)
TIME_RE = re.compile(r"^\((\d{2}):(\d{2})\)$")


@dataclass(frozen=True)
class Release:
    eastern: datetime
    name: str
    impact: str


class CalendarPageParser(HTMLParser):
    def __init__(self, year: int, month: int) -> None:
        super().__init__(convert_charrefs=True)
        self.year = year
        self.month = month
        self._cell: list[str] | None = None
        self.releases: list[Release] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "td":
            return
        attributes = dict(attrs)
        classes = attributes.get("class") or ""
        if "somatd" in classes:
            self._cell = []

    def handle_data(self, data: str) -> None:
        if self._cell is None:
            return
        value = " ".join(data.split())
        if value:
            self._cell.append(value)

    def handle_endtag(self, tag: str) -> None:
        if tag != "td" or self._cell is None:
            return
        self._parse_cell(self._cell)
        self._cell = None

    def _parse_cell(self, values: list[str]) -> None:
        if not values or not values[0].isdigit():
            return
        day = int(values[0])
        if not 1 <= day <= 31:
            return
        name_parts: list[str] = []
        for value in values[1:]:
            match = TIME_RE.match(value)
            if match is None:
                name_parts.append(value)
                continue
            if not name_parts:
                continue
            name = " ".join(name_parts).strip()
            name_parts.clear()
            hour, minute = (int(part) for part in match.groups())
            eastern = datetime(self.year, self.month, day, hour, minute)
            self.releases.append(Release(eastern, name, classify_impact(name)))


def classify_impact(name: str) -> str:
    normalized = name.casefold()
    critical = (
        "consumer price index",
        "producer price index",
        "employment situation",
        "pce deflator",
        "pce price",
        "fomc",
        "fed chair",
        "powell",
    )
    if any(token in normalized for token in critical):
        return "CRITICAL"
    high = (
        "retail sales",
        "gross domestic product",
        "ism manufacturing",
        "ism non-manufacturing",
        "initial claims",
        "jobless claims",
        "adp national employment",
        "consumer confidence",
        "durable goods",
        "industrial production",
        "trade balance",
        "imports and exports",
        "new residential construction",
        "philadelphia fed manufacturing",
        "empire state manufacturing",
    )
    return "HIGH" if any(token in normalized for token in high) else "MEDIUM"


def month_sequence(start: date, end: date):
    year, month = start.year, start.month
    while (year, month) <= (end.year, end.month):
        yield year, month
        month += 1
        if month == 13:
            year += 1
            month = 1


def fetch_month(year: int, month: int) -> list[Release]:
    code = MONTH_CODES[month - 1]
    url = f"https://www.newyorkfed.org/research/calendars/i-{code}{year % 100:02d}.html"
    request = Request(url, headers={"User-Agent": "trading-bot-calendar-audit/1.0"})
    with urlopen(request, timeout=30) as response:
        final_url = response.geturl()
        html = response.read().decode("utf-8", errors="replace")
    if "/errors/404" in final_url or "Page Not Found" in html:
        raise RuntimeError(f"New York Fed calendar unavailable: {url}")
    parser = CalendarPageParser(year, month)
    parser.feed(html)
    if not parser.releases:
        raise RuntimeError(f"No releases parsed from {url}")
    return parser.releases


def add_weekly_claims(releases: list[Release], start: date, end: date) -> None:
    known = {
        release.eastern.date()
        for release in releases
        if "initial claims" in release.name.casefold()
        or "jobless claims" in release.name.casefold()
    }
    current = start
    while current.weekday() != 3:
        current += timedelta(days=1)
    while current <= end:
        if current not in known:
            releases.append(
                Release(
                    datetime.combine(current, time(8, 30)),
                    "Initial Claims (weekly conservative schedule)",
                    "HIGH",
                )
            )
        current += timedelta(days=7)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    parser.add_argument("--start", default="2025-01-01")
    parser.add_argument("--end", default="2026-08-01")
    parser.add_argument("--server-timezone", default="Europe/Athens")
    args = parser.parse_args()

    start = date.fromisoformat(args.start)
    end = date.fromisoformat(args.end)
    if end <= start:
        raise ValueError("end must be after start")
    releases: list[Release] = []
    for year, month in month_sequence(start, end - timedelta(days=1)):
        releases.extend(fetch_month(year, month))
    add_weekly_claims(releases, start, end - timedelta(days=1))

    eastern = ZoneInfo("America/New_York")
    server = ZoneInfo(args.server_timezone)
    unique: dict[tuple[datetime, str], Release] = {}
    for release in releases:
        if not start <= release.eastern.date() < end:
            continue
        server_wall = release.eastern.replace(tzinfo=eastern).astimezone(server)
        unique[(server_wall.replace(tzinfo=None), release.name)] = release

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    with args.destination.open("w", newline="", encoding="cp1252", errors="replace") as handle:
        writer = csv.writer(handle)
        writer.writerow(("time", "impact", "name"))
        for (server_wall, name), release in sorted(unique.items()):
            writer.writerow((server_wall.strftime("%Y.%m.%d %H:%M"), release.impact, name))
    print(f"Wrote {len(unique)} releases to {args.destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
