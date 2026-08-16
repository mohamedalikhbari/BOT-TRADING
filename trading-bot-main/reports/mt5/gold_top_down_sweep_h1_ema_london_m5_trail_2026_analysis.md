# Backtest MT5 2026 — H1 EMA, pool Londra, sweep M5 e target trail

## Configurazione

- Periodo: 2026-01-01 — 2026-08-07 (ultimo giorno disponibile nel test)
- XAUUSD M1, modello MT5 a tick reali
- Qualità storico: 100% tick reali
- 51.310.787 tick, 211.566 barre
- Capitale iniziale: 50.000 USD
- Leva: 1:30
- Rischio: 1% dell'equity per trade, senza limite lotti imposto dall'EA
- Finestra ingressi: 08:30–11:00 `America/New_York`

## Regole della variante

- Nessun controllo H4.
- Bias H1: EMA21 sopra EMA50 per long, EMA21 sotto EMA50 per short.
- Pullback: prezzo M5 di conferma entro 0,15 ATR H1 dalla EMA21 H1.
- PNYH/PNYL sostituiti da PLH/PLL, calcolati sulla precedente sessione Londra 08:00–16:30 `Europe/London`.
- ASH/ASL, PDH/PDL e PRE_NY_H/PRE_NY_L restano monitorati.
- Sweep solo M5: penetrazione minima 0,10 ATR M5, chiusura di reclaim e wick ratio minimo 0,35.
- Trigger M1: zona FVG, IFVG oppure Order Block formatasi dopo lo sweep; successivo BOS M1 nella direzione del bias, confermato dalla chiusura oltre lo swing. La sola wick non vale.
- Stop: oltre l'estremo dello sweep con buffer fisso di 0,80 USD.
- Target teorico: precedente swing H1 nella direzione del trade; R:R ammesso 0,50–3,00.
- Nessun TP inviato al broker.
- Al 50% del percorso entry–target: stop a break-even; poi trailing a distanza pari al 50% del percorso iniziale.
- Dal raggiungimento del target teorico: trailing a distanza pari al 10% del percorso iniziale, quindi al primo tocco protegge il 90%.
- Uscita temporale invariata: Sydney 09:30 lunedì–giovedì; venerdì due ore prima della chiusura settimanale broker.

## Risultato

| Metrica | Valore |
|---|---:|
| Profitto netto | -1.465,45 USD (-2,93%) |
| Saldo finale | 48.534,55 USD |
| Trade | 3 |
| Vincenti | 0 |
| Perdenti | 3 |
| Profit factor | 0,00 |
| Payoff medio | -488,48 USD |
| Drawdown massimo equity | 1.676,97 USD (3,34%) |
| Drawdown massimo balance | 1.465,45 USD (2,93%) |

| Apertura | Direzione | Risultato | MFE rispetto al target teorico |
|---|---:|---:|---:|
| 2026-04-13 | Short | -495,84 USD | 20,6% |
| 2026-07-27 | Long | -498,55 USD | 5,9% |
| 2026-08-06 | Long | -471,06 USD | 49,8% |

Tutti e tre gli ingressi erano nella finestra New York (10:24, 09:42 e 09:41 locali). Nessun trade ha raggiunto il 50% del target teorico, quindi break-even e trailing non si sono mai attivati. Il terzo trade si è fermato circa 0,04 USD prima della soglia di attivazione.

## Diagnostica del funnel

- Barre M5 nella finestra: 4.723.
- Scartate perché fuori dalla tolleranza EMA21: 4.382.
- Contesti H1 EMA/pullback validi: 337.
- Sweep M5 validi: 8.
- Setup annullati da CHOCH M1 contrario: 4.
- Trigger BOS M1: 4.
- Ordini scartati per R:R inferiore a 0,50: 1.
- Trade eseguiti: 3.

Il filtro dominante è il pullback entro 0,15 ATR H1, che elimina il 92,8% delle barre M5 della finestra. Sul campione 2026 questa variante non è risultata profittevole; tre operazioni sono inoltre troppo poche per stimarne la robustezza.
