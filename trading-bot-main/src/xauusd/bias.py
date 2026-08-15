from __future__ import annotations

from bisect import bisect_right
from datetime import datetime
import math

import pandas as pd

from .config import StrategyConfig
from .domain import (
    BiasResult,
    Direction,
    StructureEventKind,
    Trend,
)
from .structure import StructureTimeline


class BiasEngine:
    def __init__(
        self,
        h4: pd.DataFrame,
        h1: pd.DataFrame,
        h4_structure: StructureTimeline,
        h1_structure: StructureTimeline,
        config: StrategyConfig,
    ):
        self.h4 = h4
        self.h1 = h1
        self.h4_structure = h4_structure
        self.h1_structure = h1_structure
        self.config = config
        self._h4_close_times = [pd.Timestamp(value).to_pydatetime() for value in h4["close_time"]]
        self._h1_close_times = [pd.Timestamp(value).to_pydatetime() for value in h1["close_time"]]

    def _h4_index(self, at: datetime) -> int:
        return bisect_right(self._h4_close_times, at) - 1

    def _h1_index(self, at: datetime) -> int:
        return bisect_right(self._h1_close_times, at) - 1

    def evaluate(self, at: datetime, price: float) -> BiasResult:
        index = self._h4_index(at)
        warmup = (self.config.ema_macro if self.config.use_ema_macro else self.config.ema_slow) * 3
        if index < warmup - 1 or index < self.config.ema_slope_lookback:
            return BiasResult(None, at, reason="ema_warmup")
        row = self.h4.iloc[index]
        previous = self.h4.iloc[index - self.config.ema_slope_lookback]
        if not bool(row.get("quality_ok", True)):
            return BiasResult(None, at, reason="data_quality")
        fast = float(row[f"ema_{self.config.ema_fast}"])
        slow = float(row[f"ema_{self.config.ema_slow}"])
        macro = float(row[f"ema_{self.config.ema_macro}"])
        atr = float(row["atr"])
        if not all(math.isfinite(value) for value in (fast, slow, atr)) or atr <= 0:
            return BiasResult(None, at, reason="indicator_unavailable")
        slope = (slow - float(previous[f"ema_{self.config.ema_slow}"])) / (
            atr * self.config.ema_slope_lookback
        )
        close = float(row["close"])
        direction: Direction | None = None
        if self.config.h4_bias_mode == "EMA_AND_STRUCTURE":
            if close > fast > slow and slope > self.config.min_ema_slope:
                direction = Direction.LONG
            elif close < fast < slow and slope < -self.config.min_ema_slope:
                direction = Direction.SHORT
            if direction is None:
                return BiasResult(None, at, fast, slow, macro, slope, reason="ema_alignment")
        if self.config.h4_bias_mode == "EMA_AND_STRUCTURE" and self.config.use_ema_macro:
            if (direction is Direction.LONG and close <= macro) or (
                direction is Direction.SHORT and close >= macro
            ):
                return BiasResult(None, at, fast, slow, macro, slope, reason="ema_macro")

        evaluated_at = self._h4_close_times[index]
        structure = self.h4_structure.snapshot(evaluated_at)
        if structure.trend is Trend.RANGING:
            return BiasResult(None, at, fast, slow, macro, slope, reason="h4_ranging")
        if self.config.h4_bias_mode == "STRUCTURE_ONLY":
            direction = structure.trend.direction
        elif structure.trend.direction is not direction:
            return BiasResult(None, at, fast, slow, macro, slope, reason="h4_structure_opposed")
        assert direction is not None
        contrary_choch = self.h4_structure.recent_events(
            evaluated_at,
            bars=3,
            kind=StructureEventKind.CHOCH,
            direction=direction.opposite,
        )
        if contrary_choch:
            return BiasResult(None, at, fast, slow, macro, slope, reason="h4_choch_veto")

        return BiasResult(
            direction=direction,
            evaluated_at=evaluated_at,
            ema_fast=fast,
            ema_slow=slow,
            ema_macro=macro,
            slope=slope,
            reason="ok",
        )

    def h1_confirms(self, at: datetime, direction: Direction, price: float) -> tuple[bool, str]:
        index = self._h1_index(at)
        if index < 1:
            return False, "h1_warmup"
        evaluated_at = self._h1_close_times[index]
        row = self.h1.iloc[index]
        if not bool(row.get("quality_ok", True)):
            return False, "h1_data_quality"
        snapshot = self.h1_structure.snapshot(evaluated_at)
        if snapshot.trend.direction is not direction:
            return False, "h1_trend"
        if self.config.h1_confirmation_mode == "STRICT_BOS":
            if (
                snapshot.latest_event is None
                or snapshot.latest_event.kind is not StructureEventKind.BOS
                or snapshot.latest_event.direction is not direction
            ):
                return False, "h1_last_event"
        if self.h1_structure.recent_events(
            evaluated_at,
            bars=5,
            kind=StructureEventKind.CHOCH,
            direction=direction.opposite,
        ):
            return False, "h1_choch"
        if direction is Direction.LONG and snapshot.last_low and price < snapshot.last_low.price:
            return False, "h1_swing_violation"
        if direction is Direction.SHORT and snapshot.last_high and price > snapshot.last_high.price:
            return False, "h1_swing_violation"
        if self.config.use_ema_h1:
            ema = float(row[f"ema_{self.config.ema_fast}"])
            close = float(row["close"])
            if (direction is Direction.LONG and close <= ema) or (
                direction is Direction.SHORT and close >= ema
            ):
                return False, "h1_ema"
        return True, "ok"
