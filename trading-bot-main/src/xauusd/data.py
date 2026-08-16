from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path

import pandas as pd

from .config import StrategyConfig
from .indicators import enrich_bars


TIMEFRAME_MINUTES = {"M1": 1, "M5": 5, "M15": 15, "H1": 60, "H4": 240}


@dataclass(frozen=True)
class MarketData:
    m1: pd.DataFrame
    m5: pd.DataFrame
    m15: pd.DataFrame
    h1: pd.DataFrame
    h4: pd.DataFrame

    def by_name(self, timeframe: str) -> pd.DataFrame:
        return getattr(self, timeframe.lower())


def load_rates(path: str | Path, timeframe: str, config: StrategyConfig) -> pd.DataFrame:
    if timeframe not in TIMEFRAME_MINUTES:
        raise ValueError(f"Unsupported timeframe: {timeframe}")
    bars = pd.read_csv(path, parse_dates=["time"])
    if bars.empty:
        raise ValueError(f"No rates in {path}")
    bars["time"] = pd.to_datetime(bars["time"], utc=True)
    bars = bars.sort_values("time").drop_duplicates("time").set_index("time")
    numeric = ["open", "high", "low", "close", "tick_volume", "spread", "real_volume"]
    for column in numeric:
        if column in bars:
            bars[column] = pd.to_numeric(bars[column], errors="raise")
    if not bars.index.is_monotonic_increasing or not bars.index.is_unique:
        raise ValueError(f"Rates are not ordered and unique in {path}")
    duration = timedelta(minutes=TIMEFRAME_MINUTES[timeframe])
    bars["close_time"] = bars.index + duration
    ema_periods: tuple[int, ...] = ()
    if timeframe == "H4":
        ema_periods = (config.ema_fast, config.ema_slow, config.ema_macro)
    elif timeframe == "H1" and config.use_ema_h1:
        ema_periods = (config.ema_fast,)
    return enrich_bars(
        bars,
        ema_periods=ema_periods,
        max_gap_atr=config.max_gap_atr,
        gap_suspend_bars=config.gap_suspend_bars,
    )


def load_market_data(directory: str | Path, symbol: str, config: StrategyConfig) -> MarketData:
    base = Path(directory)
    frames = {
        timeframe.lower(): load_rates(base / f"{symbol}_{timeframe}.csv", timeframe, config)
        for timeframe in TIMEFRAME_MINUTES
    }
    return MarketData(**frames)
