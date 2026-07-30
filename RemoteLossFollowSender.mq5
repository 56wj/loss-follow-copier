//+------------------------------------------------------------------+
//|                                      RemoteLossFollowSender.mq5  |
//|  Exports source account positions for RemoteLossFollowReceiver.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "远程浮亏跟单发送端：把源账号持仓快照写入MT5公共文件夹。"

input group "发送通道"
input string InpChannelName     = "loss_follow_1"; // 通道名称，接收端必须填写同一个名称
input string InpAllowedSymbols  = "";              // 导出品种，多个用;或,分隔，空表示全部
input int    InpScanIntervalMs  = 50;              // 本机双MT5建议50毫秒；最低20毫秒
input bool   InpPauseWhenAutoTradingOff = true;    // 自动交易关闭时暂停发布源单快照
input bool   InpPrintDebug      = false;           // 打印调试日志；追求速度时关闭

string g_file_name;
string g_temp_file_name;
ulong g_snapshot_sequence = 0;
datetime g_last_print_time = 0;
datetime g_last_error_print_time = 0;

int OnInit()
{
   if(InpChannelName == "")
   {
      Print("InpChannelName cannot be empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   int timer_period = InpScanIntervalMs < 20 ? 20 : InpScanIntervalMs;
   g_file_name = SnapshotFileName();
   g_temp_file_name = g_file_name + ".tmp";
   EventSetMillisecondTimer((uint)timer_period);
   WriteSnapshot();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
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
   if(InpPauseWhenAutoTradingOff && !IsAlgoTradingAllowed())
   {
      WritePausedSnapshot();
      return;
   }

   ulong next_sequence = g_snapshot_sequence + 1;
   ulong publish_tick_ms = GetTickCount64();
   datetime now = TimeLocal();

   int handle = FileOpen(g_temp_file_name,
                         FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_UNICODE | FILE_SHARE_READ,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      PrintSnapshotError("Open temporary snapshot failed", GetLastError());
      return;
   }

   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);

   FileWrite(handle,
             "META",
             "RLFC2",
             InpChannelName,
             login,
             server,
             (long)now,
             (long)next_sequence,
             (long)publish_tick_ms);

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

   FileWrite(handle, "END", exported, (long)now, (long)next_sequence);
   FileClose(handle);

   if(!CommitSnapshot())
      return;

   g_snapshot_sequence = next_sequence;

   if(InpPrintDebug && now != g_last_print_time)
   {
      g_last_print_time = now;
      PrintFormat("Remote snapshot exported. file=%s positions=%d channel=%s seq=%I64u",
                  g_file_name,
                  exported,
                  InpChannelName,
                  g_snapshot_sequence);
   }
}

void WritePausedSnapshot()
{
   ulong next_sequence = g_snapshot_sequence + 1;
   ulong publish_tick_ms = GetTickCount64();
   datetime now = TimeLocal();

   int handle = FileOpen(g_temp_file_name,
                         FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_UNICODE | FILE_SHARE_READ,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      PrintSnapshotError("Open temporary paused snapshot failed", GetLastError());
      return;
   }

   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);

   FileWrite(handle,
             "META",
             "RLFC2",
             InpChannelName,
             login,
             server,
             0,
             (long)next_sequence,
             (long)publish_tick_ms);
   FileWrite(handle, "PAUSED", "auto_trading_disabled");
   FileWrite(handle, "END", 0, 0, (long)next_sequence);
   FileClose(handle);

   if(!CommitSnapshot())
      return;

   g_snapshot_sequence = next_sequence;

   if(InpPrintDebug && now != g_last_print_time)
   {
      g_last_print_time = now;
      PrintFormat("Remote snapshot paused. file=%s reason=auto_trading_disabled channel=%s",
                  g_file_name,
                  InpChannelName);
   }
}

bool CommitSnapshot()
{
   ResetLastError();
   if(FileMove(g_temp_file_name,
               FILE_COMMON,
               g_file_name,
               FILE_COMMON | FILE_REWRITE))
      return true;

   PrintSnapshotError("Atomic snapshot replace failed", GetLastError());
   return false;
}

void PrintSnapshotError(const string action, const int error_code)
{
   datetime now = TimeLocal();
   if(now == g_last_error_print_time)
      return;

   g_last_error_print_time = now;
   PrintFormat("%s. file=%s temp=%s error=%d",
               action,
               g_file_name,
               g_temp_file_name,
               error_code);
}

bool IsAlgoTradingAllowed()
{
   return (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
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
