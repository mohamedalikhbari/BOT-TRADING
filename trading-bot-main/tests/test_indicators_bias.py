from __future__ import annotations

from dataclasses import replace

import numpy as np
import pandas as pd

from xauusd.bias import BiasEngine
from xauusd.config import StrategyConfig
from xauusd.domain import StructureSnapshot, Trend
from xauusd.indicators import atr, ema, enrich_bars


class FakeStructure:
    def __init__(self, trend=Trend.BULLISH):
        self.trend = trend

    def snapshot(self, at):
        return StructureSnapshot(at, None, None, None, None, self.trend, None)

    def recent_events(self, *args, **kwargs):
        return []

    def reference_leg(self, *args, **kwargs):
        return None


class FibonacciForbiddenStructure(FakeStructure):
    def reference_leg(self, *args, **kwargs):
        raise AssertionError("H4 Fibonacci must not be evaluated")


def trend_bars(flat=False):
    index = pd.date_range("2025-01-01", periods=220, freq="4h", tz="UTC")
    close = np.full(len(index), 100.0) if flat else 100 + np.arange(len(index)) * 0.25
    frame = pd.DataFrame(
        {
            "open": close - 0.1,
            "high": close + 0.5,
            "low": close - 0.5,
            "close": close,
            "tick_volume": 100,
            "spread": 20,
        },
        index=index,
    )
    frame["close_time"] = frame.index + pd.Timedelta(hours=4)
    return enrich_bars(frame, ema_periods=(21, 50, 200))


def test_ema_calculation_matches_reference():
    values = pd.Series([1.0, 2.0, 3.0, 4.0])
    assert ema(values, 2).iloc[-1] == values.ewm(span=2, adjust=False, min_periods=2).mean().iloc[-1]


def test_atr_warmup_and_reference():
    frame = trend_bars()
    calculated = atr(frame)
    assert calculated.iloc[:13].isna().all()
    assert calculated.iloc[-1] > 0


def test_ema_warmup_blocks_bias():
    h4 = trend_bars()
    fake = FakeStructure()
    engine = BiasEngine(h4, h4, fake, fake, StrategyConfig())
    result = engine.evaluate(h4.iloc[20].close_time.to_pydatetime(), float(h4.iloc[20].close))
    assert result.direction is None
    assert result.reason == "ema_warmup"


def test_ema_alignment_long_and_slope_normalization():
    h4 = trend_bars()
    fake = FakeStructure()
    engine = BiasEngine(h4, h4, fake, fake, StrategyConfig())
    result = engine.evaluate(h4.iloc[-1].close_time.to_pydatetime(), float(h4.iloc[-1].close))
    assert result.direction.value == "LONG"
    assert result.slope > 0.05


def test_ema_flat_blocks_operation():
    h4 = trend_bars(flat=True)
    fake = FakeStructure()
    config = replace(StrategyConfig(), h4_bias_mode="EMA_AND_STRUCTURE")
    engine = BiasEngine(h4, h4, fake, fake, config)
    result = engine.evaluate(h4.iloc[-1].close_time.to_pydatetime(), 100)
    assert result.direction is None
    assert result.reason == "ema_alignment"


def test_structure_only_bias_allows_flat_ema_when_structure_trends():
    h4 = trend_bars(flat=True)
    fake = FakeStructure()
    engine = BiasEngine(h4, h4, fake, fake, StrategyConfig())
    result = engine.evaluate(h4.iloc[-1].close_time.to_pydatetime(), 100)
    assert result.direction.value == "LONG"


def test_ema_macro_filter_toggle():
    config = replace(StrategyConfig(), use_ema_macro=True)
    h4 = trend_bars()
    fake = FakeStructure()
    engine = BiasEngine(h4, h4, fake, fake, config)
    result = engine.evaluate(h4.iloc[-1].close_time.to_pydatetime(), float(h4.iloc[-1].close))
    assert result.direction is None or result.direction.value == "LONG"


def test_structure_ranging_vetoes_ema_bias():
    h4 = trend_bars()
    fake = FakeStructure(Trend.RANGING)
    engine = BiasEngine(h4, h4, fake, fake, StrategyConfig())
    result = engine.evaluate(h4.iloc[-1].close_time.to_pydatetime(), float(h4.iloc[-1].close))
    assert result.direction is None
    assert result.reason == "h4_ranging"


def test_h4_bias_does_not_depend_on_fibonacci():
    h4 = trend_bars()
    fake = FibonacciForbiddenStructure()
    engine = BiasEngine(h4, h4, fake, fake, StrategyConfig())
    result = engine.evaluate(h4.iloc[-1].close_time.to_pydatetime(), 1.0)
    assert result.direction.value == "LONG"
