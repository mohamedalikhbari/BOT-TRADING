from __future__ import annotations

from dataclasses import replace

import pytest

from xauusd.config import StrategyConfig, load_config


def test_min_break_atr_cannot_be_zero():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), min_break_atr=0).validate()


def test_m5_fib_filter_modes():
    for mode in ("STRICT", "LENIENT", "OFF"):
        replace(StrategyConfig(), m5_fib_mode=mode).validate()


def test_unknown_fib_mode_rejected():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), m5_fib_mode="MAYBE").validate()


def test_m1_trigger_modes():
    for mode in ("BOS", "ZONE_READY", "DISPLACEMENT"):
        replace(StrategyConfig(), m1_trigger_mode=mode).validate()


def test_unknown_m1_trigger_mode_rejected():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), m1_trigger_mode="MAYBE").validate()


def test_stop_modes():
    for mode in ("SWEEP_ANCHORED", "LOCAL_STRUCTURE", "ZONE_ONLY"):
        replace(StrategyConfig(), stop_mode=mode).validate()


def test_unknown_stop_mode_rejected():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), stop_mode="MAYBE").validate()


def test_target_modes():
    for mode in ("NEAREST", "FIRST_VALID_RR"):
        replace(StrategyConfig(), target_mode=mode).validate()


def test_unknown_target_mode_rejected():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), target_mode="MAYBE").validate()


def test_h1_confirmation_modes():
    for mode in ("STRICT_BOS", "TREND_ALIGNED"):
        replace(StrategyConfig(), h1_confirmation_mode=mode).validate()


def test_unknown_h1_confirmation_mode_rejected():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), h1_confirmation_mode="MAYBE").validate()


def test_h4_bias_modes():
    for mode in ("EMA_AND_STRUCTURE", "STRUCTURE_ONLY"):
        replace(StrategyConfig(), h4_bias_mode=mode).validate()


def test_unknown_h4_bias_mode_rejected():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), h4_bias_mode="MAYBE").validate()


def test_entry_timeout_must_be_positive():
    with pytest.raises(ValueError):
        replace(StrategyConfig(), entry_timeout_minutes=0).validate()


def test_default_configuration_loads():
    config = load_config("config/default.toml")
    assert config.strategy.min_setup_score == 8
    assert config.strategy.min_wick_ratio_m5 == 0.34
    assert config.strategy.entry_timeout_minutes == 20
    assert config.strategy.m1_trigger_mode == "DISPLACEMENT"
    assert config.strategy.stop_mode == "LOCAL_STRUCTURE"
    assert config.strategy.target_mode == "FIRST_VALID_RR"
    assert config.strategy.h1_confirmation_mode == "TREND_ALIGNED"
    assert config.strategy.h4_bias_mode == "STRUCTURE_ONLY"
    assert config.backtest.start.tzinfo is not None
