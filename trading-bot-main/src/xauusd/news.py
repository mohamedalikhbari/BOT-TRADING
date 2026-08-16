from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd


WINDOWS = {
    "CRITICAL": (60, 60),
    "HIGH": (30, 30),
    "MEDIUM": (15, 15),
    "LOW": (0, 0),
}


@dataclass(frozen=True)
class NewsEvent:
    at: datetime
    name: str
    impact: str
    country: str = "US"

    @property
    def blackout_start(self) -> datetime:
        return self.at - timedelta(minutes=WINDOWS[self.impact][0])

    @property
    def blackout_end(self) -> datetime:
        return self.at + timedelta(minutes=WINDOWS[self.impact][1])


class NewsCalendar:
    def __init__(self, events: list[NewsEvent], *, available: bool = True):
        self.events = sorted(events, key=lambda event: event.at)
        self.available = available

    @classmethod
    def from_csv(cls, path: str | Path, *, required: bool = True) -> "NewsCalendar":
        source = Path(path)
        if not source.exists():
            return cls([], available=not required)
        frame = pd.read_csv(source, parse_dates=["time"])
        events = [
            NewsEvent(
                pd.Timestamp(row.time).to_pydatetime(),
                str(row.name),
                str(row.impact).upper(),
                str(getattr(row, "country", "US")),
            )
            for row in frame.itertuples(index=False)
            if str(row.impact).upper() in WINDOWS
        ]
        return cls(events, available=True)

    def is_blackout(self, at: datetime) -> bool:
        if not self.available:
            return True
        return any(event.blackout_start <= at <= event.blackout_end for event in self.events)

    def force_close_reason(self, at: datetime) -> str | None:
        if not self.available:
            return "NEWS_CALENDAR_UNAVAILABLE"
        for event in self.events:
            lead = 15 if event.impact == "CRITICAL" else 10 if event.impact == "HIGH" else None
            if lead is not None and event.at - timedelta(minutes=lead) <= at < event.at:
                return f"NEWS_{event.impact}:{event.name}"
        return None

    def next_events(self, at: datetime, hours: int = 4) -> list[NewsEvent]:
        end = at + timedelta(hours=hours)
        return [event for event in self.events if at <= event.at <= end]

