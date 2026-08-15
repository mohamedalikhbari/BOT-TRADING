# Analisi della modalità all-day con rischio per trade

Data: 7 agosto 2026.

## Correzione della gestione del rischio

In questi test il rischio è definito esclusivamente per singola operazione:

- rischio nominale di ogni nuovo trade: 1% dell'equity corrente;
- lotto calcolato da `equity * 1% / (distanza SL * contract size)` e arrotondato per difetto al passo volume del simbolo;
- nessuna riduzione del rischio dopo perdite o drawdown;
- nessun limite di perdita giornaliero o complessivo;
- nessuna pausa dopo una serie di stop;
- nessun tetto lotti imposto dall'EA;
- massimo una posizione contemporanea.

Il preset imposta `InpUsePortfolioRiskLimits=false`. Restano inevitabilmente i vincoli fisici del broker e della leva 1:30. Se il volume necessario non dispone di margine sufficiente, MT5 rifiuta l'ordine invece di ridimensionarlo. Il rischio realizzato può inoltre differire leggermente dall'1% nominale per arrotondamento del lotto, spread, slippage, gap e swap.

## Metodo

La domanda testata è l'effetto della rimozione completa della finestra 14:30-17:00 Europe/Rome: nuovi setup ammessi durante tutte le ore negoziabili di XAUUSD e nessuna chiusura forzata di fine sessione.

Sono rimasti invariati struttura H4/H1, sweep M15+M5, trigger BOS M1, liquidity pool, SL sulla sweep e TP sul precedente swing M15. La variante R:R aggiunge il filtro di ricerca 0,5-3R ma non cambia il target M15.

- Periodo: 6 settembre 2021 - 7 agosto 2026.
- Capitale iniziale: 50.000 USD.
- Leva: 1:30.
- Modello MT5: ogni tick basato su tick reali.
- Qualità: 100% tick reali.
- Dati elaborati: 262.427.146 tick e 1.740.924 barre M1.

Per avere un confronto omogeneo sono stati rieseguiti anche i due controlli con finestra NY usando la stessa identica gestione 1% per trade.

## Confronto omogeneo

| Variante | Trade | Frequenza | Netto | Rendimento | PF | Win rate | DD equity |
|---|---:|---:|---:|---:|---:|---:|---:|
| Finestra NY, regole esatte | 53 | 0,21/settimana | +413,05 USD | +0,83% | 1,04 | 60,38% | 6,44% |
| All-day, regole esatte | 198 | 0,77/settimana | -12.374,50 USD | -24,75% | 0,76 | 45,96% | 29,51% |
| Finestra NY, R:R 0,5-3R | 20 | 0,08/settimana | +3.962,38 USD | +7,92% | 2,07 | 65,00% | 3,25% |
| All-day, R:R 0,5-3R | 111 | 0,43/settimana | -1.844,35 USD | -3,69% | 0,95 | 39,64% | 16,36% |

Togliere la finestra aumenta molto la frequenza, ma nessuna versione raggiunge un trade eseguito a settimana. Soprattutto, l'aumento arriva da segnali con aspettativa negativa: la versione esatta perde quasi un quarto del capitale e la versione filtrata resta sotto break-even.

La variante R:R nella finestra NY è stata individuata dopo aver analizzato questo stesso storico: è un risultato post-selezionato, non una validazione out-of-sample. Inoltre produce solo 20 trade e +7,92% complessivo in quasi cinque anni, quindi non supporta un obiettivo del 5-10% mensile.

## Stabilità temporale all-day

### Regole esatte

| Anno | Trade | Netto | PF | Win rate |
|---|---:|---:|---:|---:|
| 2021 parziale | 12 | +1.197,59 USD | 1,39 | 50,00% |
| 2022 | 38 | -1.921,15 USD | 0,81 | 50,00% |
| 2023 | 51 | +2.935,57 USD | 1,24 | 52,94% |
| 2024 | 31 | -1.737,18 USD | 0,78 | 51,61% |
| 2025 | 41 | -10.464,58 USD | 0,18 | 31,71% |
| 2026 parziale | 25 | -2.384,75 USD | 0,59 | 40,00% |

### Filtro R:R 0,5-3R

| Anno | Trade | Netto | PF | Win rate |
|---|---:|---:|---:|---:|
| 2021 parziale | 7 | -340,22 USD | 0,86 | 28,57% |
| 2022 | 24 | +1.217,61 USD | 1,20 | 50,00% |
| 2023 | 32 | +4.471,18 USD | 1,50 | 46,88% |
| 2024 | 14 | +985,08 USD | 1,24 | 50,00% |
| 2025 | 18 | -5.819,79 USD | 0,23 | 22,22% |
| 2026 parziale | 16 | -2.358,21 USD | 0,61 | 25,00% |

Per la variante R:R, il periodo 2021-2023 guadagna 5.348,57 USD con PF 1,30; il periodo 2024-2026 perde 7.192,92 USD con PF 0,59. L'edge decade nettamente nella parte recente.

## Risultato all-day per fascia di apertura

Valori della variante R:R 1% per trade, con gli orari del server Atene convertiti in UTC.

| Fascia di apertura | Trade | Netto | PF | Win rate |
|---|---:|---:|---:|---:|
| Asia 00:00-08:00 UTC | 49 | -7.464,02 USD | 0,58 | 30,61% |
| Londra 08:00-12:30 UTC | 32 | +1.003,45 USD | 1,10 | 43,75% |
| Overlap/NY 12:30-17:00 UTC | 18 | +3.694,20 USD | 1,89 | 55,56% |
| Tarda 17:00-24:00 UTC | 12 | +922,02 USD | 1,26 | 41,67% |

Le 13 aperture che ricadono nella finestra originale 14:30-17:00 Europe/Rome producono +3.401,15 USD, PF 2,31 e win rate 61,54%. Le 98 aperture esterne perdono 5.245,50 USD con PF 0,84. Questa suddivisione del run all-day è diagnostica: non sostituisce il controllo NY, perché nell'all-day le posizioni non vengono chiuse alle 17:00.

L'Asia è la principale fonte di perdita. Londra e la fascia tarda sono positive in-sample ma hanno pochi trade e non sono una prova sufficiente per estendere l'operatività; richiederebbero test dedicati e una specifica delle liquidity pool coerente con quelle sessioni.

## Rifiuti tecnici degli ordini

| Variante all-day | Ordini eseguiti | Invalid stops (`10016`) | Margine insufficiente (`10019`) |
|---|---:|---:|---:|
| Regole esatte | 198 | 14 | 8 |
| R:R 0,5-3R | 111 | 2 | 1 |

Questi rifiuti non sono limiti di rischio generale. `10019` è la conseguenza della leva 1:30 quando il lotto necessario per rischiare l'1% con uno stop molto stretto richiede troppo margine; il sistema non riduce il lotto per forzare l'entrata.

## Test precedenti superati

I precedenti run all-day a rischio 1% riportavano 36 e 84 trade perché il circuito di drawdown fermava il campione. Anche l'audit a rischio 0,1% applicava quattro pause di 48 ore dopo serie di perdite. Non rappresentavano la definizione richiesta di rischio esclusivamente per trade e sono pertanto superati dai quattro test di questo documento.

## Conclusione

Non conviene tradiare sempre con questa logica. Eliminare la finestra NY:

- aumenta la frequenza, ma resta sotto un trade a settimana;
- trasforma le regole esatte da circa break-even a una perdita del 24,75%;
- trasforma la variante R:R da positiva nella finestra NY a negativa all-day;
- concentra la perdita soprattutto nella sessione asiatica;
- peggiora fortemente drawdown e stabilità 2024-2026.

La finestra temporale non è un filtro superfluo. L'espansione più sensata, se si vuole cercare maggiore frequenza, è testare separatamente fasce limitrofe alla sovrapposizione Europa/New York, non abilitare indiscriminatamente tutte le ore.

## Artefatti principali

- EA MQL5: `mt5/GoldTopDownSweepEA.mq5`
- Preset NY esatto: `mt5/GoldTopDownSweepEA_rome17_exact_risk1_per_trade.set`
- Preset NY R:R: `mt5/GoldTopDownSweepEA_rome17_rr_band_risk1_per_trade.set`
- Preset all-day esatto: `mt5/GoldTopDownSweepEA_all_day_exact_risk1_per_trade.set`
- Preset all-day R:R: `mt5/GoldTopDownSweepEA_all_day_rr_band_risk1_per_trade.set`
- Report NY esatto: `reports/mt5/gold_top_down_sweep_rome17_exact_risk1_per_trade.htm`
- Report NY R:R: `reports/mt5/gold_top_down_sweep_rome17_rr_band_risk1_per_trade.htm`
- Report all-day esatto: `reports/mt5/gold_top_down_sweep_all_day_exact_risk1_per_trade.htm`
- Report all-day R:R: `reports/mt5/gold_top_down_sweep_all_day_rr_band_risk1_per_trade.htm`
