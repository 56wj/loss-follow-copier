//+------------------------------------------------------------------+
//|                                      RemoteLossFollowSender.mq5  |
//|  Exports source account positions for RemoteLossFollowReceiver.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "远程浮亏跟单发送端：把源账号持仓快照写入MT5公共文件夹。"

input group "发送通道"
input string InpChannelName     = "loss_follow_1"; // 通道名称，接收端必须填写同一个名称
input string InpAllowedSymbols  = "";              // 导出品种，多个用;或,分隔，空表示全部
input int    InpScanIntervalMs  = 300;             // 快照刷新间隔，单位毫秒
input bool   InpPrintDebug      = true;            // 打印调试日志

string g_file_name;
datetime g_last_print_time = 0;

int OnInit()
{
   if(InpChannelName == "")
   {
      Print("InpChannelName cannot be empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   int timer_period = InpScanIntervalMs < 100 ? 100 : InpScanIntervalMs;
   g_file_name = SnapshotFileName();
   EventSetMillisecondTimer((uint)timer_period);
   WriteSnapshot();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   WriteSnapshot();
}

void OnTick()
{
   WriteSnapshot();
}

void OnTimer()
{
   WriteSnapshot();
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   WriteSnapshot();
}

void WriteSnapshot()
{
   int handle = FileOpen(g_file_name,
                         FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_UNICODE,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("Open snapshot file failed. file=%s error=%d", g_file_name, GetLastError());
      return;
   }

   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   datetime now = TimeLocal();

   FileWrite(handle, "META", "RLFC1", InpChannelName, login, server, (long)now);

   int exported = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!IsAllowedSymbol(symbol, InpAllowedSymbols))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL)
         continue;

      long identifier = PositionGetInteger(POSITION_IDENTIFIER);
      ulong source_id = identifier > 0 ? (ulong)identifier : ticket;

      FileWrite(handle,
                "P",
                (long)source_id,
                (long)ticket,
                symbol,
                (int)type,
                PositionGetInteger(POSITION_MAGIC),
                PositionGetString(POSITION_COMMENT),
                DoubleToString(PositionGetDouble(POSITION_VOLUME), 8),
                DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 10),
                DoubleToString(PositionGetDouble(POSITION_SL), 10),
                DoubleToString(PositionGetDouble(POSITION_TP), 10),
                (long)PositionGetInteger(POSITION_TIME));
      exported++;
   }

   FileWrite(handle, "END", exported, (long)now);
   FileClose(handle);

   if(InpPrintDebug && now != g_last_print_time)
   {
      g_last_print_time = now;
      PrintFormat("Remote snapshot exported. file=%s positions=%d channel=%s",
                  g_file_name,
                  exported,
                  InpChannelName);
   }
}

string SnapshotFileName()
{
   return "RemoteLossFollow_" + SanitizeFilePart(InpChannelName) + ".tsv";
}

string SanitizeFilePart(string value)
{
   StringReplace(value, "\\", "_");
   StringReplace(value, "/", "_");
   StringReplace(value, ":", "_");
   StringReplace(value, "*", "_");
   StringReplace(value, "?", "_");
   StringReplace(value, "\"", "_");
   StringReplace(value, "<", "_");
   StringReplace(value, ">", "_");
   StringReplace(value, "|", "_");
   StringReplace(value, " ", "_");
   return value;
}

bool IsAllowedSymbol(string symbol, string allowed)
{
   StringReplace(allowed, " ", "");
   StringReplace(allowed, ",", ";");

   if(allowed == "")
      return true;

   string parts[];
   int count = StringSplit(allowed, ';', parts);
   for(int i = 0; i < count; i++)
   {
      if(parts[i] == symbol)
         return true;
   }

   return false;
}
