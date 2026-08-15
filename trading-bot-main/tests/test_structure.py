from __future__ import annotations

from xauusd.domain import Direction, StructureEventKind, SwingKind, Trend
from xauusd.structure import StructureTimeline, detect_swings

from conftest import make_bars


def test_swing_high_detection():
    bars = make_bars([
        {"high": 10, "low": 8, "close": 9},
        {"high": 12, "low": 9, "close": 11},
        {"high": 11, "low": 9, "close": 10},
    ])
    swings = detect_swings(bars, 1)
    assert any(point.kind is SwingKind.HIGH and point.price == 12 for point in swings)


def test_swing_low_detection():
    bars = make_bars([
        {"high": 11, "low": 9, "close": 10},
        {"high": 10, "low": 7, "close": 8},
        {"high": 12, "low": 8, "close": 11},
    ])
    swings = detect_swings(bars, 1)
    assert any(point.kind is SwingKind.LOW and point.price == 7 for point in swings)


def test_swing_high_with_equal_highs_keeps_first():
    bars = make_bars([
        {"high": 10, "low": 8, "close": 9},
        {"high": 12, "low": 9, "close": 11},
        {"high": 12, "low": 10, "close": 11},
        {"high": 11, "low": 9, "close": 10},
    ])
    highs = [point for point in detect_swings(bars, 1) if point.kind is SwingKind.HIGH]
    assert len(highs) == 1
    assert highs[0].index == 1


def test_swing_confirmation_delay():
    bars = make_bars([
        {"high": 10, "low": 8, "close": 9},
        {"high": 12, "low": 9, "close": 11},
        {"high": 11, "low": 9, "close": 10},
    ])
    point = next(point for point in detect_swings(bars, 1) if point.kind is SwingKind.HIGH)
    assert point.confirmed_at > point.occurred_at
    assert point.confirmed_at == bars.iloc[2].close_time.to_pydatetime()


def bullish_structure(final_close: float, final_high: float = 14):
    return make_bars([
        {"high": 10, "low": 9, "close": 9.5},
        {"high": 12, "low": 10, "close": 11},
        {"high": 11, "low": 9.5, "close": 10},
        {"high": 13, "low": 10.5, "close": 12},
        {"high": 12, "low": 10.0, "close": 11},
        {"high": final_high, "low": 11, "close": final_close},
        {"high": 13, "low": 11, "close": 12},
    ])


def test_bos_requires_close_not_wick():
    timeline = StructureTimeline(bullish_structure(13.5), 1, 0.05)
    assert any(
        event.kind is StructureEventKind.BOS and event.direction is Direction.LONG
        for event in timeline.events
    )


def test_bos_rejected_on_wick_only():
    timeline = StructureTimeline(bullish_structure(12.9, final_high=14), 1, 0.05)
    assert not any(
        event.kind is StructureEventKind.BOS and event.direction is Direction.LONG
        for event in timeline.events
    )


def test_choch_detection():
    bars = bullish_structure(9.0, final_high=12)
    timeline = StructureTimeline(bars, 1, 0.05)
    assert any(
        event.kind is StructureEventKind.CHOCH and event.direction is Direction.SHORT
        for event in timeline.events
    )


def test_sweep_vs_bos_disambiguation():
    timeline = StructureTimeline(bullish_structure(12.5, final_high=15), 1, 0.05)
    # A wick through 13 that closes back below it is not a bullish BOS.
    assert not any(event.direction is Direction.LONG for event in timeline.events)


def test_market_structure_trend_from_confirmed_swings():
    timeline = StructureTimeline(bullish_structure(13.5), 1, 0.05)
    snapshot = timeline.snapshot(bullish_structure(13.5).iloc[-1].close_time.to_pydatetime())
    assert snapshot.trend in {Trend.BULLISH, Trend.RANGING}

