# Analisi controfattuale dei trade scartati

Data analisi: 7 agosto 2026.

## Perimetro del test

- Piattaforma: MetaTrader 5 Strategy Tester, modello `Every tick based on real ticks` (`Model=4`).
- Simbolo/server: `XAUUSD`, TenTrade-Server.
- Periodo: 6 settembre 2021 - 7 agosto 2026.
- Qualità: 100% tick reali, 262.427.146 tick, 1.740.924 barre M1.
- Conto: 50.000 USD, leva 1:30, rischio nominale 1% per trade, nessun cap EA sui lotti.
- Finestra: 14:30-17:00 Europe/Rome per i nuovi segnali; gestione/chiusura come nell'EA esatto.
- Metodo: una sola modifica alla volta rispetto alla strategia esatta.

## Conclusione

Nessuno dei filtri direzionali o di conferma esistenti risulta superfluo. Togliere H1, rendere persistente il trend H4/H1 o aggregare il rifiuto M5 peggiora nettamente il risultato. Rendere più permissivo il trigger M1 sembra positivo sul totale, ma il profitto dipende da un unico trade eccezionale del 2022; i 26 trade realmente aggiunti perdono complessivamente 1.607,83 USD.

Il problema più evidente non è un filtro che elimina buoni trade, ma il rapporto rischio/rendimento del target M15: il target mediano del riferimento vale soltanto 0,52R. I setup con target sotto 0,5R generano molti piccoli vincenti ma perdono nel complesso.

La gestione mobile richiesta è stata testata in due forme reali e non va promossa:

1. breakeven a +1R e trailing sull'ultimo swing M5;
2. uscita 50% a +1R, 25% a +2R e trailing M5 sul 25% restante.

Entrambe hanno aspettativa negativa. Il miglior controllo d'uscita non mobile è il target fisso 2R, ma il suo vantaggio rimane debole (PF 1,07).

La variante esplorativa più interessante mantiene il target M15 originale ma accetta soltanto un rapporto compreso tra 0,5R e 3R: 20 trade, +3.506,57 USD, PF 1,95 e drawdown equity 3,38%. La fascia è stata individuata osservando lo storico e richiede quindi forward test prima di qualsiasi uso reale.

## Ablation dei filtri

| Variante | Trade | Netto USD | PF | Win rate | DD equity max | Esito |
|---|---:|---:|---:|---:|---:|---|
| Strategia esatta | 53 | +138,43 | 1,01 | 60,38% | 6,44% | Riferimento, edge quasi nullo |
| Senza allineamento H1 | 33 | -2.592,70 | 0,58 | 51,52% | 5,36% | Bocciata; poi interviene il circuito rischio |
| Conferma M5 aggregata | 34 | -2.607,39 | 0,53 | 55,88% | 5,78% | Bocciata |
| Trend H4/H1 persistente | 40 | -1.811,08 | 0,71 | 60,00% | 6,85% | Bocciata; poi interviene il circuito rischio |
| Trigger M1 structure-break | 79 | +4.388,67 | 1,31 | 59,49% | 7,04% | Non robusta; dipende da un outlier |

Le varianti senza H1, M5 aggregata e trend persistente raggiungono il limite interno di drawdown; per questo il numero di trade osservato si ferma prima della fine di tutti i segnali possibili. È comunque un esito operativo negativo: con rischio 1% quelle varianti attivano la protezione del conto.

### Trade aggiunti rimuovendo o allentando il filtro

| Filtro allentato | Trade extra rispetto al riferimento | Vincenti | Netto extra | PF extra |
|---|---:|---:|---:|---:|
| H1 rimosso | 24 | 13 | -1.559,39 | 0,62 |
| M5 aggregato | 2 | 0 | -826,14 | 0,00 |
| Trend persistente | 14 | 7 | -1.800,74 | 0,33 |
| Trigger M1 più permissivo | 26 | 15 | -1.607,83 | 0,66 |

Esistono singoli buoni trade persi. I migliori esempi recuperati dal trigger M1 più permissivo sono:

- 26 aprile 2023, short: +698,88 USD;
- 18 agosto 2023, short: +541,03 USD;
- 7 febbraio 2023, long: +342,00 USD;
- 16 giugno 2022, long: +284,76 USD;
- 5 agosto 2025, long: +212,24 USD.

Tuttavia, lo stesso gruppo comprende stop da circa 550 USD il 18 maggio 2022, 12 agosto 2022, 12 ottobre 2023, 1 maggio 2024, 23 giugno 2025 e 25 settembre 2025. Il gruppo completo è negativo: non conviene rimuovere il BOS M1 per catturare soltanto gli esempi favorevoli.

Anche senza H1 sono stati recuperati trade positivi, per esempio il long del 9 febbraio 2022 (+588,72 USD), ma i 24 trade extra rimangono negativi e portano rapidamente al circuito di rischio.

### Instabilità del trigger M1 permissivo

| Periodo | Trade | Netto USD | PF | Win rate |
|---|---:|---:|---:|---:|
| 2021-2023 | 41 | +5.797,97 | 1,82 | 63,41% |
| 2024-2026 | 38 | -1.409,30 | 0,80 | 55,26% |

Il trade del 7 marzo 2022 vale +5.248,60 USD. Senza quel singolo trade la variante chiude a -859,93 USD. Non è quindi una modifica robusta.

## Analisi del rapporto rischio/rendimento

Nel riferimento, la distanza del primo target M15 rispetto allo stop è distribuita così:

| R:R del target M15 | Trade | Netto USD | PF |
|---|---:|---:|---:|
| < 0,25R | 16 | -1.355,34 | 0,32 |
| 0,25R - 0,50R | 10 | -816,76 | 0,55 |
| 0,50R - 1,00R | 8 | +956,54 | 1,92 |
| 1,00R - 2,00R | 9 | +2.034,32 | 2,36 |
| 2,00R - 3,00R | 3 | +317,88 | 1,42 |
| >= 3,00R | 7 | -998,21 | 0,64 |

Il valore mediano è 0,52R; 34 dei 53 trade hanno target sotto 1R. La combinazione di target molto piccoli e stop pieni spiega il riferimento: win rate alto ma vincita media 312,79 USD contro perdita media 470,04 USD.

### Candidato con fascia 0,5R-3R

Questa variante non sposta il TP: seleziona sempre il primo massimo/minimo M15 precedente e scarta definitivamente il setup se quel target vale meno di 0,5R o più di 3R.

| Metrica | Risultato |
|---|---:|
| Trade | 20 |
| Netto | +3.506,57 USD (+7,01%) |
| Profit factor | 1,95 |
| Win rate | 65,00% |
| Payoff atteso | +175,33 USD/trade |
| Drawdown equity massimo | 1.869,14 USD (3,38%) |
| Setup sotto 0,5R scartati | 26 |
| Setup sopra 3R scartati | 10 |

Stabilità temporale:

| Periodo | Trade | Netto USD | PF | Win rate |
|---|---:|---:|---:|---:|
| 2021-2023 | 10 | +2.347,92 | 2,55 | 70,00% |
| 2024-2026 | 10 | +1.158,65 | 1,53 | 60,00% |
| Solo 2026 | 3 | -622,05 | 0,42 | 33,33% |

La coerenza dei due blocchi è incoraggiante, ma non è un vero out-of-sample: la fascia è stata scelta dopo l'analisi dello stesso storico. Inoltre la frequenza scende a circa 0,08 trade/settimana.

## Take profit e stop loss

| Gestione | Posizioni | Netto USD | PF | DD equity max | Valutazione |
|---|---:|---:|---:|---:|---|
| TP massimo/minimo M15 originale | 53 | +138,43 | 1,01 | 6,44% | Edge quasi nullo |
| TP fisso 2R | 55 | +940,42 | 1,07 | 5,13% | Migliore tra le uscite generiche, ma debole |
| TP M15 adattato nella fascia 1R-3R | 56 | -268,53 | 0,98 | 5,05% | Bocciato |
| Nessun TP, BE +1R e trailing M5 | 14 | -2.663,03 | 0,14 | 5,85% | Bocciato; circuito rischio |
| Parziali 1R/2R + runner M5 | 56 | -1.564,37 | 0,85 | 5,50% | Bocciato |
| SL composito, TP M15 originale | 34 | -2.525,86 | 0,59 | 7,72% | Bocciato; circuito rischio |

Il TP fisso 2R produce +122,53 USD nel 2021-2023 e +817,89 USD nel 2024-2026, ma resta negativo nel 2026 (-346,12 USD, PF 0,81). Non è abbastanza forte da essere considerato una soluzione definitiva.

Lo SL va mantenuto oltre l'estremo dello sweep con buffer 0,30 ATR M1. Allargarlo fino a includere zona e ultimo swing M1 riduce la size ma non evita gli stop; peggiora PF e drawdown.

## Raccomandazione operativa

1. Non rimuovere H1, conferma M5 individuale, definizione stretta H4/H1 o BOS M1.
2. Mantenere lo SL originario oltre lo sweep + 0,30 ATR M1.
3. Non usare il trailing mobile a +1R né l'uscita mobile a scale: i test real-tick sono negativi.
4. Conservare il 2R fisso soltanto come benchmark, non come versione validata.
5. Portare avanti come candidato di ricerca separato la fascia R:R 0,5R-3R con target M15 originale.
6. Validare il candidato con forward test o walk-forward bloccato prima di usarlo; il 2026 è ancora negativo.
7. Non aspettarsi un trade a settimana da questa pipeline esatta: il riferimento produce circa 0,21 trade/settimana e il candidato R:R circa 0,08. Per aumentare la frequenza senza distruggere i filtri sarebbe necessaria una seconda strategia indipendente o un ampliamento sostanziale delle specifiche.

## Artefatti

- EA con modalità di ricerca: `mt5/GoldTopDownSweepEA.mq5`
- Candidato R:R: `mt5/GoldTopDownSweepEA_rr_band_05_3.set`
- Config tester candidato: `tools/mt5_gold_top_down_sweep_rr_band_05_3.ini`
- Report MT5 candidato: `reports/mt5/gold_top_down_sweep_rr_band_05_3.htm`
- Diagnostica candidato: `reports/mt5/gold_top_down_sweep_rr_band_05_3_diagnostics.csv`
- Tutti gli altri report controllati sono salvati nella stessa cartella `reports/mt5/` con prefissi `gold_top_down_sweep_cf_`, `gold_top_down_sweep_exit_` e `gold_top_down_sweep_sl_`.
