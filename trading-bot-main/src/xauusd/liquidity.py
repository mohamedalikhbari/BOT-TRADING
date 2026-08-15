from __future__ import annotations

from dataclasses import replace
import math

import pandas as pd

from .domain import Direction, LiquidityLevel, LiquidityState, SweepEvent


_LOW_POOLS = {"ASL", "PNYL", "PDL", "PRE_NY_L"}
_HIGH_POOLS = {"ASH", "PNYH", "PDH", "PRE_NY_H"}


def candle_sweeps_level(
    row: pd.Series,
    level: LiquidityLevel,
    direction: Direction,
    *,
    min_sweep_atr: float,
    min_wick_ratio: float,
) -> bool:
    """Return whether one closed candle rejects one pool per specification 2.12."""
    if level.state is LiquidityState.SWEPT or not bool(row.get("quality_ok", True)):
        return False
    high = float(row["high"])
    low = float(row["low"])
    close = float(row["close"])
    atr = float(row["atr"])
    candle_range = high - low
    if candle_range <= 0 or not math.isfinite(atr) or atr <= 0:
        return False
    if direction is Direction.LONG and level.name in _LOW_POOLS:
        penetration = level.price - low
        wick_ratio = (close - low) / candle_range
        return (
            low < level.price
            and close > level.price
            and penetration >= min_sweep_atr * atr
            and wick_ratio >= min_wick_ratio
        )
    if direction is Direction.SHORT and level.name in _HIGH_POOLS:
        penetration = high - level.price
        wick_ratio = (high - close) / candle_range
        return (
            high > level.price
            and close < level.price
            and penetration >= min_sweep_atr * atr
            and wick_ratio >= min_wick_ratio
        )
    return False


def swept_levels(
    row: pd.Series,
    levels: list[LiquidityLevel] | tuple[LiquidityLevel, ...],
    direction: Direction,
    *,
    min_sweep_atr: float,
    min_wick_ratio: float,
) -> tuple[LiquidityLevel, ...]:
    """Keep every intact pool swept by the same candle, preserving book order."""
    return tuple(
        level
        for level in levels
        if candle_sweeps_level(
            row,
            level,
            direction,
            min_sweep_atr=min_sweep_atr,
            min_wick_ratio=min_wick_ratio,
        )
    )


def confirm_sweep_on_m5(
    event: SweepEvent,
    m5_bars: pd.DataFrame,
    *,
    min_sweep_atr: float,
    min_wick_ratio: float,
) -> SweepEvent | None:
    """Confirm the M15 event on its three constituent, already-closed M5 bars."""
    if len(m5_bars) != 3:
        return None
    confirmed: list[LiquidityLevel] = []
    qualifying_extremes: list[float] = []
    for level in event.levels:
        matches = [
            row
            for _, row in m5_bars.iterrows()
            if candle_sweeps_level(
                row,
                level,
                event.direction,
                min_sweep_atr=min_sweep_atr,
                min_wick_ratio=min_wick_ratio,
            )
        ]
        if not matches:
            continue
        confirmed.append(level)
        if event.direction is Direction.LONG:
            qualifying_extremes.extend(float(row["low"]) for row in matches)
        else:
            qualifying_extremes.extend(float(row["high"]) for row in matches)
    if not confirmed:
        return None
    extreme = (
        min(qualifying_extremes)
        if event.direction is Direction.LONG
        else max(qualifying_extremes)
    )
    return replace(
        event,
        levels=tuple(confirmed),
        extreme=extreme,
        confirmed_m5=True,
    )


def score_swept_pools(levels: tuple[LiquidityLevel, ...]) -> dict[str, int]:
    """Return section 4.3 pool points for levels confirmed on both timeframes."""
    groups = {
        "PRE_NY" if level.name in {"PRE_NY_H", "PRE_NY_L"} else level.name[:-1]
        for level in levels
    }
    score: dict[str, int] = {}
    if "PNY" in groups:
        score["sweep_previous_ny"] = 3
    if "PD" in groups:
        score["sweep_previous_day"] = 3
    if "AS" in groups:
        score["sweep_asian_session"] = 2
    if "PRE_NY" in groups:
        score["sweep_pre_ny"] = 1
    if len({(level.name, round(level.price, 8)) for level in levels}) >= 2:
        score["sweep_multiple_pools"] = 2
    return score
