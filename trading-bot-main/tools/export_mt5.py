"""Export MT5 rates using the official Windows MetaTrader5 package.

The MT5 Python API exposes broker-server wall-clock timestamps as Unix-like
integers. They are converted explicitly through the configured server timezone
so that every CSV timestamp is genuine UTC.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

import MetaTrader5 as mt5


TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
}


def parse_datetime(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("datetime must include a UTC offset")
    return parsed.astimezone(timezone.utc)


def api_wall_time(actual_utc: datetime, server_zone: ZoneInfo) -> datetime:
    wall = actual_utc.astimezone(server_zone).replace(tzinfo=timezone.utc)
    return wall


def api_timestamp_to_utc(raw: int, server_zone: ZoneInfo) -> datetime:
    fake_utc = datetime.fromtimestamp(int(raw), timezone.utc)
    server_wall = fake_utc.replace(tzinfo=None).replace(tzinfo=server_zone)
    return server_wall.astimezone(timezone.utc)


def fetch_rates(
    symbol: str,
    timeframe: int,
    start: datetime,
    end: datetime,
    server_zone: ZoneInfo,
) -> list[dict]:
    records: dict[datetime, dict] = {}
    cursor = start - timedelta(days=2)
    extended_end = end + timedelta(days=2)
    while cursor < extended_end:
        chunk_end = min(cursor + timedelta(days=21), extended_end)
        rates = mt5.copy_rates_range(
            symbol,
            timeframe,
            api_wall_time(cursor, server_zone),
            api_wall_time(chunk_end, server_zone),
        )
        if rates is None:
            raise RuntimeError(f"copy_rates_range failed: {mt5.last_error()}")
        for rate in rates:
            at = api_timestamp_to_utc(int(rate["time"]), server_zone)
            if start <= at < end:
                records[at] = {
                    "time": at.isoformat(),
                    "open": float(rate["open"]),
                    "high": float(rate["high"]),
                    "low": float(rate["low"]),
                    "close": float(rate["close"]),
                    "tick_volume": int(rate["tick_volume"]),
                    "spread": int(rate["spread"]),
                    "real_volume": int(rate["real_volume"]),
                    "server_time_raw": int(rate["time"]),
                }
        cursor = chunk_end
    return [records[key] for key in sorted(records)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terminal", required=True)
    parser.add_argument("--symbol", default="XAUUSD")
    parser.add_argument("--start", required=True, type=parse_datetime)
    parser.add_argument("--end", required=True, type=parse_datetime)
    parser.add_argument("--server-timezone", default="Europe/Athens")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if args.start >= args.end:
        parser.error("start must precede end")
    args.output.mkdir(parents=True, exist_ok=True)
    if not mt5.initialize(args.terminal, timeout=120_000):
        print(f"MT5 initialization failed: {mt5.last_error()}", file=sys.stderr)
        return 2
    try:
        if not mt5.symbol_select(args.symbol, True):
            raise RuntimeError(f"Cannot select {args.symbol}: {mt5.last_error()}")
        terminal = mt5.terminal_info()
        account = mt5.account_info()
        symbol = mt5.symbol_info(args.symbol)
        if terminal is None or symbol is None:
            raise RuntimeError(f"Missing terminal/symbol information: {mt5.last_error()}")
        server_zone = ZoneInfo(args.server_timezone)
        counts: dict[str, int] = {}
        for name, value in TIMEFRAMES.items():
            rows = fetch_rates(
                args.symbol, value, args.start, args.end, server_zone
            )
            output_path = args.output / f"{args.symbol}_{name}.csv"
            with output_path.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else ["time"])
                writer.writeheader()
                writer.writerows(rows)
            counts[name] = len(rows)
            first = rows[0]["time"] if rows else None
            last = rows[-1]["time"] if rows else None
            print(f"{name}: {len(rows)} bars ({first} -> {last})", flush=True)

        metadata = {
            "exported_at_utc": datetime.now(timezone.utc).isoformat(),
            "requested_start_utc": args.start.isoformat(),
            "requested_end_utc": args.end.isoformat(),
            "server_timezone_assumption": args.server_timezone,
            "terminal_version": mt5.version(),
            "terminal_connected": terminal.connected,
            "terminal_trade_allowed": terminal.trade_allowed,
            "server": getattr(account, "server", None),
            "symbol": args.symbol,
            "digits": symbol.digits,
            "point": symbol.point,
            "contract_size": symbol.trade_contract_size,
            "volume_min": symbol.volume_min,
            "volume_max": symbol.volume_max,
            "volume_step": symbol.volume_step,
            "counts": counts,
        }
        with (args.output / "metadata.json").open("w", encoding="utf-8") as handle:
            json.dump(metadata, handle, indent=2)
        return 0
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())

