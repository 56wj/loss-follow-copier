//+------------------------------------------------------------------+
//|                                            FileLossFollow.mq5    |
//|  Sender/Receiver roles over MT5 FILE_COMMON, no DLL required.    |
//|  One EA file; role is selected from inputs.                     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "本机文件浮亏跟单：统一角色切换，Receiver内嵌控制面板。"

enum ENUM_FILE_FOLLOW_ROLE
{
   FILE_FOLLOW_SENDER = 0,   // 源账号终端：写入FILE_COMMON快照
   FILE_FOLLOW_RECEIVER = 1  // 跟单账号终端：读取快照并执行跟单
};

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

struct FileSourcePosition
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

input group "运行角色"
input ENUM_FILE_FOLLOW_ROLE InpFileRole          = FILE_FOLLOW_RECEIVER; // Sender或Receiver

input group "公共文件通道"
input string             InpChannelName          = "loss_follow_file_1"; // 两个终端必须一致

input group "发送端设置（仅Sender角色）"
input string             InpSenderAllowedSymbols = "";                    // 发布品种，空表示全部
input int                InpSenderScanIntervalMs = 50;                    // 建议50毫秒；最低20毫秒
input bool               InpSenderPauseWhenAutoTradingOff = true;         // 自动交易关闭时发布暂停状态

input group "接收端设置（仅Receiver角色）"
input int                InpSourceStaleSeconds   = 10;                    // 快照超时后停止新开单及同步平仓

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
input ulong              InpCopyMagic            = 2026062303;   // 跟单EA魔术号，必须和源EA不同
input int                InpDeviationPoints      = 100;          // 允许滑点，单位为券商点数
input string             InpSymbolMap            = "";           // 品种映射，源=跟单；多个用;分隔，例如 XAUUSD=XAUUSDm
input bool               InpCloseCopyWithSource  = true;         // 源单平仓后跟单一起市价平仓
input int                InpCloseRetrySeconds    = 3;            // 同一跟单平仓失败后的重试间隔秒数
input bool               InpOneCopyPerPosition   = true;         // 每个源单只跟一次
input int                InpScanIntervalMs       = 50;           // 本机双MT5建议50毫秒；最低20毫秒
input bool               InpBeijingFirstEntryTimeFilterEnabled = false; // 启用跟单首单北京时间过滤
input string             InpBeijingFirstEntryTimeFilterRanges  = "04:00-10:00,18:00-23:30"; // 跟单空仓时禁止开首单的北京时间区间
input bool               InpPrintDebug           = false;        // 打印调试日志；追求速度时关闭

input group "图表跟单面板（仅Receiver）"
input bool               InpShowPanel            = true;         // 在Receiver图表显示内嵌跟单面板
input ENUM_BASE_CORNER   InpPanelCorner          = CORNER_LEFT_UPPER; // 面板所在角落
input int                InpPanelX               = 10;           // 面板水平偏移
input int                InpPanelY               = 20;           // 面板垂直偏移
input int                InpPanelRefreshMs       = 250;          // 面板刷新周期，最低100毫秒

string g_prefix;
string g_snapshot_file;
FileSourcePosition g_sources[];
datetime g_snapshot_time = 0;
bool g_have_snapshot = false;
bool g_snapshot_fresh = false;
ulong g_snapshot_sequence = 0;
ulong g_snapshot_publish_tick_ms = 0;
ulong g_last_snapshot_read_tick_ms = 0;
datetime g_last_snapshot_error_log = 0;
datetime g_last_snapshot_latency_log = 0;
datetime g_last_first_entry_time_filter_log = 0;
ulong g_panel_last_update_tick_ms = 0;
string g_panel_object_prefix = "";
bool g_panel_entries_paused = false;
string g_panel_confirm_action = "";
ulong g_panel_confirm_until_tick_ms = 0;
string g_panel_last_action = "就绪";
string g_sender_temp_file;
ulong g_sender_sequence = 0;
datetime g_sender_last_print_time = 0;
datetime g_sender_last_error_print_time = 0;
string g_sender_pause_reason = "";

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

   if(InpFileRole == FILE_FOLLOW_SENDER)
      return InitFileSender();
   return InitFileReceiver();
}

int InitFileSender()
{
   g_snapshot_file = SnapshotFileName();
   g_sender_temp_file = g_snapshot_file + ".tmp";
   int timer_period = InpSenderScanIntervalMs < 20 ? 20 : InpSenderScanIntervalMs;
   EventSetMillisecondTimer((uint)timer_period);
   SenderWriteSnapshot();
   return INIT_SUCCEEDED;
}

int InitFileReceiver()
{
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

   if(!ValidateBeijingFirstEntryTimeFilter())
      return INIT_PARAMETERS_INCORRECT;

   g_snapshot_file = SnapshotFileName();
   g_prefix = "FLFC_" +
              IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
              SanitizeNamePart(InpChannelName) + "_";

   PanelInitialize();

   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("Warning: this EA is designed for hedging accounts. On netting accounts, source and copy positions may merge.");

   int timer_period = InpScanIntervalMs < 20 ? 20 : InpScanIntervalMs;
   EventSetMillisecondTimer((uint)timer_period);
   LoadFileSnapshot(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(PanelRoleIsReceiver())
      PanelDestroy();
   if(InpFileRole == FILE_FOLLOW_SENDER)
      SenderWritePausedSnapshot("sender_stopped");
}

void OnTick()
{
   if(InpFileRole == FILE_FOLLOW_RECEIVER)
      CheckPositions();
}

void OnTimer()
{
   if(InpFileRole == FILE_FOLLOW_SENDER)
      SenderWriteSnapshot();
   else
      CheckPositions();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   PanelHandleChartEvent(id, sparam);
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(InpFileRole == FILE_FOLLOW_SENDER)
   {
      SenderWriteSnapshot();
      return;
   }

   if(InpCloseCopyWithSource && LoadFileSnapshot(true))
   {
      CloseCopiesWithoutSource();
      DeletePendingsWithoutSource();
      ResetInactiveGridGroups();
   }
   PanelUpdate(true);
}

void SenderWriteSnapshot()
{
   if(InpSenderPauseWhenAutoTradingOff && !IsAlgoTradingAllowed())
   {
      SenderWritePausedSnapshot("auto_trading_disabled");
      return;
   }

   ulong next_sequence = g_sender_sequence + 1;
   ulong publish_tick_ms = GetTickCount64();
   datetime now = TimeLocal();

   int handle = FileOpen(g_sender_temp_file,
                         FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_UNICODE | FILE_SHARE_READ,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      PrintSenderSnapshotError("Open temporary snapshot failed", GetLastError());
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
      if(!IsAllowedSymbol(symbol, InpSenderAllowedSymbols))
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

   if(!SenderCommitSnapshot())
      return;

   g_sender_sequence = next_sequence;
   g_sender_pause_reason = "";

   if(InpPrintDebug && now != g_sender_last_print_time)
   {
      g_sender_last_print_time = now;
      PrintFormat("File snapshot exported. file=%s positions=%d channel=%s seq=%I64u",
                  g_snapshot_file,
                  exported,
                  InpChannelName,
                  g_sender_sequence);
   }
}

void SenderWritePausedSnapshot(const string reason)
{
   if(g_sender_pause_reason == reason)
      return;

   ulong next_sequence = g_sender_sequence + 1;
   ulong publish_tick_ms = GetTickCount64();
   datetime now = TimeLocal();

   int handle = FileOpen(g_sender_temp_file,
                         FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_UNICODE | FILE_SHARE_READ,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      PrintSenderSnapshotError("Open temporary paused snapshot failed", GetLastError());
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
   FileWrite(handle, "PAUSED", reason);
   FileWrite(handle, "END", 0, 0, (long)next_sequence);
   FileClose(handle);

   if(!SenderCommitSnapshot())
      return;

   g_sender_sequence = next_sequence;
   g_sender_pause_reason = reason;

   if(InpPrintDebug && now != g_sender_last_print_time)
   {
      g_sender_last_print_time = now;
      PrintFormat("File snapshot paused. file=%s reason=%s channel=%s",
                  g_snapshot_file,
                  reason,
                  InpChannelName);
   }
}

bool SenderCommitSnapshot()
{
   ResetLastError();
   if(FileMove(g_sender_temp_file,
               FILE_COMMON,
               g_snapshot_file,
               FILE_COMMON | FILE_REWRITE))
      return true;

   PrintSenderSnapshotError("Atomic file snapshot replace failed", GetLastError());
   return false;
}

void PrintSenderSnapshotError(const string action, const int error_code)
{
   datetime now = TimeLocal();
   if(now == g_sender_last_error_print_time)
      return;

   g_sender_last_error_print_time = now;
   PrintFormat("%s. file=%s temp=%s error=%d",
               action,
               g_snapshot_file,
               g_sender_temp_file,
               error_code);
}

bool IsAlgoTradingAllowed()
{
   return (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
}



bool PanelRoleIsReceiver()
{
   return InpFileRole == FILE_FOLLOW_RECEIVER;
}

string PanelTransportName()
{
   return "FILE_COMMON 文件快照";
}

uint PanelChannelHash(const string value)
{
   uint hash = 2166136261;
   int length = StringLen(value);
   for(int i = 0; i < length; i++)
   {
      hash ^= (uint)StringGetCharacter(value, i);
      hash = (uint)(hash * 16777619);
   }
   return hash;
}

string PanelPauseGlobalName()
{
   return "LFCP_" +
          IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
          IntegerToString((long)InpCopyMagic) + "_" +
          IntegerToString((long)PanelChannelHash(InpChannelName)) + "_PAUSE";
}

string PanelObjectName(const string suffix)
{
   return g_panel_object_prefix + suffix;
}

void PanelSetPaused(const bool paused)
{
   g_panel_entries_paused = paused;
   GlobalVariableSet(PanelPauseGlobalName(), paused ? 1.0 : 0.0);
}

bool PanelEntriesPaused()
{
   return InpShowPanel && g_panel_entries_paused;
}

void PanelCreateBackground(const string suffix,
                           const int x,
                           const int y,
                           const int width,
                           const int height,
                           const color background,
                           const color border)
{
   string name = PanelObjectName(suffix);
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

void PanelCreateLabel(const string suffix,
                      const int x,
                      const int y,
                      const string text,
                      const color text_color,
                      const int font_size = 9)
{
   string name = PanelObjectName(suffix);
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
   ObjectSetString(0, name, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void PanelCreateButton(const string suffix,
                       const int x,
                       const int y,
                       const int width,
                       const int height,
                       const string text,
                       const color background)
{
   string name = PanelObjectName(suffix);
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrSlateGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
   ObjectSetString(0, name, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void PanelSetLabel(const string suffix, const string text, const color text_color)
{
   string name = PanelObjectName(suffix);
   if(ObjectFind(0, name) < 0)
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
}

void PanelSetButton(const string suffix, const string text, const color background)
{
   string name = PanelObjectName(suffix);
   if(ObjectFind(0, name) < 0)
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void PanelInitialize()
{
   if(!InpShowPanel || !PanelRoleIsReceiver())
      return;

   g_panel_object_prefix = "LFCPANEL_" + IntegerToString((long)ChartID()) + "_";
   string pause_name = PanelPauseGlobalName();
   g_panel_entries_paused = GlobalVariableCheck(pause_name) &&
                            GlobalVariableGet(pause_name) > 0.5;

   int x = InpPanelX;
   int y = InpPanelY;
   PanelCreateBackground("BG", x, y, 390, 305, C'24,29,38', C'62,77,98');
   PanelCreateBackground("HEADER_BG", x + 1, y + 1, 388, 34, C'35,94,150', C'35,94,150');
   PanelCreateLabel("TITLE", x + 14, y + 8, "LOSS FOLLOW  跟单控制面板", clrWhite, 11);
   PanelCreateLabel("TRANSPORT", x + 14, y + 43, "传输：--", clrSilver);
   PanelCreateLabel("ACCOUNT", x + 14, y + 64, "账户：--", clrSilver);
   PanelCreateLabel("STATUS", x + 14, y + 85, "状态：--", clrOrange);
   PanelCreateLabel("SOURCE", x + 14, y + 106, "源单：--", clrSilver);
   PanelCreateLabel("COPY", x + 14, y + 127, "跟单：--", clrSilver);
   PanelCreateLabel("VOLUME", x + 14, y + 148, "手数：--", clrSilver);
   PanelCreateLabel("PROFIT", x + 14, y + 169, "浮盈亏：--", clrSilver);
   PanelCreateLabel("TRADE", x + 14, y + 190, "自动交易：--", clrSilver);
   PanelCreateLabel("PAUSE", x + 14, y + 211, "新开控制：--", clrSilver);
   PanelCreateButton("BTN_PAUSE", x + 12, y + 238, 112, 30, "暂停新开", C'184,117,22');
   PanelCreateButton("BTN_CLOSE", x + 139, y + 238, 112, 30, "全部平仓", C'161,52,58');
   PanelCreateButton("BTN_DELETE", x + 266, y + 238, 112, 30, "删除挂单", C'115,68,143');
   PanelCreateLabel("ACTION", x + 14, y + 278, "操作：就绪", clrDarkGray, 8);
   PanelUpdate(true);
}

void PanelDestroy()
{
   if(g_panel_object_prefix == "")
      return;

   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, g_panel_object_prefix) == 0)
         ObjectDelete(0, name);
   }
   ChartRedraw(0);
   g_panel_object_prefix = "";
}

void PanelCollectCopyStats(int &position_count,
                           int &pending_count,
                           double &total_volume,
                           double &floating_profit)
{
   position_count = 0;
   pending_count = 0;
   total_volume = 0.0;
   floating_profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsCopyPosition())
         continue;

      position_count++;
      total_volume += PositionGetDouble(POSITION_VOLUME);
      floating_profit += PositionGetDouble(POSITION_PROFIT) +
                         PositionGetDouble(POSITION_SWAP);
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpCopyMagic)
         continue;
      if(!IsCopyComment(OrderGetString(ORDER_COMMENT)))
         continue;
      pending_count++;
   }
}

void PanelUpdate(const bool force)
{
   if(!InpShowPanel || !PanelRoleIsReceiver() || g_panel_object_prefix == "")
      return;

   ulong now_tick = GetTickCount64();
   ulong refresh_ms = (ulong)(InpPanelRefreshMs < 100 ? 100 : InpPanelRefreshMs);
   if(!force &&
      g_panel_last_update_tick_ms > 0 &&
      now_tick >= g_panel_last_update_tick_ms &&
      now_tick - g_panel_last_update_tick_ms < refresh_ms)
      return;
   g_panel_last_update_tick_ms = now_tick;

   if(g_panel_confirm_action != "" && now_tick > g_panel_confirm_until_tick_ms)
      g_panel_confirm_action = "";

   int copy_count = 0;
   int pending_count = 0;
   double total_volume = 0.0;
   double floating_profit = 0.0;
   PanelCollectCopyStats(copy_count, pending_count, total_volume, floating_profit);

   string connection_text = "等待源端快照";
   color connection_color = clrOrange;
   if(g_snapshot_fresh)
   {
      connection_text = "快照正常";
      connection_color = clrLimeGreen;
   }
   else if(g_have_snapshot)
   {
      connection_text = "快照暂停或已过期";
      connection_color = clrTomato;
   }

   string latency_text = "--";
   if(g_snapshot_publish_tick_ms > 0 && now_tick >= g_snapshot_publish_tick_ms)
      latency_text = IntegerToString((long)(now_tick - g_snapshot_publish_tick_ms)) + " ms";

   PanelSetLabel("TRANSPORT", "传输：" + PanelTransportName() + "  通道：" + InpChannelName, clrSilver);
   PanelSetLabel("ACCOUNT",
                 "账户：" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) +
                 "  服务器：" + AccountInfoString(ACCOUNT_SERVER),
                 clrSilver);
   PanelSetLabel("STATUS",
                 "状态：" + connection_text + "  延迟/年龄：" + latency_text,
                 connection_color);
   PanelSetLabel("SOURCE",
                 "源单：" + IntegerToString(ArraySize(g_sources)) +
                 "  快照序号：" + IntegerToString((long)g_snapshot_sequence),
                 clrSilver);
   PanelSetLabel("COPY",
                 "跟单持仓：" + IntegerToString(copy_count) +
                 "  跟单挂单：" + IntegerToString(pending_count),
                 clrSilver);
   PanelSetLabel("VOLUME", "跟单总手数：" + DoubleToString(total_volume, 2), clrSilver);
   PanelSetLabel("PROFIT",
                 "跟单浮盈亏：" + DoubleToString(floating_profit, 2) + " " +
                 AccountInfoString(ACCOUNT_CURRENCY),
                 floating_profit >= 0.0 ? clrLimeGreen : clrTomato);
   PanelSetLabel("TRADE",
                 "自动交易：" + (IsAlgoTradingAllowed() ? "已开启" : "已关闭"),
                 IsAlgoTradingAllowed() ? clrLimeGreen : clrTomato);
   PanelSetLabel("PAUSE",
                 "新开控制：" + (PanelEntriesPaused() ? "已暂停（平仓逻辑继续）" : "正常跟单"),
                 PanelEntriesPaused() ? clrOrange : clrLimeGreen);
   PanelSetLabel("ACTION", "操作：" + g_panel_last_action, clrDarkGray);

   if(g_panel_confirm_action == "CLOSE")
      PanelSetButton("BTN_CLOSE", "再次点击确认", C'205,63,69');
   else
      PanelSetButton("BTN_CLOSE", "全部平仓", C'161,52,58');

   if(g_panel_confirm_action == "DELETE")
      PanelSetButton("BTN_DELETE", "再次点击确认", C'142,76,177');
   else
      PanelSetButton("BTN_DELETE", "删除挂单", C'115,68,143');

   PanelSetButton("BTN_PAUSE",
                  PanelEntriesPaused() ? "恢复新开" : "暂停新开",
                  PanelEntriesPaused() ? C'42,134,88' : C'184,117,22');
   ChartRedraw(0);
}

bool PanelConfirmAction(const string action)
{
   ulong now_tick = GetTickCount64();
   if(g_panel_confirm_action == action && now_tick <= g_panel_confirm_until_tick_ms)
   {
      g_panel_confirm_action = "";
      g_panel_confirm_until_tick_ms = 0;
      return true;
   }

   g_panel_confirm_action = action;
   g_panel_confirm_until_tick_ms = now_tick + 3000;
   g_panel_last_action = action == "CLOSE"
                         ? "3秒内再次点击“全部平仓”确认"
                         : "3秒内再次点击“删除挂单”确认";
   return false;
}

void PanelCloseAllCopies()
{
   PanelSetPaused(true);
   int success = 0;
   int failed = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;
      if(!IsCopyPosition())
         continue;

      ulong source_ticket = SourceTicketFromCurrentPosition();
      if(source_ticket == 0)
         continue;
      if(CloseCopyPosition(copy_ticket, source_ticket))
         success++;
      else
         failed++;
   }

   g_panel_last_action = "全部平仓完成：成功 " + IntegerToString(success) +
                         "，失败 " + IntegerToString(failed) + "；已暂停新开";
}

void PanelDeleteAllPendings()
{
   PanelSetPaused(true);
   int success = 0;
   int failed = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong order_ticket = OrderGetTicket(i);
      if(order_ticket == 0 || !OrderSelect(order_ticket))
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpCopyMagic)
         continue;

      ulong source_ticket = SourceTicketFromComment(OrderGetString(ORDER_COMMENT));
      if(source_ticket == 0)
         continue;
      if(DeleteCopyPending(order_ticket, source_ticket))
         success++;
      else
         failed++;
   }

   g_panel_last_action = "删除挂单完成：成功 " + IntegerToString(success) +
                         "，失败 " + IntegerToString(failed) + "；已暂停新开";
}

void PanelHandleChartEvent(const int event_id, const string object_name)
{
   if(!InpShowPanel || !PanelRoleIsReceiver() || event_id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(object_name == PanelObjectName("BTN_PAUSE"))
   {
      PanelSetPaused(!PanelEntriesPaused());
      g_panel_confirm_action = "";
      g_panel_last_action = PanelEntriesPaused()
                            ? "已暂停新开；同步平仓和盈利平仓继续运行"
                            : "已恢复新开跟单";
   }
   else if(object_name == PanelObjectName("BTN_CLOSE"))
   {
      if(PanelConfirmAction("CLOSE"))
         PanelCloseAllCopies();
   }
   else if(object_name == PanelObjectName("BTN_DELETE"))
   {
      if(PanelConfirmAction("DELETE"))
         PanelDeleteAllPendings();
   }
   else
      return;

   PanelUpdate(true);
}

void CheckPositions()
{
   bool fresh = LoadFileSnapshot(false);
   PanelUpdate(false);

   if(InpCloseCopyWithSource && fresh)
   {
      CloseCopiesWithoutSource();
      DeletePendingsWithoutSource();
   }

   if(fresh)
      ResetInactiveGridGroups();

   CheckMinuteProfitClose();
   CheckBasketProfitClose();
   ApplyFirstEntryTimeFilter();

   if(!fresh)
      return;

   if(PanelEntriesPaused())
      return;

   CheckGridActivationEntries();

   int total = ArraySize(g_sources);
   for(int i = total - 1; i >= 0; i--)
   {
      FileSourcePosition source = g_sources[i];
      string source_symbol = source.symbol;
      string comment = source.comment;
      long magic = source.magic;

      SourceProfile profile;
      if(!MatchSourceProfile(source_symbol, magic, comment, profile))
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
      FileSourcePosition source = g_sources[i];
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
   string local_symbol = LocalSymbolForSource(symbol);
   if(!EnsureSymbolReady(local_symbol))
   {
      PrintFormat("Skip grid group: local symbol is not available. source_symbol=%s local_symbol=%s profile=EA%d",
                  symbol,
                  local_symbol,
                  profile.profile_index);
      return;
   }

   int source_count = 0;
   double source_volume = 0.0;
   double weighted_open = 0.0;
   if(!SourceGroupStats(profile, symbol, position_type, source_count, source_volume, weighted_open))
      return;

   if(IsGridGroupStopped(profile.profile_index, symbol, position_type))
      return;

   double avg_open = weighted_open / source_volume;
   double loss_points = FloatingLossPoints(local_symbol, position_type, avg_open);
   double loss_price = loss_points * SymbolInfoDouble(local_symbol, SYMBOL_POINT);
   bool active = IsGridGroupActive(profile.profile_index, symbol, position_type);
   bool triggered = IsLossTriggered(loss_points, loss_price, profile, 1);

   if(active)
   {
      int copy_count = CopyGroupCount(profile.profile_index, local_symbol, position_type);
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

      if(IsFirstCopyEntryTimeBlocked())
      {
         LogFirstEntryTimeFilterSkip(0, local_symbol, 1, "grid activation");
         return;
      }

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

      CopyGridSources(profile, symbol, local_symbol, position_type, true, loss_points, loss_price);
      return;
   }

   CopyGridSources(profile, symbol, local_symbol, position_type, false, loss_points, loss_price);
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
      FileSourcePosition source = g_sources[i];

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

bool IsSourcePositionForProfile(const SourceProfile& profile, const FileSourcePosition& source)
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
                     const string local_symbol,
                     const ENUM_POSITION_TYPE position_type,
                     const bool initial_activation,
                     const double group_loss_points,
                     const double group_loss_price)
{
   int copied_now = 0;
   int total = ArraySize(g_sources);

   for(int i = total - 1; i >= 0; i--)
   {
      FileSourcePosition source = g_sources[i];
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
      double volume = CalculateCopyVolume(local_symbol, source_volume, profile, 1);
      if(volume <= 0.0)
      {
         PrintFormat("Skip grid source #%I64u: calculated copy volume is invalid. source_symbol=%s local_symbol=%s source_volume=%.8f fixed_lot=%.8f min=%.8f max=%.8f step=%.8f",
                     source_ticket,
                     symbol,
                     local_symbol,
                     source_volume,
                     LevelFixedLot(profile, 1),
                     SymbolInfoDouble(local_symbol, SYMBOL_VOLUME_MIN),
                     SymbolInfoDouble(local_symbol, SYMBOL_VOLUME_MAX),
                     SymbolInfoDouble(local_symbol, SYMBOL_VOLUME_STEP));
         continue;
      }

      double source_sl = source.sl;
      double source_tp = source.tp;
      if(IsFirstCopyEntryTimeBlocked())
      {
         LogFirstEntryTimeFilterSkip(source_ticket, local_symbol, 1, "grid copy");
         return;
      }

      if(OpenCopyTrade(source_ticket, local_symbol, position_type, volume, source_sl, source_tp, group_loss_points, group_loss_price, profile, 1))
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

void ProcessSourceLevel(const FileSourcePosition& source, const SourceProfile& profile, const int level_index)
{
   if(!IsLevelEnabled(profile, level_index))
      return;

   ulong source_ticket = source.source_id;
   if((profile.entry_mode == ENTRY_PENDING_AT_TRIGGER || InpOneCopyPerPosition) && IsAlreadyCopied(source_ticket, level_index))
      return;

   string source_symbol = source.symbol;
   string symbol = LocalSymbolForSource(source_symbol);
   if(!EnsureSymbolReady(symbol))
   {
      PrintFormat("Skip source #%I64u L%d: local symbol is not available. source_symbol=%s local_symbol=%s",
                  source_ticket,
                  level_index,
                  source_symbol,
                  symbol);
      return;
   }

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
      PrintFormat("Skip source #%I64u L%d: calculated copy volume is invalid. source_symbol=%s local_symbol=%s source_volume=%.8f fixed_lot=%.8f min=%.8f max=%.8f step=%.8f",
                  source_ticket,
                  level_index,
                  source_symbol,
                  symbol,
                  source_volume,
                  LevelFixedLot(profile, level_index),
                  SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                  SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                  SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
      return;
   }

   double source_sl = source.sl;
   double source_tp = source.tp;

   if(profile.entry_mode == ENTRY_PENDING_AT_TRIGGER)
   {
      if(IsFirstCopyEntryTimeBlocked())
      {
         LogFirstEntryTimeFilterSkip(source_ticket, symbol, level_index, "pending");
         return;
      }

      PlaceCopyPending(source_ticket, symbol, position_type, source_open_price, volume, source_sl, source_tp, profile, level_index);
      return;
   }

   if(!IsLossTriggered(loss_points, loss_price, profile, level_index))
      return;

   if(IsFirstCopyEntryTimeBlocked())
   {
      LogFirstEntryTimeFilterSkip(source_ticket, symbol, level_index, "market");
      return;
   }

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

bool ValidateBeijingFirstEntryTimeFilter()
{
   if(!InpBeijingFirstEntryTimeFilterEnabled)
      return true;

   if(!ValidateTimeRanges(InpBeijingFirstEntryTimeFilterRanges))
   {
      Print("InpBeijingFirstEntryTimeFilterRanges format must be like 04:00-10:00,18:00-23:30.");
      return false;
   }

   return true;
}

string NormalizeTimeRanges(string ranges)
{
   StringReplace(ranges, " ", "");
   StringReplace(ranges, "\t", "");
   StringReplace(ranges, "，", ";");
   StringReplace(ranges, "；", ";");
   StringReplace(ranges, ",", ";");
   return ranges;
}

bool IsDigitString(const string text)
{
   int length = StringLen(text);
   if(length <= 0)
      return false;

   for(int i = 0; i < length; i++)
   {
      ushort ch = StringGetCharacter(text, i);
      if(ch < 48 || ch > 57)
         return false;
   }

   return true;
}

bool ParseClockMinute(const string text, int& minute_of_day)
{
   int colon_pos = StringFind(text, ":");
   if(colon_pos <= 0 || colon_pos >= StringLen(text) - 1)
      return false;

   string hour_text = StringSubstr(text, 0, colon_pos);
   string minute_text = StringSubstr(text, colon_pos + 1);
   if(!IsDigitString(hour_text) || !IsDigitString(minute_text))
      return false;

   int hour = (int)StringToInteger(hour_text);
   int minute = (int)StringToInteger(minute_text);
   if(hour < 0 || hour > 24 || minute < 0 || minute > 59)
      return false;

   if(hour == 24 && minute != 0)
      return false;

   minute_of_day = hour * 60 + minute;
   return true;
}

bool ParseTimeRange(const string range_text, int& start_minute, int& end_minute)
{
   int dash_pos = StringFind(range_text, "-");
   if(dash_pos <= 0 || dash_pos >= StringLen(range_text) - 1)
      return false;

   if(StringFind(range_text, "-", dash_pos + 1) >= 0)
      return false;

   string start_text = StringSubstr(range_text, 0, dash_pos);
   string end_text = StringSubstr(range_text, dash_pos + 1);
   return ParseClockMinute(start_text, start_minute) &&
          ParseClockMinute(end_text, end_minute);
}

bool ValidateTimeRanges(string ranges)
{
   ranges = NormalizeTimeRanges(ranges);
   if(ranges == "")
      return false;

   string parts[];
   int count = StringSplit(ranges, ';', parts);
   if(count <= 0)
      return false;

   bool has_range = false;
   for(int i = 0; i < count; i++)
   {
      if(parts[i] == "")
         continue;

      int start_minute = 0;
      int end_minute = 0;
      if(!ParseTimeRange(parts[i], start_minute, end_minute))
         return false;

      has_range = true;
   }

   return has_range;
}

bool IsMinuteInRange(const int minute_of_day, const int start_minute, const int end_minute)
{
   if(start_minute == end_minute)
      return true;

   if(start_minute < end_minute)
      return minute_of_day >= start_minute && minute_of_day < end_minute;

   return minute_of_day >= start_minute || minute_of_day < end_minute;
}

bool IsMinuteInTimeRanges(const int minute_of_day, string ranges)
{
   ranges = NormalizeTimeRanges(ranges);
   if(ranges == "")
      return false;

   string parts[];
   int count = StringSplit(ranges, ';', parts);
   for(int i = 0; i < count; i++)
   {
      if(parts[i] == "")
         continue;

      int start_minute = 0;
      int end_minute = 0;
      if(!ParseTimeRange(parts[i], start_minute, end_minute))
         continue;

      if(IsMinuteInRange(minute_of_day, start_minute, end_minute))
         return true;
   }

   return false;
}

int BeijingMinuteOfDay()
{
   datetime beijing_time = TimeGMT() + 8 * 60 * 60;
   MqlDateTime now;
   TimeToStruct(beijing_time, now);
   return now.hour * 60 + now.min;
}

bool IsBeijingFirstEntryFilterTime()
{
   return IsMinuteInTimeRanges(BeijingMinuteOfDay(), InpBeijingFirstEntryTimeFilterRanges);
}

bool HasOpenCopyPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong copy_ticket = PositionGetTicket(i);
      if(copy_ticket == 0 || !PositionSelectByTicket(copy_ticket))
         continue;

      if(IsCopyPosition())
         return true;
   }

   return false;
}

bool IsFirstCopyEntryTimeBlocked()
{
   if(!InpBeijingFirstEntryTimeFilterEnabled)
      return false;

   if(HasOpenCopyPositions())
      return false;

   return IsBeijingFirstEntryFilterTime();
}

string BeijingTimeFilterNowText()
{
   datetime beijing_time = TimeGMT() + 8 * 60 * 60;
   MqlDateTime now;
   TimeToStruct(beijing_time, now);
   return StringFormat("%02d:%02d", now.hour, now.min);
}

void LogFirstEntryTimeFilterSkip(const ulong source_ticket,
                                 const string symbol,
                                 const int level_index,
                                 const string action)
{
   if(!InpPrintDebug)
      return;

   datetime now = TimeGMT();
   if(g_last_first_entry_time_filter_log > 0 &&
      now - g_last_first_entry_time_filter_log < 60)
      return;

   g_last_first_entry_time_filter_log = now;
   PrintFormat("First file copy entry blocked by Beijing time filter. action=%s source=%I64u level=L%d symbol=%s beijing=%s ranges=%s",
               action,
               source_ticket,
               level_index,
               symbol,
               BeijingTimeFilterNowText(),
               InpBeijingFirstEntryTimeFilterRanges);
}

void ApplyFirstEntryTimeFilter()
{
   if(!IsFirstCopyEntryTimeBlocked())
      return;

   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong order_ticket = OrderGetTicket(i);
      if(order_ticket == 0 || !OrderSelect(order_ticket))
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpCopyMagic)
         continue;

      ulong source_ticket = SourceTicketFromComment(OrderGetString(ORDER_COMMENT));
      DeleteCopyPending(order_ticket, source_ticket);
   }
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
   FileSourcePosition source;
   if(!FileSourceById(source_ticket, source))
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

      if(FileSourceExists(source_ticket))
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

      if(FileSourceExists(source_ticket))
         continue;

      DeleteCopyPending(order_ticket, source_ticket);
   }
}

// TODO: Sync partial source closes by reducing the copy position proportionally.

ulong SourceTicketFromComment(const string comment)
{
   string prefix = "FLFC:";
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
   string prefix = "FLFC:";
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

string LocalSymbolForSource(const string source_symbol)
{
   string mappings = InpSymbolMap;
   StringReplace(mappings, " ", "");
   StringReplace(mappings, ",", ";");

   if(mappings == "")
      return source_symbol;

   string entries[];
   int entry_count = StringSplit(mappings, ';', entries);
   for(int i = 0; i < entry_count; i++)
   {
      if(entries[i] == "")
         continue;

      string pair[];
      int pair_count = StringSplit(entries[i], '=', pair);
      if(pair_count != 2)
         continue;

      if(pair[0] == source_symbol && pair[1] != "")
         return pair[1];
   }

   return source_symbol;
}

bool EnsureSymbolReady(const string symbol)
{
   if(symbol == "")
      return false;

   if(!SymbolSelect(symbol, true))
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   return point > 0.0 && min_volume > 0.0 && max_volume > 0.0 && step > 0.0;
}

double FloatingLossPoints(const string symbol, const ENUM_POSITION_TYPE position_type, const double open_price)
{
   if(!EnsureSymbolReady(symbol))
      return 0.0;

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
   if(!EnsureSymbolReady(symbol))
      return 0.0;

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
   if(!EnsureSymbolReady(symbol))
      return 0.0;

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
   request.comment = "FLFC remove:" + IntegerToString((long)source_ticket);

   ResetLastError();
   bool sent = OrderSend(request, result);
   if(!sent || !IsSuccessRetcode(result.retcode))
   {
      PrintFormat("Delete pending failed. order=%I64u source=%I64u retcode=%u last_error=%d comment=%s",
                  order_ticket, source_ticket, result.retcode, GetLastError(), result.comment);
      return false;
   }

   if(InpPrintDebug)
      PrintFormat("Pending copy deleted. order=%I64u source=%I64u", order_ticket, source_ticket);

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
   request.comment = "FLFC close:" + IntegerToString((long)source_ticket);
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
   return "FLFC:" + IntegerToString((long)source_ticket) + ":L" + IntegerToString(level_index);
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
   string legacy_comment = "FLFC:" + IntegerToString((long)source_ticket);
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

bool LoadFileSnapshot(const bool force)
{
   ulong now_tick_ms = GetTickCount64();
   ulong read_interval_ms = (ulong)(InpScanIntervalMs < 20 ? 20 : InpScanIntervalMs);
   if(!force &&
      g_last_snapshot_read_tick_ms > 0 &&
      now_tick_ms >= g_last_snapshot_read_tick_ms &&
      now_tick_ms - g_last_snapshot_read_tick_ms < read_interval_ms)
   {
      UpdateFileSnapshotFreshness();
      return g_snapshot_fresh;
   }
   g_last_snapshot_read_tick_ms = now_tick_ms;

   FileSourcePosition loaded[];
   datetime snapshot_time = 0;
   datetime end_time = 0;
   ulong loaded_sequence = 0;
   ulong end_sequence = 0;
   ulong publish_tick_ms = 0;
   int expected_count = -1;
   bool protocol_v2 = false;
   bool have_meta = false;
   bool complete = false;
   bool paused = false;

   ResetLastError();
   int handle = FileOpen(g_snapshot_file,
                         FILE_READ | FILE_CSV | FILE_COMMON | FILE_UNICODE | FILE_SHARE_READ,
                         '\t');
   if(handle == INVALID_HANDLE)
   {
      PrintFileSnapshotReadError("File snapshot not readable", GetLastError());
      UpdateFileSnapshotFreshness();
      return g_snapshot_fresh;
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

         if(version == "RLFC2")
         {
            protocol_v2 = true;
            loaded_sequence = (ulong)StringToInteger(FileReadString(handle));
            publish_tick_ms = (ulong)StringToInteger(FileReadString(handle));
         }
         else if(version != "RLFC1")
         {
            FileClose(handle);
            PrintFileSnapshotReadError("Unsupported snapshot protocol", 0);
            UpdateFileSnapshotFreshness();
            return g_snapshot_fresh;
         }

         if(channel != InpChannelName)
         {
            FileClose(handle);
            PrintFileSnapshotReadError("Snapshot channel mismatch", 0);
            UpdateFileSnapshotFreshness();
            return g_snapshot_fresh;
         }
         have_meta = true;
         continue;
      }

      if(tag == "P")
      {
         FileSourcePosition source;
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

      if(tag == "PAUSED")
      {
         string pause_reason = FileReadString(handle);
         paused = true;
         continue;
      }

      if(tag == "END")
      {
         expected_count = (int)StringToInteger(FileReadString(handle));
         end_time = (datetime)StringToInteger(FileReadString(handle));
         if(protocol_v2)
            end_sequence = (ulong)StringToInteger(FileReadString(handle));
         complete = true;
         break;
      }
   }

   FileClose(handle);

   bool valid = have_meta &&
                complete &&
                expected_count >= 0 &&
                expected_count == ArraySize(loaded);
   if(protocol_v2)
   {
      valid = valid &&
              loaded_sequence > 0 &&
              loaded_sequence == end_sequence &&
              snapshot_time == end_time;
   }
   else if(snapshot_time == 0)
   {
      snapshot_time = end_time;
   }

   if(!valid)
   {
      PrintFileSnapshotReadError("Incomplete or inconsistent snapshot ignored", 0);
      UpdateFileSnapshotFreshness();
      return g_snapshot_fresh;
   }

   if(paused)
   {
      ArrayResize(g_sources, 0);
      g_snapshot_time = 0;
      g_snapshot_sequence = loaded_sequence;
      g_snapshot_publish_tick_ms = publish_tick_ms;
      g_have_snapshot = true;
      g_snapshot_fresh = false;
      return false;
   }

   if(snapshot_time <= 0)
   {
      PrintFileSnapshotReadError("Snapshot time is invalid", 0);
      UpdateFileSnapshotFreshness();
      return g_snapshot_fresh;
   }

   bool changed = !protocol_v2 || loaded_sequence != g_snapshot_sequence;
   if(changed)
   {
      ArrayResize(g_sources, ArraySize(loaded));
      for(int i = 0; i < ArraySize(loaded); i++)
         g_sources[i] = loaded[i];
   }

   g_snapshot_time = snapshot_time;
   g_snapshot_sequence = loaded_sequence;
   g_snapshot_publish_tick_ms = publish_tick_ms;
   g_have_snapshot = true;
   UpdateFileSnapshotFreshness();

   if(InpPrintDebug && changed && protocol_v2)
   {
      datetime now = TimeLocal();
      if(now != g_last_snapshot_latency_log)
      {
         g_last_snapshot_latency_log = now;
         ulong latency_ms = 0;
         ulong receive_tick_ms = GetTickCount64();
         if(receive_tick_ms >= publish_tick_ms)
            latency_ms = receive_tick_ms - publish_tick_ms;
         PrintFormat("File snapshot received. seq=%I64u positions=%d latency=%I64u ms",
                     loaded_sequence,
                     ArraySize(g_sources),
                     latency_ms);
      }
   }

   return g_snapshot_fresh;
}

void UpdateFileSnapshotFreshness()
{
   if(!g_have_snapshot || g_snapshot_time <= 0)
   {
      g_snapshot_fresh = false;
      return;
   }

   if(g_snapshot_publish_tick_ms > 0)
   {
      ulong now_tick_ms = GetTickCount64();
      ulong stale_limit_ms = (ulong)InpSourceStaleSeconds * 1000;
      g_snapshot_fresh = now_tick_ms >= g_snapshot_publish_tick_ms &&
                         now_tick_ms - g_snapshot_publish_tick_ms <= stale_limit_ms;
   }
   else
   {
      int snapshot_age = (int)(TimeLocal() - g_snapshot_time);
      g_snapshot_fresh = snapshot_age >= 0 && snapshot_age <= InpSourceStaleSeconds;
   }
}

void PrintFileSnapshotReadError(const string message, const int error_code)
{
   if(!InpPrintDebug)
      return;

   datetime now = TimeLocal();
   if(now == g_last_snapshot_error_log)
      return;

   g_last_snapshot_error_log = now;
   PrintFormat("%s. file=%s error=%d", message, g_snapshot_file, error_code);
}

bool FileSourceById(const ulong source_id, FileSourcePosition& source)
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

bool FileSourceExists(const ulong source_id)
{
   FileSourcePosition source;
   return FileSourceById(source_id, source);
}

string SnapshotFileName()
{
   return "FileLossFollow_" + SanitizeNamePart(InpChannelName) + ".tsv";
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
