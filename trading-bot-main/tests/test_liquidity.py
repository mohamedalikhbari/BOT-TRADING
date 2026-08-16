from __future__ import annotations

from datetime import datetime, timezone

import pandas as pd

from xauusd.domain import Direction, LiquidityLevel, SweepEvent
from xauusd.liquidity import confirm_sweep_on_m5, score_swept_pools, swept_levels


AT = datetime(2026, 7, 15, 14, 0, tzinfo=timezone.utc)


def _row(*, high: float, low: float, close: float, atr: float = 1.0) -> pd.Series:
    return pd.Series(
        {
            "open": close,
            "high": high,
            "low": low,
            "close": close,
            "atr": atr,
            "quality_ok": True,
        }
    )


def _m15_event() -> SweepEvent:
    levels = (
        LiquidityLevel("PDL", 100.0, AT),
        LiquidityLevel("ASL", 100.2, AT),
    )
    row = _row(high=102.0, low=99.7, close=101.0, atr=2.0)
    confirmed_m15 = swept_levels(
        row,
        levels,
        Direction.LONG,
        min_sweep_atr=0.10,
        min_wick_ratio=0.50,
    )
    return SweepEvent(
        Direction.LONG,
        confirmed_m15,
        AT,
        99.7,
        102.0,
        99.7,
        101.0,
        confirmed_m15=True,
    )


def test_sweep_confirmation_both_timeframes():
    event = _m15_event()
    bars = pd.DataFrame(
        [
            _row(high=100.6, low=99.7, close=100.3),
            _row(high=101.0, low=100.3, close=100.8),
            _row(high=101.2, low=100.7, close=101.0),
        ]
    )
    confirmed = confirm_sweep_on_m5(
        event,
        bars,
        min_sweep_atr=0.10,
        min_wick_ratio=0.50,
    )
    assert confirmed is not None
    assert confirmed.confirmed_m15 is True
    assert confirmed.confirmed_m5 is True
    assert {level.name for level in confirmed.levels} == {"PDL", "ASL"}
    assert confirmed.extreme == 99.7


def test_sweep_m15_ok_m5_fail_rejects_setup():
    event = _m15_event()
    bars = pd.DataFrame(
        [
            _row(high=100.4, low=99.95, close=100.1),
            _row(high=100.7, low=100.25, close=100.5),
            _row(high=101.2, low=100.4, close=101.0),
        ]
    )
    assert (
        confirm_sweep_on_m5(
            event,
            bars,
            min_sweep_atr=0.10,
            min_wick_ratio=0.50,
        )
        is None
    )


def test_multi_pool_sweep_scoring():
    levels = tuple(
        LiquidityLevel(name, 100.0, AT)
        for name in ("PNYL", "PDL", "ASL", "PRE_NY_L")
    )
    score = score_swept_pools(levels)
    assert score == {
        "sweep_previous_ny": 3,
        "sweep_previous_day": 3,
        "sweep_asian_session": 2,
        "sweep_pre_ny": 1,
        "sweep_multiple_pools": 2,
    }
    assert sum(score.values()) == 11
