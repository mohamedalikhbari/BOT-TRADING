# Backtest MT5 2026 — variante senza pullback EMA21

## Modifica isolata

È stato eliminato esclusivamente il requisito che il prezzo fosse entro ±0,15 ATR H1 dalla EMA21. Rimangono invariati bias EMA21/EMA50 H1, pool Londra, sweep M5, BOS M1, stop con buffer 0,80 USD, target teorico H1, trailing, rischio 1%, leva 1:30 e finestra New York.

## Risultato a tick reali

- Periodo: 2026-01-01 — 2026-08-07
- Qualità: 100% tick reali
- 51.310.787 tick e 211.566 barre

| Metrica | Con pullback | Senza pullback |
|---|---:|---:|
| Profitto netto | -1.465,45 USD (-2,93%) | -4.394,38 USD (-8,79%) |
| Trade | 3 | 18 |
| Vincenti | 0 (0%) | 6 (33,33%) |
| Perdenti | 3 | 12 |
| Profit factor | 0,00 | 0,25 |
| Payoff medio | -488,48 USD | -244,13 USD |
| Drawdown equity | 1.676,97 USD (3,34%) | 4.767,28 USD (9,46%) |

## Funnel senza pullback

- Barre M5 valutabili nella finestra mentre non c'erano posizioni: 4.275.
- Contesti bias EMA21/EMA50 H1 validi: 4.271.
- Sweep M5 validi: 82.
- Setup annullati da CHOCH M1 contrario: 42.
- Trigger BOS M1: 33.
- Scartati per R:R superiore a 3: 13.
- Scartati per R:R inferiore a 0,50: 2.
- Trade eseguiti: 18.

Tutti i 18 ingressi ricadono nella finestra New York; intervallo effettivo 08:47–10:54.

## Verifica trailing

- Trade che hanno attivato il passaggio iniziale a break-even: 5.
- Aggiornamenti stop nella fase 50%–100% del target: 354.
- Aggiornamenti nella fase oltre il target teorico con protezione del 90%: 10.
- Chiusure temporali Sydney: 1.

La rimozione del pullback risolve il problema della frequenza, ma introduce molti segnali peggiori: +15 trade e -2.928,93 USD di risultato aggiuntivo rispetto alla variante filtrata. Sul campione 2026, rimuovere completamente il filtro non migliora la strategia.
