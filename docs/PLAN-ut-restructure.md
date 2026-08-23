# PLAN-ut-restructure —— 拆成「播放器 + 可扩展搜索引擎」

**状态：A、B-1、B-2、B-3 已落地（2026-08-23）。B 全部完成，下一步 C。**
决定见 `ROADMAP.md` D9 / D10；证据见 `RESEARCH-bilibili-engine.md`。
本文件**自带进度**，每项落地即更新，最后一项落地后删除，契约并入 `SPEC-system.md`。

| 步 | 内容 | 状态 |
|---|---|---|
| A | 核心改名 `shell/yt` → `shell/ut-play`（零代码搬移） | ☑ 2026-08-23 |
| B-1 | `yt-search` 独立成引擎（搜索与播放路径零耦合，非破坏性） | ☑ 2026-08-23 |
| B-2 | `yt-resolve` 独立 **+** 播放器改走 resolve（耦合的一步，ytdl_hook 退场） | ☑ 2026-08-23 |
| B-3 | 合并与删除：`yt-play` 删除，`ut-play` 上 PATH | ☑ 2026-08-23 |
| C | `bili-search` / `bili-resolve` | ☐ 下一步 |
| D | `ut-tui` 引擎注册表 + 切源键 | ☐ |
| E | 文档同步 + `verify-suite` 四阶段（含 phase 4 真发声） | ☐ |

---

## 1. 目标与不变量

**目标**：让「与音源无关的东西」和「与音源有关的东西」住在不同文件里，从而加一个音源 = 加一对脚本。

**四条不变量**（任何一步都不许破）：

1. **契约本体不变** —— envelope schema、player record、退出码表（0 ok / 1 usage / 2+ 传递 / 4 未生效）、
   生命周期语义（launch → status → stop，幂等 stop，歧义即 4）。这是 D3 冻结的东西。
   （**唯一例外**见 §5 B-3 的「一处契约会真的变」，已论证并接受。）
2. **`-j` 永远单行。**
3. **bash 3.2 地板**不变；**不新增运行时依赖**（`bili-*` 只用已有的 curl / jq / openssl）。
4. **`players/` 只有一个所有者**（`ut-play`），`--status` / `--stop --all` 必须看见所有引擎起的播放器。

---

## 2. 终局形态

### 2.1 文件拓扑：4 文件 2 层 → 4 文件 1 层

```
  今天                                   B 之后
  ────────────────────────────────      ────────────────────────────────────────
  yt-search ─┐                          yt-search    引擎：搜索（壳与实现合一）
  yt-play   ─┼─► ut-play (核心)         yt-resolve   引擎：id → 直链 + header
  yt-tui    ─┘   门禁壳 + 全部逻辑       ut-play      播放器：自带门禁，上 PATH
                                        ut-tui       人机面（D 步改名）
                 VERSION                             一行数据文件，版本唯一声明处
```

`yt-search` 从「壳 + 核心里的搜索」并成一个文件；`ut-play` 吸收 `yt-play` 的门禁。
理由见 §5 B-3。

### 2.2 argv

```
ut-play  [--engine NAME] [-f MODE] [-d] [--volume N] [-j|-J] -- <id|url>
ut-play  --status [--id ID] [-j]
ut-play  --stop  (--id ID | --all) [-j]
ut-play  --set-volume N (--id ID) [-j]

<engine>-search   [-n N] [-m MIN] [-M MAX] [-s SORT] [-l|-j|-J] -- <query>
<engine>-resolve  [-f MODE] [-S SORT] [-j|-J] -- <id|url>
<engine>-resolve  --info [-j|-J] -- <id|url>
<engine>-resolve  --transcript [--sub-lang L] [-j|-J] -- <id|url>

ut-tui   [引擎选择键] [其余沿用今天的 yt-tui]
```

**引擎选择（v1，刻意最小）**：`ut-play` 用 `--engine NAME`；缺省取环境变量
`UT_DEFAULT_ENGINE`（默认 `youtube`，**播放一个 YouTube URL 的行为与今天逐字相同**）。
**v1 不做 URL 嗅探** —— `ut-tui` 永远知道引擎（是它搜的），agent 播裸 URL 时显式给 `--engine`。
嗅探（引擎声明自己的 URL 模式，`ut-play` 按注册表匹配）列为 v2，等真有第三个引擎再说。

**`--id` 不与媒体 id 冲突**：`--id` 始终是**播放器 id**（生命周期动词用）；媒体 id 走位置参数。

**`-S SORT`（format-sort）属于引擎**，不再出现在 `ut-play` 的 flag 面上 —— 它是 yt-dlp 的概念。

---

## 3. 引擎契约

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
- `format` 是引擎解析时**实际用的格式串**；播放器把它原样写进 player record（它自己不认识格式）。
- `stream_url` 为单值（音频模式）；video 模式若分离音视频，用 `stream_urls: []` 并保留 `http_headers` 同级。
- 失败时 `status:"error"` + `reason`（沿用现有 reason 枚举，**不新增成员**）。

### 3.3 `ut-play` 怎么用它

```
ut-play --engine bilibili -d -- BV1FPjy6TEiE
   └─ bili-resolve -j -f audio -- BV1FPjy6TEiE
   └─ mpv "$stream_url" --http-header-fields=<从 http_headers 拼> --input-ipc-server=…
```

`ut-play` 不再传 `--ytdl-format`：它拿到的已经是直链，格式选择上移到引擎（`-f MODE` 透传）。
这消掉了 `SPEC-system.md` §6.1 那个「第 7 次 yt-dlp 调用不是我们发起的」的不对称：
**从此只有一次抽取，且它由我们发起。**

### 3.4 ytdl_hook 退场：它免费给的三件事要自己接

| ytdl_hook 原来做的 | 谁接手 | 风险 |
|---|---|---|
| 把 `http_headers` 落成 mpv 选项（`set_http_headers`） | `ut-play` 自己拼 `--http-header-fields` | 低，但拼错只在 B 站这种校 Referer 的站暴露 |
| **分离音视频合成一条 EDL** | `ut-play`：`stream_urls` 一条 → `mpv <url>`；两条 → `mpv <video> --audio-file=<audio>` | **中** —— 5 种播放模式，`bv*+ba/b` 会出两条流。纯音频不受影响，video/fast/ascii/viz 要逐个验 |
| 直播 / HLS 清单的再解析 | `<engine>-resolve` | **中** —— 直播行本来就在移植风险清单上（`ROADMAP` §7.5） |

**退路**：若 B-2 验下来 video 模式的 EDL 太难，**只让音频模式走 resolve，video 模式暂留
`--ytdl-format` 老路**。两条路并存难看但可回退，且音频是本项目的主用例。

---

## 4. 归属决定：每个共享符号住哪

**结论：不建 `shell/ut-common`，引擎与播放器只经 argv / envelope 通信。**

逐符号核实过之后「共享面」基本不存在 —— 被当成共享的三个函数里，两个本来就该整个归引擎，
第三个是两个不同的分类器穿了一件外套。

| 符号 | 归谁 | 依据（已核实） |
|---|---|---|
| `JQ_PRELUDE`（`p2` / `fmt_dur`，`:295`） | **引擎** | 只有 `resolve_info:1427` 与 `fetch_results:1767` 用。播放器从不格式化时长（`--status` 吐裸秒数；时长渲染在 `yt-tui` 的 `short_dur`/`fmt_sec`） |
| `format_for_mode`（`:656`） | **引擎** | 它返回 **yt-dlp 格式串**（`$YT_AUDIO_FORMAT` 等）。播放器只认 mode，永不认 format。`detach_play:867` 用它只为把 `fmt` 写进 player record —— 改为记录 resolve envelope 的 `format`（§3.2）。`YT_AUDIO_FORMAT` / `YT_VIDEO_FORMAT{,_FAST}` 随它走 |
| `YT_COOKIE_ARGS` + 浏览器 profile 探测（`:68-124`） | **引擎** | 纯 `--cookies-from-browser`，是 yt-dlp 的事。它离开播放器正是 D9 要的结果 |
| `have_probe_tools:480` · `probe_media_fetchable:493` · `play_url_with_probe:528` | **引擎** | PO-token 探测是 googlevideo 专属补丁（`RESEARCH-bilibili-engine.md` #6）。**整套探测机制内化进 `yt-resolve`**：播放器拿到的直链已经是「能取到字节的那一条」，播放路径塌成 `play_url_directly → play_mode_url → run_mpv` |
| `detach_title_updater:967` | **引擎** | `yt-dlp --print "%(title)s"`。它存在只因搜索不给标题 —— B 之后标题由 resolve envelope 直接给，**这个后台回填可能整个消失**（B-2 定夺） |
| `ensure_state_dir:702` + `STATE_DIR` / `PLAYERS_DIR` | **播放器** | 它建的是 `players/`（0700）。引擎侧两个调用点要的只是「一个 0700 scratch」：`resolve_transcript:1545` 放字幕文件、`fetch_results:1732` 放 stderr 临时文件。引擎自建 `mktemp -d` 并**保持 0700** —— 字幕是内容，不能落进 world-readable `/tmp` |
| `classify_playback_error:576` | **两边各一个** | 见 §4.1 |
| `die` · `require_cmd` · `require_deps` · `validate_enum` · `is_non_negative_int` · `set_action` · `usage` | **各自一份** | 本仓既有做法：`fn_graph.py` 报 `die` 与 `require_cmd` 在 `ut-play` 与 `yt-tui` 各有一份。三十行通用助手在独立可执行文件间重复，不是「一个事实两处」 |
| `YT_VERSION`（`:20`） | **`shell/VERSION` 一行数据文件** | CLAUDE.md 硬规则要求只声明一次，而「引擎去问播放器要版本」是错误的依赖方向。各自 `cat "$SCRIPT_DIR/VERSION"`，零代码共享。E 步顺带改名 `UT_VERSION` |

### 4.1 `classify_playback_error` 一分为二

今天一个函数里混着两套词表：`Video unavailable` / `Sign in to confirm` /
`Requested format is not available` 是 **yt-dlp** 的措辞，其余是 mpv 的。
B 之后 mpv 不再调 yt-dlp，两套输出彻底分家：

- **播放器**：只保留对 mpv 输出成立的分支 —— `rc==130` → `stopped_by_user`、传输层 → `network`；
- **引擎**：保留 yt-dlp 词表 —— `unavailable` / `format_unavailable` / `forbidden`，
  `transcript_fail:1672` 与 `fetch_results` 的错误路径跟着走。

**共享的是 reason 枚举本身，而枚举是契约、不是代码** —— 一处声明在 `SPEC-system.md` §14，
两边引用。**成员不新增**（§1 不变量 1）。

---

## 5. 分步

### A. 核心改名（零代码搬移）☑ 2026-08-23

原计划是把播放器那一半（约 1000 行）搬出来。开工前核实调用图发现它在第一步就要求解决
三个本属 B 的问题，于是**反过来切**：核心整体改名，把真正的切留给 B —— B 搬的是**较小的
一半**（引擎侧约 600 行），终点完全相同，且「A 搬 1000 行」这条风险直接消失。

```
git mv shell/yt shell/ut-play
shell/yt-play · shell/yt-search   IMPL 指向 + 定位失败文案
shell/ut-play                     usage() 抬头、printf 'ut-play %s\n' "$YT_VERSION"
tests/contract.sh                 -l 直调核心；四入口版本循环（原先因缺项而侥幸通过）
.githooks/pre-push · 四个 skill（含 fn_graph.py）· CLAUDE.md · SPEC · ROADMAP
```

`shell/yt-tui` 无需改动（它只认两个壳）。`STATE_DIR="…/yt-cli-$(id -u)"` 刻意不动 ——
改它会让正在跑的播放器失联，留到 E。

验证全绿：`bash -n` 四脚本 · 四入口 `--version` 一致 · `contract.sh` **46/46** ·
`YT_TEST_LIFECYCLE=1 lifecycle.sh` **13/13**，零孤儿 mpv。

顺带修了 `lifecycle.sh` 的一处竞态：`--set-volume --id` 紧跟两次 `-d` 就断言 exit 0，
却不等 mpv 的 IPC socket。socket 未起时 `ipc_failed`/4 是**正确行为**，这条以前靠网络快
侥幸绿（实测 mpv 起来要 4.5–15 s）。已加 `wait_for_sock` 有界轮询，非定长 sleep。

### B-1. `yt-search` 独立成引擎 ☑ 2026-08-23

**为什么先搬搜索**：它与播放路径**零耦合** —— 已核实 `fetch_results:1690` /
`print_list:1774` / `emit_search_json:1798` 各只有一个调用点，全在主派发里，
播放侧没有任何函数碰它们。搬走它不改变播放的任何一行。

| 去处 | 内容 |
|---|---|
| `shell/yt-search`（壳与实现合一） | `fetch_results` · `print_list` · `emit_search_json`，加 `JQ_PRELUDE` · cookie 块 · 引擎侧 `classify_*` · 自己的 prelude 与 argv 解析。原壳的门禁（拒 `-f` / `--detach` / URL）并进来 |
| `shell/VERSION`（新建） | 一行 `0.2.0`；各入口 `cat "$SCRIPT_DIR/VERSION"` |
| 从 `shell/ut-play` 删除 | 上述三个函数 + 主派发末尾的搜索分支 + 只服务搜索的 flag（`-n` / `-m` / `-M` / `-l`） |

引擎侧的 scratch 从 `ensure_state_dir` 换成 `mktemp -d` + 0700。

**允许一处临时重复**：cookie 块（`:68-124`）与 `JQ_PRELUDE`（`:295`）在 B-1 之后同时存在于
`ut-play` 与 `yt-search` —— 因为 `ut-play` 里还留着 `resolve_*` 与 ytdl_hook 播放路径，
它们仍要用。**B-2 结束时这份重复消失**（余下的引擎代码全部离开 `ut-play`）。
这是「每步都能跑绿」换来的代价，写在这里以免被当成 DRY 违规。

**实际做的**（除清单外）：

- `shell/VERSION` 新建；`ut-play` 与 `yt-search` 各自 `cat`，`yt-play` / `yt-tui` 仍问壳。
  `.githooks/pre-push` 的 tag 校验改读它 —— 原先 grep `^YT_VERSION=` 会在改造后取到
  `$SCRIPT_DIR/VERSION` 这个字符串，静默给出错误版本。
- `ut-play` 移除：三个搜索函数 · `-n`/`-m`/`-M`/`-s` 与其校验 · `NUM_RESULTS` /
  `MIN_DURATION` / `MAX_DURATION` / `SORT_FIELD` / `FILTERED_JSON` · 尾部搜索派发。
  非 URL 位置参数现在是 usage 错误并指向 `yt-search`（D2 随之消失）。
  `MUSIC_CHAR` 与 `JQ_PRELUDE` 留下 —— `resolve_info` 还在用，B-2 一起走。
- **envelope 加了 `status` 与 `engine` 两个键**（§3.1）。这是 B-1 唯一的契约变更，且是
  additive；`engine` 正是让调用方把结果路由回对应 `<engine>-resolve` 的那个字段。
- `contract.sh`：`-l -- --status` 的 argv 顺序检查从 `ut-play` 移到 `yt-search`
  （搜索在哪，检查就在哪）；新增「envelope 自报 engine」与「核心收非 URL → 退出码 1」两条。

**踩到一个真 bug（新写的代码，不是搬移的）**：scratch 目录原本是 `fetch_results` 的
`local dir`，而 EXIT trap 在函数返回**之后**才跑 —— `set -u` 下每次成功搜索都打印
`dir: unbound variable`。改成进程级 `SCRATCH_DIR` + 惰性 `ensure_scratch`，并实测
成功 / 散文 / 网络失败三条路径均零残留。

验收全绿：`bash -n` 六个文件 · 四入口 `--version` 一致 · `contract.sh` **48/48**
（原 46 + 新增 2）· `YT_TEST_LIFECYCLE=1 lifecycle.sh` **13/13** 零孤儿 mpv ·
`tui_pane.sh` **13/13**。

### B-2. `yt-resolve` 独立 + 播放器改走 resolve ☑ 2026-08-23

**这两件事必须同一步做**：`format_for_mode` · cookie 块 · PO-token 探测
（`have_probe_tools:480` / `probe_media_fetchable:493` / `play_url_with_probe:528`）·
`detach_title_updater:967` 归引擎，**但只要 `ut-play` 还在用 `--ytdl-format` 驱动 ytdl_hook，
它就仍需要这四样**。先搬会造成真实重复，先切又没有 resolve 可调 —— 所以同步。

| 去处 | 内容 |
|---|---|
| `shell/yt-resolve`（新建） | `resolve_stream_url:1366` · `resolve_info:1405` · `resolve_transcript:1538` · `transcript_fail:1672` · `format_for_mode:656` · 探测三件 · `detach_title_updater:967` · `JQ_PRELUDE` · cookie 块 |
| `shell/ut-play` 改 | 播放前调 `<engine>-resolve -j`，拿 `stream_url` + `http_headers` 喂 mpv，不再传 `--ytdl-format`；`--get-url` / `--info` / `--transcript` 改为 `exec yt-resolve`（**转发而非留副本** —— 副本正是 §4 要避免的东西，转发让 B-3 的删除退化成删几行路由） |
| `shell/ut-play` 删除 | cookie 块 · `JQ_PRELUDE` · `format_for_mode` · 探测三件 · `YT_*_FORMAT` 环境变量 |

**这是行为真会变的一步**，逐条比对：

- PO-token 探测（现在发生在 `yt-resolve` 内部，播放器只拿结果）
- cookie 回退
- 直播 / HLS 行
- `detach_title_updater` 是否还需要存在（标题现在由 resolve envelope 直接给）
- §3.4 的三件接手，五种播放模式逐个验

退路见 §3.4。**没有用到** —— 五种模式一次全切通过。

#### 实际做的（与计划的出入，逐条）

**1. `detach` 的延迟：计划里没有的一个真问题，解法反而删掉了一个函数。**
若父进程先调 resolve 再拉 mpv，`-d` 会从 0.04 s 变成 ~3 s —— 而这正是 `yt-tui` 的热路径。
保留 re-exec、**让子进程去调 resolve**：父进程照旧秒回，子进程拿到 envelope 后把 `title`
与 `format` 补进自己的 state 文件（`patch_player_meta`，靠 `YT_PLAYER_ID` 找到记录、靠
pid 匹配自守）。于是 §8 那个悬而未决的问题有了答案：**`detach_title_updater` 整个删除**，
且是净赚 —— 少一次 `yt-dlp --print title` 往返，少一个要重定向 fd 的后台任务。
父进程写 `format: null` / `title: null`，子进程回填。实测 `--status` 一两秒后两者都在。

**2. 引擎令牌 `youtube` → `yt`（名字即命令前缀）。**
`ut-play --engine yt` 直接拼出 `yt-resolve`，零注册表 —— 否则 `ut-play` 与（D 步的）
`ut-tui` 各要一张 `youtube→yt` 映射表。B-1 刚加的 `engine` 字段随之改值，改在这里最便宜。

**3. resolve envelope 只发 `stream_urls`（数组），不发 §3.2 草稿里的单值 `stream_url`。**
两个键是同一事实两处；数组形态也正好是今天 `--get-url -j` 已有的形状，契约不变量更稳。
排序**视频在前**（jq 稳定排序按 `vcodec`），播放器只认下标：0 给 mpv，1 给 `--audio-file`。

**4. envelope 多两个键：`title`/`duration` 与 `retried`。**
前者是 detach 回填与 `--force-media-title` 的来源（`ytdl_hook` 退场后 OSD 否则会显示一串
googlevideo 路径）；后者让播放 envelope 的 `retried` 继续说真话 —— 探测搬进引擎后播放器
自己看不见这件事了。§3.2 的草稿两者都没写。

**5. 一次 yt-dlp 调用，不是两次。**
`--dump-single-json -f FMT` 同时给出 URL、`http_headers`、`title`、`duration`；探测直接
拿这份记录去 curl，不再像老代码那样先 `yt-dlp -g` 再让 mpv 又抽一次。**抽取次数 3 → 2。**

**6. 退出码：resolve 失败 floor 到 2。**
yt-dlp 对「视频不存在」退 1，而 1 是 usage。沿用 `yt-search` 已有的
`rc <= 1 ? 2 : rc`。后果：`--get-url` 遇到失效视频从 1 变 2 —— 与 §15 的分类法一致，
且 `--get-url` 本来就在 B-3 删除名单上。

**7. `ut-play` 收「handle」而不是「URL」。**
形状校验下放给引擎（§5 B-3 预告的语义提前到这里，因为不这样 `--engine` 没有意义）：
播放器只拒绝「明显不是 handle」的东西 —— 空、或含空格（那是查询）。
`yt-play "a query"` 仍然是 1（有空格），contract 不破。

**8. 顺带修的：`ut-play` 的 `usage()` heredoc 没加引号**，`--transcript` 说明里的反引号
被当命令执行，`ut-play --help` 一直往 stderr 吐三行 `command not found`（改造前就有）。
改成 `<<'EOF'`。

**9. 丢掉的一件事（已接受）：无 curl 时的 play-fail-replay 回退。**
老代码在没有 curl 时靠「播失败→去 cookie 重播」兜底，而那个重试住在播放器里 —— 现在的
播放器不知道 cookie 是什么。`yt-resolve` 无 curl 时不探测、直接用首选客户端。
交集很窄（无 curl **且** 有 cookie **且** 该视频撞 PO-token 墙），写在 `probe_raw` 的注释里。

**10. `--http-header-fields-append` 落在 mpv 的 argv 上，`ps` 可见。**
YouTube 引擎只回 UA/Accept/Accept-Language/Sec-Fetch-Mode，无凭据。已在 `run_mpv` 与
`SPEC §14` 写明：**引擎不得在 `http_headers` 里回 Cookie / Authorization**。
若将来某个引擎必须回，正解是把选项写进 0700 state dir 里的 mpv config 用 `--include=`。

#### 验收

`bash -n` 五脚本 · 五入口 `--version` 一致 · shellcheck：`ut-play` 的基线只减不增
（三条反引号 note 随 #8 消失），`yt-resolve` 只有与 `yt-search` 同款的 SC2016/SC2329 info。

- `contract.sh` **58/58**（原 48 + 新增 10：resolve envelope 键集/单行/收裸 id/拒非 id/
  拒 `-d`/拒 `-n`，未注册引擎→1、引擎名校验→1，失效 id→2 且带 reason，版本五入口）
- `YT_TEST_LIFECYCLE=1 lifecycle.sh` **13/13**，零孤儿 mpv，detach 仍 0 s 返回
- `tui_pane.sh` **13/13**
- **五种播放模式逐个真跑**：audio（coreaudio 出声、位置推进）· video（tmux exit 0）·
  fast（exit 0）· ascii（tct 逐帧、exit 0）· viz（showwaves 逐帧、exit 0）
- **分离音视频真跑**：`jNQXAC9IVRw` 默认 `bv*+ba/b` 出两条流，用 ut-play 生成的原样 argv
  跑 mpv（`--vo=null --ao=null`）→ 两条轨道都在、A-V 同步、exit 0
- **直播 / HLS 真跑**：`rFZHOHl-L8A` 解析出 m3u8，mpv 直接开、exit 0 —— 清单再解析
  不需要我们接手，ffmpeg 原生处理
- **`--force-media-title` / `--no-ytdl` / `--audio-file` / header 拼装**：用一个假 mpv
  记录 argv 逐模式核对

### B-3. 合并与删除（destructive step，最后且最小）☑ 2026-08-23

`yt-play` 是门禁壳，`ut-play` 是实现。**引擎搬走之后这两层就该合并**：`ut-play` 里只剩
一个动词，也就没有「绕过门禁去调核心」这件事可防了 —— 而那正是 CLAUDE.md 当初把核心挡在
PATH 之外的唯一理由。

- 删 `shell/yt-play`；`ut-play` 吸收其门禁职责并上 PATH
- `--get-url` 删除（由 `yt-resolve` 取代）；`--info` / `--transcript` 只在 `yt-resolve` 上
- `shell/yt-tui:39` 的 `YT_PLAY="$SCRIPT_DIR/yt-play"` → `ut-play`
  **（必须在本步内改，否则 B 到 D 之间 TUI 是坏的；原计划把 TUI 改动全放 D 步，这一行是例外）**
- `contract.sh` 约 30 处 `shell/yt-play` 分流：播放 / 生命周期 → `ut-play`，
  `--info` / `--transcript` → `yt-resolve`；`lifecycle.sh` 同理
- 每个删除前 grep-gate（A→E 方法论 C 步）

**一处契约会真的变（已论证并接受）——「ut-play 收 handle」这半已在 B-2 落地**，
因为不下放形状校验，`--engine` 就没有意义。今天 `ut-play` 只拒绝「明显不是 handle」的
输入（空、含空格），瞎写的 11 位 id 是 **resolve 失败（2+）且 envelope 带 reason**，
已由 `contract.sh` 的「dead id is 2+, not 1」两条钉住。`yt-play "a query"` 仍是 1
（含空格），因为 `yt-play` 自己那道「必须像 URL」的门禁还在 —— **B-3 要做的就是删掉它**。
搜索标志 `-n` / `-s` 在 `ut-play` 里仍然是 1（未知标志），不变。

#### 实际做的（与计划的出入，逐条）

**1. 门禁不是「搬过来」，是三条各自成立的规则。**
`yt-play` 那道「参数必须像 URL」的门禁按计划**删除**（`ut-play` 侧 B-2 已收 handle）。真正
值得留的是另外三条，都落在 `ut-play`：未知长标志（`--*` 全部在归一化循环里处理，落到 getopts
只会得到没用的 `invalid option: --`）、搜索标志重定向（`-n`/`-m`/`-M`/`-s` → 指向 `yt-search`）、
以及引擎动词**点名**。

**2. `--info` / `--transcript` 不是「变成未知标志」，是点名报错。**
计划只写「只在 `yt-resolve` 上」。静默的 `unknown flag` 会让调用方以为拼错了；现在
`ut-play --info` 退 1 并说 `run 'yt-resolve --info -- <id|URL>'`。`--get-url` 同理，且它的
文案说的是「用裸 `yt-resolve -j`」—— 因为解流本来就是裸调用，不是某个 flag。

**3. `-J` 随三个动词一起离开 `ut-play`（计划未提）。**
它只在 `--info`/`--transcript`/`--get-url` 的转发里被翻译成引擎的 `-J`；play envelope 没有
raw record。留着就是一个被静默忽略的标志 —— 正是门禁存在的理由。`-J` 现在报错并指向
`yt-resolve --info -J`。

**4. 偏离计划：`-S` 保留在 `ut-play`。**
§2.2 写「`-S` 不再出现在 `ut-play` 的 flag 面上」。但它是**纯透传**（`resolve_for_play` 与
detach 子进程各一处），移走会让「播放时覆盖 format-sort」无处可设（没有对应的 `YT_*`）。
播放器不解释这个串，只转发 —— 边界没破。

**5. `yt-resolve` 接手 `--transcript` 的 flag 门禁。**
`yt-play` 拒 `-f`/`-d`/`--volume` 与 `--transcript` 同用；`-d` 那半 `yt-resolve` 早有，`-f`/`-S`
那半没有 —— 它们被接受然后**静默无效**。补上 `FORMAT_FLAG` 与一条「`-f`/`-S` 只属于解流」的
校验，contract 里那两条检查随动词搬到引擎上。

**6. `yt-search` 的拒绝表分流。**
`--info`/`--transcript`/`--sub-lang` 从「playback flag → 用 ut-play」改为「另一半引擎 →
用 yt-resolve」；`--get-url` 从表里消失（它不再存在于任何地方）。

**7. `shell/yt-tui:39`** 的 `YT_PLAY` → `UT_PLAY`/`ut-play`（连同定位失败文案与 8 处注释），
与删除同一 commit。顺带修两处 B-2 之后就不成立的注释：LOADING 态不再是「mpv 用 yt-dlp 解流」
而是「子进程问引擎」，launch 失败也不再是「yt-dlp 失败」。

**8. `.githooks/pre-push` 的四脚本列表里没有 `yt-resolve`（B-2 漏的）。**
一并补上：否则一个语法坏掉的引擎可以直接推上去。`fn_graph.py` 的文件表同理。

**9. 文档只改「会指向不存在的文件」的地方。** `CLAUDE.md`（文件表、依赖图、seam 段、一名一
命令、`bash -n` 命令行、PATH 说明）、`README.md`（安装四行 + 一行迁移说明）、三个 skill 的命令、
`SPEC-system.md` 顶部在途说明加 B-3 条 + §14 划掉 `--get-url`。**§4 拓扑图、§12 命令规格、
§13 两层门禁模型的全量重画仍在 E** —— 在途说明已经声明了这笔债。

#### 验收

`bash -n` 四脚本（`/bin/bash` 显式）· 四入口一版本 · shellcheck 基线 15 → **14**（只减不增）

- `contract.sh` **61/61**（原 58 + 新增 3：未知长标志退 1、`--get-url` 已退役、`--info` 归引擎）
- `YT_TEST_LIFECYCLE=1 lifecycle.sh` **13/13**，零孤儿 mpv，detach 仍 0 s 返回
- `tui_pane.sh` **13/13**
- **九个 envelope 单行**（search `-j`/`-J`、resolve `-j`/`-J`、`--info`、`--transcript`、
  `--status`、`--stop`、play 失败）
- **调用栈实测**：父进程 0 s 返回 → 子进程 `yt-resolve -j -f audio` → 一次 `yt-dlp` →
  `mpv --no-ytdl <直链> --http-header-fields-append=… --force-media-title=…`；
  **mpv 之下没有 yt-dlp**，`title`/`format` 由子进程回填，停止后零孤儿
- **边界扫描**：`ut-play` 内零 `yt-dlp`/cookie/站点字样（仅注释）；`yt-search`/`yt-resolve`
  内零 `mpv`/`players/` 写入；`yt-tui` 内零两者。`fn_graph.py`：零无调用方函数

#### 发现但未做（B-3 之外，等决定）

- **`yt-search -S` 是空转标志**：它把 `--format-sort` 加到一个 `--flat-playlist
  --dump-single-json --skip-download` 的调用上，而 flat 搜索根本不解析格式，envelope 里也没有
  格式字段 —— 收一个值却不可能改变任何输出。删它是缩小 agent 面的净赚，但那是一次**契约变更**
  （冻结面规则 4），所以单独决定，不夹带在 B-3 里。
- **player record 的 `url` 可能是裸 id**：`ut-play -- dQw4w9WgXcQ` 之后 `--status` 的 `url`
  就是 `dQw4w9WgXcQ`。resolve envelope 里已经有归一化后的 `url`，子进程回填 `title`/`format`
  时可以顺手回填它 —— 但那是 `--status` 契约里一个字段的语义变化，同样单独决定。

### C. `bili-search` / `bili-resolve` ☐ 下一步

- `bili-search`：`curl` 打 `/x/web-interface/search/type`（`buvid3` + UA + Referer）→ jq 整形。
  必做的三件数据清洗：剥 `<em class="keyword">`；`"MM:SS"`（分钟无上限）转秒；`play` → `view_count`。
- `bili-resolve`：WBI 签名（`openssl dgst -md5` + `sort` + `jq -rR @uri`）→ `/x/player/wbi/playurl`
  → DASH 里挑音频 → 输出 `stream_url` + `http_headers:{Referer}`。
- **WBI 必须有固定向量单测**（纯函数、无网络，`bilibili-tui/src/api/wbi.rs` 有两条官方样例可抄）。
  这是 rigs-only 规则的合法例外：它测的不是渲染或协议，是确定性变换。
- 风控：HTTP 412 / `code:-352` 归入 `network`（可重试），**不新增 reason 枚举成员**。

### D. `ut-tui` ☐

引擎注册表（名字 → 命令前缀）+ 切源键；其余渲染逻辑不动。`yt-tui` → `ut-tui` 改名。

### E. 文档 + 全量验证 ☐

`SPEC-system.md`：§0 在途说明删除、§4 命令拓扑、§5 seam 表、**§6.1 调用栈图（形状变了：
mpv 不再自己调 yt-dlp）**、§12 命令规格、§13 门禁模型（两层塌成一层）、§14 数据契约
（加 resolve envelope）、§17 函数图、§27 验证矩阵。约 25 处光杆 `yt` 指核心的措辞一并清掉。
`YT_VERSION` → `UT_VERSION`，`STATE_DIR` 的 `yt-cli-` 前缀可在此改。
README + 各 `usage()`。然后 `verify-suite` 四阶段，**phase 4 必须真放一次 B 站音频**。

---

## 6. 验证矩阵（新增项）

| 检查 | 抓什么 production 失败 |
|---|---|
| 引擎契约一致性：对每个 `<engine>`，`-search -j` 与 `-resolve -j` 的 envelope 键集与类型 | 新引擎悄悄改了字段名 / 少了 `http_headers`，调用方对不上 |
| `ut-play --engine X` 对未注册引擎 → 退出码 1 + 可读错误 | 拼错引擎名时退出码落进 2+，agent 误判为工具失败 |
| 无法解析的媒体 id → 退出码 2+ 且 `-j` envelope 带 reason | B-3 换来的新语义静默退化成 exit 1 或裸 stderr |
| WBI 固定向量单测 | 签名算法改错，只在真实请求时才发现 |
| B 站直链 + `--http-header-fields` 能被 mpv 打开 | Referer 拼装写错 → 403，但只在 B 站上暴露 |
| 五种播放模式各起一次（B-2 之后） | EDL / `--audio-file=` 接手写错，只在 video 侧暴露 |
| `-d` 起 YouTube 与 B 站各一个 → `--status` 两个都在 → `--stop --all` 清空 | 生命周期被引擎污染 / `players/` 出现第二个所有者 |
| 三个可执行文件 `--version` 一致（读同一个 `VERSION`） | 版本声明重新长成多份 |

---

## 7. 兼容与迁移

**不留符号链接，不留弃用期。** 套件未打包、无安装器、无外部用户（`ROADMAP.md` D1），
兼容层在这里是纯成本。

- `yt-play` → **删除**（职责并入 `ut-play`，见 §5 B-3）
- `--get-url` → **删除**（由 `yt-resolve` 取代，无别名期）
- `yt-search` → **名字不变**（它本来就该说明自己是 YouTube）
- `yt-tui` → `ut-tui`（D 步）。**人机面不发短名**（D10：`ut` 与 `utt` 都被占）；
  用户想要短名自建 alias，套件不发第二个名字
- 用户自建的 `~/bin/yt-play` 符号链接由 README 一行迁移说明处理
  （`ln -s "$PWD/shell/ut-play" ~/bin/ut-play`）
- `ROADMAP.md` **D2 / D3 里「裸 `yt "query"` → 列表、`yt <url>` → 播放」的核心内部契约
  随引擎搬离而消失** —— E 步在 ROADMAP 里划掉并指向 D9

---

## 8. 已知风险

- ~~**B-2 是行为可能真变的一步**~~ —— 已过。EDL 合成塌成 mpv 的 `--audio-file` 一个
  参数；直播 / HLS **不需要再解析**（ffmpeg 原生开 m3u8）。退路未动用。唯一真丢的是
  无 curl 机器上的 play-fail-replay（B-2 实录 #9）。
- **B 一次动三个文件的身份**（`yt-play` 删除、`yt-search` 由壳变引擎、`ut-play` 上 PATH）。
  缓解就是 B-1 / B-2 / B-3 的拆分本身，且拆分线是**耦合度**而非文件数：
  B-1 搬零耦合的搜索、B-2 搬与播放路径耦合的 resolve（搬移与切换同步做，否则必然重复）、
  B-3 只做删除。**destructive step 最后且最小**（A→E 方法论）。
- ~~**`detach_title_updater` 的去留在 B-2 才能定**~~ —— 已定：**删除**。标题由 resolve
  envelope 给，detached 子进程自己回填（B-2 实录 #1）。
- **C 步的 WBI 与风控没有上游文档可跟**（`bilibili-API-collect` 2026-01 已归档）。
- **B 站音质门槛**依赖 `SESSDATA`，走现有 cookie 通道；**任何 cookie 内容都不得落进 `players/`**。
