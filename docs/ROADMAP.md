# ROADMAP-yt — `yt` 套件的下一步

2026-08-21 写。与 `SPEC-system.md` 配套：那份讲这套东西**是什么**，这份记录它**该变成什么**、为什么、
以及每一步开工前必须先成立的条件。

范围：整个 `yt` 套件（`yt`、`yt-search`、`yt-play`、`yt-tui`），外加"其中哪一部分该被公开发布"这个
问题。不是功能清单 —— 单个功能的实现前规划写 `PLAN-<topic>.md`，一路带着进度、上线即删，契约并入
`SPEC-system.md`。

> 文档类型（2026-08-22 定稿，规则在 `CLAUDE.md`）：四段流水线
> **`DESIGN-<topic>`（待决，蒸馏成 future work 后删）→ `ROADMAP`（已决定+排序）→
> `PLAN-<topic>`（可施工，自带进度，上线即删）→ `SPEC-<scope>`（与代码同步，永久）**。
> 第三段用 `PLAN-` 而非 `TODO-`：plan 会记录自己的进度，todo 只是一张没做的清单。
> 这份是流水线里唯一不终结的一环，所以它装的是"必须活过重写的决定"。
> 本文档此前那条注释已作废：它称 `CLAUDE.md` 登记了 `RUNBOOK-` / `DESIGN-` / `TODO-` 三种前缀，
> 而 `CLAUDE.md` 里从来没有这张表，仓库里也没有 RUNBOOK。同轮把与代码同步的那份从
> `DESIGN.md` 改名为 `SPEC-system.md` —— 它一直在做双重身份：是与代码同步的规格，却挂着提案阶段
> 的名字，而 `DESIGN-` 这个前缀现在归还给真正待决的探索。

---

## 0. 定位与 non-goals

先写这一节，因为没有它，任何"完整度够不够"的判断都无从谈起 —— 第一版这份文档就漏了它，导致完整度
一度是拿通用 TUI 播放器当基准评的，结论错了（详见 §6.2 的更正）。

**定位**：一个 **agent 优先的 YouTube 引擎**（`yt` + 两个窄动词壳），外加**一张给人的终端脸**。
差异化是三件与渲染无关的东西：单行 JSON envelope 契约、退出码分类、脱离终端的播放器生命周期；
以及同一套东西支持两种驱动方式。

**明确的 non-goals**：

- **不做通用 TUI 音乐播放器。** 那一层（本地/MPD：cmus、ncmpcpp、rmpc、musikcube、kew、termusic）
  已经饱和且活跃，见 §4 的实测数据。进去就是重复劳动。
- 因此**不做**：播放队列、播放列表管理、收听历史、收藏、下载器、频道订阅。它们是前一层的功能，
  **它们的缺席不构成本项目的缺口**。
- TUI 的职责边界：**搜到、放上、看着它在放、控制它**。到此为止。
- 不做 MCP（暂列 non-goal，由 §9 的触发条件决定是否解除）。

这一节冻结后，"要不要加队列"这类问题的答案默认是"不"，除非定位本身被改写。

---

## 1. 现状（2026-08-22）

| 文件 | 行数 | 角色 | 受众 |
|---|---:|---|---|
| `shell/yt` | 1965 | 引擎。yt-dlp 调用、jq prelude、时长格式、播放、脱离终端的播放器生命周期（id/pid/sock/lock/state dir、reap）、`--status`/`--stop`/`--set-volume`/`--get-url`/`--info`/`--transcript` | 机器（经壳调用） |
| `shell/yt-search` | 148 | parse → gate → `exec yt` | agent tool call |
| `shell/yt-play` | 249 | parse → gate → `exec yt` | agent tool call |
| `shell/yt-tui` | 2806 | 应用。自绘菜单、焦点卡片、宽度层、reflow、主题、中英 i18n、mpv IPC 客户端 | 人 |
| `docs/SPEC-system.md` | 2745 | 架构 + 设计理由 + 验证矩阵（与代码同步的那一份） | 两者 |

运行时依赖：**yt-dlp、jq、mpv、nc**（curl 可选，用于播放时间的客户端探测）。
可移植性契约：**bash 3.2**（macOS 自带）。

2026-08-21 这轮已落地（均已记入 `SPEC-system.md`）：启动提示支持 Esc 取消（复用
`read_query_input`）、四条 fetch 路径统一的象限块 spinner、第三个播放态（`Starting`，由 `core-idle`
判定，列表仅在该态下按秒 tick）、列表视图改为就地渲染（任何一帧都不再清屏）。

2026-08-22 这轮已落地（同上）：

- **`--transcript`** —— agent 侧的内容理解原语：字幕取回并清洗成可直接进 prompt 的文本。只读，
  不播放，依赖仍是 yt-dlp + jq。`-j` 精简 / `-J` 加 `segments`（严格超集，与 search 的
  `-j`/`-J` 同一关系）。定位上不属 §0 的 non-goals：那一列是**播放器层**功能，而它与 `--info`
  同类，是只读元数据。
- **`-j`/`-J` envelope全部收敛为单行** —— §0/§6.1 把"单行 JSON"当差异化和契约纪律写了很久，
  实际上只有生命周期动词做到了：search `-j -n 3` 是 26 行、`-J` 76 行、`--info -j` 16 行、
  `--get-url -j` 也是 pretty，而 `--status` **只在播放器列表为空时**是单行 —— 一有播放器就
  pretty，正好是有人在轮询它的时候。五处 `jq` 补 `-c`（`emit_search_json` ×2、`resolve_info`、
  `resolve_stream_url`、`--status` 的 `jq -s`）。`players/` 下的 state file 不在此规则内，仍是
  pretty：那是给 jq 读的磁盘记录，不是 envelope。契约写进 `SPEC-system.md` §14 —— P0 抽契约文档
  之前必须先修，否则抽出去的是一条假保证，而 Go 版按 D3 继承的正是那份文档。
- **`yt-play` 的 `--` 不再绕过 URL 门禁** —— `yt-play "a query"` 一直正确 exit 1，但
  `yt-play -- "a query"` 把 `--` 之后的全部灌进 `url`，不做校验就交给 core，于是**搜索**了：
  散文列表，或 `-j` 下一整个 search envelope，来自那个契约说自己只播 URL 的动词。这正是 D7 把 `yt`
  从 PATH 上撤下来要防的 bypass（§4），在防它的那层里以两个字符复现。`yt-search` 的 `--` 分支从来
  都重做 `reject_url`，这次是把 `yt-play` 抄成同一形状（`reject_non_url`，两条位置参数路径共用）。
- **HTTP 429 归入 `network`** —— 此前落到 `unknown`（调用方唯一无法据以行动的那个值）。可重试是
  调用方唯一会分支的语义，因此不新增枚举成员。
- **文档四段流水线定稿** + 与代码同步的那份从 `DESIGN.md` 改名 `SPEC-system.md`（见头部注释）。

---

## 2. 待决的问题

1. 现在这版 shell 值得单立 OSS 仓库并打包（curl 安装 + Homebrew）吗？
2. 真正值得做的是不是 Go TUI 重写？
3. 若 TUI 走 Go，agent 侧的 `yt-search` / `yt-play` 要不要跟着走 —— 还是 Go TUI 直接对接现有
   shell 引擎才是 best of both worlds？

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

**别名策略**：`uting` 只作**发布名**。本机人机面继续用 `ytt`（Go 版用 argv[0] 分派或 shell alias
实现）—— 明天早上敲的还是 `ytt`，公开的那个名字是干净的。agent 面用规范长名 `yt-search` /
`yt-play`，不再留 `yts` / `ytp`：短名的理由是省打字，而 agent 面没人打（见 `SPEC-system.md` D0）。

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
- **`yt` 是不安全的公开可执行名** —— 太短太通用，link `bin/yt` 的 formula 会直接冲突。

预期：issue 列表九成是环境问题，不是行为问题。

---

## 6. OSS 就绪度评估（2026-08-21 实测）

### 6.1 代码与设计质量：到了，且高于同类平均

- 契约纪律：`-j` 单行 JSON、退出码分类（1 用法 / 2+ 传递 / 4 未生效）、US 而非 tab 作分隔、不从渲染
  串反解数据。
- 边界处理：EAW 宽度表 + CJK 精确宽度、`YT_ASCII` 全量回退、中英 i18n 无串泄漏、reflow 验到 40×12。
- 2494 行设计文档带一份可复查的验证矩阵。
- `shellcheck --severity=warning` 共 **15 条**：SC2128×5、SC2178×4、SC2034×3、SC2054×2、SC2174×1。
  其中 SC2128/SC2178 **全是假阳性** —— `filter_live` / `read_query_input` 的 `local query=""` 与全局
  argv 数组同名，shellcheck 不跟踪作用域。要做的是改名消噪，不是改逻辑。

### 6.2 功能完整度：**按 §0 的定位，已完整**

> **更正记录**：本节第一版拿 kew / ncspot / termusic 当基准，判定"缺队列 = 完整度没到"。那个基准
> 是评估时自己加的，文档从未声明要做通用播放器。按 §0 的定位重评，队列 / 播放列表 / 历史 / 下载 /
> 频道订阅**属于 non-goals，不是缺口**。原结论作废。

按定位评，真正的功能缺口只剩一条，且已在计划内（**更正**：本节原写"唯一契约漏洞"，2026-08-22
另查出两条并当场修掉 —— `-j` 非单行、`yt-play` 的 `--` 绕过门禁，见 §1；那句"唯一"只对**功能**
缺口成立，不对契约漏洞成立）：

- **`-d` 同步失败的原因没有进 envelope** —— 今天它只以散文形式存在于 stderr，`yt-tui` 要解析 `die`
  的措辞并剥 `Error: ` 前缀。这是契约漏洞，不是功能缺失，修在 P0。

### 6.3 发布硬件：没到，但都是便宜活

| 缺项 | 后果 |
|---|---|
| ~~`LICENSE` 不存在~~ | **已补**（MIT，2026-08-21） |
| ~~测试没进仓库~~ | **已补** —— `tests/` 四个装置入库（2026-08-21）。原先所有 rig 都是 `tmp/` 下不追踪的一次性物件：对自己没问题，对贡献者致命 |
| ~~`--version` 不存在~~ | **已补**（2026-08-21）。曾经的后果：bug 报告说不清版本，升级后无法验证装上哪一版 |
| 无 `CONTRIBUTING` / `CHANGELOG` | 次要 |
| Linux 实际不可用 | §5 已述 |

### 6.4 分身份结论

| 以什么身份公开 | 现在够吗 |
|---|---|
| **参考实现 + 设计文档** | **够。** 补 `LICENSE`、套件 README、`--version` 即可 |
| **YouTube 这一格里 agent 可驱动的那个**（即 §0 的定位） | **功能够**，差 §6.3 的发布硬件与 P0 的契约补洞 |
| brew / curl 分发的产品 | 不够，卡点不在功能，在 §5 的环境账 |

---

## 7. 分析：驱动决定的六条发现

1. **差异化在契约，不在渲染。** 真正难而有价值的是 JSON envelope、退出码分类、脱离终端的生命周期 ——
   都与语言无关。而 `yt-tui` 2667 行的大头是在重新实现 Go TUI 栈免费给的东西：显示宽度
   （`go-runewidth`/`uniseg`）、事件循环与 resize（`bubbletea`）、样式（`lipgloss`）。那不是护城河，
   是重写会**删掉**（而非搬迁）的负债。

2. **single-binary 是全有全无。** 一个静态二进制、不要 jq、不要 nc、Linux 能跑、安装一行 —— 链条里
   留一个 shell 脚本就整体作废。Go TUI 接 shell 引擎仍是四依赖。所以 "best of both worlds" 在
   **风险**维度成立，在**分发**维度不成立。

3. **agent 对接的是壳的 argv + core 的契约。** agent 调窄壳是刻意的（单一职责、互斥 flag 直接拒），
   但让调用有意义的东西全在 `yt` 里。重写壳几乎零收益，重写 core 才改变能力边界。

4. **三个 agent 侧诉求都在 core，且 bash 都给不了。**

   | 想要的 | bash 为何不行 | 归属 |
   |---|---|---|
   | MCP stdio server | 手写 JSON-RPC 帧、长连接、并发 | core |
   | 失败原因**进 envelope** | 见 §6.2，账已付过 | core |
   | 流式进度 | 阻塞 `read`、一次性 jq | core |

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

- **D0 —— 定位冻结为 §0**：agent 优先的 YouTube 引擎 + 一张人脸；不做通用 TUI 播放器。
- **D1 —— 不为分发打包 shell 套件。** 支持面（§5）大于差异化（§7.1）。
- **D2 —— 但照样公开仓库，定位为参考实现，不承诺打包。** README 写明这是"一个可用的 shell 实现 +
  一份 2494 行的设计文档"。文档是更可传播的产物。
- **D3 —— 任何重写之前先冻结契约**（envelope schema、player record、退出码表、生命周期语义）。
  它是唯一完整活过重写的东西，也是 Go 版的验收规格。
- **D4 —— Go 的第一步只做 TUI**（`ytt` → Go），调用今天原封不动的 `yt-search` / `yt-play`。被否方案 —— 一次性
  全量移植：把生命周期语义和渲染器重写放进同一次变更，回归无法二分定位。
- **D5 —— "core 是否也去 Go" 是独立的、条件触发的决定**（§9）。触发前 `yt` 保持 shell。
- **D6 —— 发布名 `uting`（§3.1）；本机 PATH 为 `ytt`（人机面短名）+ `yt-search` / `yt-play`
  （agent 面规范长名）。`yts` / `ytp` 弃用 —— 一个命令一个名字，短名只留给真会被手敲的那个。**
- **D7 —— Go 版只发一个二进制加子命令，绝不发三个通用名的可执行文件。**

  ```sh
  uting search …     # 今天的 yt-search
  uting play …       # 今天的 yt-play
  uting              # 无参数 → TUI（今天的 ytt）
  uting mcp          # 第三张脸，D5 触发后
  ```

  **永不发布 `bin/yt`**（§5）。

- **D8 —— 三件发布硬件先于任何公开动作**（§6.3）：`LICENSE`、rig 入库、`--version`。

---

## 9. 把 core 推向 Go 的触发条件

任一为真，core 移植就值得它的风险。全不为真，`yt` 无限期保持 shell —— 那是正当终态。

1. **真的要 MCP**（解除 §0 的那条 non-goal）。
2. **真的要单文件分发**（推翻 D1）。
3. **真的要支持 Linux**（`nc -U` 缺失与 bash 3.2/5 分裂只在这里一起消失）。

次要、单独不足以触发：流式搜索结果；每次按键 fork `stty`；想要带编译期保证的测试套件。

---

## 10. 落地计划

### P0 —— 契约抽取（不写代码，解锁其余全部）

- 从 `SPEC-system.md` 抽成独立契约文档：envelope schema（search / play / status）、player record
  schema、退出码表、生命周期语义（launch → status → stop、幂等、歧义 → 4）、`-j` 单行保证。
- 补上 §6.2 那个洞：**`-d` 同步失败的机读原因字段**。现在定字段、在 shell 里实现，Go 版继承一个没有
  洞的契约。
- 同一批、同样便宜、且互为前提的另两件（2026-08-22 识别）：
  - **`--status` 增加 live `paused` 字段。** 今天播放器的暂停状态在任何 envelope 里都读不到，
    这正是 `live_volume()` 当初要消灭的那种谎（state file 说一套、socket 说另一套）。它也是
    运行时播控动词的前置条件：没有可观测的状态，动词加了也是瞎的（`SPEC-system.md` §26）。顺带修掉
    `yt-tui` 本地 `CURRENT_PLAY_PAUSED` 与外部改动不同步的问题。
  - **`live_volume()` 泛化为通用属性读。** 上一条一落地它就有第二个调用方，且 `volume` 与
    `pause` 能在同一个连接里一次读完 —— 不是空想的抽象。
- 验收：只读这份文档就能写出 JSON diff 测试，不需要读 `yt`。
- 上面这批"便宜且互为前提"的三件已经写成可施工的 `docs/PLAN-envelope-observability.md`
  （字段名、jq、验证矩阵都在那份里；上线即删）。

### P1 —— 独立仓库（D2 + D8）

**2026-08-21 部分完成。** 已做：用 `git filter-repo` 带着 50 个 commit 的历史抽出
`shell/{yt,yt-search,yt-play,yt-tui}` 与 `docs/{DESIGN,ROADMAP}.md`，落在
`~/workspace_fullstack/uting`；补上 `LICENSE`（MIT）、`README.md`、`.gitignore`；三个脚本改为
**自解析符号链接**定位同伴（原先的 `../../shell-scripts` 跳只在那一套 dotfiles 布局里成立，搬仓
即暴露）；`env-config` 不再保留副本，`~/bin/{yts,ytp,ytt}` 直接指向本仓。

**D8 三件已齐**：`LICENSE`（MIT）、rig 入库（`tests/` 四个装置，说明写在根 README 的
`## Tests` 一节 —— 不设 `tests/README.md`，一个仓库一份 README）、`--version`（版本常量
`YT_VERSION` 只在核心里声明一次，壳与 TUI 问它、打印自己的名字，四个入口不会各说各的；且在
任何依赖门之前应答 —— 要装齐 yt-dlp 才能知道自己是哪一版是本末倒置）。

公开与否另行决定 —— 仓库先建为 private。
- README 直说依赖与平台现实（macOS 优先；Linux 需要支持 `nc -U` 的 netcat），并直说 §0 的 non-goals
  —— 省掉一半"为什么没有队列"的 issue。
- 不 vendor yt-dlp 或 mpv。
- 验收：陌生人读完设计文档能理解架构，不必运行任何东西。

### P2 —— Go TUI 接 shell 引擎（D4）

- `bubbletea` + `lipgloss` + `go-runewidth`。移植**决定**而非代码：reflow 的"先测量再预算"顺序、
  details 块作为可计费 chrome、三个播放态、象限 spinner、CHA 定位的时长轨、中英双语、主题。
- mpv socket 用 `net.Dial("unix", …)` —— 客户端侧就此甩掉 nc。
- 交给库因而可删的清单：显示宽度表、resize 处理、事件循环、`\033[K`/`\033[J` 记账、每次按键的
  `stty` fork。
- 验收：对着 `SPEC-system.md` §27 与 shell TUI 并排比对 —— 窄终端网格、reflow 下限用例、中英、
  `YT_ASCII=1`、播放态迁移。复用 pty + pyte 屏幕模型 harness，连同教训：首次读取前 `TIOCSWINSZ`，
  断言下在屏幕模型而非字节流上。

### P3 —— core 移植（仅当 §9 触发）

- 在冻结的契约背后重写 `yt`。jq 化进结构体反序列化，nc 化进 `net.Dial`。flag 学问原样搬（§7.5）。
- 验收：固定查询集上两实现的 `-j` **逐字段 diff**（须含直播行、null 播放量、跨日时长、零结果、强制
  yt-dlp 失败），外加生命周期序列（launch → status → set-volume → stop → 再 stop）退出码全等。
  shell 套件保持安装，充当参考实现。
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
  前置条件同样已记录：`--status` 今天没有 `paused` 字段，agent 暂停了也观测不到 —— 见 §10 P0。

---

## 12. 开放问题

- **定位是否就此冻结在 §0？** 这是唯一能连锁改写本文档的问题：一旦改成"收听应用"，§4 的对标对象、
  §6.2 的完整度结论、被删的 P4 都要回来。
- **`uting` 的挪威语含义**（"陋习"）—— 当彩蛋接受，还是换 `tingyu` / `qingyin`？
- **MCP 那张脸到底属不属于这个产品** —— 还是 agent 通过通用 shell 工具调 `uting search -j` 就够了？
  P0/P1 不依赖这个答案。
- **仓库边界** —— 公开仓库含整个 `yt` 引擎（假定），还是只含壳？（只含壳没有意义。）
