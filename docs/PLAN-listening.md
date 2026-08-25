# PLAN-listening —— 收听完整度（ROADMAP P4 · D14/D15）

> 状态：**1/3 已落地**。三条目按依赖排序，逐条落地、逐条把契约并入 as-built；最后一条落地时删除本文件。
>
> | # | 条目 | 状态 | 已并入 / 落地后并入 |
> |---|---|---|---|
> | 1 | 播放列表管理（`ut-playlist` + 用户级状态层） | **已落地 2026-08-24** | `AS-BUILT-contract.md` §1.4/§1.5/§2/§3/§4/§5 · `ARCHITECTURE.md` §4/§9.4/§17/§27 · README · CLAUDE.md |
> | 2 | 播放队列 **+ 运行时播控动词**（`ut-play` 长出 `--queue/--enqueue/--next` 与 `--pause/--resume/--seek/--seek-to`） | **播控四个动词已落地 2026-08-24**；队列未开工 | 已并入：`AS-BUILT-contract.md` §1.1/§3/§4 · `ARCHITECTURE.md` §9.3/§26/§27 · README。队列落地后并入：`AS-BUILT-contract.md` §1.1/§3 · `ARCHITECTURE.md` §9.2 |
> | 3 | 收听历史（`ut-history`） | 未开工 | `AS-BUILT-contract.md` §1.6/§3/§5 · `ARCHITECTURE.md` §9.2 的分离规则 |
>
> §1/§2/§3 的三条决定（状态住在哪、记录形状、队列归谁）在第 1 步里全部落地并经过实跑，
> 后两步不再重开；第 1 步的实际交付与偏差记在 §5。
>
> **Pre-mortem（`AS-BUILT-workflow.md` B2）已跑过 —— 2026-08-24，对象是未开工的步骤 2/3。**
> 冷读的失败复盘产出 8 条预防措施，**全部采纳**，并折进各自的所属小节：§3（队列的锁与循环形状）·
> §4.2（解析失败推进队列）· §4.3（记录点）· §5 步骤 2（停止规则、曲间空隙实测）· §5 步骤 3
> （截断的会红检查）· §7（空隙从预算变成待测数字）。不另开 pre-mortem 附录 —— 一条决定只住在
> 它管的那一节。

---

## 0. 开工前核查（2026-08-24，全部成立）

- **契约文档在** —— `docs/AS-BUILT-contract.md`，契约有一份可以照着写 diff 的来源。P4 的每一条新
  envelope 都往那份文档里加，不往 `ARCHITECTURE.md` 里加。
- **`docs/PLAN-*.md` 为空** —— 本文件是 ROADMAP §1 说的"由 P4 的第一步开出"的那一份。
- **代码里没有队列/播放列表/历史的任何半成品**（`grep -rn "playlist\|queue\|history" shell/` 命中的
  全是 yt-dlp 的 `--no-playlist`、HLS playlist、和 §9.2 那条"`failed[]` 不是历史"的注释）。
- **状态层的先例已经趟过并发**：`players/` 的「一实体一 JSON + `mkdir` 锁 + 原子 temp+mv」
  （`ARCHITECTURE.md` §9.2/§9.3、`lock_player_state`/`detach_play`）。本 plan 是同一套模式的第二次应用。
- **一处文档漂移，随第 3 步修**：`shell/ut-play:760` 仍写着 listening history 是
  "a ROADMAP.md §0 non-goal" —— D14 之后不成立。`ARCHITECTURE.md:847` 已经改成了分离规则，只剩这条注释。

---

## 1. 决定 S1 —— 状态住在哪

**一个用户级状态目录，与 `players/` 的运行时状态物理分开。**

```
  $UT_STATE_DIR/                     默认 ${XDG_STATE_HOME:-$HOME/.local/state}/uting
    playlists/<name>.json            一实体一文件（原子 temp+mv）
    playlists/.lock-<name>/          mkdir 锁，与 lock_player_state 同形
    history/<YYYY-MM>.jsonl          仅追加，一行一次收听
```

- **为什么不是 `players/` 那个目录**：那个在 `${TMPDIR:-/tmp}/uting-$(id -u)`，重启即失。把一份用户
  攒了半年的播放列表放进一个会被系统清掉的目录，是这一步唯一一个不可逆的错误。
  `ARCHITECTURE.md:847` 的分离规则已经预先写下：`failed[]` 留在 `$TMPDIR`、有界、只记失败；
  历史另起一个持久的用户级存储。本节兑现它。
- **为什么是 XDG 而不是 `~/Library/Application Support/uting`**（macOS 惯例）：这套东西的用户面是
  终端，同类工具（`yt-dlp`、`mpv`）都落 XDG；且 §9 的 Go 化和 Linux 支持一旦发生，XDG 不用改。
  惯例分歧用一个 env 兜住，不用一个平台分支兜住。
- **`UT_STATE_DIR` 是必需品，不是方便**：没有它，`tests/contract.sh` 会写进用户真实的播放列表。
  新知设一律用 `UT_` 前缀（`AS-BUILT-contract.md` §5 的既有规矩）。
- 权限与 `ensure_state_dir` 同规格：`mkdir -p -m 700`，事后 `chmod 700`。

**历史为什么破例用 JSONL，而不是"一实体一文件"**：

1. **一次收听不是一个实体，是一个事件。** 一文件一事件在半年后是几千个 inode 和一次 `ls` 的灾难。
2. **追加不是 read-modify-write。** `>>` 打开即 `O_APPEND`，单行 < `PIPE_BUF`(4KB) 的写在 POSIX 上是
   原子的 —— 这是本套件唯一一处**不需要锁**的写。换成一个大 JSON 数组，每次写都是竞态（ROADMAP P4
   已经点名否掉了这条路）。
3. 按月分片让"体积/清理"变成 `rm` 一个文件，`--clear --before` 不必解析全文。

**硬约束（写进实现的注释，不只是写在这里）**：每行必须 < 4KB，否则第 2 条的原子性假设不成立。
`title` 落盘前截断到 200 字节（按 UTF-8 边界截，不切碎字符 —— `uting` 的 `utf8_complete` 已有先例）。

---

## 2. 决定 S2 —— 一个记录形状，三处复用

**item 是搜索结果的子集，字段名逐字沿用，不发明第二种拼法：**

```json
{"engine":"yt","id":"dQw4w9WgXcQ","url":"https://…","title":"…","duration":213,"added_at":"2026-08-24T09:00:00Z"}
```

- `engine` + `url` 恰好就是 `ut-play --engine <engine> -- <url>` 的两个参数：**一条记录即一次调用**，
  中间没有映射表。这也是 D12（引擎只认自己站的 host）之后唯一正确的存法 —— 存一个裸 URL 而不存
  `engine`，等于把路由信息丢掉，再让某个surface去猜。
- **不存 `channel` / `view_count` / `live_status`**：播放不需要，且它们会过期成谎话。
- `duration` 允许 `null`（直播），与搜索 envelope 的规则一致。

三处复用：

| 用处 | 形状 |
|---|---|
| 播放列表文件 | `{"schema":1,"name":"jazz","created_at":…,"updated_at":…,"count":3,"items":[item…]}` |
| 队列（播放器运行时） | `{"schema":1,"pos":0,"items":[item…]}` |
| 历史一行 | `item` + `{"played_at":…,"ended_at":…,"seconds":97,"reason":null}`（`reason` 用既有的枚举） |

`schema` 是一个整数版本号，第一版就写上：这是三份会长期存在于用户磁盘上的文件，未来一次格式变更
如果没有版本字段，只能靠猜结构来迁移。

---

## 3. 决定 S3 —— 队列归谁：**归播放器，且队列是播放器自己的运行时状态**

ROADMAP P4 记了两条路，都有实打实的代价。本 plan 取第三条，它把两边的代价都绕开：

| 路 | 代价 | 取舍 |
|---|---|---|
| A 归播放器 + 读一份外部队列文件 | 播放器第一次读**它不拥有的**可变状态；谁写谁读要另立规矩 | 否 |
| B 第七个命令 `ut-queue` | 两个进程都想管同一个播放器，撞 `ARCHITECTURE.md` §9.2「`players/` 一个所有者」的硬不变量 | 否 |
| **C 归播放器，队列进 `players/<id>.queue.json`** | 见下 | **采纳** |

**C 的形状**：

- 队列是 **ephemeral 的**，和播放器同生共死 —— **一条活过重启的队列就是一个播放列表**。
  这句话既是取舍的理由，也是"队列和播放列表为什么不是同一个东西"的判据。
- **所有者不变，但队列有自己的一把锁**：写队列的只有 lifecycle 动词与那个播放器的 detached
  child，没有第二个进程进场，§9.2 的不变量一个字不用改。锁名 `lock-queue-<id>`，与 player state
  的 `lock-<id>` **完全独立** —— 播放器和"正在播的这份列表"是两个实体，更新事件差一个量级
  （title 回填一次播放一次；队列每首一次，外加 `--enqueue` 随时），不该共用一个时钟。
- **两把锁的硬规则：任何路径都不同时持有两把**（拿 → 写 → 放，再拿另一把，绝不嵌套）。
  一把锁只会 stall，**两把锁才可能死锁**；而在本仓现有的 `lock_player_state`
  （`shell/ut-play:792`，有界自旋 5s，**超时后 `|| true` 继续裸写**）之下，嵌套的后果甚至不是
  挂死，是**两次 5 秒停顿加一次静默丢写** —— 更糟，因为没人会注意到。这条规则买的是写完整性，
  不是"消除死锁"这句口号。子进程在自己的 trap 里 `rmdir` 释放，否则 `--stop` 在写到一半时
  SIGTERM 掉持有者，留下的 stale lockdir 让之后每个调用者白等 5 秒。
- **agent 面天然继承**：队列状态进 `--status` 的 player 记录，不必再造一个查询面。
- **"播放一个播放列表" = 用一份快照给一个新播放器播种**，不是让播放器去读播放列表存储 ——
  `ut-play` 仍然不知道 `playlists/` 存在，正如它今天不知道 yt-dlp 存在。
- **代价如实记**：detached child 从"播一次"变成"播一串"的循环；`--stop` 要覆盖整串（已经是 pgid，
  天然成立）；曲间有一次 resolve 的空隙（v1 接受，见 §7）。
- **循环的形状 —— 两条实测定死的规则，不是实现细节**：
  1. **mpv 放后台 + `wait`，不放前台。** bash 3.2 在前台子进程运行期间**不派发 trap**。
     实测 3.2.57：前台 `sleep 5` 收到 SIGUSR1，trap 推迟整整 5 秒才跑、`sleep` 照样返回 0；
     换成 `cmd & wait "$!"` 则 1 秒内进 trap、`wait` 返回 158。所以 `--next` 若发信号给一个
     前台跑着 mpv 的子进程，实际效果是"曲终之后多跳一首"。改动只落在 `run_mpv` 的 detached
     分支（`shell/ut-play:439` —— 那一支是裸 exec，没有进程替换，所以 `wait` 拿得到 mpv 自己的
     退出码），按 `ARCHITECTURE.md` §24 的 A→E 走。
  2. **退出的原因来自子进程自己的变量，永不解码 mpv 的退出码。** 实测 mpv 0.41.0：正常播完
     rc=0，被信号打断 rc=**4**（man `EXIT CODES`：`4 = Quit due to a signal`）—— 一个 4 同时
     覆盖"`--next` 杀的 / `--stop` 杀的 / 用户杀的"。子进程在**杀 mpv 之前**先置自己的 reason，
     `detached_epitaph` 与历史记录只从那个变量取值。**哨兵文件否掉**：它就是另一把锁，而且会让
     死亡记录换一种方式说谎。（注意这与 D3 那张退出码表无关 —— 契约里的 4 是**父动词**返回的，
     子进程的 rc 从来不是 CLI 退出码；这里的风险是死亡记录说谎，不是退出码撞车。）

**被否掉的第四条：交给 mpv 自己的 playlist**（IPC `loadfile … append`）。换来无缝衔接，代价是**入队时就得
resolve**，而 stream URL 会过期（YouTube 约 6 小时）—— 一个 20 首的队列后半段会 403。
**JIT resolve（播到哪首解哪首）才和"一次提取，且由我们做"一致**，且它顺带让"队列里的第 N 首在被播到
之前一直只是一个 handle"这件事成立。

---

## 4. 命令面（每一条都必须同时对人和 agent 成立 —— D14 硬约束）

### 4.1 `ut-playlist` —— 第七个命令（步骤 1）

纯状态题：不认识站点，不认识播放，只认识 item 和文件。

```
  ut-playlist --ls                       列出所有播放列表（名字 + 条数 + 更新时间）
  ut-playlist --show NAME                列出一个列表的 items
  ut-playlist --add NAME                 从 stdin 读条目追加；列表不存在则创建
  ut-playlist --rm NAME --index N        删一条（N 来自 --show，0 起）
  ut-playlist --del NAME                 删整个列表
  ut-playlist --rename NAME NEWNAME
  共享：-j -l --color -h -V
```

- **没有 `--new`**：`--add` 按需创建。少一个动词，且与用户的想法一致（"把这首加到 jazz 里"，不是
  "先建 jazz 再加"）。
- **只有一种输入形状：stdin 的 JSON**，两种写法都收 —— 一个**搜索 envelope**（`yt-search -j` 的原样
  输出）或一个 item 数组。收 envelope 不是方便，是**正确性**：搜索结果的每一条**不带 `engine`**，
  那个字段在 envelope 上，所以只有整包收进来才贴得对引擎标签。于是
  `yt-search -j -n 5 -- "lofi" | ut-playlist --add jazz` 端到端成立。
  **没有 `--title`/`--duration` 这类单条便捷 flag**：那条路会造出一堆 `title:null` 的条目，
  而播放列表没有播放器那种 title 回填。
- **gate arm**：`ut-playlist -- <URL>` 而没有动词 → 退 1，文案指向 `ut-play`。这两个名字很近，
  按本套件既有的规矩（`AS-BUILT-contract.md` §2）由 gate 互指，而不是靠用户细看。
- 名字合法性：拒绝 `/`、NUL、控制字符、`.` 开头、> 64 字节。**文件名就是名字**（UTF-8 直接落盘），
  不做 slug —— slug 会让 `--ls` 显示的名字和磁盘上的名字变成两件事，就有了两个真相。

### 4.2 `ut-play` 的队列动词 + 运行时播控动词（步骤 2）

```
  ut-play -d --queue -                   从 stdin 读 items（JSON 数组）启动：播 items[0]，其余入队
  ut-play --enqueue [--id ID] -          往一个在跑的播放器队列尾部追加（stdin 同一形状）
  ut-play --next [--id ID]               跳到下一首
  ut-play --pause  [--id ID]             暂停
  ut-play --resume [--id ID]             继续
  ut-play --seek ±N [--id ID]            相对跳转，秒，符号必需
  ut-play --seek-to N [--id ID]          绝对跳转，秒
```

**后四个为什么在这一步、而不是继续挂在 §9 触发条件 1 上**：判据已作废，理由记在
`ROADMAP.md` §11（一句话：`--set-volume` 是同一形状的反例，而它早就发货了；`--next` 会第二次
推翻它；D3 冻结面开一次比开两次便宜）。**不解除任何 MCP 相关的 non-goal** —— 这批动词与 MCP
脱钩。

- **为什么是 stdin 而不是 argv 上的多个 handle**：播放列表是**引擎无关**的，一条队列可以同时有
  `yt` 和 `bili` 的条目，而 `--engine` 一次调用只有一个值。argv 表达不了 per-item 的 engine，
  JSON 数组可以。于是 `ut-playlist --show jazz -j | ut-play -d --queue -` 就是"播放一个播放列表"，
  而播放器一个字都不用知道播放列表是什么。
- **为什么是启动时播种，而不是"先播第一首再 `--enqueue` 其余"**：后者有竞态（一首 20 秒的曲子可能在
  第二次调用落地前就结束了），且把一件事变成两次调用。
- `--enqueue` / `--next` 的退出码沿用 `--set-volume` 的分类：目标不存在或有歧义 → **4**（没生效），
  不是 1（那是用法错）。`--next` 在队列已空时也是 4。
- **队列里第 N 首解析失败会怎样：推进，不停播。** 一条失败让队列走到第 N+1 首，reason 进
  `--status` 已有的 `failed[]`，播放器不死。理由：JIT resolve 把"一次播放一次提取"变成一条队列
  N 次，任何一次上游抽风都会撞上；让一条失败杀掉整条队列，等于把 yt-dlp 的可用性直接焊到播放器
  的生命周期上。也不做重试 —— 重试是把曲间空隙再乘一遍。
- `--status` 的 player 记录加一个键：`"queue":{"pos":0,"len":3,"next":{"title":…,"url":…}|null}`。
  没有队列时 `"queue":null` —— 一个键恒在，值可为 null，和 `title`/`duration` 的既有做法一致。
- **v1 不做**：`--dequeue`、重排、循环/随机。记在 §7，不是遗漏。

**播控四个动词的设计（决定，不是待议）**：

- **`--pause` / `--resume`，不做 `--toggle-pause`**（§26 早已定）：`cycle pause` 不回值，
  envelope 只能猜；两个幂等动词对机器调用方本来就更好，没有 read-modify-write 竞态。
  切换留给 `uting` 的按键。
- **`--seek` 的值必须带符号**（`+30` / `-15`），绝对跳转另用 `--seek-to N`。裸 `--seek 30` 同时
  违背 mpv 自己的默认（相对）和 `uting` 的 `seek_relative`，会把想 +30s 的调用方静默弹走。
  不带符号 → **1**（用法错），不是 4。
- **envelope 报的是回读的状态，不是推算的**：
  `--pause`/`--resume` → `{status:"ok", id, paused:true|false}`；
  `--seek`/`--seek-to` → `{status:"ok", id, position:<秒>}`。
  两者都在命令成功后**再读一次属性**填值 —— `--set-volume` 今天就是这么做的，而"算出来的位置"
  在被 clamp（seek 越过片尾）时就是谎话。
- **退出码沿用 `--set-volume` 那张表**：无目标 / 歧义 → **4**；IPC 失败 → 4 + `reason:"ipc_failed"`；
  值的形状不对 → 1。**seek 越过片尾不是错**：mpv 自己 clamp，回读到什么就报什么，退 0。
- **直播**（`duration` 为 null）上 `--seek` 让 mpv 自己拒绝，把它的失败翻成 4 + `ipc_failed`；
  不在播放器里预判"这是直播所以不能 seek" —— 那是站点知识，播放器不持有。

**`uting` 这一侧：写路径改调动词，读路径原样不动 —— 已落地。**
`toggle_pause` / `seek_relative` 改成经 `play_verb` 调 `--pause|--resume|--seek`，
**净删** TUI 里的 IPC 写代码；`toggle_pause` 顺带从"盲翻本地标志"变成"读回 envelope 的
`paused`"，盲翻只留作答不上话时的兜底。每秒刷新的 `fetch_play_times`（一次连接读四个属性）
**保持直连 socket** —— 每 tick fork 一条进程链是真代价，原判据里这一半是对的。
`adjust_volume`（`9`/`0` 键）**量过了，留在 socket 上**：真播放器上各按 10 次，直连
**10 ms/次** vs `ut-play --set-volume` **60 ms/次**（后者还要解析目标 + 带锁改状态文件），
超过本 plan 定的 50 ms 线。例外连同数字写进 `ARCHITECTURE.md` §26，不留成没解释的不一致。

### 4.3 `ut-history` —— 第八个命令（步骤 3）

```
  ut-history --ls [-n N]                 最近 N 条，新的在前（默认 20）
  ut-history --record -                  从 stdin 读一条收听记录并追加（播放器调用，best-effort）
  ut-history --clear [--before DATE]
```

- **记录点是"曲终**或**子进程收到信号"，不只是曲终。** `--stop` 杀的是整个进程组，子进程一起死 ——
  只在曲终写，历史就只会记下**没人打断的那些首**：一份系统性偏斜的记录，比没有历史更误导人
  （"我最近爱听什么"会变成"我最近没跳过什么"）。用 §3 那把 trap 写，SIGTERM 可捕获，只有
  SIGKILL 丢。
- **写入点在播放器，但存储归 `ut-history`**：detached child 在每首结束时 `ut-history --record`，
  用的是它调 `<engine>-resolve` 的同一种方式 —— **按名字调一个兄弟命令**，所以历史的磁盘布局只有
  一个所有者。`ut-history` 不在 PATH 上时静默跳过（**能力由有无表达**，与 `bili-resolve` 没有
  `--transcript` 同一条规矩）。
- 与 `detached_epitaph` 的关系：同一个时刻，两条不同的记录。epitaph 只在失败时写、写进 `$TMPDIR` 的
  日志；history 成功失败都写、写进用户级存储。**这不是重复，是那条分离规则的两侧。**
- **默认开**，`UT_HISTORY=0` 关。理由：默认关的历史等于没有历史；它是本地文件、不出这台机器、
  有 `--clear`。**重开条件**：如果有人要把这套东西跑在共享账号上，默认值要重新讨论。

---

## 5. 施工顺序与每步的验收

**顺序按依赖，不按体感优先级**（ROADMAP P4 已定）：状态层做错，后两条一起返工。

### 步骤 1 —— 播放列表（把状态层跑通）· **已落地 2026-08-24**

1. `shell/ut-playlist`：状态目录解析、`mkdir` 锁、原子 temp+mv、六个动词、gate、`-j`/`-l`。
2. `shell/uting`：把焦点条目加进一个播放列表（一个按键 + 复用已有的输入行原语），以及从一个播放列表
   进列表视图。**零站点逻辑**，纯编排 —— 它调 `ut-playlist`，不自己碰文件。
3. 验收：**全部关闭。** `contract.sh` 121 ok / 0 failed（新增 26 条，一律在
   `UT_STATE_DIR=$(mktemp -d)` 下跑，绝不碰用户真实的列表）；`a`/`b` 两个键在 tmux 里实跑过
   （`tests/drive.sh`），包括**在 yt 会话里从混合列表播一条 B 站曲目**并真的响了；
   **每条检查都先把它守的东西弄坏、看着它变红**：把 `lock_playlist` 打桩后 8 个并发 `--add`
   只剩 1 条，`--del` 改成非幂等、名字校验删掉后，正是对应的那几条检查转红。

**实际交付与偏差（对照上面的原计划）**：

- **多做的**：`uting` 不只有"加入列表"，还能**把一个播放列表当作行的来源打开**（`b` 键）——
  原计划把它列在步骤 1，实际做了，因为行记录**必须**先长出第七个字段 `engine`（一个列表可以
  混引擎，会话引擎会把 B 站 URL 送给 `yt-resolve`），而这个字段一旦加了，列表视图就几乎白送。
- **契约上多出来的两件**（都是为了不在 `uting` 里复制记录形状）：`--show -j` 的条目带一个
  **读时派生**的 `duration_fmt`（不落盘 —— 落盘就是同一个数字的第二个真相），这让一条 item
  与一条搜索结果**逐字段行兼容**；`--add` 因此也收自己的 `--show` envelope，于是
  "把一个列表拷进另一个" 免费成立。
- **少做的**：`--add` 的单条便捷 flag（`--title`/`--duration`）在开工前就砍掉了（见 §4.1）。
- **一个构建期真 bug，记下来因为它会重犯**：`read_items` 最初写成 `items=$(read_items)`,
  而命令替换跑在**子 shell** 里 —— `fail` 的 `-j` 错误 envelope 被读进了变量、`exit` 只结束了
  子 shell。**一个会带 envelope 失败的函数，不能用 stdout 返回值**，现在它写全局。
- **顺手修的三处套件级问题**（都属于"加第七个命令暴露出来的旧假设"）：
  `.githooks/pre-push` 的语法门原本硬写六个路径 → 改成 glob；`contract.sh` 的
  "六个入口一个版本" → 改成对 `shell/` 下**每个带 shebang 的文件**成立的不变量；
  `tests/drive.sh` 的环境透传其实**从来没生效过**（新 tmux session 拿的是 tmux **服务器**的
  环境，不是当前 shell 的）—— 现在显式转发 `YT_*`/`UT_*`，实测才发现的。

- **落地后的一次加固（`0f4d028`），改动了 §4.1 写下的退出码**：两个**读**动词原本没有任何
  守卫，一个坏掉的 json 文件就让 jq 的 parse error 逃出去成为退出码 5 —— `-j` 下连 envelope 都
  没有,正是 `yt-search` 修过的那个故障在第二个命令里复发。现在 `read_playlist()` 是唯一把 jq
  指向播放列表文件的地方,顺带把写了却从不读的 `schema` 用起来。同时 `--rename` 原本只锁源、
  却写目标（并发 `--add` 会被无锁覆盖,实测 0 + 列表丢失,现在 4 + `locked`）。
  **退出码因此改成两侧**：`invalid_name`/`invalid_input` → 1（调用本身错）,
  `not_found`/`exists`/`locked`/`corrupt` → 4（调用没问题、存储答不了）,与
  `ut-play --set-volume` 找不到播放器退 4 同一条线。§4.1 只写了 "0/1/4 locked",以本条为准,
  as-built 已同步。新增 reason `corrupt` 同时覆盖"文件坏了"和"schema 比本 build 新"。

### 步骤 2 —— 队列 + 播控动词（唯一动到 D3 冻结面的一步）

1. `shell/ut-play`：detached child 的播放循环（后台 mpv + `wait` + trap，§3）、
   `players/<id>.queue.json` 与它**自己那把** `lock-queue-<id>`、三个动词、`--status` 的 `queue` 键。
2. `shell/uting`：把结果加入当前播放器的队列；焦点卡显示 `next`。
3. 验收：
   - `contract.sh`（**空闲态**，无播放器）：`--enqueue` 无目标 → 4、有歧义 → 4、`--next` 空队列
     → 4、`--queue -` 收到非法 JSON → 1、`--status` 的 `queue` 键在有/无队列两种情况下都在；
     **播控四个动词同样在空闲态各退 4 并带 `not_playing`**（与 `--set-volume` 今天那条同形，
     所以这几条是**加强既有检查**而不是新开一类）；`--seek 30`（无符号）→ **1**，
     `--seek +30` 在空闲态 → 4 —— 这两条一起才证明"形状错"和"没生效"没有被混成一个码。
   - `lifecycle.sh`（真播放器）：`--pause` 后 `--status` 的 `paused` 变 true、`--resume` 变回
     false（**回读，不是相信自己的返回值**）；`--seek +5` 后 `position` 真的前进；
     `--seek-to 0` 回到起点。
   - `lifecycle.sh`：一条**两条目**的队列（两个真实 URL，走真实引擎、真实 mpv）真的推进 ——
     `--next` 之后 `--status` 的当前条目变成第二条；再把第一首 `--seek-to` 到结尾前几秒，
     **有界轮询**看它自己进第二首。轮询的是"进没进"，不是"多久进"：前者是行为，后者才是
     `CLAUDE.md` 禁止挂在网络上的那种计时断言。`--stop` 之后 `pgrep mpv` 为空。
   - **不引入 mock/fake 引擎，也不引入任何别的替身**（`CLAUDE.md` 的测试规则，无例外 ——
     `mpv_ipc_mock.py` 已按同一条规则删除，`.githooks/pre-commit` 现在拦 `tests/` 下的非 `.sh`
     文件）。理由不是洁癖：队列推进这条正好要穿过 **JIT resolve 的真实往返**，而那是这一步最
     容易坏的地方；一个直接吐 `av://lavfi:sine` 的假引擎会把它整段跳过，于是绿得比不测还危险。
     曲间空隙依旧是**手工测量**（§7），不进套件。
   - **两把锁的规则要有一条会红的检查**：`--enqueue` 与子进程的 title 回填并发时，两份状态都不丢
     —— 真的把 `lock-queue-<id>` 那个目录 `mkdir` 出来占住（锁本来就是这么工作的，这是制造真实
     争用，不是打桩），看着它转红。
4. **停止规则**：两个工作时段结束时，若 `lifecycle.sh` 那条"两条目队列自动进第二首"还没绿，
   **停手**，回来重议 §3 的路 C —— 不要继续往一条分支上堆 commit。这一步没有工期估算，
   所以它需要的是一条停止规则，不是一个截止日期。
5. **收工前必须量一次曲间空隙**：手工跑一条 5 条目 yt+bili 混合队列，median 与 p90 填回 §7。
   **p90 > 8s 则预取进 v1**（第 N 首播放期间解析第 N+1 首），不再延后。理由：
   `ARCHITECTURE.md` §25.1 已经有一次被限流污染的计时事故，一个没量过的"约 3 秒"就是下一次。
   这条是**手工测量，不进 `tests/`** —— 它对着真实站点，正是不该进套件的那一类。

### 步骤 3 —— 收听历史

1. `shell/ut-history` + `ut-play` 的 best-effort 调用（**曲终或子进程收到信号时**，见 §4.3 ——
   走的是步骤 2 已经建好的那把 trap）+ `UT_HISTORY`。
2. `shell/uting`：一个历史视图（复用列表渲染）。
3. 顺手修 `shell/ut-play:760` 那条过期注释。
4. 验收：`contract.sh` 新增 —— `--record` 写进去能被 `--ls` 读出来、`UT_HISTORY=0` 时播放器一个字都
   不写、`--clear --before` 只删该删的、**一条 8KB 标题的条目 `--record` 进去后 `--ls` 仍解析得出、
   且该行 < 4096 字节** —— 那 200 字节截断是 §1 那条原子性假设的承重件，所以它要有一条会红的检查。
   （§1 的假设本身实测成立：8 个并发写者 × 150 行 × 320 字节 → 1200/1200 行、0 行非法 JSON。
   所以风险不在 `>>`，在行长。）

---

## 6. 契约与版本

- **`AS-BUILT-contract.md`**（§1.5 与 `ut-playlist` 的 gate **已随步骤 1 落地**，剩下的是）：
  **步骤 2** 改 §1.1 —— `ut-play` 加七个动词（`--queue`/`--enqueue`/`--next` +
  `--pause`/`--resume`/`--seek`/`--seek-to`）、§3 加 queue schema 与 `--status` 的 `queue` 键、
  §4 记 `--seek` 无符号退 1 而无目标退 4；**步骤 3** 加 §1.6（`ut-history`）+ 它的一条 gate、
  §3 的 history 行 schema、§5 的 `UT_HISTORY`。
- **`ARCHITECTURE.md`**：新增一节讲用户级状态层（为什么与 `players/` 分开、锁与原子写、JSONL 的例外
  及其 4KB 约束）· §9.2 改成"播放器从一次播放变成一串播放"，并写下两把锁与**不嵌套**的硬规则（§3）·
  **§26 那条判据作废**（"只有调用方没法直接跟 socket 说话才加动词"—— 理由在 `ROADMAP.md` §11），
  pause / seek / next 从非目标表里移出。
- **semver**（D13）：三条都是**加法** —— 新命令、新动词、envelope 新增键。既有调用方一行不用改。
  → 每条落地各 bump 一次 **z**，`shell/VERSION` 单独一个 commit，不随功能 commit 走。
  `--status` 加 `queue` 键**不是**破坏性变更（既有消费者忽略未知键；本套件所有 envelope 都是这个约定）。

---

## 7. 未决问题与已知代价（记下来，不假装不存在）

- **曲间空隙**：JIT resolve 意味着两首之间有一次引擎往返（**预算约 3 秒，尚未实测**）。v1 接受，
  但**步骤 2 收工前必须量**（§5 步骤 2 第 5 条），median 与 p90 填在这里；**p90 > 8s 则预取进
  v1**。优化路径已经清楚：在第 N 首播放期间预解析第 N+1 首 —— 那要引入第二个后台任务和一份会
  过期的缓存，只在那个触发条件成立时才付。
- **N 次提取，而不是一次**：JIT resolve 把"一次播放一次提取"变成一条队列 N 次，于是每一次 yt-dlp
  上游抽风都被放大 N 倍，连续多次提取本身也可能招来限流。**这是路 C 的真实代价**，用 §4.2 那条
  "失败推进队列"兜住，不用重试兜 —— 重试会把曲间空隙再乘一遍。
- **macOS 的大小写不敏感文件系统**：`Rock` 和 `rock` 是同一个播放列表。**接受并写进文档**，不去对抗 ——
  bash 3.2 没有 `${var,,}`，而 `tr` 那条路在 UTF-8 名字上是错的。
- **`ut-play` / `ut-playlist` 名字相近**：由 gate arm 互指（§4.1）。不改名 —— D10 的"一名一物"意味着
  播放列表这个能力只能有一种拼法，而它就叫播放列表。
- ~~**`uting` 的音量键要不要也改走动词**~~ —— **已量、已定（2026-08-24）**：直连 10 ms/次、
  经动词 60 ms/次（真播放器，各 10 次，两次复测一致），超过 50 ms 线，所以音量键留在 socket 上；
  例外连同数字进了 `ARCHITECTURE.md` §26。pause / seek 不受这条影响（一次按键一次调用，
  不是每 tick 一次），已改走动词。
- **队列的重排 / 出队 / 循环 / 随机**：v1 不做。它们是队列**编辑**，而第一版要先证明队列**推进**是对的。
- **历史的体积**：一行约 200B，一天 50 首 ≈ 300KB/年。不需要轮转，`--clear --before` 足够。
- **下载器、频道订阅**：仍未排期（ROADMAP P4），本 plan 不碰。

## 8. 名字取舍

| 候选 | 判 | 理由 |
|---|---|---|
| **`ut-playlist`** | **采纳** | 全词、无歧义、与 `ut-play` 同前缀但不同词 |
| `ut-list` | 否 | 与每个 verb 都有的 `-l/--list` 输出模式撞车，"list --ls" 读不通 |
| `ut-lib` / `ut-store` | 否 | 缩写 + 两个名词（列表和历史）挤一个命令，flag 面会宽到小模型调不安全 |
| `ut-queue` | 否 | 队列不是一个命令（S3），它是播放器的运行时状态 |
| **`ut-history`** | **采纳** | 与 `ut-playlist` 一致：全词，不缩写 |
