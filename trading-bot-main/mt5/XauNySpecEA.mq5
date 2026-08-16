#property copyright "Specifica XAU/USD v1.5"
#property version   "1.50"
#property strict
#property description "EA nativo MT5 per il backtest della specifica XAU/USD multi-timeframe v1.5"

#include <Trade/Trade.mqh>

// Tutti gli input corrispondono ai default dell'Appendice A. Il tester può
// sovrascriverli tramite un file .set senza ricompilare l'EA.
input group "Strategia - struttura e trend"
input int      InpKH4                 = 3;
input int      InpKH1                 = 3;
input int      InpKM15                = 2;
input int      InpKM5                 = 2;
input int      InpKM1                 = 1;
input double   InpMinBreakATR         = 0.05;
input int      InpEmaFast             = 21;
input int      InpEmaSlow             = 50;
input int      InpEmaMacro            = 200;
input bool     InpUseEmaMacro         = false;
input bool     InpUseEmaH1            = false;
enum ENUM_H4_BIAS_MODE
  {
   H4_EMA_AND_STRUCTURE = 0,
   H4_STRUCTURE_ONLY = 1
  };
input ENUM_H4_BIAS_MODE InpH4BiasMode = H4_STRUCTURE_ONLY;
enum ENUM_H1_CONFIRM_MODE
  {
   H1_STRICT_BOS = 0,
   H1_TREND_ALIGNED = 1
  };
input ENUM_H1_CONFIRM_MODE InpH1ConfirmMode = H1_TREND_ALIGNED;
input double   InpMinEmaSlope         = 0.05;
input int      InpEmaSlopeLookback    = 6;

enum ENUM_M5_FIB_MODE
  {
   M5_FIB_STRICT = 0,
   M5_FIB_LENIENT = 1,
   M5_FIB_OFF = 2
  };
input ENUM_M5_FIB_MODE InpM5FibMode   = M5_FIB_STRICT;

enum ENUM_M1_TRIGGER_MODE
  {
   M1_TRIGGER_BOS = 0,
   M1_TRIGGER_ZONE_READY = 1,
   M1_TRIGGER_DISPLACEMENT = 2
  };
input ENUM_M1_TRIGGER_MODE InpM1TriggerMode = M1_TRIGGER_DISPLACEMENT;
input double   InpMinM1DisplacementATR = 0.50;
input double   InpMaxM1DisplacementATR = 0.90;

enum ENUM_STOP_MODE
  {
   STOP_SWEEP_ANCHORED = 0,
   STOP_LOCAL_STRUCTURE = 1,
   STOP_ZONE_ONLY = 2
  };
input ENUM_STOP_MODE InpStopMode       = STOP_LOCAL_STRUCTURE;

enum ENUM_TARGET_MODE
  {
   TARGET_NEAREST = 0,
   TARGET_FIRST_VALID_RR = 1
  };
input ENUM_TARGET_MODE InpTargetMode   = TARGET_FIRST_VALID_RR;

input group "Strategia - pattern e trigger"
input int      InpMinSetupScore       = 8;
input double   InpMinFvgAtrM1         = 0.15;
input double   InpMinFvgAtrM5         = 0.20;
input int      InpIfvgMaxAgeM1        = 30;
input int      InpIfvgMaxAgeM5        = 20;
input int      InpMinImpulseCandles   = 2;
input double   InpMinImpulseATR       = 1.00;
input double   InpMinSweepAtrM15      = 0.10;
input double   InpMinWickRatioM15     = 0.50;
input double   InpMinSweepAtrM5       = 0.10;
input double   InpMinWickRatioM5      = 0.34;
input int      InpEntryTimeoutMinutes = 20;
input int      InpBiasMaxAgeH4        = 6;
input double   InpSlBufferATR         = 0.30;
input double   InpMinSlDollars        = 1.50;
input double   InpMaxSlDollars        = 6.00;
input double   InpMinRMultiple        = 2.00;
input double   InpMaxGapATR           = 3.00;
input int      InpGapSuspendBars      = 3;

enum ENUM_EXIT_MODE
  {
   EXIT_SCALED = 0,
   EXIT_FLAT_2R = 1
  };
input ENUM_EXIT_MODE InpExitMode      = EXIT_SCALED;

input group "Rischio ed esecuzione"
input double   InpRiskPerTradePct     = 0.005;
input int      InpMaxConcurrent       = 1;
input int      InpMaxTradesPerDay     = 2;
input double   InpMaxLotAbsolute      = 2.00;
input double   InpDailyLossLimitPct   = 0.05;
input double   InpMaxLossLimitPct     = 0.10;
input double   InpSafetyMargin        = 0.70;
input double   InpMaxSpread           = 0.50;
input ulong    InpMagic               = 120260803;
input int      InpDeviationPoints     = 50;

input group "News e audit"
input bool     InpRequireNewsCalendar = true;
input string   InpNewsFile            = "xauusd_news_20260201_20260731.csv";
input string   InpDiagnosticsFile     = "xau_ny_spec_diagnostics.csv";
input bool     InpRunSelfTests        = true;
input bool     InpTesterOnly          = true;

enum Direction
  {
   DIR_SHORT = -1,
   DIR_NONE = 0,
   DIR_LONG = 1
  };

enum Trend
  {
   TREND_BEARISH = -1,
   TREND_RANGING = 0,
   TREND_BULLISH = 1
  };

enum SwingKind
  {
   SWING_HIGH = 1,
   SWING_LOW = -1
  };

enum StructureEventKind
  {
   EVENT_NONE = 0,
   EVENT_BOS = 1,
   EVENT_CHOCH = 2
  };

enum ZoneType
  {
   ZONE_NONE = 0,
   ZONE_FVG = 1,
   ZONE_IFVG = 2,
   ZONE_ORDER_BLOCK = 3
  };

enum ZoneState
  {
   ZONE_FRESH = 0,
   ZONE_PARTIAL = 1,
   ZONE_MITIGATED = 2,
   ZONE_UNMITIGATED = 3,
   ZONE_INVALIDATED = 4
  };

string ZoneTypeName(const ZoneType type)
  {
   if(type==ZONE_FVG) return "FVG";
   if(type==ZONE_IFVG) return "IFVG";
   if(type==ZONE_ORDER_BLOCK) return "ORDER_BLOCK";
   return "NONE";
  }

enum SetupState
  {
   SETUP_IDLE = 0,
   SETUP_SWEEP_DETECTED = 1,
   SETUP_SWEEP_CONFIRMED = 2,
   SETUP_ENTRY_ARMED = 3,
   SETUP_ORDER_PENDING = 4,
   SETUP_IN_POSITION = 5,
   SETUP_HALTED = 6
  };

struct SwingPoint
  {
   SwingKind kind;
   double price;
   datetime occurred_at;
   datetime confirmed_at;
   int rate_index;
   double atr;
  };

struct StructureEvent
  {
   StructureEventKind kind;
   Direction direction;
   datetime occurred_at;
   double level;
   double close_price;
   int swing_rate_index;
  };

struct StructureSnapshot
  {
   Trend trend;
   bool has_last_high;
   bool has_prev_high;
   bool has_last_low;
   bool has_prev_low;
   SwingPoint last_high;
   SwingPoint prev_high;
   SwingPoint last_low;
   SwingPoint prev_low;
   bool has_latest_event;
   StructureEvent latest_event;
  };

struct BiasResult
  {
   Direction direction;
   datetime evaluated_at;
   double ema_fast;
   double ema_slow;
   double ema_macro;
   double slope;
   string reason;
  };

enum LiquidityPoolType
  {
   POOL_ASH = 0,
   POOL_ASL = 1,
   POOL_PNYH = 2,
   POOL_PNYL = 3,
   POOL_PDH = 4,
   POOL_PDL = 5,
   POOL_PRE_NY_H = 6,
   POOL_PRE_NY_L = 7
  };

enum LiquidityPoolState
  {
   LIQUIDITY_INTACT = 0,
   LIQUIDITY_SWEPT = 1
  };

struct LiquidityLevel
  {
   LiquidityPoolType type;
   string name;
   double price;
   datetime formed_at;
   LiquidityPoolState state;
  };

struct SweepEvent
  {
   bool valid;
   Direction direction;
   ulong level_mask;
   int level_count;
   double ash_price;
   double asl_price;
   double pnyh_price;
   double pnyl_price;
   double pdh_price;
   double pdl_price;
   double pre_ny_h_price;
   double pre_ny_l_price;
   datetime occurred_at;
   double extreme;
   double high;
   double low;
   double close;
   bool confirmed_m15;
   bool confirmed_m5;
  };

struct Zone
  {
   bool valid;
   ZoneType type;
   Direction direction;
   double bottom;
   double top;
   double refined_bottom;
   double refined_top;
   datetime created_at;
   datetime expires_at;
   ZoneState state;
   bool associated_fvg;
   int mitigations;
  };

struct SetupContext
  {
   SetupState state;
   BiasResult bias;
   SweepEvent sweep;
   double reaction_extreme;
   datetime sweep_confirmed_at;
   string m5_fib_position;
   double entry_zone_low;
   double entry_zone_high;
   datetime entry_armed_at;
   Zone candidate;
   int candidate_base_score;
   ulong pending_ticket;
   datetime pending_expiry;
   double planned_entry;
   double initial_stop;
   double target;
   double initial_risk_price;
   int setup_score;
  };

struct NewsEvent
  {
   datetime time;
   int impact; // 3=critical, 2=high, 1=medium, 0=low
   string name;
  };

CTrade g_trade;
SetupContext g_setup;
NewsEvent g_news[];
bool g_news_available=false;
datetime g_last_m1_open=0;
datetime g_last_m5_open=0;
datetime g_last_m15_open=0;
double g_initial_balance=0.0;
double g_peak_equity=0.0;
double g_daily_start_balance=0.0;
int g_daily_key=-1;
int g_trades_today=0;
int g_consecutive_losses=0;
int g_liquidity_day_key=-1;
ulong g_swept_pool_mask=0;
datetime g_loss_pause_until=0;
int g_position_stage=0;
double g_position_initial_volume=0.0;
double g_position_initial_entry=0.0;
double g_position_initial_stop=0.0;
double g_position_mae=0.0;
double g_position_mfe=0.0;

string g_diag_keys[];
long g_diag_values[];

void Diag(const string key,const long amount=1)
  {
   for(int i=0;i<ArraySize(g_diag_keys);i++)
     {
      if(g_diag_keys[i]==key)
        {
         g_diag_values[i]+=amount;
         return;
        }
     }
   int n=ArraySize(g_diag_keys);
   ArrayResize(g_diag_keys,n+1);
   ArrayResize(g_diag_values,n+1);
   g_diag_keys[n]=key;
   g_diag_values[n]=amount;
  }

string DirectionName(const Direction direction)
  {
   if(direction==DIR_LONG) return "LONG";
   if(direction==DIR_SHORT) return "SHORT";
   return "NONE";
  }

void ResetSetup(const string reason)
  {
   if(g_setup.state!=SETUP_IDLE && g_setup.state!=SETUP_IN_POSITION)
      Diag("reset:"+reason);
   ZeroMemory(g_setup);
   g_setup.state=SETUP_IDLE;
   g_setup.candidate_base_score=-100000;
  }

int DaysInMonth(const int year,const int month)
  {
   if(month==2)
      return ((year%4==0 && year%100!=0) || year%400==0) ? 29 : 28;
   if(month==4 || month==6 || month==9 || month==11) return 30;
   return 31;
  }

datetime MakeTime(const int year,const int month,const int day,const int hour=0,const int minute=0,const int second=0)
  {
   MqlDateTime value;
   ZeroMemory(value);
   value.year=year;
   value.mon=month;
   value.day=day;
   value.hour=hour;
   value.min=minute;
   value.sec=second;
   return StructToTime(value);
  }

int DayOfWeek(const int year,const int month,const int day)
  {
   MqlDateTime value;
   TimeToStruct(MakeTime(year,month,day),value);
   return value.day_of_week; // 0=domenica
  }

int NthSunday(const int year,const int month,const int nth)
  {
   int first_dow=DayOfWeek(year,month,1);
   int first_sunday=1+((7-first_dow)%7);
   return first_sunday+7*(nth-1);
  }

int LastSunday(const int year,const int month)
  {
   int last=DaysInMonth(year,month);
   return last-DayOfWeek(year,month,last);
  }

// Offset del server TenTrade: Europe/Athens. Il calcolo usa le regole
// calendariali DST, non un orario UTC fisso.
int AthensOffsetForUtc(const datetime utc_time)
  {
   MqlDateTime u;
   TimeToStruct(utc_time,u);
   datetime start=MakeTime(u.year,3,LastSunday(u.year,3),1,0,0);
   datetime end=MakeTime(u.year,10,LastSunday(u.year,10),1,0,0);
   return (utc_time>=start && utc_time<end) ? 3*3600 : 2*3600;
  }

bool NewYorkDstOnDate(const int year,const int month,const int day)
  {
   int start_day=NthSunday(year,3,2);
   int end_day=NthSunday(year,11,1);
   if(month<3 || month>11) return false;
   if(month>3 && month<11) return true;
   if(month==3) return day>=start_day;
   return day<end_day;
  }

int NewYorkUtcOffsetOnDate(const int year,const int month,const int day)
  {
   return NewYorkDstOnDate(year,month,day) ? -4*3600 : -5*3600;
  }

datetime ServerToUtc(const datetime server_time)
  {
   // Due tentativi risolvono il fatto che l'offset dipende dall'UTC cercato.
   datetime guess=server_time-2*3600;
   return server_time-AthensOffsetForUtc(guess);
  }

datetime UtcToServer(const datetime utc_time)
  {
   return utc_time+AthensOffsetForUtc(utc_time);
  }

datetime NyLocalToUtc(const int year,const int month,const int day,const int hour,const int minute)
  {
   datetime wall=MakeTime(year,month,day,hour,minute,0);
   return wall-NewYorkUtcOffsetOnDate(year,month,day);
  }

void NewYorkDateFromServer(const datetime server_time,int &year,int &month,int &day,int &hour,int &minute)
  {
   datetime utc_time=ServerToUtc(server_time);
   MqlDateTime u;
   TimeToStruct(utc_time,u);
   datetime ny_time=utc_time+NewYorkUtcOffsetOnDate(u.year,u.mon,u.day);
   MqlDateTime n;
   TimeToStruct(ny_time,n);
   year=n.year;
   month=n.mon;
   day=n.day;
   hour=n.hour;
   minute=n.min;
  }

datetime NyOpenServer(const datetime server_time)
  {
   int y,m,d,h,mi;
   NewYorkDateFromServer(server_time,y,m,d,h,mi);
   return UtcToServer(NyLocalToUtc(y,m,d,9,30));
  }

datetime NyCloseServerForDate(const int year,const int month,const int day)
  {
   return UtcToServer(NyLocalToUtc(year,month,day,17,0));
  }

bool InTradingWindow(const datetime at)
  {
   datetime opening=NyOpenServer(at);
   return at>=opening-60*60 && at<=opening+60*60;
  }

datetime SetupDeadline(const datetime at)
  {
   return NyOpenServer(at)+120*60;
  }

bool MustForceClose(const datetime at)
  {
   int y,m,d,h,mi;
   NewYorkDateFromServer(at,y,m,d,h,mi);
   int dow=DayOfWeek(y,m,d);
   if(dow==5 && (h>15 || (h==15 && mi>=0))) return true;
   return h>16 || (h==16 && mi>=45);
  }

bool RunSelfTests()
  {
   bool ok=true;
   // 15 gennaio 2026: NY 09:30 = 14:30 UTC = 16:30 server Atene.
   datetime winter=UtcToServer(NyLocalToUtc(2026,1,15,9,30));
   MqlDateTime w;
   TimeToStruct(winter,w);
   if(w.hour!=16 || w.min!=30) ok=false;
   // 15 luglio 2026: NY 09:30 = 13:30 UTC = 16:30 server Atene.
   datetime summer=UtcToServer(NyLocalToUtc(2026,7,15,9,30));
   MqlDateTime s;
   TimeToStruct(summer,s);
   if(s.hour!=16 || s.min!=30) ok=false;
   // Disallineamento USA/UE del 16 marzo: server ancora UTC+2, apertura 15:30.
   datetime mismatch=UtcToServer(NyLocalToUtc(2026,3,16,9,30));
   MqlDateTime x;
   TimeToStruct(mismatch,x);
   if(x.hour!=15 || x.min!=30) ok=false;
   if(InpMinBreakATR<=0.0 || InpKH4<1 || InpKH1<1 || InpKM15<1 || InpKM5<1 || InpKM1<1)
      ok=false;
   PrintFormat("XAU_SELF_TEST|status=%s|winter=%s|summer=%s|mismatch=%s",
               ok ? "PASS" : "FAIL",
               TimeToString(winter,TIME_DATE|TIME_MINUTES),
               TimeToString(summer,TIME_DATE|TIME_MINUTES),
               TimeToString(mismatch,TIME_DATE|TIME_MINUTES));
   return ok;
  }

int LoadClosedRates(const ENUM_TIMEFRAMES timeframe,const datetime at,const int wanted,MqlRates &rates[])
  {
   int seconds=PeriodSeconds(timeframe);
   datetime from=at-(datetime)((long)wanted*seconds*3+30L*24*3600);
   MqlRates raw[];
   ArraySetAsSeries(raw,false);
   int copied=CopyRates(_Symbol,timeframe,from,at,raw);
   if(copied<=0) return 0;
   int count=0;
   ArrayResize(rates,copied);
   for(int i=0;i<copied;i++)
     {
      if(raw[i].time+seconds<=at)
        {
         rates[count]=raw[i];
         count++;
        }
     }
   if(count>wanted)
     {
      int offset=count-wanted;
      for(int i=0;i<wanted;i++) rates[i]=rates[i+offset];
      count=wanted;
     }
   ArrayResize(rates,count);
   return count;
  }

void CalculateAtrAndQuality(const MqlRates &rates[],double &atr[],bool &quality[])
  {
   int n=ArraySize(rates);
   ArrayResize(atr,n);
   ArrayResize(quality,n);
   double alpha=1.0/14.0;
   int suspend_until=-1;
   for(int i=0;i<n;i++)
     {
      double tr=rates[i].high-rates[i].low;
      if(i>0)
        {
         tr=MathMax(tr,MathAbs(rates[i].high-rates[i-1].close));
         tr=MathMax(tr,MathAbs(rates[i].low-rates[i-1].close));
        }
      atr[i]=(i==0) ? tr : alpha*tr+(1.0-alpha)*atr[i-1];
      bool bad=(rates[i].tick_volume<=0);
      if(i>0 && atr[i-1]>0.0 && MathAbs(rates[i].open-rates[i-1].close)>InpMaxGapATR*atr[i-1])
         bad=true;
      if(bad) suspend_until=MathMax(suspend_until,i+InpGapSuspendBars);
      quality[i]=(i>=13 && i>suspend_until);
     }
  }

void CalculateEma(const MqlRates &rates[],const int period,double &values[])
  {
   int n=ArraySize(rates);
   ArrayResize(values,n);
   if(n==0) return;
   double alpha=2.0/(period+1.0);
   values[0]=rates[0].close;
   for(int i=1;i<n;i++) values[i]=alpha*rates[i].close+(1.0-alpha)*values[i-1];
  }

bool NearDuplicateSwing(const SwingPoint &swings[],const SwingKind kind,const double price,const double atr)
  {
   for(int i=ArraySize(swings)-1;i>=0;i--)
     {
      if(swings[i].kind!=kind) continue;
      return MathAbs(swings[i].price-price)<=atr*0.1;
     }
   return false;
  }

int DetectSwings(const MqlRates &rates[],const double &atr[],const int k,SwingPoint &swings[])
  {
   ArrayResize(swings,0);
   int n=ArraySize(rates);
   int seconds=(n>=2) ? (int)(rates[1].time-rates[0].time) : 60;
   for(int i=k;i<n-k;i++)
     {
      if(i<13 || !MathIsValidNumber(atr[i])) continue;
      bool high_ok=true;
      bool low_ok=true;
      for(int j=i-k;j<i;j++) // lato sinistro = più vecchio: confronto stretto
        {
         if(rates[i].high<=rates[j].high) high_ok=false;
         if(rates[i].low>=rates[j].low) low_ok=false;
        }
      for(int j=i+1;j<=i+k;j++) // lato destro = più recente: uguali ammessi
        {
         if(rates[i].high<rates[j].high) high_ok=false;
         if(rates[i].low>rates[j].low) low_ok=false;
        }
      if(high_ok && !NearDuplicateSwing(swings,SWING_HIGH,rates[i].high,atr[i]))
        {
         int p=ArraySize(swings);
         ArrayResize(swings,p+1);
         swings[p].kind=SWING_HIGH;
         swings[p].price=rates[i].high;
         swings[p].occurred_at=rates[i].time;
         swings[p].confirmed_at=rates[i+k].time+seconds;
         swings[p].rate_index=i;
         swings[p].atr=atr[i];
        }
      if(low_ok && !NearDuplicateSwing(swings,SWING_LOW,rates[i].low,atr[i]))
        {
         int p=ArraySize(swings);
         ArrayResize(swings,p+1);
         swings[p].kind=SWING_LOW;
         swings[p].price=rates[i].low;
         swings[p].occurred_at=rates[i].time;
         swings[p].confirmed_at=rates[i+k].time+seconds;
         swings[p].rate_index=i;
         swings[p].atr=atr[i];
        }
     }
   return ArraySize(swings);
  }

Trend TrendFromAvailable(const SwingPoint &swings[],const int available_count)
  {
   double last_high=0.0,prev_high=0.0,last_low=0.0,prev_low=0.0;
   int highs=0,lows=0;
   for(int i=0;i<available_count;i++)
     {
      if(swings[i].kind==SWING_HIGH)
        {
         prev_high=last_high;
         last_high=swings[i].price;
         highs++;
        }
      else
        {
         prev_low=last_low;
         last_low=swings[i].price;
         lows++;
        }
     }
   if(highs<2 || lows<2) return TREND_RANGING;
   if(last_high>prev_high && last_low>prev_low) return TREND_BULLISH;
   if(last_high<prev_high && last_low<prev_low) return TREND_BEARISH;
   return TREND_RANGING;
  }

bool BrokenContains(const int &kinds[],const int &ids[],const int kind,const int id)
  {
   for(int i=0;i<ArraySize(ids);i++)
      if(kinds[i]==kind && ids[i]==id) return true;
   return false;
  }

void MarkBroken(int &kinds[],int &ids[],const int kind,const int id)
  {
   int n=ArraySize(ids);
   ArrayResize(kinds,n+1);
   ArrayResize(ids,n+1);
   kinds[n]=kind;
   ids[n]=id;
  }

void EmptySnapshot(StructureSnapshot &snapshot)
  {
   ZeroMemory(snapshot);
   snapshot.trend=TREND_RANGING;
  }

bool BuildStructure(const ENUM_TIMEFRAMES timeframe,const int k,const datetime at,const int wanted,
                    StructureSnapshot &snapshot,StructureEvent &events[],SwingPoint &all_swings[])
  {
   EmptySnapshot(snapshot);
   ArrayResize(events,0);
   ArrayResize(all_swings,0);
   MqlRates rates[];
   int n=LoadClosedRates(timeframe,at,wanted,rates);
   if(n<2*k+20) return false;
   double atr[];
   bool quality[];
   CalculateAtrAndQuality(rates,atr,quality);
   DetectSwings(rates,atr,k,all_swings);
   int swing_cursor=0;
   int available=0;
   int broken_kinds[],broken_ids[];
   int seconds=PeriodSeconds(timeframe);
   for(int i=0;i<n;i++)
     {
      datetime bar_close=rates[i].time+seconds;
      while(swing_cursor<ArraySize(all_swings) && all_swings[swing_cursor].confirmed_at<=bar_close)
        {
         available++;
         swing_cursor++;
        }
      int last_high_index=-1,last_low_index=-1;
      for(int s=available-1;s>=0 && (last_high_index<0 || last_low_index<0);s--)
        {
         if(last_high_index<0 && all_swings[s].kind==SWING_HIGH) last_high_index=s;
         if(last_low_index<0 && all_swings[s].kind==SWING_LOW) last_low_index=s;
        }
      if(last_high_index<0 || last_low_index<0 || !quality[i]) continue;
      Trend current=TrendFromAvailable(all_swings,available);
      double threshold=InpMinBreakATR*atr[i];
      SwingPoint hs=all_swings[last_high_index];
      SwingPoint ls=all_swings[last_low_index];
      if(!BrokenContains(broken_kinds,broken_ids,(int)SWING_HIGH,hs.rate_index) &&
         rates[i].close>hs.price+threshold)
        {
         StructureEventKind kind=EVENT_NONE;
         if(current==TREND_BULLISH) kind=EVENT_BOS;
         else if(current==TREND_BEARISH) kind=EVENT_CHOCH;
         if(kind!=EVENT_NONE)
           {
            int e=ArraySize(events);
            ArrayResize(events,e+1);
            events[e].kind=kind;
            events[e].direction=DIR_LONG;
            events[e].occurred_at=bar_close;
            events[e].level=hs.price;
            events[e].close_price=rates[i].close;
            events[e].swing_rate_index=hs.rate_index;
           }
         MarkBroken(broken_kinds,broken_ids,(int)SWING_HIGH,hs.rate_index);
        }
      if(!BrokenContains(broken_kinds,broken_ids,(int)SWING_LOW,ls.rate_index) &&
         rates[i].close<ls.price-threshold)
        {
         StructureEventKind kind=EVENT_NONE;
         if(current==TREND_BEARISH) kind=EVENT_BOS;
         else if(current==TREND_BULLISH) kind=EVENT_CHOCH;
         if(kind!=EVENT_NONE)
           {
            int e=ArraySize(events);
            ArrayResize(events,e+1);
            events[e].kind=kind;
            events[e].direction=DIR_SHORT;
            events[e].occurred_at=bar_close;
            events[e].level=ls.price;
            events[e].close_price=rates[i].close;
            events[e].swing_rate_index=ls.rate_index;
           }
         MarkBroken(broken_kinds,broken_ids,(int)SWING_LOW,ls.rate_index);
        }
     }

   int confirmed=0;
   for(int i=0;i<ArraySize(all_swings);i++)
      if(all_swings[i].confirmed_at<=at) confirmed++;
   snapshot.trend=TrendFromAvailable(all_swings,confirmed);
   for(int i=confirmed-1;i>=0;i--)
     {
      if(!snapshot.has_last_high && all_swings[i].kind==SWING_HIGH)
        {
         snapshot.last_high=all_swings[i];
         snapshot.has_last_high=true;
        }
      else if(snapshot.has_last_high && !snapshot.has_prev_high && all_swings[i].kind==SWING_HIGH)
        {
         snapshot.prev_high=all_swings[i];
         snapshot.has_prev_high=true;
        }
      if(!snapshot.has_last_low && all_swings[i].kind==SWING_LOW)
        {
         snapshot.last_low=all_swings[i];
         snapshot.has_last_low=true;
        }
      else if(snapshot.has_last_low && !snapshot.has_prev_low && all_swings[i].kind==SWING_LOW)
        {
         snapshot.prev_low=all_swings[i];
         snapshot.has_prev_low=true;
        }
     }
   for(int i=ArraySize(events)-1;i>=0;i--)
     {
      if(events[i].occurred_at<=at)
        {
         snapshot.latest_event=events[i];
         snapshot.has_latest_event=true;
         break;
        }
     }
   return true;
  }

bool HasRecentEvent(const StructureEvent &events[],const datetime at,const int bars,const ENUM_TIMEFRAMES timeframe,
                    const StructureEventKind kind,const Direction direction)
  {
   datetime start=at-(datetime)((long)bars*PeriodSeconds(timeframe));
   for(int i=ArraySize(events)-1;i>=0;i--)
     {
      if(events[i].occurred_at>at) continue;
      if(events[i].occurred_at<start) break;
      if(events[i].kind==kind && events[i].direction==direction) return true;
     }
   return false;
  }

bool EventAt(const StructureEvent &events[],const datetime at,const StructureEventKind kind,const Direction direction)
  {
   for(int i=ArraySize(events)-1;i>=0;i--)
     {
      if(events[i].occurred_at<at) break;
      if(events[i].occurred_at==at && events[i].kind==kind && events[i].direction==direction)
         return true;
     }
   return false;
  }

void EmptyBias(BiasResult &result,const datetime at,const string reason)
  {
   ZeroMemory(result);
   result.direction=DIR_NONE;
   result.evaluated_at=at;
   result.reason=reason;
  }

bool EvaluateBias(const datetime at,BiasResult &result)
  {
   EmptyBias(result,at,"indicator_unavailable");
   MqlRates rates[];
   int requested=InpUseEmaMacro ? MathMax(750,InpEmaMacro*3+100) : 650;
   int n=LoadClosedRates(PERIOD_H4,at,requested,rates);
   int warmup=(InpUseEmaMacro ? InpEmaMacro : InpEmaSlow)*3;
   if(n<warmup || n<=InpEmaSlopeLookback)
     {
      result.reason="ema_warmup";
      return false;
     }
   double atr[];
   bool quality[];
   double fast[],slow[],macro[];
   CalculateAtrAndQuality(rates,atr,quality);
   CalculateEma(rates,InpEmaFast,fast);
   CalculateEma(rates,InpEmaSlow,slow);
   CalculateEma(rates,InpEmaMacro,macro);
   int i=n-1;
   result.evaluated_at=rates[i].time+PeriodSeconds(PERIOD_H4);
   result.ema_fast=fast[i];
   result.ema_slow=slow[i];
   result.ema_macro=macro[i];
   if(!quality[i] || atr[i]<=0.0)
     {
      result.reason="data_quality";
      return false;
     }
   result.slope=(slow[i]-slow[i-InpEmaSlopeLookback])/(atr[i]*InpEmaSlopeLookback);
   double close=rates[i].close;
   if(InpH4BiasMode==H4_EMA_AND_STRUCTURE)
     {
      if(close>fast[i] && fast[i]>slow[i] && result.slope>InpMinEmaSlope)
         result.direction=DIR_LONG;
      else if(close<fast[i] && fast[i]<slow[i] && result.slope<-InpMinEmaSlope)
         result.direction=DIR_SHORT;
      else
        {
         result.direction=DIR_NONE;
         result.reason="ema_alignment";
         return false;
        }
     }
   if(InpH4BiasMode==H4_EMA_AND_STRUCTURE && InpUseEmaMacro &&
      ((result.direction==DIR_LONG && close<=macro[i]) ||
       (result.direction==DIR_SHORT && close>=macro[i])))
     {
      result.direction=DIR_NONE;
      result.reason="ema_macro";
      return false;
     }

   StructureSnapshot structure;
   StructureEvent events[];
   SwingPoint swings[];
   if(!BuildStructure(PERIOD_H4,InpKH4,result.evaluated_at,900,structure,events,swings))
     {
      result.direction=DIR_NONE;
      result.reason="h4_structure_unavailable";
      return false;
     }
   if(structure.trend==TREND_RANGING)
     {
      result.direction=DIR_NONE;
      result.reason="h4_ranging";
      return false;
     }
   if(InpH4BiasMode==H4_STRUCTURE_ONLY)
      result.direction=(structure.trend==TREND_BULLISH ? DIR_LONG : DIR_SHORT);
   else if((result.direction==DIR_LONG && structure.trend!=TREND_BULLISH) ||
           (result.direction==DIR_SHORT && structure.trend!=TREND_BEARISH))
     {
      result.direction=DIR_NONE;
      result.reason="h4_structure_opposed";
      return false;
     }
   Direction contrary=(result.direction==DIR_LONG ? DIR_SHORT : DIR_LONG);
   if(HasRecentEvent(events,result.evaluated_at,3,PERIOD_H4,EVENT_CHOCH,contrary))
     {
      result.direction=DIR_NONE;
      result.reason="h4_choch_veto";
      return false;
     }

   result.reason="ok";
   return true;
  }

bool H1Confirms(const datetime at,const Direction direction,const double price,string &reason)
  {
   StructureSnapshot snapshot;
   StructureEvent events[];
   SwingPoint swings[];
   if(!BuildStructure(PERIOD_H1,InpKH1,at,1400,snapshot,events,swings))
     {
      reason="h1_warmup";
      return false;
     }
   if((direction==DIR_LONG && snapshot.trend!=TREND_BULLISH) ||
      (direction==DIR_SHORT && snapshot.trend!=TREND_BEARISH))
     {
      reason="h1_trend";
      return false;
     }
   if(InpH1ConfirmMode==H1_STRICT_BOS &&
      (!snapshot.has_latest_event || snapshot.latest_event.kind!=EVENT_BOS ||
       snapshot.latest_event.direction!=direction))
     {
      reason="h1_last_event";
      return false;
     }
   Direction contrary=(direction==DIR_LONG ? DIR_SHORT : DIR_LONG);
   if(HasRecentEvent(events,at,5,PERIOD_H1,EVENT_CHOCH,contrary))
     {
      reason="h1_choch";
      return false;
     }
   if(direction==DIR_LONG && snapshot.has_last_low && price<snapshot.last_low.price)
     {
      reason="h1_swing_violation";
      return false;
     }
   if(direction==DIR_SHORT && snapshot.has_last_high && price>snapshot.last_high.price)
     {
      reason="h1_swing_violation";
      return false;
     }
   if(InpUseEmaH1)
     {
      MqlRates rates[];
      int n=LoadClosedRates(PERIOD_H1,at,MathMax(200,InpEmaFast*3+50),rates);
      if(n<InpEmaFast*3)
        {
         reason="h1_ema_warmup";
         return false;
        }
      double ema[];
      CalculateEma(rates,InpEmaFast,ema);
      if((direction==DIR_LONG && rates[n-1].close<=ema[n-1]) ||
         (direction==DIR_SHORT && rates[n-1].close>=ema[n-1]))
        {
         reason="h1_ema";
         return false;
        }
     }
   reason="ok";
   return true;
  }

bool RangeHighLow(const datetime from,const datetime to,double &high,double &low)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,PERIOD_M1,from,to,rates);
   high=-DBL_MAX;
   low=DBL_MAX;
   int used=0;
   for(int i=0;i<copied;i++)
     {
      if(rates[i].time<from || rates[i].time>=to || rates[i].tick_volume<=0) continue;
      high=MathMax(high,rates[i].high);
      low=MathMin(low,rates[i].low);
      used++;
     }
   return used>0 && high>low;
  }

ulong PoolBit(const LiquidityPoolType type)
  {
   return ((ulong)1<<(int)type);
  }

string PoolName(const LiquidityPoolType type)
  {
   if(type==POOL_ASH) return "ASH";
   if(type==POOL_ASL) return "ASL";
   if(type==POOL_PNYH) return "PNYH";
   if(type==POOL_PNYL) return "PNYL";
   if(type==POOL_PDH) return "PDH";
   if(type==POOL_PDL) return "PDL";
   if(type==POOL_PRE_NY_H) return "PRE_NY_H";
   return "PRE_NY_L";
  }

bool IsLowPool(const LiquidityPoolType type)
  {
   return type==POOL_ASL || type==POOL_PNYL || type==POOL_PDL || type==POOL_PRE_NY_L;
  }

bool IsHighPool(const LiquidityPoolType type)
  {
   return type==POOL_ASH || type==POOL_PNYH || type==POOL_PDH || type==POOL_PRE_NY_H;
  }

void SyncLiquidityDay(const datetime at)
  {
   int y,m,d,h,mi;
   NewYorkDateFromServer(at,y,m,d,h,mi);
   int key=y*10000+m*100+d;
   if(key==g_liquidity_day_key) return;
   g_liquidity_day_key=key;
   g_swept_pool_mask=0;
  }

void AppendLiquidityLevel(LiquidityLevel &levels[],const LiquidityPoolType type,
                          const double price,const datetime formed_at)
  {
   int n=ArraySize(levels);
   ArrayResize(levels,n+1);
   levels[n].type=type;
   levels[n].name=PoolName(type);
   levels[n].price=price;
   levels[n].formed_at=formed_at;
   levels[n].state=((g_swept_pool_mask&PoolBit(type))!=0 ? LIQUIDITY_SWEPT : LIQUIDITY_INTACT);
  }

void SetSweepPool(SweepEvent &event,const LiquidityPoolType type,const double price)
  {
   ulong bit=PoolBit(type);
   if((event.level_mask&bit)!=0) return;
   event.level_mask|=bit;
   event.level_count++;
   if(type==POOL_ASH) event.ash_price=price;
   else if(type==POOL_ASL) event.asl_price=price;
   else if(type==POOL_PNYH) event.pnyh_price=price;
   else if(type==POOL_PNYL) event.pnyl_price=price;
   else if(type==POOL_PDH) event.pdh_price=price;
   else if(type==POOL_PDL) event.pdl_price=price;
   else if(type==POOL_PRE_NY_H) event.pre_ny_h_price=price;
   else event.pre_ny_l_price=price;
  }

double SweepPoolPrice(const SweepEvent &event,const LiquidityPoolType type)
  {
   if(type==POOL_ASH) return event.ash_price;
   if(type==POOL_ASL) return event.asl_price;
   if(type==POOL_PNYH) return event.pnyh_price;
   if(type==POOL_PNYL) return event.pnyl_price;
   if(type==POOL_PDH) return event.pdh_price;
   if(type==POOL_PDL) return event.pdl_price;
   if(type==POOL_PRE_NY_H) return event.pre_ny_h_price;
   return event.pre_ny_l_price;
  }

string SweepLevelNames(const SweepEvent &event)
  {
   string result="[";
   bool first=true;
   for(int i=0;i<8;i++)
     {
      LiquidityPoolType type=(LiquidityPoolType)i;
      if((event.level_mask&PoolBit(type))==0) continue;
      if(!first) result+=",";
      result+=PoolName(type);
      first=false;
     }
   return result+"]";
  }

string SweepLevelPrices(const SweepEvent &event)
  {
   string result="[";
   bool first=true;
   for(int i=0;i<8;i++)
     {
      LiquidityPoolType type=(LiquidityPoolType)i;
      if((event.level_mask&PoolBit(type))==0) continue;
      if(!first) result+=",";
      result+=DoubleToString(SweepPoolPrice(event,type),2);
      first=false;
     }
   return result+"]";
  }

int GetLiquidityLevels(const datetime at,const datetime pre_ny_as_of,LiquidityLevel &levels[])
  {
   ArrayResize(levels,0);
   SyncLiquidityDay(at);
   int y,m,d,h,mi;
   NewYorkDateFromServer(at,y,m,d,h,mi);
   datetime date_wall=MakeTime(y,m,d);

   // Asian Session dello stesso giorno: 00:00-08:00 UTC, definitiva alle 08:00.
   datetime utc_midnight=MakeTime(y,m,d,0,0,0);
   datetime asian_from=UtcToServer(utc_midnight);
   datetime asian_to=UtcToServer(utc_midnight+8*3600);
   double ash,asl;
   if(pre_ny_as_of>=asian_to && RangeHighLow(asian_from,asian_to,ash,asl))
     {
      AppendLiquidityLevel(levels,POOL_ASH,ash,asian_to);
      AppendLiquidityLevel(levels,POOL_ASL,asl,asian_to);
     }

   // Sessione New York del precedente giorno di trading, saltando giorni senza dati.
   for(int back=1;back<=7;back++)
     {
      MqlDateTime prior_date;
      TimeToStruct(date_wall-back*86400,prior_date);
      datetime range_from=UtcToServer(NyLocalToUtc(prior_date.year,prior_date.mon,prior_date.day,9,30));
      datetime range_to=NyCloseServerForDate(prior_date.year,prior_date.mon,prior_date.day);
      double pnyh,pnyl;
      if(!RangeHighLow(range_from,range_to,pnyh,pnyl)) continue;
      AppendLiquidityLevel(levels,POOL_PNYH,pnyh,range_to);
      AppendLiquidityLevel(levels,POOL_PNYL,pnyl,range_to);
      break;
     }

   // Previous Day 17:00->17:00 New York, saltando weekend e giorni senza dati.
   for(int back=1;back<=7;back++)
     {
      MqlDateTime end_date,start_date;
      TimeToStruct(date_wall-back*86400,end_date);
      TimeToStruct(date_wall-(back+1)*86400,start_date);
      datetime range_from=NyCloseServerForDate(start_date.year,start_date.mon,start_date.day);
      datetime range_to=NyCloseServerForDate(end_date.year,end_date.mon,end_date.day);
      double pdh,pdl;
      if(!RangeHighLow(range_from,range_to,pdh,pdl)) continue;
      AppendLiquidityLevel(levels,POOL_PDH,pdh,range_to);
      AppendLiquidityLevel(levels,POOL_PDL,pdl,range_to);
      break;
     }

   datetime pre_from=UtcToServer(utc_midnight);
   datetime opening=NyOpenServer(at);
   datetime cutoff=MathMin(pre_ny_as_of,opening);
   double pre_high,pre_low;
   if(cutoff>pre_from && RangeHighLow(pre_from,cutoff,pre_high,pre_low))
     {
      AppendLiquidityLevel(levels,POOL_PRE_NY_H,pre_high,cutoff);
      AppendLiquidityLevel(levels,POOL_PRE_NY_L,pre_low,cutoff);
     }
   return ArraySize(levels);
  }

int ParseImpact(string value)
  {
   StringToUpper(value);
   if(value=="CRITICAL" || value=="3") return 3;
   if(value=="HIGH" || value=="2") return 2;
   if(value=="MEDIUM" || value=="1") return 1;
   return 0;
  }

bool LoadNewsCalendar()
  {
   ArrayResize(g_news,0);
   if(!FileIsExist(InpNewsFile,FILE_COMMON))
     {
      PrintFormat("XAU_NEWS|status=MISSING|file=%s|tester=%s",InpNewsFile,
                  MQLInfoInteger(MQL_TESTER) ? "true" : "false");
      return false;
     }
   int handle=FileOpen(InpNewsFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("XAU_NEWS|status=OPEN_FAILED|error=%d",GetLastError());
      return false;
     }
   bool first=true;
   while(!FileIsEnding(handle))
     {
      string raw_time=FileReadString(handle);
      string impact=FileReadString(handle);
      string name=FileReadString(handle);
      if(first)
        {
         first=false;
         string header=raw_time;
         StringToLower(header);
         if(StringFind(header,"time")>=0) continue;
        }
      datetime event_time=StringToTime(raw_time);
      if(event_time<=0) continue;
      int n=ArraySize(g_news);
      ArrayResize(g_news,n+1);
      g_news[n].time=event_time;
      g_news[n].impact=ParseImpact(impact);
      g_news[n].name=name;
     }
   FileClose(handle);
   PrintFormat("XAU_NEWS|status=LOADED|events=%d|file=%s",ArraySize(g_news),InpNewsFile);
   return ArraySize(g_news)>0;
  }

bool IsNewsBlackout(const datetime at)
  {
   if(!g_news_available) return InpRequireNewsCalendar;
   for(int i=0;i<ArraySize(g_news);i++)
     {
      int before=0,after=0;
      if(g_news[i].impact>=3) { before=60*60; after=60*60; }
      else if(g_news[i].impact==2) { before=30*60; after=30*60; }
      else if(g_news[i].impact==1) { before=15*60; after=15*60; }
      if(at>=g_news[i].time-before && at<=g_news[i].time+after) return true;
     }
   return false;
  }

string NewsForceCloseReason(const datetime at)
  {
   if(!g_news_available) return "";
   for(int i=0;i<ArraySize(g_news);i++)
     {
      if(g_news[i].impact>=3 && at>=g_news[i].time-15*60 && at<g_news[i].time)
         return "NEWS_CRITICAL";
      if(g_news[i].impact==2 && at>=g_news[i].time-10*60 && at<g_news[i].time)
         return "NEWS_HIGH";
     }
   return "";
  }

bool FvgFromTriplet(const MqlRates &rates[],const double &atr[],const int right_index,
                    const double min_fvg_atr,const ENUM_TIMEFRAMES timeframe,Zone &zone)
  {
   ZeroMemory(zone);
   if(right_index<2) return false;
   int left=right_index-2;
   int center=right_index-1;
   int seconds=PeriodSeconds(timeframe);
   if(rates[left].high<rates[right_index].low &&
      rates[right_index].low-rates[left].high>=min_fvg_atr*atr[center])
     {
      zone.valid=true;
      zone.type=ZONE_FVG;
      zone.direction=DIR_LONG;
      zone.bottom=rates[left].high;
      zone.top=rates[right_index].low;
      zone.created_at=rates[right_index].time+seconds;
      zone.state=ZONE_FRESH;
      return true;
     }
   if(rates[left].low>rates[right_index].high &&
      rates[left].low-rates[right_index].high>=min_fvg_atr*atr[center])
     {
      zone.valid=true;
      zone.type=ZONE_FVG;
      zone.direction=DIR_SHORT;
      zone.bottom=rates[right_index].high;
      zone.top=rates[left].low;
      zone.created_at=rates[right_index].time+seconds;
      zone.state=ZONE_FRESH;
      return true;
     }
   return false;
  }

int DetectFvgs(const ENUM_TIMEFRAMES timeframe,const datetime at,const int wanted,const double min_fvg_atr,
               Zone &zones[],MqlRates &rates_out[],double &atr_out[])
  {
   ArrayResize(zones,0);
   int n=LoadClosedRates(timeframe,at,wanted,rates_out);
   bool quality[];
   CalculateAtrAndQuality(rates_out,atr_out,quality);
   for(int i=2;i<n;i++)
     {
      Zone zone;
      if(!FvgFromTriplet(rates_out,atr_out,i,min_fvg_atr,timeframe,zone)) continue;
      int z=ArraySize(zones);
      ArrayResize(zones,z+1);
      zones[z]=zone;
     }
   return ArraySize(zones);
  }

void AppendZone(Zone &zones[],const Zone &zone)
  {
   int n=ArraySize(zones);
   ArrayResize(zones,n+1);
   zones[n]=zone;
  }

int ZonesCreatedAt(const ENUM_TIMEFRAMES timeframe,const datetime at,const double min_fvg_atr,
                   const int ifvg_max_age,Zone &created[])
  {
   ArrayResize(created,0);
   Zone fvgs[];
   MqlRates rates[];
   double atr[];
   int wanted=MathMax(100,ifvg_max_age+20);
   DetectFvgs(timeframe,at,wanted,min_fvg_atr,fvgs,rates,atr);
   int n=ArraySize(rates);
   int seconds=PeriodSeconds(timeframe);
   for(int i=0;i<ArraySize(fvgs);i++)
      if(fvgs[i].created_at==at) AppendZone(created,fvgs[i]);

   // Conversione IFVG: solo la prima chiusura completa oltre il gap, entro età.
   for(int f=0;f<ArraySize(fvgs);f++)
     {
      int created_index=-1;
      for(int i=0;i<n;i++)
         if(rates[i].time+seconds==fvgs[f].created_at) { created_index=i; break; }
      if(created_index<0) continue;
      int last=MathMin(n-1,created_index+ifvg_max_age);
      for(int i=created_index+1;i<=last;i++)
        {
         bool inverted=(fvgs[f].direction==DIR_LONG ? rates[i].close<fvgs[f].bottom
                                                    : rates[i].close>fvgs[f].top);
         if(!inverted) continue;
         datetime conversion=rates[i].time+seconds;
         if(conversion==at)
           {
            Zone zone=fvgs[f];
            zone.type=ZONE_IFVG;
            zone.direction=(fvgs[f].direction==DIR_LONG ? DIR_SHORT : DIR_LONG);
            zone.created_at=conversion;
            zone.expires_at=conversion+ifvg_max_age*seconds;
            zone.state=ZONE_FRESH;
            AppendZone(created,zone);
           }
         break;
        }
     }

   // Order Block: candela opposta seguita da due candele impulsive e FVG.
   if(n>=3)
     {
      int i=n-3;
      bool has_bull_fvg=false,has_bear_fvg=false;
      for(int f=0;f<ArraySize(fvgs);f++)
        {
         if(fvgs[f].created_at!=at) continue;
         if(fvgs[f].direction==DIR_LONG) has_bull_fvg=true;
         if(fvgs[f].direction==DIR_SHORT) has_bear_fvg=true;
        }
      bool bullish=(rates[i].close<rates[i].open &&
                    rates[i+1].close>rates[i+1].open && rates[i+2].close>rates[i+2].open &&
                    MathMax(rates[i+1].high,rates[i+2].high)-rates[i].high>=InpMinImpulseATR*atr[i] &&
                    has_bull_fvg);
      bool bearish=(rates[i].close>rates[i].open &&
                    rates[i+1].close<rates[i+1].open && rates[i+2].close<rates[i+2].open &&
                    rates[i].low-MathMin(rates[i+1].low,rates[i+2].low)>=InpMinImpulseATR*atr[i] &&
                    has_bear_fvg);
      if(bullish)
        {
         Zone zone;
         ZeroMemory(zone);
         zone.valid=true;
         zone.type=ZONE_ORDER_BLOCK;
         zone.direction=DIR_LONG;
         zone.bottom=rates[i].low;
         zone.top=rates[i].high;
         zone.refined_bottom=rates[i].low;
         zone.refined_top=rates[i].open;
         zone.created_at=at;
         zone.state=ZONE_UNMITIGATED;
         zone.associated_fvg=true;
         AppendZone(created,zone);
        }
      if(bearish)
        {
         Zone zone;
         ZeroMemory(zone);
         zone.valid=true;
         zone.type=ZONE_ORDER_BLOCK;
         zone.direction=DIR_SHORT;
         zone.bottom=rates[i].low;
         zone.top=rates[i].high;
         zone.refined_bottom=rates[i].open;
         zone.refined_top=rates[i].high;
         zone.created_at=at;
         zone.state=ZONE_UNMITIGATED;
         zone.associated_fvg=true;
         AppendZone(created,zone);
        }
     }
   return ArraySize(created);
  }

bool ZoneOverlaps(const Zone &zone,const double low,const double high)
  {
   return zone.bottom<=high && zone.top>=low;
  }

bool ZoneInvalidated(const Zone &zone,const double close)
  {
   return zone.direction==DIR_LONG ? close<zone.bottom : close>zone.top;
  }

double ZoneEntryPrice(const Zone &zone)
  {
   if(zone.type==ZONE_FVG) return (zone.bottom+zone.top)/2.0;
   if(zone.type==ZONE_IFVG) return zone.direction==DIR_LONG ? zone.top : zone.bottom;
   return zone.direction==DIR_LONG ? zone.refined_top : zone.refined_bottom;
  }

int ZoneBaseScore(const Zone &zone,const bool higher_tf_confluence)
  {
   int score=0;
   if(zone.type==ZONE_IFVG) score+=3;
   else if(zone.type==ZONE_ORDER_BLOCK && zone.associated_fvg) score+=3;
   else score+=1;
   if(higher_tf_confluence) score+=2;
   if(zone.state==ZONE_FRESH || zone.state==ZONE_UNMITIGATED) score+=2;
   return score;
  }

bool HigherTfConfluence(const Zone &candidate,const datetime at)
  {
   ENUM_TIMEFRAMES frames[2]={PERIOD_M5,PERIOD_M15};
   for(int t=0;t<2;t++)
     {
      Zone fvgs[];
      MqlRates rates[];
      double atr[];
      int wanted=(frames[t]==PERIOD_M5 ? 650 : 220);
      DetectFvgs(frames[t],at,wanted,InpMinFvgAtrM5,fvgs,rates,atr);
      for(int i=0;i<ArraySize(fvgs);i++)
        {
         if(fvgs[i].created_at<at-2*24*3600 || fvgs[i].created_at>at) continue;
         if(fvgs[i].direction==candidate.direction && ZoneOverlaps(fvgs[i],candidate.bottom,candidate.top))
            return true;
        }
     }
   return false;
  }

bool LatestClosedBar(const ENUM_TIMEFRAMES timeframe,const datetime at,MqlRates &bar,double &atr_value,bool &quality_ok)
  {
   MqlRates rates[];
   int n=LoadClosedRates(timeframe,at,120,rates);
   if(n<14) return false;
   double atr[];
   bool quality[];
   CalculateAtrAndQuality(rates,atr,quality);
   bar=rates[n-1];
   atr_value=atr[n-1];
   quality_ok=quality[n-1];
   return true;
  }

bool CandleSweepsLevel(const MqlRates &bar,const double atr,const LiquidityLevel &level,
                       const Direction direction,const double min_sweep_atr,
                       const double min_wick_ratio)
  {
   double candle_range=bar.high-bar.low;
   if(candle_range<=0.0 || atr<=0.0 || level.state==LIQUIDITY_SWEPT) return false;
   if(direction==DIR_LONG && IsLowPool(level.type))
     {
      double penetration=level.price-bar.low;
      double wick_ratio=(bar.close-bar.low)/candle_range;
      return bar.low<level.price && bar.close>level.price &&
             penetration>=min_sweep_atr*atr && wick_ratio>=min_wick_ratio;
     }
   if(direction==DIR_SHORT && IsHighPool(level.type))
     {
      double penetration=bar.high-level.price;
      double wick_ratio=(bar.high-bar.close)/candle_range;
      return bar.high>level.price && bar.close<level.price &&
             penetration>=min_sweep_atr*atr && wick_ratio>=min_wick_ratio;
     }
   return false;
  }

bool DetectSweep(const MqlRates &bar,const double atr,const datetime at,const Direction direction,SweepEvent &event)
  {
   ZeroMemory(event);
   LiquidityLevel levels[];
   GetLiquidityLevels(at,bar.time,levels);
   for(int i=0;i<ArraySize(levels);i++)
     {
      if(CandleSweepsLevel(bar,atr,levels[i],direction,InpMinSweepAtrM15,InpMinWickRatioM15))
         SetSweepPool(event,levels[i].type,levels[i].price);
     }
   event.valid=event.level_count>0;
   event.direction=direction;
   event.occurred_at=at;
   event.extreme=(direction==DIR_LONG ? bar.low : bar.high);
   event.high=bar.high;
   event.low=bar.low;
   event.close=bar.close;
   event.confirmed_m15=event.valid;
   return event.valid;
  }

bool ConfirmSweepOnM5(const SweepEvent &m15_event,SweepEvent &confirmed)
  {
   ZeroMemory(confirmed);
   MqlRates rates[];
   int n=LoadClosedRates(PERIOD_M5,m15_event.occurred_at,180,rates);
   if(n<14) return false;
   double atr[];
   bool quality[];
   CalculateAtrAndQuality(rates,atr,quality);
   datetime start=m15_event.occurred_at-15*60;
   int constituent_count=0;
   for(int i=0;i<n;i++)
      if(rates[i].time>=start && rates[i].time<m15_event.occurred_at) constituent_count++;
   if(constituent_count!=3) return false;

   confirmed.direction=m15_event.direction;
   confirmed.occurred_at=m15_event.occurred_at;
   confirmed.high=m15_event.high;
   confirmed.low=m15_event.low;
   confirmed.close=m15_event.close;
   confirmed.confirmed_m15=true;
   confirmed.extreme=(m15_event.direction==DIR_LONG ? DBL_MAX : -DBL_MAX);
   for(int p=0;p<8;p++)
     {
      LiquidityPoolType type=(LiquidityPoolType)p;
      if((m15_event.level_mask&PoolBit(type))==0) continue;
      LiquidityLevel level;
      level.type=type;
      level.name=PoolName(type);
      level.price=SweepPoolPrice(m15_event,type);
      level.formed_at=0;
      level.state=LIQUIDITY_INTACT;
      bool matches=false;
      double deepest=(m15_event.direction==DIR_LONG ? DBL_MAX : -DBL_MAX);
      for(int i=0;i<n;i++)
        {
         if(rates[i].time<start || rates[i].time>=m15_event.occurred_at || !quality[i]) continue;
         if(!CandleSweepsLevel(rates[i],atr[i],level,m15_event.direction,
                               InpMinSweepAtrM5,InpMinWickRatioM5)) continue;
         matches=true;
         if(m15_event.direction==DIR_LONG) deepest=MathMin(deepest,rates[i].low);
         else deepest=MathMax(deepest,rates[i].high);
        }
      if(!matches) continue;
      SetSweepPool(confirmed,type,level.price);
      if(m15_event.direction==DIR_LONG) confirmed.extreme=MathMin(confirmed.extreme,deepest);
      else confirmed.extreme=MathMax(confirmed.extreme,deepest);
     }
   confirmed.valid=confirmed.level_count>0;
   confirmed.confirmed_m5=confirmed.valid;
   return confirmed.valid;
  }

void MarkSweepPools(const datetime at,const SweepEvent &event)
  {
   SyncLiquidityDay(at);
   g_swept_pool_mask|=event.level_mask;
  }

void ArmEntryFromReaction(const datetime at,const double low,const double high,const string fib_position)
  {
   g_setup.state=SETUP_ENTRY_ARMED;
   g_setup.entry_zone_low=MathMin(low,high);
   g_setup.entry_zone_high=MathMax(low,high);
   g_setup.entry_armed_at=at;
   g_setup.m5_fib_position=fib_position;
   g_setup.candidate.valid=false;
   g_setup.candidate_base_score=-100000;
   Diag("m5_fib_passed");
  }

void OnM15Close(const datetime at)
  {
   if(g_setup.state!=SETUP_IDLE || PositionsTotal()>0 || OrdersTotal()>0) return;
   if(!InTradingWindow(at)) return;
   Diag("m15_bars_in_window");
   MqlRates bar;
   double atr;
   bool quality;
   if(!LatestClosedBar(PERIOD_M15,at,bar,atr,quality) || !quality)
     {
      Diag("veto:m15:data_quality");
      return;
     }
   if(IsNewsBlackout(at))
     {
      Diag("veto:news_blackout");
      return;
     }
   BiasResult bias;
   if(!EvaluateBias(at,bias))
     {
      Diag("veto:bias:"+bias.reason);
      return;
     }
   Diag("bias_active");
   string h1_reason;
   if(!H1Confirms(at,bias.direction,bar.close,h1_reason))
     {
      Diag("veto:h1:"+h1_reason);
      return;
     }
   Diag("h1_confirmed");
   SweepEvent sweep;
   if(!DetectSweep(bar,atr,at,bias.direction,sweep))
     {
      Diag("veto:no_sweep");
     return;
     }
   Diag("sweep_detected");
   for(int p=0;p<8;p++)
     {
      LiquidityPoolType type=(LiquidityPoolType)p;
      if((sweep.level_mask&PoolBit(type))!=0) Diag("sweep_m15_level:"+PoolName(type));
     }
   Diag("sweep_at:"+TimeToString(at,TIME_DATE|TIME_MINUTES));

   SweepEvent confirmed;
   if(!ConfirmSweepOnM5(sweep,confirmed))
     {
      Diag("veto:sweep_m5_unconfirmed");
      PrintFormat("XAU_SWEEP_REJECTED|time=%s|direction=%s|m15_levels=%s|reason=m5_unconfirmed",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),DirectionName(sweep.direction),
                  SweepLevelNames(sweep));
      return;
     }
   if(confirmed.level_count<sweep.level_count) Diag("sweep_m5_partial_confirmation");
   for(int p=0;p<8;p++)
     {
      LiquidityPoolType type=(LiquidityPoolType)p;
      if((confirmed.level_mask&PoolBit(type))!=0) Diag("sweep_level:"+PoolName(type));
     }
   MarkSweepPools(at,confirmed);
   Diag("sweep_confirmed_both_timeframes");

   g_setup.state=SETUP_SWEEP_CONFIRMED;
   g_setup.bias=bias;
   g_setup.sweep=confirmed;
   g_setup.reaction_extreme=bar.close;
   g_setup.sweep_confirmed_at=at;
   PrintFormat("XAU_SWEEP|time=%s|direction=%s|levels=%s|prices=%s|extreme=%.2f|confirmed_m15=true|confirmed_m5=true",
               TimeToString(at,TIME_DATE|TIME_MINUTES),DirectionName(confirmed.direction),
               SweepLevelNames(confirmed),SweepLevelPrices(confirmed),confirmed.extreme);
   if(InpM5FibMode==M5_FIB_OFF)
      ArmEntryFromReaction(at,confirmed.extreme,bar.close,"OFF");
  }

void OnM5Close(const datetime at)
  {
   if(!g_setup.sweep.valid || g_setup.bias.direction==DIR_NONE) return;
   if(at>SetupDeadline(g_setup.sweep.occurred_at))
     {
      ResetSetup("setup_deadline");
      return;
     }
   MqlRates bar;
   double atr;
   bool quality;
   if(!LatestClosedBar(PERIOD_M5,at,bar,atr,quality) || !quality) return;
   Direction direction=g_setup.bias.direction;
   if(g_setup.state!=SETUP_SWEEP_CONFIRMED) return;
   if(at<=g_setup.sweep_confirmed_at) return;
   if(at>g_setup.sweep_confirmed_at+3600)
     {
      ResetSetup("m5_fib_timeout");
      return;
     }
   double previous_extreme=g_setup.reaction_extreme;
   double current_extreme,range,fib382,fib50,fib75,fib786;
   bool beyond,strict_touch,lenient_touch,made_new_extreme;
   if(direction==DIR_LONG)
     {
      current_extreme=MathMax(previous_extreme,bar.high);
      g_setup.reaction_extreme=current_extreme;
      range=current_extreme-g_setup.sweep.extreme;
      fib382=current_extreme-range*0.382;
      fib50=current_extreme-range*0.50;
      fib75=current_extreme-range*0.75;
      fib786=current_extreme-range*0.786;
      beyond=bar.low<fib786;
      strict_touch=(bar.low<=fib50 && bar.high>=fib75);
      lenient_touch=(bar.low<=fib382 && bar.high>=fib786);
      made_new_extreme=current_extreme>previous_extreme;
     }
   else
     {
      current_extreme=MathMin(previous_extreme,bar.low);
      g_setup.reaction_extreme=current_extreme;
      range=g_setup.sweep.extreme-current_extreme;
      fib382=current_extreme+range*0.382;
      fib50=current_extreme+range*0.50;
      fib75=current_extreme+range*0.75;
      fib786=current_extreme+range*0.786;
      beyond=bar.high>fib786;
      strict_touch=(bar.high>=fib50 && bar.low<=fib75);
      lenient_touch=(bar.high>=fib382 && bar.low<=fib786);
      made_new_extreme=current_extreme<previous_extreme;
     }
   if(beyond)
     {
      ResetSetup("m5_beyond_786");
      return;
     }
   // Con OHLC non conosciamo l'ordine intrabar: una candela che crea un nuovo
   // estremo e ritraccia viene rifiutata conservativamente.
   if(made_new_extreme) return;
   if(InpM5FibMode==M5_FIB_STRICT && strict_touch)
      ArmEntryFromReaction(at,fib75,fib50,"IN_ZONE");
   else if(InpM5FibMode==M5_FIB_LENIENT && lenient_touch)
      ArmEntryFromReaction(at,fib786,fib382,strict_touch ? "IN_ZONE" : "LENIENT_OUTSIDE");
  }

int ContextScore()
  {
   int score=0;
   double slope=MathAbs(g_setup.bias.slope);
   if(slope>=2.0*InpMinEmaSlope) score+=2;
   else if(slope>=InpMinEmaSlope) score+=1;
   if(InpUseEmaMacro) score+=1;
   if(g_setup.m5_fib_position=="IN_ZONE") score+=2;
   else if(g_setup.m5_fib_position=="LENIENT_OUTSIDE") score-=1;
   ulong mask=g_setup.sweep.level_mask;
   if((mask&(PoolBit(POOL_PNYH)|PoolBit(POOL_PNYL)))!=0) score+=3;
   if((mask&(PoolBit(POOL_PDH)|PoolBit(POOL_PDL)))!=0) score+=3;
   if((mask&(PoolBit(POOL_ASH)|PoolBit(POOL_ASL)))!=0) score+=2;
   if((mask&(PoolBit(POOL_PRE_NY_H)|PoolBit(POOL_PRE_NY_L)))!=0) score+=1;
   if(g_setup.sweep.level_count>=2) score+=2;
   return score;
  }

bool SelectTarget(const datetime at,const Direction direction,const double entry,
                  const double stop_distance,double &target)
  {
   double candidates[];
   LiquidityLevel levels[];
   GetLiquidityLevels(at,at,levels);
   for(int i=0;i<ArraySize(levels);i++)
     {
      if(levels[i].state==LIQUIDITY_SWEPT) continue;
      if((direction==DIR_LONG && levels[i].price>entry) ||
         (direction==DIR_SHORT && levels[i].price<entry))
        {
         int n=ArraySize(candidates);
         ArrayResize(candidates,n+1);
         candidates[n]=levels[i].price;
        }
     }
   StructureSnapshot m5;
   StructureEvent events[];
   SwingPoint swings[];
   if(BuildStructure(PERIOD_M5,InpKM5,at,700,m5,events,swings))
     {
      if(direction==DIR_LONG && m5.has_last_high && m5.last_high.price>entry)
        {
         int n=ArraySize(candidates); ArrayResize(candidates,n+1); candidates[n]=m5.last_high.price;
        }
      if(direction==DIR_SHORT && m5.has_last_low && m5.last_low.price<entry)
        {
         int n=ArraySize(candidates); ArrayResize(candidates,n+1); candidates[n]=m5.last_low.price;
        }
     }
   ENUM_TIMEFRAMES frames[2]={PERIOD_M5,PERIOD_M15};
   for(int f=0;f<2;f++)
     {
      Zone fvgs[];
      MqlRates rates[];
      double atr[];
      DetectFvgs(frames[f],at,(frames[f]==PERIOD_M5 ? 650 : 220),InpMinFvgAtrM5,fvgs,rates,atr);
      for(int i=0;i<ArraySize(fvgs);i++)
        {
         if(fvgs[i].created_at<at-2*24*3600 || fvgs[i].direction==direction) continue;
         double price=(direction==DIR_LONG ? fvgs[i].bottom : fvgs[i].top);
         if((direction==DIR_LONG && price>entry) || (direction==DIR_SHORT && price<entry))
           {
            int n=ArraySize(candidates); ArrayResize(candidates,n+1); candidates[n]=price;
           }
        }
     }
   if(ArraySize(candidates)==0) return false;
   bool found=false;
   for(int i=0;i<ArraySize(candidates);i++)
     {
      double rr=MathAbs(candidates[i]-entry)/stop_distance;
      if(InpTargetMode==TARGET_FIRST_VALID_RR && rr<InpMinRMultiple) continue;
      if(!found)
        {
         target=candidates[i];
         found=true;
        }
      else if(direction==DIR_LONG) target=MathMin(target,candidates[i]);
      else target=MathMax(target,candidates[i]);
     }
   return found;
  }

int VolumeDigits(const double step)
  {
   int digits=0;
   double value=step;
   while(digits<8 && MathAbs(value-MathRound(value))>1e-9)
     {
      value*=10.0;
      digits++;
     }
   return digits;
  }

double NormalizeVolumeDown(const double raw)
  {
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) return 0.0;
   double volume=MathFloor(raw/step+1e-10)*step;
   volume=MathMax(volume,minimum);
   volume=MathMin(volume,MathMin(maximum,InpMaxLotAbsolute));
   return NormalizeDouble(volume,VolumeDigits(step));
  }

void UpdateRiskDay(const datetime at)
  {
   int y,m,d,h,mi;
   NewYorkDateFromServer(at,y,m,d,h,mi);
   int key=y*10000+m*100+d;
   if(key==g_daily_key) return;
   g_daily_key=key;
   g_daily_start_balance=AccountInfoDouble(ACCOUNT_BALANCE);
   g_trades_today=0;
  }

double EffectiveRiskFraction()
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_peak_equity=MathMax(g_peak_equity,equity);
   double peak_dd=(g_peak_equity>0.0 ? (g_peak_equity-equity)/g_peak_equity : 0.0);
   if(peak_dd>0.05 || g_consecutive_losses>=5) return 0.0;
   double fraction=InpRiskPerTradePct;
   if(peak_dd>0.03 || g_consecutive_losses>=3) fraction*=0.5;
   return fraction;
  }

bool RiskCheckAndSize(const datetime at,const double stop_distance,const double spread,double &volume,double &risk_amount,string &reason)
  {
   UpdateRiskDay(at);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double fraction=EffectiveRiskFraction();
   if(fraction<=0.0 || at<g_loss_pause_until)
     {
      reason="circuit_breaker";
      return false;
     }
   if(PositionsTotal()>=InpMaxConcurrent)
     {
      reason="max_positions";
      return false;
     }
   if(g_trades_today>=InpMaxTradesPerDay)
     {
      reason="max_trades";
      return false;
     }
   if(spread>InpMaxSpread)
     {
      reason="spread";
      return false;
     }
   double contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract<=0.0)
     {
      reason="contract_size";
      return false;
     }
   double desired_risk=equity*fraction;
   volume=NormalizeVolumeDown(desired_risk/(stop_distance*contract));
   if(volume<=0.0)
     {
      reason="volume";
      return false;
     }
   risk_amount=stop_distance*contract*volume;
   double loss_today=MathMax(0.0,g_daily_start_balance-equity);
   double daily_limit=g_initial_balance*InpDailyLossLimitPct*InpSafetyMargin;
   if(loss_today>=daily_limit)
     {
      reason="daily_loss";
      return false;
     }
   if(loss_today+risk_amount>=daily_limit)
     {
      reason="projected_daily_loss";
      return false;
     }
   double total_dd=MathMax(0.0,g_initial_balance-equity);
   double max_limit=g_initial_balance*InpMaxLossLimitPct*InpSafetyMargin;
   if(total_dd+risk_amount>=max_limit)
     {
      reason="max_drawdown";
      return false;
     }
   reason="ok";
   return true;
  }

bool PlaceLimitOrder(const datetime at,const Zone &zone,const MqlRates &bar)
  {
   Direction direction=g_setup.bias.direction;
   double entry=ZoneEntryPrice(zone);
   MqlRates m1[];
   int n=LoadClosedRates(PERIOD_M1,at,250,m1);
   if(n<20) { Diag("veto:order:no_m1_history"); return false; }
   double atr_values[];
   bool quality[];
   CalculateAtrAndQuality(m1,atr_values,quality);
   double atr=atr_values[n-1];
   StructureSnapshot snapshot;
   StructureEvent events[];
   SwingPoint swings[];
   if(!BuildStructure(PERIOD_M1,InpKM1,at,500,snapshot,events,swings))
     {
      Diag("veto:order:no_m1_structure");
      return false;
     }
   double buffer=InpSlBufferATR*atr;
   double stop;
   if(direction==DIR_LONG)
     {
      stop=zone.bottom-buffer;
      if(InpStopMode==STOP_SWEEP_ANCHORED)
        {
         stop=MathMin(stop,g_setup.sweep.extreme-buffer);
         if(snapshot.has_last_low) stop=MathMin(stop,snapshot.last_low.price-buffer);
        }
      else if(InpStopMode==STOP_LOCAL_STRUCTURE && snapshot.has_last_low &&
              snapshot.last_low.confirmed_at>=g_setup.entry_armed_at)
         stop=MathMin(stop,snapshot.last_low.price-buffer);
     }
   else
     {
      stop=zone.top+buffer;
      if(InpStopMode==STOP_SWEEP_ANCHORED)
        {
         stop=MathMax(stop,g_setup.sweep.extreme+buffer);
         if(snapshot.has_last_high) stop=MathMax(stop,snapshot.last_high.price+buffer);
        }
      else if(InpStopMode==STOP_LOCAL_STRUCTURE && snapshot.has_last_high &&
              snapshot.last_high.confirmed_at>=g_setup.entry_armed_at)
         stop=MathMax(stop,snapshot.last_high.price+buffer);
     }
   double stop_distance=MathAbs(entry-stop);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double spread=MathMax((double)bar.spread*point,
                         SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID));
   double min_distance=MathMax(InpMinSlDollars,spread*3.0);
   if(stop_distance<min_distance)
     {
      Diag("veto:order:sl_too_small");
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=sl_too_small|entry=%.2f|stop=%.2f|distance=%.2f|limit=%.2f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),entry,stop,stop_distance,min_distance);
      return false;
     }
   if(stop_distance>InpMaxSlDollars)
     {
      Diag("veto:order:sl_too_large");
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=sl_too_large|entry=%.2f|stop=%.2f|distance=%.2f|limit=%.2f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),entry,stop,stop_distance,InpMaxSlDollars);
      return false;
     }
   double target;
   if(!SelectTarget(at,direction,entry,stop_distance,target))
     {
      Diag("veto:order:no_target");
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=no_target|entry=%.2f|stop=%.2f|distance=%.2f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),entry,stop,stop_distance);
      return false;
     }
   double r_multiple=MathAbs(target-entry)/stop_distance;
   if(r_multiple<InpMinRMultiple)
     {
      Diag("veto:order:rr");
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=rr|entry=%.2f|stop=%.2f|target=%.2f|rr=%.3f|limit=%.2f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),entry,stop,target,r_multiple,InpMinRMultiple);
      return false;
     }
   bool confluence=HigherTfConfluence(zone,at);
   int total_score=ContextScore()+ZoneBaseScore(zone,confluence)+(r_multiple>=3.0 ? 2 : 1);
   if(total_score<InpMinSetupScore)
     {
      Diag("veto:order:score");
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=score|score=%d|limit=%d|rr=%.3f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),total_score,InpMinSetupScore,r_multiple);
      return false;
     }
   double volume,risk_amount;
   string risk_reason;
   if(!RiskCheckAndSize(at,stop_distance,spread,volume,risk_amount,risk_reason))
     {
      Diag("veto:risk:"+risk_reason);
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=risk_%s|distance=%.2f|spread=%.2f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),risk_reason,stop_distance,spread);
      return false;
     }
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if((direction==DIR_LONG && entry>=ask) || (direction==DIR_SHORT && entry<=bid))
     {
      Diag("veto:order:not_limit_price");
      PrintFormat("XAU_ORDER_VETO|time=%s|reason=not_limit_price|direction=%s|entry=%.2f|bid=%.2f|ask=%.2f",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),DirectionName(direction),entry,bid,ask);
      return false;
     }
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   entry=NormalizeDouble(entry,digits);
   stop=NormalizeDouble(stop,digits);
   target=NormalizeDouble(target,digits);
   datetime expiry=at+15*60;
   ENUM_ORDER_TYPE_TIME order_time=ORDER_TIME_GTC;
   datetime broker_expiry=0;
   long expiration_modes=SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
   if((expiration_modes&SYMBOL_EXPIRATION_SPECIFIED)!=0)
     {
      order_time=ORDER_TIME_SPECIFIED;
      broker_expiry=expiry;
     }
   string comment=StringFormat("XAUv12_%I64d",(long)at);
   bool placed=false;
   if(direction==DIR_LONG)
      placed=g_trade.BuyLimit(volume,entry,_Symbol,stop,target,order_time,broker_expiry,comment);
   else
      placed=g_trade.SellLimit(volume,entry,_Symbol,stop,target,order_time,broker_expiry,comment);
   if(!placed)
     {
      Diag("order_rejected:"+(string)g_trade.ResultRetcode());
      PrintFormat("XAU_ORDER_REJECTED|retcode=%u|description=%s|entry=%.2f|sl=%.2f|tp=%.2f|volume=%.2f",
                  g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription(),entry,stop,target,volume);
      return false;
     }
   g_setup.pending_ticket=g_trade.ResultOrder();
   g_setup.pending_expiry=expiry;
   g_setup.planned_entry=entry;
   g_setup.initial_stop=stop;
   g_setup.target=target;
   g_setup.initial_risk_price=stop_distance;
   g_setup.setup_score=total_score;
   g_setup.state=SETUP_ORDER_PENDING;
   Diag("orders_placed");
   PrintFormat("XAU_ORDER|time=%s|direction=%s|entry=%.2f|sl=%.2f|tp=%.2f|volume=%.2f|score=%d|rr=%.2f",
               TimeToString(at,TIME_DATE|TIME_MINUTES),DirectionName(direction),entry,stop,target,volume,total_score,r_multiple);
   return true;
  }

void OnM1Close(const datetime at)
  {
   if(g_setup.state!=SETUP_ENTRY_ARMED) return;
   if(at>g_setup.entry_armed_at+InpEntryTimeoutMinutes*60)
     {
      ResetSetup("entry_timeout");
      return;
     }
   if(at>SetupDeadline(g_setup.entry_armed_at))
     {
      ResetSetup("entry_deadline");
      return;
     }
   MqlRates bar;
   double atr;
   bool quality;
   if(!LatestClosedBar(PERIOD_M1,at,bar,atr,quality) || !quality) return;
   Direction direction=g_setup.bias.direction;
   StructureSnapshot snapshot;
   StructureEvent events[];
   SwingPoint swings[];
   if(!BuildStructure(PERIOD_M1,InpKM1,at,500,snapshot,events,swings)) return;
   Direction contrary=(direction==DIR_LONG ? DIR_SHORT : DIR_LONG);
   if(EventAt(events,at,EVENT_CHOCH,contrary))
     {
      ResetSetup("m1_choch");
      return;
     }
   if(g_setup.candidate.valid && ZoneInvalidated(g_setup.candidate,bar.close))
     {
      g_setup.candidate.valid=false;
      g_setup.candidate_base_score=-100000;
     }
   Zone zones[];
   ZonesCreatedAt(PERIOD_M1,at,InpMinFvgAtrM1,InpIfvgMaxAgeM1,zones);
   for(int i=0;i<ArraySize(zones);i++)
     {
      if(zones[i].direction!=direction || zones[i].created_at<=g_setup.entry_armed_at) continue;
      if(zones[i].expires_at>0 && zones[i].expires_at<at) continue;
      if(!ZoneOverlaps(zones[i],g_setup.entry_zone_low,g_setup.entry_zone_high)) continue;
      bool confluence=HigherTfConfluence(zones[i],at);
      int base=ZoneBaseScore(zones[i],confluence);
      Diag("m1_zone_found");
      if(base>g_setup.candidate_base_score)
        {
         g_setup.candidate=zones[i];
         g_setup.candidate_base_score=base;
        }
     }
   if(!g_setup.candidate.valid) return;
   bool bos=EventAt(events,at,EVENT_BOS,direction);
   bool zone_ready=(g_setup.candidate.created_at==at);
   bool displacement=false;
   bool directional_break=false;
   double body_atr=0.0;
   MqlRates recent[];
   int recent_count=LoadClosedRates(PERIOD_M1,at,3,recent);
   if(recent_count>=2 && atr>0.0)
     {
      MqlRates previous=recent[recent_count-2];
      double body=MathAbs(bar.close-bar.open);
      body_atr=body/atr;
      if(direction==DIR_LONG)
         directional_break=(bar.close>bar.open && bar.close>previous.high);
      else
         directional_break=(bar.close<bar.open && bar.close<previous.low);
      displacement=(directional_break && body_atr>=InpMinM1DisplacementATR &&
                    body_atr<=InpMaxM1DisplacementATR);
     }
   if(directional_break || bos)
      PrintFormat("XAU_TRIGGER_OBS|time=%s|direction=%s|body_atr=%.3f|previous_break=%s|bos=%s|zone=%s|zone_width_atr=%.3f|zone_age_min=%d|sweep_age_min=%d|levels=%s",
                  TimeToString(at,TIME_DATE|TIME_MINUTES),DirectionName(direction),body_atr,
                  (directional_break ? "true" : "false"),(bos ? "true" : "false"),
                  ZoneTypeName(g_setup.candidate.type),
                  (atr>0.0 ? (g_setup.candidate.top-g_setup.candidate.bottom)/atr : 0.0),
                  (int)((at-g_setup.candidate.created_at)/60),
                  (int)((at-g_setup.sweep.occurred_at)/60),SweepLevelNames(g_setup.sweep));
   bool triggered=false;
   if(InpM1TriggerMode==M1_TRIGGER_BOS && bos && at>g_setup.candidate.created_at)
     {
      Diag("m1_trigger:bos");
      triggered=true;
     }
   else if(InpM1TriggerMode==M1_TRIGGER_ZONE_READY && zone_ready)
     {
      Diag("m1_trigger:zone_ready");
      triggered=true;
     }
   else if(InpM1TriggerMode==M1_TRIGGER_DISPLACEMENT && displacement)
     {
      Diag("m1_trigger:displacement");
      triggered=true;
     }
   if(!triggered) return;
   PlaceLimitOrder(at,g_setup.candidate,bar);
  }

bool SelectOwnPosition(ulong &ticket)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong candidate=PositionGetTicket(i);
      if(candidate==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic)
        {
         ticket=candidate;
         return true;
        }
     }
   ticket=0;
   return false;
  }

ENUM_ORDER_TYPE_FILLING MarketDealFillingMode()
  {
   ENUM_SYMBOL_TRADE_EXECUTION execution=
      (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE);
   if(execution!=SYMBOL_TRADE_EXECUTION_MARKET) return ORDER_FILLING_RETURN;
   long modes=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((modes&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((modes&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_FOK;
  }

bool ReducePosition(const ulong ticket,double volume)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double current=PositionGetDouble(POSITION_VOLUME);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   volume=MathFloor(volume/step+1e-10)*step;
   volume=NormalizeDouble(volume,VolumeDigits(step));
   if(volume<minimum) return false;
   if(volume>=current-minimum/2.0) return g_trade.PositionClose(ticket,InpDeviationPoints);
   ENUM_POSITION_TYPE position_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action=TRADE_ACTION_DEAL;
   request.position=ticket;
   request.symbol=_Symbol;
   request.magic=InpMagic;
   request.volume=volume;
   request.deviation=InpDeviationPoints;
   request.type=(position_type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price=(request.type==ORDER_TYPE_SELL ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                               : SymbolInfoDouble(_Symbol,SYMBOL_ASK));
   request.type_filling=MarketDealFillingMode();
   bool ok=OrderSend(request,result);
   if(!ok || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL))
     {
      PrintFormat("XAU_PARTIAL_REJECTED|retcode=%u|comment=%s",result.retcode,result.comment);
      return false;
     }
   return true;
  }

void SyncPendingAndPosition(const datetime at)
  {
   ulong position_ticket;
   if(SelectOwnPosition(position_ticket))
     {
      if(g_setup.state!=SETUP_IN_POSITION)
        {
         g_setup.state=SETUP_IN_POSITION;
         g_setup.pending_ticket=0;
         g_position_stage=0;
         g_position_initial_volume=PositionGetDouble(POSITION_VOLUME);
         g_position_initial_entry=PositionGetDouble(POSITION_PRICE_OPEN);
         g_position_initial_stop=g_setup.initial_stop;
         if(g_position_initial_stop<=0.0) g_position_initial_stop=PositionGetDouble(POSITION_SL);
         g_position_mae=0.0;
         g_position_mfe=0.0;
         g_trades_today++;
         Diag("orders_filled");
         PrintFormat("XAU_FILL|time=%s|ticket=%I64u|entry=%.2f|volume=%.2f",
                     TimeToString(at,TIME_DATE|TIME_SECONDS),position_ticket,
                     g_position_initial_entry,g_position_initial_volume);
        }
      return;
     }
   if(g_setup.state==SETUP_ORDER_PENDING)
     {
      bool exists=(g_setup.pending_ticket>0 && OrderSelect(g_setup.pending_ticket));
      if(exists && at>g_setup.pending_expiry)
        {
         if(g_trade.OrderDelete(g_setup.pending_ticket)) ResetSetup("order_expired");
         return;
        }
      if(exists && IsNewsBlackout(at))
        {
         if(g_trade.OrderDelete(g_setup.pending_ticket)) ResetSetup("order_news_blackout");
         return;
        }
      if(!exists) ResetSetup("order_missing");
     }
  }

void ManagePosition(const datetime at,const bool new_m5_bar)
  {
   ulong ticket;
   if(!SelectOwnPosition(ticket)) return;
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   Direction direction=(type==POSITION_TYPE_BUY ? DIR_LONG : DIR_SHORT);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double price=(direction==DIR_LONG ? bid : ask);
   double spread=ask-bid;
   double adverse=(direction==DIR_LONG ? MathMax(0.0,g_position_initial_entry-price)
                                      : MathMax(0.0,price-g_position_initial_entry));
   double favorable=(direction==DIR_LONG ? MathMax(0.0,price-g_position_initial_entry)
                                        : MathMax(0.0,g_position_initial_entry-price));
   g_position_mae=MathMax(g_position_mae,adverse);
   g_position_mfe=MathMax(g_position_mfe,favorable);
   string news_reason=NewsForceCloseReason(at);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double daily_loss=MathMax(0.0,g_daily_start_balance-equity);
   bool risk_force=daily_loss>=g_initial_balance*InpDailyLossLimitPct*InpSafetyMargin*0.60;
   if(news_reason!="" || MustForceClose(at) || risk_force)
     {
      string reason=(news_reason!="" ? news_reason : (risk_force ? "RISK_FORCE" : "SESSION_CLOSE"));
      if(g_trade.PositionClose(ticket,InpDeviationPoints))
        {
         Diag("exit:"+reason);
         PrintFormat("XAU_EXIT|time=%s|reason=%s|mae=%.2f|mfe=%.2f",
                     TimeToString(at,TIME_DATE|TIME_SECONDS),reason,g_position_mae,g_position_mfe);
        }
      return;
     }
   double one_r=MathAbs(g_position_initial_entry-g_position_initial_stop);
   if(one_r<=0.0) return;
   double signed_move=(price-g_position_initial_entry)*(double)direction;
   if(InpExitMode==EXIT_FLAT_2R)
     {
      if(signed_move>=2.0*one_r) g_trade.PositionClose(ticket,InpDeviationPoints);
      return;
     }
   if(g_position_stage==0 && signed_move>=one_r)
     {
      if(ReducePosition(ticket,g_position_initial_volume*0.50))
        {
         g_position_stage=1;
         if(PositionSelectByTicket(ticket))
            g_trade.PositionModify(ticket,
                                   NormalizeDouble(g_position_initial_entry+(double)direction*spread,
                                                   (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)),
                                   PositionGetDouble(POSITION_TP));
         Diag("partial:1R");
        }
     }
   if(g_position_stage==1 && signed_move>=2.0*one_r)
     {
      if(ReducePosition(ticket,g_position_initial_volume*0.25))
        {
         g_position_stage=2;
         if(PositionSelectByTicket(ticket))
            g_trade.PositionModify(ticket,
                                   NormalizeDouble(g_position_initial_entry+(double)direction*one_r,
                                                   (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)),
                                   PositionGetDouble(POSITION_TP));
         Diag("partial:2R");
        }
     }
   if(g_position_stage>=2 && new_m5_bar && PositionSelectByTicket(ticket))
     {
      StructureSnapshot snapshot;
      StructureEvent events[];
      SwingPoint swings[];
      if(BuildStructure(PERIOD_M5,InpKM5,at,700,snapshot,events,swings))
        {
         double current_sl=PositionGetDouble(POSITION_SL);
         double candidate=current_sl;
         if(direction==DIR_LONG && snapshot.has_last_low && snapshot.last_low.price<price)
            candidate=MathMax(current_sl,snapshot.last_low.price);
         if(direction==DIR_SHORT && snapshot.has_last_high && snapshot.last_high.price>price+spread)
            candidate=(current_sl<=0.0 ? snapshot.last_high.price+spread
                                      : MathMin(current_sl,snapshot.last_high.price+spread));
         if(candidate!=current_sl)
            g_trade.PositionModify(ticket,NormalizeDouble(candidate,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)),
                                   PositionGetDouble(POSITION_TP));
        }
     }
  }

void CancelOwnOrders()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic)
         g_trade.OrderDelete(ticket);
     }
  }

void WriteDiagnostics()
  {
   int handle=FileOpen(InpDiagnosticsFile,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle!=INVALID_HANDLE)
     {
      FileWrite(handle,"key","value");
      FileWrite(handle,"meta:symbol",_Symbol);
      FileWrite(handle,"meta:news_required",InpRequireNewsCalendar ? "true" : "false");
      FileWrite(handle,"meta:news_available",g_news_available ? "true" : "false");
      FileWrite(handle,"meta:initial_balance",DoubleToString(g_initial_balance,2));
      FileWrite(handle,"meta:final_balance",DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
      for(int i=0;i<ArraySize(g_diag_keys);i++) FileWrite(handle,g_diag_keys[i],g_diag_values[i]);
      FileClose(handle);
     }
   PrintFormat("XAU_SUMMARY|news_required=%s|news_available=%s|initial=%.2f|final=%.2f|diagnostics=%s",
               InpRequireNewsCalendar ? "true" : "false",g_news_available ? "true" : "false",
               g_initial_balance,AccountInfoDouble(ACCOUNT_BALANCE),InpDiagnosticsFile);
   for(int i=0;i<ArraySize(g_diag_keys);i++)
      PrintFormat("XAU_DIAG|%s=%I64d",g_diag_keys[i],g_diag_values[i]);
  }

int OnInit()
  {
   if(InpEntryTimeoutMinutes<=0 || InpMinWickRatioM5<=0.0 || InpMinWickRatioM5>1.0 ||
      InpMinM1DisplacementATR<=0.0 || InpMaxM1DisplacementATR<InpMinM1DisplacementATR)
     {
      Print("XAU_INIT|status=FAIL|reason=strategy_parameters");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTesterOnly && !MQLInfoInteger(MQL_TESTER))
     {
      Print("XAU_INIT|status=FAIL|reason=tester_only_guard");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(_Symbol!="XAUUSD")
     {
      PrintFormat("XAU_INIT|status=FAIL|reason=symbol|actual=%s",_Symbol);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRunSelfTests && !RunSelfTests())
     {
      Print("XAU_INIT|status=FAIL|reason=self_tests");
      return INIT_FAILED;
     }
   ResetSetup("init");
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_news_available=LoadNewsCalendar();
   g_initial_balance=AccountInfoDouble(ACCOUNT_BALANCE);
   g_peak_equity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_start_balance=g_initial_balance;
   g_last_m1_open=iTime(_Symbol,PERIOD_M1,0);
   g_last_m5_open=iTime(_Symbol,PERIOD_M5,0);
   g_last_m15_open=iTime(_Symbol,PERIOD_M15,0);
   PrintFormat("XAU_INIT|status=OK|symbol=%s|contract=%.2f|point=%.5f|digits=%d|news_required=%s|news_available=%s",
               _Symbol,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
               SymbolInfoDouble(_Symbol,SYMBOL_POINT),(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
               InpRequireNewsCalendar ? "true" : "false",g_news_available ? "true" : "false");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now=TimeCurrent();
   UpdateRiskDay(now);
   datetime m1_open=iTime(_Symbol,PERIOD_M1,0);
   datetime m5_open=iTime(_Symbol,PERIOD_M5,0);
   datetime m15_open=iTime(_Symbol,PERIOD_M15,0);
   bool new_m1=(m1_open>0 && m1_open!=g_last_m1_open);
   bool new_m5=(m5_open>0 && m5_open!=g_last_m5_open);
   bool new_m15=(m15_open>0 && m15_open!=g_last_m15_open);
   if(new_m1) g_last_m1_open=m1_open;
   if(new_m5) g_last_m5_open=m5_open;
   if(new_m15) g_last_m15_open=m15_open;

   SyncPendingAndPosition(now);
   ManagePosition(now,new_m5);
   SyncPendingAndPosition(now);
   ulong own_position;
   if(SelectOwnPosition(own_position) || g_setup.state==SETUP_ORDER_PENDING) return;

   // Ordine identico al motore Python: M1, poi M5, poi M15. In questo modo una
   // chiusura simultanea non usa il segnale del timeframe superiore in anticipo.
   if(new_m1) OnM1Close(m1_open);
   if(new_m5) OnM5Close(m5_open);
   if(new_m15) OnM15Close(m15_open);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
     {
      double pnl=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+
                 HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
      if(pnl<0.0) g_consecutive_losses++;
      else if(pnl>0.0) g_consecutive_losses=0;
      if(g_consecutive_losses>=5)
        {
         g_loss_pause_until=TimeCurrent()+48*3600;
         Diag("circuit_breaker:five_losses");
        }
     }
  }

void OnDeinit(const int reason)
  {
   // Durante l'ottimizzazione gli agenti lavorano in parallelo: evitare che
   // tutti sovrascrivano lo stesso file diagnostico FILE_COMMON.
   if(MQLInfoInteger(MQL_TESTER))
     {
      CancelOwnOrders();
      if(!MQLInfoInteger(MQL_OPTIMIZATION)) WriteDiagnostics();
     }
  }

double OnTester()
  {
   return TesterStatistics(STAT_PROFIT);
  }
