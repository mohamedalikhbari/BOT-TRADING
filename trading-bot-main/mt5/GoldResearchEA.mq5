#property strict
#property version   "1.00"
#property description "Gold trend research EA: TSMOM, moving-average crossover, Donchian and ensemble."
#property description "Tester-only. Signals use closed D1 bars and all P&L is produced by MetaTrader 5."

#include <Trade/Trade.mqh>

enum ENUM_GOLD_RESEARCH_MODE
  {
   GOLD_TSMOM_12M = 0,
   GOLD_MA_CROSS = 1,
   GOLD_DONCHIAN = 2,
   GOLD_TREND_ENSEMBLE = 3
  };

input group "Research strategy"
input ENUM_GOLD_RESEARCH_MODE InpMode = GOLD_TSMOM_12M;
input int      InpTsmomLookback       = 252;
input int      InpMaFast              = 20;
input int      InpMaSlow              = 260;
input int      InpDonchianEntry        = 55;
input int      InpDonchianExit         = 20;
input int      InpEnsembleMinVotes     = 3;
input double   InpSignalDeadbandATR    = 0.00;
input bool     InpAllowLong            = true;
input bool     InpAllowShort           = true;

input group "Volatility and exits"
input int      InpAtrPeriod             = 20;
input double   InpInitialStopATR        = 4.00;
input bool     InpUseDailyAtrTrail      = true;
input double   InpDailyTrailATR         = 4.00;
input int      InpMaxHoldingDays        = 0;

input group "Risk and execution"
input double   InpRiskPerTradePct       = 0.005;
input double   InpMaxActualRiskPct      = 0.020;
input double   InpMaxLotAbsolute        = 2.00;
input double   InpMaxSpreadDollars      = 2.00;
input int      InpDailyExecutionDelayMinutes = 60;
input double   InpMarginSafetyFraction  = 0.70;
input double   InpCircuitBreakerDDPct   = 0.25;
input ulong    InpMagic                 = 120260900;
input int      InpDeviationPoints       = 100;

input group "Audit"
input int      InpMinTradesForCriterion = 8;
input bool     InpTesterOnly             = true;

CTrade g_trade;
datetime g_last_daily_open=0;
bool g_daily_evaluation_pending=false;
double g_peak_equity=0.0;
bool g_halted=false;

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

int MaximumLookback()
  {
   int result=MathMax(InpAtrPeriod+2,InpTsmomLookback+2);
   result=MathMax(result,InpMaSlow+2);
   result=MathMax(result,InpDonchianEntry+2);
   result=MathMax(result,InpDonchianExit+2);
   result=MathMax(result,254);
   return result;
  }

bool LoadClosedDaily(MqlRates &bars[])
  {
   ArraySetAsSeries(bars,true);
   int requested=MaximumLookback()+10;
   int copied=CopyRates(_Symbol,PERIOD_D1,1,requested,bars);
   return copied>=MaximumLookback();
  }

double DailyAtr(const MqlRates &bars[],const int period)
  {
   if(period<=0 || ArraySize(bars)<=period) return 0.0;
   double total=0.0;
   for(int i=0;i<period;i++)
     {
      double previous_close=bars[i+1].close;
      double tr=MathMax(bars[i].high-bars[i].low,
                        MathMax(MathAbs(bars[i].high-previous_close),
                                MathAbs(bars[i].low-previous_close)));
      total+=tr;
     }
   return total/(double)period;
  }

double AverageClose(const MqlRates &bars[],const int start,const int count)
  {
   if(count<=0 || start<0 || start+count>ArraySize(bars)) return 0.0;
   double total=0.0;
   for(int i=start;i<start+count;i++) total+=bars[i].close;
   return total/(double)count;
  }

double HighestHigh(const MqlRates &bars[],const int start,const int count)
  {
   if(count<=0 || start<0 || start+count>ArraySize(bars)) return 0.0;
   double value=-DBL_MAX;
   for(int i=start;i<start+count;i++) value=MathMax(value,bars[i].high);
   return value;
  }

double LowestLow(const MqlRates &bars[],const int start,const int count)
  {
   if(count<=0 || start<0 || start+count>ArraySize(bars)) return 0.0;
   double value=DBL_MAX;
   for(int i=start;i<start+count;i++) value=MathMin(value,bars[i].low);
   return value;
  }

int MomentumDirection(const MqlRates &bars[],const int lookback,const double deadband)
  {
   if(lookback<=0 || lookback>=ArraySize(bars)) return 0;
   double move=bars[0].close-bars[lookback].close;
   if(MathAbs(move)<=deadband) return 0;
   return SignOf(move);
  }

int MovingAverageDirection(const MqlRates &bars[],const double deadband)
  {
   double fast=AverageClose(bars,0,InpMaFast);
   double slow=AverageClose(bars,0,InpMaSlow);
   if(fast<=0.0 || slow<=0.0 || MathAbs(fast-slow)<=deadband) return 0;
   return SignOf(fast-slow);
  }

int EnsembleDirection(const MqlRates &bars[],const double deadband,string &detail)
  {
   const int horizons[4]={21,63,126,252};
   int votes=0;
   for(int i=0;i<4;i++) votes+=MomentumDirection(bars,horizons[i],deadband);
   detail=StringFormat("ensemble_votes=%d",votes);
   if(votes>=InpEnsembleMinVotes) return 1;
   if(votes<=-InpEnsembleMinVotes) return -1;
   return 0;
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

int DesiredDirection(const MqlRates &bars[],const double atr,const int current_direction,string &detail)
  {
   double deadband=InpSignalDeadbandATR*atr;
   if(InpMode==GOLD_TSMOM_12M)
     {
      int direction=MomentumDirection(bars,InpTsmomLookback,deadband);
      detail=StringFormat("tsmom_%d_move=%.2f",InpTsmomLookback,
                          bars[0].close-bars[InpTsmomLookback].close);
      return direction;
     }
   if(InpMode==GOLD_MA_CROSS)
     {
      int direction=MovingAverageDirection(bars,deadband);
      detail=StringFormat("ma_%d_%d",InpMaFast,InpMaSlow);
      return direction;
     }
   if(InpMode==GOLD_TREND_ENSEMBLE)
      return EnsembleDirection(bars,deadband,detail);

   double close=bars[0].close;
   double upper_entry=HighestHigh(bars,1,InpDonchianEntry);
   double lower_entry=LowestLow(bars,1,InpDonchianEntry);
   double upper_exit=HighestHigh(bars,1,InpDonchianExit);
   double lower_exit=LowestLow(bars,1,InpDonchianExit);
   detail=StringFormat("donchian_%d_%d",InpDonchianEntry,InpDonchianExit);
   if(close>upper_entry+deadband) return 1;
   if(close<lower_entry-deadband) return -1;
   if(current_direction>0) return (close<lower_exit ? 0 : 1);
   if(current_direction<0) return (close>upper_exit ? 0 : -1);
   return 0;
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

double RiskSizedVolume(const int direction,const double entry,const double stop)
  {
   ENUM_ORDER_TYPE type=(direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double one_lot_pnl=0.0;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,stop,one_lot_pnl)) return 0.0;
   double loss_per_lot=MathAbs(one_lot_pnl);
   if(loss_per_lot<=0.0) return 0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_cash=equity*InpRiskPerTradePct;
   double requested=risk_cash/loss_per_lot;
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(requested<minimum && loss_per_lot*minimum<=equity*InpMaxActualRiskPct)
      requested=minimum;
   double volume=NormalizeVolumeDown(requested);
   if(volume<=0.0) return 0.0;

   double margin=0.0;
   if(OrderCalcMargin(type,_Symbol,volume,entry,margin) && margin>0.0)
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

bool CloseOwnPosition(const ulong ticket,const string reason)
  {
   bool ok=g_trade.PositionClose(ticket,InpDeviationPoints);
   if(!OptimizationQuiet())
      PrintFormat("GOLD_RESEARCH_EXIT|time=%s|reason=%s|ok=%s|retcode=%u",
                  TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),reason,
                  (ok ? "true" : "false"),g_trade.ResultRetcode());
   return ok;
  }

bool OpenDirection(const int direction,const double atr,const string signal_detail)
  {
   if(direction>0 && !InpAllowLong) return false;
   if(direction<0 && !InpAllowShort) return false;
   if(!SpreadIsAcceptable())
     {
      if(!OptimizationQuiet()) Print("GOLD_RESEARCH_VETO|reason=spread");
      return false;
     }
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double entry=(direction>0 ? ask : bid);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   long stops_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double broker_min=(double)MathMax(stops_level,freeze_level)*point+2.0*point;
   double distance=MathMax(InpInitialStopATR*atr,broker_min);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double stop=NormalizeDouble(entry-(double)direction*distance,digits);
   double volume=RiskSizedVolume(direction,entry,stop);
   if(volume<=0.0)
     {
      if(!OptimizationQuiet()) Print("GOLD_RESEARCH_VETO|reason=volume");
      return false;
     }
   string comment=StringFormat("GoldResearch m%d",(int)InpMode);
   bool ok=(direction>0 ? g_trade.Buy(volume,_Symbol,0.0,stop,0.0,comment)
                        : g_trade.Sell(volume,_Symbol,0.0,stop,0.0,comment));
   if(!OptimizationQuiet())
      PrintFormat("GOLD_RESEARCH_ENTRY|time=%s|direction=%s|volume=%.2f|entry=%.2f|sl=%.2f|atr=%.2f|signal=%s|ok=%s|retcode=%u",
                  TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                  (direction>0 ? "LONG" : "SHORT"),volume,entry,stop,atr,signal_detail,
                  (ok ? "true" : "false"),g_trade.ResultRetcode());
   return ok;
  }

void ApplyDailyTrail(const ulong ticket,const ENUM_POSITION_TYPE type,const MqlRates &bars[],const double atr)
  {
   if(!InpUseDailyAtrTrail || !PositionSelectByTicket(ticket)) return;
   int direction=PositionDirection(type);
   double current_sl=PositionGetDouble(POSITION_SL);
   double current_tp=PositionGetDouble(POSITION_TP);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   long stops_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minimum=(double)stops_level*point+2.0*point;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double candidate=NormalizeDouble(bars[0].close-(double)direction*InpDailyTrailATR*atr,digits);
   bool improve=false;
   if(direction>0)
      improve=(candidate>current_sl && candidate<bid-minimum);
   else
      improve=((current_sl<=0.0 || candidate<current_sl) && candidate>ask+minimum);
   if(!improve) return;
   bool ok=g_trade.PositionModify(ticket,candidate,current_tp);
   if(!OptimizationQuiet())
      PrintFormat("GOLD_RESEARCH_TRAIL|time=%s|sl=%.2f|ok=%s",
                  TimeToString(TimeCurrent(),TIME_DATE),candidate,(ok ? "true" : "false"));
  }

void EvaluateDailySignal()
  {
   if(g_halted) return;
   MqlRates bars[];
   if(!LoadClosedDaily(bars))
     {
      if(!OptimizationQuiet()) Print("GOLD_RESEARCH_VETO|reason=warmup");
      return;
     }
   double atr=DailyAtr(bars,InpAtrPeriod);
   if(atr<=0.0) return;

   ulong ticket;
   ENUM_POSITION_TYPE type;
   datetime opened_at;
   bool has_position=SelectOwnPosition(ticket,type,opened_at);
   int current_direction=(has_position ? PositionDirection(type) : 0);
   if(has_position) ApplyDailyTrail(ticket,type,bars,atr);

   string detail="";
   int desired=DesiredDirection(bars,atr,current_direction,detail);
   if(desired>0 && !InpAllowLong) desired=0;
   if(desired<0 && !InpAllowShort) desired=0;
   if(InpMaxHoldingDays>0 && has_position &&
      TimeCurrent()>opened_at+(datetime)((long)InpMaxHoldingDays*86400))
      desired=0;

   if(!OptimizationQuiet())
      PrintFormat("GOLD_RESEARCH_SIGNAL|bar=%s|mode=%d|current=%d|desired=%d|close=%.2f|atr=%.2f|detail=%s",
                  TimeToString(bars[0].time,TIME_DATE),(int)InpMode,current_direction,desired,
                  bars[0].close,atr,detail);

   if(has_position && desired!=current_direction)
     {
      if(!CloseOwnPosition(ticket,(desired==0 ? "SIGNAL_FLAT" : "SIGNAL_REVERSE"))) return;
      has_position=false;
      current_direction=0;
     }
   if(!has_position && desired!=0) OpenDirection(desired,atr,detail);
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
   if(!OptimizationQuiet()) Print("GOLD_RESEARCH_HALT|reason=circuit_breaker");
  }

int OnInit()
  {
   if(InpTesterOnly && !MQLInfoInteger(MQL_TESTER))
     {
      Print("GOLD_RESEARCH_INIT|status=FAIL|reason=tester_only");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(_Symbol!="XAUUSD" || InpTsmomLookback<2 || InpMaFast<2 || InpMaSlow<=InpMaFast ||
      InpDonchianEntry<2 || InpDonchianExit<2 || InpDonchianExit>=InpDonchianEntry ||
      InpAtrPeriod<2 || InpInitialStopATR<=0.0 || InpRiskPerTradePct<=0.0 ||
      InpRiskPerTradePct>0.05 || InpMaxActualRiskPct<InpRiskPerTradePct ||
      InpMaxActualRiskPct>0.05 || InpMaxLotAbsolute<=0.0 || InpEnsembleMinVotes<1 ||
      InpEnsembleMinVotes>4 || InpDailyExecutionDelayMinutes<0 ||
      InpDailyExecutionDelayMinutes>360)
     {
      Print("GOLD_RESEARCH_INIT|status=FAIL|reason=parameters");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_last_daily_open=iTime(_Symbol,PERIOD_D1,0);
   g_daily_evaluation_pending=true;
   g_peak_equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!OptimizationQuiet())
      PrintFormat("GOLD_RESEARCH_INIT|status=OK|mode=%d|leverage=1:%d|balance=%.2f",
                  (int)InpMode,(int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                  AccountInfoDouble(ACCOUNT_BALANCE));
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   EnforceCircuitBreaker();
   datetime daily_open=iTime(_Symbol,PERIOD_D1,0);
   if(daily_open<=0) return;
   if(daily_open!=g_last_daily_open)
     {
      g_last_daily_open=daily_open;
      g_daily_evaluation_pending=true;
     }
   if(!g_daily_evaluation_pending || g_halted) return;
   datetime eligible_at=daily_open+(datetime)((long)InpDailyExecutionDelayMinutes*60);
   if(TimeCurrent()<eligible_at || !SpreadIsAcceptable()) return;
   g_daily_evaluation_pending=false;
   EvaluateDailySignal();
  }

void OnDeinit(const int reason)
  {
   if(MQLInfoInteger(MQL_TESTER) && !OptimizationQuiet())
      PrintFormat("GOLD_RESEARCH_SUMMARY|balance=%.2f|equity=%.2f|halted=%s",
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
