# GoldIntradayEA best-frequency-profit — frozen

Questa versione e congelata su richiesta dell'utente e non deve essere modificata.
Qualunque ricerca successiva deve usare un nuovo EA o un nuovo nome di preset,
senza alterare i file congelati elencati qui.

## File canonici

- `mt5/GoldIntradayEA.mq5`
- `mt5/GoldIntradayEA.ex5`
- `mt5/GoldIntradayEA_best_frequency_profit_2026.set`
- `tools/mt5_gold_intraday_best_frequency_profit_2026.ini`
- `tools/mt5_gold_intraday_best_frequency_profit_verified_history.ini`
- `tools/mt5_gold_intraday_best_frequency_profit_all_available_real_ticks.ini`
- `tools/mt5_gold_intraday_best_frequency_profit_all_available_lev100.ini`

## Checksum al congelamento

- MQ5 SHA-256: `11e7b9416f26a352f0d32b8a19c3bc737afe8c5c4a941443e3ae40862d7edcf0`
- EX5 SHA-256: `eef890df2b173d67fafd44b2b1d07715c6449107576f40ed9839c2184136fb48`
- preset SHA-256: `64f4eb40885c136332b241aab7bfecddf2eeff9f6013b6ef26bdea5cffb40284`

## Configurazione congelata

- ensemble H1 Keltner EMA70/ATR10/2ATR + RSI25;
- rischio nominale 1% equity per trade;
- leva di riferimento finale 1:100;
- lotto massimo EA 100 (non limitante rispetto al broker);
- una posizione alla volta;
- drawdown throttle attivo e circuit breaker al 40%;
- `InpTesterOnly=true`, live trading disabilitato.

## Risultati di riferimento MT5

- 2026-01-01 / 2026-08-07: 149 trade, +31.799,91 USD, PF 1,55,
  drawdown equity relativo 15,56%.
- 2021-09-06 / 2026-08-07, feed verificato: 1.250 trade,
  +58.826,96 USD, PF 1,22, drawdown equity 28,21%.
- 2019-05-24 / 2026-08-07, massimo richiesto: 1.822 trade,
  +80.731,75 USD, PF 1,20, drawdown equity 30,85%; il tratto precedente
  al 6 settembre 2021 contiene anomalie del feed ed e solo informativo.

Le simulazioni 1:30 e 1:100 hanno prodotto la stessa sequenza di trade e lo
stesso risultato; la leva 1:100 ha aumentato soltanto il livello di margine.
