# GoldIntradayEA — candidata frequenza/profitto

## Scelta

Le iterazioni sulla pipeline top-down/sweep hanno mostrato che l'aumento di frequenza ottenuto togliendo filtri produce aspettativa negativa. La candidata scelta usa invece due motori H1 complementari già emersi dalla ricerca MT5: breakout Keltner per i regimi direzionali e mean reversion RSI per i rientri estremi.

## Regole congelate

Keltner:

- timeframe H1 e sole barre chiuse;
- EMA 70, ATR 10, bande a 2 ATR;
- ingresso long/short sulla rottura della banda;
- stop iniziale 1 ATR;
- nessun TP fisso; uscita al ritorno oltre EMA70 oppure dopo 24 barre.

RSI:

- RSI 25 H1, long sotto 35 e short sopra 80;
- uscita al ritorno a 50;
- ingressi tra le 16:00 e le 08:00 ora server;
- stop 1,5 ATR, TP 2R e durata massima 36 barre.

Esecuzione/rischio:

- priorità RSI quando i due modelli sono in conflitto;
- esecuzione cinque minuti dopo l'apertura della nuova barra H1;
- spread massimo 2,00 USD;
- rischio nominale 1% dell'equity per trade;
- lotto massimo EA impostato a 100, quindi non limitante rispetto ai vincoli del broker;
- leva tester 1:30 e utilizzo massimo del 70% del margine libero;
- una sola posizione contemporaneamente;
- riduzione progressiva del rischio oltre il 15% di drawdown, fino al 25% del rischio nominale al 25% di drawdown;
- arresto definitivo al 40% di drawdown;
- `InpTesterOnly=true`, trading live disabilitato.

## Risultato 2026 a tick reali

Periodo 2026-01-01 — 2026-08-07, capitale iniziale 50.000 USD.

| Metrica | Valore |
|---|---:|
| Profitto netto | +31.799,91 USD (+63,60%) |
| Saldo finale | 81.799,91 USD |
| Trade | 149 |
| Frequenza | 4,78 trade/settimana |
| Win rate | 33,56% |
| Profit factor | 1,55 |
| Payoff medio | +213,42 USD |
| Drawdown equity massimo | 15,56% relativo / 11,76% monetario |
| Sharpe | 4,05 |
| Vincita media | 1.799,23 USD |
| Perdita media | -587,49 USD |

Distribuzione mensile del test continuo:

| Mese | Trade chiusi | Netto |
|---|---:|---:|
| Gennaio | 14 | +2.090,15 USD |
| Febbraio | 24 | -6.150,09 USD |
| Marzo | 27 | +5.247,51 USD |
| Aprile | 19 | +3.796,89 USD |
| Maggio | 17 | +5.449,73 USD |
| Giugno | 19 | +16.015,19 USD |
| Luglio | 27 | -4.868,01 USD |
| Agosto parziale | 2 | +10.218,54 USD |

## Controllo sullo storico verificato

Stesso preset, senza riottimizzazione, dal 2021-09-06 al 2026-08-07:

| Metrica | Valore |
|---|---:|
| Tick reali | 262.427.146 |
| Profitto netto | +58.826,96 USD (+117,65%) |
| Trade | 1.250 |
| Frequenza | 4,87 trade/settimana |
| Profit factor | 1,22 |
| Drawdown equity massimo | 28,21% |
| Sharpe | 1,22 |

## Valutazione

È la versione che soddisfa meglio contemporaneamente frequenza e profitto tra quelle disponibili: supera nettamente sia la variante sweep senza pullback (18 trade, -4.394,38 USD nel 2026) sia la migliore variante top-down selettiva sullo storico (20 trade, +4.479,14 USD).

Non è però un rendimento uniforme: febbraio e luglio 2026 sono negativi, il profitto recente contiene operazioni eccezionalmente grandi e lo storico lungo registra un drawdown del 28,21%. Il rischio dell'1% è nominale allo stop; gap e slippage possono produrre una perdita maggiore. Il 2026 è stato osservato durante la ricerca, quindi serve un forward test demo immutato prima di qualsiasi valutazione live.

## Massimo storico richiesto al broker

La stessa configurazione, senza alcuna modifica, è stata eseguita anche dal primo tick disponibile dichiarato dal broker, 2019-05-24, fino al 2026-08-07:

| Metrica | Valore |
|---|---:|
| Tick elaborati | 320.971.589 |
| Profitto netto | +80.731,75 USD (+161,46%) |
| Trade | 1.822 |
| Profit factor | 1,20 |
| Drawdown equity massimo | 30,85% |
| Sharpe | 1,08 |

Questo intervallo massimo non è interamente affidabile come prova a tick reali. Nonostante l'HTML MT5 riporti “100% ticks reali”, il log registra 798.402 minuti con tick scartati su 2.543.044 (31,40%) e 371 giornate intere scartate, concentrate prima del 6 settembre 2021. Il risultato rigoroso da usare come riferimento resta quindi il test 2021-09-06 — 2026-08-07: +58.826,96 USD, 1.250 trade, PF 1,22 e drawdown 28,21%.
