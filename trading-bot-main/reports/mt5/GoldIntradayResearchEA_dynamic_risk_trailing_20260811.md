# GoldIntradayResearchEA — rischio preventivo e trailing (2026-08-11)

Prova separata dall'advisor congelato, su XAUUSD H1, capitale 50.000 USD, leva 1:100, periodo 2021-09-06 — 2026-08-07 e qualità 100% tick reali.

## Gestione del rischio provata

- rischio iniziale 0,50% per trade;
- riduzione progressiva dal drawdown globale del 2%, fino al minimo al 6%;
- riduzione progressiva dalla perdita giornaliera dell'1%, fino al minimo al 3%;
- lotto limitato preventivamente alla frazione di rischio ancora disponibile prima delle barriere configurabili del 5% giornaliero e 10% globale;
- nessun circuito attivato nei test finali.

## Trailing provati

| Uscita | Netto | PF | Equity DD | Win rate |
|---|---:|---:|---:|---:|
| ATR continuo anticipato | -228,46 USD | 0,99 | 7,85% | 56% circa |
| Break-even a metà target, trailing a 2R | -2.549,21 USD | 0,95 | 7,34% | 49,27% |
| Trailing puro attivato a 2R | -2.844,83 USD | 0,92 | 7,14% | 37,58% |
| RSI: 80% a 2R + runner; Keltner: trailing largo | -2.381,83 USD | 0,91 | 7,07% | 39,67% |

## Esito

La gestione preventiva contiene il drawdown, ma il trailing obbligatorio elimina l'aspettativa positiva dell'ensemble. Nessuna variante è stata promossa. Il candidato precedente a rischio 0,20% resta invariato e separato.

Report finale: `reports/mt5/gold_intraday_research_dynamic_trail_model_specific_real.htm`.
