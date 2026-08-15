# GoldIntradayResearchEA — ricerca controllo rischio (2026-08-11)

L'Expert Advisor congelato `GoldIntradayEA` non è stato modificato. Tutte le prove sono state eseguite sul fork separato `GoldIntradayResearchEA` con capitale iniziale 50.000 USD e leva 1:100.

## Candidato conservato

- Preset: `mt5/GoldIntradayResearchEA_risk020.set`
- Periodo: 2021-09-06 — 2026-08-07
- Modello: tick reali, qualità storico 100%
- Rischio iniziale per trade: 0,20%
- Limite perdita giornaliera su equity: 5%
- Circuit breaker da massimo equity: 10%
- Drawdown throttle: disattivato
- Trade: 1.250
- Profitto netto: 16.489,91 USD
- Saldo finale: 66.489,91 USD
- Profit factor: 1,19
- Sharpe: 1,51
- Equity drawdown massimo: 4.335,23 USD (8,64%)
- Win rate: 30,56%
- Circuit breaker attivato: no

## Varianti scartate sui tick reali

| Variante | Trade | Netto | Equity DD | Esito |
|---|---:|---:|---:|---|
| 0,25%, senza throttle | 112 | -4.797,74 USD | 9,99% | Circuit breaker attivato |
| 0,45%, throttle 4%–8% | 118 | -4.632,68 USD | 9,97% | Circuit breaker attivato |

Lo screening OHLC aveva sovrastimato entrambe le varianti scartate. Per la selezione finale sono quindi stati usati esclusivamente i risultati su tick reali.

## File di prova

- `reports/mt5/gold_intraday_research_risk020_real.htm`
- `reports/mt5/gold_intraday_research_risk_screen.xml`
- `reports/mt5/gold_intraday_research_throttle_screen.xml`
