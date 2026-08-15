from __future__ import annotations

from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
import math
from typing import Any

import numpy as np
import pandas as pd

from .bias import BiasEngine
from .config import AppConfig
from .data import MarketData
from .domain import (
    BiasResult,
    Direction,
    OrderPlan,
    Position,
    SetupState,
    StructureEventKind,
    SweepEvent,
    TradeRecord,
    Zone,
    ZoneState,
    new_setup_id,
)
from .liquidity import confirm_sweep_on_m5, score_swept_pools, swept_levels
from .news import NewsCalendar
from .risk import RiskManager
from .sessions import (
    LiquidityBook,
    in_trading_window,
    must_force_close,
    ny_date,
    setup_deadline,
)
from .structure import StructureTimeline
from .zones import build_zone_seeds, entry_price, invalidated, score_zone


@dataclass
class SetupContext:
    state: SetupState = SetupState.IDLE
    bias: BiasResult | None = None
    sweep: SweepEvent | None = None
    reaction_extreme: float | None = None
    sweep_confirmed_at: datetime | None = None
    m5_fib_position: str | None = None
    entry_zone_low: float | None = None
    entry_zone_high: float | None = None
    entry_armed_at: datetime | None = None
    candidate: Zone | None = None
    candidate_base_score: int = -10_000
    pending: OrderPlan | None = None

    def clear(self) -> None:
        self.__dict__.update(SetupContext().__dict__)


@dataclass(frozen=True)
class BacktestResult:
    trades: list[TradeRecord]
    diagnostics: dict[str, int]
    metrics: dict[str, Any]


def _python_time(value: Any) -> datetime:
    return pd.Timestamp(value).to_pydatetime()


class Backtester:
    def __init__(
        self,
        data: MarketData,
        config: AppConfig,
        news: NewsCalendar,
    ):
        self.data = data
        self.config = config
        self.strategy = config.strategy
        self.news = news
        self.risk = RiskManager(config.risk, config.broker)
        self.liquidity = LiquidityBook(data.m1)
        self.diagnostics: defaultdict[str, int] = defaultdict(int)
        self.trades: list[TradeRecord] = []
        self.setup = SetupContext()
        self.position: Position | None = None

        # Lower-timeframe structure needs only a short pre-roll; higher-timeframe
        # engines retain the full exported warm-up range.
        pre_roll = config.backtest.start - timedelta(days=14)
        self._m1_structure_bars = data.m1[data.m1["close_time"] >= pre_roll]
        self.structures = {
            "M5": StructureTimeline(
                data.m5, self.strategy.k_m5, self.strategy.min_break_atr
            ),
            "M15": StructureTimeline(
                data.m15, self.strategy.k_m15, self.strategy.min_break_atr
            ),
            "H1": StructureTimeline(
                data.h1, self.strategy.k_h1, self.strategy.min_break_atr
            ),
            "H4": StructureTimeline(
                data.h4, self.strategy.k_h4, self.strategy.min_break_atr
            ),
        }
        self.bias_engine = BiasEngine(
            data.h4,
            data.h1,
            self.structures["H4"],
            self.structures["H1"],
            self.strategy,
        )

        self.m1_zones: list[Zone] = []
        self.m5_zones = build_zone_seeds(
            data.m5,
            "M5",
            self.strategy.min_fvg_atr_m5,
            self.strategy.ifvg_max_age_m5,
            5,
            self.strategy.min_impulse_atr,
        )
        self.m15_zones = build_zone_seeds(
            data.m15,
            "M15",
            self.strategy.min_fvg_atr_m5,
            self.strategy.ifvg_max_age_m5,
            15,
            self.strategy.min_impulse_atr,
        )
        self._m1_zones_at: dict[datetime, list[Zone]] = {}
        self._m5_zones_at = self._group_zones(self.m5_zones)
        self._m15_zones_at = self._group_zones(self.m15_zones)
        self._m5_index_at = {
            _python_time(value): index for index, value in enumerate(data.m5["close_time"])
        }
        self._m15_index_at = {
            _python_time(value): index for index, value in enumerate(data.m15["close_time"])
        }
        self._m1_index_at = {
            _python_time(value): index for index, value in enumerate(data.m1["close_time"])
        }

    @staticmethod
    def _group_zones(zones: list[Zone]) -> dict[datetime, list[Zone]]:
        result: defaultdict[datetime, list[Zone]] = defaultdict(list)
        for zone in zones:
            result[zone.created_at].append(zone)
        return dict(result)

    def _ensure_m1_analysis(self) -> None:
        if "M1" in self.structures:
            return
        self.structures["M1"] = StructureTimeline(
            self._m1_structure_bars,
            self.strategy.k_m1,
            self.strategy.min_break_atr,
        )
        zone_start = self.config.backtest.start - timedelta(days=2)
        bars = self.data.m1[self.data.m1["close_time"] >= zone_start]
        self.m1_zones = build_zone_seeds(
            bars,
            "M1",
            self.strategy.min_fvg_atr_m1,
            self.strategy.ifvg_max_age_m1,
            1,
            self.strategy.min_impulse_atr,
        )
        self._m1_zones_at = self._group_zones(self.m1_zones)
        self.diagnostics["m1_analysis_initialized"] += 1

    def _reset(self, reason: str) -> None:
        if self.setup.state is not SetupState.IDLE:
            self.diagnostics[f"reset:{reason}"] += 1
        self.setup.clear()

    def _detect_sweep(
        self, row: pd.Series, at: datetime, direction: Direction
    ) -> SweepEvent | None:
        # A M15 sweep may only use the liquidity range known before that candle
        # opened. The pre-NY range can therefore evolve without leaking its own
        # future high/low into the decision.
        levels = swept_levels(
            row,
            self.liquidity.levels_at(at, as_of=at - timedelta(minutes=15)),
            direction,
            min_sweep_atr=self.strategy.min_sweep_atr_m15,
            min_wick_ratio=self.strategy.min_wick_ratio_m15,
        )
        if not levels:
            return None
        extreme = float(row["low"] if direction is Direction.LONG else row["high"])
        return SweepEvent(
            direction,
            levels,
            at,
            extreme,
            float(row["high"]),
            float(row["low"]),
            float(row["close"]),
            confirmed_m15=True,
        )

    def _constituent_m5_bars(self, at: datetime) -> pd.DataFrame:
        start = pd.Timestamp(at - timedelta(minutes=15))
        end = pd.Timestamp(at)
        return self.data.m5[(self.data.m5.index >= start) & (self.data.m5.index < end)]

    def _on_m15_close(self, at: datetime) -> None:
        if self.position or self.setup.pending or self.setup.state is not SetupState.IDLE:
            return
        index = self._m15_index_at.get(at)
        if index is None or not in_trading_window(at):
            return
        self.diagnostics["m15_bars_in_window"] += 1
        row = self.data.m15.iloc[index]
        if self.news.is_blackout(at):
            self.diagnostics["veto:news_blackout"] += 1
            return
        bias = self.bias_engine.evaluate(at, float(row["close"]))
        if bias.direction is None:
            self.diagnostics[f"veto:bias:{bias.reason}"] += 1
            return
        self.diagnostics["bias_active"] += 1
        h1_ok, reason = self.bias_engine.h1_confirms(
            at, bias.direction, float(row["close"])
        )
        if not h1_ok:
            self.diagnostics[f"veto:h1:{reason}"] += 1
            return
        self.diagnostics["h1_confirmed"] += 1
        sweep = self._detect_sweep(row, at, bias.direction)
        if sweep is None:
            self.diagnostics["veto:no_sweep"] += 1
            return
        self.diagnostics["sweep_detected"] += 1
        for level in sweep.levels:
            self.diagnostics[f"sweep_m15_level:{level.name}"] += 1
        self.diagnostics[f"sweep_at:{sweep.occurred_at.isoformat()}"] += 1

        confirmed = confirm_sweep_on_m5(
            sweep,
            self._constituent_m5_bars(at),
            min_sweep_atr=self.strategy.min_sweep_atr_m5,
            min_wick_ratio=self.strategy.min_wick_ratio_m5,
        )
        if confirmed is None:
            self.diagnostics["veto:sweep_m5_unconfirmed"] += 1
            return
        if len(confirmed.levels) < len(sweep.levels):
            self.diagnostics["sweep_m5_partial_confirmation"] += 1
        for level in confirmed.levels:
            self.diagnostics[f"sweep_level:{level.name}"] += 1
        self.liquidity.mark_swept(at, confirmed.levels)
        self.diagnostics["sweep_confirmed_both_timeframes"] += 1

        self.setup.state = SetupState.SWEEP_CONFIRMED
        self.setup.bias = bias
        self.setup.sweep = confirmed
        self.setup.reaction_extreme = float(row["close"])
        self.setup.sweep_confirmed_at = at
        if self.strategy.m5_fib_mode == "OFF":
            self._arm_entry_from_reaction(
                at,
                min(confirmed.extreme, float(row["close"])),
                max(confirmed.extreme, float(row["close"])),
                "OFF",
            )

    def _arm_entry_from_reaction(
        self,
        at: datetime,
        low: float,
        high: float,
        fib_position: str,
    ) -> None:
        self._ensure_m1_analysis()
        self.setup.state = SetupState.ENTRY_ARMED
        self.setup.entry_zone_low = low
        self.setup.entry_zone_high = high
        self.setup.entry_armed_at = at
        self.setup.m5_fib_position = fib_position
        self.diagnostics["m5_fib_passed"] += 1

    def _on_m5_close(self, at: datetime) -> None:
        index = self._m5_index_at.get(at)
        if index is None or self.setup.sweep is None or self.setup.bias is None:
            return
        if at > setup_deadline(self.setup.sweep.occurred_at):
            self._reset("setup_deadline")
            return
        row = self.data.m5.iloc[index]
        direction = self.setup.bias.direction
        assert direction is not None

        if self.setup.state is not SetupState.SWEEP_CONFIRMED:
            return
        assert self.setup.sweep_confirmed_at is not None
        if at <= self.setup.sweep_confirmed_at:
            return
        if at > self.setup.sweep_confirmed_at + timedelta(hours=1):
            self._reset("m5_fib_timeout")
            return
        previous_extreme = float(self.setup.reaction_extreme)
        if direction is Direction.LONG:
            current_extreme = max(previous_extreme, float(row["high"]))
            self.setup.reaction_extreme = current_extreme
            size = current_extreme - self.setup.sweep.extreme
            fib_382 = current_extreme - size * 0.382
            fib_50 = current_extreme - size * 0.50
            fib_75 = current_extreme - size * 0.75
            fib_786 = current_extreme - size * 0.786
            beyond = float(row["low"]) < fib_786
            strict_touch = float(row["low"]) <= fib_50 and float(row["high"]) >= fib_75
            lenient_touch = float(row["low"]) <= fib_382 and float(row["high"]) >= fib_786
            made_new_extreme = current_extreme > previous_extreme
        else:
            current_extreme = min(previous_extreme, float(row["low"]))
            self.setup.reaction_extreme = current_extreme
            size = self.setup.sweep.extreme - current_extreme
            fib_382 = current_extreme + size * 0.382
            fib_50 = current_extreme + size * 0.50
            fib_75 = current_extreme + size * 0.75
            fib_786 = current_extreme + size * 0.786
            beyond = float(row["high"]) > fib_786
            strict_touch = float(row["high"]) >= fib_50 and float(row["low"]) <= fib_75
            lenient_touch = float(row["high"]) >= fib_382 and float(row["low"]) <= fib_786
            made_new_extreme = current_extreme < previous_extreme
        if beyond:
            self._reset("m5_beyond_786")
            return
        # A bar that establishes a new extreme and retraces through the zone has
        # ambiguous intrabar ordering in OHLC data. Reject it conservatively.
        if made_new_extreme:
            return
        if self.strategy.m5_fib_mode == "STRICT" and strict_touch:
            self._arm_entry_from_reaction(at, min(fib_50, fib_75), max(fib_50, fib_75), "IN_ZONE")
        elif self.strategy.m5_fib_mode == "LENIENT" and lenient_touch:
            position = "IN_ZONE" if strict_touch else "LENIENT_OUTSIDE"
            self._arm_entry_from_reaction(at, min(fib_382, fib_786), max(fib_382, fib_786), position)

    def _has_higher_tf_confluence(self, zone: Zone, at: datetime) -> bool:
        cutoff = at - timedelta(days=2)
        return any(
            candidate.direction is zone.direction
            and cutoff <= candidate.created_at <= at
            and candidate.overlaps(zone.bottom, zone.top)
            for candidate in self.m5_zones + self.m15_zones
        )

    def _context_score(self) -> dict[str, int]:
        assert self.setup.bias is not None and self.setup.sweep is not None
        score: dict[str, int] = {}
        slope = abs(float(self.setup.bias.slope or 0.0))
        if slope >= 2 * self.strategy.min_ema_slope:
            score["ema_slope_strong"] = 2
        elif slope >= self.strategy.min_ema_slope:
            score["ema_slope_valid"] = 1
        if self.strategy.use_ema_macro:
            score["ema_macro"] = 1
        if self.setup.m5_fib_position == "IN_ZONE":
            score["m5_fib_in_zone"] = 2
        elif self.setup.m5_fib_position == "LENIENT_OUTSIDE":
            score["m5_fib_lenient_penalty"] = -1
        score.update(score_swept_pools(self.setup.sweep.levels))
        return score

    def _select_target(
        self,
        at: datetime,
        direction: Direction,
        entry: float,
        stop_distance: float,
    ) -> float | None:
        candidates: list[float] = []
        if direction is Direction.LONG:
            candidates.extend(self.liquidity.target_prices(at, above=entry))
        else:
            candidates.extend(self.liquidity.target_prices(at, below=entry))
        m5_snapshot = self.structures["M5"].snapshot(at)
        if direction is Direction.LONG and m5_snapshot.last_high and m5_snapshot.last_high.price > entry:
            candidates.append(m5_snapshot.last_high.price)
        if direction is Direction.SHORT and m5_snapshot.last_low and m5_snapshot.last_low.price < entry:
            candidates.append(m5_snapshot.last_low.price)
        cutoff = at - timedelta(days=2)
        for zone in self.m5_zones + self.m15_zones:
            if not cutoff <= zone.created_at <= at or zone.direction is direction:
                continue
            if direction is Direction.LONG and zone.bottom > entry:
                candidates.append(zone.bottom)
            if direction is Direction.SHORT and zone.top < entry:
                candidates.append(zone.top)
        if not candidates:
            return None
        if self.strategy.target_mode == "FIRST_VALID_RR":
            candidates = [
                target
                for target in candidates
                if abs(target - entry) / stop_distance >= self.strategy.min_r_multiple
            ]
            if not candidates:
                return None
        return min(candidates) if direction is Direction.LONG else max(candidates)

    def _build_order(self, zone: Zone, row: pd.Series, at: datetime) -> OrderPlan | None:
        assert self.setup.bias is not None and self.setup.sweep is not None
        direction = self.setup.bias.direction
        assert direction is not None
        entry = entry_price(zone)
        atr = float(row["atr"])
        if not math.isfinite(atr):
            self.diagnostics["veto:order:no_atr"] += 1
            return None
        snapshot = self.structures["M1"].snapshot(at)
        buffer = self.strategy.sl_buffer_atr * atr
        if direction is Direction.LONG:
            candidates = [zone.bottom - buffer]
            if self.strategy.stop_mode == "SWEEP_ANCHORED":
                candidates.append(self.setup.sweep.extreme - buffer)
                if snapshot.last_low:
                    candidates.append(snapshot.last_low.price - buffer)
            elif (
                self.strategy.stop_mode == "LOCAL_STRUCTURE"
                and snapshot.last_low
                and self.setup.entry_armed_at
                and snapshot.last_low.confirmed_at >= self.setup.entry_armed_at
            ):
                candidates.append(snapshot.last_low.price - buffer)
            stop = min(candidates)
        else:
            candidates = [zone.top + buffer]
            if self.strategy.stop_mode == "SWEEP_ANCHORED":
                candidates.append(self.setup.sweep.extreme + buffer)
                if snapshot.last_high:
                    candidates.append(snapshot.last_high.price + buffer)
            elif (
                self.strategy.stop_mode == "LOCAL_STRUCTURE"
                and snapshot.last_high
                and self.setup.entry_armed_at
                and snapshot.last_high.confirmed_at >= self.setup.entry_armed_at
            ):
                candidates.append(snapshot.last_high.price + buffer)
            stop = max(candidates)
        stop_distance = abs(entry - stop)
        if stop_distance < self.strategy.min_sl_dollars:
            self.diagnostics["veto:order:sl_too_small"] += 1
            return None
        if stop_distance > self.strategy.max_sl_dollars:
            self.diagnostics["veto:order:sl_too_large"] += 1
            return None
        target = self._select_target(at, direction, entry, stop_distance)
        if target is None:
            self.diagnostics["veto:order:no_target"] += 1
            return None
        r_multiple = abs(target - entry) / stop_distance
        if r_multiple < self.strategy.min_r_multiple:
            self.diagnostics["veto:order:rr"] += 1
            return None
        breakdown = self._context_score()
        breakdown.update(score_zone(zone, self._has_higher_tf_confluence(zone, at)))
        breakdown["rr"] = 2 if r_multiple >= 3 else 1
        total_score = sum(breakdown.values())
        if total_score < self.strategy.min_setup_score:
            self.diagnostics["veto:order:score"] += 1
            return None
        spread = float(row["spread"]) * self.config.broker.point
        decision = self.risk.pre_trade_check(stop_distance=stop_distance, spread=spread)
        if not decision.approved:
            self.diagnostics[f"veto:risk:{decision.reason}"] += 1
            return None
        context = {
            "h4_trend": self.structures["H4"].snapshot(self.setup.bias.evaluated_at).trend.value,
            "h1_trend": self.structures["H1"].snapshot(at).trend.value,
            "h4_h1_aligned": True,
            "ema_fast_h4": self.setup.bias.ema_fast,
            "ema_slow_h4": self.setup.bias.ema_slow,
            "ema_slope_normalized": self.setup.bias.slope,
            "m5_fib_position": self.setup.m5_fib_position,
            "m5_reaction_extreme": self.setup.reaction_extreme,
            "sweep_level_type": [level.name for level in self.setup.sweep.levels],
            "sweep_level_price": [level.price for level in self.setup.sweep.levels],
            "sweep_extreme_price": self.setup.sweep.extreme,
            "sweep_timestamp": self.setup.sweep.occurred_at.isoformat(),
            "sweep_confirmed_m15": self.setup.sweep.confirmed_m15,
            "sweep_confirmed_m5": self.setup.sweep.confirmed_m5,
            "zone_type": zone.zone_type.value,
            "zone_bottom": zone.bottom,
            "zone_top": zone.top,
            "spread_at_signal": spread,
            "atr_m1": atr,
            "news_events_next_4h": [event.name for event in self.news.next_events(at)],
            "equity_before": self.risk.equity,
        }
        return OrderPlan(
            new_setup_id(),
            direction,
            at,
            at + timedelta(minutes=15),
            entry,
            stop,
            target,
            decision.volume,
            decision.risk_amount,
            r_multiple,
            total_score,
            breakdown,
            zone,
            self.setup.sweep,
            context,
        )

    def _on_m1_close_for_signal(self, row: pd.Series, at: datetime) -> None:
        if self.setup.state is not SetupState.ENTRY_ARMED:
            return
        assert self.setup.entry_armed_at is not None
        assert self.setup.bias is not None
        direction = self.setup.bias.direction
        assert direction is not None
        if at > self.setup.entry_armed_at + timedelta(
            minutes=self.strategy.entry_timeout_minutes
        ):
            self._reset("entry_timeout")
            return
        if at > setup_deadline(self.setup.entry_armed_at):
            self._reset("entry_deadline")
            return
        if any(
            event.kind is StructureEventKind.CHOCH and event.direction is direction.opposite
            for event in self.structures["M1"].events_at(at)
        ):
            self._reset("m1_choch")
            return
        if self.setup.candidate and invalidated(self.setup.candidate, float(row["close"])):
            self.setup.candidate = None
            self.setup.candidate_base_score = -10_000

        for zone in self._m1_zones_at.get(at, []):
            if zone.direction is not direction or zone.created_at <= self.setup.entry_armed_at:
                continue
            if zone.expires_at and zone.expires_at < at:
                continue
            if not zone.overlaps(float(self.setup.entry_zone_low), float(self.setup.entry_zone_high)):
                continue
            base = sum(score_zone(zone, self._has_higher_tf_confluence(zone, at)).values())
            self.diagnostics["m1_zone_found"] += 1
            if base > self.setup.candidate_base_score:
                self.setup.candidate = zone
                self.setup.candidate_base_score = base

        if self.setup.candidate is None:
            return
        bos = any(
            event.kind is StructureEventKind.BOS and event.direction is direction
            for event in self.structures["M1"].events_at(at)
        )
        zone_ready = self.setup.candidate.created_at == at
        displacement = False
        current_index = self._m1_index_at.get(at)
        if current_index is not None and current_index > 0:
            previous = self.data.m1.iloc[current_index - 1]
            body = abs(float(row["close"]) - float(row["open"]))
            atr = float(row["atr"])
            if direction is Direction.LONG:
                displacement = (
                    float(row["close"]) > float(row["open"])
                    and float(row["close"]) > float(previous["high"])
                    and body >= self.strategy.min_m1_displacement_atr * atr
                )
            else:
                displacement = (
                    float(row["close"]) < float(row["open"])
                    and float(row["close"]) < float(previous["low"])
                    and body >= self.strategy.min_m1_displacement_atr * atr
                )
        trigger_name: str | None = None
        if (
            self.strategy.m1_trigger_mode == "BOS"
            and bos
            and at > self.setup.candidate.created_at
        ):
            trigger_name = "bos"
        elif self.strategy.m1_trigger_mode == "ZONE_READY" and zone_ready:
            trigger_name = "zone_ready"
        elif self.strategy.m1_trigger_mode == "DISPLACEMENT" and displacement:
            trigger_name = "displacement"
        if trigger_name is None:
            return
        self.diagnostics[f"m1_trigger:{trigger_name}"] += 1
        order = self._build_order(self.setup.candidate, row, at)
        if order is None:
            return
        self.setup.pending = order
        self.setup.state = SetupState.ORDER_PENDING
        self.diagnostics["orders_placed"] += 1

    def _try_fill(self, row: pd.Series, at: datetime) -> bool:
        order = self.setup.pending
        if order is None:
            return False
        if at > order.expires_at:
            self._reset("order_expired")
            return False
        if self.news.is_blackout(at):
            self._reset("order_news_blackout")
            return False
        spread = float(row["spread"]) * self.config.broker.point
        if spread > self.config.risk.max_spread:
            self.diagnostics["pending_spread_block"] += 1
            return False
        if order.direction is Direction.LONG:
            filled = float(row["low"]) + spread <= order.entry
        else:
            filled = float(row["high"]) >= order.entry
        if not filled:
            return False
        self.position = Position(order, at, order.entry)
        self.position.order.context["spread_at_entry"] = spread
        self.risk.register_entry()
        self.setup.pending = None
        self.setup.state = SetupState.IN_POSITION
        self.diagnostics["orders_filled"] += 1
        return True

    def _realize(self, position: Position, price: float, fraction: float) -> None:
        fraction = min(fraction, position.remaining_fraction)
        if fraction <= 0:
            return
        volume = position.order.volume * fraction
        gross = (
            position.order.direction.sign
            * (price - position.entry_actual)
            * self.config.broker.contract_size
            * volume
        )
        commission = self.config.broker.commission_per_lot_round_turn * volume
        pnl = gross - commission
        position.realized_pnl += pnl
        position.realized_r += pnl / position.order.initial_risk_amount
        position.remaining_fraction -= fraction

    def _finish_position(self, at: datetime, exit_price: float, reason: str) -> None:
        assert self.position is not None
        position = self.position
        self._realize(position, exit_price, position.remaining_fraction)
        duration = int((at - position.entry_at).total_seconds() // 60)
        context = dict(position.order.context)
        context["equity_after"] = self.risk.equity + position.realized_pnl
        record = TradeRecord(
            setup_id=position.order.setup_id,
            direction=position.order.direction,
            signal_at=position.order.created_at,
            entry_at=position.entry_at,
            exit_at=at,
            entry_planned=position.order.entry,
            entry_actual=position.entry_actual,
            exit_price=exit_price,
            stop_initial=position.order.stop,
            target=position.order.target,
            volume=position.order.volume,
            risk_amount=position.order.initial_risk_amount,
            r_multiple_planned=position.order.r_multiple,
            setup_score=position.order.score,
            score_breakdown=position.order.score_breakdown,
            pnl_dollars=position.realized_pnl,
            pnl_r=position.realized_r,
            mae=position.mae,
            mfe=position.mfe,
            duration_minutes=duration,
            exit_reason=reason,
            spread_at_entry=float(position.order.context.get("spread_at_entry", 0.0)),
            context=context,
        )
        self.trades.append(record)
        self.risk.register_trade(position.realized_pnl)
        self.diagnostics[f"exit:{reason}"] += 1
        self.position = None
        self.setup.clear()

    def _update_trailing(self, at: datetime, current_close: float, spread: float) -> None:
        if self.position is None or self.position.stage < 2:
            return
        snapshot = self.structures["M5"].snapshot(at)
        if self.position.order.direction is Direction.LONG and snapshot.last_low:
            if snapshot.last_low.price < current_close:
                self.position.stop_current = max(
                    float(self.position.stop_current), snapshot.last_low.price
                )
        if self.position.order.direction is Direction.SHORT and snapshot.last_high:
            candidate = snapshot.last_high.price + spread
            if candidate > current_close + spread:
                self.position.stop_current = min(
                    float(self.position.stop_current), candidate
                )

    def _manage_position(self, row: pd.Series, at: datetime) -> None:
        if self.position is None:
            return
        position = self.position
        order = position.order
        spread = float(row["spread"]) * self.config.broker.point
        if order.direction is Direction.LONG:
            low_trade = float(row["low"])
            high_trade = float(row["high"])
            close_trade = float(row["close"])
            adverse = max(0.0, position.entry_actual - low_trade)
            favorable = max(0.0, high_trade - position.entry_actual)
            stop_hit = low_trade <= float(position.stop_current)
        else:
            low_trade = float(row["low"]) + spread
            high_trade = float(row["high"]) + spread
            close_trade = float(row["close"]) + spread
            adverse = max(0.0, high_trade - position.entry_actual)
            favorable = max(0.0, position.entry_actual - low_trade)
            stop_hit = high_trade >= float(position.stop_current)
        position.mae = max(position.mae, adverse)
        position.mfe = max(position.mfe, favorable)

        # Worst-case ordering for OHLC bars: if a stop and target coexist in one
        # minute, assume the stop traded first.
        if stop_hit:
            self._finish_position(at, float(position.stop_current), "SL")
            return
        news_reason = self.news.force_close_reason(at)
        if news_reason:
            self._finish_position(at, close_trade, news_reason)
            return
        if must_force_close(at):
            self._finish_position(at, close_trade, "SESSION_CLOSE")
            return

        one_r = abs(order.entry - order.stop)
        sign = order.direction.sign
        level_1r = position.entry_actual + sign * one_r
        level_2r = position.entry_actual + sign * 2 * one_r
        reached_1r = high_trade >= level_1r if sign > 0 else low_trade <= level_1r
        reached_2r = high_trade >= level_2r if sign > 0 else low_trade <= level_2r
        target_reached = high_trade >= order.target if sign > 0 else low_trade <= order.target

        if self.strategy.exit_mode == "FLAT_2R":
            if reached_2r:
                self._finish_position(at, level_2r, "TP_2R")
            return
        if position.stage == 0 and reached_1r:
            self._realize(position, level_1r, 0.50)
            position.stage = 1
            position.stop_current = position.entry_actual + sign * spread
        if position.stage == 1 and reached_2r:
            self._realize(position, level_2r, 0.25)
            position.stage = 2
            position.stop_current = position.entry_actual + sign * one_r
        if position.stage >= 2 and target_reached:
            self._finish_position(at, order.target, "TARGET_LIQUIDITY")

    def _metrics(self) -> dict[str, Any]:
        pnl = np.array([trade.pnl_dollars for trade in self.trades], dtype=float)
        r_values = np.array([trade.pnl_r for trade in self.trades], dtype=float)
        initial = self.config.risk.initial_balance
        equity = initial + np.cumsum(pnl) if len(pnl) else np.array([initial])
        peaks = np.maximum.accumulate(equity)
        drawdowns = (equity - peaks) / peaks
        gross_profit = float(pnl[pnl > 0].sum()) if len(pnl) else 0.0
        gross_loss = float(-pnl[pnl < 0].sum()) if len(pnl) else 0.0
        daily: defaultdict[str, float] = defaultdict(float)
        for trade in self.trades:
            daily[trade.exit_at.date().isoformat()] += trade.pnl_dollars
        daily_returns = np.array(list(daily.values()), dtype=float) / initial
        sharpe = None
        if len(daily_returns) >= 2 and float(daily_returns.std(ddof=1)) > 0:
            sharpe = float(np.sqrt(252) * daily_returns.mean() / daily_returns.std(ddof=1))
        return {
            "start": self.config.backtest.start.isoformat(),
            "end": self.config.backtest.end.isoformat(),
            "initial_balance": initial,
            "final_balance": float(initial + pnl.sum()),
            "net_profit": float(pnl.sum()),
            "return_pct": float(pnl.sum() / initial * 100),
            "trades": int(len(self.trades)),
            "wins": int((pnl > 0).sum()),
            "losses": int((pnl < 0).sum()),
            "win_rate_pct": float((pnl > 0).mean() * 100) if len(pnl) else 0.0,
            "profit_factor": gross_profit / gross_loss if gross_loss > 0 else None,
            "average_r": float(r_values.mean()) if len(r_values) else None,
            "median_r": float(np.median(r_values)) if len(r_values) else None,
            "max_drawdown_pct": float(drawdowns.min() * 100),
            "sharpe_daily": sharpe,
            "gross_profit": gross_profit,
            "gross_loss": gross_loss,
            "average_duration_minutes": float(
                np.mean([trade.duration_minutes for trade in self.trades])
            )
            if self.trades
            else None,
        }

    def run(self) -> BacktestResult:
        if not self.news.available:
            self.diagnostics["news_calendar_unavailable"] += 1
        simulation = self.data.m1[
            (self.data.m1["close_time"] >= self.config.backtest.start)
            & (self.data.m1["close_time"] < self.config.backtest.end)
        ]
        if simulation.empty:
            raise ValueError("No M1 data in requested backtest interval")
        last_row: pd.Series | None = None
        last_at: datetime | None = None
        for _, row in simulation.iterrows():
            at = _python_time(row["close_time"])
            last_row, last_at = row, at
            self.risk.start_day(ny_date(at))
            self._manage_position(row, at)
            if self.position is not None and at in self._m5_index_at:
                spread = float(row["spread"]) * self.config.broker.point
                self._update_trailing(at, float(row["close"]), spread)
            if self.position is None and self.setup.pending is not None:
                self._try_fill(row, at)
            if self.position is not None or self.setup.pending is not None:
                continue
            if self.setup.state is SetupState.ENTRY_ARMED:
                self._on_m1_close_for_signal(row, at)
            if at in self._m5_index_at:
                self._on_m5_close(at)
            if at in self._m15_index_at:
                self._on_m15_close(at)

        if self.position is not None and last_row is not None and last_at is not None:
            spread = float(last_row["spread"]) * self.config.broker.point
            close = float(last_row["close"])
            if self.position.order.direction is Direction.SHORT:
                close += spread
            self._finish_position(last_at, close, "END_OF_BACKTEST")
        return BacktestResult(self.trades, dict(self.diagnostics), self._metrics())
