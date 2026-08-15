# Gold Top-Down Sweep — rischio 1%, leva 1:30, nessun limite lotti EA

Strategia e finestra sono identiche alla versione letterale 14:30-17:00 `Europe/Rome`. Cambiano esclusivamente:

- `RISK_PER_TRADE_PCT = 1%` dell'equity;
- leva del tester `1:30`;
- nessun tetto al volume imposto dall'EA: valgono soltanto massimo lotti del broker e margine disponibile.

## Backtest MT5 a tick reali

- Periodo: 6 settembre 2021 – 7 agosto 2026.
- Qualità: 100% tick reali, 262.427.146 tick e 1.740.924 barre M1.
- Deposito iniziale: 50.000 USD.
- Profitto netto: **+138,43 USD (+0,28%)**.
- Profit factor: **1,01**.
- Payoff atteso: **+2,61 USD per trade**.
- Drawdown massimo equity: **3.385,01 USD (6,44%)**.
- Livello di margine minimo riportato: **134,23%**.
- Trade eseguiti: **53**, circa **0,21 a settimana**.
- Vincenti: **32/53 (60,38%)**.
- Vincita media: **312,79 USD**; perdita media: **-470,04 USD**.
- Lotto minimo: **0,07**; massimo: **4,79**; medio: **0,99**; mediano: **0,73**.

Un segnale long non è stato eseguito perché MT5 ha restituito `10019` (`NO_MONEY`): il volume calcolato all'1% non era compatibile con il margine disponibile a leva 1:30. Altri due ordini sono stati rifiutati con `10016` per stop non valido.

| Anno | Trade | Netto | PF |
|---:|---:|---:|---:|
| 2021 (dal 06/09) | 2 | -409,09 USD | 0,21 |
| 2022 | 11 | +284,40 USD | 1,14 |
| 2023 | 12 | +113,01 USD | 1,06 |
| 2024 | 9 | +557,36 USD | 1,24 |
| 2025 | 10 | +333,56 USD | 1,22 |
| 2026 (fino al 07/08) | 9 | -740,81 USD | 0,51 |

Il blocco 2021-2023 produce -11,68 USD con PF 1,00; il blocco 2024-2026 +150,11 USD con PF 1,03. Long: +551,70 USD, PF 1,12. Short: -413,27 USD, PF 0,92.

## Confronto con rischio 0,5%, leva 1:100 e cap 2 lotti

| Configurazione | Netto | PF | DD equity | Trade | Lotto max |
|---|---:|---:|---:|---:|---:|
| 0,5%, leva 1:100, cap 2 | -70,86 USD | 0,99 | 3,30% | 54 | 2,00 |
| 1%, leva 1:30, nessun cap EA | +138,43 USD | 1,01 | 6,44% | 53 | 4,79 |

Il cambio di sizing non crea un vantaggio strategico: il profit factor resta sostanzialmente 1, mentre il drawdown quasi raddoppia. Il piccolo utile dipende anche dal diverso dimensionamento relativo dei singoli trade e non è proporzionale in modo lineare al test precedente.
