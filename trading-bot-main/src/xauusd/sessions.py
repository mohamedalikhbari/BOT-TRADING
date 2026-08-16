from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd

from .domain import LiquidityLevel, LiquidityState


NEW_YORK = ZoneInfo("America/New_York")


def ny_open(local_date: date) -> datetime:
    return datetime.combine(local_date, time(9, 30), NEW_YORK).astimezone(timezone.utc)


def ny_close(local_date: date) -> datetime:
    return datetime.combine(local_date, time(17, 0), NEW_YORK).astimezone(timezone.utc)


def ny_date(at: datetime) -> date:
    return at.astimezone(NEW_YORK).date()


def trading_window(at: datetime) -> tuple[datetime, datetime]:
    opening = ny_open(ny_date(at))
    return opening - timedelta(minutes=60), opening + timedelta(minutes=60)


def in_trading_window(at: datetime) -> bool:
    start, end = trading_window(at)
    return start <= at <= end


def setup_deadline(at: datetime) -> datetime:
    return ny_open(ny_date(at)) + timedelta(minutes=120)


def must_force_close(at: datetime) -> bool:
    local = at.astimezone(NEW_YORK)
    if local.weekday() == 4 and local.time() >= time(15, 0):
        return True
    return local.time() >= time(16, 45)


def trading_day_label(at: datetime) -> date:
    """Label a 17:00-to-17:00 New York trading day by its ending date."""
    return (at.astimezone(NEW_YORK) + timedelta(hours=7)).date()


@dataclass(frozen=True)
class DayLevels:
    label: date
    high: float
    low: float
    available_at: datetime


class LiquidityBook:
    def __init__(self, m1: pd.DataFrame):
        self._swept: set[tuple[date, str, float]] = set()
        working = m1[["high", "low"]].copy()
        working["label"] = [trading_day_label(ts.to_pydatetime()) for ts in working.index]
        grouped = working.groupby("label", sort=True).agg(high=("high", "max"), low=("low", "min"))
        self.days: dict[date, DayLevels] = {}
        for label, row in grouped.iterrows():
            available_at = ny_close(label)
            self.days[label] = DayLevels(label, float(row.high), float(row.low), available_at)
        self._labels = sorted(self.days)

        self.asian_sessions: dict[date, DayLevels] = {}
        utc_dates = sorted({timestamp.date() for timestamp in m1.index})
        for utc_day in utc_dates:
            start = datetime.combine(utc_day, time.min, timezone.utc)
            end = start + timedelta(hours=8)
            subset = m1[(m1.index >= start) & (m1.index < end)]
            if not subset.empty:
                self.asian_sessions[utc_day] = DayLevels(
                    utc_day,
                    float(subset["high"].max()),
                    float(subset["low"].min()),
                    end,
                )

        self.ny_sessions: dict[date, DayLevels] = {}
        local_dates = sorted({timestamp.tz_convert(NEW_YORK).date() for timestamp in m1.index})
        for local_day in local_dates:
            start = ny_open(local_day)
            end = ny_close(local_day)
            subset = m1[(m1.index >= start) & (m1.index < end)]
            if not subset.empty:
                self.ny_sessions[local_day] = DayLevels(
                    local_day,
                    float(subset["high"].max()),
                    float(subset["low"].min()),
                    end,
                )
        self._ny_session_labels = sorted(self.ny_sessions)

        self.pre_ny: dict[date, tuple[pd.DatetimeIndex, np.ndarray, np.ndarray, datetime]] = {}
        for utc_day in utc_dates:
            opening = ny_open(utc_day)
            start = datetime.combine(utc_day, time.min, timezone.utc)
            subset = m1[(m1.index >= start) & (m1.index < opening)]
            if not subset.empty:
                close_times = (
                    pd.DatetimeIndex(subset["close_time"])
                    if "close_time" in subset
                    else subset.index + pd.Timedelta(minutes=1)
                )
                self.pre_ny[utc_day] = (
                    close_times,
                    subset["high"].cummax().to_numpy(dtype=float),
                    subset["low"].cummin().to_numpy(dtype=float),
                    opening,
                )

    def _previous_day(self, at: datetime) -> DayLevels | None:
        current = trading_day_label(at)
        previous = [label for label in self._labels if label < current]
        if not previous:
            return None
        return self.days[previous[-1]]

    def _previous_ny_session(self, at: datetime) -> DayLevels | None:
        current = ny_date(at)
        previous = [label for label in self._ny_session_labels if label < current]
        if not previous:
            return None
        return self.ny_sessions[previous[-1]]

    @staticmethod
    def _key(at: datetime, level: LiquidityLevel) -> tuple[date, str, float]:
        return ny_date(at), level.name, round(level.price, 8)

    def _with_state(self, at: datetime, level: LiquidityLevel) -> LiquidityLevel:
        state = (
            LiquidityState.SWEPT
            if self._key(at, level) in self._swept
            else LiquidityState.INTACT
        )
        return LiquidityLevel(level.name, level.price, level.formed_at, state)

    def mark_swept(self, at: datetime, levels: tuple[LiquidityLevel, ...]) -> None:
        for level in levels:
            self._swept.add(self._key(at, level))

    def levels_at(self, at: datetime, *, as_of: datetime | None = None) -> list[LiquidityLevel]:
        levels: list[LiquidityLevel] = []
        cutoff = as_of or at
        previous = self._previous_day(at)
        if previous is not None:
            levels.extend(
                [
                    LiquidityLevel("PDH", previous.high, previous.available_at),
                    LiquidityLevel("PDL", previous.low, previous.available_at),
                ]
            )
        previous_ny = self._previous_ny_session(at)
        if previous_ny is not None:
            levels.extend(
                [
                    LiquidityLevel("PNYH", previous_ny.high, previous_ny.available_at),
                    LiquidityLevel("PNYL", previous_ny.low, previous_ny.available_at),
                ]
            )
        local_day = ny_date(at)
        asian = self.asian_sessions.get(local_day)
        if asian is not None and asian.available_at <= cutoff:
            levels.extend(
                [
                    LiquidityLevel("ASH", asian.high, asian.available_at),
                    LiquidityLevel("ASL", asian.low, asian.available_at),
                ]
            )
        pre_ny = self.pre_ny.get(local_day)
        if pre_ny is not None:
            pre_ny_cutoff = min(cutoff, pre_ny[3])
            index = int(pre_ny[0].searchsorted(pd.Timestamp(pre_ny_cutoff), side="right") - 1)
        else:
            index = -1
        if pre_ny is not None and index >= 0:
            available_at = pd.Timestamp(pre_ny[0][index]).to_pydatetime()
            levels.extend(
                [
                    LiquidityLevel("PRE_NY_H", float(pre_ny[1][index]), available_at),
                    LiquidityLevel("PRE_NY_L", float(pre_ny[2][index]), available_at),
                ]
            )
        return [self._with_state(at, level) for level in levels]

    def target_prices(self, at: datetime, *, above: float | None = None, below: float | None = None) -> list[float]:
        prices = [
            level.price
            for level in self.levels_at(at)
            if level.state is LiquidityState.INTACT
        ]
        if above is not None:
            return sorted(price for price in prices if price > above)
        if below is not None:
            return sorted((price for price in prices if price < below), reverse=True)
        return prices
