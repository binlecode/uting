# RESEARCH-tui-player-landscape-2026 —— 通用 TUI 播放器领域复查

2026-08-22 写。**待决状态**：这份是探索，不是决定。四段流水线里的第一段（`CLAUDE.md` 那张表把它写作
`DESIGN-`，本仓改用 `RESEARCH-` 前缀，表待同步），它的终结方式是
**把 §7 蒸馏进 `ROADMAP.md`，然后删掉本文件**。在那之前，`ROADMAP.md` §0 / §4 与本文冲突的地方，
以本文的实测为准。

## 0. 为什么复查

`ROADMAP.md` §0 的第一条 non-goal —— **"不做通用 TUI 音乐播放器"** —— 整条压在 §4 的一句判断上：

> 那一层（本地/MPD：cmus、ncmpcpp、rmpc、musikcube、kew、termusic）已经饱和且活跃，见 §4 的实测数据。

这个 non-goal 的**结论**大概率是对的，但它的**论据**有两个洞，都足以让它在别人问起时站不住：

1. §4 只测了 **stars + 最后 push 日期**。push 日期区分不了"在维护"和"在生长"——一个每半年收一个
   拼写修正 PR 的项目，和一个半年 100+ commit 的项目，在那张表里长得一模一样。
2. §4 的第三条结论 —— **"没有任何一个是 agent 可驱动的"** —— 是整个定位的支点（差异化=契约而非渲染）。
   它当时只按"是不是人机 TUI"来判断，没有真去查各项目的 IPC / CLI / MCP 面。

本轮把这两个洞补上，并按用户要求把**国内**这一格单独测一遍（§4 原表里一个中文项目都没有，而
`darknessomi/musicbox` 有 9830★ —— 比表里除 spotify-tui 外的任何一个都高）。

## 1. 方法与口径

- **来源**：GitHub REST API 实测（`gh api`，2026-08-22 采集），配合对关键项目 README / CHANGELOG /
  man page 的定向抓取。采集脚本与原始 TSV 在 `tmp/`（不入库）。
- **候选集**：`search/repositories` 九组关键词（英文六组 + 中文三组）取 stars 前列，去重后并入 §4 原表
  的全部条目，再补上抓取过程中出现的新名字。**不声称穷尽** —— 长尾里 0–20★ 的新项目每周都在冒。
- **四个指标**，缺一不可：

  | 指标 | 回答什么 | 陷阱 |
  |---|---|---|
  | `stargazers_count` | 存量认知度 | 与"能不能用"无关；死项目的 star 不会掉 |
  | `pushed_at` | 还有没有人碰 | **区分不了维护与生长** —— §4 只有这一个 |
  | 近 180 天 commit 数 | 生长速率 | API 单页上限 100，故本文 `100+` 表示"≥100，未再翻页" |
  | `created_at` → **★/月** | 是不是新生代、增速多少 | 早期爆红会虚高；只当量级读 |

- **口径**：所有 star / commit 数均为 2026-08-22 快照。第三方对比文档不可信 —— `pdfrg/must` 的
  `docs/COMPARISON.md` 把 `spotify-tui` 标成 "Active"，而它 **2024-04 起再无提交**。本文只用自测数。

---

## 2. 全景：按音源分层，按活跃度分档

### 2.1 本地 / MPD 层（§0 non-goal 直接指向的那一层）

| ★ | 语言 | 最后 push | 近 180d commit | 最新 release | 项目 | 建仓 |
|---:|---|---|---:|---|---|---|
| 6222 | C | 2026-08 | **7** | v2.12.0 (2024-10) | `cmus/cmus` | 2012-12 |
| 4826 | C++ | 2026-03 | **1** | 3.0.5 (2025-09) | `clangen/musikcube` | 2015-03 |
| 3403 | Go | 2026-08 | **100+** | v1.63.2 (2026-08) | `bjarneo/cliamp` | **2026-02** |
| 3245 | Rust | 2026-08 | **100+** | v0.11.0 (2026-02) | `mierak/rmpc` | 2024-03 |
| 2986 | C | 2026-08 | **100+** | v4.2.7 (2026-07) | `ravachol/kew` | 2023-05 |
| 2472 | C++ | 2026-06 | **2** | — | `ncmpcpp/ncmpcpp` | 2012-08 |
| 2178 | Rust | 2026-08 | **100+** | v0.13.2 (2026-05) | `tramhao/termusic` | 2021-06 |
| 370 | Rust | 2026-08 | 73 | v0.3.4 (2026-08) | `Jaxx497/NoctaVox` | 2025-05 |
| 211 | Go | 2026-06 | — | — | `raziman18/gomu` | 2020-06 |
| 100 | Rust | 2024-05 | 死 | — | `figsoda/mmtc` | 2020-10 |
| 66 | Rust | 2026-08 | — | — | `JustRoccat/rs-pug` | **2026-04** |
| 37 | Rust | 2026-08 | — | — | `hikikones/trollstov` | 2026-01 |
| 22 | Rust | 2026-08 | — | — | `amsdias/Keet` | 2026-03 |
| 3 | Go | 2026-08 | — | — | `pdfrg/must` | 2026-05 |

### 2.2 流媒体层

| ★ | 语言 | 最后 push | 近 180d | 项目 | 音源 |
|---:|---|---|---:|---|---|
| 19314 | Rust | **2024-04（死）** | 0 | `Rigellute/spotify-tui` | Spotify |
| 7107 | Rust | 2026-07 | 34 | `aome510/spotify-player` | Spotify |
| 6733 | Rust | 2026-08 | 39 | `hrkfdn/ncspot` | Spotify |
| 1733 | C | 2026-08 | — | `tizonia/tizonia-openmax-il` | 多云端 |
| **1247** | Rust | 2026-08 | **100+** | `LargeModGames/spotatui` | Spotify+YT+本地+Subsonic+电台 |
| 574 | Rust | 2026-08 | **100+** | `dhonus/jellyfin-tui` | Jellyfin |
| 419 | Go | 2026-06 | — | `dubeyKartikay/lazyspotify` | Spotify |
| 284 | Rust | 2026-07 | 2 | `qxb3/fum` | MPRIS（不放音，只控） |
| 260 | Go | 2026-07 | — | `MattiaPun/SubTUI` | Subsonic |
| 257 | Rust | 2026-08 | — | `SofusA/qobine` | Qobuz |
| 203 | Swift | 2026-01 | — | `jayadamsmorgan/Yatoro` | Apple Music |
| 187 | Go | 2026-03 | — | `DECE2183/yamusic-tui` | Yandex |
| 168 | Go | 2026-06 | — | `llehouerou/waves` | Soulseek |
| 1 | Rust | 2026-08 | — | `planetaryescape/spotuify` | Spotify（见 §4.3） |

### 2.3 YouTube 格 —— §4 说"最弱、最缺维护"的那一格

| ★ | 语言 | 最后 push | 近 180d | 项目 | 形态 |
|---:|---|---|---:|---|---|
| 8782 | Python | 2026-03 | **4** | `mps-youtube/yewtube` | 2014 项目续命 |
| 4144 | Shell | **2024-09（死）** | 0 | `pystardust/ytfzf` | POSIX sh + fzf + mpv |
| **1642** | **Shell** | **2026-08** | **100+** | **`Benexl/yt-x`** | **POSIX sh + fzf + jq + curl + mpv** |
| 1141 | Rust | 2026-05 | — | `Siriusmart/youtube-tui` | 自绘 |
| 773 | Rust | 2025-03（停滞） | 0 | `sudipghimire533/ytui-music` | 自绘 |
| 691 | Rust | 2026-05 | — | `ccgauche/ytermusic` | 自绘 |
| 484 | TS | 2026-08 | — | `baairon/soundcli` | 下载器为主 |
| 479 | Python | 2026-08 | **100+** | `peternaame-boop/ytm-player` | YT Music TUI |
| 404 | TS | 2026-08 | **100+** | `involvex/youtube-music-cli` | YT Music TUI |
| 251 | C | 2026-06 | — | `lalo-space/shellbeats` | CLI |
| 236 | Rust | 2026-04 | — | `13unk0wn/Feather` | YT Music TUI |
| 198 | Rust | 2026-08 | 24 | `nick42d/youtui` | **TUI + 独立 API crate** |

### 2.4 国内格（§4 原表完全缺失）

| ★ | 语言 | 最后 push | 近 180d | 项目 | 音源 | 备注 |
|---:|---|---|---:|---|---|---|
| **9830** | Python | 2026-07 | **53** | `darknessomi/musicbox` | 网易云 | 2014 建仓，**仍在真实开发**，非僵尸 |
| **2513** | Go | 2026-08 | **100+** | `go-musicfox/go-musicfox` | 网易云 | 国内旗舰。UnblockNeteaseMusic / 多音质 / lastfm / MPRIS / DLNA / macOS 桌面歌词 / brew·scoop·AUR·Copr·Flatpak 全渠道 |
| 825 | — | 2015-11 | 死 | `bluetomlee/NetEase-MusicBox` | 网易云 | 上一代 |
| 427 | Rust | **2022-03（死）** | 0 | `betta-cyber/netease-music-tui` | 网易云 | |
| 209 | Rust | 2026-08 | 37 | `MareDevi/bilibili-tui` | **B站** | 2026-01 建仓 |
| 140 | Rust | 2026-08 | **100+** | `professor-lee/CNMPlayer` | 网易云 | **2026-03 建仓**，带频谱可视化 |
| 113 | Python | 2026-06 | — | `jaychempan/coding-with-beat` | Apple Music / 本地 / QQ音乐 | **AI 终端专用**，见 §4.4 |
| 12 | Go | 2026-04 | — | `Davied-H/ncm-cli` | 网易云 | |
| 7 | Rust | 2026-08 | — | `KayneWang/maboroshi` | **YouTube** | 中文说明的 YT TUI |
| 5 | Python | 2026-01 | — | `xieerfan/BiliBiliMusicPlayer` | **B站** | |
| 1 | Go | 2026-08 | — | `bighu630/music-tui` | **YouTube** | Go TUI + mpv 驱动 |
| 0 | Python | 2026-07 | — | `Zwl20085/yueting` 悦听 | **YouTube / B站** | 中文向 |

**国内格的两条形态判断**（观察，非实测）：

1. **头部是"网易云 + 逆向 API"这一条路**，且只有两个玩家有规模（musicbox 9830★ / go-musicfox 2513★）。
   这条路的成本不在渲染，在**持续对抗接口变更**（`UnblockNeteaseMusic` 的存在本身就是证据）。
2. **2026 建仓的中文项目在换音源**：`maboroshi`、`bighu630/music-tui`、`yueting`、`BiliBiliMusicPlayer`
   一律走 **YouTube / B站 + yt-dlp/mpv**，不再碰网易云。也就是说 —— **国内新生代与 uting 走在同一条
   技术路线上**，只是都还在 0–10★ 的量级。这是本轮对 uting 最直接的一条竞争情报。

---

## 3. 发现一：那一层不是"饱和且活跃"，是**饱和且冻结 + 新生代狂奔**

同一张表里两个分布，`pushed_at` 把它们抹平了：

| 队列 | 近 180 天 commit |
|---|---:|
| `musikcube` | **1** |
| `ncmpcpp` | **2** |
| `yewtube` | **4** |
| `cmus` | **7** |
| `qxb3/fum` | 2 |
| — | |
| `cliamp` / `rmpc` / `kew` / `termusic` / `spotatui` / `jellyfin-tui` / `go-musicfox` / `CNMPlayer` / `yt-x` / `ytm-player` / `youtube-music-cli` | **各 100+** |

`cmus`（6222★）近半年 7 个提交、最新 release 停在 2024-10；`musikcube`（4826★）近半年 1 个提交。
**经典四件套在维护模式，不在生长模式。**

增速侧（★/月，按建仓至今折算，只读量级）：

| 项目 | 建仓 | ★ | ★/月 |
|---|---|---:|---:|
| `bjarneo/cliamp` | 2026-02 | 3403 | **≈567** |
| `baairon/soundcli` | 2026-05 | 484 | ≈161 |
| `LargeModGames/spotatui` | 2025-11 | 1247 | ≈139 |
| `mierak/rmpc` | 2024-03 | 3245 | ≈112 |
| `dubeyKartikay/lazyspotify` | 2026-03 | 419 | ≈84 |
| `peternaame-boop/ytm-player` | 2026-02 | 479 | ≈80 |
| `ravachol/kew` | 2023-05 | 2986 | ≈77 |
| `Benexl/yt-x` | 2024-09 | 1642 | ≈71 |
| `professor-lee/CNMPlayer` | 2026-03 | 140 | ≈28 |

**对 §0 的影响：non-goal 的结论不变，论据要换。**
"不做通用播放器"现在的正确理由不是"那层没人动了所以饱和"，而是 **"那层每月有一个新项目以 500★/月
的速度起来（`cliamp` 六个月 3403★），拿 2.8k 行 bash 去和 Go/Rust 新生代抢渲染，是把自己放到最不
可能赢的赛道上"**。这个理由比原来的强，因为它不依赖"对手不动"这个会过期的前提。

---

## 4. 发现二（重要）：**"没有任何一个是 agent 可驱动的"已被证伪**

`ROADMAP.md` §4 结论 3 的原文：

> **没有任何一个是 agent 可驱动的。** 全是人机 TUI：没有稳定机读契约、没有退出码分类、没有"脱离终端后
> 仍可查/停/调音量"的生命周期 API。

按本轮实测，这句话**当时就不完全成立，现在明确不成立**。分四档：

### 4.1 一直就有机读面的（这条最该早发现）

| 项目 | 机读面 | 形态 |
|---|---|---|
| **MPD 全家**（`ncmpcpp` / `rmpc` / `mmtc` / `gomp`） | **MPD 协议本身** | TUI 只是客户端。协议二十余年稳定、有 `mpc` 这个现成 CLI —— 这一格**天生**就是 agent 可驱动的 |
| `cmus` | `cmus-remote -Q`（= `-C status`） | 行式 key/value：`status` / `file` / `artist` / `duration` / `position`。1998 年就有的设计 |
| `hrkfdn/ncspot` | **Unix domain socket，推 JSON** | `ncspot info` 给出 socket 路径，`nc -U <sock>` 收发；**每次播放状态变化都推一条 JSON**（`mode` + `playable{id,uri,title,duration,artists,album,cover_url}`）。文档甚至写明了 netcat 变体差异，建议 `nc -W 1` |

> `ncspot` 这条尤其刺眼：**socket + nc + JSON**，和 uting 的 mpv IPC 客户端路径几乎同构，连
> "stock netcat 不肯关连接"这个坑都踩过并写进文档了（对照 `SPEC-system.md` §26）。

### 4.2 做成了"守护进程 + CLI 动词"的（uting 的架构不是孤例）

| 项目 | 形态 |
|---|---|
| `aome510/spotify-player` | `-d/--daemon` 后台播放；CLI 子命令 `get` / `playback` / `search` / `connect` / `like` / `playlist`，经 `client_port`（默认 8080）打到运行中的实例；**`search` 明确为脚本设计，出 JSON 给 jq** |
| `tramhao/termusic` | 拆成 `termusic-server` + `termusic` 客户端，**gRPC** 通信 |

**这直接影响 `ROADMAP.md` §7 的差异化叙事**："脱离终端的播放器生命周期 + CLI 动词 + JSON" 不是 uting
独有的形状；`spotify-player` 用不同音源做了同一件事，且早于本项目。

### 4.3 2026 年直接长出 MCP 面的（这是本轮最大的变化）

**`LargeModGames/spotatui`**（1247★，2025-11 建仓，近半年 100+ commit，v0.41.0 / 2026-08-10）——
CHANGELOG 原文可查，摘要：

- **MCP server**（`--features mcp-server`）：把播放器与收听历史暴露成 MCP tools，"Claude Code、Codex、
  Gemini CLI 或任何 MCP 客户端都能当 DJ"。**默认关闭**，`behavior.mcp_enabled: true` 开启，socket
  **只绑 loopback 且带 token**（`~/.config/spotatui/mcp.json`）。
- 写给 **protocol revision `2026-07-28`**（该版移除了 `initialize` 握手、令 MCP 无状态），并**双时代
  兼容** —— 仍应答 `initialize`，否则今天在跑的客户端会直接失败。
- 工具设计上有真东西：`search_tracks` 给每条结果打 `[owned]` / `[new]`，让推荐模型在**选择的那一刻**
  就知道你有没有，省一次往返；`queue_tracks` 有 `exclude_owned: true`。两者都默认关。
- **Agent plugin**：`agent-plugin/` 同时以 **Agent Plugins 1.0**（`agent-plugins.org`，厂商中立）和
  Claude Code 插件格式发布，`/plugin marketplace add LargeModGames/spotatui` 一键装，附一个
  `spotatui-dj` skill 教 agent 怎么 DJ。
- **应用内 AI DJ**（`--features ai-dj`）：**复用 MCP server 那张 tool table 本身而非拷贝**，所以两个入口
  永不漂移。后端可插：本机已装的 agent CLI（`claude` / `codex` / `agy` / `copilot` / `opencode`，无需
  API key）、Anthropic Messages API、或任意 OpenAI 兼容端点含 Ollama / LM Studio。
- 工程纪律也在同一水位：启动提示改走 stderr，理由写的是"**MCP 规范要求 stdout 只能有协议消息**"。

**`planetaryescape/spotuify`**（1★，2026-05 建仓）—— star 数为零，但**架构是 uting 论点的极端版**，
值得单独记：

> "One daemon owns playback; the TUI, CLI, MCP server, and menubar are all clients."

58 个 CLI 命令，输出格式 `table` / `json` / `jsonl` / `csv` / `ids`；**41 个 MCP tools**；带
`ops log` / `ops undo` 的可撤销操作日志；`--dry-run` / `--yes`；还有一个 `doctor`。
**"if the TUI can do it, the CLI can."**

### 4.4 从 MCP 那一侧反向填坑的（不是 TUI，但抢的是同一块地）

| 项目 | 形态 |
|---|---|
| `arijit-gogoi/mpv-mcp-server` | **MCP server 直接驱动 mpv + yt-dlp**：浏览本地库、控制播放、YouTube 串流、下载。**这就是 uting 的 agent 面，用 Node 实现，没有 TUI。**（1★，2026-04） |
| `kevinwatt/yt-dlp-mcp`（273★） / `Gtvar/yt-dlp-mcp` / `yorickchan/mcp_youtube_dlp` | yt-dlp 的 MCP 封装：下载、元数据、**字幕/transcript** |
| `jaychempan/coding-with-beat`（113★，国内） | **AI 编码终端专用 DJ**：38 个 MCP tools（HTTP `127.0.0.1:8765/mcp`）+ 一个 `/cwb` skill 做意图路由 + **hooks/statusline 监听编码事件**（commit 庆祝、测试失败慌张）。音源 Apple Music / 本地 `afplay` / QQ音乐（仅 30s 试听） |

`yt-dlp-mcp` 那一条与 2026-08-22 刚落地的 `--transcript` **正面重叠**：字幕取回这件事，MCP 生态里已有
273★ 的现成封装。

### 4.5 这一节对 uting 的净结论

**站得住的收窄版命题**（可以写进 ROADMAP，且经得起查）：

> 在 **YouTube 这一格**里，仍然没有一个项目提供 **单行 JSON envelope + 退出码分类 + 脱离终端的
> 播放器生命周期（launch → status → stop，幂等，歧义即 4）** 这一整套契约。`yt-x` 是 shell + fzf，
> 无机读契约；`youtui` 有独立 API crate 但那是给 Rust 调用方的库，不是 CLI 契约；其余全是纯 TUI。

**必须撤回的命题**：

> ~~"没有任何一个是 agent 可驱动的"~~ —— MPD 层天生可驱动，`cmus` / `ncspot` / `spotify-player` /
> `termusic` 各有机读面，`spotatui` / `spotuify` 已经在出 MCP，`mpv-mcp-server` 从另一侧直接做了
> mpv+yt-dlp 的 agent 面。

**顺带松动一条 non-goal**：`ROADMAP.md` §0 把 MCP 列为暂定 non-goal（由 §9 触发条件决定）。
§4.3 的事实是 —— **MCP 已经从"要不要做"变成"同格竞争者做了、并且做出了可抄的工程细节"**：
默认关闭 + loopback + token、`2026-07-28` 双时代兼容、stdout 只跑协议、tool table 单一来源。
这不构成"必须做"，但它构成 §9 触发条件的一次实质性变化，应当记进 ROADMAP。

---

## 5. 发现三：YouTube 那一格已经**有活的旗舰**了

§4 结论 2 说"最像本项目的 `ytfzf` 2024-09 后没动过"。`ytfzf` 确实死了，但**它的位置被接管了**：

**`Benexl/yt-x`** —— 1642★，POSIX shell，2024-09 建仓，2026-08 仍在推，近半年 100+ commit，
v0.8.6（2026-06）。依赖：**yt-dlp + fzf + jq + curl + POSIX sh**（Nerd Font 出图标）。

它与 uting 的技术栈重合度极高，且功能面走得更远：

- 搜视频/播放列表/频道/shorts/电影，行内过滤语法（`:4k` / `:today` / `:hd`）
- **搜索历史 + bang 召回**（`!1` / `!2`）
- 个人 YouTube feeds：Home / Trending / Watch Later / Liked / History / Clips（走浏览器 cookie）
- 分页（默认 30/页）、下载（含整播放列表、抽 MP3）、本地"已存视频"与自建播放列表
- **扩展系统**：`.theme` / `.lang` / `.ui` / `.site` —— 被 source 的 shell 脚本，可覆盖函数、加菜单项
- 多启动器：fzf / rofi，预览窗放元数据与缩略图（chafa / icat / imgcat）
- `--shell` 有状态子 shell（预置 title/url/channel 环境变量）、`--playlist-skip` / `--media-exit` /
  `--cmd-exit` 供非交互脚本用
- 本地 JSON 存订阅/历史/播放列表 —— 但**那是自己的状态文件，不是对外契约**

**对 uting 的三点意味**：

1. "YouTube 格无人维护"这句要改成 **"YouTube 格有一个 1.6k★ 的活跃 shell 旗舰，但它没有机读契约"**。
   差异化叙事从"这格是空的"改成"这格的人机面已被占，机器面还空着" —— 后者依然成立，且更精确。
2. `yt-x` 的**扩展系统**（source shell 脚本、覆盖函数）是 uting **明确不该抄**的东西：它把 shell 的
   动态作用域当插件 ABI，与本仓"契约是安全边界"的取向正相反。
3. 它同时证明了一件对 §5"发布 shell 版要付的账"有利的事：**一个 POSIX shell + 四依赖的项目，在 2026 年
   照样能收 1.6k★**。§5 那笔账（依赖、终端动物园、issue 九成是环境问题）依然要付，但"shell 项目在今天
   没人要"不成立。

---

## 6. 2026 年这一层的 table stakes（观察）

不是给 uting 的 TODO —— 恰恰相反，这一节的用途是**说明进那一层要付什么**，从而支撑 §0 的 non-goal：

| 能力 | 谁在做 | 备注 |
|---|---|---|
| **终端图形协议封面**（Kitty / Sixel / iTerm2 + 半块回退） | `rmpc`（卖点即此）、`kew`（Chafa 出 Sixel）、`jellyfin-tui`、`sonic-tui`、`Keet`、`lyrtui`、`spotuify`、`must` | 2024 是加分项，2026 是**默认项** |
| **同步歌词 + LRCLIB**（含卡拉OK 高亮、偏移调整） | `Keet`、`sonic-tui`、`spotuify`、`ytm-player`、`go-musicfox`（macOS 桌面歌词 + YRC） | 同上 |
| **频谱可视化 / 参数 EQ** | `cliamp`（10 段参数 EQ）、`Keet`、`CNMPlayer`、`rs-pug`（10 段 EQ） | |
| **Lua 插件 API** | `spotatui`（已到 **v6**：cover_art widget、row/column 嵌套布局、`http_get`/`json_decode`、`spotatui plugin add/list/remove/update` + `plugins.lock`）、`rs-pug` | 插件生态是新生代的护城河 |
| **多音源聚合** | `cliamp`（15+ 后端，含 **B站、网易云、小宇宙**）、`spotatui`（5 源）、`termusic`（含 **NetEase / Migu / KuGou**） | 值得注意：**国际项目已经在收国内音源** |
| MPRIS / 媒体键 / 系统集成 | 几乎全部 Linux 侧；`go-musicfox` 的 macOS 睡眠暂停/蓝牙响应/菜单栏 | |
| 二进制自更新 | `spotatui update --install` | |
| 分发渠道齐全 | `go-musicfox`：brew / scoop / AUR / Copr / Flatpak | 对照 `ROADMAP.md` D1（shell 版不打包） |

一眼可见：**这一层的竞争已经打到图形协议、DSP 和插件 ABI 上了。** 2.8k 行 bash 3.2 进这个赛道，
要在**别人靠语言与库免费拿到**的地方从零手写 —— 这正是 `ROADMAP.md` §7 发现 1 说的"负债，不是护城河"。

---

## 7. 待蒸馏进 `ROADMAP.md` 的条目（本文件删除前必须搬走）

按 `CLAUDE.md`：RESEARCH- 的终结方式是蒸馏成 future work 再删。以下是建议的具体改动，**未执行**。

| # | 目标位置 | 改动 | 性质 |
|---|---|---|---|
| R1 | §0 第一条 non-goal | 论据从"那层饱和且活跃"改为"那层新生代以 ~500★/月 起量（`cliamp` 6 个月 3403★），且竞争已打到终端图形协议 / 参数 EQ / Lua 插件 ABI —— bash 3.2 在这些点上要手写别人免费拿到的东西"。**结论不变** | 换论据，加固 |
| R2 | §4 结论 1 | 补一列近 180 天 commit 数，并写明"经典层（cmus 7、musikcube 1、ncmpcpp 2）在**维护模式**，生长全在 2024–2026 新生代" | 更正 |
| R3 | §4 结论 2 | `ytfzf` 死了但**位置被 `Benexl/yt-x`（1642★，POSIX sh + fzf + jq + mpv，100+ commit/6mo）接管**。改述为"人机面已被占，机器面仍空" | **更正（重要）** |
| R4 | §4 结论 3 | **撤回**"没有任何一个是 agent 可驱动的"。换成收窄版：YouTube 格内无人提供"单行 JSON envelope + 退出码分类 + 脱离终端生命周期"这一整套。并列出反例清单（MPD 协议 / `cmus-remote -Q` / `ncspot` JSON socket / `spotify-player` daemon+CLI+JSON / `termusic` gRPC / `spotatui` MCP / `spotuify` daemon+41 tools / `mpv-mcp-server`） | **撤回（最重要）** |
| R5 | §4 新增小节 | **国内格**整表（§2.4），含两条形态判断：头部=网易云+逆向 API 两强；2026 建仓的中文项目**集体转向 YouTube/B站 + yt-dlp/mpv**，与 uting 同路线但都在 0–10★ | 新增 |
| R6 | §0 末条 + §9 | MCP 的 non-goal 状态**不变**，但记入触发条件的实质变化：同格竞争者已落地 MCP，且给出了可抄的工程细节（默认关 + loopback + token、`2026-07-28` 双时代兼容、stdout 只跑协议、tool table 与应用内 DJ 单一来源） | 触发条件更新 |
| R7 | §7 发现 3 附近 | 记下"守护进程 + CLI 动词 + JSON"**不是 uting 独有形状**（`spotify-player` 早于本项目，`spotuify` 更彻底）。差异化必须落到**契约的严格度**（退出码分类、幂等 stop、歧义即 4、单行 envelope），而非"有 CLI"这件事本身 | 叙事收紧 |
| R8 | `PLAN-` 候选（不入 ROADMAP） | `--transcript` 与 `kevinwatt/yt-dlp-mcp`（273★）重叠 —— 若将来做 MCP，字幕这一格不是空地，需要说清为什么用 uting 的而不是那个 | 情报，待观察 |
| R9 | §5 | 补一条正面证据：`yt-x` 证明 POSIX shell + 四依赖的项目在 2026 年仍能收 1.6k★。§5 那笔环境账照付，但"shell 项目没人要"不成立 | 补充 |

---

## 8. 本文的已知局限

- **候选集不穷尽**：只覆盖到 GitHub 搜索 stars 前列 + 定向抓取。长尾 0–20★ 的 2026 新项目（`must`、
  `spotuify`、`bighu630/music-tui`、`yueting`…）是顺带撞到的，不是系统扫出来的。
- **近 180 天 commit 数上限 100**：`100+` 无法区分 100 与 1000。要真比生长速率需翻页或用
  `stats/participation`。
- **只测了 GitHub**：Codeberg 上已有 `thelinuxcast/sonic-tui`，GitLab / 国内 Gitee 完全没扫。
  国内格的实际项目数**很可能被低估**。
- **功能面靠 README 自述**：除 `spotatui` 的 CHANGELOG 逐条读过外，其余项目的能力声明未实机验证。
  README 的"支持 X"和真的能用 X 之间有距离。
- **star 不等于用户**：`spotuify`（1★）架构上比多数千星项目更贴近 uting 的论点。本文用它做架构证据，
  不做市场证据。
