# PLAN-ut-restructure —— 拆成「播放器 + 可扩展搜索引擎」

**状态：A 已落地（2026-08-23），下一步 B。** 决定见 `ROADMAP.md` D9 / D10；证据见
`RESEARCH-bilibili-engine.md`。本文件**自带进度**，每项落地即更新，最后一项落地后删除，
契约并入 `SPEC-system.md`。

| 步 | 内容 | 状态 |
|---|---|---|
| A | 核心改名 `shell/yt` → `shell/ut-play`（零代码搬移） | ☑ 2026-08-23 |
| B | 从 `ut-play` 里把 YouTube 引擎切成 `yt-search` / `yt-resolve` | ☐ 下一步 |
| C | `bili-search` / `bili-resolve` | ☐ |
| D | `ut-tui` 引擎注册表 + 切源键 | ☐ |
| E | 文档同步 + `verify-suite` 四阶段（含 phase 4 真发声） | ☐ |

---

## 1. 目标与不变量

**目标**：让「与音源无关的东西」和「与音源有关的东西」住在不同文件里，从而加一个音源 = 加一对脚本。

**四条不变量**（任何一步都不许破）：

1. **契约本体不变** —— envelope schema、player record、退出码表（0 ok / 1 usage / 2+ 传递 / 4 未生效）、
   生命周期语义（launch → status → stop，幂等 stop，歧义即 4）。这是 D3 冻结的东西。
2. **`-j` 永远单行。**
3. **bash 3.2 地板**不变；**不新增运行时依赖**（`bili-*` 只用已有的 curl / jq / openssl）。
4. **`players/` 只有一个所有者**（`ut-play`），`--status` / `--stop --all` 必须看见所有引擎起的播放器。

---

## 2. 命令与 argv

```
ut-play  [--engine NAME] [-f MODE] [-d] [--volume N] [-S SORT] [-j|-J] -- <id|url>
ut-play  --status [--id ID] [-j]
ut-play  --stop  (--id ID | --all) [-j]
ut-play  --set-volume N (--id ID) [-j]

<engine>-search   [-n N] [-m MIN] [-M MAX] [-s SORT] [-l|-j|-J] -- <query>
<engine>-resolve  [-f MODE] [-S SORT] [-j|-J] -- <id|url>

ut-tui   [引擎选择键] [其余沿用今天的 yt-tui]
```

**引擎选择（v1，刻意最小）**：`ut-play` 用 `--engine NAME`；缺省取环境变量
`UT_DEFAULT_ENGINE`（默认 `youtube`，**保持今天 `yt-play <url>` 的行为逐字不变**）。
**v1 不做 URL 嗅探** —— `ut-tui` 永远知道引擎（是它搜的），agent 播裸 URL 时显式给 `--engine`。
嗅探（引擎声明自己的 URL 模式，`ut-play` 按注册表匹配）列为 v2，等真有第三个引擎再说。

**`--id` 不与媒体 id 冲突**：`--id` 始终是**播放器 id**（生命周期动词用）；媒体 id 走位置参数。

---

## 3. 引擎契约（新增的那一半）

一个引擎 = 同名前缀的两个可执行文件，二者都必须实现 `--version` 与 `-j`。

### 3.1 `<engine>-search -j`

沿用今天的 search envelope，**加两个字段**：

```json
{"status":"ok","engine":"bilibili","query":"周杰伦","count":10,
 "results":[{"id":"BV1FPjy6TEiE","title":"…","uploader":"…","duration":13348,
             "view_count":10697444,"url":"https://www.bilibili.com/video/BV1FPjy6TEiE"}]}
```

- `engine`：引擎名，`ut-play` 用它决定回调谁。
- `results[].id`：**引擎内唯一**的媒体标识，`<engine>-resolve` 的输入。
- 字段缺失用 `null`，不省略键 —— 渲染层据此决定画不画那一列（B 站有 `view_count` 无精确秒数的情况）。

### 3.2 `<engine>-resolve -j`（新契约）

```json
{"status":"ok","engine":"bilibili","id":"BV1FPjy6TEiE",
 "url":"https://www.bilibili.com/video/BV1FPjy6TEiE",
 "title":"…","duration":13348,
 "mode":"audio","format":"ba/b",
 "stream_url":"https://upos-sz-…",
 "http_headers":{"Referer":"https://www.bilibili.com/"}}
```

- **`http_headers` 是必需键**，可为空对象。这是本次重切顺带关闭的契约漏洞：
  今天 `--get-url` 只吐裸 URL，B 站实测无 Referer 403 / 有 206。
- `stream_url` 为单值（音频模式）；video 模式若分离音视频，用 `stream_urls: []` 并保留 `http_headers` 同级。
- 失败时 `status:"error"` + `reason`（沿用现有 reason 枚举，**不新增成员**）。

### 3.3 `ut-play` 怎么用它

```
ut-play --engine bilibili -d -- BV1FPjy6TEiE
   └─ exec bili-resolve -j -f audio -- BV1FPjy6TEiE
   └─ mpv "$stream_url" --http-header-fields=<从 http_headers 拼> --input-ipc-server=…
```

**`ut-play` 不再传 `--ytdl-format` 给 mpv** —— 它拿到的已经是直链，所以格式选择上移到引擎里
（`-f MODE` 由 `ut-play` 透传给 `<engine>-resolve`）。这同时消掉了 `SPEC-system.md` §6.1
说的「site 7 不是我们的」那个不对称：**从此只有一次抽取，且它由我们发起。**

> **`ytdl_hook` 从此不再参与 —— 这带走三件它免费提供的事，B 步必须逐件接手：**
>
> | ytdl_hook 原来做的 | 谁接手 | 风险 |
> |---|---|---|
> | 把 `http_headers` 落成 mpv 选项（`set_http_headers`） | `ut-play` 自己拼 `--http-header-fields` | 低，但拼错只在 B 站这种校 Referer 的站暴露 |
> | **分离音视频合成一条 EDL** | `ut-play`：`stream_urls` 一条 → `mpv <url>`；两条 → `mpv <video> --audio-file=<audio>` | **中** —— uting 有 5 种播放模式，`bv*+ba/b` 会出两条流。纯音频模式不受影响，video/fast/ascii/viz 要逐个验 |
> | 直播 / HLS 清单的再解析 | `<engine>-resolve` | **中** —— 直播行本来就是移植风险清单上的一条（`ROADMAP` §7.5） |
>
> 另外 **PO-token / cookie 403**（`SPEC §8.2`）从播放器移进 `yt-resolve`：那本来就是
> **YouTube 引擎自己的事**，不再污染播放器。**A 步一律不动，全部留到 B 步。**
>
> 若 B 步验下来 video 模式的 EDL 太难，退路是**只让音频模式走 resolve，video 模式暂留
> `--ytdl-format` 老路** —— 两条路并存是难看的，但它是可回退的，且音频是本项目的主用例。

---

## 4. 分步

### A. 核心改名（零代码搬移）☑ 2026-08-23

**原计划是把播放器那一半（约 1000 行）搬出来。开工前核实调用图，发现它在 A 步内就要求
三件额外的事**（详见下面的「核实结果」），于是**反过来切**：核心整体改名，把真正的切
留给 B —— B 搬的是**较小的一半**（引擎侧约 600 行），且终点完全相同。

实际做的：

```
git mv shell/yt shell/ut-play
shell/yt-play   IMPL="$SCRIPT_DIR/yt" → "$SCRIPT_DIR/ut-play"（含定位失败的错误文案）
shell/yt-search 同上
shell/ut-play   自称改名：usage() 抬头、printf 'ut-play %s\n' "$YT_VERSION"
tests/contract.sh          两处（-l 直调核心；四入口版本一致性的 for 循环）
.githooks/pre-push         语法检查列表 + YT_VERSION 读取
.claude/skills/            verify-suite · audit-conformance（含 fn_graph.py）· capture-pane
CLAUDE.md · SPEC §0/§17 · ROADMAP 文件表
```

`shell/yt-tui` **无需改动**：它只认 `yt-search` / `yt-play` 两个壳，从不直连核心。
`STATE_DIR="…/yt-cli-$(id -u)"` **刻意不动** —— 改它会让正在跑的播放器失联，留到 D/E。

验证（全绿）：`bash -n` 四脚本 · 四入口 `--version` 一致 · `tests/contract.sh` **46/46** ·
`YT_TEST_LIFECYCLE=1 tests/lifecycle.sh` **13/13**，零孤儿 mpv。

#### 核实结果 —— 原 A 清单与真实调用图的四处出入（现在全部转为 B 的输入）

1. **两个 yt-dlp 函数被播放器侧调用**，原计划把它们排在 B：
   `detach_play → detach_title_updater`（`yt-dlp --print`）；
   `play_url_with_probe → probe_media_fetchable`（`yt-dlp -g`）。
   B 切走它们时，`detach_play` 与 `play_url_with_probe` 必须改为回调引擎，
   而不是直接调函数。
2. **原清单漏了 5 个必需符号**：`have_probe_tools` · `play_url_with_probe`
   （被 `play_url_directly` 和 `play_url_json` 调）· `normalize_playback_mode` ·
   `mpv_supports_vo` · `set_action`。
3. **三个函数切完之后两边都要用** —— 这是 B 必须先决定共享库形态的原因：

   | 函数 | 播放器侧调用点 | 引擎侧调用点 |
   |---|---|---|
   | `format_for_mode` | `play_url_with_probe` · `detach_play` | `resolve_stream_url` |
   | `ensure_state_dir` | `play_url_json` · `detach_play` | `resolve_transcript` · `fetch_results` |
   | `classify_playback_error` | `play_url_json` · `detached_epitaph` | `transcript_fail` |

   外加整个 prelude：`JQ_PRELUDE` · `STATE_DIR`/`PLAYERS_DIR` · `YT_COOKIE_ARGS` ·
   `die`/`validate_enum`/`require_deps` · **`YT_VERSION`（CLAUDE.md 硬规则「只声明一次」）**。
4. **`yt-play` 不能变符号链接**（原 §4 A 与 §6 都这么写，是错的）。它是门禁层：拒 `-n`/`-s`/
   裸 query、校 YouTube URL 形状、`--transcript` 与播放标志的冲突检查。做成符号链接直接打掉
   `tests/contract.sh:89-94,107-116`。符号链接最早只能在 D 步、`ut-play` 自己长出门禁之后。

#### 顺带修的一处 rig 竞态

`tests/lifecycle.sh` 的 `--set-volume --id` 紧跟在两次 `-d` 之后断言 exit 0，**但没有等
mpv 的 IPC socket 出现**。socket 未起时 `ipc_failed`/退出码 4 是**正确行为**，所以这条以前
是靠网络够快侥幸绿的（本次实测 mpv 起来要 4.5–15 s，于是红了）。已加 `wait_for_sock`
有界轮询（不是定长 sleep）。**这不是改名造成的回归** —— 手工复现确认：不等 → 4，等到
socket → 0 且 volume 40。

### B. `yt-search` / `yt-resolve`

从 `shell/ut-play` 里把引擎侧（`fetch_results` · `print_list` · `emit_search_json` ·
`resolve_stream_url` · `resolve_info` · `resolve_transcript` · `transcript_fail` ·
`probe_media_fetchable` · `detach_title_updater`，约 600 行）切成两个引擎动词。
`ut-play` 改为回调 `yt-resolve`，不再传 `--ytdl-format`。

**B 开工前要先定的一件事**：上面「核实结果」第 3 条的共享面住哪。候选是新建
`shell/ut-common`，两边 `source`（它同时满足 `YT_VERSION` 只声明一次的硬规则）；
另一条路是共享面全部下沉进 `ut-play`，引擎侧改为**只经 argv/envelope 通信、不共享函数**。
后者更干净但要重写 `resolve_transcript` 的错误分类路径。

**此处才是行为可能变的地方**（抽取从 mpv 内部移到我们这边）。逐条比对：PO-token 探测、
cookie 回退、直播行、format-sort、`--info` / `--transcript` 的归属（它们跟着引擎走）。

### C. `bili-search` / `bili-resolve`

- `bili-search`：`curl` 打 `/x/web-interface/search/type`（`buvid3` + UA + Referer）→ jq 整形。
  必做的三件数据清洗：剥 `<em class="keyword">`；`"MM:SS"`（分钟无上限）转秒；`play` → `view_count`。
- `bili-resolve`：WBI 签名（`openssl dgst -md5` + `sort` + `jq -rR @uri`）→ `/x/player/wbi/playurl`
  → DASH 里挑音频 → 输出 `stream_url` + `http_headers:{Referer}`。
- **WBI 必须有固定向量单测**（纯函数、无网络，`bilibili-tui/src/api/wbi.rs` 有两条官方样例可抄）。
  这是 rigs-only 规则的合法例外：它测的不是渲染或协议，是确定性变换。
- 风控：HTTP 412 / `code:-352` 归入 `network`（可重试），**不新增 reason 枚举成员**。

### D. `ut-tui`

引擎注册表（名字 → 命令前缀）+ 切源键；其余渲染逻辑不动。`ytt` 留符号链接过渡。

### E. 文档 + 全量验证

`SPEC-system.md`：§4 命令拓扑、§5 seam 表、**§6.1 调用栈图（形状会变：mpv 不再自己调 yt-dlp）**、
§12 命令规格、§13 门禁模型、§14 数据契约（加 resolve envelope）、§17 函数图、§27 验证矩阵。
README + `usage()`。然后 `verify-suite` 四阶段，**phase 4 必须真放一次 B 站音频**。

---

## 5. 验证矩阵（新增项）

| 检查 | 抓什么 production 失败 |
|---|---|
| 引擎契约一致性：对每个 `<engine>`，`-search -j` 与 `-resolve -j` 的 envelope 键集与类型 | 新引擎悄悄改了字段名 / 少了 `http_headers`，调用方对不上 |
| `ut-play --engine X` 对未注册引擎 → 退出码 1 + 可读错误 | 拼错引擎名时退出码落进 2+，agent 误判为工具失败 |
| WBI 固定向量单测 | 签名算法改错，只在真实请求时才发现 |
| B 站直链 + `--http-header-fields` 能被 mpv 打开 | Referer 拼装写错 → 403，但只在 B 站上暴露 |
| `-d` 起 YouTube 与 B 站各一个 → `--status` 两个都在 → `--stop --all` 清空 | 生命周期被引擎污染 / `players/` 出现第二个所有者 |

---

## 6. 兼容与迁移

`yt-play` → `ut-play`、`ytt` → `ut-tui` 留符号链接，直到 D 步结束
（**但不是在 A/B**：`yt-play` 是门禁层，见 §4 A 核实结果第 4 条）。`yt-search` **名字不变**
（它本来就该说明自己是 YouTube）。`--get-url` 保留为 `yt-resolve` 的别名一个版本周期，
`usage()` 标注弃用。

---

## 7. 已知风险

- ~~**A 步搬移量大**（约 1000 行）~~ —— 反向切之后这条消失了：A 搬 0 行，B 搬约 600 行。
- **B 步是行为可能真变的一步**：抽取责任从 mpv 转到我们。除 PO-token / cookie 回退外，
  **分离音视频的 EDL 合成与直播/HLS 再解析**是 ytdl_hook 免费给、现在要自己写的两件（见 §3.3 的表）。
  退路：video 模式暂留老路。
- **C 步的 WBI 与风控没有上游文档可跟**（`bilibili-API-collect` 2026-01 已归档）。
- **B 站音质门槛**依赖 `SESSDATA`，走现有 cookie 通道；**任何 cookie 内容都不得落进 `players/`**。
