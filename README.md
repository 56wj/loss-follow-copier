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
- 发送端默认 `InpPauseWhenAutoTradingOff = true`。源端自动交易关闭时，会暂停发布有效快照，接收端不会继续用旧文件开新跟单。
- 接收端跟单注释使用 `RLFC:源ID:L档位`，不和本地版 `LFC:` 混用。
- `InpSourceStaleSeconds` 用于快照过期保护。快照过期时，接收端不会新开单，也不会把“读不到快照”误判成源单平仓。
- 接收端支持 `InpSymbolMap` 品种映射，例如源账号是 `XAUUSD`、跟单账号是 `XAUUSDm`，填写 `XAUUSD=XAUUSDm`。

限制：

- 这个版本不是跨机器/VPS 的网络同步。跨机器需要后续增加 WebRequest/HTTP 中转、FTP 或共享盘。
- 远程源单部分平仓后，按比例减少跟单手数仍是待办。
- 如果接收端日志出现 `calculated copy volume is invalid`，通常表示跟单账号没有对应交易品种，或品种后缀不同。先检查市场报价是否有该品种，再配置 `InpSymbolMap`。

## 本机三个 MT5 统一版本

| 文件 | 传输方式 | 额外文件 | DLL imports | 加载顺序 | 默认周期 |
| --- | --- | --- | --- | --- | --- |
| `MemoryLossFollow.mq5` | 双缓冲命名共享内存 | `RlfcMemoryBridge.dll` | 两端开启 | 任意 | `20ms/20ms` |
| `WinApiMemoryLossFollow.mq5` | Windows API 命名共享内存 | 无额外 DLL | 两端开启 | 任意 | `20ms/20ms` |
| `FileLossFollow.mq5` | MT5 `FILE_COMMON` 文件快照 | 无 | 关闭即可 | 任意 | `50ms/50ms` |

三个版本使用不同的默认 `InpCopyMagic`、订单注释和全局变量前缀，可以并行测试，
但同一跟单账号正式运行时应只选择一个版本，避免对同一源单重复跟单。

### Receiver 内嵌跟单面板

面板代码直接写在上面三个 `.mq5` 文件中，没有独立面板 EA，也没有额外
`.mqh` 依赖。EA 选择 Receiver 角色并初始化成功后，图表左上角默认显示深色面板；
Sender 角色不创建面板。

面板显示：

- 当前传输类型、通道、接收账户和服务器；
- 快照正常/等待/暂停或过期状态，以及快照延迟或年龄；
- 源单数量、快照 sequence；
- 跟单持仓、跟单挂单、总手数和浮动盈亏；
- 自动交易状态和当前是否暂停新开。

面板按钮：

- `暂停新开/恢复新开`：只控制后续新开跟单，源单同步平仓、单笔盈利平仓和
  篮子盈利平仓继续执行；暂停状态按账户、Magic 和通道保存在终端全局变量中。
- `全部平仓`：关闭当前 EA Magic/映射识别到的跟单持仓，并自动暂停新开。
- `删除挂单`：删除当前 EA 的跟单挂单，并自动暂停新开。
- 平仓和删挂单使用 3 秒内二次点击确认，减少误触。

面板参数：`InpShowPanel`、`InpPanelCorner`、`InpPanelX`、`InpPanelY`、
`InpPanelRefreshMs`。正式实盘前先在模拟盘验证按钮、券商 filling mode 和成交回报。

## 本机共享内存版

追求同机双 MT5 更低延迟时使用：

- `MemoryLossFollow.mq5`：同一个 EA，通过 `InpMemoryRole` 选择 Sender 或 Receiver
- `memory-bridge/`：Windows x64 共享内存 DLL 工程

内存版保留远程 Receiver 的源 EA 匹配、三档跟单、挂单、网格激活、
SL/TP、源单平仓同步、盈利平仓、品种映射和北京时间首单过滤逻辑，
只把 `FILE_COMMON` 快照替换为双缓冲共享内存。

数据通路：

`源MT5 -> MemoryLossFollow(Sender) -> RlfcMemoryBridge.dll -> Local\\共享内存 -> MemoryLossFollow(Receiver) -> 跟单账号`

共享内存保护包括：

- inactive slot 写入完成后再原子切换 active slot；
- sequence 前后保护，拒绝并发覆盖期间的不一致读取；
- CRC32 校验完整 payload；
- 同通道 writer mutex，避免多个发送端同时覆盖；
- Receiver 保留上一份完整快照，并在每个行情 tick 上继续判断浮亏触发。

安装：

1. 在 Windows x64 + Visual Studio 2022 环境运行 `memory-bridge/build.ps1`。
2. 把生成的 `RlfcMemoryBridge.dll` 放进两个终端各自的 `MQL5/Libraries/`。
3. 两个终端都编译并挂载 `MemoryLossFollow.mq5`，勾选 **Allow DLL imports**。
4. 源账号设置 `InpMemoryRole=MEMORY_FOLLOW_SENDER`，跟单账号设置为 `MEMORY_FOLLOW_RECEIVER`。
5. 两边保持相同的 `InpChannelName` 和 `InpSharedMemoryCapacityKB`。
6. Sender/Receiver 任意顺序加载；建议周期分别使用 `20ms/20ms`，先在模拟盘测延迟日志和完整交易周期。

共享内存只适用于同一台 Windows 主机、同一登录会话中的多个 MT5 进程；
跨机器仍使用网络 API/WebSocket 方案。

## 本机 Windows API 共享内存版（无额外 DLL 文件）

`WinApiMemoryLossFollow.mq5` 是当前推荐的同机低延迟版本。它仍是一个 EA，
通过 `InpMemoryRole` 切换 Sender/Receiver，但直接导入 Windows 自带的
`kernel32.dll`，不再依赖、编译或复制 `RlfcMemoryBridge.dll`。

数据通路：

`源MT5 -> WinApiMemoryLossFollow -> kernel32 命名共享内存 -> WinApiMemoryLossFollow -> 跟单账号`

实现与保护：

- `CreateFileMappingW(INVALID_HANDLE_VALUE, ...)` 创建系统分页文件支持的命名共享内存；
- `MapViewOfFile` 映射同名内存，两个 MT5 任意顺序启动，先启动的一端负责初始化；
- Windows named mutex 串行化读写，避免读取写到一半的 payload；
- 通道名附加稳定哈希，避免名称清洗或截断后让不同通道误用同一 Windows 对象；
- 每个通道只允许一个 Sender；同一通道、接收账户和 `InpCopyMagic` 只允许一个 Receiver，
  避免重复挂载后重复跟单；
- Sender 默认启用 `InpSenderExcludeOwnCopies`，不把本版本产生的跟单仓再次发布，
  双向互跟时阻断 A→B→A 的循环复制；
- header sequence + payload CRC32 校验，并在发送端重启时续接 sequence；
- Receiver 保留最后一份完整快照，并用 stale timeout 阻止旧快照继续开单；
- 毫秒定时器启动失败时终止初始化并释放 mapping、mutex 和角色占用锁；
- 只支持 Windows x64，同一 Windows 登录会话中的 MT5 进程。

安装：

1. 把 `WinApiMemoryLossFollow.mq5` 分别放进两个终端的 `MQL5/Experts/` 并编译。
2. 两个终端挂载同一个 EA，并都勾选 **Allow DLL imports**；这里只加载 Windows
   系统自带的 `kernel32.dll`，无需向 `MQL5/Libraries/` 复制任何 DLL。
3. 源账号选择 `MEMORY_FOLLOW_SENDER`，跟单账号选择 `MEMORY_FOLLOW_RECEIVER`。
4. 两边的 `InpChannelName` 和 `InpSharedMemoryCapacityKB` 必须一致。
5. Sender/Receiver 没有加载顺序限制，默认轮询周期为 `20ms/20ms`。
6. 面板的“暂停新开”不会删除已经存在的跟单挂单；需要阻止挂单后续成交时，
   再点击“删除挂单”（该按钮也会自动保持暂停新开）。

双向互跟要使用两个独立通道：A 端 Sender 与 B 端 Receiver 使用 `A_to_B`，
B 端 Sender 与 A 端 Receiver 使用 `B_to_A`。每个 Receiver 的源 EA Magic 必须只匹配
对端策略 Magic，且和本端 `InpCopyMagic` 不同；保持 `InpSenderExcludeOwnCopies=true`。

## MT4↔MT4 / MT4↔MT5 WinAPI 版

`WinApiMemoryLossFollow.mq4` 是 MT4 对端源码，和 MT5 的
`WinApiMemoryLossFollow.mq5` v1.30 使用同一套 Windows named mapping、mutex、64 字节 header、
sequence、CRC32 和 `RLMC1` payload。文件扩展名按终端分别使用：

- MT4：编译并挂载 `WinApiMemoryLossFollow.mq4`；
- MT5：编译并挂载 `WinApiMemoryLossFollow.mq5`；
- Sender 与 Receiver 可以任意组合为 MT4→MT4、MT4→MT5 或 MT5→MT4；
- 两端保持相同的 `InpChannelName`、`InpSharedMemoryCapacityKB`；
- 两端都开启 DLL imports，只调用系统 `kernel32.dll`，没有额外 DLL 文件；
- MT4 的 `InpCopyMagic` 范围为 `0..2147483647`；
- MT4 以订单 ticket 作为稳定源 ID，并用 20ms timer + tick 轮询交易变化；
- 源 EA 匹配、三档跟单、挂单、网格激活、SL/TP、同步平仓、盈利平仓、
  北京时间首单过滤和 Receiver 面板与 MT5 版保持一致。

混合双向互跟仍使用 `A_to_B`、`B_to_A` 两个通道，每个终端各挂一个 Sender 和一个
Receiver 实例，并保持 `InpSenderExcludeOwnCopies=true`。共享内存范围仍是同一台
Windows 主机、同一登录会话。

## 本机免 DLL 文件版

`FileLossFollow.mq5` 是一个纯 MQL5 的统一 Sender/Receiver EA，使用 MT5
内置的 `FILE_COMMON` 公共目录交换快照：

- 源账号设置 `InpFileRole=FILE_FOLLOW_SENDER`；
- 跟单账号设置 `InpFileRole=FILE_FOLLOW_RECEIVER`；
- 两端只需保持 `InpChannelName` 一致；
- 不依赖 DLL，不需要勾选 DLL imports；
- Sender 或 Receiver 任意一端先加载都可以，Receiver 在快照出现前保持等待状态；
- 使用临时文件写入后原子替换、RLFC2 sequence、数量和结束标记校验，避免读取半截快照。

该版本保留与远程 Receiver 相同的源 EA 匹配、三档跟单、挂单、网格激活、
SL/TP、同步平仓、盈利平仓、品种映射和北京时间首单过滤逻辑。默认文件
轮询为 `50ms/50ms`，部署最简单；追求更低传输延迟时再使用上面的共享内存版。

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
