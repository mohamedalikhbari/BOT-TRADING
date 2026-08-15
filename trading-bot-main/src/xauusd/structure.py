from __future__ import annotations

from bisect import bisect_right
from collections.abc import Iterable
from datetime import datetime
import math

import pandas as pd

from .domain import (
    Direction,
    StructureEvent,
    StructureEventKind,
    StructureSnapshot,
    SwingKind,
    SwingPoint,
    Trend,
)


def _trend(
    highs: list[SwingPoint], lows: list[SwingPoint]
) -> Trend:
    if len(highs) < 2 or len(lows) < 2:
        return Trend.RANGING
    previous_high, last_high = highs[-2], highs[-1]
    previous_low, last_low = lows[-2], lows[-1]
    if last_high.price > previous_high.price and last_low.price > previous_low.price:
        return Trend.BULLISH
    if last_high.price < previous_high.price and last_low.price < previous_low.price:
        return Trend.BEARISH
    return Trend.RANGING


def detect_swings(bars: pd.DataFrame, k: int) -> list[SwingPoint]:
    """Detect confirmed fractals while retaining the first of equal extrema."""
    if k < 1:
        raise ValueError("k must be positive")
    highs = bars["high"].to_numpy(dtype=float)
    lows = bars["low"].to_numpy(dtype=float)
    atrs = bars["atr"].to_numpy(dtype=float)
    close_times = list(bars["close_time"])
    open_times = list(bars.index)
    result: list[SwingPoint] = []
    last_by_kind: dict[SwingKind, SwingPoint] = {}

    for index in range(k, len(bars) - k):
        left_highs = highs[index - k : index]
        right_highs = highs[index + 1 : index + k + 1]
        left_lows = lows[index - k : index]
        right_lows = lows[index + 1 : index + k + 1]
        candidates: list[tuple[SwingKind, float]] = []
        # Strict on the left and inclusive on the right selects the first equal high/low.
        if (highs[index] > left_highs).all() and (highs[index] >= right_highs).all():
            candidates.append((SwingKind.HIGH, highs[index]))
        if (lows[index] < left_lows).all() and (lows[index] <= right_lows).all():
            candidates.append((SwingKind.LOW, lows[index]))

        for kind, price in candidates:
            atr_value = float(atrs[index])
            if not math.isfinite(atr_value):
                continue
            previous = last_by_kind.get(kind)
            if previous and abs(previous.price - price) <= atr_value * 0.1:
                continue
            point = SwingPoint(
                kind=kind,
                price=float(price),
                occurred_at=pd.Timestamp(open_times[index]).to_pydatetime(),
                confirmed_at=pd.Timestamp(close_times[index + k]).to_pydatetime(),
                index=index,
                atr=atr_value,
            )
            result.append(point)
            last_by_kind[kind] = point

    return sorted(result, key=lambda item: (item.confirmed_at, item.index))


class StructureTimeline:
    """A no-look-ahead view of swings and structure events for one timeframe."""

    def __init__(self, bars: pd.DataFrame, k: int, min_break_atr: float):
        self.bars = bars
        self.k = k
        self.min_break_atr = min_break_atr
        self.swings = detect_swings(bars, k)
        self._swing_times = [swing.confirmed_at for swing in self.swings]
        self.events = self._build_events()
        self._event_times = [event.occurred_at for event in self.events]
        self._events_at: dict[datetime, list[StructureEvent]] = {}
        for event in self.events:
            self._events_at.setdefault(event.occurred_at, []).append(event)

    def _build_events(self) -> list[StructureEvent]:
        events: list[StructureEvent] = []
        available_highs: list[SwingPoint] = []
        available_lows: list[SwingPoint] = []
        swing_cursor = 0
        broken: set[tuple[SwingKind, int]] = set()

        for _, row in self.bars.iterrows():
            at = pd.Timestamp(row["close_time"]).to_pydatetime()
            while (
                swing_cursor < len(self.swings)
                and self.swings[swing_cursor].confirmed_at <= at
            ):
                swing = self.swings[swing_cursor]
                if swing.kind is SwingKind.HIGH:
                    available_highs.append(swing)
                else:
                    available_lows.append(swing)
                swing_cursor += 1

            if not available_highs or not available_lows:
                continue
            atr_value = float(row["atr"])
            if not math.isfinite(atr_value) or not bool(row.get("quality_ok", True)):
                continue
            current_trend = _trend(available_highs, available_lows)
            close = float(row["close"])
            high_swing = available_highs[-1]
            low_swing = available_lows[-1]
            high_key = (SwingKind.HIGH, high_swing.index)
            low_key = (SwingKind.LOW, low_swing.index)
            threshold = self.min_break_atr * atr_value

            if high_key not in broken and close > high_swing.price + threshold:
                if current_trend is Trend.BULLISH:
                    kind = StructureEventKind.BOS
                elif current_trend is Trend.BEARISH:
                    kind = StructureEventKind.CHOCH
                else:
                    kind = None
                if kind:
                    events.append(
                        StructureEvent(
                            kind,
                            Direction.LONG,
                            at,
                            high_swing.price,
                            close,
                            high_swing,
                        )
                    )
                broken.add(high_key)

            if low_key not in broken and close < low_swing.price - threshold:
                if current_trend is Trend.BEARISH:
                    kind = StructureEventKind.BOS
                elif current_trend is Trend.BULLISH:
                    kind = StructureEventKind.CHOCH
                else:
                    kind = None
                if kind:
                    events.append(
                        StructureEvent(
                            kind,
                            Direction.SHORT,
                            at,
                            low_swing.price,
                            close,
                            low_swing,
                        )
                    )
                broken.add(low_key)

        return sorted(events, key=lambda event: event.occurred_at)

    def swings_at(self, at: datetime) -> list[SwingPoint]:
        return self.swings[: bisect_right(self._swing_times, at)]

    def events_at(self, at: datetime) -> tuple[StructureEvent, ...]:
        return tuple(self._events_at.get(at, ()))

    def events_between(self, start: datetime, end: datetime) -> list[StructureEvent]:
        left = bisect_right(self._event_times, start)
        right = bisect_right(self._event_times, end)
        return self.events[left:right]

    def snapshot(self, at: datetime) -> StructureSnapshot:
        swings = self.swings_at(at)
        highs = [swing for swing in swings if swing.kind is SwingKind.HIGH]
        lows = [swing for swing in swings if swing.kind is SwingKind.LOW]
        event_index = bisect_right(self._event_times, at)
        latest_event = self.events[event_index - 1] if event_index else None
        return StructureSnapshot(
            at=at,
            last_high=highs[-1] if highs else None,
            previous_high=highs[-2] if len(highs) >= 2 else None,
            last_low=lows[-1] if lows else None,
            previous_low=lows[-2] if len(lows) >= 2 else None,
            trend=_trend(highs, lows),
            latest_event=latest_event,
        )

    def recent_events(
        self,
        at: datetime,
        *,
        bars: int,
        kind: StructureEventKind | None = None,
        direction: Direction | None = None,
    ) -> list[StructureEvent]:
        closed = self.bars[self.bars["close_time"] <= at]
        if closed.empty:
            return []
        start_index = max(0, len(closed) - bars)
        start = pd.Timestamp(closed.iloc[start_index]["close_time"]).to_pydatetime()
        candidates = self.events_between(start, at)
        if kind is not None:
            candidates = [event for event in candidates if event.kind is kind]
        if direction is not None:
            candidates = [event for event in candidates if event.direction is direction]
        return candidates



def latest_closed_row(bars: pd.DataFrame, at: datetime) -> pd.Series | None:
    available = bars[bars["close_time"] <= at]
    if available.empty:
        return None
    return available.iloc[-1]


def event_matches(
    events: Iterable[StructureEvent],
    *,
    kind: StructureEventKind,
    direction: Direction,
) -> bool:
    return any(event.kind is kind and event.direction is direction for event in events)
