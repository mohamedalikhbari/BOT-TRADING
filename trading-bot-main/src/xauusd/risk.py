from __future__ import annotations

from dataclasses import dataclass
from datetime import date
import math

from .config import BrokerConfig, RiskConfig


@dataclass(frozen=True)
class RiskDecision:
    approved: bool
    reason: str
    volume: float = 0.0
    risk_amount: float = 0.0


def floor_to_step(value: float, step: float) -> float:
    return math.floor((value + 1e-12) / step) * step


class RiskManager:
    def __init__(self, config: RiskConfig, broker: BrokerConfig):
        self.config = config
        self.broker = broker
        self.equity = config.initial_balance
        self.peak_equity = config.initial_balance
        self.initial_balance = config.initial_balance
        self.current_day: date | None = None
        self.daily_start_equity = config.initial_balance
        self.trades_today = 0
        self.consecutive_losses = 0
        self.reduced_risk_trades_remaining = 0
        self.halted = False

    def start_day(self, day: date) -> None:
        if self.current_day != day:
            self.current_day = day
            self.daily_start_equity = self.equity
            self.trades_today = 0

    @property
    def risk_fraction(self) -> float:
        fraction = self.config.risk_per_trade_pct
        drawdown = (self.peak_equity - self.equity) / self.peak_equity
        if drawdown > 0.03 or self.reduced_risk_trades_remaining > 0:
            fraction *= 0.5
        return fraction

    def pre_trade_check(self, *, stop_distance: float, spread: float) -> RiskDecision:
        if self.halted:
            return RiskDecision(False, "halted")
        if stop_distance <= 0:
            return RiskDecision(False, "invalid_stop")
        if spread > self.config.max_spread:
            return RiskDecision(False, "spread_too_wide")
        if self.trades_today >= self.config.max_trades_per_day:
            return RiskDecision(False, "max_trades")
        daily_loss = self.daily_start_equity - self.equity
        total_loss = self.initial_balance - self.equity
        risk_amount = self.equity * self.risk_fraction
        if daily_loss >= self.initial_balance * self.config.daily_loss_limit_pct * self.config.safety_margin:
            return RiskDecision(False, "daily_loss_limit")
        if daily_loss + risk_amount >= self.initial_balance * self.config.daily_loss_limit_pct * self.config.safety_margin:
            return RiskDecision(False, "projected_daily_loss")
        if total_loss + risk_amount >= self.initial_balance * self.config.max_loss_limit_pct * self.config.safety_margin:
            return RiskDecision(False, "max_drawdown")
        raw_volume = risk_amount / (stop_distance * self.broker.contract_size)
        volume = floor_to_step(raw_volume, self.broker.volume_step)
        volume = min(volume, self.broker.volume_max, self.config.max_lot_absolute)
        if volume < self.broker.volume_min:
            return RiskDecision(False, "below_min_volume")
        actual_risk = volume * stop_distance * self.broker.contract_size
        return RiskDecision(True, "approved", round(volume, 8), actual_risk)

    def register_entry(self) -> None:
        self.trades_today += 1

    def register_trade(self, pnl: float) -> None:
        self.equity += pnl
        self.peak_equity = max(self.peak_equity, self.equity)
        if pnl < 0:
            self.consecutive_losses += 1
        else:
            self.consecutive_losses = 0
        if self.consecutive_losses == 3:
            self.reduced_risk_trades_remaining = 5
        elif self.reduced_risk_trades_remaining > 0:
            self.reduced_risk_trades_remaining -= 1
        drawdown = (self.peak_equity - self.equity) / self.peak_equity
        if self.consecutive_losses >= 5 or drawdown > 0.05:
            self.halted = True
