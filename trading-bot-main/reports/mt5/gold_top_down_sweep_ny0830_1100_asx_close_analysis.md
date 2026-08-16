# Backtest MT5 — finestra New York e chiusura rigorosa

## Configurazione testata

- Expert Advisor: `GoldTopDownSweepEA`
- Simbolo/timeframe: XAUUSD, M1
- Intervallo: 2021-09-06 — 2026-08-07
- Modello MT5: tick reali, qualità storico 100%
- Dati elaborati: 262.427.146 tick e 1.740.924 barre
- Capitale iniziale: 50.000 USD
- Leva: 1:30
- Rischio: 1% dell'equity per singolo trade, senza limite lotti imposto dall'EA
- Aperture consentite: 08:30–11:00 `America/New_York`
- Lunedì–giovedì: chiusura forzata alle 09:30 `Australia/Sydney`, cioè 30 minuti prima dell'apertura normale ASX delle 10:00
- Venerdì: chiusura forzata due ore prima della fine della sessione settimanale XAUUSD dichiarata dal broker

Il broker TenTrade ha restituito una fine sessione del venerdì alle 00:00 ora server; il cutoff calcolato è quindi 22:00 ora server.

## Risultato

| Metrica | Valore |
|---|---:|
| Profitto netto | +4.479,14 USD (+8,96%) |
| Saldo finale | 54.479,14 USD |
| Trade | 20 |
| Trade vincenti | 13 (65,00%) |
| Trade perdenti | 7 (35,00%) |
| Profit factor | 2,22 |
| Payoff medio | 223,96 USD |
| Drawdown massimo equity | 1.681,40 USD (3,07%) |
| Drawdown massimo balance | 1.098,06 USD (2,01%) |
| Tempo medio in posizione | 1:21:44 |
| Tempo massimo in posizione | 9:12:00 |

## Verifiche delle regole orarie

- Ingressi analizzati: 20 su 20.
- Intervallo effettivo degli ingressi in ora New York: 09:04–10:51.
- Ingressi fuori dalla finestra 08:30–11:00 New York: 0.
- Trade aperti di venerdì: 3; tutti hanno raggiunto SL/TP prima del cutoff delle 22:00 server.
- Chiusure forzate Sydney: 1, eseguita esattamente alla scadenza salvata (`2022-07-08 02:30` server = `2022-07-08 09:30 Australia/Sydney`).
- Risultato di quella chiusura: +592,80 USD di prezzo e +21,60 USD di swap, totale +614,40 USD.
- Chiusure forzate del venerdì: 0, perché nessuna posizione del venerdì era ancora aperta al cutoff.

Le ore server osservate per il cutoff Sydney cambiano tra 00:30, 01:30 e 02:30. È corretto: l'EA mantiene fisse le 09:30 locali di Sydney e gestisce sia l'ora legale australiana sia le settimane in cui i cambi d'ora di Australia ed Europa non coincidono.

## Confronto con il test precedente

Il test precedente con la vecchia politica d'uscita aveva prodotto +3.962,38 USD, profit factor 2,07 e drawdown equity 3,25%. Con la nuova politica rigorosa il numero e la percentuale di trade vincenti restano invariati, mentre il profitto netto sale di 516,76 USD, il profit factor a 2,22 e il drawdown equity scende al 3,07%.

Questo è un miglioramento sul campione storico, ma la frequenza resta molto bassa: 20 trade in quasi cinque anni. Non dimostra un obiettivo del 5–10% mensile né un trade a settimana.
