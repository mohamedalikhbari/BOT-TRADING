from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID, uuid4


class Direction(StrEnum):
    LONG = "LONG"
    SHORT = "SHORT"

    @property
    def sign(self) -> int:
        return 1 if self is Direction.LONG else -1

    @property
    def opposite(self) -> "Direction":
        return Direction.SHORT if self is Direction.LONG else Direction.LONG


class Trend(StrEnum):
    BULLISH = "BULLISH"
    BEARISH = "BEARISH"
    RANGING = "RANGING"

    @property
    def direction(self) -> Direction | None:
        if self is Trend.BULLISH:
            return Direction.LONG
        if self is Trend.BEARISH:
            return Direction.SHORT
        return None


class SwingKind(StrEnum):
    HIGH = "HIGH"
    LOW = "LOW"


class StructureEventKind(StrEnum):
    BOS = "BOS"
    CHOCH = "CHOCH"


class ZoneType(StrEnum):
    FVG = "FVG"
    IFVG = "IFVG"
    ORDER_BLOCK = "ORDER_BLOCK"


class ZoneState(StrEnum):
    FRESH = "FRESH"
    PARTIAL = "PARTIAL"
    MITIGATED = "MITIGATED"
    INVERTED = "INVERTED"
    UNMITIGATED = "UNMITIGATED"
    INVALIDATED = "INVALIDATED"


class LiquidityState(StrEnum):
    INTACT = "INTACT"
    SWEPT = "SWEPT"


class SetupState(StrEnum):
    IDLE = "IDLE"
    SWEEP_DETECTED = "SWEEP_DETECTED"
    SWEEP_CONFIRMED = "SWEEP_CONFIRMED"
    ENTRY_ARMED = "ENTRY_ARMED"
    ORDER_PENDING = "ORDER_PENDING"
    IN_POSITION = "IN_POSITION"


@dataclass(frozen=True)
class SwingPoint:
    kind: SwingKind
    price: float
    occurred_at: datetime
    confirmed_at: datetime
    index: int
    atr: float


@dataclass(frozen=True)
class StructureEvent:
    kind: StructureEventKind
    direction: Direction
    occurred_at: datetime
    level: float
    close: float
    source_swing: SwingPoint


@dataclass(frozen=True)
class StructureSnapshot:
    at: datetime
    last_high: SwingPoint | None
    previous_high: SwingPoint | None
    last_low: SwingPoint | None
    previous_low: SwingPoint | None
    trend: Trend
    latest_event: StructureEvent | None


@dataclass(frozen=True)
class BiasResult:
    direction: Direction | None
    evaluated_at: datetime
    ema_fast: float | None = None
    ema_slow: float | None = None
    ema_macro: float | None = None
    slope: float | None = None
    reason: str = ""


@dataclass(frozen=True)
class LiquidityLevel:
    name: str
    price: float
    formed_at: datetime
    state: LiquidityState = LiquidityState.INTACT

    @property
    def available_at(self) -> datetime:
        """Backward-compatible name for the instant the pool became usable."""
        return self.formed_at


@dataclass(frozen=True)
class SweepEvent:
    direction: Direction
    levels: tuple[LiquidityLevel, ...]
    occurred_at: datetime
    extreme: float
    candle_high: float
    candle_low: float
    candle_close: float
    confirmed_m15: bool = True
    confirmed_m5: bool = False

    @property
    def level(self) -> LiquidityLevel:
        """Compatibility accessor; scoring must use the complete levels tuple."""
        return self.levels[0]


@dataclass
class Zone:
    zone_type: ZoneType
    direction: Direction
    bottom: float
    top: float
    created_at: datetime
    timeframe: str
    state: ZoneState = ZoneState.FRESH
    refined_bottom: float | None = None
    refined_top: float | None = None
    expires_at: datetime | None = None
    associated_fvg: bool = False
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def midpoint(self) -> float:
        return (self.top + self.bottom) / 2.0

    def overlaps(self, low: float, high: float) -> bool:
        return self.top >= low and self.bottom <= high


@dataclass(frozen=True)
class OrderPlan:
    setup_id: UUID
    direction: Direction
    created_at: datetime
    expires_at: datetime
    entry: float
    stop: float
    target: float
    volume: float
    initial_risk_amount: float
    r_multiple: float
    score: int
    score_breakdown: dict[str, int]
    zone: Zone
    sweep: SweepEvent
    context: dict[str, Any]


@dataclass
class Position:
    order: OrderPlan
    entry_at: datetime
    entry_actual: float
    remaining_fraction: float = 1.0
    stop_current: float | None = None
    realized_pnl: float = 0.0
    realized_r: float = 0.0
    stage: int = 0
    mae: float = 0.0
    mfe: float = 0.0

    def __post_init__(self) -> None:
        if self.stop_current is None:
            self.stop_current = self.order.stop


@dataclass(frozen=True)
class TradeRecord:
    setup_id: UUID
    direction: Direction
    signal_at: datetime
    entry_at: datetime
    exit_at: datetime
    entry_planned: float
    entry_actual: float
    exit_price: float
    stop_initial: float
    target: float
    volume: float
    risk_amount: float
    r_multiple_planned: float
    setup_score: int
    score_breakdown: dict[str, int]
    pnl_dollars: float
    pnl_r: float
    mae: float
    mfe: float
    duration_minutes: int
    exit_reason: str
    spread_at_entry: float
    context: dict[str, Any]


def new_setup_id() -> UUID:
    return uuid4()
