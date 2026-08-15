from __future__ import annotations

import numpy as np
import pandas as pd


def true_range(bars: pd.DataFrame) -> pd.Series:
    previous_close = bars["close"].shift(1)
    values = pd.concat(
        [
            bars["high"] - bars["low"],
            (bars["high"] - previous_close).abs(),
            (bars["low"] - previous_close).abs(),
        ],
        axis=1,
    )
    return values.max(axis=1)


def atr(bars: pd.DataFrame, period: int = 14) -> pd.Series:
    """Wilder ATR, with no value exposed before a complete warm-up."""
    return true_range(bars).ewm(
        alpha=1.0 / period,
        adjust=False,
        min_periods=period,
    ).mean()


def ema(values: pd.Series, period: int) -> pd.Series:
    return values.ewm(span=period, adjust=False, min_periods=period).mean()


def enrich_bars(
    bars: pd.DataFrame,
    *,
    ema_periods: tuple[int, ...] = (),
    max_gap_atr: float = 3.0,
    gap_suspend_bars: int = 3,
) -> pd.DataFrame:
    enriched = bars.copy()
    enriched["atr"] = atr(enriched)
    for period in ema_periods:
        enriched[f"ema_{period}"] = ema(enriched["close"], period)

    gap = (enriched["open"] - enriched["close"].shift(1)).abs()
    bad = (enriched.get("tick_volume", 1) <= 0) | (
        gap > max_gap_atr * enriched["atr"].shift(1)
    )
    suspended = np.zeros(len(enriched), dtype=bool)
    for index in np.flatnonzero(bad.fillna(False).to_numpy()):
        suspended[index : min(index + gap_suspend_bars + 1, len(enriched))] = True
    enriched["quality_ok"] = ~suspended
    return enriched

