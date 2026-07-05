# Loss Follow Copier

`LossFollowCopier.mq5` 是一个 MT5 跟单 EA。它用于监控本地同账户内其他 EA 的持仓，在源单或源 EA 组合达到指定浮亏距离后，开同方向跟单，并支持源单平仓同步、篮子整体盈利平仓、单笔盈利平仓等逻辑。

> 风险提示：这是实盘交易工具，不是无风险套利。使用前必须先在模拟盘或小手数实盘验证参数、券商报价位数、滑点、止损止盈和源 EA 风控。

## 适用场景

### 普通单源单 EA

如果源 EA 通常一轮只开一单，适合使用普通三档模式：

- `ENTRY_MARKET_ON_TRIGGER`
- `ENTRY_PENDING_AT_TRIGGER`

每张源单可以独立设置最多 3 个浮亏跟单档位，例如：

- 档位 1：浮亏 2 美金跟 0.01 手
- 档位 2：浮亏 4 美金跟 0.02 手
- 档位 3：浮亏 6 美金跟 0.03 手

### 网格/补仓/马丁类 EA

如果源 EA 会在浮亏后继续补仓，建议使用：

- `ENTRY_GRID_ACTIVATION`

这个模式不再对每张源单单独跑三档，而是按：

`源EA + 品种 + 方向`

统计组合均价和组合浮亏。组合浮亏达到档位 1 的触发距离后，EA 进入激活状态：

- 激活瞬间补跟当前已有源单，数量由 `GridInitialMaxCopies` 控制。
- 激活后，源 EA 后续新增源单会直接跟。
- 源 EA 组合全部平仓后，跟单仓位同步平仓并重置状态。
- 如果跟单篮子提前盈利平仓，且 `GridStopAfterBasketClose = true`，本轮停止继续跟单，直到源 EA 组合归零。

## 安装方式

1. 将 `LossFollowCopier.mq5` 放入 MT5 数据目录：

   `MQL5/Experts/`

2. 在 MetaEditor 中打开并编译。

3. 在同一个 MT5 账户内：

   - 一个图表挂源 EA。
   - 另一个图表挂 `LossFollowCopier`。

4. 按源 EA 的魔术号、注释或品种过滤配置监控条件。

## 远程跟单版

新增两个文件：

- `RemoteLossFollowSender.mq5`：挂在源账号终端，负责导出源账号持仓快照。
- `RemoteLossFollowReceiver.mq5`：挂在跟单账号终端，读取快照后执行同样的浮亏跟单逻辑。

当前远程版默认使用 MT5 的 `FILE_COMMON` 公共文件夹传输，适合：

- 同一台电脑上多个 MT5 终端。
- 同一台 VPS 上多个 MT5 终端。
- 本地账号跟同机其他账号。

使用步骤：

1. 源账号终端编译并挂载 `RemoteLossFollowSender.mq5`。
2. 跟单账号终端编译并挂载 `RemoteLossFollowReceiver.mq5`。
3. 两边 `InpChannelName` 必须一致，例如都填 `loss_follow_1`。
4. 接收端继续按源 EA 魔术号、注释、品种配置 `源EA1/源EA2`。

远程版的主要保护：

- 发送端写入源单稳定 ID、票号、品种、方向、手数、开仓价、SL/TP、魔术号和注释。
- 接收端跟单注释使用 `RLFC:源ID:L档位`，不和本地版 `LFC:` 混用。
- `InpSourceStaleSeconds` 用于快照过期保护。快照过期时，接收端不会新开单，也不会把“读不到快照”误判成源单平仓。

限制：

- 这个版本不是跨机器/VPS 的网络同步。跨机器需要后续增加 WebRequest/HTTP 中转、FTP 或共享盘。
- 远程源单部分平仓后，按比例减少跟单手数仍是待办。
- 接收端交易品种名称必须和源账号一致，例如都叫 `XAUUSD`；如果券商后缀不同，需要后续增加品种映射。

## 核心参数

### 源 EA 匹配

- `Enabled`：是否启用该源 EA 配置。
- `Magic`：源 EA 魔术号，`-1` 表示不限制魔术号。
- `CommentFilter`：源单注释模糊匹配，空表示不限制。
- `AllowedSymbols`：允许品种，多个品种用 `;` 或 `,` 分隔，空表示全部。

EA 当前支持 `源EA1` 和 `源EA2` 两套独立配置。

## 入场模式

### `ENTRY_MARKET_ON_TRIGGER`

持续轮询源单。当单张源单浮亏达到当前档位设置时，市价开同方向跟单。

适合：一轮只开一单或很少补仓的 EA。

### `ENTRY_PENDING_AT_TRIGGER`

源单出现后，提前在浮亏触发价挂同方向限价单。  
如果检测时价格已经越过触发价，则直接市价入场。

适合：希望提前挂单、减少轮询延迟的场景。

### `ENTRY_GRID_ACTIVATION`

网格激活模式。按源 EA 的组合均价计算浮亏，达到档位 1 触发距离后激活：

- 激活前不跟单。
- 激活时最多补跟 `GridInitialMaxCopies` 张已有源单。
- 激活后新增源单直接跟。
- 档位 2/3 在该模式下不参与。

适合：网格、补仓、马丁、小止盈大止损类 EA。

## 浮亏距离模式

### `LOSS_TRIGGER_PRICE`

价格距离模式。适合黄金。

示例：

- XAUUSD 多单 4000 开仓
- 设置 `LossPrice = 5.0`
- 价格下跌到 3995 附近触发

### `LOSS_TRIGGER_POINTS`

券商点数模式。

示例：

- 黄金 2 位报价：`300` 点约等于 `3.00`
- 黄金 3 位报价：`3000` 点约等于 `3.000`

如果主要交易黄金，优先使用 `LOSS_TRIGGER_PRICE`。

## 手数模式

- `COPY_LOT_FIXED`：固定手数。
- `COPY_LOT_SOURCE`：跟随源单手数。
- `COPY_LOT_MULTIPLIER`：源单手数乘以倍数。

普通三档模式下，每个档位都有自己的手数配置。

网格激活模式下，使用档位 1 的手数配置。

## 止损止盈

- `CopySourceSLTP = true`：开仓时复制源单 SL/TP。
- `CopySourceSLTP = false`：使用各档位自定义 SL/TP。

普通三档模式下，档位 1/2/3 可以分别设置自定义止损止盈点数。

网格激活模式下，使用档位 1 的自定义 SL/TP。

`0` 表示不设置。

## 平仓逻辑

### 源单平仓同步

`CloseCopyWithSource = true`

源单消失后，跟单仓位会尝试市价平仓。挂单也会在源单消失后删除。

EA 会用 `LFC:源单票号:L档位` 注释和本地全局变量记录跟单仓映射，降低手动部分平仓后漏平的概率。

### 单笔盈利平仓

`MinuteProfitCloseEnabled = true`

单个跟单仓位盈利达到指定点数后平仓。

该功能更适合普通单源单模式。网格/补仓模式通常不建议开启单笔盈利平仓，否则低位关键仓位可能提前跑掉。

### 篮子整体盈利平仓

`BasketProfitCloseEnabled = true`

按同一个源 EA、同品种、同方向统计跟单仓位加权平均成本。整体盈利达到指定点数后，整篮子平仓。

该功能适合网格/补仓模式。

### 盈利检查时机

- `PROFIT_CHECK_ANYTIME`：随时检查，默认推荐。
- `PROFIT_CHECK_TIME_WINDOW`：只在指定秒数窗口检查。

## 网格模式推荐配置

保守配置：

- `EntryMode = ENTRY_GRID_ACTIVATION`
- `LossMode = LOSS_TRIGGER_PRICE`
- `LossPrice = 1.0 ~ 5.0`
- `GridInitialMaxCopies = 1`
- `GridStopAfterBasketClose = true`
- `BasketProfitCloseEnabled = true`
- 关闭单笔盈利平仓

更贴近源 EA 组合结构：

- `GridInitialMaxCopies = 0`

这表示激活瞬间补跟所有已有源单。风险更高，但更接近源 EA 的解套结构。

## 已知限制

- 源单部分平仓后，按比例同步减少跟单剩余手数仍是待办。
- 如果旧跟单仓在新版 EA 运行前已经同时丢失 `LFC` 注释和本地映射，EA 无法判断它原本对应哪个源单。
- EA 设计目标是对冲账户。净值账户可能出现源单和跟单合并的问题。
- 本仓库只保存源码，不保存 `.ex5` 编译文件。

## 实盘建议

- 先用模拟盘验证一整轮源 EA 开仓、补仓、止盈、止损流程。
- 不要让跟单 EA 的风险控制替代源 EA 风控。
- 网格模式下，源 EA 自身必须限制最大订单数、最大浮亏或止损。
- 每次更新源码后，重新在 MetaEditor 编译，再替换到 MT5。
