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
strategies/XauNySpecEA/XauNySpecEA.mq5
strategies/XauNySpecEA/presets/XauNySpecEA_strict.set
strategies/XauNySpecEA/presets/XauNySpecEA_technical.set
strategies/XauNySpecEA/tester/mt5_tester_strict.ini
strategies/XauNySpecEA/tester/mt5_tester_technical.ini
```

I report nativi del test 1 febbraio–1 agosto 2026 sono in:

- `results/mt5_v1.3_2026-02_2026-07/` — baseline;
- `results/mt5_v1.4_2026-02_2026-07/` — timeout M1 a 45 minuti e wick M5 a 0.35.

## Ricerca intraday MT5

La ricerca successiva, eseguita soltanto nello Strategy Tester nativo, ha prodotto
un candidato H1 Keltner + RSI con preset aggressivo all'1% di rischio. Codice,
preset e resoconto completo sono in:

```text
strategies/GoldIntradayEA/GoldIntradayEA.mq5
strategies/GoldIntradayEA/presets/GoldIntradayEA_ensemble_final.set
strategies/GoldIntradayEA/tester/mt5_gold_intraday_ensemble_final_oos.ini
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

- `strategies/<NomeEA>/`: una cartella auto-contenuta per ogni strategia MT5.
- `shared/ExportCalendar.mq5`: esportazione del calendario economico nativo.
- `src/xauusd/`: dominio, struttura, zone, bias, rischio e backtester.
- `tools/`: utilità trasversali a tutte le strategie (`export_mt5.py`, script Ruby
  di analisi, `mt5_calendar.ini`, `mt5_history.ini`).
- `tests/`: test sintetici anti-look-ahead e dei vincoli di rischio.
- `config/default.toml`: parametri della specifica, senza ottimizzazione.

### Convenzione per le strategie

Ogni strategia vive in una sola cartella, così che aggiungerla o rimuoverla sia
un'operazione atomica su una directory:

```text
strategies/<NomeEA>/
  <NomeEA>.mq5        sorgente dell'Expert Advisor
  <NomeEA>.ex5        binario compilato
  presets/            i file .set della strategia
  tester/             i file .ini dello Strategy Tester
```

Strategie presenti: `GoldIntradayEA`, `GoldIntradayResearchEA`,
`GoldTopDownSweepEA`, `XauNySpecEA`.

Due dettagli di MT5 vincolano i percorsi dentro i file `.ini`:

- `Expert=` si risolve a partire da `MQL5\Experts\`, quindi punta al percorso
  completo della strategia, ad esempio
  `Expert=Advisors\trading-bot-main\strategies\GoldIntradayEA\GoldIntradayEA`.
- `ExpertParameters=` si risolve invece a partire da `MQL5\Profiles\Tester\`,
  non dal repository: resta perciò il solo nome del file `.set`, che va copiato
  in quella cartella prima di lanciare il test.
