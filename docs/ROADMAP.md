# ROADMAP —— `uting` 套件的下一步

2026-08-21 写；2026-08-23 随播放器/引擎重切（D9–D12）与代码重新对齐。与 `SPEC-system.md` 配套：
那份讲这套东西**是什么**，这份记录它**该变成什么**、为什么、以及每一步开工前必须先成立的条件。

范围：整个套件 —— 播放器 `ut-play`、人机面 `uting`、两对引擎 `yt-search`/`yt-resolve` 与
`bili-search`/`bili-resolve` —— 外加"其中哪一部分该被公开发布"这个问题。不是功能清单 —— 单个功能的实现前规划写 `PLAN-<topic>.md`，一路带着进度、上线即删，契约并入
`SPEC-system.md`。

> 五段文档流水线的定义在 `CLAUDE.md`。本文档是其中**唯一不终结**的一环，所以它只装两样东西：
> **必须活过重写的决定**，和**还没做的事**。**已落地的工作不留在这里** —— 它的去处是
> `SPEC-system.md`（契约与架构）与 git 历史（怎么落的）。

---

## 0. 定位与 non-goals

先写这一节，因为没有它，任何"完整度够不够"的判断都无从谈起 —— 第一版这份文档就漏了它，导致完整度
一度是拿通用 TUI 播放器当基准评的，结论错了（详见 §6.2 的更正）。

**定位**：一个 **agent 优先的媒体引擎**（一个不认识任何站点的播放器 + 一对一对可插拔的引擎），
外加**一张给人的终端脸**。差异化是三件与渲染无关的东西：单行 JSON envelope 契约、退出码分类、
脱离终端的播放器生命周期；以及同一套东西支持两种驱动方式。

> **2026-08-23 措辞更正**：本条原写"agent 优先的 **YouTube** 引擎（`yt` + 两个窄动词壳）"。
> D9 落地后音源不止一个（今天两个：YouTube、B 站），站点知识只住在引擎对里，所以"YouTube"
> 不再属于定位，只是**今天的第一个引擎**。差异化那三件与 non-goals 一字未动 —— 换音源不改定位。

**明确的 non-goals**：

- **不做通用 TUI 音乐播放器。** 那一层（本地/MPD：cmus、ncmpcpp、rmpc、musikcube、kew、termusic）
  已经饱和且活跃，见 §4 的实测数据。进去就是重复劳动。
- 因此**不做**：播放队列、播放列表管理、收听历史、收藏、下载器、频道订阅。它们是前一层的功能，
  **它们的缺席不构成本项目的缺口**。
- TUI 的职责边界：**搜到、放上、看着它在放、控制它**。到此为止。
- 不做 MCP（暂列 non-goal，由 §9 的触发条件决定是否解除）。

这一节冻结后，"要不要加队列"这类问题的答案默认是"不"，除非定位本身被改写。

---

## 1. 现状（2026-08-23）

**六个平级可执行文件，一层，无库**：播放器 `ut-play`、人机面 `uting`、两对引擎
（`yt-search`/`yt-resolve`、`bili-search`/`bili-resolve`）。站点知识只在引擎对里，播放只在播放器里
（D9）。**架构、函数图与全部契约见 `SPEC-system.md`** —— 那份与代码同步，这里不复述，也不放行数表：
一张会随每次 commit 过期的表，正是这份文档上次脱节的地方。

运行时依赖：**yt-dlp、jq、mpv、nc、curl**（curl 由 `bili-search` 必需 —— 它就是那个引擎的传输层；
在别处仍是可选的播放时客户端探测）。可移植性契约：**bash 3.2**（macOS 自带）。

**在飞**：`docs/PLAN-ut-restructure.md` 只剩 E 步（`SPEC-system.md` 文档同步 + 三个 rig 全跑）。
落地即删该文件，契约并入 spec。

---

## 2. 待决的问题

1. 现在这版 shell 值得单立 OSS 仓库并打包（curl 安装 + Homebrew）吗？
2. 真正值得做的是不是 Go TUI 重写？
3. 若 TUI 走 Go，agent 侧的 `ut-play` 与两对引擎要不要跟着走 —— 还是 Go TUI 直接对接现有
   shell 播放器与引擎才是 best of both worlds？（D9 之后这一问的答案面变宽了：可以只移植播放器，
   把引擎留在 shell —— 引擎才是会随站点变化而频繁改的那一半。）

贯穿三问的约束：这套东西是**人机双驱动** —— 人用 TUI，agent 调动词 —— 任何一面都不能为另一面牺牲。

---

## 3. 调研（一）：名字

2026-08-21 筛查。每个候选查六项：本机 PATH、Homebrew（core formula + cask）、crates.io、npm、
PyPI、**同领域**的 GitHub 同名仓库。

### 3.1 结论：`uting`

三层读法叠在一起，而且互不打架：

| 层 | 读法 | 谁读到 |
|---|---|---|
| 你听 | u-ting | 中文用户 |
| you listen | `u` = you（短信体），英文自然念作 "YOO-ting" | 英文用户 |
| **You**—tube | "You" 那一半的回声 | 潜意识 |

第三层**只有好处没有代价**：借到了 YouTube 的联想，却既没用 `yt` 也没用 "YouTube"，完全在品牌指引的
灰区之外。而且它**降解得体面** —— 将来若接入其他音源，前两层照样成立，只有第三层的回声淡掉，名字不会
变成谎话。这正是所有 `yt*` 系名字做不到的：那些是焊死的。

已知瑕疵、接受：挪威语里 `uting` 是真词，意为"陋习 / 讨人厌的东西"。

**别名策略（D10 定的现行规则）**：**套件不发任何短名。** 人机面就是发布名本身 —— `uting`；
agent 面用规范长名 `ut-play` / `<engine>-search` / `<engine>-resolve`。想短的人自己写 alias。
本节初稿提过的 `ytt` 与"`uting` 只作发布名"两条都已被 D10 推翻，理由记在那里。

### 3.2 被否掉的候选，及原因

| 名字 | Homebrew core | 其他 tap | crates/npm/PyPI | 结论 |
|---|---|---|---|---|
| **`uting`** | 空 | 空 | 全空 | **采用** —— 唯一六项全空 |
| `ting` 听 | 空 | `dhth/tap/ting`（同为命令行音频工具，"叮"） | 全占 | 个人 OSS 勉强可用，但撞商标 `Ting®`（Tucows / Ting Internet）且与那个工具**同词异义**，SEO 全废 |
| `yting` | 空 | 空 | 全空 | 六项也全空，但**是描述性名字**（`yt-*` 是最挤的角落），焊死 YouTube，读音含混 |
| `ytt` | **被占** —— carvel `ytt`（YAML 模板工具，1873★，`brew install ytt`） | — | 全占 | 出局。撞的正是同一批用户（k8s 生态）；作者本机有 k8s 相关笔记，说明本人也可能装它 |
| `tin` | **被占** —— Usenet 阅读器 tin 2.6.5（bottled） | — | 全占 | 出局。语义也丢了（锡/罐头） |
| `kiku` 聴く | 空 | — | crates 被占（"Kiku (聞く, to listen) 转录引擎"，同一词源） | 出局 |
| `yin` 音 / `yun` 韵 / `sheng` 声 / `qu` 曲 / `jing` 静 / `chan` 蝉 | — | — | crates + npm 基本全占 | 单音节拼音已被抢完 |
| `tuna` / `dial` | — | — | — | 撞 Linux 实时调优工具 `tuna(8)` / 一个 AI 语音 CLI |
| `tingyu` 听雨 / `qingyin` 清音 | 空 | 空 | 全空 | **备选**，若 `uting` 被推翻 |

规律：**短的 `yt*` / `t*` 名字这块地已被翻过一遍**，还空着的只有拼前缀拼出来的 `uting`。

风格先例（名字不描述功能、只做标签）：`yazi`（鸭子）、`nezha`（哪吒）、`atuin`、`zellij`、`kew`。

---

## 4. 调研（二）：领域现状（GitHub API 实测，2026-08-21）

| stars | 语言 | 最后推送 | 项目 | 音源 |
|---:|---|---|---|---|
| 19310 | Rust | **2024-04（已死）** | `Rigellute/spotify-tui` | Spotify |
| 8781 | Python | 2026-03 | `mps-youtube/yewtube` | **YouTube** |
| 7103 | Rust | 2026-07 | `aome510/spotify-player` | Spotify |
| 6727 | Rust | 2026-08 | `hrkfdn/ncspot` | Spotify |
| 6223 | C | 2026-08 | `cmus/cmus` | 本地 |
| 4825 | C++ | 2026-03 | `clangen/musikcube` | 本地 |
| 4144 | Shell | **2024-09（已死）** | `pystardust/ytfzf` | **YouTube** |
| 3237 | Rust | 2026-08 | `mierak/rmpc` | MPD |
| 2985 | C | 2026-08 | `ravachol/kew` | 本地 |
| 2472 | C++ | 2026-06 | `ncmpcpp/ncmpcpp` | MPD |
| 2176 | Rust | 2026-08 | `tramhao/termusic` | 本地/流 |
| 772 | Rust | **2025-03（停滞）** | `sudipghimire533/ytui-music` | **YouTube** |

新一代（都还小）：`NoctaVox` 370、`SubTUI` 260（Subsonic）、`gomu` 211、`waves` 168（Soulseek）、
`involvex/youtube-music-cli` 404。

三条结论，直接支撑 §0：

1. **这个领域按音源分层，不按 UI 分层。** 本地/MPD 那层饱和且活跃 → 不做通用播放器是对的。
2. **YouTube 这一格最弱、最缺维护。** 最像本项目的 `ytfzf`（POSIX shell + fzf + mpv，4.1k★）
   **2024-09 后没动过**；`ytui-music` 2025-03 停滞；`yewtube` 是 2014 年项目的 Python 续命。
3. **没有任何一个是 agent 可驱动的。** 全是人机 TUI：没有稳定机读契约、没有退出码分类、没有"脱离
   终端后仍可查/停/调音量"的生命周期 API。**star 数在这里不是对标指标 —— 不在同一赛道。**

---

## 5. 调研（三）：发布 shell 版要付的账

- **四个运行时依赖**（yt-dlp、jq、mpv、nc），全部由用户负责安装并保持可用。
- **bash 3.2 与 5 的行为差异**，可移植性契约已长篇记录（`SPEC-system.md` §28）—— 那是持续的维护承诺。
- **Linux 自带 netcat 没有 `-U`**（`SPEC-system.md` §26）。发布后从个人脚注变成平台缺口。
- **终端动物园**：DCS 帧同步、Ambiguous 宽度、tmux 透传 —— 宽度层与 `YT_AMBIG_WIDE` 存在的全部理由，
  发布后都会变成外部 bug 类别。
- **五个运行时依赖**（yt-dlp、jq、mpv、nc、curl），全部由用户负责安装并保持可用；且**每加一个
  音源就多一份站点维护面** —— 引擎对是本仓唯一会因外部网站变动而坏掉的地方（D9 把它关进两个
  文件，但没让它消失）。
- **通用短名不可用**：这一条已由 D10 兑现（六个命令名全做过六项筛查），但它仍约束 Go 版 ——
  见 D7 的"永不发布 `bin/yt`"。

预期：issue 列表九成是环境问题，不是行为问题。

---

## 6. OSS 就绪度评估（2026-08-21 实测）

### 6.1 代码与设计质量：到了，且高于同类平均

- 契约纪律：`-j` 单行 JSON、退出码分类（1 用法 / 2+ 传递 / 4 未生效）、US 而非 tab 作分隔、不从渲染
  串反解数据。
- 边界处理：EAW 宽度表 + CJK 精确宽度、`YT_ASCII` 全量回退、中英 i18n 无串泄漏、reflow 验到 40×12。
- 3124 行设计文档带一份可复查的验证矩阵。
- `shellcheck --severity=warning`（2026-08-23 六个脚本重测）共 **14 条**：SC2128×5、SC2178×4、
  SC2054×2、SC2034×2、SC2174×1。SC2128/SC2178 那 9 条**全在 `uting`、全是假阳性** ——
  `filter_live` / `read_query_input` 的 `local query=""` 与全局 argv 数组同名，shellcheck 不跟踪
  作用域。要做的是改名消噪，不是改逻辑。四个引擎与播放器文件里 SC2128/SC2178 是零。

### 6.2 功能完整度：**按 §0 的定位，已完整**

> **更正记录（保留，因为它改的是评判基准而不是某一项工作）**：本节第一版拿 kew / ncspot /
> termusic 当基准，判定"缺队列 = 完整度没到"。那个基准是评估时自己加的，文档从未声明要做通用
> 播放器。按 §0 的定位重评，队列 / 播放列表 / 历史 / 下载 / 频道订阅**属于 non-goals，不是缺口**。
> 原结论作废。

按这个基准，功能缺口为零；曾经的两条（detached 播放器的运行时状态、死亡原因不可观测）已于
2026-08-22 补齐，契约在 `SPEC-system.md` §9.2/§9.3/§14，回归在 `tests/contract.sh`。

### 6.3 发布硬件：**D8 三件已齐**，剩下的都是可选项

| 缺项 | 后果 |
|---|---|
| 无 `CONTRIBUTING` / `CHANGELOG` | 次要 |
| Linux 实际不可用 | §5 已述，且由 §9 触发条件 3 把关 |

### 6.4 分身份结论

| 以什么身份公开 | 现在够吗 |
|---|---|
| **参考实现 + 设计文档** | **够。** 发布硬件（D8）齐了 |
| **agent 可驱动的那个**（即 §0 的定位；今天占着 YouTube 与 B 站两格） | **功能够**，只差 P0 的独立契约文档 |
| brew / curl 分发的产品 | 不够，卡点不在功能，在 §5 的环境账 |

---

## 7. 分析：驱动决定的六条发现

1. **差异化在契约，不在渲染。** 真正难而有价值的是 JSON envelope、退出码分类、脱离终端的生命周期 ——
   都与语言无关。而 `uting` 2983 行的大头是在重新实现 Go TUI 栈免费给的东西：显示宽度
   （`go-runewidth`/`uniseg`）、事件循环与 resize（`bubbletea`）、样式（`lipgloss`）。那不是护城河，
   是重写会**删掉**（而非搬迁）的负债。

2. **single-binary 是全有全无。** 一个静态二进制、不要 jq、不要 nc、Linux 能跑、安装一行 —— 链条里
   留一个 shell 脚本就整体作废。Go TUI 接 shell 引擎仍是四依赖。所以 "best of both worlds" 在
   **风险**维度成立，在**分发**维度不成立。

3. **agent 对接的是窄动词的 argv + 它们背后的契约。**（**2026-08-23 更新**：本条原写"壳的 argv +
   core 的契约，重写壳几乎零收益"。D9 之后**没有壳了** —— 窄动词就是实现本身，`ut-play` 与四个引擎
   都是平级 peer。结论因此换了形状：可移植的单位从"core"变成**播放器**，而引擎可以整条留在 shell，
   因为它们才是随外部网站变动而频繁改的那一半 —— 见 §7.6 的迭代速度论证。）

4. **两个 agent 侧诉求落在播放器/新脸上，且 bash 都给不了**（第三个已还清）。

   | 想要的 | bash 为何不行 | 归属 |
   |---|---|---|
   | MCP stdio server | 手写 JSON-RPC 帧、长连接、并发 | 第三张脸（既非播放器也非引擎，D7） |
   | 流式进度 | 阻塞 `read`、一次性 jq | 引擎（search）+ 播放器（`--status`） |

   （原表第三行"失败原因进 envelope"已于 2026-08-22 落地，随之删除。）

5. **yt-dlp 与 mpv 在任何方案里都是子进程，Go 也一样。** 引擎的真实价值是 **flag 学问**
   （`--ytdl-format=ba/b`、`--ytdl-raw-options`、`--msg-level` 噪音压制、`--no-video` 与 term-osd、
   socket 路径、reap 规则），以 argv 数组原样搬。移植风险在边缘语义：直播行、null 播放量、两种时长
   拼法、`--stop` 幂等、锁顺序。

6. **agent 驱动两面都成立，第二面支持 shell。** 使用层面语言无关。开发层面：shell 利于**迭代**
   （无构建、可整文件读懂、原地改、pty 立验、ssh 上 `vi` 就能修）；Go 利于**重构安全**（本文件已出过
   **三次 `set -e` 回归**，`SPEC-system.md` §25.1 —— 正是编译器一次消灭的一类）。不足以压过第 2 条，
   但方向相反，必须记录。

---

## 8. 决定

- **D0 —— 定位冻结为 §0**：agent 优先的媒体引擎（播放器 + 可插拔引擎对）+ 一张人脸；
  不做通用 TUI 播放器。音源数量不是定位的一部分（见 §0 的措辞更正）。
- **D1 —— 不为分发打包 shell 套件。** 支持面（§5）大于差异化（§7.1）。
- **D2 —— 但照样公开仓库，定位为参考实现，不承诺打包。** README 写明这是"一个可用的 shell 实现 +
  一份 3124 行的设计文档"。文档是更可传播的产物。
- **D3 —— 任何重写之前先冻结契约**（envelope schema、player record、退出码表、生命周期语义）。
  它是唯一完整活过重写的东西，也是 Go 版的验收规格。
  **D9 之后冻结面多了一项：引擎契约**（`<engine>-search` 的结果 envelope、`<engine>-resolve` 的
  `{stream_urls[], http_headers{}, title, duration, format}`、`engine` 字段的路由含义、非本站 URL
  = 1）。它是"加一个音源 = 加一对脚本"这句话的全部兑现手段，所以 P0 抽契约文档时必须一并抽出。
  同一轮里被**故意收窄**的只有一处：`--get-url` / `--info` / `--transcript` 不再是播放器的动词
  （见 §1 的 2026-08-23 条目）。
- **D4 —— Go 的第一步只做 TUI**（`uting` → Go），调用今天原封不动的 `<engine>-search` 与
  `ut-play`。被否方案 —— 一次性全量移植：把生命周期语义和渲染器重写放进同一次变更，回归无法二分定位。
  **D9 让这一步更干净了**：Go TUI 要复刻的只剩"扫 `*-search` 建注册表 + 切源"，它不需要认识任何站。
- **D5 —— "播放器是否也去 Go" 是独立的、条件触发的决定**（§9）。触发前 `ut-play` 保持 shell。
  **引擎不在这个问题里**：它们随外部网站变，shell 的原地可改性在那半边是净收益（§7.6）。
- **D6 —— 发布名 `uting`（§3.1）**；一个命令一个名字，不留第二种拼法。**命令名由 D9/D10 定死**：
  `uting` / `ut-play` / `yt-search` / `yt-resolve` / `bili-search` / `bili-resolve`。
- **D7 —— Go 版只发一个二进制加子命令，绝不发三个通用名的可执行文件。**

  ```sh
  uting search …           # 缺省引擎的 <engine>-search
  uting <engine> search …  # per-engine，D9 之后的形状（yt / bili / …）
  uting play …             # 今天的 ut-play
  uting                    # 无参数 → TUI（今天就是这个名字，Go 版逐字相同）
  uting mcp                # 第三张脸，D5 触发后
  ```

  **永不发布 `bin/yt`**（§5 —— 那个名字今天已经不在套件里了，D10）。上表是 **D9 之后重排过的草稿**：
  `resolve` 刻意不进子命令表（它只被播放器调），per-engine 那一层的最终形状留到 Go 真正开工时定 ——
  它不影响 shell 版。

- **D8 —— 三件发布硬件先于任何公开动作**（§6.3）：`LICENSE`、rig 入库、`--version`。
- **D9 —— 套件按「播放器 + 可扩展搜索引擎」重切，不按站点开命令**（2026-08-22 定，取代 D6 的命令名）。

  起因是接入 B 站时实测出的三件事（`RESEARCH-bilibili-engine.md`）：核心（当时的 `shell/yt`）里有三处**只对
  YouTube 成立**的逻辑（PO-token 探测、`player_client=android`、`detach_title_updater` 存在只因
  搜索不给标题）；沿用 `-s/--source` flag 会把这三处原样继承给每一个新音源，并在四个函数里长出
  `if source ==` 树。真正与音源无关的是**播放器**（生命周期 / mpv / envelope / 退出码 / `players/`），
  与音源有关的只有**抽取**。按这条线切：

  ```
        uting ──持有引擎注册表──┬── yt-search   / yt-resolve     (yt-dlp · yt-dlp)
          │                     └── bili-search / bili-resolve   (curl · yt-dlp)
          └── ut-play   生命周期 · mpv · envelope · players/ · 退出码
                        不认识任何一个站；播放时回调 <engine>-resolve
  ```

  - **引擎 = 两个动词**：`search`（列表）与 `resolve`（id → 直链 + header）。加第三个音源只加一对
    脚本，`ut-play` 与 `uting` 一行不改。
  - **四命令而非子命令**（否决 `yt search|resolve` 形式）：窄动词、flag 面窄，符合 D0 的 agent 取向；
    `resolve` 实际只被 `ut-play` 调，暴露给模型的仍是 `*-search` + `ut-play`。
  - **resolve 必须发生在播放时**，不能在搜索时：直链会过期，且 10 条结果只会用 1 条。
  - **顺带修掉一个契约漏洞**：`resolve` 的 envelope 从第一天就带 `http_headers`，因此
    `--get-url` 那个「裸 URL 无 Referer 即 403」的洞（B 站实测 403/206）随重切一并关闭。
  - 契约**本体不变**（envelope schema、player record、退出码表、生命周期语义 = D3 冻结的那些）；
    变的是命令名与新增一个 `resolve` 动词 —— 按 `CLAUDE.md` 属「deliberate, documented act」。
  - 施工计划见 `docs/PLAN-ut-restructure.md`（自带进度，上线即删）。

- **D10 —— 命令前缀 `ut-`（派生自发布名 `uting`），取代 D6 的 `ytt` / `yt-play`。**
  六项筛查（§3 方法，2026-08-22）：`ut-play` / `ut-tui` / `ut-search` **PATH·brew·npm·PyPI·crates·
  GitHub 同名 全空**；光杆 `ut` 全占（npm/PyPI/crates + `boost-ext/ut` 1438★），短名 `utt` 也被占
  （npm/PyPI + `larose/utt` 349★）。**因此人机面没有短名** —— 想短由用户自建 alias，不随包发第二个名字。
  引擎命令保留音源自身的名字（`yt-*` / `bili-*`），因为它们本来就该说明自己是哪个站。

  **修订（2026-08-23，同日）：人机面不叫 `ut-tui`，直接叫 `uting`。** `ut-tui` 与 `uting` 是同一个
  东西的两种拼法，而人真正会敲、也真正会被别人提起的是**发布名本身** —— 留着 `ut-tui` 等于让
  §3.1 那条"一个命令一个名字"在最显眼的那个命令上先破例。筛查结论不受影响：`uting` 本来就是
  §3.2 里唯一六项全空的那个。**因此 `ut-` 前缀今天只约束 agent 面的播放器 `ut-play`**；
  人机面用光杆发布名，引擎用站名。三类命令三种命名规则，各自的理由都在上面 —— 这不是不一致，
  是"谁在敲它"不同。


- **D11 —— B 站引擎按「操作」分原语：搜索走 curl，解流走 yt-dlp**（2026-08-23 实测定，取代
  `RESEARCH-bilibili-engine.md` R3 的「搜索也走 yt-dlp」）。

  R3 当初撤回「直连」的三条理由（法务、无上游可跟、`buvid3` 不够 production-grade）指向的是
  **自建一个完整客户端**：签名、选流、CDN、风控绕过。那一整块现在归 yt-dlp —— `bili-resolve`
  一次 `yt-dlp -J` 就拿到直链 + header + title + duration（2.7s），**本仓没有一行 WBI 签名、
  没有 playurl 端点、没有 key 轮换缓存**。

  但**搜索那一格 yt-dlp 走不通**，实测（2026-08-23）：`--flat-playlist` 一次请求 0.9s 却
  **零元数据**（`BiliBiliSearchIE` 只 yield URL 与 aid）；完整抽取则因该站音乐结果绝大多数是
  多 P 合集而**逐 P 递归**，N=10 超过 120s 未完成。直连 `search/type` 一次请求 0.71s 拿全字段。

  所以分界不在站点，在**操作** —— 与 R6 同一条原则。落进本仓的 B 站知识因此是
  **一个公开端点 + 一个 Referer + 一个本地生成的随机 buvid3**，不含任何认证机制；登录态只经
  `--cookies-from-browser` 到 yt-dlp。`buvid3` 是正确性要求而非优化：不带它，连续六次搜索里三次
  412（带则 6/6 通过），而 `<uuid>infoc` 与「本地造」都是 yt-dlp 自己对每个 B 站请求做的事。

  **重开条件**：若 yt-dlp 的 `BiliBiliSearchIE` 对齐 `SoundcloudSearchIE` 的元数据透传（上游
  patch，`RESEARCH` §2.6），搜索那一格就该改回 yt-dlp，本仓的 HTTP 路径整个删掉。

---

- **D12 —— 一个引擎一套：`<engine>-resolve` 只解自己站的 host**（2026-08-23 定）。

  C 步实测暴露：`yt-resolve` 接受**任意** http(s) URL 并原样交给 yt-dlp（支持 1700+ 站），
  所以一条 B 站 / Bandcamp 的 URL 解得出来，并被标成 `engine:"yt"`。**它能用,正是它没被发现的
  原因** —— 而 `engine` 这个字段存在的全部理由就是让调用方把结果路由回**正确的** resolve,
  在这条路径上它一直在说谎。裸 `www.*` 分支同样是通配。`bili-resolve` 有一模一样的疣。

  **否决了两个更聪明的方案**：通用引擎（`dlp-resolve` 一类,把 1700 站合并成一个引擎),
  以及引擎间 `exec` 委托（`yt-resolve` 判出非本站时转交）。理由是 KISS —— 一个音源一对脚本,
  边界就是文件边界,`grep` 一次就能验;通用引擎的维护面是一张我们测不了的站表,委托则让引擎之间
  长出依赖。**现在的规则一句话说得完：`X-resolve` 只认 X 的 host,别的一律退 1。**

  非本站 URL 是 **usage 错误(1)** 而不是抽取失败(2+)：什么都没尝试,也没什么可重试的 ——
  调用方点错了引擎,与 `--engine nope` 是同一个错误,评分也该相同。

  **要付的账,如实记**：URL-only 音源（Bandcamp / Apple Podcasts / 喜马拉雅）原先「`ut-play <url>`
  今天就能放」是**靠上面那个疣**才成立的。这条路现在关闭,`RESEARCH-bilibili-engine.md` §0 把它们
  判为「不需要接」的依据随之失效。**重开条件**：若它们成为真实需求,正确做法是**给它写一对**,
  不是放宽 host 校验。

---

## 9. 把 core 推向 Go 的触发条件

任一为真，**播放器**移植就值得它的风险。全不为真，`ut-play` 无限期保持 shell —— 那是正当终态。
（引擎不受这三条支配，见 D5。）

1. **真的要 MCP**（解除 §0 的那条 non-goal）。
2. **真的要单文件分发**（推翻 D1）。
3. **真的要支持 Linux**（`nc -U` 缺失与 bash 3.2/5 分裂只在这里一起消失）。

次要、单独不足以触发：流式搜索结果；每次按键 fork `stty`；想要带编译期保证的测试套件。

---

## 10. 落地计划

### P0 —— 契约抽取（不写代码，解锁其余全部）

- 从 `SPEC-system.md` 抽成独立契约文档：envelope schema（search / play / status）、player record
  schema、退出码表、生命周期语义（launch → status → stop、幂等、歧义 → 4）、`-j` 单行保证。
- **D9 之后这份文档要多装一半：引擎契约**（见 D3）—— `<engine>-search` 的结果 envelope、
  `<engine>-resolve` 的 `{stream_urls[], http_headers{}, title, duration, format}`、`engine` 字段的
  路由含义、"只认自己站的 host，别的退 1"（D12）、以及**能力用动词的有无表达**（`bili-resolve`
  没有 `--transcript`）。**这一半才是"加一个音源 = 加一对脚本"的兑现手段** —— 缺了它，第三方写引擎
  只能照抄 `yt-resolve`。
- **前置**：`PLAN-ut-restructure` 的 E 步（文档同步）必须先落 —— P0 是从 `SPEC-system.md` 里抽，
  而它现在还挂着一段"A–D 已改了什么"的临时注记。从一份自知过期的文档里抽契约，抽出来的仍是过期的。
- 验收：只读这份文档就能写出 JSON diff 测试，不需要读 `ut-play`；也能照着写出第三个音源的引擎对，
  不需要读 `yt-resolve`。
- **状态：未开工。** 两个洞（`--status` 的实读属性、死亡记录）已于 2026-08-22 补进 spec 与 rig，
  所以要抽的是一份**没有那两个洞**的契约；抽取本身一行没写。

### P1 —— 独立仓库（D2 + D8）

**已完成（2026-08-21 建仓，D8 三件齐）。** 仓库在 `~/workspace_fullstack/uting`，含 `LICENSE`
（MIT）、`README.md`、`tests/`、`shell/VERSION`；每个脚本自解析符号链接定位同伴，所以 checkout
可以放在任何地方。

**唯一剩下的是一个决定，不是一件工作：仓库是否公开。** 现为 private。公开前要成立的条件：

- README 直说依赖与平台现实（macOS 优先；Linux 需要支持 `nc -U` 的 netcat），并直说 §0 的
  non-goals —— 省掉一半"为什么没有队列"的 issue。
- 不 vendor yt-dlp 或 mpv。
- 验收：陌生人读完设计文档能理解架构，不必运行任何东西。

### P2 —— Go TUI 接 shell 播放器与引擎（D4）

- `bubbletea` + `lipgloss` + `go-runewidth`。移植**决定**而非代码：reflow 的"先测量再预算"顺序、
  details 块作为可计费 chrome、三个播放态、象限 spinner、CHA 定位的时长轨、中英双语、主题，
  外加 D9 之后新增的那条：**扫 PATH / 同目录的 `*-search` 建引擎注册表 + 切源**，不写死站名。
- mpv socket 用 `net.Dial("unix", …)` —— 客户端侧就此甩掉 nc。
- 交给库因而可删的清单：显示宽度表、resize 处理、事件循环、`\033[K`/`\033[J` 记账、每次按键的
  `stty` fork。
- 验收：对着 `SPEC-system.md` §27 与 shell TUI 并排比对 —— 窄终端网格、reflow 下限用例、中英、
  `YT_ASCII=1`、播放态迁移。复用 `tests/tui_pane.sh`（tmux 就是终端，所以 harness 不可能与真终端
  有差异——那正是 pty 版本栽过的地方），连同教训：等就绪标记而不是 sleep，屏幕类断言下在
  `capture-pane` 的单元格网格上、字节类断言下在 `pipe-pane` 的流上。

### P3 —— 播放器移植（仅当 §9 触发）

- 在冻结的契约背后重写 **`ut-play`**。jq 化进结构体反序列化，nc 化进 `net.Dial`。flag 学问原样搬
  （§7.5）。**引擎默认留在 shell** —— Go 播放器照样 `exec` `<engine>-resolve` 读它那一行 JSON，
  这正是 D9 用进程边界换来的东西（移植面从"整套"缩到"一个文件"）。
- 验收：固定查询集上两实现的 `-j` **逐字段 diff**（须含直播行、null 播放量、跨日时长、零结果、强制
  yt-dlp 失败），外加生命周期序列（launch → status → set-volume → stop → 再 stop）退出码全等；
  **两个引擎都要各跑一遍**，否则 diff 只证明了 YouTube 那一格。shell 套件保持安装，充当参考实现。
- 之后、且仅在之后：`uting mcp`、curl 安装脚本、Homebrew tap。

### P4 —— （已删）

原 P4 是"产品完整度：补队列等功能"。按 D0 它属于 non-goals，整段删除。若将来定位改写为"收听应用"，
再新开一份 ROADMAP 讨论，而不是把它当作本项目的待办。

---

## 11. Future work（已蒸馏，等触发条件）

- **运行时播控动词 `--pause` / `--resume` / `--seek`。** 不是没想清楚，是**卡在一个决定上**：
  `SPEC-system.md` §26 把它们列为非目标，解禁条件是"调用方真的没法直接跟 socket 说话"。而今天
  有 shell 的 agent 能自己 `nc -U`（socket 路径就在 `-d -j` envelope 里，是故意给的），所以条件
  未成立。唯一让它成立的调用方是只能调已声明工具面的 agent —— 即 `uting mcp`，而 MCP 仍是 §0 的
  non-goal，由 §9 把关。**因此这批动词挂在 §9 触发条件 1 上，不是排期问题。**
  两条设计约束已预先定好、写进 §26，届时不必重开讨论：`--seek` 相对必须带符号、绝对另用
  `--seek-to`；`--toggle-pause` 不做（`cycle pause` 不回值，envelope 兑现不了）。
  前置条件**已不再是障碍**：`--status` 现在实读 `paused`（2026-08-22 落地），agent 暂停了观测得
  到。这批动词仍然卡在上面那个决定上，不是卡在可观测性上。

---

## 12. 开放问题

- **定位是否就此冻结在 §0？** 这是唯一能连锁改写本文档的问题：一旦改成"收听应用"，§4 的对标对象、
  §6.2 的完整度结论、被删的 P4 都要回来。
- **`uting` 的挪威语含义**（"陋习"）—— 当彩蛋接受，还是换 `tingyu` / `qingyin`？
- **MCP 那张脸到底属不属于这个产品** —— 还是 agent 通过通用 shell 工具调 `uting search -j` 就够了？
  P0/P1 不依赖这个答案。
- **引擎边界** —— 第三方音源的引擎对进本仓，还是各自成仓、只靠契约（P0 那份文档）对齐？
  答案取决于 P0 抽不抽得出一份能照着写引擎的文档。（此问取代了原先的"仓库边界"：D9 之后没有壳，
  六个文件都是实现，仓库就是全部。）
