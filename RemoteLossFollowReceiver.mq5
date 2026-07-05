//+------------------------------------------------------------------+
//|                                  RemoteLossFollowReceiver.mq5    |
//|  Reads remote source snapshots and opens same-direction copies    |
//|  when the remote source reaches a floating loss threshold.        |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "远程浮亏跟单接收端：读取发送端快照后按浮亏距离跟单。"

enum ENUM_COPY_LOT_MODE
{
   COPY_LOT_FIXED = 0,       // 固定手数
   COPY_LOT_SOURCE = 1,      // 跟随源单手数
   COPY_LOT_MULTIPLIER = 2   // 源单手数 * 倍数
};

enum ENUM_LOSS_TRIGGER_MODE
{
   LOSS_TRIGGER_POINTS = 0,   // 券商点数: 黄金2位报价300=3.00, 3位报价3000=3.000
   LOSS_TRIGGER_PRICE = 1     // 价格距离: 黄金3.0表示3美金
};

enum ENUM_COPY_ENTRY_MODE
{
   ENTRY_MARKET_ON_TRIGGER = 0, // 持续监控，浮亏达到条件后市价入场
   ENTRY_PENDING_AT_TRIGGER = 1, // 源单出现后，在浮亏触发价提前挂单
   ENTRY_GRID_ACTIVATION = 2     // 网格激活: 组合浮亏触发后补跟已有源单，后续新源单可直接跟
};

enum ENUM_PROFIT_CHECK_MODE
{
   PROFIT_CHECK_ANYTIME = 0,      // 随时检查: 每次OnTick/定时轮询都检查盈利平仓
   PROFIT_CHECK_TIME_WINDOW = 1   // 按秒窗口检查: 只在下方起始秒~结束秒窗口检查
};

struct SourceProfile
{
   int profile_index;
   bool enabled;
   long magic;
   string comment_filter;
   string allowed_symbols;
   ENUM_COPY_ENTRY_MODE entry_mode;
   ENUM_LOSS_TRIGGER_MODE loss_trigger_mode;
   double loss_trigger_price;
   double loss_trigger_points;
   ENUM_COPY_LOT_MODE lot_mode;
   double fixed_lot;
   double lot_multiplier;
   bool level2_enabled;
   ENUM_LOSS_TRIGGER_MODE level2_loss_trigger_mode;
   double level2_loss_trigger_price;
   double level2_loss_trigger_points;
   ENUM_COPY_LOT_MODE level2_lot_mode;
   double level2_fixed_lot;
   double level2_lot_multiplier;
   double level2_stop_loss_points;
   double level2_take_profit_points;
   bool level3_enabled;
   ENUM_LOSS_TRIGGER_MODE level3_loss_trigger_mode;
   double level3_loss_trigger_price;
   double level3_loss_trigger_points;
   ENUM_COPY_LOT_MODE level3_lot_mode;
   double level3_fixed_lot;
   double level3_lot_multiplier;
   double level3_stop_loss_points;
   double level3_take_profit_points;
   bool copy_source_sltp;
   double stop_loss_points;
   double take_profit_points;
   ENUM_PROFIT_CHECK_MODE profit_check_mode;
   bool minute_profit_close_enabled;
   double minute_profit_close_points;
   int minute_close_start_second;
   int minute_close_end_second;
   bool basket_profit_close_enabled;
   double basket_profit_close_points;
   int grid_initial_max_copies;
   bool grid_stop_after_basket_close;
};

struct RemoteSourcePosition
{
   ulong source_id;
   ulong ticket;
   string symbol;
   ENUM_POSITION_TYPE position_type;
   long magic;
   string comment;
   double volume;
   double open_price;
   double sl;
   double tp;
   datetime open_time;
};

input group "远程通道"
input string             InpChannelName          = "loss_follow_1"; // 通道名称，必须和发送端一致
input int                InpSourceStaleSeconds   = 10;              // 快照超过多少秒视为失效；失效时不新开单、不按源单消失平仓

input group "源EA1设置"
input bool               InpEA1Enabled           = true;         // 启用源EA1
input long               InpEA1Magic             = 123456;       // 源EA1魔术号，-1表示不限制魔术号
input string             InpEA1CommentFilter     = "";           // 源EA1注释模糊匹配，空表示不限制
input string             InpEA1AllowedSymbols    = "";           // 源EA1允许品种，多个用;或,分隔，空表示全部
input ENUM_COPY_ENTRY_MODE InpEA1EntryMode       = ENTRY_MARKET_ON_TRIGGER; // 源EA1入场模式
input ENUM_LOSS_TRIGGER_MODE InpEA1LossMode      = LOSS_TRIGGER_PRICE; // 源EA1档位1浮亏触发模式
input double             InpEA1LossPrice         = 3.0;          // 源EA1档位1价格距离触发，黄金3.0=浮亏3美金
input double             InpEA1LossPoints        = 300.0;        // 源EA1档位1点数触发，黄金2位300=3.00，3位3000=3.000
input ENUM_COPY_LOT_MODE InpEA1LotMode           = COPY_LOT_FIXED; // 源EA1档位1跟单手数模式
input double             InpEA1FixedLot          = 0.01;         // 源EA1档位1固定跟单手数
input double             InpEA1LotMultiplier     = 1.0;          // 源EA1档位1手数倍数，倍数模式下生效
input double             InpEA1StopLossPoints    = 0.0;          // 源EA1档位1自定义止损点数，0=不设置
input double             InpEA1TakeProfitPoints  = 0.0;          // 源EA1档位1自定义止盈点数，0=不设置
input bool               InpEA1Level2Enabled     = false;        // 启用源EA1档位2
input ENUM_LOSS_TRIGGER_MODE InpEA1Level2LossMode = LOSS_TRIGGER_PRICE; // 源EA1档位2浮亏触发模式
input double             InpEA1Level2LossPrice   = 4.0;          // 源EA1档位2价格距离触发，黄金4.0=浮亏4美金
input double             InpEA1Level2LossPoints  = 400.0;        // 源EA1档位2点数触发，黄金2位400=4.00，3位4000=4.000
input ENUM_COPY_LOT_MODE InpEA1Level2LotMode     = COPY_LOT_FIXED; // 源EA1档位2跟单手数模式
input double             InpEA1Level2FixedLot    = 0.01;         // 源EA1档位2固定跟单手数
input double             InpEA1Level2LotMultiplier = 1.0;        // 源EA1档位2手数倍数，倍数模式下生效
input double             InpEA1Level2StopLossPoints = 0.0;       // 源EA1档位2自定义止损点数，0=不设置
input double             InpEA1Level2TakeProfitPoints = 0.0;     // 源EA1档位2自定义止盈点数，0=不设置
input bool               InpEA1Level3Enabled     = false;        // 启用源EA1档位3
input ENUM_LOSS_TRIGGER_MODE InpEA1Level3LossMode = LOSS_TRIGGER_PRICE; // 源EA1档位3浮亏触发模式
input double             InpEA1Level3LossPrice   = 5.0;          // 源EA1档位3价格距离触发，黄金5.0=浮亏5美金
input double             InpEA1Level3LossPoints  = 500.0;        // 源EA1档位3点数触发，黄金2位500=5.00，3位5000=5.000
input ENUM_COPY_LOT_MODE InpEA1Level3LotMode     = COPY_LOT_FIXED; // 源EA1档位3跟单手数模式
input double             InpEA1Level3FixedLot    = 0.01;         // 源EA1档位3固定跟单手数
input double             InpEA1Level3LotMultiplier = 1.0;        // 源EA1档位3手数倍数，倍数模式下生效
input double             InpEA1Level3StopLossPoints = 0.0;       // 源EA1档位3自定义止损点数，0=不设置
input double             InpEA1Level3TakeProfitPoints = 0.0;     // 源EA1档位3自定义止盈点数，0=不设置
input bool               InpEA1CopySourceSLTP    = false;        // 源EA1开仓时复制源单止损止盈，true时忽略各档位自定义SL/TP
input ENUM_PROFIT_CHECK_MODE InpEA1ProfitCheckMode = PROFIT_CHECK_ANYTIME; // 源EA1盈利平仓检查时机，默认随时检查
input bool               InpEA1MinuteProfitCloseEnabled = false; // 源EA1跟单启用单笔盈利平仓
input double             InpEA1MinuteProfitClosePoints  = 100.0; // 源EA1跟单盈利达到多少点后平仓
input int                InpEA1MinuteCloseStartSecond   = 57;    // 源EA1窗口检查起始秒，包含，仅按秒窗口检查时生效
input int                InpEA1MinuteCloseEndSecond     = 0;     // 源EA1窗口检查结束秒，不包含；57到0表示57~59秒
input bool               InpEA1BasketProfitCloseEnabled = false; // 源EA1启用跟单篮子整体盈利平仓
input double             InpEA1BasketProfitClosePoints  = 100.0; // 源EA1篮子均价盈利达到多少点后整篮子平仓
input int                InpEA1GridInitialMaxCopies = 1;         // 网格模式: 激活瞬间最多补跟已有源单数，0=不限制
input bool               InpEA1GridStopAfterBasketClose = true;  // 网格模式: 篮子提前平仓后本轮停止跟单

input group "源EA2设置"
input bool               InpEA2Enabled           = false;        // 启用源EA2
input long               InpEA2Magic             = 654321;       // 源EA2魔术号，-1表示不限制魔术号
input string             InpEA2CommentFilter     = "";           // 源EA2注释模糊匹配，空表示不限制
input string             InpEA2AllowedSymbols    = "";           // 源EA2允许品种，多个用;或,分隔，空表示全部
input ENUM_COPY_ENTRY_MODE InpEA2EntryMode       = ENTRY_MARKET_ON_TRIGGER; // 源EA2入场模式
input ENUM_LOSS_TRIGGER_MODE InpEA2LossMode      = LOSS_TRIGGER_PRICE; // 源EA2档位1浮亏触发模式
input double             InpEA2LossPrice         = 3.0;          // 源EA2档位1价格距离触发，黄金3.0=浮亏3美金
input double             InpEA2LossPoints        = 300.0;        // 源EA2档位1点数触发，黄金2位300=3.00，3位3000=3.000
input ENUM_COPY_LOT_MODE InpEA2LotMode           = COPY_LOT_FIXED; // 源EA2档位1跟单手数模式
input double             InpEA2FixedLot          = 0.01;         // 源EA2档位1固定跟单手数
input double             InpEA2LotMultiplier     = 1.0;          // 源EA2档位1手数倍数，倍数模式下生效
input double             InpEA2StopLossPoints    = 0.0;          // 源EA2档位1自定义止损点数，0=不设置
input double             InpEA2TakeProfitPoints  = 0.0;          // 源EA2档位1自定义止盈点数，0=不设置
input bool               InpEA2Level2Enabled     = false;        // 启用源EA2档位2
input ENUM_LOSS_TRIGGER_MODE InpEA2Level2LossMode = LOSS_TRIGGER_PRICE; // 源EA2档位2浮亏触发模式
input double             InpEA2Level2LossPrice   = 4.0;          // 源EA2档位2价格距离触发，黄金4.0=浮亏4美金
input double             InpEA2Level2LossPoints  = 400.0;        // 源EA2档位2点数触发，黄金2位400=4.00，3位4000=4.000
input ENUM_COPY_LOT_MODE InpEA2Level2LotMode     = COPY_LOT_FIXED; // 源EA2档位2跟单手数模式
input double             InpEA2Level2FixedLot    = 0.01;         // 源EA2档位2固定跟单手数
input double             InpEA2Level2LotMultiplier = 1.0;        // 源EA2档位2手数倍数，倍数模式下生效
input double             InpEA2Level2StopLossPoints = 0.0;       // 源EA2档位2自定义止损点数，0=不设置
input double             InpEA2Level2TakeProfitPoints = 0.0;     // 源EA2档位2自定义止盈点数，0=不设置
input bool               InpEA2Level3Enabled     = false;        // 启用源EA2档位3
input ENUM_LOSS_TRIGGER_MODE InpEA2Level3LossMode = LOSS_TRIGGER_PRICE; // 源EA2档位3浮亏触发模式
input double             InpEA2Level3LossPrice   = 5.0;          // 源EA2档位3价格距离触发，黄金5.0=浮亏5美金
input double             InpEA2Level3LossPoints  = 500.0;        // 源EA2档位3点数触发，黄金2位500=5.00，3位5000=5.000
input ENUM_COPY_LOT_MODE InpEA2Level3LotMode     = COPY_LOT_FIXED; // 源EA2档位3跟单手数模式
input double             InpEA2Level3FixedLot    = 0.01;         // 源EA2档位3固定跟单手数
input double             InpEA2Level3LotMultiplier = 1.0;        // 源EA2档位3手数倍数，倍数模式下生效
input double             InpEA2Level3StopLossPoints = 0.0;       // 源EA2档位3自定义止损点数，0=不设置
input double             InpEA2Level3TakeProfitPoints = 0.0;     // 源EA2档位3自定义止盈点数，0=不设置
input bool               InpEA2CopySourceSLTP    = false;        // 源EA2开仓时复制源单止损止盈，true时忽略各档位自定义SL/TP
input ENUM_PROFIT_CHECK_MODE InpEA2ProfitCheckMode = PROFIT_CHECK_ANYTIME; // 源EA2盈利平仓检查时机，默认随时检查
input bool               InpEA2MinuteProfitCloseEnabled = false; // 源EA2跟单启用单笔盈利平仓
input double             InpEA2MinuteProfitClosePoints  = 100.0; // 源EA2跟单盈利达到多少点后平仓
input int                InpEA2MinuteCloseStartSecond   = 57;    // 源EA2窗口检查起始秒，包含，仅按秒窗口检查时生效
input int                InpEA2MinuteCloseEndSecond     = 0;     // 源EA2窗口检查结束秒，不包含；57到0表示57~59秒
input bool               InpEA2BasketProfitCloseEnabled = false; // 源EA2启用跟单篮子整体盈利平仓
input double             InpEA2BasketProfitClosePoints  = 100.0; // 源EA2篮子均价盈利达到多少点后整篮子平仓
input int                InpEA2GridInitialMaxCopies = 1;         // 网格模式: 激活瞬间最多补跟已有源单数，0=不限制
input bool               InpEA2GridStopAfterBasketClose = true;  // 网格模式: 篮子提前平仓后本轮停止跟单

input group "跟单EA全局设置"
input ulong              InpCopyMagic            = 2026062301;   // 跟单EA魔术号，必须和源EA不同
input int                InpDeviationPoints      = 100;          // 允许滑点，单位为券商点数
input bool               InpCloseCopyWithSource  = true;         // 源单平仓后跟单一起市价平仓
input int                InpCloseRetrySeconds    = 3;            // 同一跟单平仓失败后的重试间隔秒数
input bool               InpOneCopyPerPosition   = true;         // 每个源单只跟一次
input int                InpScanIntervalMs       = 500;          // 轮询扫描间隔，单位毫秒
input bool               InpPrintDebug           = true;         // 打印调试日志

string g_prefix;
string g_snapshot_file;
RemoteSourcePosition g_sources[];
datetime g_snapshot_time = 0;
bool g_have_snapshot = false;
bool g_snapshot_fresh = false;

void LoadProfile(const int index, SourceProfile& profile)
{
   if(index == 1)
   {
      profile.profile_index = 1;
      profile.enabled = InpEA1Enabled;
      profile.magic = InpEA1Magic;
      profile.comment_filter = InpEA1CommentFilter;
      profile.allowed_symbols = InpEA1AllowedSymbols;
      profile.entry_mode = InpEA1EntryMode;
      profile.loss_trigger_mode = InpEA1LossMode;
      profile.loss_trigger_price = InpEA1LossPrice;
      profile.loss_trigger_points = InpEA1LossPoints;
      profile.lot_mode = InpEA1LotMode;
      profile.fixed_lot = InpEA1FixedLot;
      profile.lot_multiplier = InpEA1LotMultiplier;
      profile.stop_loss_points = InpEA1StopLossPoints;
      profile.take_profit_points = InpEA1TakeProfitPoints;
      profile.level2_enabled = InpEA1Level2Enabled;
      profile.level2_loss_trigger_mode = InpEA1Level2LossMode;
      profile.level2_loss_trigger_price = InpEA1Level2LossPrice;
      profile.level2_loss_trigger_points = InpEA1Level2LossPoints;
      profile.level2_lot_mode = InpEA1Level2LotMode;
      profile.level2_fixed_lot = InpEA1Level2FixedLot;
      profile.level2_lot_multiplier = InpEA1Level2LotMultiplier;
      profile.level2_stop_loss_points = InpEA1Level2StopLossPoints;
      profile.level2_take_profit_points = InpEA1Level2TakeProfitPoints;
      profile.level3_enabled = InpEA1Level3Enabled;
      profile.level3_loss_trigger_mode = InpEA1Level3LossMode;
      profile.level3_loss_trigger_price = InpEA1Level3LossPrice;
      profile.level3_loss_trigger_points = InpEA1Level3LossPoints;
      profile.level3_lot_mode = InpEA1Level3LotMode;
      profile.level3_fixed_lot = InpEA1Level3FixedLot;
      profile.level3_lot_multiplier = InpEA1Level3LotMultiplier;
      profile.level3_stop_loss_points = InpEA1Level3StopLossPoints;
      profile.level3_take_profit_points = InpEA1Level3TakeProfitPoints;
      profile.copy_source_sltp = InpEA1CopySourceSLTP;
      profile.profit_check_mode = InpEA1ProfitCheckMode;
      profile.minute_profit_close_enabled = InpEA1MinuteProfitCloseEnabled;
      profile.minute_profit_close_points = InpEA1MinuteProfitClosePoints;
      profile.minute_close_start_second = InpEA1MinuteCloseStartSecond;
      profile.minute_close_end_second = InpEA1MinuteCloseEndSecond;
      profile.basket_profit_close_enabled = InpEA1BasketProfitCloseEnabled;
      profile.basket_profit_close_points = InpEA1BasketProfitClosePoints;
      profile.grid_initial_max_copies = InpEA1GridInitialMaxCopies;
      profile.grid_stop_after_basket_close = InpEA1GridStopAfterBasketClose;
      return;
   }

   profile.profile_index = 2;
   profile.enabled = InpEA2Enabled;
   profile.magic = InpEA2Magic;
   profile.comment_filter = InpEA2CommentFilter;
   profile.allowed_symbols = InpEA2AllowedSymbols;
   profile.entry_mode = InpEA2EntryMode;
   profile.loss_trigger_mode = InpEA2LossMode;
   profile.loss_trigger_price = InpEA2LossPrice;
   profile.loss_trigger_points = InpEA2LossPoints;
   profile.lot_mode = InpEA2LotMode;
   profile.fixed_lot = InpEA2FixedLot;
   profile.lot_multiplier = InpEA2LotMultiplier;
   profile.stop_loss_points = InpEA2StopLossPoints;
   profile.take_profit_points = InpEA2TakeProfitPoints;
   profile.level2_enabled = InpEA2Level2Enabled;
   profile.level2_loss_trigger_mode = InpEA2Level2LossMode;
   profile.level2_loss_trigger_price = InpEA2Level2LossPrice;
   profile.level2_loss_trigger_points = InpEA2Level2LossPoints;
   profile.level2_lot_mode = InpEA2Level2LotMode;
   profile.level2_fixed_lot = InpEA2Level2FixedLot;
   profile.level2_lot_multiplier = InpEA2Level2LotMultiplier;
   profile.level2_stop_loss_points = InpEA2Level2StopLossPoints;
   profile.level2_take_profit_points = InpEA2Level2TakeProfitPoints;
   profile.level3_enabled = InpEA2Level3Enabled;
   profile.level3_loss_trigger_mode = InpEA2Level3LossMode;
   profile.level3_loss_trigger_price = InpEA2Level3LossPrice;
   profile.level3_loss_trigger_points = InpEA2Level3LossPoints;
   profile.level3_lot_mode = InpEA2Level3LotMode;
   profile.level3_fixed_lot = InpEA2Level3FixedLot;
   profile.level3_lot_multiplier = InpEA2Level3LotMultiplier;
   profile.level3_stop_loss_points = InpEA2Level3StopLossPoints;
   profile.level3_take_profit_points = InpEA2Level3TakeProfitPoints;
   profile.copy_source_sltp = InpEA2CopySourceSLTP;
   profile.profit_check_mode = InpEA2ProfitCheckMode;
   profile.minute_profit_close_enabled = InpEA2MinuteProfitCloseEnabled;
   profile.minute_profit_close_points = InpEA2MinuteProfitClosePoints;
   profile.minute_close_start_second = InpEA2MinuteCloseStartSecond;
   profile.minute_close_end_second = InpEA2MinuteCloseEndSecond;
   profile.basket_profit_close_enabled = InpEA2BasketProfitCloseEnabled;
   profile.basket_profit_close_points = InpEA2BasketProfitClosePoints;
   profile.grid_initial_max_copies = InpEA2GridInitialMaxCopies;
   profile.grid_stop_after_basket_close = InpEA2GridStopAfterBasketClose;
}

bool ValidateProfile(const int index, const SourceProfile& profile)
{
   if(!profile.enabled)
      return true;

   if(profile.loss_trigger_mode == LOSS_TRIGGER_POINTS && profile.loss_trigger_points <= 0.0)
   {
      PrintFormat("EA%d loss trigger points must be greater than 0.", index);
      return false;
   }

   if(profile.loss_trigger_mode == LOSS_TRIGGER_PRICE && profile.loss_trigger_price <= 0.0)
   {
      PrintFormat("EA%d loss trigger price must be greater than 0.", index);
      return false;
   }

   if(profile.lot_mode == COPY_LOT_FIXED && profile.fixed_lot <= 0.0)
   {
      PrintFormat("EA%d fixed lot must be greater than 0.", index);
      return false;
   }

   if(profile.lot_mode == COPY_LOT_MULTIPLIER && profile.lot_multiplier <= 0.0)
   {
      PrintFormat("EA%d lot multiplier must be greater than 0.", index);
      return false;
   }

   if(profile.stop_loss_points < 0.0 || profile.take_profit_points < 0.0)
   {
      PrintFormat("EA%d level 1 SL/TP points cannot be negative.", index);
      return false;
   }

   if(profile.level2_enabled)
   {
      if(profile.level2_loss_trigger_mode == LOSS_TRIGGER_POINTS && profile.level2_loss_trigger_points <= 0.0)
      {
         PrintFormat("EA%d level 2 loss trigger points must be greater than 0.", index);
         return false;
      }

      if(profile.level2_loss_trigger_mode == LOSS_TRIGGER_PRICE && profile.level2_loss_trigger_price <= 0.0)
      {
         PrintFormat("EA%d level 2 loss trigger price must be greater than 0.", index);
         return false;
      }

      if(profile.level2_lot_mode == COPY_LOT_FIXED && profile.level2_fixed_lot <= 0.0)
      {
         PrintFormat("EA%d level 2 fixed lot must be greater than 0.", index);
         return false;
      }

      if(profile.level2_lot_mode == COPY_LOT_MULTIPLIER && profile.level2_lot_multiplier <= 0.0)
      {
         PrintFormat("EA%d level 2 lot multiplier must be greater than 0.", index);
         return false;
      }

      if(profile.level2_stop_loss_points < 0.0 || profile.level2_take_profit_points < 0.0)
      {
         PrintFormat("EA%d level 2 SL/TP points cannot be negative.", index);
         return false;
      }
   }

   if(profile.level3_enabled)
   {
      if(profile.level3_loss_trigger_mode == LOSS_TRIGGER_POINTS && profile.level3_loss_trigger_points <= 0.0)
      {
         PrintFormat("EA%d level 3 loss trigger points must be greater than 0.", index);
         return false;
      }

      if(profile.level3_loss_trigger_mode == LOSS_TRIGGER_PRICE && profile.level3_loss_trigger_price <= 0.0)
      {
         PrintFormat("EA%d level 3 loss trigger price must be greater than 0.", index);
         return false;
      }

      if(profile.level3_lot_mode == COPY_LOT_FIXED && profile.level3_fixed_lot <= 0.0)
      {
         PrintFormat("EA%d level 3 fixed lot must be greater than 0.", index);
         return false;
      }

      if(profile.level3_lot_mode == COPY_LOT_MULTIPLIER && profile.level3_lot_multiplier <= 0.0)
      {
         PrintFormat("EA%d level 3 lot multiplier must be greater than 0.", index);
         return false;
      }

      if(profile.level3_stop_loss_points < 0.0 || profile.level3_take_profit_points < 0.0)
      {
         PrintFormat("EA%d level 3 SL/TP points cannot be negative.", index);
         return false;
      }
   }

   if(profile.magic >= 0 && (ulong)profile.magic == InpCopyMagic)
   {
      PrintFormat("EA%d source magic must be different from copy magic.", index);
      return false;
   }

   if(profile.minute_profit_close_enabled && profile.minute_profit_close_points <= 0.0)
   {
      PrintFormat("EA%d single profit close points must be greater than 0.", index);
      return false;
   }

   if(profile.basket_profit_close_enabled && profile.basket_profit_close_points <= 0.0)
   {
      PrintFormat("EA%d basket profit close points must be greater than 0.", index);
      return false;
   }

   if(profile.entry_mode == ENTRY_GRID_ACTIVATION)
   {
      if(profile.grid_initial_max_copies < 0)
      {
         PrintFormat("EA%d grid initial max copies cannot be negative.", index);
         return false;
      }

   }

   if((profile.minute_profit_close_enabled || profile.basket_profit_close_enabled) &&
      profile.profit_check_mode == PROFIT_CHECK_TIME_WINDOW &&
      (profile.minute_close_start_second < 0 || profile.minute_close_start_second > 59 ||
       profile.minute_close_end_second < 0 || profile.minute_close_end_second > 59))
   {
      PrintFormat("EA%d profit close window seconds must be in 0..59.", index);
      return false;
   }

   return true;
}

int OnInit()
{
   if(InpChannelName == "")
   {
      Print("InpChannelName cannot be empty.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpSourceStaleSeconds < 1)
   {
      Print("InpSourceStaleSeconds must be at least 1.");
      return INIT_PARAMETERS_INCORRECT;
   }

   SourceProfile profile;
   LoadProfile(1, profile);
   if(!ValidateProfile(1, profile))
      return INIT_PARAMETERS_INCORRECT;

   LoadProfile(2, profile);
   if(!ValidateProfile(2, profile))
      return INIT_PARAMETERS_INCORRECT;

   if(!InpEA1Enabled && !InpEA2Enabled)
   {
      Print("At least one source EA profile must be enabled.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpCloseRetrySeconds < 1)
   {
      Print("InpCloseRetrySeconds must be at least 1.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_snapshot_file = SnapshotFileName();
   g_prefix = "RLFC_" +
              IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
              SanitizeNamePart(InpChannelName) + "_";

   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("Warning: this EA is designed for hedging accounts. On netting accounts, source and copy positions may merge.");

   int timer_period = InpScanIntervalMs < 100 ? 100 : InpScanIntervalMs;
   EventSetMillisecondTimer((uint)timer_period);
   LoadRemoteSnapshot();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTick()
{
   CheckPositions();
}

void OnTimer()
{
   CheckPositions();
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(InpCloseCopyWithSource && LoadRemoteSnapshot())
   {
      CloseCopiesWithoutSource();
      DeletePendingsWithoutSource();
      ResetInactiveGridGroups();
   }
}

void CheckPositions()
{
   bool fresh = LoadRemoteSnapshot();

   if(InpCloseCopyWithSource && fresh)
   {
      CloseCopiesWithoutSource();
      DeletePendingsWithoutSource();
   }

   if(fresh)
      ResetInactiveGridGroups();

   CheckMinuteProfitClose();
   CheckBasketProfitClose();

   if(!fresh)
      return;

   CheckGridActivationEntries();

   int total = ArraySize(g_sources);
   for(int i = total - 1; i >= 0; i--)
   {
      RemoteSourcePosition source = g_sources[i];
      string symbol = source.symbol;
      string comment = source.comment;
      long magic = source.magic;

      SourceProfile profile;
      if(!MatchSourceProfile(symbol, magic, comment, profile))
         continue;

      if(profile.entry_mode == ENTRY_GRID_ACTIVATION)
         continue;

      ENUM_POSITION_TYPE position_type = source.position_type;
      if(position_type != POSITION_TYPE_BUY && position_type != POSITION_TYPE_SELL)
         continue;

      ProcessSourceLevel(source, profile, 1);
      ProcessSourceLevel(source, profile, 2);
      ProcessSourceLevel(source, profile, 3);
   }
}

void CheckGridActivationEntries()
{
   string processed_keys[];
   int total = ArraySize(g_sources);

   for(int i = total - 1; i >= 0; i--)
   {
      RemoteSourcePosition source = g_sources[i];
      string symbol = source.symbol;
      string comment = source.comment;
      SourceProfile profile;
      if(!MatchSourceProfile(symbol, source.magic, comment, profile))
         continue;

      if(profile.entry_mode != ENTRY_GRID_ACTIVATION)
         continue;

      ENUM_POSITION_TYPE position_type = source.position_type;
      if(position_type != POSITION_TYPE_BUY && position_type != POSITION_TYPE_SELL)
         continue;

      string key = BasketKey(profile.profile_index, symbol, position_type);
      if(IsStringInArray(processed_keys, key))
         continue;
      AddString(processed_keys, key);

      ProcessGridGroup(profile, symbol, position_type);
   }
}

void ProcessGridGroup(const SourceProfile& profile,
                      const string symbol,
                      const ENUM_POSITION_TYPE position_type)
{
   int source_count = 0;
   double source_volume = 0.0;
   double weighted_open = 0.0;
   if(!SourceGroupStats(profile, symbol, position_type, source_count, source_volume, weighted_open))
      return;

   if(IsGridGroupStopped(profile.profile_index, symbol, position_type))
      return;

   double avg_open = weighted_open / source_volume;
   double loss_points = FloatingLossPoints(symbol, position_type, avg_open);
   double loss_price = loss_points * SymbolInfoDouble(symbol, SYMBOL_POINT);
   bool active = IsGridGroupActive(profile.profile_index, symbol, position_type);
   bool triggered = IsLossTriggered(loss_points, loss_price, profile, 1);

   if(active)
   {
      int copy_count = CopyGroupCount(profile.profile_index, symbol, position_type);
      if(copy_count == 0 && !triggered)
      {
         ClearGridGroupActive(profile.profile_index, symbol, position_type);
         active = false;
      }
   }

   if(!active)
   {
      if(!triggered)
         return;

      SetGridGroupActive(profile.profile_index, symbol, position_type);
      if(InpPrintDebug)
      {
         PrintFormat("Grid activation triggered. profile=EA%d symbol=%s type=%s source_count=%d loss=%.1f points / %.5f price",
                     profile.profile_index,
                     symbol,
                     position_type == POSITION_TYPE_BUY ? "BUY" : "SELL",
                     source_count,
                     loss_points,
                     loss_price);
      }

      CopyGridSources(profile, symbol, position_type, true, loss_points, loss_price);
      return;
   }

   CopyGridSources(profile, symbol, position_type, false, loss_points, loss_price);
}

bool SourceGroupStats(const SourceProfile& profile,
                      const string symbol,
                      const ENUM_POSITION_TYPE position_type,
                      int& source_count,
                      double& total_volume,
                      double& weighted_open)
{
   source_count = 0;
   total_volume = 0.0;
   weighted_open = 0.0;

   int total = ArraySize(g_sources);
   for(int i = total - 1; i >= 0; i--)
   {
      RemoteSourcePosition source = g_sources[i];

      if(!IsSourcePositionForProfile(profile, source))
         continue;

      if(source.symbol != symbol)
         continue;

      if(source.position_type != position_type)
         continue;

      double volume = source.volume;
      if(volume <= 0.0)
         continue;

      source_count++;
      total_volume += volume;
      weighted_open += source.open_price * volume;
   }

   return source_count > 0 && total_volume > 0.0;
}

bool IsSourcePositionForProfile(const SourceProfile& profile, const RemoteSourcePosition& source)
{
   if(!IsAllowedSymbol(source.symbol, profile.allowed_symbols))
      return false;

   if(profile.magic >= 0 && source.magic != profile.magic)
      return false;

   if(profile.comment_filter != "" && StringFind(source.comment, profile.comment_filter) < 0)
      return false;

   return true;
}

void CopyGridSources(const SourceProfile& profile,
                     const string symbol,
                     const ENUM_POSITION_TYPE position_type,
                     const bool initial_activation,
                     const double group_loss_points,
                     const double group_loss_price)
{
   int copied_now = 0;
   int total = ArraySize(g_sources);

   for(int i = total - 1; i >= 0; i--)
   {
      RemoteSourcePosition source = g_sources[i];
      ulong source_ticket = source.source_id;

      if(!IsSourcePositionForProfile(profile, source))
         continue;

      if(source.symbol != symbol)
         continue;

      if(source.position_type != position_type)
         continue;

      if(IsAlreadyCopied(source_ticket, 1))
         continue;

      if(initial_activation && profile.grid_initial_max_copies > 0 && copied_now >= profile.grid_initial_max_copies)
         return;

      double source_volume = source.volume;
      double volume = CalculateCopyVolume(symbol, source_volume, profile, 1);
      if(volume <= 0.0)
         continue;

      double source_sl = source.sl;
      double source_tp = source.tp;
      if(OpenCopyTrade(source_ticket, symbol, position_type, volume, source_sl, source_tp, group_loss_points, group_loss_price, profile, 1))
      {
         MarkCopied(source_ticket, 1);
         copied_now++;
      }
   }
}

int CopyGroupCount(const int profile_index,
                   const string symbol,
                   const ENUM_POSITION_TYPE position_type)
{
   int copy_count = 0;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;

      SourceProfile profile;
      if(!SourceProfileByTicket(SourceTicketFromCurrentPosition(), profile))
         continue;

      if(profile.profile_index != profile_index)
         continue;

      if(!PositionSelectByTicket(copy_ticket))
         continue;

      copy_count++;
   }

   return copy_count;
}

void ProcessSourceLevel(const RemoteSourcePosition& source, const SourceProfile& profile, const int level_index)
{
   if(!IsLevelEnabled(profile, level_index))
      return;

   ulong source_ticket = source.source_id;
   if((profile.entry_mode == ENTRY_PENDING_AT_TRIGGER || InpOneCopyPerPosition) && IsAlreadyCopied(source_ticket, level_index))
      return;

   string symbol = source.symbol;
   ENUM_POSITION_TYPE position_type = source.position_type;
   if(position_type != POSITION_TYPE_BUY && position_type != POSITION_TYPE_SELL)
      return;

   double source_open_price = source.open_price;
   double loss_points = FloatingLossPoints(symbol, position_type, source_open_price);
   double loss_price = loss_points * SymbolInfoDouble(symbol, SYMBOL_POINT);

   double source_volume = source.volume;
   double volume = CalculateCopyVolume(symbol, source_volume, profile, level_index);
   if(volume <= 0.0)
   {
      PrintFormat("Skip source #%I64u L%d: calculated copy volume is invalid.", source_ticket, level_index);
      return;
   }

   double source_sl = source.sl;
   double source_tp = source.tp;

   if(profile.entry_mode == ENTRY_PENDING_AT_TRIGGER)
   {
      PlaceCopyPending(source_ticket, symbol, position_type, source_open_price, volume, source_sl, source_tp, profile, level_index);
      return;
   }

   if(!IsLossTriggered(loss_points, loss_price, profile, level_index))
      return;

   if(OpenCopyTrade(source_ticket, symbol, position_type, volume, source_sl, source_tp, loss_points, loss_price, profile, level_index))
      MarkCopied(source_ticket, level_index);
}

bool MatchSourceProfile(const string symbol, const long magic, const string comment, SourceProfile& profile)
{
   SourceProfile candidate;
   for(int i = 1; i <= 2; i++)
   {
      LoadProfile(i, candidate);
      if(!candidate.enabled)
         continue;

      if(!IsAllowedSymbol(symbol, candidate.allowed_symbols))
         continue;

      if(candidate.magic >= 0 && magic != candidate.magic)
         continue;

      if(candidate.comment_filter != "" && StringFind(comment, candidate.comment_filter) < 0)
         continue;

      profile = candidate;
      return true;
   }

   return false;
}

bool IsLevelEnabled(const SourceProfile& profile, const int level_index)
{
   if(level_index == 1)
      return true;

   if(level_index == 2)
      return profile.level2_enabled;

   return profile.level3_enabled;
}

ENUM_LOSS_TRIGGER_MODE LevelLossMode(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_loss_trigger_mode;

   return level_index == 2 ? profile.level2_loss_trigger_mode : profile.loss_trigger_mode;
}

double LevelLossPrice(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_loss_trigger_price;

   return level_index == 2 ? profile.level2_loss_trigger_price : profile.loss_trigger_price;
}

double LevelLossPoints(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_loss_trigger_points;

   return level_index == 2 ? profile.level2_loss_trigger_points : profile.loss_trigger_points;
}

ENUM_COPY_LOT_MODE LevelLotMode(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_lot_mode;

   return level_index == 2 ? profile.level2_lot_mode : profile.lot_mode;
}

double LevelFixedLot(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_fixed_lot;

   return level_index == 2 ? profile.level2_fixed_lot : profile.fixed_lot;
}

double LevelLotMultiplier(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_lot_multiplier;

   return level_index == 2 ? profile.level2_lot_multiplier : profile.lot_multiplier;
}

double LevelStopLossPoints(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_stop_loss_points;

   return level_index == 2 ? profile.level2_stop_loss_points : profile.stop_loss_points;
}

double LevelTakeProfitPoints(const SourceProfile& profile, const int level_index)
{
   if(level_index == 3)
      return profile.level3_take_profit_points;

   return level_index == 2 ? profile.level2_take_profit_points : profile.take_profit_points;
}

bool IsLossTriggered(const double loss_points, const double loss_price, const SourceProfile& profile, const int level_index)
{
   if(LevelLossMode(profile, level_index) == LOSS_TRIGGER_PRICE)
      return loss_price >= LevelLossPrice(profile, level_index);

   return loss_points >= LevelLossPoints(profile, level_index);
}

void CheckMinuteProfitClose()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      ulong source_ticket = SourceTicketFromCurrentPosition();
      if(source_ticket == 0)
         continue;

      SourceProfile profile;
      if(!SourceProfileByTicket(source_ticket, profile))
         continue;

      if(!profile.minute_profit_close_enabled)
         continue;

      if(!ShouldCheckProfitClose(profile))
         continue;

      if(!PositionSelectByTicket(copy_ticket))
         continue;

      if(IsCloseRetryCoolingDown(copy_ticket))
         continue;

      double profit_points = FloatingProfitPoints(PositionGetString(POSITION_SYMBOL),
                                                  (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE),
                                                  PositionGetDouble(POSITION_PRICE_OPEN));
      if(profit_points < profile.minute_profit_close_points)
         continue;

      if(InpPrintDebug)
      {
         PrintFormat("Single profit close triggered. copy=%I64u source=%I64u profit=%.1f points threshold=%.1f",
                     copy_ticket, source_ticket, profit_points, profile.minute_profit_close_points);
      }

      CloseCopyPosition(copy_ticket, source_ticket);
   }
}

bool IsInMinuteCloseWindow(const SourceProfile& profile)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int start_second = profile.minute_close_start_second;
   int end_second = profile.minute_close_end_second;

   if(start_second == end_second)
      return true;

   if(start_second < end_second)
      return now.sec >= start_second && now.sec < end_second;

   return now.sec >= start_second || now.sec < end_second;
}

bool ShouldCheckProfitClose(const SourceProfile& profile)
{
   if(profile.profit_check_mode == PROFIT_CHECK_ANYTIME)
      return true;

   return IsInMinuteCloseWindow(profile);
}

void CheckBasketProfitClose()
{
   int total = PositionsTotal();
   string processed_keys[];

   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      ulong source_ticket = SourceTicketFromCurrentPosition();
      if(source_ticket == 0)
         continue;

      SourceProfile profile;
      if(!SourceProfileByTicket(source_ticket, profile))
         continue;

      if(!profile.basket_profit_close_enabled)
         continue;

      if(!ShouldCheckProfitClose(profile))
         continue;

      if(!PositionSelectByTicket(copy_ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string key = BasketKey(profile.profile_index, symbol, position_type);
      if(IsStringInArray(processed_keys, key))
         continue;
      AddString(processed_keys, key);

      double basket_points = BasketProfitPoints(profile.profile_index, symbol, position_type);
      if(basket_points < profile.basket_profit_close_points)
         continue;

      if(InpPrintDebug)
      {
         PrintFormat("Basket profit close triggered. profile=EA%d symbol=%s type=%s profit=%.1f points threshold=%.1f",
                     profile.profile_index,
                     symbol,
                     position_type == POSITION_TYPE_BUY ? "BUY" : "SELL",
                     basket_points,
                     profile.basket_profit_close_points);
      }

      if(profile.entry_mode == ENTRY_GRID_ACTIVATION && profile.grid_stop_after_basket_close)
         SetGridGroupStopped(profile.profile_index, symbol, position_type);

      CloseBasketPositions(profile.profile_index, symbol, position_type);
   }
}

double BasketProfitPoints(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   double total_volume = 0.0;
   double weighted_open = 0.0;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;

      SourceProfile profile;
      if(!SourceProfileByTicket(SourceTicketFromCurrentPosition(), profile))
         continue;

      if(profile.profile_index != profile_index)
         continue;

      if(!PositionSelectByTicket(copy_ticket))
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);
      total_volume += volume;
      weighted_open += PositionGetDouble(POSITION_PRICE_OPEN) * volume;
   }

   if(total_volume <= 0.0)
      return 0.0;

   double avg_open = weighted_open / total_volume;
   return FloatingProfitPoints(symbol, position_type, avg_open);
}

void CloseBasketPositions(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != position_type)
         continue;

      ulong source_ticket = SourceTicketFromCurrentPosition();
      SourceProfile profile;
      if(!SourceProfileByTicket(source_ticket, profile))
         continue;

      if(profile.profile_index != profile_index)
         continue;

      if(!PositionSelectByTicket(copy_ticket))
         continue;

      if(IsCloseRetryCoolingDown(copy_ticket))
         continue;

      CloseCopyPosition(copy_ticket, source_ticket);
   }
}

bool SourceProfileByTicket(const ulong source_ticket, SourceProfile& profile)
{
   RemoteSourcePosition source;
   if(!RemoteSourceById(source_ticket, source))
      return false;

   return MatchSourceProfile(source.symbol,
                             source.magic,
                             source.comment,
                             profile);
}

string BasketKey(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   return IntegerToString(profile_index) + "|" + symbol + "|" + IntegerToString((int)position_type);
}

string GridStatePrefix(const string state)
{
   return g_prefix + "GRID_" + state + "_" + IntegerToString((long)InpCopyMagic) + "_";
}

string GridGroupStateName(const string state,
                          const int profile_index,
                          const string symbol,
                          const ENUM_POSITION_TYPE position_type)
{
   return GridStatePrefix(state) +
          IntegerToString(profile_index) + "_" +
          IntegerToString((int)position_type) + "_" +
          symbol;
}

bool IsGridGroupActive(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   return GlobalVariableCheck(GridGroupStateName("A", profile_index, symbol, position_type));
}

bool IsGridGroupStopped(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   return GlobalVariableCheck(GridGroupStateName("S", profile_index, symbol, position_type));
}

void SetGridGroupActive(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   GlobalVariableSet(GridGroupStateName("A", profile_index, symbol, position_type), (double)TimeCurrent());
}

void ClearGridGroupActive(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   GlobalVariableDel(GridGroupStateName("A", profile_index, symbol, position_type));
}

void SetGridGroupStopped(const int profile_index, const string symbol, const ENUM_POSITION_TYPE position_type)
{
   GlobalVariableSet(GridGroupStateName("S", profile_index, symbol, position_type), (double)TimeCurrent());
}

bool ParseGridStateName(const string name,
                        int& profile_index,
                        string& symbol,
                        ENUM_POSITION_TYPE& position_type)
{
   string active_prefix = GridStatePrefix("A");
   string stopped_prefix = GridStatePrefix("S");
   string prefix = "";

   if(StringFind(name, active_prefix) == 0)
      prefix = active_prefix;
   else if(StringFind(name, stopped_prefix) == 0)
      prefix = stopped_prefix;
   else
      return false;

   string tail = StringSubstr(name, StringLen(prefix));
   string parts[];
   int count = StringSplit(tail, '_', parts);
   if(count < 3)
      return false;

   profile_index = (int)StringToInteger(parts[0]);
   position_type = (ENUM_POSITION_TYPE)StringToInteger(parts[1]);
   symbol = parts[2];
   for(int i = 3; i < count; i++)
      symbol += "_" + parts[i];

   return profile_index > 0 && symbol != "";
}

void ResetInactiveGridGroups()
{
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      int profile_index = 0;
      string symbol = "";
      ENUM_POSITION_TYPE position_type = POSITION_TYPE_BUY;
      if(!ParseGridStateName(name, profile_index, symbol, position_type))
         continue;

      if(profile_index < 1 || profile_index > 2)
      {
         GlobalVariableDel(name);
         continue;
      }

      SourceProfile profile;
      LoadProfile(profile_index, profile);
      int source_count = 0;
      double source_volume = 0.0;
      double weighted_open = 0.0;
      if(profile.enabled &&
         profile.entry_mode == ENTRY_GRID_ACTIVATION &&
         SourceGroupStats(profile, symbol, position_type, source_count, source_volume, weighted_open))
         continue;

      GlobalVariableDel(GridGroupStateName("A", profile_index, symbol, position_type));
      GlobalVariableDel(GridGroupStateName("S", profile_index, symbol, position_type));
   }
}

bool IsStringInArray(const string &values[], const string value)
{
   int total = ArraySize(values);
   for(int i = 0; i < total; i++)
   {
      if(values[i] == value)
         return true;
   }

   return false;
}

void AddString(string &values[], const string value)
{
   int total = ArraySize(values);
   ArrayResize(values, total + 1);
   values[total] = value;
}

void CloseCopiesWithoutSource()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      ulong source_ticket = SourceTicketFromCurrentPosition();
      if(source_ticket == 0)
         continue;

      if(RemoteSourceExists(source_ticket))
         continue;

      if(IsCloseRetryCoolingDown(copy_ticket))
         continue;

      CloseCopyPosition(copy_ticket, source_ticket);
   }
}

void DeletePendingsWithoutSource()
{
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong order_ticket = OrderGetTicket(i);
      if(order_ticket == 0 || !OrderSelect(order_ticket))
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpCopyMagic)
         continue;

      ulong source_ticket = SourceTicketFromComment(OrderGetString(ORDER_COMMENT));
      if(source_ticket == 0)
         continue;

      if(RemoteSourceExists(source_ticket))
         continue;

      DeleteCopyPending(order_ticket, source_ticket);
   }
}

// TODO: Sync partial source closes by reducing the copy position proportionally.

ulong SourceTicketFromComment(const string comment)
{
   string prefix = "RLFC:";
   if(StringSubstr(comment, 0, StringLen(prefix)) != prefix)
      return 0;

   string tail = StringSubstr(comment, StringLen(prefix));
   int colon_pos = StringFind(tail, ":");
   if(colon_pos >= 0)
      tail = StringSubstr(tail, 0, colon_pos);

   return (ulong)StringToInteger(tail);
}

int CopyLevelFromComment(const string comment)
{
   string prefix = "RLFC:";
   if(StringSubstr(comment, 0, StringLen(prefix)) != prefix)
      return 0;

   int colon_pos = StringFind(comment, ":", StringLen(prefix));
   if(colon_pos < 0)
      return 1;

   string level_text = StringSubstr(comment, colon_pos + 1);
   if(StringSubstr(level_text, 0, 1) == "L")
      level_text = StringSubstr(level_text, 1);

   int level_index = (int)StringToInteger(level_text);
   return level_index > 0 ? level_index : 0;
}

bool IsCopyComment(const string comment)
{
   return SourceTicketFromComment(comment) != 0;
}

ulong CurrentPositionIdentifier()
{
   long identifier = PositionGetInteger(POSITION_IDENTIFIER);
   if(identifier > 0)
      return (ulong)identifier;

   return (ulong)PositionGetInteger(POSITION_TICKET);
}

string CopyPositionSourceMapName(const ulong position_identifier)
{
   return g_prefix + "P_SRC_" + IntegerToString((long)InpCopyMagic) + "_" + IntegerToString((long)position_identifier);
}

string CopyPositionLevelMapName(const ulong position_identifier)
{
   return g_prefix + "P_LVL_" + IntegerToString((long)InpCopyMagic) + "_" + IntegerToString((long)position_identifier);
}

void RememberCopyPositionMapping(const ulong source_ticket, const int level_index)
{
   if(source_ticket == 0)
      return;

   ulong position_identifier = CurrentPositionIdentifier();
   if(position_identifier == 0)
      return;

   GlobalVariableSet(CopyPositionSourceMapName(position_identifier), (double)source_ticket);
   if(level_index > 0)
      GlobalVariableSet(CopyPositionLevelMapName(position_identifier), (double)level_index);
}

ulong SourceTicketFromCurrentPosition()
{
   string comment = PositionGetString(POSITION_COMMENT);
   ulong source_ticket = SourceTicketFromComment(comment);
   if(source_ticket != 0)
   {
      RememberCopyPositionMapping(source_ticket, CopyLevelFromComment(comment));
      return source_ticket;
   }

   ulong position_identifier = CurrentPositionIdentifier();
   if(position_identifier == 0)
      return 0;

   string gv_name = CopyPositionSourceMapName(position_identifier);
   if(!GlobalVariableCheck(gv_name))
      return 0;

   return (ulong)GlobalVariableGet(gv_name);
}

int CopyLevelFromCurrentPosition()
{
   string comment = PositionGetString(POSITION_COMMENT);
   int level_index = CopyLevelFromComment(comment);
   if(level_index > 0)
      return level_index;

   ulong position_identifier = CurrentPositionIdentifier();
   if(position_identifier == 0)
      return 0;

   string gv_name = CopyPositionLevelMapName(position_identifier);
   if(!GlobalVariableCheck(gv_name))
      return 0;

   return (int)GlobalVariableGet(gv_name);
}

bool IsCopyPosition()
{
   if(SourceTicketFromCurrentPosition() == 0)
      return false;

   // 手动部分平仓后，部分券商/终端可能让剩余仓位的magic或注释变化。
   // 有本地映射且magic为0时也按本EA跟单仓处理；其他非0 magic不接管。
   long magic = PositionGetInteger(POSITION_MAGIC);
   return (ulong)magic == InpCopyMagic || magic == 0;
}

double FloatingLossPoints(const string symbol, const ENUM_POSITION_TYPE position_type, const double open_price)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(position_type == POSITION_TYPE_BUY)
      return MathMax(0.0, (open_price - bid) / point);

   return MathMax(0.0, (ask - open_price) / point);
}

double FloatingProfitPoints(const string symbol, const ENUM_POSITION_TYPE position_type, const double open_price)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(position_type == POSITION_TYPE_BUY)
      return MathMax(0.0, (bid - open_price) / point);

   return MathMax(0.0, (open_price - ask) / point);
}

double CalculateCopyVolume(const string symbol, const double source_volume, const SourceProfile& profile, const int level_index)
{
   double raw_volume = LevelFixedLot(profile, level_index);

   if(LevelLotMode(profile, level_index) == COPY_LOT_SOURCE)
      raw_volume = source_volume;
   else if(LevelLotMode(profile, level_index) == COPY_LOT_MULTIPLIER)
      raw_volume = source_volume * LevelLotMultiplier(profile, level_index);

   return NormalizeVolume(symbol, raw_volume);
}

double NormalizeVolume(const string symbol, const double volume)
{
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || min_volume <= 0.0 || max_volume <= 0.0)
      return 0.0;

   double clipped = MathMin(MathMax(volume, min_volume), max_volume);
   double steps = MathFloor((clipped - min_volume) / step + 0.00000001);
   double normalized = min_volume + steps * step;

   return NormalizeDouble(normalized, VolumeDigits(step));
}

int VolumeDigits(double step)
{
   int digits = 0;
   while(digits < 8 && MathAbs(step - MathRound(step)) > 0.00000001)
   {
      step *= 10.0;
      digits++;
   }
   return digits;
}

bool PlaceCopyPending(const ulong source_ticket,
                      const string symbol,
                      const ENUM_POSITION_TYPE position_type,
                      const double source_open_price,
                      const double volume,
                      const double source_sl,
                      const double source_tp,
                      const SourceProfile& profile,
                      const int level_index)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double trigger_distance = TriggerDistancePrice(symbol, profile, level_index);
   if(trigger_distance <= 0.0 || point <= 0.0)
      return false;

   double trigger_price = position_type == POSITION_TYPE_BUY
                          ? source_open_price - trigger_distance
                          : source_open_price + trigger_distance;
   trigger_price = NormalizeDouble(trigger_price, digits);

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if((position_type == POSITION_TYPE_BUY && trigger_price >= ask) ||
      (position_type == POSITION_TYPE_SELL && trigger_price <= bid))
   {
      double loss_points = FloatingLossPoints(symbol, position_type, source_open_price);
      double loss_price = loss_points * point;
      if(OpenCopyTrade(source_ticket, symbol, position_type, volume, source_sl, source_tp, loss_points, loss_price, profile, level_index))
         MarkCopied(source_ticket, level_index);
      return true;
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = symbol;
   request.volume = volume;
   request.type = position_type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   request.price = trigger_price;
   request.deviation = InpDeviationPoints;
   request.magic = InpCopyMagic;
   request.comment = CopyComment(source_ticket, level_index);
   request.type_time = ORDER_TIME_GTC;
   request.type_filling = GetFillingType(symbol);

   ApplyStops(request, position_type, trigger_price, source_sl, source_tp, point, digits, profile, level_index);

   ResetLastError();
   bool sent = OrderSend(request, result);
   if(!sent || !IsSuccessRetcode(result.retcode))
   {
      PrintFormat("Pending copy failed. source=%I64u symbol=%s volume=%.8f price=%.5f retcode=%u last_error=%d comment=%s",
                  source_ticket, symbol, volume, trigger_price, result.retcode, GetLastError(), result.comment);
      return false;
   }

   if(InpPrintDebug)
   {
      PrintFormat("Pending copy placed. source=%I64u level=L%d order=%I64u symbol=%s type=%s volume=%.8f source_open=%.5f distance=%.5f trigger=%.5f",
                  source_ticket,
                  level_index,
                  result.order,
                  symbol,
                  position_type == POSITION_TYPE_BUY ? "BUY_LIMIT" : "SELL_LIMIT",
                  volume,
                  source_open_price,
                  trigger_distance,
                  trigger_price);
   }

   return true;
}

double TriggerDistancePrice(const string symbol, const SourceProfile& profile, const int level_index)
{
   if(LevelLossMode(profile, level_index) == LOSS_TRIGGER_PRICE)
      return LevelLossPrice(profile, level_index);

   return LevelLossPoints(profile, level_index) * SymbolInfoDouble(symbol, SYMBOL_POINT);
}

void ApplyStops(MqlTradeRequest& request,
                const ENUM_POSITION_TYPE position_type,
                const double entry_price,
                const double source_sl,
                const double source_tp,
                const double point,
                const int digits,
                const SourceProfile& profile,
                const int level_index)
{
   if(profile.copy_source_sltp)
   {
      request.sl = source_sl > 0.0 ? NormalizeDouble(source_sl, digits) : 0.0;
      request.tp = source_tp > 0.0 ? NormalizeDouble(source_tp, digits) : 0.0;
      return;
   }

   double stop_loss_points = LevelStopLossPoints(profile, level_index);
   double take_profit_points = LevelTakeProfitPoints(profile, level_index);

   if(stop_loss_points > 0.0)
   {
      double sl = position_type == POSITION_TYPE_BUY
                  ? entry_price - stop_loss_points * point
                  : entry_price + stop_loss_points * point;
      request.sl = NormalizeDouble(sl, digits);
   }

   if(take_profit_points > 0.0)
   {
      double tp = position_type == POSITION_TYPE_BUY
                  ? entry_price + take_profit_points * point
                  : entry_price - take_profit_points * point;
      request.tp = NormalizeDouble(tp, digits);
   }
}

bool OpenCopyTrade(const ulong source_ticket,
                   const string symbol,
                   const ENUM_POSITION_TYPE position_type,
                   const double volume,
                   const double source_sl,
                   const double source_tp,
                   const double loss_points,
                   const double loss_price,
                   const SourceProfile& profile,
                   const int level_index)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double price = position_type == POSITION_TYPE_BUY ? ask : bid;

   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = volume;
   request.type = position_type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = NormalizeDouble(price, digits);
   request.deviation = InpDeviationPoints;
   request.magic = InpCopyMagic;
   request.comment = CopyComment(source_ticket, level_index);
   request.type_time = ORDER_TIME_GTC;
   request.type_filling = GetFillingType(symbol);

   ApplyStops(request, position_type, request.price, source_sl, source_tp, point, digits, profile, level_index);

   ResetLastError();
   bool sent = OrderSend(request, result);
   if(!sent || !IsSuccessRetcode(result.retcode))
   {
      PrintFormat("Copy failed. source=%I64u symbol=%s volume=%.8f retcode=%u last_error=%d comment=%s",
                  source_ticket, symbol, volume, result.retcode, GetLastError(), result.comment);
      return false;
   }

   if(InpPrintDebug)
   {
      PrintFormat("Copy opened. source=%I64u level=L%d order=%I64u deal=%I64u symbol=%s type=%s volume=%.8f source_loss=%.1f points / %.5f price",
                  source_ticket,
                  level_index,
                  result.order,
                  result.deal,
                  symbol,
                  position_type == POSITION_TYPE_BUY ? "BUY" : "SELL",
                  volume,
                  loss_points,
                  loss_price);
   }

   return true;
}

bool DeleteCopyPending(const ulong order_ticket, const ulong source_ticket)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_REMOVE;
   request.order = order_ticket;
   request.magic = InpCopyMagic;
   request.comment = "RLFC remove:" + IntegerToString((long)source_ticket);

   ResetLastError();
   bool sent = OrderSend(request, result);
   if(!sent || !IsSuccessRetcode(result.retcode))
   {
      PrintFormat("Delete pending failed. order=%I64u source=%I64u retcode=%u last_error=%d comment=%s",
                  order_ticket, source_ticket, result.retcode, GetLastError(), result.comment);
      return false;
   }

   if(InpPrintDebug)
      PrintFormat("Pending copy deleted with source. order=%I64u source=%I64u", order_ticket, source_ticket);

   return true;
}

bool CloseCopyPosition(const ulong copy_ticket, const ulong source_ticket)
{
   if(!PositionSelectByTicket(copy_ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double price = position_type == POSITION_TYPE_BUY ? bid : ask;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = copy_ticket;
   request.symbol = symbol;
   request.volume = volume;
   request.type = position_type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = NormalizeDouble(price, digits);
   request.deviation = InpDeviationPoints;
   request.magic = InpCopyMagic;
   request.comment = "RLFC close:" + IntegerToString((long)source_ticket);
   request.type_time = ORDER_TIME_GTC;
   request.type_filling = GetFillingType(symbol);

   MarkCloseAttempt(copy_ticket);
   ResetLastError();
   bool sent = OrderSend(request, result);
   if(!sent || !IsSuccessRetcode(result.retcode))
   {
      PrintFormat("Close copy failed. copy=%I64u source=%I64u symbol=%s volume=%.8f retcode=%u last_error=%d comment=%s",
                  copy_ticket, source_ticket, symbol, volume, result.retcode, GetLastError(), result.comment);
      return false;
   }

   if(InpPrintDebug)
   {
      PrintFormat("Copy closed with source. copy=%I64u source=%I64u order=%I64u deal=%I64u symbol=%s volume=%.8f",
                  copy_ticket, source_ticket, result.order, result.deal, symbol, volume);
   }

   return true;
}

bool IsCloseRetryCoolingDown(const ulong copy_ticket)
{
   string gv_name = CloseAttemptGlobalName(copy_ticket);
   if(!GlobalVariableCheck(gv_name))
      return false;

   datetime last_attempt = (datetime)GlobalVariableGet(gv_name);
   return (TimeCurrent() - last_attempt) < InpCloseRetrySeconds;
}

void MarkCloseAttempt(const ulong copy_ticket)
{
   GlobalVariableSet(CloseAttemptGlobalName(copy_ticket), (double)TimeCurrent());
}

string CloseAttemptGlobalName(const ulong copy_ticket)
{
   return g_prefix + "CLOSING_" + IntegerToString((long)InpCopyMagic) + "_" + IntegerToString((long)copy_ticket);
}

ENUM_ORDER_TYPE_FILLING GetFillingType(const string symbol)
{
   int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

bool IsSuccessRetcode(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL ||
          retcode == TRADE_RETCODE_PLACED;
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

string CopyComment(const ulong source_ticket, const int level_index)
{
   return "RLFC:" + IntegerToString((long)source_ticket) + ":L" + IntegerToString(level_index);
}

string CopyGlobalName(const ulong source_ticket, const int level_index)
{
   return g_prefix + IntegerToString((long)InpCopyMagic) + "_" + IntegerToString((long)source_ticket) + "_L" + IntegerToString(level_index);
}

bool IsAlreadyCopied(const ulong source_ticket, const int level_index)
{
   string gv_name = CopyGlobalName(source_ticket, level_index);
   if(GlobalVariableCheck(gv_name))
      return true;

   string expected_comment = CopyComment(source_ticket, level_index);
   string legacy_comment = "RLFC:" + IntegerToString((long)source_ticket);
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsCopyPosition())
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(comment == expected_comment || (level_index == 1 && comment == legacy_comment))
         return true;

      if(SourceTicketFromCurrentPosition() == source_ticket && CopyLevelFromCurrentPosition() == level_index)
         return true;
   }

   int orders_total = OrdersTotal();
   for(int i = orders_total - 1; i >= 0; i--)
   {
      ulong order_ticket = OrderGetTicket(i);
      if(order_ticket == 0 || !OrderSelect(order_ticket))
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpCopyMagic)
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(comment == expected_comment || (level_index == 1 && comment == legacy_comment))
         return true;
   }

   return false;
}

void MarkCopied(const ulong source_ticket, const int level_index)
{
   GlobalVariableSet(CopyGlobalName(source_ticket, level_index), (double)TimeCurrent());
}

bool LoadRemoteSnapshot()
{
   RemoteSourcePosition loaded[];
   datetime snapshot_time = 0;
   bool complete = false;

   int handle = FileOpen(g_snapshot_file,
                         FILE_READ | FILE_CSV | FILE_COMMON | FILE_UNICODE,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      g_snapshot_fresh = false;
      if(InpPrintDebug)
         PrintFormat("Remote snapshot not readable. file=%s error=%d", g_snapshot_file, GetLastError());
      return false;
   }

   while(!FileIsEnding(handle))
   {
      string tag = FileReadString(handle);
      if(tag == "")
         continue;

      if(tag == "META")
      {
         string version = FileReadString(handle);
         string channel = FileReadString(handle);
         string login_text = FileReadString(handle);
         string server = FileReadString(handle);
         string time_text = FileReadString(handle);
         snapshot_time = (datetime)StringToInteger(time_text);
         if(version != "RLFC1" || channel != InpChannelName)
         {
            FileClose(handle);
            g_snapshot_fresh = false;
            return false;
         }
         continue;
      }

      if(tag == "P")
      {
         RemoteSourcePosition source;
         source.source_id = (ulong)StringToInteger(FileReadString(handle));
         source.ticket = (ulong)StringToInteger(FileReadString(handle));
         source.symbol = FileReadString(handle);
         source.position_type = (ENUM_POSITION_TYPE)StringToInteger(FileReadString(handle));
         source.magic = (long)StringToInteger(FileReadString(handle));
         source.comment = FileReadString(handle);
         source.volume = StringToDouble(FileReadString(handle));
         source.open_price = StringToDouble(FileReadString(handle));
         source.sl = StringToDouble(FileReadString(handle));
         source.tp = StringToDouble(FileReadString(handle));
         source.open_time = (datetime)StringToInteger(FileReadString(handle));

         if(source.source_id != 0 &&
            source.symbol != "" &&
            source.volume > 0.0 &&
            (source.position_type == POSITION_TYPE_BUY || source.position_type == POSITION_TYPE_SELL))
         {
            int count = ArraySize(loaded);
            ArrayResize(loaded, count + 1);
            loaded[count] = source;
         }
         continue;
      }

      if(tag == "END")
      {
         string count_text = FileReadString(handle);
         string end_time_text = FileReadString(handle);
         if(snapshot_time == 0)
            snapshot_time = (datetime)StringToInteger(end_time_text);
         complete = true;
         break;
      }
   }

   FileClose(handle);

   if(!complete || snapshot_time <= 0)
   {
      g_snapshot_fresh = false;
      return false;
   }

   ArrayResize(g_sources, ArraySize(loaded));
   for(int i = 0; i < ArraySize(loaded); i++)
      g_sources[i] = loaded[i];

   g_snapshot_time = snapshot_time;
   g_have_snapshot = true;
   g_snapshot_fresh = (TimeCurrent() - g_snapshot_time) <= InpSourceStaleSeconds;

   if(InpPrintDebug && !g_snapshot_fresh)
   {
      PrintFormat("Remote snapshot is stale. file=%s age=%d seconds limit=%d",
                  g_snapshot_file,
                  (int)(TimeCurrent() - g_snapshot_time),
                  InpSourceStaleSeconds);
   }

   return g_snapshot_fresh;
}

bool RemoteSourceById(const ulong source_id, RemoteSourcePosition& source)
{
   int total = ArraySize(g_sources);
   for(int i = 0; i < total; i++)
   {
      if(g_sources[i].source_id == source_id)
      {
         source = g_sources[i];
         return true;
      }
   }

   return false;
}

bool RemoteSourceExists(const ulong source_id)
{
   RemoteSourcePosition source;
   return RemoteSourceById(source_id, source);
}

string SnapshotFileName()
{
   return "RemoteLossFollow_" + SanitizeNamePart(InpChannelName) + ".tsv";
}

string SanitizeNamePart(string value)
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
