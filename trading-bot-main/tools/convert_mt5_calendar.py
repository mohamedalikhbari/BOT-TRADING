from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--server-timezone", default="Europe/Athens")
    args = parser.parse_args()
    server_zone = ZoneInfo(args.server_timezone)
    rows: dict[tuple[str, str], dict[str, str]] = {}
    with args.source.open(newline="", encoding="cp1252", errors="replace") as handle:
        for row in csv.DictReader(handle):
            server_wall = datetime.strptime(row["server_time"], "%Y.%m.%d %H:%M")
            at = server_wall.replace(tzinfo=server_zone).astimezone(timezone.utc)
            converted = {
                "time": at.isoformat(),
                "name": row["name"],
                "impact": row["impact"],
                "country": "US",
                "event_id": row["event_id"],
                "server_time": row["server_time"],
            }
            rows[(converted["time"], converted["event_id"])] = converted
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    with args.destination.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = ["time", "name", "impact", "country", "event_id", "server_time"]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(sorted(rows.values(), key=lambda row: (row["time"], row["name"])))
    print(f"Converted {len(rows)} economic-calendar events to {args.destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
