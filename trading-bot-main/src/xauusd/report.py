from __future__ import annotations

from dataclasses import asdict
from datetime import datetime
import html
import json
from pathlib import Path
from typing import Any

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

from .backtest import BacktestResult
from .data import MarketData
from .domain import TradeRecord


def _json_default(value: Any) -> str:
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def trade_to_dict(trade: TradeRecord) -> dict[str, Any]:
    raw = asdict(trade)
    raw["setup_id"] = str(trade.setup_id)
    raw["direction"] = trade.direction.value
    for key in ("signal_at", "entry_at", "exit_at"):
        raw[key] = raw[key].isoformat()
    raw["score_breakdown"] = json.dumps(raw["score_breakdown"], sort_keys=True)
    raw["context"] = json.dumps(raw["context"], default=_json_default, sort_keys=True)
    return raw


def _equity_figure(result: BacktestResult, initial_balance: float) -> go.Figure:
    times = [trade.exit_at for trade in result.trades]
    values: list[float] = []
    equity = initial_balance
    for trade in result.trades:
        equity += trade.pnl_dollars
        values.append(equity)
    figure = go.Figure()
    if times:
        figure.add_trace(go.Scatter(x=times, y=values, mode="lines+markers", name="Equity"))
    else:
        figure.add_annotation(text="Nessun trade eseguito", x=0.5, y=0.5, showarrow=False)
    figure.update_layout(title="Equity curve", xaxis_title="Data", yaxis_title="Equity ($)")
    return figure


def _verification_figure(data: MarketData, result: BacktestResult) -> go.Figure:
    m15 = data.m15.copy()
    if result.trades:
        start = min(trade.signal_at for trade in result.trades) - pd.Timedelta(hours=4)
        end = max(trade.exit_at for trade in result.trades) + pd.Timedelta(hours=4)
        m15 = m15[(m15.index >= start) & (m15.index <= end)]
    else:
        m15 = m15.tail(1_000)
    figure = make_subplots(rows=1, cols=1)
    figure.add_trace(
        go.Candlestick(
            x=m15.index,
            open=m15["open"],
            high=m15["high"],
            low=m15["low"],
            close=m15["close"],
            name="XAUUSD M15",
        )
    )
    for trade in result.trades:
        color = "#16a34a" if trade.pnl_dollars >= 0 else "#dc2626"
        figure.add_trace(
            go.Scatter(
                x=[trade.entry_at, trade.exit_at],
                y=[trade.entry_actual, trade.exit_price],
                mode="markers+lines",
                marker={"color": color, "size": 9},
                name=f"{trade.direction.value} {trade.pnl_r:.2f}R",
                hovertext=[str(trade.setup_id), trade.exit_reason],
            )
        )
    figure.update_layout(
        title="Verifica visuale: segnali ed esecuzioni",
        xaxis_rangeslider_visible=False,
        height=760,
    )
    return figure


def write_results(
    result: BacktestResult,
    data: MarketData,
    output_directory: str | Path,
    *,
    initial_balance: float,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Path]:
    output = Path(output_directory)
    output.mkdir(parents=True, exist_ok=True)
    metrics_path = output / "metrics.json"
    trades_path = output / "trades.csv"
    diagnostics_path = output / "diagnostics.json"
    report_path = output / "report.html"
    verification_path = output / "verification.html"

    metrics_payload = dict(result.metrics)
    metrics_payload["metadata"] = metadata or {}
    metrics_path.write_text(
        json.dumps(metrics_payload, indent=2, default=_json_default), encoding="utf-8"
    )
    diagnostics_path.write_text(
        json.dumps(result.diagnostics, indent=2, sort_keys=True), encoding="utf-8"
    )
    frame = pd.DataFrame([trade_to_dict(trade) for trade in result.trades])
    frame.to_csv(trades_path, index=False)

    equity = _equity_figure(result, initial_balance)
    verification = _verification_figure(data, result)
    verification.write_html(verification_path, include_plotlyjs=True)
    rows = "".join(
        f"<tr><th>{html.escape(str(key))}</th><td>{html.escape(str(value))}</td></tr>"
        for key, value in result.metrics.items()
    )
    diagnostic_rows = "".join(
        f"<tr><th>{html.escape(key)}</th><td>{value}</td></tr>"
        for key, value in sorted(result.diagnostics.items(), key=lambda item: (-item[1], item[0]))
    )
    document = f"""<!doctype html>
<html lang="it"><head><meta charset="utf-8"><title>Backtest XAU/USD</title>
<style>body{{font-family:system-ui;max-width:1200px;margin:2rem auto;padding:0 1rem}}
table{{border-collapse:collapse}}th,td{{text-align:left;padding:.35rem .7rem;border-bottom:1px solid #ddd}}
th{{font-weight:600}}.grid{{display:grid;grid-template-columns:1fr 1fr;gap:2rem}}</style></head>
<body><h1>Backtest XAU/USD — specifica v1.5</h1>
<div class="grid"><section><h2>Metriche</h2><table>{rows}</table></section>
<section><h2>Funnel diagnostico</h2><table>{diagnostic_rows}</table></section></div>
{equity.to_html(full_html=False, include_plotlyjs=True)}
<p><a href="verification.html">Apri il grafico di verifica</a></p>
</body></html>"""
    report_path.write_text(document, encoding="utf-8")
    return {
        "metrics": metrics_path,
        "trades": trades_path,
        "diagnostics": diagnostics_path,
        "report": report_path,
        "verification": verification_path,
    }
