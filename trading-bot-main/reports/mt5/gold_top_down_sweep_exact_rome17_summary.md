# Gold Top-Down Sweep — specifica letterale, finestra Roma 14:30-17:00

## Regole testate

1. H4 su sole candele chiuse e swing frattali confermati `k=3`: LONG con massimo e minimo crescenti, SHORT con massimo e minimo decrescenti. Una chiusura oltre lo swing protetto genera il cambio di trend; struttura mista significa nessun bias.
2. H1 calcolato nello stesso modo e obbligatoriamente allineato all'H4.
3. Valutazione soltanto tra le 14:30 e le 17:00 `Europe/Rome`, con DST automatico. Anche il BOS e l'ordine M1 devono maturare entro le 17:00.
4. Monitoraggio parallelo di ASH/ASL, PNYH/PNYL, PDH/PDL e PRE_NY_H/PRE_NY_L, senza scegliere prima un pool preferito.
5. Sweep su una candela M15 chiusa: oltrepassamento, rientro, penetrazione minima `0.10 ATR14 M15` e wick ratio minimo `0.50`.
6. Per ogni pool M15, almeno una delle tre candele M5 interne deve confermare individualmente lo stesso livello con `0.10 ATR14 M5` e wick ratio `0.35`. La lista finale è l'intersezione M15/M5.
7. Dopo la conferma: prima zona M1 valida nella direzione del bias, scegliendo tra `FVG OR IFVG OR Order Block`; successivamente è obbligatorio un BOS M1 nella stessa direzione.
8. Entrata a mercato sul primo tick dopo la chiusura del BOS.
9. Stop oltre l'estremo dello sweep con buffer `0.30 ATR14 M1`.
10. Target sul più recente swing M15 opposto ancora davanti al prezzo. Nessun filtro R:R minimo, punteggio minimo, direzione o pool aggiuntivo.
11. Una sola posizione contemporanea. Nessun filtro Fibonacci e nessun filtro news.

Il test usa rischio 0,5% dell'equity, lotto massimo 2, deposito 50.000 USD e leva 1:100. I limiti preventivi arbitrari su spread e distanza SL sono disattivati; restano validi i limiti reali imposti dal broker.

## Risultato Strategy Tester MT5

- Periodo: 6 settembre 2021 – 7 agosto 2026.
- Modello: Every tick based on real ticks.
- Qualità: 100% tick reali.
- Dati elaborati: 262.427.146 tick, 1.740.924 barre M1.
- Profitto netto: **-70,86 USD (-0,14%)**.
- Profit factor: **0,99**.
- Payoff atteso: **-1,31 USD per trade**.
- Drawdown massimo equity: **1.690,47 USD (3,30%)**.
- Trade: **54**, pari a **0,21 trade/settimana**.
- Vincenti: **32/54 (59,26%)**.
- Vincita media: **160,74 USD**; perdita media: **-237,02 USD**.
- Long: 26 trade, +247,40 USD, PF 1,10.
- Short: 28 trade, -318,26 USD, PF 0,88.

| Anno | Trade | Netto | PF |
|---:|---:|---:|---:|
| 2021 (dal 06/09) | 2 | -200,00 USD | 0,21 |
| 2022 | 11 | +182,91 USD | 1,19 |
| 2023 | 13 | -83,29 USD | 0,93 |
| 2024 | 9 | +139,86 USD | 1,13 |
| 2025 | 10 | +175,39 USD | 1,24 |
| 2026 (fino al 07/08) | 9 | -285,73 USD | 0,71 |

Sviluppo 2021-2023: 26 trade, -100,38 USD, PF 0,96. Verifica 2024-2026: 28 trade, +29,52 USD, PF 1,01. Entrambi i blocchi sono vicini al pareggio, quindi non emerge un vantaggio robusto.

## Funnel dei segnali

| Passaggio | Eventi |
|---|---:|
| Sweep M15 rilevati | 152 |
| Sweep confermati anche da una candela M5 | 145 |
| Zone M1 valide | 439 |
| BOS M1 successivi alla zona | 59 |
| Ordini eseguiti | 54 |

Tra i 59 trigger finali, 3 non avevano uno swing M15 valido davanti al prezzo e 2 ordini sono stati rifiutati dal broker (`10016`, stop non valido). Nessun segnale è stato escluso per spread, punteggio, R:R o filtri discrezionali.

## Conclusione

La condizione completa si verifica, ma non una volta a settimana. L'estensione fino alle 17:00 produce 54 trade in circa 4,94 anni e un risultato sostanzialmente piatto. Il win rate è superiore al 59%, ma la perdita media è circa 1,47 volte la vincita media; per questo il profit factor resta sotto 1.
