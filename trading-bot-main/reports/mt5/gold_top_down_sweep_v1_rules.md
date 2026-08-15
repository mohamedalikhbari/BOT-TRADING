# Gold Top-Down Sweep v1

Traduzione deterministica delle note e delle immagini ricevute il 7 agosto 2026. Questa e' una strategia separata da `GoldIntradayEA` congelata nel tag `gold-intraday-ensemble-v1-real-ticks`.

## Pipeline operativa

1. **H4:** swing fractal confermato con `K=3`. La relazione dello swing confermato piu' recente aggiorna la direzione, che persiste finche' una chiusura non rompe il massimo/minimo protetto e genera il cambio trend.
2. **H1:** stessa logica strutturale persistente e direzione obbligatoriamente allineata all'H4.
3. **M15:** tra un'ora prima e un'ora dopo le 09:30 di New York viene cercato il rifiuto di almeno uno tra ASH/ASL, PNYH/PNYL, PDH/PDL e PRE_NY_H/PRE_NY_L su una candela M15 chiusa.
4. **M5:** il movimento formato dalle tre candele M5 interne deve confermare il medesimo sweep e gli stessi livelli con soglie ATR e rifiuto proprie. Non e' un secondo sweep indipendente.
5. **M1:** dopo la conferma deve formarsi una FVG, iFVG oppure un order block nella direzione del bias. In seguito una chiusura M1 deve produrre un BOS di continuazione nella stessa direzione.
6. **Entrata:** ordine a mercato sul primo tick dopo la chiusura del BOS M1.
7. **Stop:** oltre l'estremo dello sweep confermato, con buffer di 0,30 ATR M1.
8. **Target:** primo swing M15 opposto, confermato, ancora davanti al prezzo e non gia' consumato. Gli swing sotto 1R vengono saltati in favore del successivo livello strutturale.

Non viene usato alcun livello o filtro Fibonacci. Il baseline non applica un filtro news, perche' non compare nelle note ricevute. Rischio: 0,5% dell'equity per operazione, massimo una nuova operazione al giorno e una posizione contemporanea. Le posizioni ancora aperte vengono chiuse a fine sessione secondo il vincolo NY-only della specifica esistente.

## Assunzioni rese esplicite

- La finestra indicata come 14:30-16:30 italiane e' implementata come 08:30-10:30 di New York, con cambio automatico dell'ora legale. In questo modo resta centrata sull'apertura NY delle 09:30 anche nelle settimane in cui Europa e Stati Uniti cambiano ora in date diverse.
- Il precedente massimo/minimo M15 usato come target deve trovarsi ancora davanti al prezzo al momento dell'ordine e deve offrire almeno 1R. Un livello gia' attraversato non e' un target valido.
- La conferma M5 misura penetrazione e rifiuto sull'intero movimento interno alla candela M15; i tre componenti devono essere presenti e privi di gap dati.
- Tutti i pool ASH/ASL, PNYH/PNYL, PDH/PDL e PRE_NY_H/PRE_NY_L vengono monitorati in parallelo e marcati `SWEPT` anche se un filtro sperimentale rifiuta poi il setup.

## Backtest nativi MetaTrader 5

Tutti i risultati seguenti provengono dallo Strategy Tester MT5 in modalita' `Every tick based on real ticks`, non da una simulazione Python. Deposito iniziale 50.000 USD, leva 1:100, rischio 0,5% per trade.

| Variante | Periodo | Netto | PF | DD equity max | Trade | Trade/settimana |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | 2026-02-01 / 2026-08-07 | +876,30 USD (+1,75%) | 2,05 | 1,20% | 9 | 0,35 |
| Baseline | 2021-09-06 / 2026-08-07 | -772,01 USD (-1,54%) | 0,87 | 4,52% | 60 | 0,23 |
| Solo short su PNYH/PRE_NY_H | 2021-09-06 / 2026-08-07 | +774,81 USD (+1,55%) | 1,24 | 3,40% | 28 | 0,11 |

La variante selettiva migliora il totale, ma non costituisce ancora una strategia robusta: sul blocco 2021-2023 produce +757,42 USD con PF 1,42; sul blocco di verifica 2024-2026 produce soltanto +17,39 USD con PF 1,01. Inoltre il 2025 perde 650,18 USD. Non soddisfa quindi l'obiettivo di almeno un trade a settimana ne' un obiettivo credibile del 5-10% mensile.

Sono state anche scartate le varianti con trigger M1 piu' permissivo, sweep M15 su piu' candele e soglie swing piu' aggressive: aumentavano leggermente la frequenza ma riducevano il profit factor sotto 1 o rendevano negativo il semestre recente.
