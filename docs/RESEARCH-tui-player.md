# RESEARCH-tui-player —— 终端播放器：别人怎么搭的，我该抄什么、该躲什么

> **先说这份调研是为什么做的**，因为它决定了每个数字该怎么读：
> **uting 是我和几个朋友自用的一件工具 —— 工作时放点音乐，人从 TUI 放，agent 从 CLI 放。**
> 不是要做这个领域的头部项目，也没有用户增长要交代。所以这份文档**不是竞品分析**，
> 它只回答两个自用者的问题：**这件事别人是怎么做的**，以及**哪些做法值得抄、哪些是我不需要的**。
>
> 由此，几个读法要先校准：
> - **star 数不是排名**，它在这里只回答"这项目还活着吗、值不值得花时间读它的代码"（§3）；
> - **功能清单不是差距**。别人为了拿用户在拼的东西（参数 EQ、频谱、图形协议封面、Lua 插件 ABI），
>   对"工作时放点音乐"是零价值 —— 照着抄就是给自己派活；
> - **"要付的账"是我自己付、朋友装的时候也付**（§4），不是发布前的风险清单。
>
> 这仍然是一份调研文档：只记**仓库之外**的事实与可核对的出处，不记我们要建什么。
> 由它落定的决定住在 `ROADMAP.md` —— **D6/D10**（名字）· **D0/§0 的 non-goal**（不做通用
> TUI 播放器）· **D1/D2**（不打包）· **§9**（把播放器推向 Go 的触发条件）。
>
> **文档有两半，分界线是可信度**：**上半 §2–§5 量出来的** —— 叫什么（§2）、外面已经有什么
> （§3）、要付什么账、自用够不够（§4/§5）。**下半 §6–§11 读出来的** —— 别人的播放器怎么搭
> （§6–§8）、国内拿到一个可播 URL 有几条路（§9）、agent 面（§10）、逐项对照（§11）。
> §1 把这条分界线写死，**读之前先看那一节**。

---

## 1. 时效、方法与诚实边界

| 内容 | 日期 | 怎么来的 |
|---|---|---|
| 名字筛查（§2） | 2026-08-21 | **实测** —— 逐项查 PATH / brew / crates / npm / PyPI / GitHub |
| 领域现状（§3） | 2026-08-21 | **实测** —— GitHub API |
| 发布要付的账（§4） | 2026-08-21 | **实测 + 本仓已知约束** |
| 自用够不够（§5） | 2026-08-21，`shellcheck` 计数 2026-08-27 | **实测** |
| **播放设计（§6–§11）** | **2026-08-29** | **读的** —— 网络检索 + 各项目 README / 文档 / CHANGELOG / issue |

**这两半的可信度不一样，混着引用就会出错。**

上半的每个数字都会过期 —— star 数、`pushed_at`、`shellcheck` 计数尤其。想重开
`ROADMAP.md` 里任何一条由它支撑的决定，**先按对应小节的方法重跑，别照抄结论**。

下半**没有逐个装起来跑**，是文献调研。因此：每条陈述都带出处（§13），**读结论不如读出处**；
标 **[需实测]** 的是**会影响设计判断、但只有二手来源**的事实 —— 想拿它当依据，先自己跑一遍；
§12 单列本轮没能确定的问号。

---

## 2. 名字：六项筛查（压缩留档）

**方法**：每个候选查六项 —— 本机 PATH、Homebrew（core formula + cask）、crates.io、npm、PyPI、
**同领域**的 GitHub 同名仓库；六项全空才算可用。"同领域"是必要限定：撞在别的生态上只是噪音，
撞在同一批用户身上才是代价。**自用的工具照样要查**：命令要上自己的 PATH，撞名是自己每天踩。
两轮应用的结果：项目名 **`uting` 六项全空**（2026-08-21），
命令名 **`ut-*` 这类长前缀全空、光杆短名全被占**。由此得出的规则不是调研结果而是决定，
住在 `ROADMAP.md` D6/D10，这里不复述。**下表留档只为一个目的：挡住重复调研。**

| 候选 | 六项结果 / 否掉的理由 |
|---|---|
| `uting` | **全空** —— 采用（`ROADMAP.md` D6）。已知瑕疵：挪威语里是真词，意为"陋习"，当彩蛋接受 |
| `tingyu` / `qingyin` | **全空** —— 备选，未采用 |
| `ut-play` / `ut-search` 等长前缀 | **全空** —— 采用（`ROADMAP.md` D10） |
| 光杆 `ut` | **全占** —— npm / PyPI / crates，外加 `boost-ext/ut` 1438★ |
| `utt` | 被占 —— npm / PyPI，外加 `larose/utt` 349★ |
| `ytt` | 撞 carvel 的 YAML 模板工具（1873★，`brew install ytt`），且撞的是同一批 k8s 用户 |
| `yting` | **六项也全空，照样否掉** —— 描述性名字，焊死 YouTube |
| `ting` | 撞商标 `Ting®`，另有同名异义的命令行音频工具 —— SEO 全废 |
| `tin` | 撞 Usenet 阅读器 |
| `kiku`、单音节拼音（`yin`/`yun`/`sheng`/`qu`…）、`tuna`、`dial` | crates / npm 上已被抢完，或各有主 |

**规律**：短的 `yt*` / `t*` 这块地已经被翻过一遍，还空着的只有拼前缀拼出来的 `uting`。

---

## 3. 领域现状（GitHub API 实测）

**这一节量的是"谁还活着、谁的代码值得读"**，不是排名。一个死了两年的 19310★ 项目，
对我的价值低于一个 209★ 但每周都在动的项目 —— 后者会告诉我这条路今天还通不通。

### 3.1 头部分布

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

**`pushed_at` 会把两个分布抹平，必须看 commit 数**：经典四件套在**维护模式**
（近 180 天：`musikcube` 1、`ncmpcpp` 2、`yewtube` 4、`cmus` 7），生长全在 2024–2026 新生代
（`cliamp` / `rmpc` / `kew` / `termusic` / `spotatui` / `go-musicfox` / `yt-x` 各 100+）。

### 3.2 国内格

原表完全缺失，两条形态判断：

- 头部只有"网易云 + 逆向 API"这一条路，且只有两个玩家有规模（`musicbox` 9830★、
  `go-musicfox` 2513★）；其成本不在渲染而在**持续对抗接口变更**（`UnblockNeteaseMusic`
  的存在本身就是证据）。
- **2026 年建仓的中文项目集体在换音源** —— `maboroshi`、`bighu630/music-tui`、`yueting`、
  `BiliBiliMusicPlayer` 一律走 **YouTube / B 站 + yt-dlp/mpv**，不再碰网易云。

这几个项目的**架构**（解码在哪、寿命、控制面）见 §11 的五轴表 —— 这里只量规模。

**国内新生代与本仓走在同一条技术路线上**（YouTube / B 站 + yt-dlp + mpv），
只是都还在 0–10★ 的量级（唯一例外是 `MareDevi/bilibili-tui` 209★）。
**这是好消息**：同路的人不少，坑有人先踩过，读他们的代码比自己试便宜。

### 3.3 三条结论

1. **这个领域按音源分层，不按 UI 分层。** "不做通用播放器"的第一位理由是**我不需要一个**：
   工作时放点音乐用不上参数 EQ、频谱、图形协议封面、Lua 插件 ABI —— 而那一层正是在这些东西上
   卷（每月都有新项目以 ~500★/月 起量，`cliamp` 六个月 3403★）。第二位理由才是成本：
   那些别人靠语言和库免费拿到的东西，**bash 3.2 要从零手写**。
   决定见 `ARCHITECTURE.md` §1 与 §1.1 第 1 条。

2. **YouTube 这一格的人机面已被占，机器面仍空。** `ytfzf` 死在 2024-09，
   但**位置被 `Benexl/yt-x` 接管了**（1642★，POSIX sh + fzf + jq + curl + mpv，
   近半年 100+ commit）—— 技术栈与本项目高度重合，功能面走得更远（行内过滤、搜索历史与 bang
   召回、个人 feeds、分页、下载、扩展系统）。**但它没有机读契约**：本地 JSON 是它自己的状态文件，
   不是对外承诺。它的**扩展系统**（source shell 脚本、覆盖函数）是本仓**明确不该抄**的东西 ——
   那是把 shell 的动态作用域当插件 ABI，与"契约即安全边界"的取向正相反。

3. **agent 可驱动的先例分四档 —— 这一格不是空白。**（**别再写"没有一个能被 agent 驱动"**：
   实测不成立，写进定位文案就是错的。）MPD 全家
   （`ncmpcpp`/`rmpc`）**天生**可驱动，协议二十余年稳定且有 `mpc`；`cmus-remote -Q` 1998 年就在出
   行式 key/value；`ncspot` **推 JSON 到 unix socket**（与本仓的 mpv IPC 客户端路径几乎同构，
   连"stock netcat 不肯关连接"那个坑都踩过并写进了文档）；`spotify-player` 是
   **daemon + CLI 动词 + 给 jq 的 JSON**，且**早于本项目**；`termusic` 拆 server/client 走 gRPC；
   `spotatui`（1247★）与 `spotuify` 已经在出 **MCP 面**；`mpv-mcp-server` 干脆从另一侧直接做了
   mpv + yt-dlp 的 agent 面。**这条结论在 §10 有 2026 年的续篇**：agent 面已经不是加分项，
   而且"可被 agent 驱动"与"播放脱离 UI 存活"被证明是同一个架构需求的两面。

### 3.4 站得住的收窄版命题

**这一节回答的是"我为什么没直接用现成的"** —— 不是市场空位分析。经得起查的只有这一句：

> 在 **YouTube 这一格**里，仍然没有一个项目提供**单行 JSON envelope + 退出码分类 + 脱离终端的
> 播放器生命周期（launch → status → stop，幂等，歧义即 4）**这一整套契约。

`yt-x` 无机读契约；`youtui` 的独立 API crate 是给 Rust 调用方的库，不是 CLI 契约；其余是纯 TUI。
所以这不是"抢到了一个空位"，是**我要的那件事没有现成的**：让 agent 和我用同一套命令放同一首歌。
**别拿 star 数跟这些项目比 —— 不在同一件事上。**

§10 从另一个方向印证了这句话：2026 年出 agent 面的项目里，**只有 spotuify 一个把播放生命周期
也交了出去**，而它靠的是守护进程形态（§7.3）；其余（`Meting-Agent`、bilibili-mcp 一族）**只做查**。

顺带记一笔（真做 MCP 时要用）：字幕这一格在 MCP 生态里已有 `kevinwatt/yt-dlp-mcp`（273★），
与 `yt-resolve --transcript` 正面重叠；`spotatui` 的 MCP 面给出了可抄的工程细节 ——
具体清单在 `ROADMAP.md` §9 触发条件 1。

---

---

## 4. 这套东西要付的账（我自己付，朋友装的时候也付）

- **bash 3.2 与 5 的行为差异**，可移植性契约已长篇记录（`ARCHITECTURE.md` §28）—— 那是持续的维护承诺。
- **Linux 自带 netcat 没有 `-U`**（`ARCHITECTURE.md` §26）。我自己不碰，但**朋友里有人用 Linux
  就是直接卡住** —— 这是这份清单上唯一会当场拦人的一条。
- **终端动物园**：DCS 帧同步、Ambiguous 宽度、tmux 透传 —— 宽度层与 `YT_AMBIG_WIDE` 存在的全部理由。
  换一个终端、换一台机器就可能露头。
- **五个运行时依赖**（yt-dlp、jq、mpv、nc、curl），全部由用户负责安装并保持可用；且**每加一个
  音源就多一份站点维护面** —— 引擎对是本仓唯一会因外部网站变动而坏掉的地方（`ROADMAP.md` D9
  把它关进两个文件，但没让它消失）。
- **通用短名不可用**：由 `ROADMAP.md` D10 兑现（命令名全做过六项筛查，§2），
  但它仍约束 Go 版 —— 见 D7 的"永不发布 `bin/yt`"。

**预期：朋友装不上的时候，九成是环境问题，不是行为问题。** 这条决定了帮人排查该先看哪儿。

**而"shell 这条路今天走不通"不成立** —— `yt-x` 是 POSIX sh + 四依赖，2024-09 建仓，
2026 年仍在收 1642★ 与 100+ commit/半年（§3.3 结论 2）。上面那笔环境账照付，
但它不构成"该换语言"的理由。

---

---

## 5. 自用够不够

### 5.1 代码与设计质量

- 契约纪律：`-j` 单行 JSON、退出码分类（1 用法 / 2+ 传递 / 4 未生效）、US 而非 tab 作分隔、不从渲染
  串反解数据。
- 边界处理：EAW 宽度表 + CJK 精确宽度、`YT_ASCII` 全量回退、中英 i18n 无串泄漏、reflow 验到 40×12。
- 一份与代码同步的设计文档，带一份可复查的验证矩阵。
- **`shellcheck --severity=warning` 基线是一个被跟踪的计数，不是一张干净的体检单**
  （2026-08-27 八个脚本重测，`--format=json1` 计数 —— 一行上落两条时 `grep '^In'` 会少数）
  共 **22 条**：SC2088×8、SC2128×5、SC2178×4、SC2174×3、SC2054×2、**SC2034×0**。
  - SC2128/SC2178 那 9 条**全在 `uting`、全是假阳性** —— `filter_live` / `read_query_input` 的
    `local query=""` 与全局 argv 数组同名，shellcheck 不跟踪作用域。要做的是改名消噪，不是改逻辑。
    **四个引擎与播放器文件里 SC2128/SC2178 是零。**
  - SC2174 那 3 条同形、同为已知可接受项：`mkdir -p -m 700` 的 mode 只作用于最深一层，
    所以三处都在事后再 `chmod`。
  - **SC2088 那 8 条是同一行，一个入口点一条**：配置读取器 `ut_read_config` 里的
    `[[ "$val" == "~/"* ]]` —— 那个 `~` 是**当作字面量来匹配**的模式，不是要展开的路径，
    紧接着的赋值本身用的就是 `$HOME`。八份逐字副本，所以一处误报计八次（见 CLAUDE.md
    的"一个事实一处"carve-out：八个独立可执行文件不共享库）。

**这条基线的用法是比较，不是绝对值**：改动前后各跑一次，看净增几条 —— 净增 0 才算没欠新账。

### 5.2 功能完整度

两把尺子，必须分开量，否则结论一定错：

- **契约完整度：到了。** envelope、退出码、生命周期、引擎契约都实现且有回归覆盖
  （`ARCHITECTURE.md` §14/§27）。
- **功能完整度：到了。** `ROADMAP.md` D14/D15 那三条（播放列表、队列、历史）都已落地，
  每条都带着自己的动词和 `-j` envelope。**"工作时放点音乐"这件事，清单到此为止** ——
  拿 kew / ncspot / termusic 当基准来评是错的，那是通用本地播放器的清单，不是这里要的。

### 5.3 发布硬件

只剩一个真缺项：**Linux 实际不可用**（§4，由 `ROADMAP.md` §9 触发条件 3 把关）。
其余都是可选项。

### 5.4 按"谁在用"分档

| 谁在用 | 够吗 |
|---|---|
| **我自己**（macOS，人从 TUI、agent 从 CLI） | **够** —— 这就是它被造出来要满足的那件事 |
| **朋友手动装**（clone + 软链上 PATH） | **够，但要陪装一次**：五个依赖靠他自己装，Linux 直接卡住（§4） |
| **陌生人 brew / curl 装** | **不够**，卡点不在功能，在 §4 的环境账 —— 也不是现在想要的（`ROADMAP.md` D1/D2） |

---

## 6. 坐标系：一个播放器的设计其实是五个独立的选择

看了十几个项目之后，最有用的发现不是某个项目怎么做，而是**这些选择彼此正交**。
把它们拆开，任何一个播放器都能一句话定位，比较也才有意义。

| 轴 | 问题 | 取值 |
|---|---|---|
| **A 解码在哪** | 谁把字节变成声音 | 进程内库 / 外部播放器进程 / 远端设备 |
| **B 播放进程的寿命** | 关掉 UI，歌还响吗 | 随 UI 生死 / 独立守护进程 / 远端 |
| **C 站点知识在哪** | 谁知道怎么从一个网页拿到流 | 内置逆向 / 外包给 yt-dlp / 外挂脚本源 / 远端 API 网关 |
| **D 控制面** | 谁能操作它 | 键盘 / 本地 socket 协议 / 网络协议 / 系统媒体键 / **agent** |
| **E 提取几次** | 一次拿到 URL 就够了吗 | 一次提取（URL 有时效）/ 交给播放器反复提取 |

轴 A 与轴 B 常被当成一回事，其实不是：**外部播放器进程 ≠ 独立寿命**
（bilibili-tui 用外部 mpv，但 mpv 是它的子进程），
**进程内解码也能有独立寿命**（spotifyd 自己就是守护进程）。
真正决定"关掉 UI 歌还响不响"的是轴 B，不是轴 A。

---

## 7. 五种播放架构

### 7.1 进程内解码

**机制**：应用自己链接一个解码库，自己开音频设备。Rust 侧是 `symphonia`（解容器/解码）
+ `rodio`（输出），Go 侧是 `beep`。

**谁在用**：
- **termusic** —— 默认后端叫 `rusty`，就是 Symphonia；另外两个后端是 GStreamer 与 MPV，
  **后端可在运行时切换，不是编译期决定**（[termusic README](https://github.com/tramhao/termusic)、[DeepWiki](https://deepwiki.com/tramhao/termusic)）。
- **go-musicfox** —— 默认 `beep`，另有 `mpd`、`mpv`、`dlna` 三个可选引擎 [需实测：配置键名与各引擎的实际能力差异]。
- **spotify_player** —— `ratatui` + `rspotify` + `librespot`，默认音频后端 `rodio`（[crates.io](https://crates.io/crates/spotify_player)）。
- **cliamp** —— 本地文件走**纯 Go 解码，不需要任何外部工具**；只有网络源才拉 yt-dlp
  （[cliamp README](https://github.com/bjarneo/cliamp)）。

**买到什么**：零外部依赖（至少对本地文件是）；对**采样率、缓冲、无缝衔接**有完全控制权 ——
这是 gapless 与频谱可视化必须在进程内才好做的原因（spotify_player 的实时 FFT 频谱正是"本地
用 librespot 播时才有，投到外部 Connect 设备就隐藏"）。

**付什么账**：**格式矩阵要自己填**。termusic 的文档要为 Symphonia / MPV / GStreamer 三个后端
分别列出 ADTS / AIFF / FLAC / M4a / MP3 / Opus / Ogg / WAV / WebM / MKV 的支持情况 —— 这张表
本身就是这条路的成本。seek 精度、容器级定位也得自己负责（有实现明确写"用 Symphonia 做
容器级精确 seek，rodio 作为 fallback 解码器"）。

### 7.2 外部播放器 + IPC（mpv 模型）

**机制**：`mpv --input-ipc-server=<path>` 打开一条 **行式 JSON** 通道；每条消息是一个
JSON 对象加换行，编码是 RFC-8259 的 UTF-8。Linux/macOS 是 unix socket，**Windows 是命名管道**
（同一个选项，mpv 自己切换）；另有 `--input-ipc-client` 直接收文件描述符。
mpv 手册对它的定位写得很直白：**"不是安全的网络协议 —— 没有认证、没有加密，命令本身也不安全"**
（[mpv ipc.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/man/ipc.rst)）。

**谁在用**：
- **bilibili-tui**（Rust + Ratatui 0.30 + Tokio）：扫码登录拿 `sessdata` / `bili_jct` 存在
  `~/.config/bilibili-tui/`，**把 cookie 同步给 mpv**，由 mpv + yt-dlp 出流
  （[README](https://github.com/MareDevi/bilibili-tui)）。
- **go-musicfox**：5.0 起为 Windows 的 MPV 播放器加了**命名管道通信** —— 同一个
  IPC 模型在 Windows 上的落地（[CHANGELOG](https://github.com/go-musicfox/go-musicfox/blob/master/CHANGELOG.md)）。
- **termusic** 的 MPV 后端、以及本仓。

**这条路上真正要做的四个决定**（mpv 侧的选项名，本仓的用法见 `docs/AS-BUILT-player.md` §8）：

| 决定 | mpv 侧 | 后果 |
|---|---|---|
| 提取归谁 | 默认 `ytdl_hook` 会拦下 URL 去调 yt-dlp；`--no-ytdl` 关掉它 | 关掉，就等于**声明"提取由调用方做一次"**（轴 E） |
| 请求头怎么带 | `--http-header-fields`（是个 LIST，多头要用 `-append` 或数组语义） | mpv 的 issue #9978 / #6492 都是这个坑：ytdl_hook 分离音视频流时，头能不能正确传下去 |
| 进程活不活 | `--idle`（没片可播也不退）/ `--keep-open`（播完最后一个不退，改成暂停） | 决定"播完之后这个进程还在不在"，直接关系轴 B |
| 无缝 | `--gapless-audio`（按第一个文件的参数开音频设备并保持打开）/ `--prefetch-playlist=yes`（本地或网络都能无缝） | 见 §8.1 |

**买到什么**：编解码、容器、seek、硬件输出、HLS/DASH 全部外包给一个被几百万人测过的
实现；**跨平台的音频输出问题不归你管**。而且这是唯一一条**天然支持轴 B 独立寿命**的路 ——
mpv 是个独立进程，谁启动它跟它活多久无关。

**付什么账**：多一个运行时依赖；IPC 的传输在平台间不同（unix socket vs 命名管道），
**没有认证**意味着 socket 的文件权限就是全部的安全边界；以及最隐蔽的一条 —— mpv 的
`--input-ipc-server` **是每进程的**，多个并发播放器就是多个 socket，不是一个总线。

### 7.3 守护进程 + 协议（客户端只是视图）

**机制**：把播放、队列、状态放进一个**长期存活的服务端**，UI 只是它的客户端，通过某种协议
连上去。这是终端音乐领域最老、也最近重新流行起来的形态。

**四个样本，四种协议**：

| 项目 | 服务端 | 协议 | 客户端 |
|---|---|---|---|
| **MPD** | `mpd` 守护进程，管播放 + 播放列表 + 音乐库 | 自定义文本协议，默认 `127.0.0.1:6600` 或 unix socket | ncmpcpp（C++）、rmpc（Rust）等几十个 |
| **termusic** | `termusic-server` | **gRPC** | `termusic` TUI，与服务端**是两个进程** |
| **spotuify** | 一个守护进程，内嵌 librespot | **一条 unix socket** | TUI / CLI / **MCP** / macOS 菜单栏，共四个 |
| **spotifyd** | 守护进程，实现 Spotify Connect | Spotify Connect（网络协议） | 任意官方/第三方 Spotify 客户端 |

**这条路 2026 年的新意在 rmpc 和 spotuify 上**：
- **rmpc** 本身是纯客户端 —— "它不做音频输出，只向 MPD 发命令"；但它另配了一个 **`rmpcd`
  后台守护进程，用来把功能延伸到 TUI 生命周期之外**，带 Lua 插件系统（可脚本化 song-change
  之类的事件）和 D-Bus MPRIS 接口（[rmpc](https://github.com/mierak/rmpc)）。
  **注意这里出现了两层守护进程**：MPD 负责播，rmpcd 负责"UI 关了之后还要发生的事"。
- **spotuify**（Rust，2026）把这个形态推到了极致，README 的原话是
  **"一个守护进程，四个客户端"**：守护进程内嵌 librespot、自己**就是**那个 Spotify Connect
  设备（不是遥控别的播放器），带 SQLite 元数据缓存和 Tantivy 搜索索引；CLI 有 **58 条命令、
  与 TUI 完全对等**，输出可选 table / JSON / JSONL / CSV / 纯 ID，专门为管道设计；
  另有 **41 个工具的 MCP 面**，并且明确写着 **"agent 跑的是和你一样的命令"**，
  `ops undo` 是它的安全网（[spotuify](https://github.com/planetaryescape/spotuify)）。

**买到什么**：轴 B 彻底解决 —— 关掉 UI 歌照响，另一个 shell 里发的命令立刻生效；
**并且控制面天然多份**（TUI / CLI / MCP / 媒体键都是同一个服务端的客户端）。

**付什么账**：多了一个要管的长驻进程 —— 启动、崩溃、版本对齐、状态目录、并发客户端。
协议一旦公开就是冻结面（MPD 的协议活了二十年，代价是它至今还是那个形状）。
termusic 为此付的是 gRPC 全套依赖；spotuify 付的是一个 SQLite + Tantivy 的运行时。

### 7.4 协议级客户端（自己就是那台设备）

**机制**：不调用任何播放器，也不解析网页 —— **直接实现服务方的私有协议**，把自己注册成一台
播放设备。`librespot` 是这条路的公共基座：它是 Spotify 官方已弃用的闭源 libspotify 的开源替代，
**既作为库出货，也作为 headless 二进制出货**（后者会在局域网里注册成一个 Spotify Connect 接收端），
ncspot / spotifyd / Snapcast 都嵌它（[librespot](https://github.com/librespot-org/librespot)）。
Go 侧的对应物 `go-librespot` 被 cliamp 用来接 Spotify。

**买到什么**：官方级的能力（登录、推荐、跨设备接管），以及**别的客户端可以来控制你** ——
用手机上的官方 App 控制终端里的播放器，这是其他任何架构都做不到的。

**付什么账**：一个源一套协议，**完全不可复用**。它是"深"的极致，也是"窄"的极致。
这也是国内平台上几乎没有对应物的原因：没有 Connect 这类开放的设备协议可实现，
只能退回 §9 的音源路线。

### 7.5 投放到远端（DLNA / UPnP）

**机制**：本机既不解码也不开音频设备，只把一个 URL 和控制指令交给局域网里的电视/音箱/主机。
go-musicfox 5.0 加了 **DLNA/UPnP 播放引擎**，跟 `beep`/`mpd`/`mpv` 并列为一个可选 engine
（[CHANGELOG](https://github.com/go-musicfox/go-musicfox/blob/master/CHANGELOG.md)）。

**值得记的一点**：它和 §7.4 是同一个思想的两个方向 —— 都是"播放发生在别处"。
把 DLNA 做成**与本地引擎并列的一个 engine**，而不是一个独立功能，是 go-musicfox 这次
架构上最干净的一笔：**轴 A 的第三个取值被收进了同一个抽象里。**

---

## 8. 五个横切问题（不属于任何一种架构，但每种都要回答）

### 8.1 gapless 无缝

- **mpv 路线**：`--gapless-audio` 的机制是 **按第一个文件的参数打开音频设备，然后一直不关**；
  跨文件无缝还需要 `--prefetch-playlist=yes`，它对**本地文件系统和网络流都有效**。
- **进程内路线**：termusic 为 symphonia / mpv / gstreamer **三个后端都实现了 gapless**，
  `Ctrl+g` 切换，**默认开启**。
- **代价**：无缝的前提是"下一首在当前这首结束前就已经就绪"。这与 §8.3 的 URL 时效直接冲突 ——
  预取得太早，URL 可能在真正播到时已经过期。

### 8.2 网络流的缓冲：管道直喂的隐藏代价

dennislan 的 Music Player TUI 是这条路最纯粹的样本：
**`yt-dlp stdout → Arc<Mutex> 共享缓冲 → rodio 解码 → 音频设备`**，
后台播放线程与 TUI 之间用 mpsc 通道通信，**零落盘**（[项目页](https://dennislan.github.io/music-player/)）。

**买到**：边下边播、不写磁盘、不需要 mpv。
**付出**：管道**不可 seek**。该项目宣传的 seek 是 ±10 秒，且有"跨会话记住位置"这样的功能 ——
在一条只能前进的管道上，这两件事的实现代价远高于把 URL 交给 mpv 让它自己发 Range 请求。
**判据**：如果产品要"拖动进度条"，管道直喂就是错的路；如果只要"顺序听完"，它是最省依赖的路。

### 8.3 URL 时效：一次提取的隐含期限

这是"一次提取"（轴 E）这条路唯一的真实代价，也是最容易被忽略的。

- **YouTube**：签名过的 `/videoplayback` 链接是限时的，**约 6 小时** [需实测 —— 二手来源，
  且平台随时可改]。
- **Bilibili**：yt-dlp 的 issue #16571 记录了一个更麻烦的状态 —— **网页与 WBI 签名都成功，
  但 `x/player/wbi/playurl` 仍返回 HTTP 412，即使 cookie 有效且出口 IP 相同**；
  2026-04 前后的若干 issue 指向"playurl 现在需要超出标准 cookie 的浏览器/运行时上下文"
  （[#16571](https://github.com/yt-dlp/yt-dlp/issues/16571)、[#16584](https://github.com/yt-dlp/yt-dlp/issues/16584)）。
  **这是本轮调研里最该盯住的一条**：它不是时效问题，是**风控在收紧**。

**设计含义**：把提取结果存进播放列表是错的（存的是会烂的 URL），存**调用**才是对的；
队列预取的窗口不能太长（§8.1 的冲突）；以及，任何"一次提取"的架构都必须有一条
**过期即重解**的路径，否则长队列必然在中途失败。

### 8.4 系统媒体集成：三个平台三套 API

想接系统媒体键 / 锁屏卡片 / 蓝牙耳机按钮，就得分别对接：

| 平台 | API |
|---|---|
| Linux | **MPRIS**（D-Bus，freedesktop 规范 v2.2）—— 连 session bus、占用 MPRIS bus name、把 D-Bus 调用翻成播放命令、再把状态作为 MPRIS 属性发布出去 |
| macOS | **MPNowPlayingInfoCenter + MPRemoteCommandCenter**（需要走 Objective-C 运行时） |
| Windows | **SMTC**（System Media Transport Controls）—— 媒体键、音量浮出控件、任务栏 / Win+G 里的那个卡片 |

cliamp 把这三套收进一个叫 `mediactl` 的服务里，并单独写了篇文档
（[mediactl.md](https://github.com/bjarneo/cliamp/blob/main/docs/mediactl.md)）；
SPlayer 在 Linux 用 `mpris-server` crate、macOS 走 Objective-C 运行时、Windows 接 SMTC，
是同一套做法。go-musicfox 也三个都做了（README 明确写 MPRIS / Now Playing / 系统媒体控制）。

**值得注意的是它与轴 B 的耦合**：媒体键要能控制的是**正在播的那个进程**。
UI 与播放分离的架构里，MPRIS 该由谁来发布，是个真问题 —— rmpc 的答案是让 `rmpcd`
（而不是 TUI）来持有 D-Bus 接口。

### 8.5 一个反复出现的模式：把"源"做成协议或脚本，而不是模块

三个不同世代的样本，同一个答案：

- **FeelUOwn**（Python）：`fuo://{provider}/{type}/{id}`，例如
  `fuo://netease/artists/46490`。**源是 URI scheme 的一段**，provider 以插件形式存在
  （netease / qqmusic / local / xiami…）（[fuo 协议](https://feeluown.readthedocs.io/en/latest/protocol.html)）。
- **lx-music / MusicFree**：源是**外挂的 JS 脚本**，用户在设置里导入。MusicFree **自身零内置源**，
  搜索、歌单导入、歌词全部由插件提供。这已经是国内音源分发的事实标准
  （[LXMusic vs MusicFree](https://zhuanlan.zhihu.com/p/718757633)）。
- **go-music-dl**：平台逻辑全部收进一个独立库 **`music-lib`**，主程序只是它的三个壳
  （Web / TUI / 桌面）（[README](https://github.com/guohuiyuan/go-music-dl)）。

**共同点**：源的数量会增长且不可控（平台会挂、会封、会改签名），所以**源必须能在不改主程序的
前提下增删**。分歧只在边界画在哪：URI 协议（FeelUOwn）、脚本沙箱（lx-music）、
库（go-music-dl）、**还是可执行文件**（本仓的 `<engine>-search` / `<engine>-resolve` 对）。

---

## 9. 音源层：拿到一个可播 URL 的四条路（国内侧）

播放架构解决"怎么播"，这一节是"播什么"。国内平台没有 §3.4 那样的开放设备协议，
所以只剩四条路，且**每条都在 2026 年出现了退化**：

| 路线 | 机制 | 2026-08 的状态 |
|---|---|---|
| **官方 API 逆向** | 直接实现 eapi/weapi 等加密调用 | Binaryify 的 `NeteaseCloudMusicApi` **GitHub 仓已停更**（npm 尚有版本），接力的是 `api-enhanced` 与 `xgxdmx/NeteaseMusic-API`（自 v4.28.0 起自维护）。**从"一个大仓"碎片化成"若干分叉"** |
| **多源回退** | 一首歌不可用就去别家找替身（UnblockNeteaseMusic 模型：酷狗/酷我/波点/咪咕/JOOX/YouTube/Bilibili） | **明确退化**：酷我大量返回同一 URL 且要求开会员（[issue #1299](https://github.com/UnblockNeteaseMusic/server/issues/1299)）；有测试报告称 QQ 与咪咕不再支持海外 IP，酷我尚可 |
| **yt-dlp 统一提取** | 站点知识外包给上游 | B 站侧见 §8.3 的 412；国内音乐平台（网易云/QQ/酷狗）覆盖弱 |
| **远端聚合网关** | 自己不碰站点，调一个统一 API | `Meting-Agent`（音乐虾）聚合网易云/QQ/酷狗/酷我，统一接口 search / song / album / artist / playlist / **url** / lyric / pic，**同时出 MCP 和 Skill 两种形态**（[GitHub](https://github.com/ELDment/Meting-Agent)） |

**新出现的源**（值得记，因为它们已进入聚合器的清单）：
**汽水音乐**（字节，go-music-dl 支持，需音频解密）、**小宇宙**（播客，cliamp 支持）、
5sing、千千、JOOX。

---

## 10. agent 面：2026 年它不再是加分项

三个独立样本在同一年做了同一件事：

- **Meting-Agent**：一个音源聚合器，**同时提供 MCP server 和 Claude Skill**；
- **bilibili-mcp-server** 一族：其中一个有 **22 个工具**，覆盖视频 / 弹幕 / 字幕 / 评论 /
  直播 / 用户 / 专栏（[iseenope/bilibili-mcp-server](https://github.com/iseenope/bilibili-mcp-server)）；
- **spotuify**：**41 个 MCP 工具**，与 58 条 CLI 命令、TUI 完全对等，明确写着
  "agent 跑的是和你一样的命令"。

**但要看清楚这三者的边界**：Meting-Agent 和 bilibili-mcp 都**只做"查"** —— 搜索、拿链接、
拿字幕；**没有一个管播放进程的生命周期**。唯一把"播"也交给 agent 的是 spotuify，
而它靠的正是 §7.3 的守护进程形态。

**这构成本轮调研最有价值的一条观察**：
**"可被 agent 调用" 与 "播放能脱离 UI 存活" 是同一个架构需求的两面。**
一个只在 TUI 前台活着的播放器，天然无法被 agent 驱动 —— 因为 agent 不持有终端。
spotuify 用守护进程 + unix socket 解决它；本仓用 detached 进程 + 每进程 socket + JSON 契约
解决它（`docs/AS-BUILT-player.md` §9）。**这是两种不同的答案，但回答的是同一个问题。**

---

## 11. 样本清单

按 §6 的五轴排开。**"最近活动"一栏是 2026-08-29 读到的，最先过期。**

| 项目 | 语言 / UI | A 解码 | B 寿命 | C 站点知识 | D 控制面 | 最近活动 |
|---|---|---|---|---|---|---|
| **go-musicfox** | Go / Bubbletea | beep（默认）· mpd · mpv · **dlna** | 随 UI | 内置网易云 + UnblockNeteaseMusic | 键盘 · MPRIS · Now Playing · SMTC | 5.0（2026-07）、5.1（2026-08） |
| **bilibili-tui** | Rust / Ratatui 0.30 | 外部 mpv | 随 UI | yt-dlp + 自己的扫码登录 | 键盘 · 鼠标 | 活跃（~100 commits） |
| **termusic** | Rust / tui-realm | symphonia（默认）· mpv · gstreamer，**运行时可切** | **独立**（termusic-server） | 本地 + 播客 | 键盘 · gRPC · MPRIS | 活跃 |
| **spotuify** | Rust / ratatui | 内嵌 librespot | **独立守护进程** | Spotify 协议 | 键盘 · **CLI 58 命令** · **MCP 41 工具** · 菜单栏 | 活跃（~546 commits） |
| **spotify_player** | Rust / ratatui | rodio + librespot | 可选 daemon（`-d`） | Spotify 协议 | 键盘 · Connect | 活跃 |
| **rmpc** | Rust / ratatui | **无**（MPD 播） | MPD 独立 + `rmpcd` | MPD 音乐库 | 键盘 · MPD 协议 · rmpcd 的 MPRIS + Lua 插件 | 活跃 |
| **cliamp** | Go / Bubbletea + Beep | 纯 Go 解码（本地）· yt-dlp（网络）· go-librespot | 随 UI | **yt-dlp 覆盖 + Lua 插件** | 键盘 · `mediactl`（三平台媒体键） | 活跃（~798 commits） |
| **go-music-dl** | Go / Bubbletea | —（以下载为主） | — | **`music-lib`：10+ 国内平台** | CLI · TUI · Web · 桌面 | 活跃（~379 commits） |
| **FeelUOwn** | Python / GUI+ | — | — | **`fuo://` 协议 + provider 插件** | GUI · fuo 协议 | 长期维护 |
| **Music Player TUI** | Rust / ratatui + rodio | 进程内，**yt-dlp 管道直喂** | 随 UI | yt-dlp 全覆盖 | 键盘 | 新 |

---

## 12. 本轮没能确定的问号

诚实记下来，免得下一轮重复踩：

1. **B 站 `playurl` 的实际有效期**，以及 412 的触发条件是否与 IP / UA / 是否登录相关 —— 只看到
   issue，没有实测（§8.3）。**这是最该先补的一条**，因为它决定"一次提取"的安全窗口。
2. **YouTube 6 小时**这个数字只有二手来源，且平台可随时改。
3. **各国内音源的实际可用率**：UnblockNeteaseMusic 的退化有 issue 佐证，但"哪几个源现在还能用、
   成功率多少"需要真的跑一遍，而且**结论只对跑的那天、那个 IP 有效**。
4. **go-musicfox 的 mpv engine 具体怎么通信**（是不是也走 JSON IPC，Windows 命名管道之外的路径）
   —— CHANGELOG 只写了结果，没写机制。
5. **termusic 的 gRPC 接口是否算公开契约**（能不能被第三方客户端调用），文档没说。
6. **spotuify 的 MCP 面与 CLI 面是否真的对等**（41 vs 58），以及 `ops undo` 覆盖哪些操作。

---

## 13. 出处

**播放架构 / 播放器**
- mpv JSON IPC 手册：https://github.com/mpv-player/mpv/blob/master/DOCS/man/ipc.rst
- mpv 选项手册：https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst
- mpv `ytdl_hook.lua`：https://github.com/mpv-player/mpv/blob/master/player/lua/ytdl_hook.lua
- mpv issue #9978（ytdl_hook 的 http headers）：https://github.com/mpv-player/mpv/issues/9978
- termusic：https://github.com/tramhao/termusic · https://deepwiki.com/tramhao/termusic
- go-musicfox：https://github.com/go-musicfox/go-musicfox · CHANGELOG：https://github.com/go-musicfox/go-musicfox/blob/master/CHANGELOG.md
- bilibili-tui：https://github.com/MareDevi/bilibili-tui
- cliamp：https://github.com/bjarneo/cliamp · mediactl：https://github.com/bjarneo/cliamp/blob/main/docs/mediactl.md
- spotuify：https://github.com/planetaryescape/spotuify
- spotify_player：https://crates.io/crates/spotify_player
- librespot：https://github.com/librespot-org/librespot
- rmpc：https://github.com/mierak/rmpc · MPD 客户端总表：https://www.musicpd.org/clients/
- Music Player TUI（dennislan）：https://dennislan.github.io/music-player/
- FeelUOwn fuo 协议：https://feeluown.readthedocs.io/en/latest/protocol.html
- MPRIS 规范 v2.2：https://specifications.freedesktop.org/mpris/latest/

**音源**
- go-music-dl：https://github.com/guohuiyuan/go-music-dl
- Meting-Agent（音乐虾）：https://github.com/ELDment/Meting-Agent
- NeteaseCloudMusicApi（原仓）：https://github.com/Binaryify/NeteaseCloudMusicApi
- api-enhanced：https://github.com/neteasecloudmusicapienhanced/api-enhanced
- NeteaseMusic-API（接力仓）：https://github.com/xgxdmx/NeteaseMusic-API
- UnblockNeteaseMusic/server：https://github.com/UnblockNeteaseMusic/server · 酷我 issue #1299：https://github.com/UnblockNeteaseMusic/server/issues/1299
- yt-dlp B 站 412：https://github.com/yt-dlp/yt-dlp/issues/16571 · https://github.com/yt-dlp/yt-dlp/issues/16584
- LXMusic vs MusicFree：https://zhuanlan.zhihu.com/p/718757633 · 洛雪 2026 音源汇总：https://zhuanlan.zhihu.com/p/2016513313782113612
- Listen 1：https://listen1.github.io/listen1/

**agent 面**
- bilibili-mcp-server（22 工具）：https://github.com/iseenope/bilibili-mcp-server
- bilibili-mcp：https://github.com/adoresever/bilibili-mcp

---

## 14. 怎么重跑这份调研

1. **播放架构**：读各项目的 README + CHANGELOG + `docs/`，按 §6 的五轴填 §11 的表。
   **不要读综述文章** —— 本轮所有二手综述都比一手 README 落后至少一个大版本。
2. **音源**：直接看目标仓库最近 90 天的 issue，尤其是标题里带 412 / 403 / 会员 / 无法播放的。
   **issue 比 README 诚实** —— README 说支持哪些源，issue 说哪些还真的能用。
3. **URL 时效**：解一个 URL，记下时间，隔 1/3/6/12 小时各 `curl -I` 一次。这是 §12.1 和 §12.2
   唯一的补法，成本是一天的挂机。
4. **agent 面**：在 MCP 目录站（glama / lobehub / mcpservers.org）按平台名检索，
   看工具数与工具名 —— **工具名比 star 数更能说明它到底做了什么**。
