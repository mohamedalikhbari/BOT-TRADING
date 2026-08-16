from __future__ import annotations

from datetime import timedelta

import pandas as pd


def make_bars(rows, *, start="2026-01-01T00:00:00Z", frequency="1min"):
    index = pd.date_range(start, periods=len(rows), freq=frequency, tz="UTC")
    frame = pd.DataFrame(rows, index=index)
    if "open" not in frame:
        frame["open"] = frame["close"]
    if "tick_volume" not in frame:
        frame["tick_volume"] = 100
    if "spread" not in frame:
        frame["spread"] = 20
    if "real_volume" not in frame:
        frame["real_volume"] = 0
    if "atr" not in frame:
        frame["atr"] = 1.0
    if "quality_ok" not in frame:
        frame["quality_ok"] = True
    frame["close_time"] = frame.index + pd.Timedelta(frequency)
    return frame

