from __future__ import annotations

from dataclasses import replace
from datetime import date, datetime, timedelta, timezone

from xauusd.config import BrokerConfig, RiskConfig
from xauusd.news import NewsCalendar, NewsEvent
from xauusd.risk import RiskManager, floor_to_step


def test_position_sizing_formula():
    manager = RiskManager(RiskConfig(), BrokerConfig())
    decision = manager.pre_trade_check(stop_distance=2.5, spread=0.2)
    assert decision.approved
    assert decision.volume == 1.0
    assert decision.risk_amount == 250.0


def test_position_sizing_rounding():
    manager = RiskManager(RiskConfig(), BrokerConfig())
    decision = manager.pre_trade_check(stop_distance=4.0, spread=0.2)
    assert decision.volume == 0.62


def test_position_sizing_broker_limits():
    manager = RiskManager(replace(RiskConfig(), max_lot_absolute=0.5), BrokerConfig())
    assert manager.pre_trade_check(stop_distance=1.5, spread=0.2).volume == 0.5
    assert floor_to_step(0.629, 0.01) == 0.62


def test_risk_manager_daily_loss_veto():
    manager = RiskManager(RiskConfig(), BrokerConfig())
    manager.start_day(date(2026, 1, 1))
    manager.equity -= 2_000
    assert manager.pre_trade_check(stop_distance=2.5, spread=0.2).reason == "daily_loss_limit"


def test_risk_manager_projected_loss_veto():
    config = replace(RiskConfig(), risk_per_trade_pct=0.02)
    manager = RiskManager(config, BrokerConfig())
    manager.start_day(date(2026, 1, 1))
    manager.equity -= 1_000
    assert manager.pre_trade_check(stop_distance=2.5, spread=0.2).reason == "projected_daily_loss"


def test_risk_manager_max_drawdown_veto():
    manager = RiskManager(RiskConfig(), BrokerConfig())
    manager.daily_start_equity = 46_000
    manager.equity = 46_000
    assert manager.pre_trade_check(stop_distance=2.5, spread=0.2).reason == "max_drawdown"


def test_risk_manager_spread_veto():
    manager = RiskManager(RiskConfig(), BrokerConfig())
    assert manager.pre_trade_check(stop_distance=2.5, spread=0.51).reason == "spread_too_wide"


def test_circuit_breaker_each_loss_trigger():
    manager = RiskManager(RiskConfig(), BrokerConfig())
    for _ in range(5):
        manager.register_trade(-10)
    assert manager.halted


def test_news_blackout_windows():
    at = datetime(2026, 2, 6, 13, 30, tzinfo=timezone.utc)
    calendar = NewsCalendar([NewsEvent(at, "Nonfarm Payrolls", "CRITICAL")])
    assert calendar.is_blackout(at - timedelta(minutes=60))
    assert calendar.is_blackout(at + timedelta(minutes=60))
    assert not calendar.is_blackout(at + timedelta(minutes=61))


def test_news_calendar_stale_fallback():
    calendar = NewsCalendar([], available=False)
    assert calendar.is_blackout(datetime.now(timezone.utc))

