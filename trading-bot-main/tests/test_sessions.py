from __future__ import annotations

from datetime import date, datetime, timezone

import pandas as pd

from xauusd.domain import LiquidityState
from xauusd.sessions import LiquidityBook, in_trading_window, ny_open, trading_day_label


def test_ny_window_winter_dst():
    assert ny_open(date(2026, 1, 15)).hour == 14
    assert ny_open(date(2026, 1, 15)).minute == 30


def test_ny_window_summer_dst():
    assert ny_open(date(2026, 7, 15)).hour == 13
    assert ny_open(date(2026, 7, 15)).minute == 30


def test_ny_window_us_eu_dst_mismatch():
    # The conversion is anchored to New York, independent of Europe's DST date.
    assert ny_open(date(2026, 3, 20)).hour == 13
    assert in_trading_window(datetime(2026, 3, 20, 12, 30, tzinfo=timezone.utc))


def test_previous_day_and_pre_ny_calculation_without_lookahead():
    index = pd.date_range("2026-07-13T00:00:00Z", "2026-07-15T14:00:00Z", freq="1min")
    frame = pd.DataFrame({"high": 100.0, "low": 90.0}, index=index)
    book = LiquidityBook(frame)
    before_open = datetime(2026, 7, 15, 13, 0, tzinfo=timezone.utc)
    after_open = datetime(2026, 7, 15, 13, 31, tzinfo=timezone.utc)
    early_levels = book.levels_at(before_open, as_of=before_open)
    assert any(level.name.startswith("PRE_NY") for level in early_levels)
    assert all(level.available_at <= before_open for level in early_levels)
    assert any(level.name.startswith("PRE_NY") for level in book.levels_at(after_open))


def test_multiple_pool_tracking():
    index = pd.date_range("2026-07-13T00:00:00Z", "2026-07-15T13:15:00Z", freq="1min")
    frame = pd.DataFrame({"high": 100.0, "low": 90.0}, index=index)
    book = LiquidityBook(frame)
    at = datetime(2026, 7, 15, 13, 15, tzinfo=timezone.utc)

    levels = book.levels_at(at)
    assert {level.name for level in levels} == {
        "ASH",
        "ASL",
        "PNYH",
        "PNYL",
        "PDH",
        "PDL",
        "PRE_NY_H",
        "PRE_NY_L",
    }
    swept = tuple(level for level in levels if level.name in {"PNYL", "PDL"})
    book.mark_swept(at, swept)
    states = {level.name: level.state for level in book.levels_at(at)}
    assert states["PNYL"] is LiquidityState.SWEPT
    assert states["PDL"] is LiquidityState.SWEPT
    assert states["ASL"] is LiquidityState.INTACT


def test_trading_day_rolls_at_17_new_york():
    before = datetime(2026, 7, 15, 20, 59, tzinfo=timezone.utc)
    after = datetime(2026, 7, 15, 21, 1, tzinfo=timezone.utc)
    assert trading_day_label(after) > trading_day_label(before)
