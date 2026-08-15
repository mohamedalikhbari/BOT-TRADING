from __future__ import annotations

from datetime import timedelta

from xauusd.domain import Direction, Zone, ZoneState, ZoneType
from xauusd.zones import (
    derive_ifvg,
    detect_fvg,
    detect_order_blocks,
    entry_price,
    score_zone,
    update_zone_state,
)

from conftest import make_bars


def test_fvg_bullish_detection():
    bars = make_bars([
        {"open": 9, "high": 10, "low": 8, "close": 9},
        {"open": 9, "high": 12, "low": 9, "close": 11},
        {"open": 11, "high": 13, "low": 10.5, "close": 12},
    ])
    zones = detect_fvg(bars, "M1", 0.15)
    assert [(zone.direction, zone.bottom, zone.top) for zone in zones] == [
        (Direction.LONG, 10.0, 10.5)
    ]


def test_fvg_bearish_detection():
    bars = make_bars([
        {"open": 12, "high": 13, "low": 11, "close": 12},
        {"open": 12, "high": 12, "low": 9, "close": 10},
        {"open": 10, "high": 10.5, "low": 8, "close": 9},
    ])
    zone = detect_fvg(bars, "M1", 0.15)[0]
    assert zone.direction is Direction.SHORT
    assert (zone.bottom, zone.top) == (10.5, 11.0)


def test_fvg_size_filter():
    bars = make_bars([
        {"high": 10, "low": 8, "close": 9, "atr": 2},
        {"high": 12, "low": 9, "close": 11, "atr": 2},
        {"high": 13, "low": 10.1, "close": 12, "atr": 2},
    ])
    assert detect_fvg(bars, "M1", 0.15) == []


def test_fvg_state_transitions():
    zone = Zone(ZoneType.FVG, Direction.LONG, 10, 12, make_bars([{"high": 1, "low": 0, "close": .5}]).index[0].to_pydatetime(), "M1")
    assert update_zone_state(zone, high=13, low=11.5, close=12.5) is ZoneState.PARTIAL
    assert update_zone_state(zone, high=12, low=10.9, close=11.5) is ZoneState.MITIGATED
    assert update_zone_state(zone, high=11, low=9, close=9.5) is ZoneState.INVERTED


def test_ifvg_conversion_and_expiry():
    bars = make_bars([
        {"high": 10, "low": 8, "close": 9},
        {"high": 12, "low": 9, "close": 11},
        {"high": 13, "low": 10.5, "close": 12},
        {"high": 11, "low": 9, "close": 9.5},
    ])
    fvg = detect_fvg(bars.iloc[:3], "M1", 0.15)
    converted = derive_ifvg(bars, fvg, "M1", 30, 1)
    assert converted[0].direction is Direction.SHORT
    assert converted[0].expires_at == converted[0].created_at + timedelta(minutes=30)


def order_block_bars():
    return make_bars([
        {"open": 9.5, "high": 10, "low": 8, "close": 9},
        {"open": 9, "high": 11, "low": 9.5, "close": 10.5},
        {"open": 10.5, "high": 12.5, "low": 10.2, "close": 12},
    ])


def test_order_block_identification_and_refined_zone():
    bars = order_block_bars()
    fvgs = detect_fvg(bars, "M1", 0.15)
    block = detect_order_blocks(bars, "M1", fvgs, 1.0)[0]
    assert block.direction is Direction.LONG
    assert (block.bottom, block.top) == (8, 10)
    assert (block.refined_bottom, block.refined_top) == (8, 9.5)
    assert entry_price(block) == 9.5


def test_order_block_invalidation_and_second_mitigation():
    block = Zone(ZoneType.ORDER_BLOCK, Direction.LONG, 8, 10, make_bars([{"high": 1, "low": 0, "close": .5}]).index[0].to_pydatetime(), "M1", state=ZoneState.UNMITIGATED, refined_bottom=8, refined_top=9.5)
    assert update_zone_state(block, high=10, low=9, close=9.8) is ZoneState.MITIGATED
    assert update_zone_state(block, high=10, low=9, close=9.8) is ZoneState.INVALIDATED


def test_setup_scoring_total():
    zone = Zone(ZoneType.IFVG, Direction.LONG, 10, 11, make_bars([{"high": 1, "low": 0, "close": .5}]).index[0].to_pydatetime(), "M1")
    assert sum(score_zone(zone, True).values()) == 7

