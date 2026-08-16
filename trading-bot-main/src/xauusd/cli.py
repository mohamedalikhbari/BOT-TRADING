from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

from .backtest import Backtester
from .config import load_config
from .data import load_market_data
from .news import NewsCalendar
from .report import write_results


def run_test_gate(project_root: Path) -> None:
    completed = subprocess.run(
        [sys.executable, "-m", "pytest", "-q"],
        cwd=project_root,
        check=False,
    )
    if completed.returncode:
        raise SystemExit("Test gate failed: backtest aborted")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="XAU/USD strategy tools")
    subparsers = parser.add_subparsers(dest="command", required=True)
    backtest_parser = subparsers.add_parser("backtest")
    backtest_parser.add_argument("--config", default="config/default.toml")
    backtest_parser.add_argument("--skip-test-gate", action="store_true")
    backtest_parser.add_argument(
        "--ignore-news",
        action="store_true",
        help="Diagnostic only: treat every timestamp as news-safe",
    )
    args = parser.parse_args(argv)
    project_root = Path(__file__).resolve().parents[2]
    config = load_config(project_root / args.config)
    if not args.skip_test_gate:
        run_test_gate(project_root)
    data = load_market_data(config.backtest.data_dir, config.strategy.symbol, config.strategy)
    if args.ignore_news:
        news = NewsCalendar([], available=True)
    else:
        news = NewsCalendar.from_csv(
            config.backtest.data_dir / "news.csv", required=config.news.required
        )
    engine = Backtester(data, config, news)
    result = engine.run()
    metadata_path = config.backtest.data_dir / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8")) if metadata_path.exists() else {}
    paths = write_results(
        result,
        data,
        config.backtest.results_dir,
        initial_balance=config.risk.initial_balance,
        metadata=metadata,
    )
    print(json.dumps(result.metrics, indent=2))
    for name, path in paths.items():
        print(f"{name}: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
