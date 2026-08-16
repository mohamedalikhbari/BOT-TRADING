# XAU/USD New York Open System

Implementazione backtest-grade della specifica tecnica v1.4 del 3 agosto 2026.
Comprende sia il core Python disaccoppiato dal broker sia un Expert Advisor
MQL5 destinato allo Strategy Tester nativo di MetaTrader 5.

## Comandi

```bash
uv sync --all-groups
uv run pytest
uv run xau-backtest backtest --config config/default.toml
```

Il comando di backtest esegue prima l'intera suite di test. I risultati vengono
salvati nella directory configurata sotto `results/`.

Il backtest MT5 riproducibile usa:

```text
mt5/XauNySpecEA.mq5
mt5/XauNySpecEA_strict.set
mt5/XauNySpecEA_technical.set
tools/mt5_tester_strict.ini
tools/mt5_tester_technical.ini
```

I report nativi del test 1 febbraio–1 agosto 2026 sono in:

- `results/mt5_v1.3_2026-02_2026-07/` — baseline;
- `results/mt5_v1.4_2026-02_2026-07/` — timeout M1 a 45 minuti e wick M5 a 0.35.

## Ricerca intraday MT5

La ricerca successiva, eseguita soltanto nello Strategy Tester nativo, ha prodotto
un candidato H1 Keltner + RSI con preset aggressivo all'1% di rischio. Codice,
preset e resoconto completo sono in:

```text
mt5/GoldIntradayEA.mq5
mt5/GoldIntradayEA_ensemble_final.set
tools/mt5_gold_intraday_ensemble_final_oos.ini
reports/mt5/gold_intraday_ensemble_final.md
```

Il candidato resta esclusivamente di ricerca: `InpTesterOnly=true` e
`AllowLiveTrading=0`. Il resoconto distingue esplicitamente sviluppo,
validazione, real ticks 2026, distribuzione mensile e stress di esecuzione.

## Sicurezza

- Nessuna credenziale è memorizzata nel repository.
- Il trading automatico è disabilitato nelle configurazioni MT5 di supporto.
- L'EA ha `InpTesterOnly=true` per default e rifiuta l'avvio fuori dal tester.
- Il core Python non contiene un adapter di esecuzione live.
- I timestamp MT5 vengono convertiti dal fuso del server a UTC prima dell'uso.

## Struttura

- `src/xauusd/`: dominio, struttura, zone, bias, rischio e backtester.
- `tools/export_mt5.py`: esportazione OHLCV tramite API ufficiale MT5 Windows.
- `mt5/XauNySpecEA.mq5`: implementazione nativa per lo Strategy Tester MT5.
- `mt5/ExportCalendar.mq5`: esportazione del calendario economico nativo.
- `tests/`: test sintetici anti-look-ahead e dei vincoli di rischio.
- `config/default.toml`: parametri della specifica, senza ottimizzazione.
