# Table of Contents

# Specifica tecnica — Sistema automatizzato XAU/USD multi-timeframe

**Versione 1.4 — 3 agosto 2026**

**Documento di specifica per sviluppo software.** Non è codice: è il contratto funzionale che il codice deve rispettare. Ogni definizione è pensata per essere implementabile senza interpretazione.

**Sessione operativa: esclusivamente apertura di New York.** Londra e Asia non sono sessioni operative.

**Modifiche rispetto alla v1.2:** rimosso ogni controllo e contributo allo scoring del Fibonacci H4; il filtro superiore richiede bias H4 e struttura H1 allineati. I liquidity pool sono monitorati in parallelo su ASH/ASL, PNYH/PNYL, PDH/PDL e PRE_NY_H/PRE_NY_L. Lo stesso evento di sweep deve essere confermato sia su M15 sia sulle candele M5 interne, con parametri M5 indipendenti. Introdotti scoring multi-pool e journal dello sweep multi-livello.

**Modifiche rispetto alla v1.3:** `MIN_WICK_RATIO_M5` ridotto da 0.50 a 0.35 e timeout dello stato `ENTRY_ARMED` esteso da 20 a 45 candele M1. Tutto il resto resta invariato, incluso il filtro Fibonacci esclusivamente M5.

## PARTE 1 — Architettura del sistema

### 1.1 Componenti

Il sistema si divide in sette moduli indipendenti. Ogni modulo ha un input definito, un output definito, e può essere testato da solo.

| \#  | Modulo            | Responsabilità                                                   | Input                       | Output                                     |
|-----|-------------------|------------------------------------------------------------------|-----------------------------|--------------------------------------------|
| 1   | `DataFeed`        | Ricezione e normalizzazione candele multi-TF                     | Stream broker / API         | Candele OHLCV validate, timestamp UTC      |
| 2   | `StructureEngine` | Calcolo swing, struttura di mercato, BOS/CHoCH                   | Candele per TF              | Oggetti strutturali con timestamp          |
| 2b  | `TrendEngine`     | Calcolo EMA, allineamento, pendenza normalizzata                 | Candele H4 (e H1 se attivo) | Bias direzionale + metriche di forza       |
| 3   | `ZoneEngine`      | Calcolo FVG, Order Block, zone premium/discount, liquidity pools | Candele + struttura         | Zone attive con stato                      |
| 4   | `SignalEngine`    | Valutazione della cascata multi-TF e generazione segnale         | Struttura + zone            | Segnale con direzione, entry, SL, TP       |
| 5   | `RiskManager`     | Sizing, validazione limiti, veto                                 | Segnale + stato conto       | Ordine approvato o rifiutato               |
| 6   | `NewsFilter`      | Blackout e classificazione eventi macro                          | Calendario economico        | Stato: `TRADE_OK` / `BLACKOUT` / `REDUCED` |
| 7   | `ExecutionEngine` | Invio ordini, gestione posizione, exit                           | Ordine approvato            | Posizione aperta/gestita/chiusa            |

**Regola architetturale non negoziabile:** `RiskManager` e `NewsFilter` hanno potere di veto assoluto su `SignalEngine`. Un segnale perfetto viene scartato se viola un limite di rischio. Non esistono eccezioni configurabili a runtime.

### 1.2 Flusso di esecuzione

    Ogni chiusura candela 1M:
      1. DataFeed aggiorna tutti i TF
      2. StructureEngine ricalcola struttura su TF modificati
      3. ZoneEngine aggiorna/invalida zone
      4. NewsFilter verifica stato → se BLACKOUT, esci
      5. SignalEngine valuta cascata 4H→1H→15M→5M→1M
      6. Se segnale: RiskManager valuta → approva o veta
      7. Se approvato: ExecutionEngine invia ordine
      8. ExecutionEngine gestisce posizioni aperte (BE, parziali, trailing)

### 1.3 Stack tecnologico consigliato

**Opzione A — MetaTrader 5 + Python (consigliata per iniziare)** - MT5 come terminale di esecuzione e fonte dati - Libreria `MetaTrader5` per Python per il controllo - Vantaggio: broker già integrati, dati storici disponibili, esecuzione testata - Svantaggio: Windows-dependent, meno controllo sulla latenza

**Opzione B — Python nativo + API broker REST/WebSocket** - Broker con API diretta (cTrader Open API, Interactive Brokers, OANDA) - Vantaggio: pieno controllo, deployabile su Linux/VPS - Svantaggio: più lavoro infrastrutturale

**Librerie chiave in entrambi i casi:** - `pandas` / `polars` per gestione serie temporali - `numpy` per calcoli vettoriali - `pydantic` per validazione oggetti di dominio - `SQLite` o `TimescaleDB` per storico e journal - `pytest` per la suite di test (obbligatoria, vedi Parte 9)

**Requisito architetturale:** il core deve essere scritto in Python puro e disaccoppiato dal broker. `DataFeed` ed `ExecutionEngine` sono interfacce astratte con implementazioni intercambiabili (storico locale, demo, live). Cambiare fonte dati o broker non deve richiedere modifiche alla logica di strategia.

## PARTE 2 — Definizioni formali

Questa è la parte centrale del documento. Ogni definizione qui è pensata per essere implementabile senza interpretazione.

### 2.1 Candela

    Candle = {
      timestamp: datetime (UTC, apertura candela)
      open, high, low, close: float
      volume: float (tick volume se real volume non disponibile)
      timeframe: enum {M1, M5, M15, H1, H4}
    }

**Regole:** - Tutti i timestamp in UTC. Le conversioni a ora italiana avvengono solo nel `NewsFilter` e nel logging. - Una candela è valutabile solo dopo la chiusura. Nessuna logica opera su candele in formazione, salvo dove esplicitamente indicato (trailing stop). - Candele con `volume == 0` o gap superiori a `MAX_GAP_ATR` (default: 3× ATR14 del TF) vengono flaggate e la valutazione del TF viene sospesa per `N` candele (default: 3).

### 2.2 Swing point (frattale)

Base di tutto il resto. Definizione a finestra fissa.

    SwingHigh(i, k):
      candle[i].high > candle[j].high  per ogni j in [i-k, i-1]
      AND
      candle[i].high > candle[j].high  per ogni j in [i+1, i+k]

    SwingLow(i, k):
      candle[i].low < candle[j].low  per ogni j in [i-k, i-1]
      AND
      candle[i].low < candle[j].low  per ogni j in [i+1, i+k]

**Parametro** `k` **(lookback/lookforward) per timeframe:**

| TF  | k   | Motivazione                        |
|-----|-----|------------------------------------|
| H4  | 3   | Swing strutturali maggiori         |
| H1  | 3   | Struttura intermedia               |
| M15 | 2   | Sensibilità ai livelli di sessione |
| M5  | 2   | Conferma reattiva                  |
| M1  | 1   | Massima sensibilità per il trigger |

**Conseguenza critica:** uno swing è confermato solo `k` candele dopo la sua formazione. Il sistema non può usare uno swing “in tempo reale”. Questo introduce un ritardo strutturale che va accettato e rappresentato fedelmente nel codice — mai aggirato usando swing non confermati.

**Gestione swing uguali:** se `candle[i].high == candle[j].high`, usa il primo in ordine temporale. Nessun swing duplicato allo stesso livello entro `ATR14 * 0.1`.

### 2.3 Struttura di mercato

    MarketStructure(TF) = {
      last_swing_high: SwingPoint
      last_swing_low: SwingPoint
      prev_swing_high: SwingPoint
      prev_swing_low: SwingPoint
      trend: enum {BULLISH, BEARISH, RANGING}
    }

**Determinazione del trend:**

    BULLISH  se  last_swing_high > prev_swing_high  AND  last_swing_low > prev_swing_low
    BEARISH  se  last_swing_high < prev_swing_high  AND  last_swing_low < prev_swing_low
    RANGING  in tutti gli altri casi

**Regola operativa:** se `trend == RANGING` su H4 o su H1, il sistema non opera. Nessuna eccezione. Il range è dove questa strategia perde di più, perché gli sweep sono bidirezionali e i BOS sono falsi.

### 2.4 Break of Structure (BOS)

    BOS_BULLISH:
      close[i] > last_swing_high.price
      AND trend era già BULLISH prima del break
      AND (close[i] - last_swing_high.price) >= MIN_BREAK_ATR * ATR14

    BOS_BEARISH:
      close[i] < last_swing_low.price
      AND trend era già BEARISH prima del break
      AND (last_swing_low.price - close[i]) >= MIN_BREAK_ATR * ATR14

`MIN_BREAK_ATR` **default: 0.05** (cioè il break deve superare il livello di almeno il 5% dell’ATR).

Questo parametro esiste per eliminare i break “di un pip” che sono rumore. Deve essere configurabile ma il sistema deve rifiutare il valore zero.

**Fondamentale — la rottura è sulla CHIUSURA, non sul wick.** Un high che buca il livello e rientra non è un BOS: è, potenzialmente, un liquidity sweep. Confondere i due è l’errore che distrugge questo tipo di sistemi.

### 2.5 Change of Character (CHoCH)

    CHoCH_BULLISH:
      trend corrente == BEARISH
      AND close[i] > last_swing_high.price
      AND break confermato con MIN_BREAK_ATR

    CHoCH_BEARISH:
      trend corrente == BULLISH
      AND close[i] < last_swing_low.price
      AND break confermato con MIN_BREAK_ATR

Il CHoCH è il primo segnale di inversione. Nel tuo sistema serve principalmente come **invalidazione**: un CHoCH su H1 contro il bias H4 sospende l’operatività fino a riallineamento.

### 2.6 Filtro di trend EMA (bias primario H4)

Il bias direzionale su H4 è determinato dalle medie mobili esponenziali. Questo è il filtro primario: oggettivo, non ambiguo, indipendente dalla scelta della swing di riferimento.

    EMA(period) = media mobile esponenziale sulle chiusure

    Parametri di default:
      EMA_FAST = 21
      EMA_SLOW = 50
      EMA_MACRO = 200   (filtro opzionale, vedi sotto)

**Determinazione del bias:**

    BIAS_LONG:
      close > EMA_FAST
      AND EMA_FAST > EMA_SLOW
      AND slope(EMA_SLOW) > MIN_EMA_SLOPE

    BIAS_SHORT:
      close < EMA_FAST
      AND EMA_FAST < EMA_SLOW
      AND slope(EMA_SLOW) < -MIN_EMA_SLOPE

    BIAS_NONE:
      in tutti gli altri casi → il sistema non opera

**Calcolo della pendenza:**

    slope(EMA, lookback) = (EMA[now] - EMA[now - lookback]) / (ATR14_H4 * lookback)

    EMA_SLOPE_LOOKBACK = 6 candele H4 (24 ore)
    MIN_EMA_SLOPE = 0.05

La pendenza è normalizzata sull’ATR, quindi il valore è confrontabile tra regimi di volatilità diversi. Una EMA piatta produce slope vicino a zero e blocca l’operatività: è esattamente il comportamento voluto, perché il mercato laterale è dove questa strategia perde di più.

**Filtro macro opzionale (**`USE_EMA_MACRO`**, default** `false`**):**

    Se attivo:
      BIAS_LONG richiede anche  close > EMA_200
      BIAS_SHORT richiede anche close < EMA_200

Riduce sensibilmente il numero di setup ma migliora la qualità media. Va esposto in configurazione e valutato sui dati.

**Rapporto tra EMA e struttura di mercato.** Le EMA determinano la direzione; la struttura determina la validità. I due lavorano insieme così:

| Situazione                                                | Azione                                 |
|-----------------------------------------------------------|----------------------------------------|
| EMA allineate + struttura concorde                        | Bias attivo, si opera                  |
| EMA allineate + struttura `RANGING`                       | Bias sospeso                           |
| EMA allineate + CHoCH H4 contrario nelle ultime 3 candele | Bias sospeso fino a nuovo BOS concorde |
| EMA non allineate                                         | Bias assente, nessuna valutazione      |

Un CHoCH contro la direzione delle EMA è il primo segnale che il trend sta girando: le EMA se ne accorgeranno con ritardo, la struttura no. Per questo la struttura mantiene potere di veto anche quando le EMA sono perfettamente allineate.

**Nota sull’inizializzazione.** L’EMA richiede un periodo di warm-up: il sistema non deve generare bias finché non ha almeno `EMA_SLOW * 3` candele H4 di storico caricate (150 candele, cioè circa 25 giorni). Con `USE_EMA_MACRO` attivo servono `200 * 3 = 600` candele.

### 2.7 Fibonacci 50–75% — uso esclusivo M5

Il Fibonacci non viene usato su H4: non è un veto, non assegna punti e non partecipa alla determinazione del bias. Il bias superiore dipende esclusivamente da EMA e struttura secondo le sezioni 2.6, 3.2 e 3.3. Il Fibonacci resta un filtro operativo solo su M5, applicato alla gamba successiva allo sweep confermato su entrambi i timeframe.

#### 2.7.1 Calcolo della zona

**Bias LONG:**

    origin  = estremo minimo dello sweep M5 confermato
    extreme = massimo della reazione successiva
    range = extreme - origin

    fib_50  = extreme - (range * 0.50)
    fib_75  = extreme - (range * 0.75)
    fib_786 = extreme - (range * 0.786)

    ZONA_PREMIUM = [fib_75, fib_50]      // fib_75 è il livello più basso
    INVALIDAZIONE = price < fib_786

**Bias SHORT:**

    origin  = estremo massimo dello sweep M5 confermato
    extreme = minimo della reazione successiva
    range = origin - extreme

    fib_50  = extreme + (range * 0.50)
    fib_75  = extreme + (range * 0.75)
    fib_786 = extreme + (range * 0.786)

    ZONA_PREMIUM = [fib_50, fib_75]
    INVALIDAZIONE = price > fib_786

**Selezione della gamba di riferimento su M5:** usa la gamba di reazione definita nella sezione 2.7.3, con origine sull’estremo dello sweep M5 confermato. Gli estremi sono aggiornati solo con candele chiuse.

Se non esiste ancora una gamba M5 valida, il sistema attende fino al timeout dello stato `SWEEP_CONFIRMED`.

#### 2.7.2 Uso su H4 — disattivato

Su H4 non viene calcolata alcuna posizione premium/discount ai fini decisionali. Non esiste veto a 78.6%, non esiste bonus `IN_ZONE`/`NEAR_ZONE` e nessuna misura Fibonacci H4 entra nello scoring. L’unico filtro top-down è l’allineamento tra bias EMA/struttura H4 e struttura H1.

#### 2.7.3 Uso su M5 — filtro operativo

Su M5 il Fibonacci si applica alla **gamba di reazione post-sweep**, non alla struttura generale. È la parte che affina il punto di ingresso.

    DEFINIZIONE DELLA GAMBA DI REAZIONE M5:

      origin  = estremo raggiunto dalla candela di sweep
                (il low dello sweep se bias LONG, l'high se bias SHORT)

      extreme = estremo opposto raggiunto dal movimento di reazione
                prima del primo pullback significativo
                (il massimo più alto se LONG, il minimo più basso se SHORT)

      reaction_range = |extreme - origin|
    FILTRO M5 (bias LONG):
      fib_50_m5 = extreme - (reaction_range * 0.50)
      fib_75_m5 = extreme - (reaction_range * 0.75)

      ZONA_ENTRATA_M5 = [fib_75_m5, fib_50_m5]

      Il pullback deve rientrare in questa fascia prima di scendere su M1.

    FILTRO M5 (bias SHORT): speculare

**Comportamento del filtro:**

| Posizione del pullback                | Azione                                               |
|---------------------------------------|------------------------------------------------------|
| Dentro \[50%, 75%\]                   | Setup valido, si procede su M1                       |
| Sopra il 50% (pullback poco profondo) | Attendi: il prezzo non ha ancora dato un buon prezzo |
| Oltre il 75% ma sotto il 78.6%        | Setup valido ma con penalità nello scoring           |
| Oltre il 78.6%                        | Setup **scartato**: la reazione non ha tenuto        |

`M5_FIB_MODE` **— parametro di configurazione:**

    STRICT   → il pullback deve essere in [50%, 75%], altrimenti scarto  (default)
    LENIENT  → accetta [38.2%, 78.6%], applica penalità fuori da [50%, 75%]
    OFF      → filtro disattivato, si passa direttamente a M1

Questo parametro va esposto perché è quello che regola direttamente il compromesso tra numero di setup e qualità media. Partire da `STRICT`.

### 2.8 Fair Value Gap (FVG)

Definizione a tre candele.

    FVG_BULLISH (i è la candela centrale):
      candle[i-1].high < candle[i+1].low
      → gap = [candle[i-1].high, candle[i+1].low]

    FVG_BEARISH (i è la candela centrale):
      candle[i-1].low > candle[i+1].high
      → gap = [candle[i+1].high, candle[i-1].low]
    FVG = {
      top: float
      bottom: float
      midpoint: float = (top + bottom) / 2
      direction: enum {BULLISH, BEARISH}
      created_at: timestamp
      timeframe: TF
      state: enum {FRESH, PARTIAL, MITIGATED, INVERTED}
    }

**Filtro dimensionale obbligatorio:**

    size = top - bottom
    FVG valido solo se  size >= MIN_FVG_ATR * ATR14

`MIN_FVG_ATR` default: **0.15** su M1, **0.20** su M5.

Senza questo filtro, su M1 il sistema troverà decine di micro-FVG irrilevanti a ogni sessione. Questo è il singolo parametro che più influenza la qualità del sistema sul timeframe di entrata.

**Transizioni di stato:**

    FRESH     → PARTIAL   quando price entra nel gap ma non lo attraversa
    PARTIAL   → MITIGATED quando price attraversa il midpoint
    MITIGATED → INVERTED  quando price chiude completamente oltre il gap dal lato opposto

### 2.9 Inversion FVG (IFVG)

    IFVG_BULLISH:
      esisteva un FVG_BEARISH
      AND close ha superato completamente il gap verso l'alto
      → il gap ex-bearish diventa zona di supporto

    IFVG_BEARISH:
      esisteva un FVG_BULLISH
      AND close ha superato completamente il gap verso il basso
      → il gap ex-bullish diventa zona di resistenza

**Validità temporale:** un IFVG resta valido per `IFVG_MAX_AGE` candele dalla conversione (default: 30 su M1, 20 su M5). Oltre, viene scartato.

**Perché è utile nel tuo sistema:** l’IFVG è statisticamente un livello di reazione più affidabile del FVG fresco per le entrate in continuazione, perché rappresenta un livello dove il mercato ha già dimostrato di aver cambiato posizione. Va trattato come segnale di qualità superiore (vedi scoring, sezione 4.3).

### 2.10 Order Block (OB)

    OB_BULLISH:
      ultima candela ribassista (close < open)
      PRIMA di un movimento impulsivo rialzista
      dove il movimento impulsivo è definito come:
        - almeno MIN_IMPULSE_CANDLES candele consecutive rialziste (default 2)
        - AND il movimento supera l'high dell'OB di almeno MIN_IMPULSE_ATR * ATR14 (default 1.0)
        - AND genera almeno un FVG nella direzione del movimento

      zona OB = [candle.low, candle.high]
      zona OB refined = [candle.low, candle.open]   ← usa questa per l'entry
    OB_BEARISH:
      ultima candela rialzista (close > open)
      PRIMA di un movimento impulsivo ribassista
      (condizioni speculari)

      zona OB = [candle.low, candle.high]
      zona OB refined = [candle.open, candle.high]

**Uso della zona refined:** l’entry avviene sulla zona refined (corpo della candela), lo stop loss va oltre l’estremo della zona completa (wick incluso). Questo massimizza l’R:R mantenendo lo stop protetto.

**Stato OB:**

    UNMITIGATED → price non è ancora tornato nella zona
    MITIGATED   → price ha toccato la zona refined
    INVALIDATED → close oltre l'estremo della zona completa

Un OB `INVALIDATED` non è più utilizzabile. Un OB `MITIGATED` una volta è utilizzabile con priorità ridotta; dopo due mitigazioni viene scartato.

### 2.11 Sessione operativa e liquidity pool

**Il sistema opera esclusivamente sull’apertura di New York.** Le sessioni di Londra e Asia non sono sessioni operative: nessun setup viene valutato al di fuori della finestra NY definita sotto.

    SESSIONE OPERATIVA = New York

    NY_OPEN  = 09:30 ora di New York  (America/New_York, DST automatico)

    FINESTRA_TRADING = [08:30, 11:00] America/New_York
                      = [NY_OPEN - 60min, NY_OPEN + 90min]

**Ancoraggio temporale — regola critica.** Il sistema calcola la finestra convertendo dal fuso `America/New_York`, mai da un orario UTC fisso e mai dall’ora italiana. Nelle 2–3 settimane l’anno in cui USA ed Europa cambiano ora in date diverse, un orario UTC hardcoded sposta la finestra di un’ora intera. Usa una libreria timezone-aware (`zoneinfo` in Python 3.9+), non offset manuali.

La finestra limita la formazione del setup e l'apertura di nuovi ordini. Una posizione gia aperta puo continuare oltre le 11:00 New York fino a SL, TP o alla chiusura forzata definita in 5.4.

**Liquidity pool monitorati in parallelo:**

    ASH / ASL = Asian Session High / Low
                Massimo e minimo tra 00:00 UTC e 08:00 UTC dello stesso giorno.

    PNYH / PNYL = Previous New York Session High / Low
                  Massimo e minimo della sessione 09:30–17:00 America/New_York
                  dell’ultimo giorno di trading precedente con dati.

    PDH / PDL = Previous Day High / Low
                Massimo e minimo dell’ultimo giorno di trading completo
                17:00–17:00 America/New_York.

    PRE_NY_H / PRE_NY_L = Pre-NY Range High / Low
                          Massimo e minimo da 00:00 UTC fino a NY_OPEN
                          dello stesso giorno.

Il sistema non seleziona in anticipo un livello di riferimento. Mantiene tutti i pool contemporaneamente e usa quelli effettivamente spazzati dal movimento.

    LiquidityPool = {
      price: float
      type: enum {ASH, ASL, PNYH, PNYL, PDH, PDL, PRE_NY_H, PRE_NY_L}
      formed_at: datetime
      state: enum {INTACT, SWEPT}
    }

**Disponibilità e assenza di look-ahead:** ASH/ASL diventano definitivi alle 08:00 UTC; PNYH/PNYL alle 17:00 New York della sessione precedente; PDH/PDL alla chiusura del giorno 17:00–17:00; PRE_NY_H/PRE_NY_L evolvono fino a NY_OPEN. Una candela M15 può usare solo il valore del pool disponibile prima della propria apertura. Quando un evento valido spazza un pool, lo stato passa da `INTACT` a `SWEPT`; il journal conserva tutti i tipi coinvolti.

Asia e pre-NY restano esclusivamente finestre di formazione della liquidità: non diventano sessioni operative. Il sistema continua a valutare setup soltanto nella finestra NY.

### 2.12 Liquidity Sweep (LS)

Definizione precisa — questa è la più delicata. La formula è identica sui due timeframe, ma usa ATR e parametri del timeframe valutato.

    LS_HIGH (sweep di un massimo, prelude a un movimento SHORT):
      candle[i].high > liquidity_level
      AND candle[i].close < liquidity_level
      AND (candle[i].high - liquidity_level) >= MIN_SWEEP_ATR_TF * ATR14_TF
      AND (candle[i].high - candle[i].close) / (candle[i].high - candle[i].low) >= MIN_WICK_RATIO_TF

    LS_LOW (sweep di un minimo, prelude a un movimento LONG):
      candle[i].low < liquidity_level
      AND candle[i].close > liquidity_level
      AND (liquidity_level - candle[i].low) >= MIN_SWEEP_ATR_TF * ATR14_TF
      AND (candle[i].close - candle[i].low) / (candle[i].high - candle[i].low) >= MIN_WICK_RATIO_TF

**Chiarimento sulla direzione, perché è fonte di confusione costante:** - Sweep di un **massimo** (il prezzo buca un high e rientra) → i compratori sono stati intrappolati → movimento atteso **ribassista** → cerchi **SHORT** - Sweep di un **minimo** (il prezzo buca un low e rientra) → i venditori sono stati intrappolati → movimento atteso **rialzista** → cerchi **LONG**

**Parametri M15:** `MIN_SWEEP_ATR_M15` default **0.10** e `MIN_WICK_RATIO_M15` default **0.50**.

**Parametri M5:** `MIN_SWEEP_ATR_M5` default **0.10** e `MIN_WICK_RATIO_M5` default **0.35**. Sono indipendenti dai parametri M15 e vengono calcolati sull’ATR14 M5.

**Sweep multi-pool:** una singola candela o sequenza può oltrepassare più pool dalla stessa parte. L’evento conserva la lista completa dei pool che soddisfano la formula. Un pool è conteggiato nello scoring soltanto se lo stesso livello è confermato sia su M15 sia su almeno una delle tre candele M5 che compongono la candela M15 dell’evento.

**Vincolo di coerenza con il bias:** lo sweep è valido solo se la sua direzione attesa coincide con il bias H4. Se il bias è LONG e si verifica uno sweep di un massimo (che implica short), l’evento viene registrato ma non genera setup.

**Finestra temporale:** lo sweep deve verificarsi entro la finestra operativa NY (sezione 3.4). Sweep fuori finestra vengono ignorati, anche se tecnicamente validi.

## PARTE 3 — Pipeline di esecuzione multi-timeframe

### 3.1 Principio di cascata

Ogni livello è un **filtro binario**. Se un livello non passa, la valutazione si ferma e nessun livello inferiore viene calcolato. Non esistono compensazioni: un segnale fortissimo su M1 non compensa un H4 in range.

Lo stato del sistema è una macchina a stati espliciti:

    IDLE
      → BIAS_ACTIVE       (bias H4 + struttura H1 allineati)
      → SWEEP_DETECTED    (LS confermato su M15 in finestra)
      → SWEEP_CONFIRMED   (M5 conferma lo stesso sweep e gli stessi pool)
      → ENTRY_ARMED       (M1 ha formato FVG/OB, si attende il BOS)
      → IN_POSITION       (ordine eseguito)
      → IDLE              (posizione chiusa o setup invalidato)

Ogni stato ha un **timeout** e una **condizione di invalidazione**. Uno stato che scade torna a `IDLE`.

### 3.2 Livello 1 — H4 (bias direzionale)

Il bias è determinato dalle EMA e validato dalla struttura. Il Fibonacci H4 è completamente escluso sia dall’ammissibilità sia dallo scoring.

    CONDIZIONI BLOCCANTI (tutte necessarie):
      1. Bias EMA definito: BIAS_LONG o BIAS_SHORT secondo sezione 2.6
         - close oltre EMA_FAST nella direzione
         - EMA_FAST e EMA_SLOW allineate
         - |slope(EMA_SLOW)| >= MIN_EMA_SLOPE
      2. Warm-up EMA completato (storico sufficiente caricato)
      3. MarketStructure(H4).trend != RANGING
      4. Nessun CHoCH H4 contrario al bias EMA nelle ultime 3 candele
      5. Se USE_EMA_MACRO attivo: close dal lato corretto di EMA_200

    FATTORI DI QUALITÀ (non bloccanti, alimentano lo scoring):
      - Ampiezza della pendenza EMA (trend forte vs trend debole)
      - Distanza del prezzo da EMA_FAST (prezzo esteso vs prezzo vicino alla media)

    OUTPUT: {
      bias_direction: LONG | SHORT | NONE,
      ema_slope_normalized: float,
      quality_flags: list
    }

**Frequenza di valutazione:** a ogni chiusura candela H4, con verifica dell’allineamento H4–H1 a ogni chiusura M15 nella finestra operativa.

**Timeout:** il bias resta valido per `BIAS_MAX_AGE` candele H4 (default: 6, cioè 24 ore) e viene invalidato immediatamente se le EMA perdono l’allineamento.

**Regola esplicita:** nessun prezzo o livello Fibonacci H4 può bloccare, favorire o penalizzare un setup. La direzione H4 deve coincidere con la direzione strutturale H1 prima di valutare i liquidity pool.

### 3.3 Livello 2 — H1 (conferma trend)

    CONDIZIONI (tutte necessarie):
      1. MarketStructure(H1).trend == bias_direction H4
      2. Ultimo evento strutturale H1 è un BOS nella direzione del bias
         (non un CHoCH contrario)
      3. Nessun CHoCH H1 contrario al bias nelle ultime 5 candele
      4. Il prezzo non ha violato l'ultimo swing low (se LONG) o high (se SHORT) di H1
      5. Opzionale (USE_EMA_H1, default false): close H1 dal lato corretto di EMA_FAST_H1

    OUTPUT: h1_confirmed: bool, h4_h1_aligned: bool

**Nota:** l’allineamento H4–H1 è obbligatorio e binario. La condizione 2 resta più stringente del semplice allineamento: serve un evento di rottura recente e nella direzione giusta, non solo una struttura che tecnicamente rispetta la definizione.

### 3.4 Livello 3 — M15 (liquidity sweep)

**Finestra operativa — solo apertura New York:**

    FINESTRA = [NY_OPEN - 60min, NY_OPEN + 90min]
    dove NY_OPEN = 09:30 nel fuso America/New_York

    La finestra locale e quindi 08:30-11:00 America/New_York.
    Il sistema NON deve usare un equivalente italiano o UTC hardcoded:
    deve convertire dal fuso NY a ogni valutazione.

    Fuori da questa finestra il sistema è in IDLE e non valuta alcun setup.
    Nessun'altra sessione è operativa.
    CONDIZIONI (tutte necessarie):
      1. timestamp IN FINESTRA
      2. Esiste un LS confermato su M15 secondo definizione 2.12
      3. Uno o più pool `INTACT` tra ASH/ASL, PNYH/PNYL, PDH/PDL,
         PRE_NY_H/PRE_NY_L soddisfano la definizione M15
      4. La direzione implicata dallo sweep == bias_direction
      5. La candela di sweep è chiusa (nessuna valutazione su candela in formazione)

    OUTPUT: sweep_event {
      levels_swept_m15: list[LiquidityPool],
      sweep_extreme_m15: float,
      timestamp,
      sweep_confirmed_m15: true,
      sweep_confirmed_m5: false
    }

Lo stato `SWEEP_DETECTED` è transitorio: appena la candela M15 chiude, il livello 4 verifica le tre candele M5 interne. Se nessun pool M15 è confermato anche su M5, il setup viene scartato immediatamente.

**Vincolo aggiuntivo:** l’intera maturazione successiva non può superare `NY_OPEN + 120min`. Il sistema non insegue setup nate in finestra ma maturate a metà pomeriggio.

### 3.5 Livello 4 — M5 (conferma dello sweep + filtro Fibonacci)

Questo livello svolge due funzioni: conferma con maggiore granularità lo stesso sweep identificato su M15 e verifica che il pullback successivo offra un prezzo di ingresso accettabile.

    FASE A — Conferma M5 dello stesso sweep

    CONDIZIONI (tutte necessarie):
      1. Considera esclusivamente le tre candele M5 chiuse che compongono
         la candela M15 dello sweep: [m15_open, m15_close).
      2. Per ogni pool spazzato su M15, almeno una di queste candele M5 deve
         oltrepassare e chiudere nuovamente dal lato interno dello stesso livello.
      3. La penetrazione deve essere >= MIN_SWEEP_ATR_M5 * ATR14_M5.
      4. Il wick di rifiuto deve avere rapporto >= MIN_WICK_RATIO_M5.
      5. La direzione implicata deve coincidere con il bias H4/H1.

    Non sono ammessi due sweep indipendenti. Il pool, la direzione e l’intervallo
    temporale devono appartenere allo stesso evento M15. La lista definitiva è
    l’intersezione tra i pool confermati su M15 e quelli confermati su M5.

    SE intersezione vuota:
        SETUP SCARTATO
    ALTRIMENTI:
        marca i pool confermati come SWEPT
        sweep_confirmed_m5 = true
        origin = estremo più profondo delle candele M5 di conferma
        passa a SWEEP_CONFIRMED

    OUTPUT: {
      levels_swept: list[LiquidityPool],
      sweep_confirmed_m15: true,
      sweep_confirmed_m5: true,
      origin: float
    }

    FASE B — Filtro Fibonacci sulla gamba di reazione

      Dopo la conferma M5, osserva con sole candele chiuse l’estremo opposto
      raggiunto dalla reazione. La reaction_leg usa l’origin della FASE A e
      l’extreme più favorevole raggiunto prima del pullback.

      Calcola fib_50_m5 e fib_75_m5 sulla reaction_leg (sezione 2.7.3)

      Attendi che il prezzo ritracci nella zona [fib_75_m5, fib_50_m5]

      SE M5_FIB_MODE == STRICT:
          pullback fuori dalla zona → attendi o scarta secondo tabella 2.7.3
      SE M5_FIB_MODE == LENIENT:
          accetta [38.2%, 78.6%] con penalità di scoring
      SE M5_FIB_MODE == OFF:
          salta questa fase

      Oltre fib_786 della gamba di reazione → SETUP SCARTATO

    OUTPUT: m5_confirmed: bool, levels_swept: list, m5_fib_position: enum, entry_zone_m5: [low, high]

**Timeout stato** `SWEEP_CONFIRMED`**:** 12 candele M5 (1 ora) dalla chiusura M15 dell’evento, e comunque non oltre `NY_OPEN + 120min`.

**Perché il filtro Fibonacci sta qui e non su H4.** Su M5 la gamba di riferimento è appena stata creata dal movimento che stai seguendo: non c’è ambiguità su quale swing usare, e il ritracciamento in zona 50–75% ha un significato operativo diretto, cioè “il prezzo mi sta offrendo un ingresso a sconto sul movimento appena partito”. Su H4 la stessa misura è molto più soggettiva perché dipende da quale gamba storica scegli come riferimento.

### 3.6 Livello 5 — M1 (trigger di entrata)

Questo è il livello che genera l’ordine. Tre condizioni in sequenza obbligata.

    FASE A — Identificazione zona di entrata
      Ambito di ricerca: le candele M1 comprese nella entry_zone_m5 definita
      al livello precedente (o tutte le candele post-conferma se M5_FIB_MODE == OFF).

      Cerca la prima zona valida tra:
        - FVG nella direzione del bias (definizione 2.8, filtro dimensionale attivo)
        - IFVG nella direzione del bias (definizione 2.9)
        - Order Block nella direzione del bias (definizione 2.10)

      Se più zone sono presenti, applica lo scoring (sezione 4.3) e scegli la migliore.

    FASE B — Attesa del Break of Structure
      Il BOS deve verificarsi DOPO la formazione della zona.
      BOS su M1 secondo definizione 2.4, direzione == bias.
      Questo è il "break of structure dopo la FV e la BS precedente" della tua strategia.

    FASE C — Trigger di entrata
      Dopo il BOS, il prezzo deve ritornare nella zona identificata in FASE A.
      L'ordine è un LIMIT posizionato al livello di entrata (sezione 4.2).

**Timeout stato** `ENTRY_ARMED`**:** `ENTRY_TIMEOUT_MINUTES`, default 45 candele M1. Se il prezzo non torna nella zona entro il timeout, il setup decade; resta comunque valido il limite assoluto della finestra operativa NY-only.

**Invalidazione immediata:** se durante `ENTRY_ARMED` il prezzo rompe strutturalmente contro il bias su M1 (CHoCH), il setup viene cancellato.

## PARTE 4 — Logica di entrata

### 4.1 Tipo di ordine

**Usa BUY LIMIT / SELL LIMIT, non ordini a mercato.**

Motivazione: sul M1 con questa metodologia, l’entrata avviene su un ritorno in zona. L’ordine a mercato ti fa entrare al prezzo peggiore del movimento, il limit ti fa entrare al prezzo che hai deciso. Su un sistema con SL stretti, la differenza tra entry a mercato ed entry a limite è la differenza tra R:R 1:2 e R:R 1:1.4.

    ORDINE = {
      type: LIMIT
      direction: bias_direction
      entry_price: (sezione 4.2)
      stop_loss: (sezione 5.1)
      take_profit: (sezione 5.2)
      volume: (sezione 6)
      expiry: 15 minuti dalla piazzata
      magic_number: identificativo univoco del sistema
      comment: setup_id per il journal
    }

**Se l’ordine non viene riempito entro la scadenza, viene cancellato e lo stato torna a** `IDLE`**.** Non inseguire.

### 4.2 Livello di entrata per tipo di zona

| Zona            | Entry level                                 | Motivazione                                                     |
|-----------------|---------------------------------------------|-----------------------------------------------------------------|
| **FVG**         | Midpoint del gap                            | Compromesso tra probabilità di riempimento e qualità del prezzo |
| **IFVG**        | Bordo prossimale del gap invertito          | L’IFVG reagisce spesso senza penetrare a fondo                  |
| **Order Block** | Bordo prossimale della zona refined (corpo) | Massimizza R:R mantenendo probabilità di tocco                  |

Dove “bordo prossimale” = il bordo della zona che il prezzo incontra per primo tornando indietro.

    LONG:
      FVG:  entry = (fvg.top + fvg.bottom) / 2
      IFVG: entry = ifvg.top
      OB:   entry = ob_refined.top    (cioè l'open della candela ribassista)

    SHORT:
      FVG:  entry = (fvg.top + fvg.bottom) / 2
      IFVG: entry = ifvg.bottom
      OB:   entry = ob_refined.bottom (cioè l'open della candela rialzista)

### 4.3 Scoring del setup

Lo scoring valuta il setup completo, non solo la zona di entrata. Serve sia a scegliere tra più zone candidate su M1, sia a stabilire se il setup merita di essere operato.

**Fattori di contesto (H4 / M5 / liquidity pool):**

| Criterio                                               | Punti |
|--------------------------------------------------------|-------|
| `slope(EMA_SLOW)` \>= 2× `MIN_EMA_SLOPE` (trend forte) | +2    |
| `slope(EMA_SLOW)` tra 1× e 2× `MIN_EMA_SLOPE`          | +1    |
| `USE_EMA_MACRO` attivo e rispettato                    | +1    |
| Pullback M5 dentro \[50%, 75%\]                        | +2    |
| Pullback M5 tra 75% e 78.6% (solo in modalità LENIENT) | −1    |
| Sweep confermato PNYH / PNYL                           | +3    |
| Sweep confermato PDH / PDL                             | +3    |
| Sweep confermato ASH / ASL                             | +2    |
| Sweep confermato PRE_NY_H / PRE_NY_L                   | +1    |
| Sweep multiplo: almeno 2 pool nello stesso movimento   | +2 aggiuntivi |

Se più pool dello stesso gruppo vengono registrati nello stesso evento, i punti del gruppo vengono assegnati una sola volta. Gruppi diversi si sommano; il bonus multi-pool si applica una sola volta e soltanto ai pool confermati su entrambi i timeframe.

**Fattori di zona (M1):**

| Criterio                                                 | Punti      |
|----------------------------------------------------------|------------|
| Zona è un IFVG                                           | +3         |
| Zona è un Order Block con FVG associato                  | +3         |
| Zona è un FVG semplice                                   | +1         |
| Zona in confluenza con un FVG di TF superiore (M5 o M15) | +2         |
| Zona `FRESH` / `UNMITIGATED`                             | +2         |
| Zona `PARTIAL` / mitigata una volta                      | 0          |
| R:R \>= 3.0                                              | +2         |
| R:R tra 2.0 e 3.0                                        | +1         |
| R:R \< 2.0                                               | **scarta** |

**Soglia minima per operare:** `MIN_SETUP_SCORE`**, default 8 punti.**

La soglia è più alta della versione precedente perché il numero di fattori è aumentato. Va ricalibrata sui dati raccolti: è il parametro che regola direttamente il numero di trade generati.

**Selezione tra zone multiple:** se più zone M1 sono valide contemporaneamente, i fattori di contesto sono identici per tutte; si sceglie quella con il punteggio di zona più alto. A parità, si sceglie quella che produce l’R:R migliore.

## PARTE 5 — Logica di uscita

### 5.1 Stop Loss

**Regola base — lo SL va sempre oltre l’invalidazione strutturale, mai a distanza fissa.**

    LONG:
      candidato_1 = zona_entrata.bottom - (SL_BUFFER_ATR * ATR14_M1)
      candidato_2 = sweep_low - (SL_BUFFER_ATR * ATR14_M1)
      candidato_3 = ultimo_swing_low_M1 - (SL_BUFFER_ATR * ATR14_M1)

      SL = MIN(candidato_1, candidato_2, candidato_3)

    SHORT:
      candidato_1 = zona_entrata.top + (SL_BUFFER_ATR * ATR14_M1)
      candidato_2 = sweep_high + (SL_BUFFER_ATR * ATR14_M1)
      candidato_3 = ultimo_swing_high_M1 + (SL_BUFFER_ATR * ATR14_M1)

      SL = MAX(candidato_1, candidato_2, candidato_3)

`SL_BUFFER_ATR` default: **0.30**

**Vincolo di distanza minima:**

    SL_distance >= MAX(spread_medio * 3, MIN_SL_DOLLARS)
    MIN_SL_DOLLARS default: 1.50 (cioè $1.50 di movimento su XAU/USD)

Uno SL troppo stretto su gold viene preso dal rumore anche quando l’analisi è corretta. Su XAU/USD lo spread tipico è 0.15–0.35 in condizioni normali e può esplodere a 1.00+ durante le news.

**Vincolo di distanza massima:**

    SL_distance <= MAX_SL_DOLLARS  (default: 6.00)

Se lo SL strutturale è più lontano, **scarta il setup**. Non ridurre lo SL per farlo entrare: significa che la struttura non supporta l’operazione.

### 5.2 Take Profit

**Target primario — liquidità opposta.**

    LONG:
      TP_1 = livello di liquidità più vicino sopra l'entry, tra:
             - ultimo swing high M5 non ancora violato
             - pool `INTACT` più vicino tra ASH, PNYH, PDH e PRE_NY_H
             - bordo prossimale del primo FVG bearish M5/M15 sopra

    SHORT:
      TP_1 = speculare

**Vincolo R:R minimo:**

    R = |entry - SL|
    R_multiple = |TP - entry| / R

    Se R_multiple < 2.0 → SCARTA IL SETUP

Questo è il vincolo che protegge l’intero sistema. Con win rate del 40% e R:R 1:2 sei in profitto; con win rate del 60% e R:R 1:1 sei in pareggio dopo i costi.

### 5.3 Gestione della posizione

**Schema a tre fasi (consigliato per iniziare):**

    FASE 1 — Parziale a 1R
      A +1.0R: chiudi il 50% della posizione
      Sposta SL a breakeven + spread   (protezione da costi)

    FASE 2 — Parziale a 2R
      A +2.0R: chiudi il 25% della posizione (metà del residuo)
      Sposta SL a +1.0R

    FASE 3 — Runner
      Il 25% restante resta aperto con trailing stop
      Trailing: SL segue l'ultimo swing low M5 (LONG) / high M5 (SHORT)
                aggiornato a ogni nuovo swing confermato
      Chiusura forzata: secondo la regola 5.4 o a TP_2

**Modalità alternativa da implementare come opzione di configurazione:** chiusura integrale a 2R senza parziali. Entrambe le modalità devono essere selezionabili dal file di configurazione tramite un flag `EXIT_MODE: {SCALED, FLAT_2R}`.

### 5.4 Chiusure forzate

Il sistema chiude qualunque posizione aperta se:

1.  `NewsFilter` passa a stato `BLACKOUT` con evento a impatto alto entro 10 minuti (vedi Parte 8)
2.  Dal lunedi al giovedi, ora corrente \>= 09:30 `Australia/Sydney`, cioe 30 minuti prima dell'apertura ordinaria ASX delle 10:00. La conversione deve applicare automaticamente il DST australiano: il cutoff vale 23:30 UTC durante AEST e 22:30 UTC durante AEDT, nel giorno UTC precedente all'apertura australiana.
3.  Il venerdi, ora corrente \>= due ore prima della chiusura dell'ultima sessione settimanale XAUUSD comunicata dal broker. Il sistema deve leggere la sessione con `SymbolInfoSessionTrade`, non usare un orario hardcoded; se il calendario della sessione non e disponibile, l'EA non deve inizializzarsi.
4.  Connessione al broker persa per più di 60 secondi con posizione aperta e nessun SL server-side confermato

Il cutoff viene calcolato e salvato come timestamp assoluto all'apertura della posizione. Non deve essere ricalcolato come "prossima apertura" dopo il suo superamento, altrimenti slitterebbe erroneamente al giorno successivo. La regola del venerdi ha priorita sulla chiusura pre-ASX.

**Regola non negoziabile:** SL e TP devono essere sempre registrati lato server (broker), mai gestiti solo dalla logica del bot. Se il bot crasha, la posizione deve restare protetta.

## PARTE 6 — Position sizing e lottaggio

### 6.1 Specifiche del contratto XAU/USD

    1 lotto standard = 100 once troy
    Movimento di $1.00 del prezzo = $100 di P/L per lotto standard
    Movimento di $0.01 = $1.00 per lotto standard

    ATTENZIONE: verifica queste specifiche con il tuo broker specifico.
    Alcuni broker usano 10 once per lotto, altri quotano 3 decimali.
    Il sistema deve leggere le specifiche dal broker via API, mai assumerle.

### 6.2 Formula di sizing

    rischio_dollari = equity_corrente * RISK_PER_TRADE_PCT

    distanza_SL_dollari = |entry_price - stop_loss|

    valore_per_lotto = distanza_SL_dollari * 100

    lotti = rischio_dollari / valore_per_lotto

    lotti = ARROTONDA_AL_BASSO(lotti, broker.volume_step)
    lotti = CLAMP(lotti, broker.volume_min, broker.volume_max)
    lotti = MIN(lotti, MAX_LOT_ABSOLUTE)

**Esempio concreto (conto 50.000, rischio 0.5%):**

    rischio_dollari = 50.000 * 0.005 = $250
    distanza_SL = $2.50
    valore_per_lotto = 2.50 * 100 = $250
    lotti = 250 / 250 = 1.00 lotti

**Esempio con SL più ampio:**

    rischio_dollari = $250
    distanza_SL = $4.00
    valore_per_lotto = 4.00 * 100 = $400
    lotti = 250 / 400 = 0.625 → arrotondato a 0.62

### 6.3 Parametri di rischio

| Parametro                  | Fase validazione | Fase challenge | Fase funded |
|----------------------------|------------------|----------------|-------------|
| `RISK_PER_TRADE_PCT`       | 0.25%            | 0.50%          | 0.50%       |
| `MAX_CONCURRENT_POSITIONS` | 1                | 1              | 1           |
| `MAX_TRADES_PER_DAY`       | 2                | 2              | 3           |
| `MAX_LOT_ABSOLUTE`         | 1.00             | 2.00           | 2.00        |

**Perché** `MAX_CONCURRENT_POSITIONS = 1`**:** la tua strategia opera su un solo strumento in una finestra di due ore. Due posizioni simultanee su XAU/USD non sono diversificazione, sono la stessa scommessa raddoppiata.

**Perché rischio così basso:** con R:R 1:2 e un win rate ipotetico del 45%, l’aspettativa per trade è positiva ma la deviazione standard è alta. Con 0.5% per trade, una serie di 8 perdite consecutive — che è statisticamente normale — costa il 4%. Con il 2% per trade, la stessa serie costa il 16% e ti squalifica.

### 6.4 Riduzione dinamica del rischio

    Se drawdown_corrente > 3% del picco di equity:
        RISK_PER_TRADE_PCT *= 0.5

    Se drawdown_corrente > 5% del picco di equity:
        STOP TOTALE fino a revisione manuale

    Se 3 perdite consecutive:
        RISK_PER_TRADE_PCT *= 0.5 per i successivi 5 trade

    Se 5 perdite consecutive:
        STOP per 48 ore, revisione manuale obbligatoria

**Non implementare mai la logica inversa (aumentare il rischio dopo le vincite, martingala, recovery).** È il meccanismo che distrugge i conti più rapidamente di qualunque altro.

## PARTE 7 — Risk management e vincoli prop firm

### 7.1 Vincoli FTMO (verifica le regole correnti, cambiano)

Per un conto FTMO 50k, i vincoli tipici sono:

| Vincolo                  | Valore                   | Note                  |
|--------------------------|--------------------------|-----------------------|
| Profit target Fase 1     | 10% (\$5.000)            |                       |
| Profit target Fase 2     | 5% (\$2.500)             |                       |
| Max perdita giornaliera  | 5% (\$2.500)             | Include P/L flottante |
| Max perdita totale       | 10% (\$5.000)            | Su balance iniziale   |
| Giorni minimi di trading | Verifica regole correnti | Cambiato più volte    |

**Importante:** le regole FTMO sono cambiate diverse volte e la mia conoscenza si ferma a maggio 2026. **Prima di scrivere una riga di codice del** `RiskManager`**, scarica il regolamento aggiornato dal sito e codificalo da lì.** Un sistema che viola una regola che non conoscevi ti fa fallire la challenge con un trade perfetto.

### 7.2 Implementazione dei limiti

    class RiskManager:

        def pre_trade_check(signal) -> Decision:

            # Vincolo 1 — perdita giornaliera
            loss_today = daily_start_balance - current_equity
            if loss_today >= DAILY_LOSS_LIMIT * SAFETY_MARGIN:
                return VETO("daily loss limit")

            # Vincolo 2 — perdita giornaliera proiettata
            potential_loss = loss_today + risk_amount(signal)
            if potential_loss >= DAILY_LOSS_LIMIT * SAFETY_MARGIN:
                return VETO("projected daily loss")

            # Vincolo 3 — drawdown totale
            total_dd = initial_balance - current_equity
            if total_dd + risk_amount(signal) >= MAX_LOSS_LIMIT * SAFETY_MARGIN:
                return VETO("max drawdown")

            # Vincolo 4 — numero trade
            if trades_today >= MAX_TRADES_PER_DAY:
                return VETO("max trades")

            # Vincolo 5 — posizioni concorrenti
            if open_positions >= MAX_CONCURRENT_POSITIONS:
                return VETO("max positions")

            # Vincolo 6 — R:R minimo
            if signal.r_multiple < MIN_R_MULTIPLE:
                return VETO("insufficient R:R")

            # Vincolo 7 — spread
            if current_spread > MAX_SPREAD:
                return VETO("spread too wide")

            return APPROVE(calculated_volume)

`SAFETY_MARGIN` **default: 0.70.** Significa che il sistema si ferma al 70% del limite consentito. Il 30% residuo copre slippage, gap e errori di calcolo. Questo margine ti salverà almeno una volta.

`MAX_SPREAD` **per XAU/USD: 0.50.** Sopra questo valore non si entra. Lo spread che si allarga è il primo segnale di condizioni anomale.

### 7.3 Circuit breaker

Il sistema deve avere un interruttore che sospende tutto e richiede intervento manuale:

    TRIGGER DI CIRCUIT BREAKER:
      - 5 perdite consecutive
      - Drawdown giornaliero > 3%
      - Drawdown totale > 5%
      - Discrepanza tra P/L calcolato e P/L broker > $50
      - Più di 3 ordini rifiutati dal broker in 10 minuti
      - Latenza media > 500ms su 10 richieste consecutive
      - Qualunque eccezione non gestita nel SignalEngine

    AZIONE:
      1. Chiudi tutte le posizioni aperte
      2. Cancella tutti gli ordini pendenti
      3. Passa a stato HALTED
      4. Invia notifica (Telegram / email)
      5. Non riprendere senza riattivazione manuale esplicita

## PARTE 8 — News filter

Hai chiesto che il sistema possa operare anche durante le news dopo aver fatto “le verifiche opportune”. Ti spiego come strutturarlo, e perché la mia raccomandazione è di essere molto più conservativo di quanto potresti volere.

### 8.1 Perché le news sono un problema specifico per questa strategia

La tua strategia entra su M1 con SL stretti (1.50–6.00 dollari). Durante un rilascio macro ad alto impatto su gold:

- Lo spread può passare da 0.20 a 5.00+ in un secondo
- Il prezzo può muoversi di \$15–30 in pochi secondi
- Gli ordini limit possono non essere riempiti, o riempiti con slippage enorme
- Gli SL vengono eseguiti al primo prezzo disponibile, che può essere molto oltre il livello

Uno SL da \$2.50 durante un NFP può costarti \$15 di movimento reale. Con 1 lotto, sono \$1.500 invece di \$250. Su un conto FTMO 50k, un singolo evento del genere ti porta al 60% del limite giornaliero.

**Questo non è un rischio da mitigare con verifiche. È un rischio da evitare.**

### 8.2 Classificazione degli eventi

    IMPACT_LEVEL:
      CRITICAL — eventi che muovono gold di $10+ regolarmente
        · FOMC rate decision + press conference
        · NFP (Non-Farm Payrolls)
        · CPI USA (headline e core)
        · PPI USA
        · Discorsi del Presidente Fed
        · PCE Price Index

      HIGH — eventi che muovono gold di $5–10
        · Retail Sales USA
        · GDP USA (preliminare e finale)
        · ISM Manufacturing / Services PMI
        · Jobless Claims (settimanale, impatto minore ma frequente)
        · Discorsi di membri FOMC votanti
        · Decisioni BCE / BoE

      MEDIUM — eventi con impatto variabile
        · Consumer Confidence
        · Durable Goods
        · Housing data
        · PMI europei

      LOW — trascurabili per gold

### 8.3 Finestre di blackout

| Impatto  | Blackout prima | Blackout dopo | Azione su posizione aperta                         |
|----------|----------------|---------------|----------------------------------------------------|
| CRITICAL | 60 min         | 60 min        | **Chiudi 15 min prima**                            |
| HIGH     | 30 min         | 30 min        | Chiudi 10 min prima                                |
| MEDIUM   | 15 min         | 15 min        | Sposta SL a BE se in profitto, altrimenti mantieni |
| LOW      | 0              | 0             | Nessuna azione                                     |

**Conflitto strutturale con la finestra operativa:** molti dati USA escono alle 08:30 ora di New York, cioè un’ora esatta prima dell’apertura, dentro la finestra operativa. Nei giorni di CPI, NFP e PPI il sistema **non opererà affatto**. È il comportamento corretto e voluto: sono circa 4–6 giorni al mese in cui il sistema resta fermo.

### 8.4 Fonti dati per il calendario

| Fonte                             | Tipo                | Note                                                  |
|-----------------------------------|---------------------|-------------------------------------------------------|
| **Forex Factory**                 | Scraping / feed XML | Gratuito, affidabile, classificazione impatto inclusa |
| **Investing.com**                 | Scraping            | Gratuito ma protezioni anti-bot                       |
| **Trading Economics API**         | REST API            | A pagamento, molto affidabile                         |
| **FMP (Financial Modeling Prep)** | REST API            | Tier gratuito disponibile                             |
| **MQL5 Economic Calendar**        | Nativo MT5          | Se usi MT5, integrato                                 |

**Implementazione consigliata:**

    1. Scarica il calendario settimanale ogni domenica alle 20:00 UTC
    2. Ricarica ogni giorno alle 00:00 UTC (per revisioni)
    3. Cache locale in SQLite
    4. FALLBACK OBBLIGATORIO: se il calendario non è disponibile o è più
       vecchio di 24 ore → il sistema NON OPERA.
       Meglio zero trade che un trade cieco durante un NFP.

### 8.5 Il “trading sulle news” che hai chiesto

Capisco l’idea: se il sistema sa cosa esce e legge il risultato, potrebbe sfruttare il movimento. Ti dico perché sconsiglio fortemente di includerlo in questa versione:

**Problemi tecnici:** - La lettura del dato richiede un feed a bassissima latenza. I feed retail arrivano con 1–3 secondi di ritardo: il movimento è già finito. - Interpretare il dato (actual vs forecast vs previous, e come il mercato reagirà) richiede modelli che non sono deterministici. Gold a volte sale su CPI alto, a volte scende, a seconda del contesto sui tassi reali e sul dollaro. - L’esecuzione durante il rilascio è inaffidabile per definizione.

**Problema strutturale:** il news trading è una strategia completamente diversa dalla tua. Ha logica diversa, sizing diverso, gestione diversa. Metterla nello stesso software significa avere due sistemi non validati invece di uno.

**Cosa fare invece:** costruisci il sistema con blackout rigido. Se dopo 6 mesi di dati hai un sistema che funziona, valuta se aggiungere un modulo news **separato**, con conto separato e validazione propria. Non prima.

Se comunque vuoi procedere, la versione minima difendibile è: **operare solo 15–30 minuti DOPO il rilascio**, quando lo spread è rientrato e la direzione si è definita, applicando la tua stessa cascata multi-TF sul movimento post-news. Questo è gestibile e non richiede lettura del dato.

## PARTE 9 — Suite di test unitari (responsabilità dello sviluppatore)

Ogni funzione di riconoscimento pattern deve avere test con casi costruiti a mano, con dati sintetici in cui il risultato atteso è noto. Questa è una condizione di consegna: codice senza questi test non è considerato completo.

    test_swing_high_detection()
    test_swing_low_detection()
    test_swing_high_with_equal_highs()
    test_swing_confirmation_delay()          ← verifica che confirmed_at > occurred_at

    test_bos_requires_close_not_wick()
    test_bos_rejected_on_wick_only()
    test_choch_detection()
    test_sweep_vs_bos_disambiguation()       ← il test più importante di tutti

    test_fvg_bullish_detection()
    test_fvg_bearish_detection()
    test_fvg_size_filter()
    test_fvg_state_transitions()
    test_ifvg_conversion()
    test_ifvg_expiry()

    test_order_block_identification()
    test_order_block_refined_zone()
    test_order_block_invalidation()

    test_ema_calculation_matches_reference()
    test_ema_warmup_blocks_bias()
    test_ema_alignment_long()
    test_ema_alignment_short()
    test_ema_slope_normalization()
    test_ema_flat_blocks_operation()
    test_ema_macro_filter_toggle()
    test_structure_choch_vetoes_ema_bias()

    test_m5_fib_zone_calculation_bullish()
    test_m5_fib_zone_calculation_bearish()
    test_h4_bias_has_no_fibonacci_dependency()
    test_m5_reaction_leg_definition()
    test_m5_fib_filter_strict_mode()
    test_m5_fib_filter_lenient_mode()
    test_m5_fib_filter_off_mode()
    test_setup_scoring_total()
    test_setup_score_threshold_veto()

    test_liquidity_sweep_direction_bullish()
    test_liquidity_sweep_direction_bearish()
    test_wick_ratio_filter()
    test_multiple_pool_tracking()
    test_sweep_confirmation_both_timeframes()
    test_sweep_m15_ok_m5_fail_rejects_setup()
    test_multi_pool_sweep_scoring()

    test_ny_window_summer_dst()
    test_ny_window_winter_dst()
    test_ny_window_us_eu_dst_mismatch()      ← bug classico, testalo esplicitamente
    test_pre_ny_range_calculation()
    test_pdh_pdl_calculation()
    test_asian_session_high_low_calculation()
    test_previous_ny_session_high_low_calculation()

    test_position_sizing_formula()
    test_position_sizing_rounding()
    test_position_sizing_broker_limits()

    test_risk_manager_daily_loss_veto()
    test_risk_manager_projected_loss_veto()
    test_risk_manager_max_drawdown_veto()
    test_risk_manager_r_multiple_veto()
    test_risk_manager_spread_veto()

    test_news_blackout_windows()
    test_news_calendar_stale_fallback()

    test_circuit_breaker_each_trigger()
    test_state_machine_all_timeouts()
    test_state_machine_invalidation_paths()

**Regola di build:** se un test fallisce, il sistema non parte. Il check va nell’entrypoint, non solo in CI.

### 9.1 Visualizzatore di verifica

Deliverable obbligatorio insieme al codice: uno strumento che, dato un intervallo di date, renderizzi il grafico con sovrapposti tutti gli oggetti identificati dal sistema — swing, BOS, zone premium, FVG, OB, sweep, e i punti di entry/SL/TP di ogni segnale generato.

Serve per la verifica manuale: guardare 50 setup identificati dal sistema e confermare che siano quelli che un operatore umano avrebbe preso. Senza questo strumento non è possibile stabilire se la traduzione della strategia in codice è corretta.

Formato: `matplotlib` o `plotly` con export HTML interattivo.

## PARTE 10 — Roadmap di sviluppo

### Fase 1 — Fondamenta

    □ Setup ambiente, repository, CI
    □ Modelli di dominio (Candle, SwingPoint, FVG, OrderBlock, Zone, Signal)
    □ DataFeed astratto + implementazione da storico locale
    □ Pipeline di caricamento e validazione dati
    □ Test unitari sui modelli

### Fase 2 — Motori di analisi

    □ StructureEngine: swing, trend, BOS, CHoCH
    □ ZoneEngine: FVG, IFVG, Order Block, Fibonacci M5
    □ Gestione sessione NY con timezone e DST
    □ Calcolo parallelo ASH/ASL, PNYH/PNYL, PDH/PDL e PRE_NY_H/PRE_NY_L
    □ Suite completa di test su pattern costruiti a mano
    □ Visualizzatore di verifica (sezione 9.1)

**Checkpoint di Fase 2:** verifica visiva di almeno 50 setup identificati dal sistema prima di procedere. È il punto in cui si scopre se la strategia è stata tradotta correttamente. Procedere senza questo controllo significa costruire le fasi successive su fondamenta non verificate.

### Fase 3 — Logica di segnale

    □ Macchina a stati della cascata multi-TF
    □ SignalEngine completo con tutti i livelli
    □ Scoring delle zone
    □ Calcolo entry / SL / TP
    □ Gestione timeout e invalidazioni di ogni stato
    □ Test di integrazione end-to-end su dati storici

### Fase 4 — Rischio, news, esecuzione

    □ RiskManager con tutti i vincoli e poteri di veto
    □ Position sizing con lettura specifiche contratto dal broker
    □ NewsFilter + integrazione calendario economico
    □ Fallback su calendario non disponibile
    □ ExecutionEngine astratto
    □ Circuit breaker con tutti i trigger

### Fase 5 — Integrazione broker e operatività

    □ Implementazione DataFeed live
    □ Implementazione ExecutionEngine reale
    □ Gestione riconnessione, ordini rifiutati, requote, slippage
    □ SL/TP server-side verificati
    □ Journal completo (Appendice B)
    □ Notifiche Telegram
    □ Dashboard di monitoraggio
    □ Procedura di spegnimento di emergenza

### Fase 6 — Consegna

    □ Documentazione tecnica del codice
    □ File di configurazione parametri esposto e commentato
    □ Istruzioni di deploy (VPS o locale)
    □ Handover: sessione di walkthrough del codice

**Nota sulla configurazione:** tutti i parametri dell’Appendice A devono essere esposti in un file di configurazione esterno (YAML o TOML), non hardcoded. Nessuna modifica di parametro deve richiedere una ricompilazione o una modifica al codice.

## PARTE 11 — Modalità di fallimento da prevenire in fase di sviluppo

Queste sono le cause tecniche per cui i sistemi di questo tipo falliscono. Vanno prevenute nel codice, non scoperte dopo.

### 11.1 Look-ahead bias

Il codice usa informazioni non disponibili al momento della decisione. Il rischio maggiore qui è **lo swing point**: uno swing con `k=3` è confermato solo 3 candele dopo la sua formazione. Se il sistema lo usa nel momento in cui si è formato, sta usando il futuro.

**Difesa obbligatoria:** ogni oggetto strutturale porta due campi distinti, `occurred_at` e `confirmed_at`. Il `SignalEngine` può accedere solo a oggetti con `confirmed_at <= now`. Questa regola va imposta a livello di interfaccia del repository degli oggetti, non lasciata alla disciplina di chi scrive la logica.

### 11.2 Confusione sweep / BOS

Il singolo errore logico più costoso di questa metodologia. Un wick che buca un livello e rientra è uno **sweep**; una chiusura oltre il livello è un **BOS**. Se il codice li confonde, il sistema entrerà sistematicamente nella direzione sbagliata nei momenti di massima volatilità.

**Difesa:** test unitario dedicato (`test_sweep_vs_bos_disambiguation`) con almeno 10 casi limite, più verifica visiva.

### 11.3 Gestione errata di DST

L’apertura NY si sposta rispetto a UTC due volte l’anno, e nelle settimane di disallineamento tra USA ed Europa si sposta anche rispetto all’ora italiana. Un orario hardcoded fa operare il sistema nella finestra sbagliata per giorni senza generare alcun errore visibile.

**Difesa:** nessun offset manuale, solo conversioni timezone-aware. Test espliciti per estate, inverno e settimane di disallineamento.

### 11.4 Degradazione silenziosa

Il sistema funziona, poi le condizioni di mercato cambiano e inizia a perdere. Senza monitoraggio automatico, la scoperta arriva dopo il drawdown.

**Difesa:** il sistema traccia rolling win rate e rolling profit factor su finestra di 30 trade. Se il profit factor a 30 trade scende sotto 1.0, il circuit breaker si attiva e invia notifica.

### 11.5 Intervento manuale sulle posizioni

Se un operatore modifica manualmente uno SL o chiude una posizione in anticipo, il sistema non sta più eseguendo la strategia e le statistiche raccolte non sono più valide.

**Difesa a livello software:** l’interfaccia di controllo espone solo tre azioni — `PAUSE` (non apre nuove posizioni, gestisce quelle in corso), `HALT` (chiude tutto e si ferma), `RESUME`. Non deve esistere alcuna funzione per modificare un trade in corso.

## APPENDICE A — Riepilogo parametri

| Parametro                  | Default      | Configurabile a runtime | Sezione |
|----------------------------|--------------|-------------------------|---------|
| `k_H4`, `k_H1`             | 3            | Sì                      | 2.2     |
| `k_M15`, `k_M5`            | 2            | Sì                      | 2.2     |
| `k_M1`                     | 1            | Sì                      | 2.2     |
| `MIN_BREAK_ATR`            | 0.05         | Sì                      | 2.4     |
| `EMA_FAST`                 | 21           | Sì                      | 2.6     |
| `EMA_SLOW`                 | 50           | Sì                      | 2.6     |
| `EMA_MACRO`                | 200          | Sì                      | 2.6     |
| `USE_EMA_MACRO`            | false        | Sì                      | 2.6     |
| `USE_EMA_H1`               | false        | Sì                      | 3.3     |
| `MIN_EMA_SLOPE`            | 0.05         | Sì                      | 2.6     |
| `EMA_SLOPE_LOOKBACK`       | 6 candele H4 | Sì                      | 2.6     |
| `M5_FIB_MODE`              | STRICT       | Sì                      | 2.7.3   |
| `MIN_SETUP_SCORE`          | 8            | Sì                      | 4.3     |
| `MIN_FVG_ATR` (M1)         | 0.15         | Sì                      | 2.8     |
| `MIN_FVG_ATR` (M5)         | 0.20         | Sì                      | 2.8     |
| `IFVG_MAX_AGE` (M1)        | 30           | Sì                      | 2.9     |
| `MIN_IMPULSE_CANDLES`      | 2            | No                      | 2.10    |
| `MIN_IMPULSE_ATR`          | 1.0          | Sì                      | 2.10    |
| `MIN_SWEEP_ATR_M15`        | 0.10         | Sì                      | 2.12    |
| `MIN_WICK_RATIO_M15`       | 0.50         | Sì                      | 2.12    |
| `MIN_SWEEP_ATR_M5`         | 0.10         | Sì                      | 2.12 / 3.5 |
| `MIN_WICK_RATIO_M5`        | 0.35         | Sì                      | 2.12 / 3.5 |
| `ENTRY_TIMEOUT_MINUTES`    | 45 minuti    | Sì                      | 3.6     |
| `BIAS_MAX_AGE`             | 6 candele H4 | No                      | 3.2     |
| `SL_BUFFER_ATR`            | 0.30         | Sì                      | 5.1     |
| `MIN_SL_DOLLARS`           | 1.50         | No                      | 5.1     |
| `MAX_SL_DOLLARS`           | 6.00         | No                      | 5.1     |
| `MIN_R_MULTIPLE`           | 2.0          | No                      | 5.2     |
| `RISK_PER_TRADE_PCT`       | 0.5%         | No                      | 6.3     |
| `MAX_TRADES_PER_DAY`       | 2            | No                      | 6.3     |
| `MAX_CONCURRENT_POSITIONS` | 1            | No                      | 6.3     |
| `SAFETY_MARGIN`            | 0.70         | No                      | 7.2     |
| `MAX_SPREAD`               | 0.50         | No                      | 7.2     |

## APPENDICE B — Schema del journal

Ogni trade deve registrare tutto quello che serve per capire, mesi dopo, perché è stato preso.

    TradeRecord = {
      setup_id: uuid
      timestamp_signal, timestamp_entry, timestamp_exit: datetime

      # Contesto multi-TF
      h4_trend, h1_trend: enum
      ema_fast_h4, ema_slow_h4: float
      ema_slope_normalized: float
      ema_macro_respected: bool
      h4_h1_aligned: bool
      m5_fib_position: enum
      m5_reaction_range: float
      setup_score: int
      score_breakdown: dict
      price_at_signal: float

      # Sweep
      sweep_level_type: list[enum {ASH, ASL, PNYH, PNYL, PDH, PDL, PRE_NY_H, PRE_NY_L}]
      sweep_level_price: list[float]
      sweep_extreme_price: float
      sweep_timestamp: datetime
      sweep_confirmed_m15: bool
      sweep_confirmed_m5: bool

      # Zona di entrata
      zone_type: enum {FVG, IFVG, OB}
      zone_top, zone_bottom: float
      zone_score: int
      zone_state_at_entry: enum

      # Esecuzione
      entry_planned, entry_actual: float
      slippage_entry: float
      sl_price, tp_price: float
      r_multiple_planned: float
      volume: float
      risk_amount: float

      # Risultato
      exit_price, exit_reason: (TP, SL, TIME, NEWS, MANUAL, CIRCUIT_BREAKER)
      pnl_dollars, pnl_r: float
      mae, mfe: float   # max adverse / favorable excursion
      duration_minutes: int

      # Contesto
      spread_at_entry: float
      atr_m1, atr_m5, atr_h4: float
      news_events_next_4h: list
      equity_before, equity_after: float
    }

**MAE e MFE sono le metriche più sottovalutate.** Ti dicono quanto il trade è andato contro prima di andare a favore (utile per calibrare lo SL) e quanto è andato a favore prima di tornare indietro (utile per calibrare il TP). Dopo 200 trade, questi due numeri ti diranno più di qualunque ottimizzazione.

## APPENDICE C — Checklist di consegna

Condizioni che il codice deve soddisfare per essere considerato completo.

    □ Tutti i test unitari della Parte 9 presenti e passanti
    □ Check dei test integrato nell'entrypoint, non solo in CI
    □ Visualizzatore di verifica funzionante ed esportabile in HTML
    □ Ogni oggetto strutturale espone occurred_at e confirmed_at
    □ Nessun accesso a oggetti non confermati dal SignalEngine
    □ Nessun orario hardcoded: tutte le conversioni timezone-aware
    □ Tutti i parametri dell'Appendice A esposti in file di configurazione
    □ RiskManager con potere di veto non bypassabile a runtime
    □ SL e TP sempre registrati server-side, mai solo lato bot
    □ NewsFilter con fallback su calendario non disponibile o stale
    □ Circuit breaker testato su ogni singolo trigger
    □ Journal completo secondo lo schema dell'Appendice B
    □ Notifiche funzionanti e testate
    □ Interfaccia di controllo limitata a PAUSE / HALT / RESUME
    □ Procedura di spegnimento di emergenza documentata e provata
    □ Riconnessione automatica al broker testata con disconnessione simulata
    □ Comportamento verificato su ordine rifiutato, requote e slippage estremo
    □ Documentazione tecnica e istruzioni di deploy consegnate

*Documento di specifica — versione 1.3, 3 agosto 2026. Le regole delle prop firm, le specifiche dei contratti e le condizioni di mercato cambiano: verifica ogni parametro esterno alla fonte prima di implementarlo.*
