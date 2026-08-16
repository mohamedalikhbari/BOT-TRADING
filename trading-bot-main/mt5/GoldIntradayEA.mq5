#property strict
#property version   "1.10"
#property description "Research-only XAUUSD EA: Keltner, RSI, Donchian, momentum and daily-open volatility breakout."
#property description "All signals use closed bars. Tester-only by default; no live-trading authorization."

#include <Trade/Trade.mqh>

enum ENUM_GOLD_INTRADAY_MODE
  {
   GOLD_H1_KELTNER_BREAKOUT = 0,
   GOLD_H1_RSI_REVERSION = 1,
   GOLD_H1_DONCHIAN = 2,
   GOLD_H1_MOMENTUM = 3,
   GOLD_M15_DAILY_OPEN_BREAKOUT = 4,
   GOLD_H1_KELTNER_RSI_ENSEMBLE = 5
  };

enum ENUM_GOLD_REGIME_MODE
  {
   GOLD_REGIME_EMA = 0,
   GOLD_REGIME_MOMENTUM = 1,
   GOLD_REGIME_EMA_AND_MOMENTUM = 2
  };

input group "Research strategy"
input ENUM_GOLD_INTRADAY_MODE InpMode = GOLD_H1_KELTNER_RSI_ENSEMBLE;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_H1;
input bool     InpAllowLong = true;
input bool     InpAllowShort = true;
input bool     InpUseTrendFilter = false;
input int      InpTrendEmaPeriod = 100;

input group "Closed higher-timeframe regime"
input bool     InpUseHigherTimeframeRegime = false;
input ENUM_TIMEFRAMES InpRegimeTimeframe = PERIOD_D1;
input ENUM_GOLD_REGIME_MODE InpRegimeMode = GOLD_REGIME_EMA_AND_MOMENTUM;
input int      InpRegimeEmaPeriod = 50;
input int      InpRegimeMomentumLookback = 20;

input group "Keltner breakout"
input int      InpKeltnerEmaPeriod = 70;
input int      InpKeltnerAtrPeriod = 10;
input double   InpKeltnerAtrMultiplier = 2.00;

input group "RSI reversion"
input int      InpRsiPeriod = 25;
input double   InpRsiLower = 35.0;
input double   InpRsiUpper = 80.0;
input double   InpRsiExit = 50.0;

input group "Hourly Donchian"
input int      InpDonchianEntry = 20;
input int      InpDonchianExit = 5;

input group "Hourly momentum"
input int      InpMomentumLookback = 6;
input double   InpMomentumMinAtr = 0.25;

input group "Daily-open volatility breakout"
input int      InpOrbAtrPeriod = 20;
input double   InpOrbThresholdAtr = 0.50;
input bool     InpOrbUseContractionFilter = false;
input double   InpOrbMaxPriorRangeAtr = 1.00;
input bool     InpOrbOneTradePerDay = true;

input group "Keltner-RSI ensemble"
input int      InpEnsembleRsiStartHour = 16;
input int      InpEnsembleRsiEndHour = 8;
input int      InpEnsembleConflictMode = 2; // 0=skip, 1=Keltner, 2=RSI
input double   InpEnsembleRsiStopAtr = 1.50;
input double   InpEnsembleRsiTakeProfitR = 2.00;
input int      InpEnsembleRsiMaxHoldingBars = 36;

input group "Position exits"
input int      InpRiskAtrPeriod = 20;
input double   InpInitialStopAtr = 1.00;
input double   InpTakeProfitR = 0.00;
input bool     InpUseAtrTrail = false;
input double   InpTrailAtr = 2.00;
input int      InpMaxHoldingBars = 24;

input group "Frequency and session"
input bool     InpUseServerSession = false;
input int      InpSessionStartHour = 1;
input int      InpSessionEndHour = 23;
input int      InpBarExecutionDelayMinutes = 5;

input group "Aggressive risk and execution"
input double   InpRiskPerTradePct = 0.010;
input double   InpMaxActualRiskPct = 0.030;
input double   InpMaxLotAbsolute = 5.00;
input double   InpMaxSpreadDollars = 2.00;
input double   InpMarginSafetyFraction = 0.70;
input bool     InpUseDrawdownThrottle = true;
input double   InpThrottleStartDDPct = 0.15;
input double   InpThrottleFullDDPct = 0.25;
input double   InpThrottleMinRiskMultiplier = 0.25;
input double   InpCircuitBreakerDDPct = 0.40;
input ulong    InpMagic = 120261000;
input int      InpDeviationPoints = 100;

input group "Tester acceptance"
input int      InpMinTradesForCriterion = 26;
input bool     InpTesterOnly = true;

CTrade g_trade;
datetime g_last_signal_bar_open=0;
bool g_signal_pending=false;
double g_peak_equity=0.0;
bool g_halted=false;
int g_last_orb_entry_day=-1;
int g_active_ensemble_model=0;
int g_pending_ensemble_model=0;

bool OptimizationQuiet()
  {
   return (bool)MQLInfoInteger(MQL_OPTIMIZATION);
  }

int SignOf(const double value)
  {
   if(value>0.0) return 1;
   if(value<0.0) return -1;
   return 0;
  }

int DayKey(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value,parts);
   return parts.year*1000+parts.day_of_year;
  }

bool HourInWindow(const int hour,const int start_hour,const int end_hour)
  {
   if(start_hour==end_hour) return true;
   if(start_hour<end_hour) return hour>=start_hour && hour<end_hour;
   return hour>=start_hour || hour<end_hour;
  }

int MaximumLookback()
  {
   int result=MathMax(InpRiskAtrPeriod+3,InpKeltnerAtrPeriod+3);
   result=MathMax(result,InpKeltnerEmaPeriod*5+3);
   result=MathMax(result,InpTrendEmaPeriod*5+3);
   result=MathMax(result,InpRsiPeriod+3);
   result=MathMax(result,InpDonchianEntry+3);
   result=MathMax(result,InpDonchianExit+3);
   result=MathMax(result,InpMomentumLookback+3);
   return result;
  }

bool LoadClosedSignalBars(MqlRates &bars[])
  {
   ArraySetAsSeries(bars,true);
   int requested=MaximumLookback()+20;
   int copied=CopyRates(_Symbol,InpSignalTimeframe,1,requested,bars);
   return copied>=MaximumLookback();
  }

double AtrAt(const MqlRates &bars[],const int start,const int period)
  {
   if(period<1 || start<0 || start+period>=ArraySize(bars)) return 0.0;
   double total=0.0;
   for(int i=start;i<start+period;i++)
     {
      double previous_close=bars[i+1].close;
      double true_range=MathMax(bars[i].high-bars[i].low,
                                MathMax(MathAbs(bars[i].high-previous_close),
                                        MathAbs(bars[i].low-previous_close)));
      total+=true_range;
     }
   return total/(double)period;
  }

double EmaAt(const MqlRates &bars[],const int start,const int period)
  {
   int warmup=MathMax(period+2,period*5);
   if(period<2 || start<0 || start+warmup>ArraySize(bars)) return 0.0;
   int oldest=start+warmup-1;
   double ema=bars[oldest].close;
   double alpha=2.0/((double)period+1.0);
   for(int i=oldest-1;i>=start;i--)
      ema=alpha*bars[i].close+(1.0-alpha)*ema;
   return ema;
  }

double RsiAt(const MqlRates &bars[],const int start,const int period)
  {
   if(period<2 || start<0 || start+period>=ArraySize(bars)) return 50.0;
   double gains=0.0;
   double losses=0.0;
   for(int i=start;i<start+period;i++)
     {
      double change=bars[i].close-bars[i+1].close;
      if(change>0.0) gains+=change;
      else losses-=change;
     }
   if(losses<=0.0) return (gains>0.0 ? 100.0 : 50.0);
   if(gains<=0.0) return 0.0;
   double relative_strength=gains/losses;
   return 100.0-100.0/(1.0+relative_strength);
  }

double HighestHigh(const MqlRates &bars[],const int start,const int count)
  {
   if(count<1 || start<0 || start+count>ArraySize(bars)) return 0.0;
   double value=-DBL_MAX;
   for(int i=start;i<start+count;i++) value=MathMax(value,bars[i].high);
   return value;
  }

double LowestLow(const MqlRates &bars[],const int start,const int count)
  {
   if(count<1 || start<0 || start+count>ArraySize(bars)) return 0.0;
   double value=DBL_MAX;
   for(int i=start;i<start+count;i++) value=MathMin(value,bars[i].low);
   return value;
  }

bool SelectOwnPosition(ulong &ticket,ENUM_POSITION_TYPE &type,datetime &opened_at)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong candidate=PositionGetTicket(i);
      if(candidate==0 || !PositionSelectByTicket(candidate)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      ticket=candidate;
      type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      opened_at=(datetime)PositionGetInteger(POSITION_TIME);
      return true;
     }
   ticket=0;
   type=POSITION_TYPE_BUY;
   opened_at=0;
   return false;
  }

int PositionDirection(const ENUM_POSITION_TYPE type)
  {
   return (type==POSITION_TYPE_BUY ? 1 : -1);
  }

bool TrendAllows(const MqlRates &bars[],const int direction)
  {
   if(!InpUseTrendFilter) return true;
   double trend=EmaAt(bars,0,InpTrendEmaPeriod);
   if(trend<=0.0) return false;
   return (direction>0 ? bars[0].close>trend : bars[0].close<trend);
  }

bool HigherTimeframeRegimeAllows(const int direction,string &detail)
  {
   if(!InpUseHigherTimeframeRegime) return true;
   int warmup=MathMax(InpRegimeEmaPeriod*5+3,InpRegimeMomentumLookback+3);
   MqlRates regime[];
   ArraySetAsSeries(regime,true);
   if(CopyRates(_Symbol,InpRegimeTimeframe,1,warmup+20,regime)<warmup) return false;

   double regime_ema=EmaAt(regime,0,InpRegimeEmaPeriod);
   if(regime_ema<=0.0 || InpRegimeMomentumLookback>=ArraySize(regime)) return false;
   double regime_move=regime[0].close-regime[InpRegimeMomentumLookback].close;
   bool ema_allows=(direction>0 ? regime[0].close>regime_ema : regime[0].close<regime_ema);
   bool momentum_allows=(direction>0 ? regime_move>0.0 : regime_move<0.0);
   bool allowed=false;
   if(InpRegimeMode==GOLD_REGIME_EMA) allowed=ema_allows;
   else if(InpRegimeMode==GOLD_REGIME_MOMENTUM) allowed=momentum_allows;
   else allowed=ema_allows && momentum_allows;
   detail+=StringFormat("|regime_tf=%s_mode=%d_ema=%d_mom=%d",
                        EnumToString(InpRegimeTimeframe),(int)InpRegimeMode,
                        InpRegimeEmaPeriod,InpRegimeMomentumLookback);
   return allowed;
  }

int KeltnerDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   double ema0=EmaAt(bars,0,InpKeltnerEmaPeriod);
   double ema1=EmaAt(bars,1,InpKeltnerEmaPeriod);
   double atr0=AtrAt(bars,0,InpKeltnerAtrPeriod);
   double atr1=AtrAt(bars,1,InpKeltnerAtrPeriod);
   if(ema0<=0.0 || ema1<=0.0 || atr0<=0.0 || atr1<=0.0) return current_direction;
   double upper0=ema0+InpKeltnerAtrMultiplier*atr0;
   double lower0=ema0-InpKeltnerAtrMultiplier*atr0;
   double upper1=ema1+InpKeltnerAtrMultiplier*atr1;
   double lower1=ema1-InpKeltnerAtrMultiplier*atr1;
   detail=StringFormat("kc_ema=%d_mult=%.2f",InpKeltnerEmaPeriod,InpKeltnerAtrMultiplier);
   if(current_direction>0) return (bars[0].close<ema0 ? 0 : 1);
   if(current_direction<0) return (bars[0].close>ema0 ? 0 : -1);
   if(bars[0].close>upper0 && bars[1].close<=upper1) return 1;
   if(bars[0].close<lower0 && bars[1].close>=lower1) return -1;
   return 0;
  }

int RsiDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   double rsi0=RsiAt(bars,0,InpRsiPeriod);
   double rsi1=RsiAt(bars,1,InpRsiPeriod);
   detail=StringFormat("rsi_%d=%.2f",InpRsiPeriod,rsi0);
   if(current_direction>0) return (rsi0>=InpRsiExit ? 0 : 1);
   if(current_direction<0) return (rsi0<=InpRsiExit ? 0 : -1);
   if(rsi0<=InpRsiLower && rsi1>InpRsiLower) return 1;
   if(rsi0>=InpRsiUpper && rsi1<InpRsiUpper) return -1;
   return 0;
  }

int DonchianDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   double upper_entry=HighestHigh(bars,1,InpDonchianEntry);
   double lower_entry=LowestLow(bars,1,InpDonchianEntry);
   double upper_exit=HighestHigh(bars,1,InpDonchianExit);
   double lower_exit=LowestLow(bars,1,InpDonchianExit);
   detail=StringFormat("donchian_%d_%d",InpDonchianEntry,InpDonchianExit);
   if(current_direction>0) return (bars[0].close<lower_exit ? 0 : 1);
   if(current_direction<0) return (bars[0].close>upper_exit ? 0 : -1);
   if(bars[0].close>upper_entry) return 1;
   if(bars[0].close<lower_entry) return -1;
   return 0;
  }

int MomentumDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   if(InpMomentumLookback>=ArraySize(bars)) return current_direction;
   double atr=AtrAt(bars,0,InpRiskAtrPeriod);
   double move=bars[0].close-bars[InpMomentumLookback].close;
   double threshold=InpMomentumMinAtr*atr;
   int signal=(MathAbs(move)>threshold ? SignOf(move) : 0);
   detail=StringFormat("momentum_%d_move=%.2f",InpMomentumLookback,move);
   if(current_direction==0) return signal;
   return (signal==current_direction ? current_direction : 0);
  }

int DailyOpenBreakoutDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   if(current_direction!=0) return current_direction;
   if(InpOrbOneTradePerDay && g_last_orb_entry_day==DayKey(bars[0].time)) return 0;

   MqlRates daily[];
   ArraySetAsSeries(daily,true);
   int requested=InpOrbAtrPeriod+5;
   if(CopyRates(_Symbol,PERIOD_D1,1,requested,daily)<InpOrbAtrPeriod+1) return 0;
   double daily_atr=AtrAt(daily,0,InpOrbAtrPeriod);
   double daily_open=iOpen(_Symbol,PERIOD_D1,0);
   if(daily_atr<=0.0 || daily_open<=0.0) return 0;
   double prior_range_ratio=(daily[0].high-daily[0].low)/daily_atr;
   if(InpOrbUseContractionFilter && prior_range_ratio>InpOrbMaxPriorRangeAtr) return 0;

   double upper=daily_open+InpOrbThresholdAtr*daily_atr;
   double lower=daily_open-InpOrbThresholdAtr*daily_atr;
   detail=StringFormat("daily_orb_open=%.2f_atr=%.2f_k=%.2f_prior=%.2f",
                       daily_open,daily_atr,InpOrbThresholdAtr,prior_range_ratio);
   if(bars[0].close>upper) return 1;
   if(bars[0].close<lower) return -1;
   return 0;
  }

int KeltnerRsiEnsembleDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   if(current_direction!=0)
     {
      if(g_active_ensemble_model==2) return RsiDirection(bars,current_direction,detail);
      return KeltnerDirection(bars,current_direction,detail);
     }

   string keltner_detail="";
   string rsi_detail="";
   int keltner_direction=KeltnerDirection(bars,0,keltner_detail);
   MqlDateTime parts;
   TimeToStruct(bars[0].time,parts);
   int rsi_direction=0;
   if(HourInWindow(parts.hour,InpEnsembleRsiStartHour,InpEnsembleRsiEndHour))
      rsi_direction=RsiDirection(bars,0,rsi_detail);

   int selected=0;
   g_pending_ensemble_model=0;
   if(keltner_direction!=0 && rsi_direction!=0)
     {
      if(keltner_direction==rsi_direction)
        {
         selected=keltner_direction;
         g_pending_ensemble_model=1;
        }
      else if(InpEnsembleConflictMode==1)
        {
         selected=keltner_direction;
         g_pending_ensemble_model=1;
        }
      else if(InpEnsembleConflictMode==2)
        {
         selected=rsi_direction;
         g_pending_ensemble_model=2;
        }
     }
   else if(keltner_direction!=0)
     {
      selected=keltner_direction;
      g_pending_ensemble_model=1;
     }
   else if(rsi_direction!=0)
     {
      selected=rsi_direction;
      g_pending_ensemble_model=2;
     }
   detail=StringFormat("ensemble_model=%d|%s|%s",g_pending_ensemble_model,
                       keltner_detail,rsi_detail);
   return selected;
  }

int DesiredDirection(const MqlRates &bars[],const int current_direction,string &detail)
  {
   int desired=0;
   if(InpMode==GOLD_H1_KELTNER_BREAKOUT)
      desired=KeltnerDirection(bars,current_direction,detail);
   else if(InpMode==GOLD_H1_RSI_REVERSION)
      desired=RsiDirection(bars,current_direction,detail);
   else if(InpMode==GOLD_H1_DONCHIAN)
      desired=DonchianDirection(bars,current_direction,detail);
   else if(InpMode==GOLD_H1_MOMENTUM)
      desired=MomentumDirection(bars,current_direction,detail);
   else if(InpMode==GOLD_M15_DAILY_OPEN_BREAKOUT)
      desired=DailyOpenBreakoutDirection(bars,current_direction,detail);
   else
      desired=KeltnerRsiEnsembleDirection(bars,current_direction,detail);

   if(current_direction==0 && desired!=0 && !TrendAllows(bars,desired)) desired=0;
   if(current_direction==0 && desired!=0 && !HigherTimeframeRegimeAllows(desired,detail)) desired=0;
   if(desired>0 && !InpAllowLong) desired=0;
   if(desired<0 && !InpAllowShort) desired=0;
   return desired;
  }

double NormalizeVolumeDown(double volume)
  {
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0 || minimum<=0.0) return 0.0;
   volume=MathMin(volume,MathMin(maximum,InpMaxLotAbsolute));
   volume=MathFloor((volume+1e-12)/step)*step;
   if(volume<minimum) return 0.0;
   int digits=(int)MathMax(0,MathCeil(-MathLog10(step)));
   return NormalizeDouble(volume,digits);
  }

double DrawdownRiskMultiplier()
  {
   if(!InpUseDrawdownThrottle || g_peak_equity<=0.0) return 1.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown=MathMax(0.0,1.0-equity/g_peak_equity);
   if(drawdown<=InpThrottleStartDDPct) return 1.0;
   if(drawdown>=InpThrottleFullDDPct) return InpThrottleMinRiskMultiplier;
   double span=InpThrottleFullDDPct-InpThrottleStartDDPct;
   double progress=(drawdown-InpThrottleStartDDPct)/span;
   return 1.0-progress*(1.0-InpThrottleMinRiskMultiplier);
  }

double RiskSizedVolume(const int direction,const double entry,const double stop)
  {
   ENUM_ORDER_TYPE order_type=(direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double one_lot_pnl=0.0;
   if(!OrderCalcProfit(order_type,_Symbol,1.0,entry,stop,one_lot_pnl)) return 0.0;
   double loss_per_lot=MathAbs(one_lot_pnl);
   if(loss_per_lot<=0.0) return 0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double requested=equity*InpRiskPerTradePct*DrawdownRiskMultiplier()/loss_per_lot;
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(requested<minimum && loss_per_lot*minimum<=equity*InpMaxActualRiskPct)
      requested=minimum;
   double volume=NormalizeVolumeDown(requested);
   if(volume<=0.0) return 0.0;

   double margin=0.0;
   if(OrderCalcMargin(order_type,_Symbol,volume,entry,margin) && margin>0.0)
     {
      double allowed=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*InpMarginSafetyFraction;
      if(margin>allowed) volume=NormalizeVolumeDown(volume*allowed/margin);
     }
   return volume;
  }

bool SpreadIsAcceptable()
  {
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   return bid>0.0 && ask>bid && ask-bid<=InpMaxSpreadDollars;
  }

bool SessionAllowsEntry()
  {
   if(!InpUseServerSession) return true;
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(),parts);
   if(InpSessionStartHour==InpSessionEndHour) return true;
   if(InpSessionStartHour<InpSessionEndHour)
      return parts.hour>=InpSessionStartHour && parts.hour<InpSessionEndHour;
   return parts.hour>=InpSessionStartHour || parts.hour<InpSessionEndHour;
  }

bool CloseOwnPosition(const ulong ticket,const string reason)
  {
   bool ok=g_trade.PositionClose(ticket,InpDeviationPoints);
   if(ok && InpMode==GOLD_H1_KELTNER_RSI_ENSEMBLE) g_active_ensemble_model=0;
   if(!OptimizationQuiet())
      PrintFormat("GOLD_INTRADAY_EXIT|time=%s|reason=%s|ok=%s|retcode=%u",
                  TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),reason,
                  (ok ? "true" : "false"),g_trade.ResultRetcode());
   return ok;
  }

bool OpenDirection(const int direction,const double atr,const string detail)
  {
   if(!SpreadIsAcceptable() || !SessionAllowsEntry()) return false;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double entry=(direction>0 ? ask : bid);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   long stops_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double broker_min=(double)MathMax(stops_level,freeze_level)*point+2.0*point;
   double stop_atr=InpInitialStopAtr;
   double target_r=InpTakeProfitR;
   if(InpMode==GOLD_H1_KELTNER_RSI_ENSEMBLE && g_pending_ensemble_model==2)
     {
      stop_atr=InpEnsembleRsiStopAtr;
      target_r=InpEnsembleRsiTakeProfitR;
     }
   double stop_distance=MathMax(stop_atr*atr,broker_min);
   double target_distance=(target_r>0.0 ? MathMax(target_r*stop_distance,broker_min) : 0.0);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double stop=NormalizeDouble(entry-(double)direction*stop_distance,digits);
   double target=(target_distance>0.0 ? NormalizeDouble(entry+(double)direction*target_distance,digits) : 0.0);
   double volume=RiskSizedVolume(direction,entry,stop);
   if(volume<=0.0)
     {
      if(!OptimizationQuiet()) Print("GOLD_INTRADAY_VETO|reason=volume");
      return false;
     }
   string comment=StringFormat("GoldIntra m%d",(int)InpMode);
   bool ok=(direction>0 ? g_trade.Buy(volume,_Symbol,0.0,stop,target,comment)
                        : g_trade.Sell(volume,_Symbol,0.0,stop,target,comment));
   if(ok && InpMode==GOLD_M15_DAILY_OPEN_BREAKOUT)
      g_last_orb_entry_day=DayKey(TimeCurrent());
   if(ok && InpMode==GOLD_H1_KELTNER_RSI_ENSEMBLE)
      g_active_ensemble_model=g_pending_ensemble_model;
   if(!OptimizationQuiet())
      PrintFormat("GOLD_INTRADAY_ENTRY|time=%s|direction=%s|volume=%.2f|entry=%.2f|sl=%.2f|tp=%.2f|atr=%.2f|signal=%s|ok=%s|retcode=%u",
                  TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                  (direction>0 ? "LONG" : "SHORT"),volume,entry,stop,target,atr,detail,
                  (ok ? "true" : "false"),g_trade.ResultRetcode());
   return ok;
  }

void ApplyAtrTrail(const ulong ticket,const ENUM_POSITION_TYPE type,const MqlRates &bars[],const double atr)
  {
   if(!InpUseAtrTrail || !PositionSelectByTicket(ticket)) return;
   int direction=PositionDirection(type);
   double current_sl=PositionGetDouble(POSITION_SL);
   double current_tp=PositionGetDouble(POSITION_TP);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minimum=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point+2.0*point;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double candidate=NormalizeDouble(bars[0].close-(double)direction*InpTrailAtr*atr,digits);
   bool improve=(direction>0 ? candidate>current_sl && candidate<bid-minimum
                             : (current_sl<=0.0 || candidate<current_sl) && candidate>ask+minimum);
   if(improve) g_trade.PositionModify(ticket,candidate,current_tp);
  }

void EvaluateSignalBar()
  {
   if(g_halted) return;
   MqlRates bars[];
   if(!LoadClosedSignalBars(bars)) return;
   double risk_atr=AtrAt(bars,0,InpRiskAtrPeriod);
   if(risk_atr<=0.0) return;

   ulong ticket;
   ENUM_POSITION_TYPE type;
   datetime opened_at;
   bool has_position=SelectOwnPosition(ticket,type,opened_at);
   int current_direction=(has_position ? PositionDirection(type) : 0);
   if(has_position) ApplyAtrTrail(ticket,type,bars,risk_atr);

   string detail="";
   int desired=DesiredDirection(bars,current_direction,detail);
   int timeframe_seconds=PeriodSeconds(InpSignalTimeframe);
   int maximum_holding=InpMaxHoldingBars;
   if(InpMode==GOLD_H1_KELTNER_RSI_ENSEMBLE && g_active_ensemble_model==2)
      maximum_holding=InpEnsembleRsiMaxHoldingBars;
   if(has_position && maximum_holding>0 && timeframe_seconds>0 &&
      TimeCurrent()>=opened_at+(datetime)((long)maximum_holding*timeframe_seconds))
      desired=0;

   if(!OptimizationQuiet())
      PrintFormat("GOLD_INTRADAY_SIGNAL|bar=%s|mode=%d|current=%d|desired=%d|close=%.2f|atr=%.2f|detail=%s",
                  TimeToString(bars[0].time,TIME_DATE|TIME_MINUTES),(int)InpMode,
                  current_direction,desired,bars[0].close,risk_atr,detail);

   if(has_position && desired!=current_direction)
     {
      if(!CloseOwnPosition(ticket,(desired==0 ? "SIGNAL_OR_TIME" : "REVERSE"))) return;
      has_position=false;
      current_direction=0;
     }
   if(!has_position && desired!=0) OpenDirection(desired,risk_atr,detail);
  }

void EnforceCircuitBreaker()
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_peak_equity=MathMax(g_peak_equity,equity);
   if(g_halted || InpCircuitBreakerDDPct<=0.0 || g_peak_equity<=0.0) return;
   if(equity>g_peak_equity*(1.0-InpCircuitBreakerDDPct)) return;
   ulong ticket;
   ENUM_POSITION_TYPE type;
   datetime opened_at;
   if(SelectOwnPosition(ticket,type,opened_at)) CloseOwnPosition(ticket,"CIRCUIT_BREAKER");
   g_halted=true;
   if(!OptimizationQuiet()) Print("GOLD_INTRADAY_HALT|reason=circuit_breaker");
  }

int OnInit()
  {
   if(InpTesterOnly && !MQLInfoInteger(MQL_TESTER)) return INIT_PARAMETERS_INCORRECT;
   if(_Symbol!="XAUUSD" || PeriodSeconds(InpSignalTimeframe)<=0 ||
      InpKeltnerEmaPeriod<2 || InpKeltnerAtrPeriod<2 || InpKeltnerAtrMultiplier<=0.0 ||
      InpRsiPeriod<2 || InpRsiLower<=0.0 || InpRsiUpper>=100.0 ||
      InpRsiLower>=InpRsiExit || InpRsiExit>=InpRsiUpper ||
      InpDonchianEntry<2 || InpDonchianExit<2 || InpDonchianExit>=InpDonchianEntry ||
      InpMomentumLookback<1 || InpMomentumMinAtr<0.0 || InpTrendEmaPeriod<2 ||
      InpOrbAtrPeriod<2 || InpOrbThresholdAtr<=0.0 || InpOrbMaxPriorRangeAtr<=0.0 ||
      InpEnsembleRsiStartHour<0 || InpEnsembleRsiStartHour>23 ||
      InpEnsembleRsiEndHour<0 || InpEnsembleRsiEndHour>23 ||
      InpEnsembleConflictMode<0 || InpEnsembleConflictMode>2 ||
      InpEnsembleRsiStopAtr<=0.0 || InpEnsembleRsiTakeProfitR<0.0 ||
      InpEnsembleRsiMaxHoldingBars<1 ||
      PeriodSeconds(InpRegimeTimeframe)<=0 || InpRegimeEmaPeriod<2 ||
      InpRegimeMomentumLookback<1 ||
      InpRiskAtrPeriod<2 || InpInitialStopAtr<=0.0 || InpTakeProfitR<0.0 ||
      InpTrailAtr<=0.0 || InpMaxHoldingBars<1 || InpBarExecutionDelayMinutes<0 ||
      InpBarExecutionDelayMinutes>30 || InpSessionStartHour<0 || InpSessionStartHour>23 ||
      InpSessionEndHour<0 || InpSessionEndHour>23 || InpRiskPerTradePct<=0.0 ||
      InpRiskPerTradePct>0.10 || InpMaxActualRiskPct<InpRiskPerTradePct ||
      InpMaxActualRiskPct>0.10 || InpMaxLotAbsolute<=0.0 || InpMarginSafetyFraction<=0.0 ||
      InpMarginSafetyFraction>1.0 || InpThrottleStartDDPct<0.0 ||
      InpThrottleFullDDPct<=InpThrottleStartDDPct || InpThrottleFullDDPct>=1.0 ||
      InpThrottleMinRiskMultiplier<=0.0 || InpThrottleMinRiskMultiplier>1.0 ||
      InpCircuitBreakerDDPct<0.0 || InpCircuitBreakerDDPct>=1.0 ||
      InpMinTradesForCriterion<1)
      return INIT_PARAMETERS_INCORRECT;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_last_signal_bar_open=iTime(_Symbol,InpSignalTimeframe,0);
   g_signal_pending=true;
   g_peak_equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!OptimizationQuiet())
      PrintFormat("GOLD_INTRADAY_INIT|mode=%d|timeframe=%s|leverage=1:%d|balance=%.2f|risk=%.3f",
                  (int)InpMode,EnumToString(InpSignalTimeframe),
                  (int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                  AccountInfoDouble(ACCOUNT_BALANCE),InpRiskPerTradePct);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   EnforceCircuitBreaker();
   datetime signal_bar_open=iTime(_Symbol,InpSignalTimeframe,0);
   if(signal_bar_open<=0) return;
   if(signal_bar_open!=g_last_signal_bar_open)
     {
      g_last_signal_bar_open=signal_bar_open;
      g_signal_pending=true;
     }
   if(!g_signal_pending || g_halted) return;
   datetime eligible_at=signal_bar_open+(datetime)((long)InpBarExecutionDelayMinutes*60);
   if(TimeCurrent()<eligible_at || !SpreadIsAcceptable()) return;
   g_signal_pending=false;
   EvaluateSignalBar();
  }

void OnDeinit(const int reason)
  {
   if(MQLInfoInteger(MQL_TESTER) && !OptimizationQuiet())
      PrintFormat("GOLD_INTRADAY_SUMMARY|balance=%.2f|equity=%.2f|halted=%s",
                  AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),
                  (g_halted ? "true" : "false"));
  }

double OnTester()
  {
   double profit=TesterStatistics(STAT_PROFIT);
   double trades=TesterStatistics(STAT_TRADES);
   double drawdown=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double factor=TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe=TesterStatistics(STAT_SHARPE_RATIO);
   if(!MathIsValidNumber(factor) || factor>10.0) factor=10.0;
   if(!MathIsValidNumber(sharpe)) sharpe=0.0;
   if(trades<(double)InpMinTradesForCriterion)
      return -1000000.0+trades*1000.0+profit;
   if(profit<=0.0) return -100000.0+profit;
   double quality=MathMax(0.10,MathMin(4.0,factor))*MathMax(0.10,1.0+sharpe);
   return profit*MathSqrt(trades)*quality/(1.0+drawdown);
  }
