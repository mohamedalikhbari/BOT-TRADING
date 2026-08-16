# GoldIntradayEA v1.10 — resoconto ricerca MT5

Data del report: 4 agosto 2026. Simbolo: `XAUUSD`. Capitale iniziale: 50.000 USD. Leva del conto tester: 1:100.

## Aggiornamento full-history tick reali — 7 agosto 2026

È stato richiesto a MT5 l'intero intervallo disponibile del broker, dal primo dato storico al giorno corrente. TenTrade ha fornito tick dal 24 maggio 2019 e MT5 ha fissato automaticamente l'ultimo istante completo al 7 agosto 2026 00:00 (ultimo tick elaborato: 6 agosto 2026 23:59:58).

| Test continuo | Tick elaborati | Profitto | Ritorno | PF | DD equity | Sharpe | Trade |
|---|---:|---:|---:|---:|---:|---:|---:|
| Massimo richiesto 24 mag 2019–7 ago 2026 | 320.971.588 | +80.731,75 USD | +161,46% | 1,20 | 30,85% | 1,08 | 1.822 |
| Intervallo verificato 6 set 2021–7 ago 2026 | 262.427.145 | +58.826,96 USD | +117,65% | 1,22 | 28,21% | 1,22 | 1.250 |

Il primo test **non è interamente utilizzabile come prova su tick reali**, nonostante il report HTML mostri l'etichetta `100% ticks reali`: il log dettagliato MT5 registra 798.402 minuti scartati su 2.543.044 (31,40%), 371 giornate intere e l'uso della generazione Every Tick. Le anomalie sono concentrate tra il 24 maggio 2019 e il 3 settembre 2021 e derivano dalla mancata corrispondenza tra tick e barre M1 fornite dallo stesso broker.

Il secondo test parte dal primo lunedì successivo all'ultima anomalia. Non registra tick scartati né prezzi non corrispondenti. Su 1.740.920 minuti, soltanto 32 (0,00184%) sono privi di tick e vengono ricostruiti internamente da MT5. È quindi il risultato full-history più rigoroso disponibile con questo feed. Equivale a 4,87 trade/settimana, 1,33% mensile composto e 17,14% CAGR, prima di eventuali commissioni separate del conto reale.

La curva non è uniforme e mostra forte dipendenza dal regime. Nel test continuo il saldo dopo l'ultimo deal di ogni anno è:

| Periodo | Saldo | Variazione dal saldo precedente | Trade |
|---|---:|---:|---:|
| 6 set–31 dic 2021 | 38.077,50 USD | −23,84% | 88 |
| 2022 | 37.789,60 USD | −0,76% | 264 |
| 2023 | 41.209,52 USD | +9,05% | 261 |
| 2024 | 46.835,54 USD | +13,65% | 242 |
| 2025 | 66.326,38 USD | +41,62% | 245 |
| 1 gen–6 ago 2026 | 108.826,96 USD | +64,08% | 150 |

Queste variazioni descrivono il saldo del test continuo, non test annuali con capitale azzerato. Rendono però evidente che quasi tutto il profitto è concentrato nel 2025–2026: il risultato positivo complessivo non implica un rendimento stabile del 5–10% al mese.

I report HTML nativi, i grafici PNG, i preset `.ini`/`.set` e le cache `.tst` sono stati salvati. Le cache restano nella directory `Tester/cache` di MT5 e consentono al terminale locale di conservare il risultato.

## Esito

Il candidato migliore è un ensemble H1 formato da breakout Keltner e mean-reversion RSI. Nel test continuo 2 gennaio 2022–31 luglio 2026 ha prodotto +127.205,92 USD (+254,41%), PF 1,22, drawdown equity massimo 25,89% e 1.154 trade. Nel blocco più recente 2 febbraio–31 luglio 2026, testato su 41.974.135 tick reali del broker, ha prodotto +16.824,87 USD (+33,65%), PF 1,34, drawdown equity 14,95%, Sharpe 2,71 e 133 trade.

La frequenza recente è 5,17 trade/settimana. Il rendimento recente equivale al 4,95% mensile composto, quindi raggiunge sostanzialmente il limite inferiore dell'obiettivo medio 5–10%. Non produce però il 5–10% ogni mese e il rendimento composto sull'intero storico è 2,33% mensile.

Questo è un candidato di ricerca, non un'autorizzazione al trading live. L'EA mantiene `InpTesterOnly=true` e tutte le configurazioni hanno `AllowLiveTrading=0`.

## Regole congelate

Keltner:

- timeframe H1, solo barre chiuse;
- EMA 70, ATR 10, bande a 2 ATR;
- ingresso sulla rottura della banda, long e short;
- stop iniziale 1 ATR, nessun take-profit fisso;
- uscita al ritorno oltre l'EMA o dopo 24 barre.

RSI:

- RSI 25 su H1, livelli 35/80 e uscita a 50;
- nuove entrate soltanto tra le 16:00 e le 08:00 nel tempo server del dataset;
- stop 1,5 ATR, target 2R, durata massima 36 barre;
- nei rari segnali opposti simultanei, priorità al segnale RSI.

Esecuzione e rischio:

- valutazione cinque minuti dopo l'apertura della nuova barra H1;
- spread massimo ammesso 2,00 USD;
- rischio nominale 1% dell'equity per trade, volume massimo 5 lotti;
- throttle lineare: rischio pieno fino al 15% di drawdown, poi riduzione fino al 25% del rischio nominale al 25% di drawdown;
- circuit breaker definitivo al 40% di drawdown;
- una sola posizione dell'EA alla volta.

La scelta di Keltner e RSI segue la ricerca specifica sui sistemi algoritmici intraday per futures sui metalli preziosi, che studia entrambe le famiglie e identifica H1 come una scala utile per l'oro: [Intraday Trading of Precious Metals Futures Using Algorithmic Systems](https://www.sciencedirect.com/science/article/pii/S0960077921010304). Il razionale della componente trend è coerente anche con l'evidenza sul time-series momentum: [Time Series Momentum](https://www.sciencedirect.com/science/article/pii/S0304405X11002613). L'Opening Range Breakout è stato implementato e poi scartato; la sua instabilità tra sottoperiodi è coerente con quanto rilevato nella letteratura: [Assessing the profitability of intraday opening range breakout strategies](https://www.sciencedirect.com/science/article/abs/pii/S1544612312000438).

## Protocollo

Tutti i trade e tutte le statistiche derivano dallo Strategy Tester nativo MT5 build 6063. Ruby è stato usato soltanto per leggere i report HTML/XML generati da MT5; non è stato usato per simulare prezzi, segnali o ordini.

| Blocco | Modello MT5 | Tick | Profitto | Ritorno | PF | DD equity | Sharpe | Trade |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Sviluppo 2022–2024 | Every Tick | 99.276.341 | +34.464,99 USD | +68,93% | 1,12 | 25,89% | 0,96 | 762 |
| Validazione 2025 | Every Tick | 55.236.834 | +22.326,16 USD | +44,65% | 1,24 | 21,56% | 1,96 | 245 |
| OOS recente 2 feb–31 lug 2026 | Real ticks | 41.974.135 | +16.824,87 USD | +33,65% | 1,34 | 14,95% | 2,71 | 133 |
| Continuo 2022–31 lug 2026 | Every Tick | 201.524.828 | +127.205,92 USD | +254,41% | 1,22 | 25,89% | 1,48 | 1.154 |

Il test OOS usa il modo “Every tick based on real ticks”, per il quale MT5 usa i tick accumulati dal broker senza simularli. La documentazione ufficiale descrive anche il forward testing e i modelli di generazione: [MetaTrader 5 Strategy Testing](https://www.metatrader5.com/en/terminal/help/algotrading/testing).

Il report del broker registra commissioni pari a zero, spread tick-by-tick e swap. Un conto con commissioni separate produrrà risultati inferiori.

## Distribuzione mensile 2026

Ogni riga è un test MT5 autonomo ripartito da 50.000 USD; per questo la somma non coincide esattamente con il test continuo, che capitalizza i risultati e conserva lo stato tra i mesi.

| Mese | Profitto | Ritorno | PF | DD equity | Trade |
|---|---:|---:|---:|---:|---:|
| Febbraio | −5.724,66 USD | −11,45% | 0,37 | 14,95% | 24 |
| Marzo | +3.412,22 USD | +6,82% | 1,39 | 8,33% | 27 |
| Aprile | +1.141,27 USD | +2,28% | 1,19 | 10,07% | 18 |
| Maggio | +5.739,12 USD | +11,48% | 1,94 | 7,43% | 18 |
| Giugno | +12.917,41 USD | +25,83% | 3,82 | 5,06% | 18 |
| Luglio | −3.140,89 USD | −6,28% | 0,71 | 11,06% | 28 |

Quattro mesi su sei sono positivi; tre su sei superano il 5%. La media aritmetica dei test mensili è 4,78%, ma con dispersione molto elevata.

## Stress di ritardo

MT5 applica il ritardo tra richiesta e risposta del server, permettendo al prezzo di cambiare. La documentazione ufficiale spiega i modi No Delay, Random Delay e Fixed Delay: [Execution simulation in Strategy Tester](https://www.metatrader5.com/en/terminal/help/algotrading/testing#execution).

| Ritardo fisso | Profitto OOS | Ritorno | PF | DD equity | Trade |
|---:|---:|---:|---:|---:|---:|
| 0 ms | +16.824,87 USD | +33,65% | 1,34 | 14,95% | 133 |
| 100 ms | +17.171,05 USD | +34,34% | 1,34 | 14,95% | 133 |
| 500 ms | +17.410,85 USD | +34,82% | 1,34 | 14,86% | 133 |
| 1.000 ms | +9.391,69 USD | +18,78% | 1,21 | 17,19% | 132 |

Il risultato è stabile a 100–500 ms, ma un secondo di ritardo cambia una sequenza d'ordini e riduce sensibilmente l'utile. Va trattato come rischio operativo reale, non come dettaglio cosmetico.

## Strategie esaminate e scartate

- Donchian/TSMOM D1: positivo, ma soltanto 3 trade nell'OOS 2026; non soddisfa la frequenza.
- Keltner H1 isolato: +10,41% a rischio 0,5% nell'OOS, ma DD 21,18% nello sviluppo e scaling fragile.
- Keltner long-only: forte nel 2022–2025, quasi nullo o negativo nei real ticks 2026; dipendente dal regime.
- filtro D1 momentum/EMA: positivo ma PF 1,04 nel 2026; edge insufficiente.
- RSI H1 isolato: positivo in tutti i blocchi e DD basso, ma soltanto +1,70% nell'OOS a rischio 0,5%.
- ORB M15: la sola regione positiva aveva PF 1,01 nel 2025; scartata.
- Keltner M15: nessuna configurazione positiva contemporaneamente nello sviluppo e nel 2025.

## Limiti e interpretazione

1. L'obiettivo 5–10% è raggiunto come media composta nel blocco recente, non in modo uniforme. Sullo storico completo il rendimento composto è 2,33% mensile.
2. Il massimo drawdown verificato del candidato finale è 25,89%. Il limite hard al 40% è molto ampio e il capitale resta esposto a perdite rilevanti.
3. Durante la ricerca sono stati osservati più risultati 2026 prima di costruire l'ensemble. Il 2026 è quindi un holdout di ricerca, non una prova finale completamente intatta. Serve un forward test futuro non utilizzato per ulteriori modifiche.
4. I risultati sono specifici ai tick, spread, swap e specifiche contratto di TenTrade-Server. Il report indica commissioni separate pari a zero.
5. L'evidenza su regole tecniche per l'oro non è unanimemente positiva; studi che correggono per data-snooping trovano spesso assenza di profitti netti robusti: [Performance of intraday technical trading in China's gold market](https://www.sciencedirect.com/science/article/abs/pii/S1042443121001876).
6. Un backtest profittevole non garantisce rendimenti futuri. La prossima verifica corretta è un forward test demo senza cambiare parametri.

## File riproducibili

- EA sorgente: `mt5/GoldIntradayEA.mq5`
- EA compilato: `mt5/GoldIntradayEA.ex5`
- preset finale: `mt5/GoldIntradayEA_ensemble_final.set`
- OOS real ticks: `tools/mt5_gold_intraday_ensemble_final_oos.ini`
- storico Every Tick: `tools/mt5_gold_intraday_ensemble_final_full_every_tick.ini`
- massimo storico richiesto in modalità real ticks: `tools/mt5_gold_intraday_ensemble_final_all_available_real_ticks.ini`
- intervallo continuo verificato real ticks: `tools/mt5_gold_intraday_ensemble_final_verified_real_ticks.ini`
- configurazione che lascia il risultato aperto in MT5: `tools/mt5_gold_intraday_ensemble_final_verified_real_ticks_viewer.ini`
- report nativi: `reports/mt5/gold_intraday_ensemble_final_all_available_real_ticks.htm` e `reports/mt5/gold_intraday_ensemble_final_verified_real_ticks_2021_09.htm`
- stress 100/500/1.000 ms: `tools/mt5_gold_intraday_ensemble_final_oos_delay100.ini`, `...delay500.ini`, `...delay1000.ini`
- test mensili: `tools/mt5_gold_intraday_ensemble_final_2026_02.ini` … `..._2026_07.ini`

I report HTML nativi restano nella directory dati MT5 usata dai file `.ini`. Il preset e l'EA sono tester-only; non contengono credenziali.
