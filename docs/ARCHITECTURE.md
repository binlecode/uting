# ARCHITECTURE —— uting

`ut-play` · `yt-search` · `yt-resolve` · `bili-search` · `bili-resolve` · `ut-playlist` ·
`ut-history` · `uting` —— 一套"搜索 + 终端播放"的 CLI 套件，为 **LLM/agent 调用方**设计的程度
不亚于为人设计。范围是整套套件，这份是伞状的那一份：**图、流程、伪码与决定**。
具体怎么落地，各面各住一份，本文的引用一律指过去：

```
   docs/
   ├── ARCHITECTURE.md          ← 你在这里。伞：定位与非目标（§1）、六条发现（§1.1）、
   │                              设计决定（§3，按模块与接口）、拓扑与接缝、控制流、
   │                              函数图、四条工作流、已知约束（§26）、bash 3.2 契约（§28）
   ├── AS-BUILT-contract.md       冻结的 CLI 面：命令面、把门、envelope、退出码、配置键
   ├── AS-BUILT-engine.md         站点那一半：搜索、解析、登录/PO-token 探测、句柄文法
   ├── AS-BUILT-player.md         播放器、队列，与两个持久存储
   ├── AS-BUILT-tui.md            人机面：两个视图、宽度层、重排、三个播放态
   ├── AS-BUILT-verification.md   风险登记与验证矩阵
   ├── ROADMAP.md                 还开着的：记下来的 NO、重开条件、没做的事
   ├── RESEARCH-tui-player.md     这套决定所依赖的那份外部调研
   └── PLAN-<topic>.md            在飞的工作
```

组件清单、PATH 拓扑与运行时依赖图在 §4；每个动词自己的 `-h`/`--help` 是调用方的表面，
入门指引是 `README.md`。

全文脉络：**I. 系统架构 → II. 功能结构 → III. 模块 API → IV. 支持的工作流 →
V. 对齐的最佳实践。** 骨架是图，不是散文 —— 按序读下面六张，就读完了整个系统，
而 §3 的设计决定按模块与接口分组，每组也挂在其中一张上：

```
   §2     系统全景图               谁在敲、谁在调、原语与外部世界在哪
   §4     PATH 拓扑 + 运行时依赖图   八个平级成员；站点知识与播放各锁在哪
   §6     播放器的 argv 路由         一条命令行怎么变成一次行为
   §6.1   进程树 A / B / B′ / C      哪些进程会跑；抽取发生在哪、恰好一次
   §17    函数图                     每个子系统的函数按名字可寻
   §18–21 四条工作流                 人一条（交互式），agent 三条
                                     （搜→播 · 只解析 · 后台 + 生命周期控制）
```

---

# 第一部分 —— 系统架构

## 1. 为什么有这套东西 / 设计目标

这套套件是**直接**暴露给有 shell 能力的 agent 的（Claude Code、OpenCode），**不套 MCP 包装**
—— 包装层只会把 CLI 已经提供的东西用一个更窄、更难维护的接口重新编码一遍，
同时绕开 agent 宿主自己的权限门。于是 **CLI 契约本身**（argv、退出码、输出形状、进程生命周期）
*就是*可用性与安全的边界。下面每一个设计选择，都是"把这份契约当作产品"推出来的结果。

**定位**：一个 **agent 优先的媒体引擎**（一个不认识任何站点的播放器 + 一对一对可插拔的引擎），
外加**一张给人的终端脸**。音源数量不属于定位 —— 今天两个（YouTube、B 站），站点知识只住在引擎
对里，加一个不改这一段。

**差异化是三件与渲染无关的东西**，加任何功能都不许动它们：单行 JSON envelope 契约、退出码分类、
脱离终端的播放器生命周期；以及同一套东西支持人和 agent 两种驱动。

**最大的那条非目标：不做通用 TUI 音乐播放器。** 理由不是"那层饱和了" —— 实测不成立
（`RESEARCH-tui-player.md` §3）：那层每月都有新项目起量，竞争已经打到终端图形协议封面、
参数 EQ/频谱、Lua 插件 ABI、同步歌词上 —— 全是别人靠语言和库免费拿到、而 bash 3.2 要从零
手写的东西（§1.1 第 1 条：那是负债，不是护城河）。也不去和 cmus 抢本地/MPD 那一格 ——
这里播的是引擎给的东西，不是 `~/Music/*.mp3`。**在范围内**的是这套音源上的收听完整度
（播放列表、队列、收听历史，§3.5）。其余非目标与已知约束在 §26。

判断一个新功能进不进来，先问这一节；答案是"不"的默认成立，除非定位本身被改写。

### 1.1 分析：驱动决定的六条发现

§3 的设计决定与 `ROADMAP.md` 的 NO 从这里取理由。**第 1、2、5、6 条合起来就是
ROADMAP D10（不做 Go 版）的全部账**：收益只剩"删渲染负债"，分发收益不兑现，成本是一次无法二分的回归。

1. **差异化在契约，不在渲染。** 真正难而有价值的是 JSON envelope、退出码分类、脱离终端的
   生命周期 —— 都与语言无关。而 `uting` 的大头是在重新实现 Go TUI 栈免费给的东西：显示宽度
   （`go-runewidth`/`uniseg`）、事件循环与 resize（`bubbletea`）、样式（`lipgloss`）。
   那不是护城河，是重写会**删掉**（而非搬迁）的负债 —— 但删负债是**内部**收益，
   不改变产品对人与 agent 呈现的任何一件事。

2. **single-binary 是全有全无。** 一个静态二进制、不要 jq、不要 nc、Linux 能跑、安装一行 ——
   链条里留一个 shell 脚本就整体作废。而引擎按 ROADMAP D10 在任何情况下都不移植（第 6 条），
   所以 Go TUI 或 Go 播放器接 shell 引擎仍是四依赖。所以 "best of both worlds"
   在**风险**维度成立，在**分发**维度不成立 —— 而分发才是唯一能兑现的外部收益。

3. **agent 对接的是窄动词的 argv + 它们背后的契约。** 没有壳可言 —— 窄动词就是实现本身，
   `ut-play` 与四个引擎都是平级 peer。所以真要换语言，能换的单位也只有**播放器**，
   而引擎整条留在 shell：它们才是随外部网站变动而频繁改的那一半（第 6 条）。
   **但"守护进程 + CLI 动词 + JSON"这个形状不是本项目独有的**
   （`RESEARCH-tui-player.md` §3.3）：`spotify-player` 用不同音源做了同一件事且早于本项目。
   所以差异化**不能**建在"有 CLI"上，只能落到**契约的严格度** —— 退出码分类、幂等 stop、
   歧义即 4、单行 envelope、脱离终端后仍可查/停/调音量。

4. **两个 agent 侧诉求落在播放器/新脸上，且 bash 都给不了。**

   | 想要的 | bash 为何不行 | 归属 |
   |---|---|---|
   | MCP stdio server | 手写 JSON-RPC 帧、长连接、并发 | 会是第三张脸（既非播放器也非引擎）—— 今天是非目标，也是 ROADMAP D10 的重开条件 |
   | 流式进度 | 阻塞 `read`、一次性 jq | 引擎（search）+ 播放器（`--status`） |

5. **yt-dlp 与 mpv 在任何方案里都是子进程，Go 也一样。** 引擎的真实价值是 **flag 学问**
   （`--ytdl-format=ba/b`、`--ytdl-raw-options`、`--msg-level` 噪音压制、`--no-video` 与
   term-osd、socket 路径、reap 规则），换语言也只是把 argv 数组原样搬 —— 买不到能力，
   只买到风险，而风险在边缘语义：直播行、null 播放量、两种时长拼法、`--stop` 幂等、锁顺序。

6. **agent 驱动两面都成立，第二面支持 shell。** 使用层面语言无关。开发层面：shell 利于
   **迭代**（无构建、可整文件读懂、原地改、pty 立验、ssh 上 `vi` 就能修）；Go 利于
   **重构安全**（本套件已出过三次 `set -e` 回归 —— 正是编译器一次消灭的一类）。
   这是 Go 一侧唯一没有被前几条驳倒的收益，仍不足以压过第 2 条与第 5 条，但方向相反，必须记录。

## 2. 系统全景 —— 两个面，都 100% 自有

整条路径上没有任何有主见的第三方媒体客户端。所有站点相关的编排都活在我们自己的代码里；
外部原语只干通用的、与站点无关的重活，且每一个都被隔离在**单一接缝**之后（§5）。

整个系统一张图 —— 从谁在敲，到谁在抽取，中间每一层都在这里：

```
 ┌ 驱动方 ───────────────────────────────────────────────────────────────────────
 │
 │      人（TTY · 键位）                    LLM / agent（argv，直连，不套 MCP 包装）
 │            │                                        │
 │            ▼                                        │  单行 JSON envelope + 退出码
 │      ┌───────────┐                                  │  （契约本身就是产品面，§3.8）
 │      │   uting   │ ───── 调的是同一批命令 ─────────►│
 │      └───────────┘   人机面：只有渲染               │
 │                      站点与播放一样都不碰           │
 └───────────────────────────────────────────┬─────────┘
                                             ▼
 ┌ 八个平级可执行文件：一层，无内核，无共享库（§4）────────────────────────────
 │
 │   ┌───────────────────────────┐   -j envelope   ┌───────────────────────────┐
 │   │ yt-search     yt-resolve  │ ◄────────────── │ ut-play                   │
 │   │ bili-search   bili-resolve│ ──────────────► │  队列 · detached 生命周期 │
 │   └───────────────────────────┘  直链 + 请求头  │  死亡记录 · 运行时 IPC    │
 │     引擎：一站一对                              └────┬─────────────────┬────┘
 │     站点知识**只**住这里                             │ --record        │
 │                                                      ▼                 │
 │   ┌───────────────────────────┐   人存的 / 播放器写的                  │
 │   │ ut-playlist   ut-history  │ ◄──────────────────────────────────────┘
 │   └───────────────────────────┘   两个存储：既不认站点，也不认播放
 │        ▲
 │        └── uting 也从这里取行渲染（--show -j / --ls -j）；一条记录就是一次调用
 └──────────────────────────────────────────────────────────────────────────────
         │  yt-dlp · curl · jq                        │  mpv --no-ytdl · nc -U <sock>
         │  （站点原语只在引擎里）                    │  （播放原语只在播放器里）
         ▼      —— 每一个都关在单一接缝后（§5）——     ▼
 ┌ 外部世界 ─────────────────────────────────────────────────────────────────────
 │   youtube.com · bilibili.com                        音频输出 · 运行时控制
 │   抽取恰好发生一次，且发生在引擎里（§6.1）
 └──────────────────────────────────────────────────────────────────────────────
   数据文件（不是代码，也不 source）：VERSION 声明版本，config 声明默认值（§4、§3.6）
```

图里每一个方块都是暴露在 PATH 上的平级成员；底下没有一个隐藏的内核，彼此之间也没有共享库（§4）。

**所有权为什么要紧（§3.1）。** 调研过的替代品都被否决为运行时依赖：`ytfzf` 已休眠
（约 21 个月，GPL-3.0）—— 客户端层面的锁定风险；`yewtube` 是一个更重的 Python 应用；
`yt-x`（MIT，活跃）只被当作布局与键位创意的*参考* —— 没有取用它的代码，也没有引入依赖。
反正所有客户端的瓶颈都是 `yt-dlp`，所以第三方客户端买不到任何我们自己拼不出来的能力，
却要拿可移植性去付账。结论：**胶水自己写，只依赖原语**。

**这条所有权的线划在哪（§3.1）。** 拥有的是**接缝**，不是一个内核。
站点知识归自己所有，并被关在一对引擎里；播放与生命周期归自己所有，
并被关在播放器里；在两者之间穿过去的，是这份文档规定的一个 JSON 信封
（AS-BUILT-contract.md §3），而不是一次函数调用。

## 3. 设计决定（按模块与接口）

每条一到两行，**挂在它所属的模块、以及那个模块对外的接口上** —— 这里只留决定本身，
完整理由住在被引用的那一节。**引用键是小节号**（`ARCHITECTURE.md §3.4` 这样写），
一条决定只住一个小节。`ROADMAP.md` 自己那套 `D#`（如今只剩记录在案的 NO：D2、D9、D10）
与这里无关，引用它永远写成 `ROADMAP D2`，绝不写成光秃秃的 `D2`。

### 3.1 套件 —— 八个平级动词（接口：文件名 + argv，共享的是信封不是代码；§2、§4 的图）

- **没有内核**：八个平级成员各把自己的门、各调自己的原语，共享的是**信封**，
  不是代码。（§4）
- **一个命令一个名字，且不发短名**；三条命名规矩与挡住重提的落选名在 §4。
  （§4、RESEARCH-tui-player.md §2）
- **按「播放器 + 可扩展引擎对」切，不按站点开命令**：与音源无关的是播放器，
  引擎 = search / resolve 两个动词；resolve 发生在**播放时** —— 直链会过期，
  10 条结果只用 1 条。（§4、§6.1）
- **不依赖第三方媒体客户端** —— 胶水自己写，只依赖原语。（§2）

### 3.2 调用形状 —— 非交互与把门（接口：argv → 退出码，每个动词自己把门；§6）

- **除 `uting` 之外的一切都是非交互的**：一个能提问的动词就是 agent 会挂住的动词；
  把能力拿掉，那种失败模式就不可能发生。（§6）
- **一个没有东西可作用的动词 → 用法错误，且点名正确的那个动词**；绝不提问。（§6）
- **搜索是它自己的动词**（`<engine>-search`），**不是**播放器的一种多态拼法：
  `ut-play` 拿到一个非句柄时点名那个动词，而不是去猜。（§6）

### 3.3 播放器 —— 播放与 detached 生命周期（接口：`-d` 信封的 id/pid/socket、`--status`/`--stop`；§6.1-B/B′/C）

- **detached 句柄 = 一个单调的 mktemp token，不是 pid**：socket 路径启动前已知，
  且对 pid 复用免疫；pid 只留着做存活判断。（AS-BUILT-player.md §9.3）
- **一个 detached 播放器没有键盘**（stdin → /dev/null，`--input-terminal=no`）——
  上一条那个进程组模型的**后果**，不是一个独立的选择。（AS-BUILT-player.md §9.1）

### 3.4 引擎 —— 站点知识的边界（接口：search / resolve 两个动词 + 两个信封 + `--engine` 拼名；§6.1-A、§7、§10）

- **引擎名就是命令前缀**：`--engine yt` 靠字符串拼接找到 `yt-resolve`，
  加一个源不会在播放器或 TUI 的任何地方加出注册表。（§4）
- **一个引擎靠有没有那个动词声明能力** —— 不给一个永远答"没有"的动词，
  那种东西调用方分不清它与"今天不走运"。（AS-BUILT-contract.md §1）
- **resolve 只解自己站的 host**，别的一律退 1：`engine` 字段的全部意义是路由，
  通配让它说谎。（AS-BUILT-engine.md §10）
- **登录状态只报到"发不发"这层**：`--auth` 印 cookie 决定，不是鉴权裁决；
  升级路径是 `--auth --probe`、不改 `auth` 键的语义。
  （AS-BUILT-engine.md §8.2、AS-BUILT-contract.md §1.3/§3）
- **引擎内部按「操作」选原语**（B 站搜索走 curl，解流走 yt-dlp）：接缝是**信封**，
  不是它背后的工具。（§5、AS-BUILT-engine.md §7）
- **按 site 切不按 stack 切**：stack 会变、site 不会（`engine` 是被持久化的路由键）；
  样板重复是"一对自足文件"的代价。（§4、§17、§23）

### 3.5 两个存储 —— 播放列表与收听历史（接口：`--ls`/`--show`/`--add…` 与 `-j` 行，一行就是一次调用；AS-BUILT-player.md §9.4–§9.6）

- **持久状态是一个自己的命令、住在 $TMPDIR 之外**；存下的记录是 `{engine, url, …}`
  —— 一次**调用**，不是一个引用。队列是刻意的例外：一个正在被消费的播放列表，归播放器。
  （AS-BUILT-player.md §9.4、§9.5）
- **收听完整度在范围内**（播放列表、队列、收听历史；收藏 = 一个名字固定的播放列表），
  且每条功能**必有 agent 面**：人有按键，agent 有动词 + `-j`。历史默认开、`UT_HISTORY=0` 关。
  （§1、§26、AS-BUILT-player.md §9.4–§9.6）

### 3.6 配置 —— 两个根数据文件（接口：`KEY=value` 数据文件 + 四级链；§4）

- **默认值声明一次**：根上的 `config`，**当数据读、绝不 source**；链是
  标志 > 环境 > 用户配置 > 出厂。出厂那份没有命令会写；用户那份由 `uting` 写回七个偏好键。
  （§4；键表与写回：AS-BUILT-contract.md §5）

### 3.7 人机面 —— `uting`（接口：键位 + 自绘渲染，对下只调那些动词；§11 → AS-BUILT-tui.md）

- **`uting` 画自己的菜单**（不用 picker/TUI 框架）并把活委派给动词。（§11）
- **套件里任何地方都不用 fzf / 交互式依赖。**（§11）
- **`uting` 只组合那些动词** —— 不碰引擎的内部，也不碰 mpv，
  除非经由播放器已经公布出来的那个 socket。（AS-BUILT-contract.md §2）
- **TUI 里不用 emoji**：17 个字形的封闭库存，全部文本呈现，宽度表因此**精确**
  而不只是保守。（AS-BUILT-tui.md §11）

### 3.8 冻结面 —— 契约本身（接口：整份 AS-BUILT-contract.md）

- **契约（含引擎契约）是被冻结、被版本化的那个面** —— 唯一完整活过重写的东西，
  也是任何一次移植的验收规格；semver 2.0.0 版本化它、不是代码（0.y.z 期间：破坏性 → y，
  其余 → z），**1.0.0 = ROADMAP D2 反转那一天**。（边界表与 bump 判法：AS-BUILT-contract.md 开头）

## 4. 命令拓扑与文件布局

**八个命令，一层，无库。** 没有内核，也没有包装层。每个文件都是一个完整的、暴露在 PATH 上的
可执行文件，自己把自己的 flag，自己调自己的原语。它们的划分依据是*各自持有哪一类知识*，
而不是谁调谁：

- **播放器**（`ut-play`）持有播放与 detached 生命周期，**不认识任何站点**；
- **一个引擎是一对** —— `<name>-search`（查询 → 结果）与 `<name>-resolve`
  （句柄 → 流 URL + 请求头，外加该站点支持的只读动词）—— 它持有某一个站点的**全部**知识；
- **两个存储**（`ut-playlist`、`ut-history`）持有用户级的持久状态，既不认站点也不认播放 ——
  一条记录是 `{engine, url}`，那是一次**调用**而不是一个引用（`AS-BUILT-player.md` §9.4）；
  播放列表是人放进去的，日志是播放器写下的（§9.6）；
- **人机面**（`uting`）持有渲染，以上三样一样都不持有。

```
                          PATH 上的入口（用户自建的符号链接）
        ~/bin/
        ├── uting        → <checkout>/shell/uting          人机面
        ├── ut-play      → <checkout>/shell/ut-play        agent 面
        ├── yt-search    → <checkout>/shell/yt-search      agent 面
        ├── yt-resolve   → <checkout>/shell/yt-resolve     agent 面
        ├── bili-search  → <checkout>/shell/bili-search    agent 面
        ├── bili-resolve → <checkout>/shell/bili-resolve   agent 面
        ├── ut-playlist  → <checkout>/shell/ut-playlist    agent 面（可选）
        └── ut-history   → <checkout>/shell/ut-history     agent 面（可选）
              一个命令一个名字；不发短名（§3.1）

   运行时依赖图 —— 站点知识**只**在一对引擎里，播放**只**在播放器里：

     uting ──► <engine>-search -j ──► 渲染 ──► ut-play -d -j --engine <该行的引擎>
        │  ▲                                           │
        │  ├──── ut-playlist --show -j   同样的行，另一个来源（player §9.4）
        │  └──── ut-history  --ls   -j   还是同样的行（player §9.6）
        └──► nc -U <sock>  （路径是播放器公布的；player §9.3）
                                                       ▼
                                   ut-play ──► <engine>-resolve -j -f MODE
                                        │            （名字靠拼接，§3.4；
                                        │              yt-dlp / curl 住在**这里**）
                                        ├──► mpv --no-ytdl <直链>
                                        └──► ut-history --record -   （一首一行）
```

**八个名字怎么来的（§3.1）。** 三条命名规矩，一条对一类受众：人机面用发行名（`uting`），
播放器带套件前缀（`ut-`），一个引擎带它那个**站点**的名字 —— 因为那是调用方必须知道的
唯一一件事。不发短名：六项筛查里长前缀全空、短名全被占（`RESEARCH-tui-player.md` §2；
挪威语里 `uting` 是真词"陋习"，当彩蛋接受）。挡住重提的落选名：`ut-list`（与 `-l/--list`
撞车）· `ut-lib`/`ut-store`（两件事挤一个命令）· `ut-queue`（队列是播放器的运行时状态，
`AS-BUILT-player.md` §9.5）。说 "tui" 而不说 "ui"：uting 恰恰是一个全屏的*终端* UI。

**引擎名就是命令前缀（§3.4）。** `--engine yt` 靠字符串拼接找到 `yt-resolve`
（`ut-play` 约第 228 行：先试 `$SCRIPT_DIR/$ENGINE-resolve`，再试 PATH，
都没有就退 1 并把引擎名说出来）。这就是全部的"注册表"。加第三个源等于加一对新文件，
播放器与 TUI **一个字都不用改** —— 这正是 Bilibili 引擎被造出来要检验的那条主张，
而它成立了：步骤 C 两个文件都没动。

**`uting` 怎样在不持有名单的前提下找到引擎。** 启动时它扫自己所在目录和 PATH 找
`<name>-search`，且只有当 `<name>-resolve` 就在旁边时才保留这个名字 ——
装了一半的引擎不算引擎。`e` 切换源并重新取数；只装了一个引擎时，这个交互干脆不画出来。
它交给 `ut-play` 的 `--engine` 来自搜索信封自己的 `engine` 字段，绝不来自某个默认值
（`AS-BUILT-tui.md` §11）。

**为什么是四个引擎命令，而不是 `yt search|resolve` 子命令。** 一个窄动词的 flag 面也窄，
而这正是小模型敢调它的原因：`yt-search` 从字面上就不可能接受 `--detach`，
`ut-play` 从字面上就不可能去搜索。子命令分发器会把这些面重新并回一套 argv 文法，
并把门重新塞回程序内部 —— 那正是拆分之前门所在的位置。`resolve` 是暴露出来的，
但它不是给模型用的：实际上它的调用方是 `ut-play`，模型看见的是 `<engine>-search` 加 `ut-play`。

**为什么播放器绝不能叫得出自己的引擎。** `ut-play` 从不读引擎的文件，不 source 它任何东西，
也不持有一份合法名字的清单 —— 一个未知的 `--engine` 是靠"拼出来的那条路径不存在"被发现的。
这与把版本号放进 `VERSION` 是同一条依赖方向的规矩：一个一行的数据文件，
因为把变量放进八个独立可执行文件中的任何一个，都会让另外七个反过来向*它*要版本 ——
而播放器除了"把这个解出来"之外还向引擎要任何东西，正是这次拆分要消掉的耦合。

它坐在**仓库根**，而不是脚本旁边：它版本化的是这套套件，不是 `shell/`，
而根目录是读者 —— 以及其他任何项目 —— 找它的地方。每个入口点都从自己**解析之后**的位置
往上一层去够它，这也是为什么 `SCRIPT_DIR` 前面那段符号链接链的行走是承重的、不是装饰：
`~/bin/ut-play` 是一条指进 checkout 的符号链接（ROADMAP D2），所以一个朴素的 `dirname`
得到的是 `~/bin`，那里既没有 `VERSION` 也没有引擎。`ut-play` 曾是唯一一个不走这段行走的
入口点，于是通过符号链接调用时 `--version` 答的是 `unknown`；现在它按它兄弟们一直以来的
方式解析。`tests/contract.sh` **通过一条真符号链接**把这个值钉死在文件上，
因为八个入口点全都打印 `unknown` 时，它们彼此完全一致。

**根上有两个数据文件，不是一个 —— `VERSION` 与 `config`，而第二个在这里的理由就是第一个的
理由。** 默认值曾经是各脚本内联的 `: "${KEY:=值}"`，于是一个跨引擎的默认值
（`UT_MAX_SEARCH_RESULTS`）在读它的每个引擎里各写一遍。那不是重复的美学问题，是一个
**没有东西会发现的漂移面**：把默认值收进一个文件，当场就抓出 `UT_PLAY_MODE` 在四个脚本里
不一致、`UT_SORT_FIELD` 在三个里不一致（根因见下）。所以配置走的是 `VERSION` 那条路
——一个根上的数据文件，八个入口点各自读它——而**不是**一个 source 进来的库：
一个共享库会让另外七个反过来向持有它的那一个要值，正是这一节开头那条依赖方向的规矩
所要消掉的耦合。代价是老实的：读它的那段块在八个入口点里**逐字重复**，
而逐字节的副本可以 grep 出漂移。

这个文件**不是可选的** —— 缺了它的 checkout 是坏的，一行话，退 **2**，
而且刻意**没有**给 `--version`/`--help` 留后门：放行之后 `set -u` 会在一百行之后报一句
`YT_ASCII_VO: unbound variable`，把一句清楚的话换成一句不清楚的。
一个缺了自己一部分的 checkout 不是**依赖门**（yt-dlp/jq/mpv 没装时 `--version` 照样答），
它是坏 checkout。

**当数据读，绝不 source。** 一个会被 source 的配置文件可以运行任何东西，
而这套套件的整个安全故事就是它的输入是数据 —— 与"任何 shell 出去的参数都走数组、
绝不走一条重新引号化的字符串"是同一条规矩的另一面。
读进来的键只认 `UT_`/`YT_`/`BILI_` 三个命名空间，所以一个文件永远够不到 `PATH`、`TMPDIR`
或 `LD_PRELOAD`；播放器为自己 detached 子进程设的那四个在允许的命名空间**之内**被拒。

**两条规矩是这次搬迁自己教出来的，都不显然：**

- **轮换顺序不是合法值域。** `uting` 的 `-f`/`-s` 曾对着 `MODE_CYCLE`/`SORT_CYCLE` 校验 ——
  在那还是一个等于全集的常量时安全，一旦它可配置，一个收窄了的 cycle 就开始拒绝引擎
  接受的值，并逼着 `uting` 的默认值与引擎的不一致。两个标志现在对着**封闭集**校验，
  cycle 只是 `v`/`o`/`t` 轮换的顺序。
- **"未设置"本身是一次自动探测的旋钮，不能进出厂文件。** 在文件里给它一个值，
  和用户自己设了它无从区分，于是恰好废掉了作为其默认值的那次探测。
  `YT_LANG`、`YT_ASCII`、`UT_STATE_DIR` 因此仍然内联 —— `YT_ASCII` 尤其：
  一个值会让遗留别名 `YT_TUI_ASCII` 变成**读起来仍像被支持的死代码**。

键表在 `AS-BUILT-contract.md` §5，不在这里。

**为什么每个动词自己把门（§3.1 的反面）。** 旧形状是一个内核加两层把门的包装，门是一个*层*。
搜索与抽取搬出去之后，播放器只剩一个动词，于是也就不存在需要防守的绕过路径了 ——
而原来住在包装层里的那些分支，如今变成了在调用方真正够得到的那一个地方给出好错误的分支：
`ut-play` 里的 `-n`/`-m`/`-M`/`-s` 回答"那是搜索的 flag —— 请用 `<engine>-search`"，
`--info`/`--transcript` 回答"那是引擎的动词"，`--get-url` 则回答那条取代了它的
`<engine>-resolve` 调用。**一扇能说出正确动词的门，比一扇只会说不的门值钱。**
每条消息里的 `<engine>` 是**拼出来的**（`$ENGINE`，来自 `--engine` 或 `UT_DEFAULT_ENGINE`），
不是写死的 `yt`：一扇给 bili 调用方指向 YouTube 命令的门，说的是正确动词的**错误名字**。

**自定位的兄弟，而不是 PATH 查找。** 以 `~/bin/uting` 被调用时，脚本的 `$0` 是那条**符号链接**，
不是代码本身 —— 所以每个脚本先解析自己的符号链接链，再拿真实文件所在的目录去找兄弟。
机制就是这么多，而这正是为什么 checkout 可以放在任何地方、且不需要一个 `bin/` 条目也能工作。

用 `cd -P` / `pwd -P`，不用逻辑形式：一条相对符号链接会解析出类似
`~/bin/../../../elsewhere/shell` 的东西，而逻辑 `cd` 会把那些 `..` 按文本对着 `~/bin` 归一化，
而不是对着 `~/bin` 真正指向的地方 —— 于是落进一个不存在的目录。bash 3.2 没有 `readlink -f`，
所以是手写的循环。（它取代的是更早的 `../../shell-scripts/` 那一跳，那一跳只在某一种特定的
dotfiles 布局里成立；把套件抽成自己的仓库，才把它暴露出来。）

任何通过 PATH 按名字调用它们的东西 —— agent 的工具定义、Claude Code 的 Bash 允许清单 ——
用的就是上面那八个名字。而 checkout **内部**的调用方（`tests/` 里的两个套件、技能）
改用仓库相对的 `shell/<name>` 形式：它们与代码同处一地，绝不能依赖用户的 PATH ——
一条经由 `~/bin` 解析的检查，测的是安装，不是套件。

**支配原则，不因拆分而变，只被拆分磨得更锋利：** 正确性往**下**加 —— 与播放有关就加在
播放器里，与站点有关就加在引擎里 —— 这样每一个面都继承它；绝不往**上**加进某个 UI。
一个本可以由 `ut-play` 做的修复却做在了 `uting` 里，那是一个"改错了文件"的 bug。

## 5. 原语与接缝（可替换点）

**接缝如今按文件切开。** 没有任何一个文件同时担任其中两个角色，而 `ut-play` 里的一次 yt-dlp
调用、或引擎里的一次 mpv 调用，都是分层违规，不是接缝。

| 原语 | 角色 | 谁可以调它 | 接缝（唯一的调用点） |
|---|---|---|---|
| **yt-dlp** | 抽取 | 只有引擎 | `fetch_results`（`yt-search`）；`dump_once`、`resolve_info`、`resolve_transcript`（`yt-resolve`）；`dump_once`、`resolve_info`（`bili-resolve`） |
| **mpv** | 播放 | 只有播放器 | `run_mpv()`（唯一的播放接缝）+ `mpv_supports_vo()` 能力探测 |
| **curl** | HTTP 传输 | `bili-search`（它的传输层）；`yt-resolve`（仅探测） | `fetch_page_once`（`bili-search`）—— 全套件唯一一处手工拼请求的地方；`probe_raw`（`yt-resolve`，可取性探测） |
| **nc** | mpv JSON-IPC | 播放器，以及作为客户端的 `uting` | `live_props` / `do_set_volume`（`ut-play`）；TUI 自己的客户端（`AS-BUILT-tui.md` §11） |
| jq | JSON 整形 | 所有人 | 无处不在 |

**mpv 藏在一个函数后面。** 五种 `play_*_url` 模式全部经由 `run_mpv` 出去，所以换掉它
（mpv→vlc）基本是一处局部改动；有两个 mpv 专有的细节出于必要待在它外面 ——
`mpv_supports_vo()` 去问 mpv 它有哪些终端 VO，而 `play_viz_url` 把 mpv 的
`--lavfi-complex` showwaves 滤镜穿过 `run_mpv` 传进去。

**mpv 不运行 yt-dlp。** `run_mpv` 传的是 `--no-ytdl` 加一个引擎已经解出来的直链。
让 mpv 自己抽取，就意味着任何一次播放里**最后**那次抽取不是我们发起的：分类不了它，
只能通过 `--ytdl-format` / `--ytdl-raw-options` 去间接影响。这里是
**一次播放一次抽取，且由我们来发** —— 这也正是那份 reason 枚举诚实的原因，
因为会失败的那次调用，是一次我们读得到 stderr 的调用。

**一个引擎的两半不必用同一种原语。** `bili-search` 用 `curl` 说 HTTP，
而 `bili-resolve` 外壳调用 `yt-dlp`；YouTube 那一对两半都用 `yt-dlp`。
一半与它的调用方之间的接缝是**信封**（AS-BUILT-contract.md §3），不是背后那件工具 ——
这也是为什么拆分是按*操作*而不是按站点（§3.4）。

**yt-dlp 是在表里那些点上被调用的，而不是收在单一接缝后** —— 但它是每个客户端都依赖的
抽取标准，所以"替换它"不是一个现实目标；价值在于每一处都是一个朴素的 `yt-dlp …` 数组，
而不是埋在某个第三方客户端里，并且它们全都在引擎内部。**jq** 无处不在。
列表内的过滤一个原语都不用（`AS-BUILT-tui.md` §11）。

---

# 第二部分 —— 功能结构

## 6. 端到端控制流

每个动词解析自己的 argv；没有任何一个会 exec 成另一个。播放器的解析是最大的一份，
这里展示的就是它 —— 引擎用的是同一套三段形状（长选项归一化 → `getopts` → 校验），
只是各自的 flag 集不同（AS-BUILT-contract.md §1）。

```
   $ ut-play -d -j --engine yt -- "https://youtu.be/ID"
        │
        ▼
   ┌───────────────────────────────────────────────────────────────────
   │ ut-play
   │  (a) 长选项**归一化**循环
   │      --json→-j  --detach→-d  --list→-l  --help→-h --version→-V
   │      --color/--volume/--engine/--id → 变量
   │      --status/--stop/--set-volume   → set_action
   │      --get-url / --info / --transcript → die，并点名 <engine>-resolve
   │      未知的 --flag → die，并**列出**播放类 flag
   │      `--` → 选项到此为止：其后原样复制（连 getopts 也一起停）
   │  (b) getopts  ":f:S:dljhV"  → MODE、FORMAT_SORT、OUTPUT_MODE
   │      未知的 -n/-m/-M/-s → die "那是搜索的 flag"
   │      未知的 -J          → die "那是引擎的 flag"
   │  (c) **校验**  --color 枚举、--volume 0-100、只许一个动作、
   │      --id 只能配 stop|set-volume、--all 只能配 stop、
   │      -d 不能与任何动作同用、-d 不能配 ascii|viz
   │  (d) IS_HANDLE？非空**且**不含空白
   │      （整个判断就这么多 —— 见下）
   │  (e) **路由**（先匹配先赢）：
   │        没句柄也没动作 → die，点名 <engine>-search / uting（§3.2）
   │        ACTION=status     → do_status      （只要 jq；退 0）
   │        ACTION=stop       → do_stop        （只要 jq；退 0|4）
   │        ACTION=set-volume → do_set_volume  （jq+nc；退 0|4）
   │        require_deps jq mpv        ◄─ **不**要 yt-dlp；那是引擎的依赖
   │        IS_HANDLE：
   │           DETACH      → detach_play      （后台）
   │           OUTPUT=json → play_url_json    （结构化）
   │           否则        → play_url_directly（散文）
   │        否则 → die "'<x>' 不是一个视频 id 或 URL —— 用
   │                    '<engine>-search -- <x>' 去搜它"
   └───────────────────────────────────────────────────────────────────
```

**播放器**刻意**分辨不出一个句柄是好是坏。** `IS_HANDLE` 就是"非空且不含空白"，仅此而已。
id 的*形状*（`dQw4w9WgXcQ`、`BV1FPjy6TEiE`）是引擎知识，而把它交出去正是拆分的意义 ——
于是一个解不开的句柄浮现为一次**被转述的引擎失败（2+）**，而不是一个用法错误（1）。
播放器仍然作为用法错误拒绝的，是那些**根本不是句柄**的东西：空的，或者含空白 ——
那是一条搜索查询，归另一个动词管。

**由构造保证的非交互（§3.2/§3.2）。** 除 `uting` 之外没有任何动词会提问。"没有句柄"那道守卫跑在
mpv 依赖检查**之前**，于是消息讲的是缺输入，而不是缺播放器 ——
而 `-V` 在任何依赖门之前就被回答，因为"要先装上 yt-dlp 才能知道自己装的是哪个版本"是反的。

**每一个动词都遵守 `--`。** 归一化循环在 `--` 处停下，把其后的一切原样复制过去
（连 `--` 本身也复制，于是 `getopts` 也在那里停 —— 在 bash 3.2 上验证过）。
没有这一条，一条仅仅**长得像**长 flag 的查询就会变成一个动作：
`-l -- --status` 会去列播放器而不是搜那段文字，而一个以单个短横开头的句柄会被 `getopts` 吃掉。
这道守卫归每个动词自己 —— 没有一个层替它们守。

**一次调用一个动作。** `set_action` 记下是哪个 flag 认领了这次调用，并拒绝第二个不同的
（`--status --stop` → "conflicting actions"），而一个"最后一个 flag 赢"的解析会静默丢掉第一个。
`--id`/`--all` 在 `--stop`/`--set-volume` 之外被拒，`-d` 与任何动作并列时被拒 ——
被接受然后忽略是最难看见的那种失败，所以这三样都是硬拒。

**为什么在 getopts 之前要有一个归一化循环：** bash 的 `getopts` 只认单字母。
这个循环把**有**短形式的长选项映射过去（`--json`→`-j`、`--detach`→`-d`、`--list`→`-l`、
`--help`→`-h`、`--version`→`-V`），并把没有短形式的那些 —— 那些动作
（`--status`/`--stop`/`--set-volume`，以及 `--id`/`--all`）与带值的
`--color`/`--volume`/`--engine` —— 直接吃进全局量，于是 getopts 从来看不见它们。
颜色**刻意**没有 `-c` 短 flag（只有 `--color`）；`-S`（不是 `-F`）是 format-sort 覆盖，
而且它是**原样**转发给引擎的，因为 format-sort 是 yt-dlp 的语言，不是播放器的。

**为什么一个未知的长 flag 死在这个循环里。** 每一个长 flag 都在那里被处理，
所以一个没匹配上的永远不可能合法 —— 而放它掉下去的话，它会以 `-` 的身份到达 `getopts`，
报出毫无用处的 "invalid option: --"。那个分支改为点名真正的那些 flag：
**一扇门里帮助调用方恢复的那一半。**

### 6.1 调用栈 —— 哪些进程会跑，以及抽取发生在哪里

§6 回答的是*"这条 argv 由哪个函数处理"*。这一节回答的是*"哪些**进程**被生出来，
以及真正被播放的那次抽取发生在哪里"*。后半个问题的答案很短：
**在引擎里，恰好一次，而且我们读得到它的 stderr。**

**A. 搜索与只读动词 —— 一个进程**

```
   $ yt-search -j -- "lofi"        $ bili-search -j -- "周杰伦"      $ yt-resolve --info -j -- <url>
         │                               │                                  │
         ▼                               ▼                                  ▼
   ┌────────────────────────┐   ┌────────────────────────┐   ┌────────────────────────┐
   │ yt-search              │   │ bili-search            │   │ yt-resolve             │
   │  fetch_results         │   │  fetch_page_once       │   │  resolve_info          │
   │   └─ yt-dlp            │   │   └─ curl（search/type）│   │   └─ yt-dlp            │
   │      "ytsearch<N>:…"   │   │      + 随机 buvid3      │   │      --dump-single-json│
   │  jq → 单行信封          │   │  jq → 单行信封          │   │  jq → 单行信封          │
   └────────────────────────┘   └────────────────────────┘   └────────────────────────┘
     一个进程 · 一次原语调用 · mpv 从不启动 · 播放器完全不参与
```

`yt-resolve --transcript` 是同样的形状（一次 `yt-dlp --skip-download --no-simulate`，
AS-BUILT-contract.md §3）。`bili-resolve` 根本没有 `--transcript` 那一半（§3.4）。

**B. 播放 —— 播放器问一个引擎，然后播一条直链**

```
   $ ut-play -j --engine yt -- <handle>
         │
         ▼
   ┌──────────────────────────────────────────────────────────────────
   │ 进程 1 ：ut-play
   │    resolve_via_engine:  "$SCRIPT_DIR/$ENGINE-resolve"（否则 PATH）
   │         │               未知引擎 → 退 1，并把它的名字说出来
   │         ▼
   │  ┌───────────────────────────────────────────────────────────
   │  │ 进程 2 ：<engine>-resolve -j -f MODE -- <handle>
   │  │    host 白名单：不是本站的 host → 退 1（§3.4）
   │  │    resolve_stream ──► yt-dlp --dump-single-json -f <fmt>   [#1]
   │  │    （仅 yt）探测 ──► curl 取 1 字节；失败就匿名重解     [#1']
   │  │                      并把 retried:true 置上（engine §8.2）
   │  │    jq ──► {stream_urls[], http_headers{}, title, duration, …}
   │  └───────────────────────────────────────────────────────────
   │    读那个信封；失败按引擎给的 `reason` 分类，
   │    绝不靠重读 yt-dlp 的散文（AS-BUILT-contract.md §3）
   │         ▼
   │    run_mpv:  mpv --no-ytdl <stream_urls[0]>
   │              [--audio-file=<stream_urls[1]> 当格式是合并的]
   │              [--http-header-fields=… 来自 http_headers]
   └──────────────────────────────────────────────────────────────────
                        │
                        ▼
              进程 3 ：mpv —— 解码一条直链。**不跑任何 extractor。**
```

**B′. detached 播放 —— 多一个进程，而父进程在毫秒级返回**

```
   $ ut-play -d -j --engine yt -- <handle>
         │
         ▼
   进程 1 ：ut-play，那个**会返回的**父进程
        detach_play: ensure_state_dir · new_player_id · lock_player_state
             ├── nohup bash "$SELF" -f MODE --engine <name> -- <handle> &
             │      是一个**全新的 ut-play**，不是直接的 mpv。set -m + disown，
             │      于是播放器活过这个父进程的退出（player §9.1）；stdin → /dev/null（§3.3）
             └── 发出 {status:"started", id, pid, sock, log, title:null} 然后**退出**
                        │
                        ▼
   进程 2 ：ut-play（YT_DETACHED=1、YT_IPC_SOCK=<sock>）→ 走上面的 B，
            并在锁下、且 pid 仍匹配时，从解析信封把 `title`、`format`、
            `selected`/`selected_resolution` 与 `engine` 补进**它自己的**记录。
```

**那个后台标题更新器没有了。** 它存在的唯一理由是"被播放的东西是一个 URL、而上游没人知道标题"；
解析信封带着 `title`，于是子进程补自己的记录，每次 detached 播放多出来的那整个
`yt-dlp --print "%(title)s"` 随之消失。

**C. 生命周期控制 —— 不抽取，也不起新 mpv**

```
   $ ut-play --status -j    |    --set-volume 60 --id <id>    |    --stop --all
         │
         ▼
   ┌──────────────────────────────────────────────────────────
   │ ut-play
   │    reap_dead_players → resolve_target
   │    read_player_live → live_props ──► nc -U <sock> ──┐
   │    do_stop → stop_group ──► 杀掉整个进程组           │
   │         │                                            ▼
   │         └── jq ──► 信封                    （那个**已经在跑**的 mpv）
   └──────────────────────────────────────────────────────────
         没有 yt-dlp · 没有新 mpv · 每个播放器一次 socket 往返
```

`uting` 不增加第四种形状：它把 **A**（`<engine>-search -j`）与 **B′**
（`ut-play -d -j --engine`）作为子进程跑，然后用它自己的 `nc -U` 直接对播放器的 socket 说话，
而不是绕回 `ut-play`（`AS-BUILT-tui.md` §11）。

**那些抽取点**

| # | 在哪 | 命令 | 谁的进程 | 结果用来干什么 |
|---|---|---|---|---|
| 1 | `fetch_results`（`yt-search`） | `yt-dlp ytsearch<N>:…` | 引擎 | 搜索信封 |
| 2 | `fetch_page_once`（`bili-search`） | 对 `search/type` 的 `curl` | 引擎 | 搜索信封 |
| 3 | `resolve_stream` / `dump_once` | `yt-dlp --dump-single-json -f` | 引擎 | **真正被播放的那条流** |
| 4 | `probe_raw`（`yt-resolve`） | `curl` 取 1 字节，失败则第二次解析 | 引擎 | 挑客户端；置 `retried`（engine §8.2） |
| 5 | `resolve_info` | `yt-dlp --dump-single-json --skip-download` | 引擎 | `--info` 信封 |
| 6 | `resolve_transcript`（`yt-resolve`） | `yt-dlp --skip-download --no-simulate` | 引擎 | 字幕文件 → 文本 |

**三个值得明说的后果**

1. **如今每一次抽取都是我们的。** 旧的第 7 个点 —— mpv 内部的 `ytdl_hook.lua` ——
   随 `--no-ytdl` 一起没了，那种"一次播放里最后也最重要的抽取，我们既分类不了、
   也没法给它传任意 argv"的不对称也随之消失。将来某个 extractor 在播放时需要什么，
   那是一次**引擎改动**，不是一个 mpv flag。
2. **请求头是契约，不是运气。** `http_headers` 是解析信封的必需键，而播放器把它放上 mpv 的 argv。
   旧的 `--get-url` 交出去的是一条光秃秃的 URL、没有放头的字段，
   于是同一个视频可以在这边播得好好的、同时交给调用方一条 CDN 会用 403 拒掉的 URL ——
   这是在 Bilibili 上量到的，也正是这个键承重而非理论的原因（AS-BUILT-contract.md §3）。
3. **一次 detached 播放跑一次 yt-dlp，最坏两次**（#3，加上带 cookie 的客户端探测失败时的 #4′）
   —— 从四次降下来。mpv 一次都不贡献。

## 7. 搜索子系统 —— 引擎的一个动词
已移出 → `AS-BUILT-engine.md` §7，Bilibili 的传输层在 §7.1。

## 8. 播放子系统
已移出 → `AS-BUILT-player.md` §8 —— §8.1（模式 → 格式 → mpv、mpv 选项集、终端噪声压制）
与 §8.3（输出模式与错误分类）。§8.2 那个登录 / PO-token 探测移到了
`AS-BUILT-engine.md`：它本来就是引擎知识。

## 9. detached 播放的生命周期
已移出 → `AS-BUILT-player.md` §9 —— 进程组模型、多播放器状态机与死亡记录、
运行时 IPC 控制、持久状态层（§9.4）、队列（§9.5）与收听日志（§9.6）。

## 10. 解析 —— 引擎的第二半
已移出 → `AS-BUILT-engine.md` §10（含 §10.1 `--info` 与 §10.2 `--transcript`）。

## 11. `uting` 编排（自有胶水，零站点逻辑）
已移出 → `AS-BUILT-tui.md` §11 —— 引擎发现、两个视图、原地渲染、宽度层与封闭字形库存、
reflow、共享时钟与三个播放态。

# 第三部分 —— 模块 API（契约面）

**已移出：** 整个契约面 —— 命令规格、把门模型、JSON 数据契约、退出码表与配置面 ——
如今住在 `docs/AS-BUILT-contract.md`，也就是 §3.8 的那个冻结面。
下面的节号作为墓碑保留，好让旧引用仍然解析得开。

## 12. 命令规格
已移出 → `AS-BUILT-contract.md` §1。

## 13. 把门模型
已移出 → `AS-BUILT-contract.md` §2。

## 14. 数据契约（JSON schema）
已移出 → `AS-BUILT-contract.md` §3。

## 15. 退出码、TTY、依赖
已移出 → `AS-BUILT-contract.md` §4。

## 16. 配置面
已移出 → `AS-BUILT-contract.md` §5（键表、优先级链与每个键的语义）。
**两个根数据文件的拓扑、以及"数据文件而非共享库"这个决定留在 §4**（§3.6）。

## 17. 函数图与源流

**列名与函数名保持英文**（它们是标识符与定宽列）；括注里的说明是中文。

```
   跨全部八个脚本 : ut_read_config（KEY=value 当数据读、绝不 source；用户那份先读、
                  先到者赢，然后是根上的 config —— 与读 VERSION 是同一条自解析路径，§3.6。
                  八份逐字节相同，见本节末尾）

   播放器 (shell/ut-play) —— 无 yt-dlp，无站点知识
     Setup/util : usage, die, is_non_negative_int, is_signed_int（--seek 的符号**就是**
                  契约，绝对跳转另有 --seek-to）, validate_enum,
                  require_cmd/require_deps, mpv_supports_vo, normalize_playback_mode,
                  set_action
     Engine call: engine_resolve_bin（名字 → 可执行文件，靠拼接），
                  resolve_media（跑 <engine>-resolve -j，填好 RESOLVED_* 全局量），
                  patch_player_meta（子进程把 title/format 回填进自己的记录）
     Playback   : run_mpv（唯一的 mpv 接缝）, play_{audio,video,fast,ascii,viz}_url,
                  play_mode_url, play_url_directly, play_url_json,
                  classify_playback_error（mpv 的措辞 + 引擎的 yt_reason 标记），
                  emit_play_json（播放信封**唯一**的写者）
     Lifecycle  : group_alive, stop_group, ensure_state_dir, live_props（多属性一次 IPC 读），
                  read_player_live（关联 + 归一化，--status 两种模式共用），
                  detached_epitaph（子进程写在日志里的最后一行），
                  record_player_death / prune_dead_players / collect_failed_players
                  （墓碑，player §9.2），
                  player_state/player_sock/player_log/player_lock_dir,
                  lock_player_state/unlock_player_state, new_player_id, detach_play,
                  reap_dead_players, resolve_target, do_status, do_stop, do_set_volume,
                  do_playback_verb（四个 socket 动词，一个形状）,
                  ipc_command（socket 往返**唯一**的读者，填 IPC_DATA —— 走全局量是因为
                  nc 超时/SIGPIPE 会在赋值处就把脚本掀了）, ipc_failed（"命令没生效"
                  那个退出码 4，永远不是 1）, require_live_target（socket 动词共用的
                  活目标门；--stop **故意**不用它，见 do_stop）, rm_player_files
                  （sock+log+queue+两个锁，**唯一**的清理，player §9.5）
     Queue      : player_queue/queue_lock_dir, lock_queue_state/unlock_queue_state
                  （**第二把**锁，绝不与第一把嵌套，player §9.5）, read_queue_items
                  （stdin → items，三种形状，所有拒绝都是用法错误），
                  queue_write_new/queue_append/queue_bump（父进程这边的写者），
                  queue_advance_from（子进程的 compare-and-swap）, queue_current,
                  queue_snapshot（{pos,len,next,upcoming}，每个要报队列的信封都用它；
                  upcoming 是队尾的列表形式、带时长、封顶 QUEUE_UPCOMING_MAX=5），
                  queue_note_failure（一首**曲目**的墓碑，<id>-q<pos>），
                  child_signal + detached_child_loop（子进程：一个播放器，一条队列），
                  do_enqueue, do_next
     History    : history_bin（按名字找 ut-history，只找一次，否则答"没装"），
                  history_record（每首一行，在**每一次**播放之后，跑在一个已经忽略了
                  INT/TERM 的子 shell 里 —— player §9.6）。播放器对这份日志的全部认识
                  就是那一行的形状；文件是 ut-history 的。

   存储之一：日志 (shell/ut-history)
     Verbs      : do_ls（跨月分片、最新在前，只读到 -n 需要的那么多；一行读不了就计数并跳过，
                  绝不致命）, do_record（那一行是**逐字段构造**的，于是调用方多带的键到不了盘上；
                  构造完再对 LINE_MAX 做测量）, do_clear（整片直接 rm，只有边界那一片被重写）
     Shape      : JQ_TRUNC（在 UTF-8 边界上按**字节**预算截断）, line_bytes,
                  count_rows, collect_history_files（分片最新在前 —— YYYY-MM 的字典序恰好
                  就是它的时间序，而这正是分片这么命名的全部理由）, ensure_store

   引擎，搜索半 (shell/yt-search · shell/bili-search)
     Shared shape: die, is_non_negative_int, validate_enum, require_cmd/require_deps,
                  cleanup_scratch/ensure_scratch, fetch_results, print_list,
                  emit_search_json, print_usage, reject_url, JQ_PRELUDE（fmt_dur ——
                  每个引擎自己那份唯一的时长格式化器）
     yt-search  : classify_yt_dlp_error
     bili-search: classify_http_error, search_fail, ensure_buvid（本地生成的随机 cookie ——
                  是**正确性**要求而不是优化，AS-BUILT-contract.md §1）,
                  duration_bucket（本地时长界 → 服务端的粗桶；桶不精确，
                  本地界仍然照筛）, fetch_page_once（全套件**唯一**手工拼的
                  HTTP 请求）, fetch_page

   引擎，解析半 (shell/yt-resolve · shell/bili-resolve)
     Shared shape: die, validate_enum, require_cmd/require_deps,
                  cleanup_scratch/ensure_scratch, normalize_playback_mode,
                  format_for_mode（模式→格式表）, quality_sort_for_tier
                  （(mode, tier) → yt-dlp format-sort 串；--quality 的档位只有这张
                  表译得动，yt-dlp sort 串在这里之外不存在 —— contract §1.3）,
                  url_host, is_own_host,
                  normalize_target（句柄文法 + host 白名单，§3.4）,
                  dump_once, emit_stream, resolve_fail, resolve_stream, resolve_info,
                  resolve_auth（--auth：报告 cookie 决定本身，不承诺它买到了什么）,
                  classify_yt_dlp_error, print_usage
     yt-resolve only : have_probe_tools, probe_raw（PO-token 探测，engine §8.2）,
                  resolve_transcript / transcript_fail（engine §10.2）
     bili-resolve only : resolve_parts / parts_fail（--parts：列出多 P 视频的各 P，
                  一次 HTTP 请求、没有 yt-dlp；parts[] 元素就是条目记录，
                  直接管进 ut-playlist --add —— contract §3）
                  （根本没有 transcript 那一半 —— 能力规矩，§3.4）

   存储之二：播放列表 (shell/ut-playlist) —— 无站点知识、无播放，只用 jq
     Setup/util : die, require_cmd, validate_enum, now_utc, print_usage, set_action,
                  fail（状态错误信封：not_found | exists | invalid_name |
                  invalid_input | locked | corrupt —— 它**自己的**枚举，player §9.4）,
                  JQ_PRELUDE（fmt_dur）
     Store      : playlist_file/playlist_lock, ensure_store, validate_name,
                  read_playlist（**唯一**的读者：解析守卫 + schema 门，
                  于是 jq 的退出码永远不会变成这个命令的），
                  lock_playlist/release_lock（超时即失败，抢走陈旧目录；持有的是一个**集合**，
                  因为 --rename 要按固定顺序同时锁源与目标）,
                  write_playlist（temp+mv）, read_items（stdin → 条目记录；
                  **通过全局量**返回，因为命令替换会把它的错误信封吞进一个子 shell）
     Verbs      : do_ls, do_show, do_add, do_rm, do_del（幂等）, do_rename

   交互式     : uting （fetch_json → build_all_rows → load_rows → 菜单循环：
                  display_menu · read_nav_input · move_selection · play_selected ·
                  new_search [read_query_input，Esc 取消] · filter_live → apply_filter）
                  启动提示：同一个 read_query_input，在第一次取数前以 echo 关闭的状态跑 ——
                  一个读取器、一份 Esc 契约、没有第二套实现
     Views      : display_list_menu（行 + 横幅 + reflow；原地 \033[H/K/J）,
                  display_now_playing_card, display_menu（分派、DCS 帧保持）
     Width layer: char_w/disp_w/truncate_disp/cluster_back, cw_range/init_cell_tables
     Fetch UX   : spin_start/spin_stop（后台子 shell，sleep 0.12 一帧）夹住 fetch_json ——
                  每一条取数路径都有动画
     Row count  : more_results（`→` 越过末页：用当前查询重取，+1 批）,
                  fewer_results（`←` 在第 1 页：ALL_ROWS 就地截断，−1 批，零网络，
                  地板是一屏）—— 两条边，一个键都不占（tui §11）
     Cycles     : cycle_mode（`v`：PLAY_MODE audio→video→fast，纯本地，下一次 Enter 才生效）,
                  cycle_quality（`f`：PLAY_QUALITY 轮换 UT_QUALITY_CYCLE，同样纯本地 ——
                  它选的是**引擎那张 (mode, tier) 表的一行**，这个文件不认识 yt-dlp 串）,
                  cycle_sort（`o`：轮换 SORT_FIELD 并**重取** —— 页与选中项在这里刻意重置，
                  因为重排之后旧下标底下是另一个视频）—— 另外三个 cycle 键各自跟着它们的
                  子系统列在别处：cycle_theme / cycle_ui_lang 在 i18n/theme，cycle_engine
                  在 Engines。六个 cycle 键管七个偏好里的六个，第七个（UT_START_RESULTS）来自上面
                  那两条边；置脏点全都在**成功路径之后**（tui §11）
     Prefs      : mark_pref（cycle 成功之后置脏位；被环境压住的键在这里被拒并说一次）,
                  flush_prefs（冲刷点是 nav_tick 与 cleanup_on_exit 两个现成的地方）,
                  write_prefs（就地改写用户配置：一遍扫描、一个临时文件、一次 mv；
                  注释与空白逐字节搬过去）, pref_value（键→变量的映射，同时**就是**
                  那张白名单）, pref_value_ok（round-trip 闸）, pref_listed
                  （3.2 没有关联数组，一个集合就是一个字符串）
                  —— 七个键，且只写**用户那份**（contract §5「写回」、§3.6）
     Chrome     : term_size（TERM_LINES/TERM_COLS —— 走这个 UI 本来就要求的那个 TTY 的真
                  ioctl，不信 $LINES/$COLUMNS；reflow 与分页的输入，tui §11）, layout_cols,
                  print_hints（HINT_MEASURE）, wrap_print/wrap_emit
                  （WRAP_MEASURE）, print_details（DETAIL_MEASURE）, card_divider,
                  repeat_glyph, render_prog_bar
     Card       : display_now_playing_card（**一个**视图、两个主语，CARD_SUBJECT
                  = playing | item）, card_subject_head（rail + 标题 + 频道，两个主语共用的
                  骨架）, card_meta_row（从右往左丢字段、tail 永不丢的那一行）,
                  card_item_body（item 主语：free 层 + 取数买来的层 + 按行预算的简介）,
                  card_info_row（上传日期/点赞/章节数 —— **两个主语共用**的那一行片段）,
                  card_queue_block（前方队列块：`--status` 的 queue.upcoming，按行预算，
                  装不下就退回单行 next: 形式 —— TUI 里唯一**读**队列的地方，tui §11）
     Input      : read_nav_input/read_esc_tail（ESC-[/O 解码器，拆出来是为了让 PENDING_ESC
                  的再入不成为它的第二份副本）/read_query_input,
                  confirm_key（确认是**一个字节**不是一行文本：`read -rsn1`，默认否 ——
                  今天只有 `d` 用它，tui §11）,
                  utf8_complete + init_lead_tables（一个**字符**一个键）,
                  tty_echo_off/tty_echo_restore, cursor_hide/cursor_show
     Queue      : enqueue_selected（`+`）, skip_next（`>`）, focused_payload（焦点行作为
                  一个单项信封 —— **一个**构造器，因为 ut-playlist --add 与 ut-play --enqueue
                  读的恰好是同样那两种形状）, apply_player_record / refresh_player_record
                  （这里曲目可以在不按键的情况下改变，所以 media-title 搭 fetch_play_times
                  本来就有的那次往返，只有**发生变化**时才花一次 ut-play --status，§26）
     Player     : play_verb（**写**的一侧：一次按键，一个 ut-play 动词）,
                  send_mpv_ipc, mpv_get_prop, fetch_play_times（一条连接取 pos/dur/pct +
                  pause；直播路径上**只**取 pause）,
                  player_check_ready（core-idle → 清掉 Starting 态，20 秒上限）,
                  play_state_marks（playing/paused/starting → 字形+标签+颜色，两个视图共用）,
                  toggle_pause, seek_relative, adjust_volume, stop_current_playback,
                  check_player_alive, clear_play_state, elapsed_since_play,
                  cleanup_on_exit
     i18n/theme : init_ui_strings（启动时按 YT_LANG、否则按 locale 定一次语言）/
                  set_ui_lang/cycle_ui_lang（S_* 表 —— 每个标签**一次性**解析进全局量，
                  不在渲染路径上每帧再判一次语言）, init_theme/set_theme（配色家族 →
                  强调色与灰阶，`t` 的实时轮换用的就是启动时这同一次重解析）/init_colors/
                  detect_bg/init_colorterm/cycle_theme, init_glyphs, init_sync
     Failures   : report_fetch_failure, play_failed_notice, press_any_key
     Formatters : fmt_sec（时钟）, short_dur（duration_fmt → 6:10:58）, commas
     Engines    : scan_engines / engine_seen / engine_search_bin（按**对**发现，tui §11）,
                  cycle_engine（`e` 键：换源并重新取数）, refresh_engine_auth
                  （每次换源重算 ENGINE_AUTH —— 不建映射表，bash 3.2 没有关联数组）,
                  refresh_engine_caps / refresh_engine_parts（**每个引擎有没有 `--parts`**
                  是一次启动时问出来的能力探测，不是一张硬编码表 —— 与 auth 同一条
                  "以有没有声明能力"的路，§3.4）, open_parts（`c` 键：把聚焦行的多 P
                  部分开成一个列表 —— 一次 `<engine>-resolve --parts -j`，把信封 reshape
                  成与存储同样的七字段行；`LIST_SOURCE="parts"` 是它自己的一个来源，
                  再按 `c` 回到搜索）, refresh_engine_info（同一套探测，问的是 `--info`）,
                  open_item（`i` 键：聚焦行 → item 主语，**进门即取数**，单槽缓存）,
                  open_playing_info（卡内 `i`：对**在播**曲目叠 info，主语不变；
                  engine 取自播放器记录，不取自当初启动的那一行）,
                  fetch_item_info（两扇门背后的**同一次**取数：一个 spinner、一份错误措辞、
                  一个 engine:url 单槽缓存）, apply_item_info（--info 信封 → ITEM_* 字段）
     Stores     : build_playlist_rows（一个存储信封 → 与搜索建出来的同样的七字段行；
                  播放列表的 --show 与日志的 --ls 是一个形状，所以一个构造器服务两者）,
                  add_to_playlist（`a`）, browse_playlists / open_playlist（`b`）,
                  open_history（`h`，不提问 —— 日志只有一个）, stash_search / back_to_search
                  （`h`/`b` 再按一次：一个存储替换掉那些行，而它替换掉的是本地状态，
                  所以回去是**还原**而不是重新搜索 —— 规则见 AS-BUILT-tui.md §11）, stored_rows（谓词；search_only 是
                  "这些行来自一个存储"的另一半 —— 那个三处都要用、否则就会变成三份漂移副本的判断）,
                  playlist UI 一家（全部外壳调用 ut-playlist，自己不存也不改）：
                  list_playlists · show_playlist（两者都**通过全局量**回 JSON + COUNT）·
                  pick_playlist（`b` 挑一个来开、`a` 挑一个来加 —— **一个**选择器，两个键）·
                  focused_index（焦点行 → 它在存储信封里的下标：拿 url **加上它的出现
                  序号**去查，因为一个歌单允许同一个 url 出现多次）·
                  delete_from_playlist（`d`：唯一破坏性的存储键，先问且默认否）·
                  reload_playlist（删完重读；读失败就落回搜索，因为屏幕上那是过去的图像）·
                  playlist_only（`d` 的谓词，search_only 的镜像 —— 日志没有按行删除，
                  所以不是 stored_rows）,
                  prompt_name（`n` 提示的读取器，复用）, have_store / have_history /
                  store_notice —— 它们全都外壳调用 ut-playlist 或 ut-history，
                  自己什么也不存（player §9.4、§9.6）
```

**八个脚本之间的重复是刻意的，不是漂移。** `ut_read_config` 在**八个入口点**里各出现一次，
八份逐字节相同（函数体 sha 一致，2026-08-28 实测）—— 配置层是一个根上的数据文件
加一份复制过去的读取器，不是第九个文件（§3.6）；同理，`die`、`require_deps`、`fmt_dur`、
`ensure_scratch` 与那些信封发射器在每个引擎里各出现一次。一个共享库会是第七个文件，
而每个引擎 —— 因而传递地，还有那个去找引擎的播放器 —— 都得知道它；
而这次拆分的全部主张就是"**一个引擎是一对可以直接丢进来的自足文件**"。
**不得**分歧的是**信封**，而钉住它的是 AS-BUILT-contract.md §3，
以及 `tests/contract.sh` 对两个引擎跑同样的断言 —— 不是靠共享代码。

不是每一个 helper 都列出来了 —— `print_usage`、`die`、`is_uint` 与其他一行的守卫是**故意**略去的。
每一个**子系统**都列了，而那才是这张图的意义：一个这份文档按行为讨论过的函数，
应该能从这里按名字找到。

**源流。** 这套套件源自一个大一统的 `yt-search-n-play.sh`：它的非交互内核变成了
`shell/yt` 加两个把门的动词，然后再次拆成这份文档描述的播放器与引擎对；
它那个自绘 TUI（菜单 chrome、`display_menu`、`read_nav_input`、`read_query_input`、
方向键翻页、阻塞式播放语义）被重新安家到如今的 `uting` —— 同一个菜单，只是如今委派给那些动词。
那个原版的**播放**行为几乎没有留下什么：如今播放是 detached 的，
所以"播放前不 clear"与"播放后不清空 stdin"描述的是一个 TUI 已经不再运行的前台 mpv，
而行如今是量过并省略的、不再任它折行。**活下来的**是菜单的形状与它的键位表；
`/` 过滤、两视图切换与整个宽度层都是净新增的。

---

# 第四部分 —— 支持的工作流

## 18. 人 —— 交互式浏览与播放

```
   $ uting "lofi hip hop" -n 40 [-f video] [-p 15] [--theme nord] [--engine bili]
     → 自绘菜单（tui §11），两个视图用 Tab/p 切换：
       列表  ：↑/↓ 移动 · ←/→ 翻页（→ 越过末页 = 多取一批，← 在第 1 页 = 少要一批，
               本地截断不取数）· Enter 播放（**detached、非阻塞** —— 菜单保住它的终端，
               而音乐在 n / o / 过滤之间继续放）· / 过滤（实时收窄）· n 新搜索 ·
               o 排序 · v 轮换模式（audio→video→fast，对下一次 Enter 生效）·
               f 轮换质量档（auto→medium→high，同样对下一次 Enter 生效；档位由引擎
               按 (mode, tier) 翻译成 format-sort）·
               e 换源并重新取数（只有装了 2 个以上引擎时才画出来）
               —— 这七个改的设置会写回用户配置（contract §5「写回」，§3.6）
               i 把聚焦行开成卡片的 **item 主语**（一次 `<engine>-resolve --info`，
               进门即取数 —— 唯一的入口，任何行源都行）
       卡片  ：←/→ seek ∓5s · ↑/↓ 音量 · Esc 回到列表 ·
               i 对**在播**曲目叠一行 info（主语不变：播头、前方队列块、播放状态都还在）
       两者  ：Space 暂停/恢复 · s 停止 · 9/0 音量 · [ ] seek ∓10s ·
               l chrome 语言（en↔zh）· t 调色板家族 · q 退出（回收它的播放器）
```

## 19. Agent —— 先搜，再播

```
   # 1) 搜索 → 结构化、省 token 的信封；用程序去挑。
   #    **引擎从同一个信封里取** —— 绝不假设。
   env=$(yt-search -j -n 10 -- "lofi")
   url=$(jq -r '.results[0].url'  <<<"$env")
   eng=$(jq -r '.engine'          <<<"$env")
   # 2) 播放（阻塞式散文），或者拿一个机器可读的结果：
   ut-play --engine "$eng" -- "$url"                       # 散文
   ut-play -j --engine "$eng" -- "$url" | jq -r .reason    # → ok 时是 null；失败时是枚举
```

换一个源就是把这三行里的 `yt-search` 换成 `bili-search`，别的什么都不变 ——
而这正是 `engine` 这个字段的用处（AS-BUILT-contract.md §3）。搞错了会**吵**而不是**静**：
一条 Bilibili URL 送去 `yt-resolve` 会退 1 并说明（engine §10）。

## 20. Agent —— 不播放地组合（解析）

```
   # 解出一条直链交给别的工具（非阻塞）。
   # 这是一个**引擎**动词 —— 播放器没有"只解析"的拼法（engine §10）。
   yt-resolve -- "$url"                                  # 散文：流 URL
   yt-resolve -j -- "$url" | jq -r '.stream_urls[0]'     # 结构化
   yt-resolve -j -- "$url" | jq -r '.http_headers | to_entries[] | "\(.key): \(.value)"'
```

**取 URL 时把请求头一起取走。** 在一个会检查 `Referer` 或钉住 `User-Agent` 的站点上，
一条光秃秃的流 URL 不够 —— 实测：Bilibili 的 CDN 对单独的 URL 答 403，
对同一条带上这些头的 URL 答 206。旧的 `--get-url` 没有放它们的字段，
而这正是这个信封堵上的那个洞（AS-BUILT-contract.md §3）。

```
   # 只读的元数据与字幕也是引擎动词：
   yt-resolve --info -j -- "$url" | jq -r '.chapters[]?.title'
   yt-resolve --transcript -j -- "$url" | jq -r .text     # 拿来就能丢进 prompt
```

## 21. Agent —— 后台播放加生命周期控制

```
   ut-play -d --engine yt -- "$u1"        # detach 播放器 1（立即返回，约 0.03s）
   ut-play -d --engine bili -- "$u2"      # **第二个引擎**的播放器，并排跑
   ut-play -j --status                    # {"status":"players","players":[{id,…},{id,…}]}（退 0）
   id=$(ut-play -j --status | jq -r '.players[0].id')
   ut-play -j --set-volume 70 --id "$id"  # 播放器 1 的实时音量 → {"status":"ok",id,volume:70}
   ut-play --stop --id "$id"              # 只停播放器 1（幂等）
   ut-play --stop --all                   # 停掉每一个；不留孤儿
```

`players/` 恰好有一个所有者，所以 `--status` 与 `--stop --all` 看得见每一个播放器，
不管它是被哪个引擎起来的 —— 播放器是唯一会往那儿写的东西（player §9.2）。

为什么是这个形状：一个只会阻塞的播放器对 agent 不可组合。`<engine>-resolve`（解析而不播放）、
`-d` + `--status`/`--stop`/`--set-volume`（后台 + 轮询 + 实时控制）与 `-j`（结构化结果），
就是"只在视频结束时才返回"的那些逃生口；而 `--status`（永远）与 `--stop`
（除了目标歧义那一种，那是退 4）都退 0，于是一个轮询循环永远不会把一个正常状态误读成失败。

---

# 第五部分 —— 对齐的最佳实践

## 22. 2026 agent 工具计分卡

| 维度 | 理由 | 状态 |
|---|---|---|
| 可发现性 | 对一个没有部落知识的调用方，`--help` 就是事实来源 | ✅ 每个动词一份窄帮助；每一份都点名调用方**可能真正想要**的**其他**动词 |
| 结构化输出 | 不靠字符串匹配散文就能解析 | ✅ 搜索（`-j`/`-J`）+ 播放（`-j`） |
| token 效率 | 高信噪比胜过完整 | ✅ 8 字段的 `-j`（小约 4×）；`-J` 是 opt-in；`--transcript -j` 丢掉重复的 `segments`（3.1×） |
| 退出码契约 | 成功/失败必须可判 | ✅ `cmd \|\| rc=$?`；130 被归一 |
| 信任边界 | agent 的字符串绝不进入任何 shell 插值点 | ✅ 查询/URL 是单个 argv 元素；`--` 守卫 |
| 拒绝而不挂起 | 绝不阻塞在缺席的 stdin 上 | ✅ 除 `uting` 外每个动词都非交互；`uting` 要求 TTY |
| 契约稳定性 | 变更要吵着失败，而不是静默 | ✅ 非法枚举 + 交叉 flag 拒绝 |
| 进程生命周期 | 长播放要能后台化 / 查询 / 停止 | ✅ `-d`/`--status`/`--stop`，按进程组停 |
| 可组合性 | 只会阻塞的播放不可组合 | ✅ `<engine>-resolve`（流 URL **加请求头**）、`-d` + 生命周期 |
| 错误分类 | 按**原因**分支，不按原始措辞 | ✅ 固定的 `reason` 枚举 |
| 配置面 | 每次请求用 flag；set-once 用环境变量 | ✅ flag 按调用；环境变量做调优 |
| 所有权 | 不被客户端锁定；两个面都可移植 | ✅ 自有的播放器 + 引擎 + 胶水；原语在接缝后 |
| 入口形状 | 分开的动词胜过一个带模式 flag 的命令 | ✅ 八个窄动词，没有分发器，没有包装层 |
| 可扩展性 | 一个新能力不得去改调用方 | ✅ 一个新源 = 一**对**引擎；播放器与 TUI 不动（由步骤 C 证明） |

## 23. Clean / Safe / Modular / DRY 的遵守情况

```
   Clean   : 每个命令单一职责；agent 路径上没有菜单状态机；
             播放器里任何地方都没有 `if site ==`。
   Safe    : 退出码契约横跨两次重构都保住了；TTY 守卫；
             变更期间交互路径从不缺席（§24）；破坏性编辑由 grep 把闸。
   Modular : 八个平级成员，一层，一张显式依赖图；每个原语在单一接缝之后，
             而接缝按文件切开（§5）。
   DRY     : 规矩是"一个事实一个**地方**"，这与"一个**副本**"不是一回事。
             播放与生命周期只存在一次（播放器）。一个站点的知识只存在一次（它那对引擎）。
             样板代码 —— die、require_deps、fmt_dur —— 是**有意**按引擎重复的（§17）：
             一个共享库会是一个每个引擎、并传递地连播放器都得知道的文件，
             而那恰恰是这次拆分消掉的耦合。**不得**分歧的是**信封**，
             而钉住它的是 AS-BUILT-contract.md §3，加上一条**对每一个被发现的引擎**
             都成立的检查 —— 于是第三个引擎落地当天就被覆盖。
```

## 24. 安全演进方法论（这套套件是怎么被改的）
已移出 → `CLAUDE.md` § Safe-Evolution Methodology —— A→E 那个顺序，以及
"把唯一那一步破坏性动作放在最后、并做到最小"这条原则。流程归那份文件，不归这里。

## 25. 风险登记（设计层面的缓解）
已移出 → `AS-BUILT-verification.md` §25 —— 风险表。

## 26. 非目标 / 已知约束

- detached 的 `ascii`/`viz`（没有终端可画）—— 在解析期就被拒（player §9.2）；
  `audio` 是常态，而 `video`/`fast` 会开它们自己的 GUI 窗口。
- 阻塞式播放（`ut-play -- <handle>` / `-j`）只在播放结束时才返回；非阻塞的 agent 流程请用
  `--detach` + `--status`/`--stop`，或者 `<engine>-resolve`。
- **范围说明（§3.5）：三个收听功能全部已落地**，在 shell 版里，
  按它们彼此依赖的顺序 —— 播放列表管理（player §9.4、AS-BUILT-contract.md §1.5）、
  队列（player §9.5、§1.1）、收听日志（player §9.6、§1.6）。每一个都与它的键位在**同一个提交**里
  带着自己的 agent 动词与 `-j` 信封一起到达，而这正是它们共同继承的那条约束：
  **一个只有键位、没有动词的功能只做了一半。**
  收藏刻意不是一个功能（它是一个名字固定的播放列表）；下载器与频道订阅未排期。
- **队列的编辑 —— 重排、出队、循环、随机 —— 刻意不进 v1。** 那些是对一条队列的操作；
  第一版必须先证明队列会**推进**，而那是其余一切所依赖的部分。加它们是给 `ut-play` 加动词
  （每个都带自己的 `-j` 信封，§3.5），不是加一个新命令 —— 队列归播放器（player §9.5）。
- `uting` 的行是每次搜索对缓存结果的一次 jq —— 小 N 没问题；不是为几千条结果设计的。
- **播放器里的 URL 嗅探** —— `ut-play` 从不猜一条光秃秃的 URL 属于哪个引擎；
  调用方说（`--engine`），而 `uting` 永远知道，因为搜索是它做的。
  推迟到第三个引擎让一张模式注册表值那个重量时再说（AS-BUILT-contract.md §1.1）。
- **一个共享的引擎库** —— 刻意不建；那份重复是"一个引擎是一对自足文件"的代价（§23）。
- 不套 MCP 包装（§1）。不依赖第三方媒体客户端（§2）。
- **对一个 detached 播放器的运行时控制是一组动词**（`--set-volume N`、`--pause`、
  `--resume`、`--seek ±N`、`--seek-to N`，每个都可带 `[--id ID]` ——
  player §9.2 / AS-BUILT-contract.md §1.1、§3）：每个 detached 的 mpv 都带着
  `--input-ipc-server=mpv-<id>.sock` 跑，而一条命令经由那个每实例 socket 出去
  （`ipc_command`，五个动词共用）。`nc -U` 是惰性把门的，于是一次光秃秃的搜索不必为它付账
  （AS-BUILT-contract.md §4）。`--volume N` 仍然是启动时的**起始**音量。
  **这套套件不按那条听起来很有道理的判据走 —— "只有当调用方真的没法直接跟 socket
  说话时，才加一个动词"。** 它写在这里，是因为一条这么像规矩的规矩会被反复重提。
  四件事否掉它：
    1. **`--set-volume` 本身就是反例。** volume 与 pause 在 socket 上同样够得到 ——
       那条判据对两者逐字成立 —— 而 volume 早在这条规矩写下来之前就是一个动词了。
       **一条解释不了自己已经发出去的那个面的规矩不是规矩**；真正的取舍从来都是
       "TUI 需要它，所以它存在"。
    2. **队列会把它第二次推翻。** `--next [--id ID]` 的形状**一模一样**：
       对一个在跑的播放器的一次变更、走同一个 socket、歧义同样退 4。
       `--next` 一发出，再拒绝 `--pause` 就只是任意。
    3. **代价是反的。** 动那个冻结面是一次刻意且有记录的行为（§3.8）。
       五个一起做只开**一次**；分两批做要开两次。
    4. **代码本来就存在，只是长在错的文件里。** `uting` 的 `toggle_pause` / `seek_relative`
       已经直接驱动 IPC 好几个月了，所以这次是把逻辑往**下**搬、并**净删**了 TUI 代码 ——
       那是支配原则，而不是给播放器做加法。
  属于这里的是**代码到底是什么**：
    - 这一节事先写下的两条约束原样发出了：`--seek` 取一个**带符号**的值，
      而绝对定位是另一个拼法（`--seek-to N`）；没有 `--toggle-pause`，
      因为 mpv 的 `cycle pause` 不回值，信封只能猜结果状态。
      `uting` 自己决定目标，然后发那两个幂等动词之一。
    - 每一个信封报的都是**从 socket 读回来的**那个属性，绝不是被要求的那个值
      （`do_playback_verb`）—— mpv 会把 seek 钳在文件两端，
      而那两个数字恰恰在调用方最需要真相时才不同。
    - **什么**没有**搬，以及决定它的那个数字。** `uting` 每拍一次的**读**
      （`fetch_play_times`，一条连接四个属性）留在 socket 上：每 1 秒一拍付一条进程链是真代价 ——
      这一半是那条判据里唯一站得住的部分。按住不放的 `9`/`0` 音量键也一样 ——
      在一个活播放器上各按 10 次实测：**走 socket 每次 10 ms，走 `ut-play --set-volume`
      每次 60 ms**（后者还要解析目标、并在锁下补状态文件）。那超过了为这个选择设的 50 ms 线，
      所以那两个键留下了，而这个例外**带着它的数字**被记下来，而不是留成一处没人解释的不一致。
      暂停与 seek 是一次按键一次调用、不是一拍一次，所以它们乐意付 —— 而 TUI 因此**净删**了
      IPC 写代码，这才是重点：**播放的正确性如今住在播放器里，每一个调用方都继承它。**
  仍然**刻意**不在范围内的：
    - **前台**播放的实时音量 —— 它有一个真 tty，所以 mpv 自己的音量键本来就能用；不需要 IPC。
      （`uting` 已经不是前台了：它 detached 地播、经 socket 调音量，而 `--status` 会把它活读出来。）
    - **`netcat-traditional` / busybox-only 的主机** —— `ut-play` 与 `uting` 各带一份
      `resolve_nc_unix`，按**能力**探测（`-h` 文本里有没有 `-U`），`nc` 不认 `-U` 就落到
      `ncat`（`-w` 只管连接，空闲兜底改拼 `-i 1`），两个都没有才拒。Debian/Ubuntu 的
      `netcat-openbsd` 与 Fedora 系的 `ncat` 因此直接通，剩下的那类主机装一个带 `-U` 的
      变体即可。**socat 依旧被拒**（不加新依赖；netcat 的变体是同一个依赖的第二拼法，
      不是新依赖）。

## 27. 验证矩阵
已移出 → `AS-BUILT-verification.md` §27 —— 上一次运行的测量、套件**刻意不覆盖**什么、
抖动登记册，以及矩阵本身。

## 28. 可移植性契约 —— bash 3.2

**`shell/` 里的每一个脚本都必须能在 bash 3.2 下跑**（macOS 那个被冻住的系统 `/bin/bash`，
在原生 macOS 上 `#!/usr/bin/env bash` 解析到的就是它）。这是一个**刻意**的下限：
零安装步骤，在 macOS、Linux、容器、CI 与 cron/launchd（那里 PATH 可能根本浮不出一个更新的
bash）下行为一致。我们*不*依赖 Homebrew 的 bash —— 一个被管理的解释器会引入一种
"解释器漂移"的失败模式（同一个脚本，交互时是 bash 5、cron 下是 3.2），
却买不到这套套件需要的任何特性。

给任何要编辑这些脚本的人的规矩：

```
   禁用（bash 4+）    ：declare -A（关联数组）· ${var,,}/${var^^} · mapfile/readarray ·
                        ${arr[-1]} · &>> · |& · ${!prefix@}
   空数组 + set -u    ：在一个**空**数组上光秃秃地写 "${arr[@]}"，在 3.2 上会**中止**
                        （"unbound variable"）。用下面两种可移植写法之一：
                          ((${#arr[@]})) && cmd "${arr[@]}"          （守卫，核心里的写法）
                          cmd ${arr[@]+"${arr[@]}"}                  （内联，uting 里的写法）
   算术 + set -e      ：光秃秃的 ((expr)) 是一条**命令**，而当表达式求值为 0 时它的退出码是 1。
                        在 set -e 下那会中止脚本。所以绝不要把 ((x = 1 - x)) 或 ((n += w))
                        写成一条语句 —— 写 x=$((1 - x)) / n=$((n + w))。
                        把 ((x)) 当作**判断**用（在 if、&&、|| 里）没问题：那里退出码正是重点。
   read -rsn1 是一个**字节**：在 3.2 上不是一个字符。在提示处键入的一个 CJK 字符会作为
                        2–3 个独立的"键"到达（验证过：你 → e4 bd a0），
                        所以任何把按键累积成文本的读取器，都必须从首字节把那个 UTF-8 序列
                        重新拼起来（uting 的 utf8_complete）。首字节要按**表成员关系**分类，
                        与 char_w 的做法一致 —— **不要**用字节范围比较：
                          `LC_ALL=C [[ … ]]`  根本不是合法的 bash。赋值前缀只作用于简单命令，
                            而 [[ 是保留字，于是 bash 会把那个裸字节当命令名去跑；
                            那个判断从来没有在 C 排序下跑过，答案是错的。
                          `( LC_ALL=C … )`    是对的，但每次按键 fork 一次，而且设不了全局量。
                        用 cw_range '' <lo> <hi> 一次性建好那些类，再用
                        [[ "$CLASS" == *"$byte"* ]] 测 —— 在 3.2.57 上逐字节验证过，
                        哪怕干草堆本身是非法 UTF-8。
   read -s 是**按单次读**的：它只在**一次**读的时长内关掉终端驱动的回显，之后就恢复。
                        两次读之间，驱动会把仍在**队列里**的东西回显出来 ——
                        而任何一次突发（粘贴、一个打得快的多字节字符）都会留下这种东西 ——
                        实测：在提示处粘贴"咖啡"，最后一个字符被回显了两遍，
                        而逐字节那版会洒出一串 U+FFFD。**一个自己画输入的 UI 必须在整个会话
                        期间拥有回显** —— 标志位见下一条 —— 并从恢复光标的**同一个 trap** 里恢复它。
   -echo 必须连 -icanon：回显关着而规范模式还开着，正是 getpass() 的 termios 签名，
                        而终端反应的是**这一对**、不是那个程序：Ghostty 按这条启发式打开
                        macOS 的 Secure Input（macos-auto-secure-input），iTerm2 在光标处画一把锁。
                        一个全屏应用是 -echo -icanon，这也是为什么 vi 从来不会被标记。
                        read -rsn1 只在它自己那次读的时长里清掉 ICANON，
                        所以"整个会话拥有回显、却不动 ICANON"，会让**每一次按键之间的空隙**
                        以及**任何一次阻塞调用的全程**都看起来像密码提示
                        （`AS-BUILT-verification.md` §25）。两个一起放倒 ——
                        stty -echo -icanon min 1 time 0 —— 并恢复进来时用 stty -g 存下的状态，
                        而不是在一个调用方自己设好的 tty 上重新摁上一套默认值。
   ${var//pat/} 是 O(n2)：在 3.2 上，一旦字符串里含有**一个**匹配，模式**替换**就是
                        "带多字节常数的二次方"：bash 会在每一个字节位置上跑一次 glob 匹配，
                        而在 UTF-8 locale 下每次尝试花 O(剩余长度)。在 3.2.57 上实测，
                        每五个字节一个空格：1KB 93ms · 2KB 527ms · 4KB 3.4s · 7KB 17.5s。
                        而当**任何地方都没有**匹配时有一条快速退出路径（48KB 只要 5ms），
                        这恰恰就是这个写法读起来"免费"的原因：一个手写的、标题很短的测试信封
                        走的是快路径，而每一个真实标题都含空格、走的是慢路径。
                        在这条规矩存在之前量到的：`yt-search -j -n 25 | ut-playlist --add`
                        在一次这样的展开里花了 16s，`ut-play -d --queue -` 花了 16.5s。
                        所以"是不是空白"的判断是一次**匹配**，绝不是一次替换：
                          [[ "$s" == *[![:space:]]* ]]   含有非空白字符
                          [[ "$s" != *[![:space:]]* ]]   是空白或空
                        两个放大因子也量过：一个字符类比一个字面模式贵 47 倍，
                        而 en_US.UTF-8 比 LC_ALL=C 贵 8 倍。如今 shell/ 里任何地方都没有
                        `${var//` —— 保持这样；并注意**带锚点**的剥离（${v#pat}、${v%pat}）
                        **不受**影响。
   验证               ：显式用 /bin/bash 跑一遍那些空参数路径 ——
                        这一类是**运行时的 bash 版本行为**，所以 `bash -n` 与 shellcheck
                        **抓不到**；只有真的在 3.2 上执行才抓得到。上面那两条规矩同理，
                        它们也都是运行时行为。
```

如果将来某个功能真的需要 bash 4+，诚实的做法是在顶部断言
`((BASH_VERSINFO[0] >= 4))`、并给一句 `brew install bash` 的提示，让 PATH 去提供它 ——
**绝不**硬编码 `/opt/homebrew/bin/bash`（那会在 Intel macOS 与 Linux 上坏掉）。
