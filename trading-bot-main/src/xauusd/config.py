from __future__ import annotations

from dataclasses import dataclass, fields
from datetime import datetime
from pathlib import Path
import tomllib


@dataclass(frozen=True)
class StrategyConfig:
    symbol: str = "XAUUSD"
    server_timezone: str = "Europe/Athens"
    k_h4: int = 3
    k_h1: int = 3
    k_m15: int = 2
    k_m5: int = 2
    k_m1: int = 1
    min_break_atr: float = 0.05
    ema_fast: int = 21
    ema_slow: int = 50
    ema_macro: int = 200
    use_ema_macro: bool = False
    use_ema_h1: bool = False
    h4_bias_mode: str = "STRUCTURE_ONLY"
    h1_confirmation_mode: str = "TREND_ALIGNED"
    min_ema_slope: float = 0.05
    ema_slope_lookback: int = 6
    m5_fib_mode: str = "STRICT"
    m1_trigger_mode: str = "DISPLACEMENT"
    min_m1_displacement_atr: float = 0.50
    stop_mode: str = "LOCAL_STRUCTURE"
    target_mode: str = "FIRST_VALID_RR"
    min_setup_score: int = 8
    min_fvg_atr_m1: float = 0.15
    min_fvg_atr_m5: float = 0.20
    ifvg_max_age_m1: int = 30
    ifvg_max_age_m5: int = 20
    min_impulse_candles: int = 2
    min_impulse_atr: float = 1.0
    min_sweep_atr_m15: float = 0.10
    min_wick_ratio_m15: float = 0.50
    min_sweep_atr_m5: float = 0.10
    min_wick_ratio_m5: float = 0.34
    entry_timeout_minutes: int = 20
    bias_max_age_h4: int = 6
    sl_buffer_atr: float = 0.30
    min_sl_dollars: float = 1.50
    max_sl_dollars: float = 6.00
    min_r_multiple: float = 2.0
    exit_mode: str = "SCALED"
    max_gap_atr: float = 3.0
    gap_suspend_bars: int = 3

    def validate(self) -> None:
        if self.min_break_atr <= 0:
            raise ValueError("min_break_atr must be greater than zero")
        if self.m5_fib_mode not in {"STRICT", "LENIENT", "OFF"}:
            raise ValueError("m5_fib_mode must be STRICT, LENIENT, or OFF")
        if self.m1_trigger_mode not in {"BOS", "ZONE_READY", "DISPLACEMENT"}:
            raise ValueError(
                "m1_trigger_mode must be BOS, ZONE_READY, or DISPLACEMENT"
            )
        if self.min_m1_displacement_atr <= 0:
            raise ValueError("min_m1_displacement_atr must be greater than zero")
        if self.stop_mode not in {"SWEEP_ANCHORED", "LOCAL_STRUCTURE", "ZONE_ONLY"}:
            raise ValueError(
                "stop_mode must be SWEEP_ANCHORED, LOCAL_STRUCTURE, or ZONE_ONLY"
            )
        if self.target_mode not in {"NEAREST", "FIRST_VALID_RR"}:
            raise ValueError("target_mode must be NEAREST or FIRST_VALID_RR")
        if self.h1_confirmation_mode not in {"STRICT_BOS", "TREND_ALIGNED"}:
            raise ValueError(
                "h1_confirmation_mode must be STRICT_BOS or TREND_ALIGNED"
            )
        if self.h4_bias_mode not in {"EMA_AND_STRUCTURE", "STRUCTURE_ONLY"}:
            raise ValueError(
                "h4_bias_mode must be EMA_AND_STRUCTURE or STRUCTURE_ONLY"
            )
        if self.exit_mode not in {"SCALED", "FLAT_2R"}:
            raise ValueError("exit_mode must be SCALED or FLAT_2R")
        if not 0 < self.min_wick_ratio_m15 <= 1:
            raise ValueError("min_wick_ratio_m15 must be in (0, 1]")
        if not 0 < self.min_wick_ratio_m5 <= 1:
            raise ValueError("min_wick_ratio_m5 must be in (0, 1]")
        if self.entry_timeout_minutes <= 0:
            raise ValueError("entry_timeout_minutes must be greater than zero")
        if self.min_sweep_atr_m15 <= 0 or self.min_sweep_atr_m5 <= 0:
            raise ValueError("sweep ATR thresholds must be greater than zero")
        if self.ema_fast >= self.ema_slow:
            raise ValueError("ema_fast must be lower than ema_slow")


@dataclass(frozen=True)
class RiskConfig:
    initial_balance: float = 50_000.0
    risk_per_trade_pct: float = 0.005
    max_concurrent_positions: int = 1
    max_trades_per_day: int = 2
    max_lot_absolute: float = 2.0
    daily_loss_limit_pct: float = 0.05
    max_loss_limit_pct: float = 0.10
    safety_margin: float = 0.70
    max_spread: float = 0.50


@dataclass(frozen=True)
class BrokerConfig:
    contract_size: float = 100.0
    volume_min: float = 0.01
    volume_max: float = 100.0
    volume_step: float = 0.01
    point: float = 0.01
    commission_per_lot_round_turn: float = 0.0


@dataclass(frozen=True)
class NewsConfig:
    required: bool = True
    max_cache_age_hours: int = 24


@dataclass(frozen=True)
class BacktestConfig:
    start: datetime
    end: datetime
    data_dir: Path
    results_dir: Path


@dataclass(frozen=True)
class AppConfig:
    strategy: StrategyConfig
    risk: RiskConfig
    broker: BrokerConfig
    news: NewsConfig
    backtest: BacktestConfig


def _strict_dataclass(cls: type, values: dict):
    allowed = {field.name for field in fields(cls)}
    unknown = set(values) - allowed
    if unknown:
        raise ValueError(f"Unknown {cls.__name__} keys: {sorted(unknown)}")
    return cls(**values)


def load_config(path: str | Path) -> AppConfig:
    config_path = Path(path)
    with config_path.open("rb") as handle:
        raw = tomllib.load(handle)
    strategy = _strict_dataclass(StrategyConfig, raw.get("strategy", {}))
    strategy.validate()
    risk = _strict_dataclass(RiskConfig, raw.get("risk", {}))
    broker = _strict_dataclass(BrokerConfig, raw.get("broker", {}))
    news = _strict_dataclass(NewsConfig, raw.get("news", {}))
    backtest_raw = raw["backtest"]
    start = datetime.fromisoformat(backtest_raw["start"])
    end = datetime.fromisoformat(backtest_raw["end"])
    if start.tzinfo is None or end.tzinfo is None:
        raise ValueError("Backtest start/end must be timezone-aware")
    if start >= end:
        raise ValueError("Backtest start must precede end")
    base = config_path.parent.parent
    data_dir = (base / backtest_raw["data_dir"]).resolve()
    results_dir = (base / backtest_raw["results_dir"]).resolve()
    backtest = BacktestConfig(start, end, data_dir, results_dir)
    return AppConfig(strategy, risk, broker, news, backtest)
