#property script_show_inputs
#property strict

input datetime InpFrom = D'2023.01.01 00:00';
input datetime InpTo   = D'2026.08.02 00:00';
input string InpOutput = "xauusd_news_raw.csv";

string Lower(string value)
  {
   StringToLower(value);
   return value;
  }

string ClassifyImpact(const MqlCalendarEvent &event)
  {
   if(event.importance==CALENDAR_IMPORTANCE_LOW)
      return "LOW";
   if(event.importance==CALENDAR_IMPORTANCE_MODERATE)
      return "MEDIUM";
   if(event.importance!=CALENDAR_IMPORTANCE_HIGH)
      return "LOW";

   string name=Lower(event.name+" "+event.event_code);
   string critical_tokens[]={
      "nonfarm", "non-farm", "consumer price", "cpi", "producer price", "ppi",
      "fomc", "fed interest rate", "federal funds", "powell", "fed chair",
      "pce price", "personal consumption expenditure"
   };
   for(int i=0;i<ArraySize(critical_tokens);i++)
      if(StringFind(name,critical_tokens[i])>=0)
         return "CRITICAL";
   return "HIGH";
  }

void OnStart()
  {
   datetime connect_deadline=TimeLocal()+60;
   while(!TerminalInfoInteger(TERMINAL_CONNECTED) && TimeLocal()<connect_deadline)
      Sleep(1000);
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      Print("ExportCalendar aborted: terminal is not connected");
      return;
     }

   int handle=FileOpen(InpOutput,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("FileOpen failed: %d",GetLastError());
      return;
     }
   FileWrite(handle,"server_time","event_id","name","impact","importance","time_mode");
   int written=0;
   int received=0;
   int failures=0;
   MqlCalendarEvent events[];
   int event_count=-1;
   for(int attempt=0;attempt<3 && event_count<0;attempt++)
     {
      ResetLastError();
      event_count=CalendarEventByCountry("US",events);
      if(event_count<0)
        {
         PrintFormat("CalendarEventByCountry attempt %d failed: %d",attempt+1,GetLastError());
         Sleep(2000);
        }
     }
   if(event_count<0)
     {
      FileClose(handle);
      return;
     }

   int queried=0;
   for(int e=0;e<event_count;e++)
     {
      if(events[e].importance<CALENDAR_IMPORTANCE_MODERATE) continue;
      queried++;
      MqlCalendarValue values[];
      int count=-1;
      for(int attempt=0;attempt<2 && count<0;attempt++)
        {
         ResetLastError();
         count=CalendarValueHistoryByEvent(events[e].id,values,InpFrom,InpTo);
         if(count<0)
           {
            PrintFormat("Calendar event %I64u (%s) attempt %d failed: %d",
                        events[e].id,events[e].name,attempt+1,GetLastError());
            Sleep(1000);
           }
        }
      if(count<0)
        {
         failures++;
         continue;
        }
      received+=count;
      for(int i=0;i<count;i++)
        {
         string impact=ClassifyImpact(events[e]);
         FileWrite(
            handle,
            TimeToString(values[i].time,TIME_DATE|TIME_MINUTES),
            (string)values[i].event_id,
            events[e].name,
            impact,
            (string)events[e].importance,
            (string)events[e].time_mode
         );
         written++;
        }
      FileFlush(handle);
      ArrayFree(values);
     }
   FileClose(handle);
   PrintFormat("ExportCalendar queried %d of %d events and wrote %d of %d values with %d failed events to FILE_COMMON\\%s",
               queried,event_count,written,received,failures,InpOutput);
  }
