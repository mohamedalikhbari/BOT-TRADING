from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta
import math

import numpy as np
import pandas as pd

from .domain import Direction, Zone, ZoneState, ZoneType


def detect_fvg(bars: pd.DataFrame, timeframe: str, min_fvg_atr: float) -> list[Zone]:
    zones: list[Zone] = []
    if len(bars) < 3:
        return zones
    highs = bars["high"].to_numpy(dtype=float)
    lows = bars["low"].to_numpy(dtype=float)
    atrs = bars["atr"].to_numpy(dtype=float)
    close_times = [pd.Timestamp(value).to_pydatetime() for value in bars["close_time"]]
    left_high = highs[:-2]
    left_low = lows[:-2]
    right_high = highs[2:]
    right_low = lows[2:]
    center_atr = atrs[1:-1]
    bullish = (
        (left_high < right_low)
        & np.isfinite(center_atr)
        & ((right_low - left_high) >= min_fvg_atr * center_atr)
    )
    bearish = (
        (left_low > right_high)
        & np.isfinite(center_atr)
        & ((left_low - right_high) >= min_fvg_atr * center_atr)
    )
    for left_index in np.flatnonzero(bullish):
        right_index = int(left_index) + 2
        zones.append(
            Zone(
                ZoneType.FVG,
                Direction.LONG,
                float(left_high[left_index]),
                float(right_low[left_index]),
                close_times[right_index],
                timeframe,
            )
        )
    for left_index in np.flatnonzero(bearish):
        right_index = int(left_index) + 2
        zones.append(
            Zone(
                ZoneType.FVG,
                Direction.SHORT,
                float(right_high[left_index]),
                float(left_low[left_index]),
                close_times[right_index],
                timeframe,
            )
        )
    return zones


def derive_ifvg(
    bars: pd.DataFrame,
    fvgs: list[Zone],
    timeframe: str,
    max_age: int,
    timeframe_minutes: int,
) -> list[Zone]:
    close_times = [pd.Timestamp(value).to_pydatetime() for value in bars["close_time"]]
    time_values = pd.DatetimeIndex(bars["close_time"])
    closes = bars["close"].to_numpy(dtype=float)
    ifvgs: list[Zone] = []
    for fvg in fvgs:
        start = int(time_values.searchsorted(pd.Timestamp(fvg.created_at), side="right"))
        end = min(start + max_age, len(bars))
        if start >= end:
            continue
        window = closes[start:end]
        matches = (
            np.flatnonzero(window < fvg.bottom)
            if fvg.direction is Direction.LONG
            else np.flatnonzero(window > fvg.top)
        )
        if not len(matches):
            continue
        index = start + int(matches[0])
        created = close_times[index]
        ifvgs.append(
            Zone(
                ZoneType.IFVG,
                fvg.direction.opposite,
                fvg.bottom,
                fvg.top,
                created,
                timeframe,
                state=ZoneState.FRESH,
                expires_at=created + timedelta(minutes=timeframe_minutes * max_age),
                metadata={"source_created_at": fvg.created_at.isoformat()},
            )
        )
    return ifvgs


def detect_order_blocks(
    bars: pd.DataFrame,
    timeframe: str,
    fvgs: list[Zone],
    min_impulse_atr: float,
) -> list[Zone]:
    fvg_keys = {(fvg.created_at, fvg.direction) for fvg in fvgs}
    zones: list[Zone] = []
    if len(bars) < 3:
        return zones
    opens = bars["open"].to_numpy(dtype=float)
    highs = bars["high"].to_numpy(dtype=float)
    lows = bars["low"].to_numpy(dtype=float)
    closes = bars["close"].to_numpy(dtype=float)
    atrs = bars["atr"].to_numpy(dtype=float)
    close_times = [pd.Timestamp(value).to_pydatetime() for value in bars["close_time"]]
    for index in range(0, len(bars) - 2):
        created_at = close_times[index + 2]
        atr = float(atrs[index])
        if not math.isfinite(atr):
            continue
        bullish_impulse = (
            closes[index] < opens[index]
            and closes[index + 1] > opens[index + 1]
            and closes[index + 2] > opens[index + 2]
            and max(highs[index + 1], highs[index + 2]) - highs[index]
            >= min_impulse_atr * atr
            and (created_at, Direction.LONG) in fvg_keys
        )
        bearish_impulse = (
            closes[index] > opens[index]
            and closes[index + 1] < opens[index + 1]
            and closes[index + 2] < opens[index + 2]
            and lows[index] - min(lows[index + 1], lows[index + 2])
            >= min_impulse_atr * atr
            and (created_at, Direction.SHORT) in fvg_keys
        )
        if bullish_impulse:
            zones.append(
                Zone(
                    ZoneType.ORDER_BLOCK,
                    Direction.LONG,
                    float(lows[index]),
                    float(highs[index]),
                    created_at,
                    timeframe,
                    state=ZoneState.UNMITIGATED,
                    refined_bottom=float(lows[index]),
                    refined_top=float(opens[index]),
                    associated_fvg=True,
                )
            )
        if bearish_impulse:
            zones.append(
                Zone(
                    ZoneType.ORDER_BLOCK,
                    Direction.SHORT,
                    float(lows[index]),
                    float(highs[index]),
                    created_at,
                    timeframe,
                    state=ZoneState.UNMITIGATED,
                    refined_bottom=float(opens[index]),
                    refined_top=float(highs[index]),
                    associated_fvg=True,
                )
            )
    return zones


def build_zone_seeds(
    bars: pd.DataFrame,
    timeframe: str,
    min_fvg_atr: float,
    ifvg_max_age: int,
    timeframe_minutes: int,
    min_impulse_atr: float,
) -> list[Zone]:
    fvgs = detect_fvg(bars, timeframe, min_fvg_atr)
    ifvgs = derive_ifvg(bars, fvgs, timeframe, ifvg_max_age, timeframe_minutes)
    order_blocks = detect_order_blocks(bars, timeframe, fvgs, min_impulse_atr)
    return sorted(fvgs + ifvgs + order_blocks, key=lambda zone: zone.created_at)


def entry_price(zone: Zone) -> float:
    if zone.zone_type is ZoneType.FVG:
        return zone.midpoint
    if zone.zone_type is ZoneType.IFVG:
        return zone.top if zone.direction is Direction.LONG else zone.bottom
    if zone.direction is Direction.LONG:
        return float(zone.refined_top)
    return float(zone.refined_bottom)


def invalidated(zone: Zone, close: float) -> bool:
    if zone.direction is Direction.LONG:
        return close < zone.bottom
    return close > zone.top


def update_zone_state(zone: Zone, *, high: float, low: float, close: float) -> ZoneState:
    if invalidated(zone, close):
        zone.state = (
            ZoneState.INVERTED if zone.zone_type is ZoneType.FVG else ZoneState.INVALIDATED
        )
        return zone.state
    if zone.zone_type in {ZoneType.FVG, ZoneType.IFVG}:
        entered = low < zone.top and high > zone.bottom
        crossed_midpoint = low <= zone.midpoint if zone.direction is Direction.LONG else high >= zone.midpoint
        if crossed_midpoint:
            zone.state = ZoneState.MITIGATED
        elif entered and zone.state is ZoneState.FRESH:
            zone.state = ZoneState.PARTIAL
        return zone.state
    refined_low = float(zone.refined_bottom)
    refined_high = float(zone.refined_top)
    touched = low <= refined_high and high >= refined_low
    if touched:
        mitigations = int(zone.metadata.get("mitigations", 0)) + 1
        zone.metadata["mitigations"] = mitigations
        zone.state = ZoneState.INVALIDATED if mitigations >= 2 else ZoneState.MITIGATED
    return zone.state


def score_zone(zone: Zone, higher_timeframe_confluence: bool) -> dict[str, int]:
    result: dict[str, int] = {}
    if zone.zone_type is ZoneType.IFVG:
        result["zone_ifvg"] = 3
    elif zone.zone_type is ZoneType.ORDER_BLOCK and zone.associated_fvg:
        result["zone_order_block_fvg"] = 3
    else:
        result["zone_fvg"] = 1
    if higher_timeframe_confluence:
        result["higher_tf_confluence"] = 2
    if zone.state in {ZoneState.FRESH, ZoneState.UNMITIGATED}:
        result["zone_fresh"] = 2
    return result
