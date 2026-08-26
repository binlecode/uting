# AS-BUILT-contract —— uting 的 CLI 契约

那个**冻结面**（ROADMAP D3/D13）：任何一次重写之后仍然活着的东西，也是一次移植的验收规格。
这里写的全都是 as-built —— 对着八个脚本核过 —— 并按 ROADMAP D13 的 semver 规则由 `VERSION` 定版。
**改动这份文件里的任何一条，都是一次刻意的、有记录的行为**（CLAUDE.md 硬规则 4），
从来不是某个功能的副作用。

写给两类读者，他们谁都不该需要去翻源码：

- **一个测试作者** —— 要对这八个命令中的任何一个写 JSON diff 测试，所需要的每一个信封、
  每一个退出码、每一种错误形状，都在 §1–§5；
- **第三个引擎的作者** —— §1.2/§1.3（引擎的两个命令面）、§2（它的门）、§3（它的信封）
  与 §6（清单）就是全部义务；`bili-search` / `bili-resolve` 没有满足任何这里没写的东西。

理由在 `ARCHITECTURE.md`（全文各处指过去）；流程在 `CLAUDE.md`。
一个事实一个地方：这里的 schema 别处一律不再陈述。

## 1. 命令规格

八个平级，四种形状：播放器、一个引擎的两半、UI，以及两个存储。
它们每一个都自己解析自己的 argv、自己拿着自己的门（ARCHITECTURE.md §4）——
没有一个可以委托过去的 core。

### 1.1 `ut-play` —— 播放器（与站点无关，非交互）

- **它拥有：** 播放、detached 生命周期、播放信封、退出码分类学、`players/`。
  **它不拥有任何站点知识：** 没有 yt-dlp 调用，没有 cookie 决定，没有格式字符串，没有 id 形状。
- **标志：** `-f -S -d -j -l -h -V` 加上长标志 `--engine --volume --detach --json --list
  --status --stop --set-volume --pause --resume --seek --seek-to --queue --enqueue --next
  --id --all --color --help --version`。颜色只有 `--color`（没有 `-c`）；
  `-S` 是格式排序覆盖（没有 `-F`），原样转发给引擎。`--` 结束选项解析：它之后的一切都是句柄
  （ARCHITECTURE.md §6）。一次调用至多一个动作；`--id` 属于每一个**寻址**某个在跑的播放器的动词
  （`--stop`、`--set-volume`、`--pause`、`--resume`、`--seek`、`--seek-to`、`--enqueue`、`--next`），
  而 `--all` 只属于 `--stop`；`-d` 既不与动作组合，也不与 `-f ascii|viz` 组合。
  `--queue` 不是一个动作，而是一个**启动修饰符**：它要求 `-d`、拒绝 argv 上的句柄、
  从 stdin 取它的条目（`-` 是它唯一合法的取值，`--enqueue` 也一样）。
- **行为：**
  ```
   ut-play -- <handle>          播放（散文）      ut-play -j -- <handle>   播放 JSON
   ut-play -d -- <handle>       detach；并发播放器可以
   ut-play --status             列出播放器        ut-play --set-volume N [--id ID]
   ut-play --stop [--id ID | --all]               停一个/停全部（--id 来自 --status）
   ut-play --pause | --resume [--id ID]           两个幂等动词，从不是一个 toggle
   ut-play --seek ±N [--id ID]                    **相对**；符号是必须的
   ut-play --seek-to N [--id ID]                  绝对，秒
   ut-play -d --queue - < items.json              以一个**队列**启动；第一条开始放
   ut-play --enqueue - [--id ID] < items.json     追加到一个在跑的播放器的队列
   ut-play --next [--id ID]                       丢掉这一条，开始下一条（4：没有下一条）
   ut-play                      → 用法错误，点名 yt-search / uting（D3）
   ut-play -- "some query"      → 用法错误，点名 yt-search（有空白 ⇒ 不是句柄）
  ```
- **它写收听日志。** 一个 **detached** 播放器通过 `ut-history --record`（§1.6）每条曲目记一行 ——
  在曲目结束时记，一次 `--stop` 或一次 `--next` 结束了它时同样记，
  因为一份只记录未被打断的曲目的日志，是一份系统性偏斜的记录。尽力而为：`UT_HISTORY=0` 关掉它，
  `ut-history` 不在就静默，它的任何失败都不得让一条曲目付出代价。
  一条从未开始、也不是失败的曲目（一次 stop 正好落在两条曲目之间的缝里）不是一次收听，不得一行。
- **引擎选择：** `--engine NAME`，默认取 `UT_DEFAULT_ENGINE`（默认 `yt`）。
  这个名字就是命令前缀；一个不认识的名字退出 1 并点名它（ARCHITECTURE.md §4）。
  **v1 不做 URL 嗅探** —— `uting` 永远知道引擎，因为搜索是它做的；
  而一个 agent 播放一个裸 URL 时会说出它是哪个引擎。嗅探（引擎声明自己的 URL 模式）推迟到
  第三个引擎让一份注册表变得值得为止。
- **点名正确动词的门臂**（那个被删掉的 wrapper 的拒绝语变成了这些）：
  `-n`/`-m`/`-M`/`-s` → "那是一个搜索标志 —— 用 yt-search"；`-J` → "那是一个引擎标志 ——
  试试 `yt-resolve --info -J`"；`--info`/`--transcript`/`--sub-lang` → "那是一个引擎动词"；
  `--get-url` → 取代了它的那个 `yt-resolve -j` 调用；其它任何不认识的长标志 → 播放标志的清单。

### 1.2 `<engine>-search` —— 一个引擎的第一半

- **它拥有：** 一个站点的查询路径、它自己的传输、它自己的 cookie 决定、它自己的结果整形
  与时长格式化器、它自己的门。**零播放、零生命周期逻辑。**
- **标志：** `-n -m -M -s -l -j -J --color -h -V`。位置参数：一个 QUERY。一个 URL 会被拒绝，
  并指向 `ut-play` —— 包括在 `--` 之后，那正是这项检查必须**重新施加**一次的地方，
  因为 `--` 停掉的是标志解析，不是参数校验。
- **信封：** `{status, engine, query, count, results[]}`，一行（§3）。
- **今天：** `yt-search`（yt-dlp）与 `bili-search`（curl + jq）。同一个信封，不同的传输 ——
  接缝是信封，不是它背后的工具（ROADMAP D11）。

### 1.3 `<engine>-resolve` —— 一个引擎的第二半

- **它拥有：** 句柄文法与 host 白名单、模式→格式表、cookie 决定、这个站点的只读动词、
  yt-dlp 错误词汇表。**cookie 决定同时是可查询的** —— 它是这一半里唯一一件调用方
  在没有句柄的情况下也想知道的事（`--auth`，见下）。
- **标志：** `-f -S -j -J --color -h -V` 加上它**有**的那些动词：`--info`（两个引擎都有）、
  `--auth`（两个引擎都有）、`--transcript --sub-lang`（只有 `yt-resolve`，D13）。
- **`--auth` —— 这一半里唯一不吃句柄的动词。** 它问的是**引擎**怎么配的，不是某个句柄
  怎么样，所以它自己的门与别的动词反着来：一个位置参数是用法错误（1），
  `-f`/`-S` 同样是（它不解析流），`-J` 也是（`-J` 是 yt-dlp 的原始记录，而它根本不跑
  yt-dlp）。它在**依赖门之前**作答，和 `-V` 一样 —— 一个报告"我怎么配的"的动词，
  不该需要它正在报告的那个工具装在机器上；散文形态连 `jq` 都不需要。
  信封见 §3。
- **行为：** AS-BUILT-engine.md §10。非本站 host → 用法错误（1）。
- **以"有没有"声明能力（D13）：** 一个引擎做不到的事，它就不为它准备动词。

### 1.4 `uting` —— 交互式终端 UI

- 命令面：`uting [--engine NAME] [-n N] [-m S] [-M S] [-s field] [-f audio|video|fast]
  [--volume N] [-p ROWS] [--color auto|always|never] [query]` —— 搜索整形的标志转发给
  `<engine>-search`；`-f`/`--volume` 是播放设置，每次播放都转发给 `ut-play`；`-p` 是每页行数；
  其余一律拒绝。`--volume` 只在启动时生效（没有运行时循环键，不像 `-f` 有 `v` ——
  见 ARCHITECTURE.md §26）。查询可选（缺了就提问）。要求 stdin 与 stdout 双双是 TTY，
  要求 `jq`，要求那些同级动词。
  `-f` 对着 `audio|video|fast` 校验：播放是 detached 的，而 `ascii`/`viz` 需要一个终端
  （AS-BUILT-player.md §9.2）。
  按键：方向键导航/翻页 · Enter 非阻塞播放 · `Tab`/`p` 在两个视图间切换 ·
  `Esc` 回到列表（在卡片里）· `Space` 暂停 · `[`/`]` 快退/快进 ∓10s · `9`/`0` 音量 · `s` 停止 ·
  `v` 循环模式（audio→video→fast）· `e` 切换来源（只有一个引擎时隐藏）·
  `l` 切换界面语言（en↔zh，任一视图）· `t` 循环配色家族（任一视图）·
  `n` 新搜索 · `m` 更多结果 · `o` 排序 · `/` 过滤 · `q` 退出 ·
  `a` 把当前聚焦行加入一个播放列表 · `b` 把一个已存播放列表打开为行来源 ·
  `h` 把收听日志打开为行来源。
  `a`/`b` 只在 `ut-playlist` 装了时出现（§1.5），`h` 只在 `ut-history` 装了时出现（§1.6）——
  跟单引擎安装下隐藏 `e` 是同一条规则。两者都**替换**屏幕上的行，且两者都是 **toggle**：
  打开一个存储的那个键把它关掉（再按一次 `h`、再按一次 `b`），
  从暂存的信封还原那次搜索而不是重跑那个查询，所以用户回去时看到的行就是他离开时的那些行。
  这个键在它自己的存储开着时会给自己换标签 —— 不印第二个键，`Esc` 不参与其中
  （AS-BUILT-tui.md §11 有这条规则，以及它背后那次一秒的测量）。
  `h` 不取名字 —— 日志只有一份 —— 并显示最新的 50 行。
  播放列表或日志在屏幕上时，那三个会**重新取数**的键 —— `m` `o` `e` —— 会说一声然后什么也不做；
  一切作用在行本身上的东西照旧。行各自带着自己的 `engine`，
  所以一份混了来源的清单，每一行都在产出它的那个引擎下播放。

### 1.5 `ut-playlist` —— 播放列表存储（durable，用户级，与引擎无关）

- **它拥有：** 用户级状态目录、播放列表文件布局、锁与原子写、条目记录（§3），以及状态错误枚举。
  **别的它一概不拥有：** 没有站点知识，没有播放，没有 `players/`，没有队列。
- **动词（每次调用恰好一个）：** `--ls` · `--show NAME` · `--add NAME` · `--rm NAME
  --index N` · `--del NAME` · `--rename NAME NEWNAME`。共享：`-l -j --color -h -V`。
  没有 `--new`：`--add` 按需创建。`--index` 从 0 开始，跟 `--show` 印出来的一致，
  并且只属于 `--rm`（选择器配上别的动词就是退出 1，跟播放器上的 `--id` 一样）。
- **位置参数：没有。** 每一个名字都挂在它自己的动词上，所以 `--` 之后的任何东西都是一个
  本意是 `ut-play` 的调用方，门会这么说。
- **输入 —— 一种形状，在 stdin 上（`--add`）：** JSON，三种形式任一：一个**搜索信封**
  （`<engine>-search -j` 原样）、这个命令自己的 **`--show` 信封**（于是一个列表能拷进另一个），
  或一个裸的**条目数组**。搜索信封那一种是重点：一条搜索**结果**不带 `engine` 字段，
  信封才带，所以只有整个包裹才能给条目打上产出它的引擎的标签。
  不认识的字段被丢掉；每个条目必须有 `engine` 与 `url`。
- **存储：** `$UT_STATE_DIR/playlists/<name>.json`，一个播放列表一个文件，`mkdir` 锁
  （`.lock-<name>`），temp+mv。名字**就是**文件名 —— 不做 slug，因为一个 slug 会让屏幕上的名字
  和磁盘上的名字变成两个事实。名字拒绝 `/`、控制字符与开头的 `.`，上限 64 个字符。
  **在一个大小写不敏感的文件系统上（macOS 默认），两个只有大小写不同的名字是同一个播放列表** ——
  接受并写进文档，而不是做归一化。
- **不是播放器的状态。** `players/` 在 `$TMPDIR` 里，随重启一起死；这个不会。
  队列（一个正在被消费的播放列表）留在播放器那边 —— 一个能挺过重启的队列**就是**一个播放列表
  （AS-BUILT-player.md §9.4）。

### 1.6 `ut-history` —— 收听日志（durable，用户级，与引擎无关）

- **它拥有：** 日志的文件布局、行的形状与它的长度上界。**别的它一概不拥有：**
  没有站点知识，没有播放，没有 `players/`，没有播放列表。它是用户级存储的第二半，
  也是唯一一个由程序而不是由人写的。
- **动词（每次调用恰好一个）：** `--ls [-n N]`（最新在前，默认 20，上限 10000）·
  `--record -`（stdin 上**一行**）· `--clear [--before DATE]`。共享：`-l -j --color -h -V`。
  `-n` 属于 `--ls`，`--before` 属于 `--clear`；任一个用在另一个动词上就是退出 1，
  跟 `--index` 在播放列表存储上遵守的是同一条规则。
- **位置参数：没有**，`--` 之后的任何东西都是一个本意是别的命令的调用方。
- **输入 —— 一行，在 stdin 上（`--record -`）：** 单个 JSON 对象。单数是契约，不是限制：
  下面那个免锁的追加只对**一次**写成立。字段是一个一个取的，从不合并，
  所以调用方碰巧带着的某个键（一条搜索结果的 `channel`）到不了磁盘。
  `engine` 与一个不含空白的 `url` 是必须的，`played_at` 必须是一个 ISO 时间戳，
  而 `reason` 必须是 PLAYBACK 枚举（§3）的成员或 null。
- **存储：** `$UT_STATE_DIR/history/<YYYY-MM>.jsonl`，只追加，一次收听一行。
  **这是整套套件里唯一一个不取锁的写** —— `>>` 是 `O_APPEND`，而一行在 `PIPE_BUF` 以内就整行落地 ——
  这也正是为什么**每一行都必须待在 4096 字节以内**：标题在 UTF-8 边界上截到 200 字节，
  然后整行被**量一遍**，字段按顺序丢（title、id、url）直到装得下。信封里的 `truncated` 报告这件事。
  按月分片让"清掉旧的东西"是一次 `rm` 而不是一次重写。
- **谁写它：** 一个 detached 的 `ut-play` 子进程，每条曲目一次，无论是什么结束了这条曲目
  （§1.1，`UT_HISTORY`）。`ut-history` 从不播放，`ut-play` 从不打开日志文件。
- **不是死亡记录。** `players/dead/` 只装失败、有界、在 `$TMPDIR` 里、重启即无；
  这一个是每一条曲目、无界、且 durable。两者在同一瞬间被写下，是同一条规则的两面
  （AS-BUILT-player.md §9.2）。

## 2. 门模型 —— 一层，八个自己把门的动词

**没有 wrapper 层。** 每个动词只接受它自己的命令面，遇到跨界标志就把调用方指向正确的那把工具；
既然调用方与实现之间已经不再坐着任何东西，这就是让那些契约互不重叠的东西。

```
   <engine>-search                            ut-play
   ─────────────────────────────────         ─────────────────────────────────
   允许： -n -m -M -s -l -j -J               允许： -f -S -d -j -l --engine --volume
          --color -h -V                             --status --stop --set-volume
                                                    --id --all --color -h -V
   拒绝（→ "use ut-play"）：                  拒绝（→ "use yt-search"）：
          -f -d --detach --status                   -n -m -M -s
          --stop --set-volume --id --all      拒绝（→ "use <engine>-resolve"）：
   拒绝（→ "use <engine>-resolve"）：                --info --transcript --sub-lang
          --info --transcript -S                    --get-url  -J
          （-S 排的是流的格式；一次搜索
            什么也没解析）
   位置参数：一个 QUERY（拒绝 URL）          位置参数：一个 HANDLE（拒绝空白）
   默认：没有 -l/-j/-J 就注入 -l             句柄是必须的，除非
                                             --status/--stop/--set-volume
   两者共有：`--` 结束标志；位置参数检查在它之后**重新施加**一次

   ut-playlist
   ─────────────────────────────────
   允许： --ls --show --add --rm --del --rename --index -l -j --color -h -V
   拒绝（→ "use ut-play"）：       -f -d --detach --status --stop --set-volume --all
                                   --engine，以及**任何**位置参数（包括 -- 之后的）
   拒绝（→ "use <engine>-*"）：    -n -m -M -s --info --transcript
   输入：`--add` 从 stdin 读 JSON；完全没有位置参数

   ut-history
   ─────────────────────────────────
   允许： --ls --record --clear -n --before -l -j --color -h -V
   拒绝（→ "use ut-play"）：       -f -d --detach --status --stop --set-volume --pause
                                   --resume --seek --seek-to --queue --enqueue --next
                                   --id --all --engine，以及**任何**位置参数（包括 -- 之后的）
   拒绝（→ "use ut-playlist"）：   --add --show --rm --del --rename --index
   拒绝（→ "use <engine>-*"）：    -m -M -s -S --info --transcript
   输入：`--record` 从 stdin 读**一行** json；完全没有位置参数
```

**`--` 停掉的是标志解析，不是参数校验。** 每个动词都在它自己的 `--` 排空循环里
**重新施加**一次它的位置参数检查，因为那项检查就是这个动词存在的全部意义。这一课是付过学费的：
`yt-play -- "some query"` 曾经绕过了 `yt-play "some query"` 会给出的那个"这不是一个 URL"的拒绝，
一路走到 core，跑了一次**搜索** —— 印出一份散文列表，或者在 `-j` 下印出一整个搜索信封，
而这个动词的契约说的是它播放 URL。一个只守着不带 `--` 的那种拼法的门，不是门。
这条规则活得比教出它的那个 wrapper 更久：`ut-play` 对 `--` 之后的任何东西施加空白测试，
而 `<engine>-search` 对它之后的每一个 token 施加 `reject_url`。

**为什么门不再是一个层了（D7，已退役）。** 老模型是一个 core 加两个 wrapper，
而门就是 wrapper 存在的理由：core 实现了一个宽的多态命令面（`yt "query"` 搜索、`yt <url>` 播放），
wrapper 的活是保证调用方到达的是哪一半。一旦搜索搬去了 `<engine>-search`、
抽取搬去了 `<engine>-resolve`，播放器就只剩下恰好一个动词 ——
没有别的操作可供一次绕过去够到，也就没剩下什么好让一个层去守。
那个 wrapper 贡献过的、值得留下来的东西是它的**错误文本**，而它的那些门臂正是它变成的东西（§1.1）。

**为什么 `uting` 组合这些动词，而从不碰它们的内部（D8）。** `fetch_json` 解析搜索信封，
而 `<engine>-search` 的 URL 拒绝正是让"`-j` = 搜索信封"这件事无条件成立的东西 ——
一个粘进 TUI 的 `n`（新搜索）提示里的 URL，除了变成一次被拒绝的搜索之外不能变成任何东西。
TUI 还**显式**传 `--engine`，**取自信封自己的 `engine` 字段**，从不让 `ut-play` 的默认值来决定：
装了两个引擎时，那个默认值会把第二个引擎的 URL 送给第一个引擎的 resolver，
而自 ROADMAP D12 起那是一个硬用法错误，不再是从前那种悄无声息的贴错标签。
D8 唯一被批准的例外是那个 mpv socket（AS-BUILT-player.md §9.3），
播放器把它的路径发布在 `-d -j` 信封里，正是为了让一个客户端可以用它。

## 3. 数据契约（JSON schema）

搜索信封（`<engine>-search -j`）：
```json
{ "status":"ok", "engine":"yt", "query": "lofi", "count": 25,
  "results": [ { "id":"…", "title":"…", "url":"https://www.youtube.com/watch?v=…",
    "channel":"…", "duration":213, "duration_fmt":"00h:03m:33s",
    "view_count":12345, "live_status":"not_live" } ] }
```
`-j` = 上面那 8 个结果字段（高信噪比，比原始那条约 23 字段的 yt-dlp 记录小约 4 倍）。
`-J`/`--json-full` = 同一个信封，`results` 里装每一个原始字段。
时长未知时（一路直播）`duration` 与 `duration_fmt` **一起是 `null`**；`view_count` 也可以是 `null`。
失败时信封改为 `{status:"error", engine, query, count:0, results:[], reason}`，
`reason` 用的是与播放相同的那个枚举，退出码是 2+（AS-BUILT-engine.md §7 / 本文 §4）。

- **`engine` 是每一个引擎信封的必需键** —— search、resolve、`--info`、`--transcript`，
  以及它们各自的错误形状。它是那个同时也是命令前缀的 token，
  于是一个手里拿着结果的调用方靠字符串拼接就够到了对应的 resolver（`yt` → `yt-resolve`），
  而 `uting` 不需要一张映射表就能传 `ut-play --engine <那个值>`。
  **这就是 host 白名单保护的那个字段**（AS-BUILT-engine.md §10，ROADMAP D12）：
  一个接受了别的站点的 URL 的 resolver，会在这里印出它自己的名字，那条路由声明就成了假的。
  每个引擎都从**一个常量**（`ENGINE_NAME`）印出自己的名字，而不是推导出来，
  所以信封和文件名不可能互相矛盾。
- **`status` 同样是必需键**，`"ok"` 或 `"error"` —— 这样一个调用方在看任何别的东西之前，
  可以先在一个字段上分支，套件写出的每一个信封都如此。
- **两个键都是引擎级的，不是 YouTube 级的：** `bili-search` 印出一模一样的信封，
  只是 `engine:"bili"`。一个漏掉其中任一个的第三引擎，将与一次被截断的读无从分辨。

解析信封（`<engine>-resolve -j -f MODE -- <handle>`）：
```json
{ "status":"ok", "engine":"yt", "id":"dQw4w9WgXcQ",
  "url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "title":"…", "duration":213, "mode":"audio", "format":"ba/b",
  "stream_urls":["https://rr2---sn-….googlevideo.com/videoplayback?…"],
  "http_headers":{"User-Agent":"…","Accept-Language":"…"},
  "retried":false }
```
这就是播放器用来表达"我在放什么"的全部词汇，每一个键都在承重：

- **`stream_urls` 是一个数组，视频在前。** 单流时一个元素；引擎的格式把一条纯视频轨与一条纯音频轨
  合并时是两个，此时第 1 个元素是音频。播放器用 mpv 的 `--audio-file` 把它们接起来 ——
  那正是 `ytdl_hook` 从前免费做掉的 EDL 合成（AS-BUILT-player.md §8.1）。
- **`http_headers` 是必需键**，可以是 `{}`。它堵上了老的 `--get-url` 留下的那个洞：
  在一个检查 `Referer` 或钉死 `User-Agent` 的 host 上，一个光秃秃的流 URL 不足以取到东西，
  而播放器无从把它们发明出来。一个引擎**不得**在这里返回凭据头 ——
  播放器把这些放在 mpv 的 argv 上，那是 `ps` 读得到的地方。
- **`format`** 是引擎实际用掉的那个格式字符串。播放器把它原样记进播放器状态文件，从不去读它：
  `bv*+ba/b` 是一句 yt-dlp 表达式，而播放器不懂那门语言。
- **`retried`** = 引擎回落到了一个匿名 client（AS-BUILT-engine.md §8.2）。
  播放器把它转手进播放信封的 `retried`；它不再自己观察这件事。
  **它不是一个登录裁决**：`retried:false` 只说明带 cookie 那次调用没有出错，
  不说明那份登录被站点认了 —— 见下面 `--auth` 那条同样的界线。
- **`engine`** = 那个同时也是命令前缀的 token，于是一个手里拿着搜索结果的调用方靠拼接
  就够到了对应的 resolver（`yt` → `yt-resolve`）。
- 失败 → `{status:"error", engine, url, mode, reason}`，`reason` 用与播放相同的枚举，
  且**退出 2+** —— 下限抬到 2，因为一个视频不可用时 yt-dlp 退出 1，而 1 是留给用法错误的。

auth 信封（`<engine>-resolve --auth -j`）—— 一行，不发包，也不跑 yt-dlp：
```json
{ "status":"ok", "engine":"bili", "auth":"cookie",
  "cookie_browser":"chrome", "profile_found":true }
```
- **`auth`** ∈ `cookie | anonymous` —— 调用方要渲染的那个摘要。
  它 `== "cookie"` 当且仅当 `cookie_browser != "none"` **且** `profile_found`。
- **`cookie_browser`** = `<ENGINE>_COOKIE_BROWSER` 的原值（`chrome`、`safari`、`none`…），
  引擎名大写就是那个变量名（§5、§6）。
- **`profile_found`** = 那个浏览器的 profile 目录在这台机器上在不在。
- **这个信封承诺的是"发不发"，不是"认不认"。** cookie 送到了、站点却仍然只给匿名档位，
  是一个真实且常见的状态（本机实测 2026-08-26：从 chrome 提取到 3159 个 cookie，
  B 站依然只供匿名音频档，因为那个 profile 不是大会员）。
  证明后者需要一次鉴权往返 —— 刻意不在这个动词里，也刻意不在这个信封里
  （ROADMAP D16）。要那个的话，升级路径是把网络调用放到一个 `--auth --probe` 后面，
  让这个信封的含义保持不变。

播放状态（`ut-play -j -- <handle>`）—— 播放器自己的信封，也是唯一一个没有 `engine` 键的：
播放器与站点无关，它回声出来的那个句柄就是别人给它的那个（ARCHITECTURE.md §4）。
```json
{ "status":"ok"|"error", "url":"…", "mode":"audio",
  "exit_code":0, "reason":null, "retried":false }
```
`reason` 枚举：`forbidden | unavailable | format_unavailable | network |
stopped_by_user | unknown | null(ok)`。**`network` 除了连通性之外也涵盖 HTTP 429 限流**：
两者都是可重试的，而那是调用方在它上面唯一会走的分支，
所以在一个三个动词都在发布的契约里，429 没有挣到一个新的枚举成员。
它是刻意**不**跟 `forbidden` 归在一起的 —— 403 说的是这份凭据永远不行，429 说的是现在不行。
把这件事顶到台面上来的是 `--transcript`（它每种语言取一个字幕文件，几次调用之内就能踩到
YouTube 的限流器），但播放与搜索一直都够得到它，只是报成 `unknown` ——
那个调用方唯一无法据以行动的 reason。

**枚举是那个共享的事实；分类器不是。** 自 B-2 起它有三个读者，而它们刻意住在不同的文件里：
`yt-search` 与 `yt-resolve` 各自带一个懂 extractor 措辞的 `classify_yt_dlp_error`
（*video unavailable*、*requested format*、*sign in to confirm*），
而 `ut-play` 带一个小得多的、只懂 mpv 的 `classify_playback_error` —— 传输失败与 rc 130。
一次失败的解析由那个读得懂措辞的半边分类**一次**，播放器复述那个判决，
而不是从散文里把它重新推导一遍。**这三者中的任何一个都不得添加本节尚未列出的成员。**

播放列表存储（`ut-playlist`）—— **条目**是那条 durable 的记录，
它是一条搜索结果的子集，外加把信封的 `engine` 折进来：
```json
{"engine":"yt","id":"a1","url":"https://…","title":"…","duration":213,"added_at":"…"}
```
`engine` + `url` 恰好就是 `ut-play --engine E -- URL` 的两个参数，所以**一条存下来的记录就是一次调用** ——
任何地方都不需要映射表。`channel`、`view_count` 与 `live_status` 是**刻意不存**的：
播放不需要它们，而它们会过期成错误答案。`duration` 可以是 null（一路直播），跟搜索信封里一样。

磁盘上，一个播放列表一个文件：
```json
{"schema":1,"name":"chill","created_at":"…","updated_at":"…","count":2,"items":[…]}
```
`schema` 从第一个版本起就盖上去：这是一个会在用户磁盘上待很多年的文件，
而一次没有版本字段的格式变更，只能靠猜来迁移。

信封（`-j`，各一行）：
```
   --ls     : {status:"ok", count, playlists:[{name, count, updated_at}…]}
   --show   : {status:"ok", name, count, items:[item + {duration_fmt}…]}
   --add    : {status:"ok", name, added, count}
   --rm     : {status:"ok", name, removed, count}
   --del    : {status:"ok", name, deleted:true|false}     false = 它本来就已经不在了
   --rename : {status:"ok", name, from}
   error    : {status:"error", name:NAME|null, reason}
```
`duration_fmt` 是**读的时候导出来的，从不存下来** —— 存一份副本就是关于同一个数字的第二个真相。
它被印出来，是为了让一个条目跟一条搜索结果逐字段行兼容，
而那正是让 `uting` 用同一个装载器渲染一个播放列表的东西。

收听日志（`ut-history`）—— **同一条**条目记录，加上一次收听有、而一个列表条目没有的那四个字段：
```json
{"schema":1,"engine":"yt","id":"a1","url":"https://…","title":"…","duration":213,
 "played_at":"…","ended_at":"…","seconds":97,"reason":null}
```
`$UT_STATE_DIR/history/<YYYY-MM>.jsonl` 的一行，且**在 4096 字节以内** ——
那个免锁追加所倚仗的前提（§1.6）。`reason` 是 PLAYBACK 枚举，或者 **null，
而那正是一条放到自己尽头的曲目长的样子**；一条被跳过或被停掉的是 `stopped_by_user`，
而 `seconds` 是那个把 0:05 的一次跳过与 3:20 的一次停止区分开来的东西。
`played_at` 决定分片文件的名字。`added_at` 按设计不存在：一次收听是什么时候发生的，就是 `played_at`。

信封（`-j`，各一行）：
```
   --ls     : {status:"ok", count, items:[row + {duration_fmt, seconds_fmt}…]}
   --record : {status:"ok", recorded:1, month:"2026-08", truncated:false}
   --clear  : {status:"ok", removed:N, before:DATE|null}
   error    : {status:"error", reason}
```
两个 `_fmt` 字段都是读的时候导出来的，理由跟 `--show` 那个一样；
结果是 `ut-history --ls -j` 可以直接管进 `ut-playlist --add` 与 `ut-play -d --queue -`，
中间不需要任何字段映射 —— `.items` 那个信封正是那两位已经在读的形状。

**状态错误枚举是它自己的一套，且刻意不是播放那一套：**
`not_found | exists | invalid_name | invalid_input | locked | corrupt`。
一个文件存储里的任何东西都不可能是 `format_unavailable`，
而去加宽一个另外三个读者都在其上分支的分类学，是那种不对的共享。
`corrupt` 涵盖"这个 build 读不了那个文件"的两种形状：解析不了的 JSON，
以及一个比这个 build 所理解的更新的 `schema`
（这个字段每次 add 都写、每次读都**检查** —— 一个没人读的版本号什么也买不到）。
两种输出模式下散文都走 stderr；信封只在 `-j` 下走 stdout，
跟一个引擎报告一次抽取失败的方式一模一样。

生命周期 / 解析：
```
   -d       : {status:"started", id, pid, url, mode, started_at, title:null, sock, log}
              sock/log 是交出去的，好让一个客户端永远不必自己重建状态目录的布局
   --status : {status:"players",
               players:[{id,pid,url,mode,volume,paused,position,duration,title,started_at,
                         queue:{pos,len,next}}…],
               failed:[{id,url,mode,started_at,ended_at,exit_code,reason}…]}
              没有在放 / 没有失败时是空数组（仍然退出 0）
              detach 之后的头一两秒 title 是 null：解析是那个 detached 的**子进程**做的
              （父进程必须在毫秒级返回），它一拿到解析信封就把 `title` 与 `format`
              补进它自己的那条记录
              volume、paused、position 与 duration 是**一次往返**里从播放器的 socket 上
              实时读来的（AS-BUILT-player.md §9.3）。volume 回落到记录下来的启动值 /
              --set-volume 值；另外三个在 socket 问不到、或播放器答了 null 时是 null ——
              null 是"问不到"，**不是** false/0。position 与 duration 是整数秒，
              在 mpv 开始解码之前是 null（冷启动约 8s）；一路直播的 duration 一直是 null。
              一个活着的播放器上 queue 永远不是 null：每一次 detached 启动都写一个，
              而一个单独的句柄是一个长度为 1 的队列（AS-BUILT-player.md §9.5）。
              它是从播放器自己的队列文件上读的，不是从 socket 上 —— mpv 一次只被递一个 URL，
              从来不知道有一个列表。`next` 是 pos **之后**的那一条，最后一条曲目上是 `null`。
              url 与 title 跟着**曲目**走：子进程每解析一次就补一次它自己的记录，
              所以十分钟后取的一次 --status 描述的是**此刻**在放的东西。
              failed[] 是墓碑列表 —— 那些**自己**死掉的播放器，最新在前，至多 8 条，
              不超过一小时（AS-BUILT-player.md §9.2）。reason 是那个共享的播放枚举。
              一个正常结束或者被 --stop 掉的播放器永远不在里面，
              所以这个数组是一份**错误记录**，不是收听历史那个功能（ROADMAP D14/P4）——
              后者有它自己的 durable 存储；这一个住在 $TMPDIR 里且有界。
   --set-volume : {status:"ok", id, volume}          （经 mpv IPC socket 实时调整）
                | {status:"not_playing"}             （没有目标；退出 4）
                | {status:"ambiguous", reason:"multiple_players", players:[{id,pid,title,url}…]}  （退出 4）
                | {status:"error", reason:"ipc_failed"}   （socket 死了或不在；退出 4）
   --pause  : {status:"ok", id, paused:true}    --resume : {status:"ok", id, paused:false}
   --seek   : {status:"ok", id, position:<整数秒>}          --seek-to : 同一形状
              这四个都原样采用上面那**三种** not_playing / ambiguous / ipc_failed 形状，
              理由也一样 —— 一套目标解析，一套退出分类学。
              `paused` 与 `position` 是在命令成功之后从 socket 上**读回来**的，
              从不是从别人要求的值算出来的：mpv 会把一次 seek 夹在文件两端，
              而要求的数字与真正到达的数字，恰恰在调用方最需要真相的时候不一样。
              如果只是那次读回失败了，两者都是 null —— 动词还是生效了，所以它不是一个错误。
              seek 过了尽头**不是**错误：mpv 夹住，信封报告它落在哪儿，退出 0。
              一路直播没有可 seek 的时间线，mpv 会拒绝；那次拒绝浮现为 ipc_failed（退出 4），
              而不是播放器从一个 null 的 duration 做出的一次预测 —— 那会是它并不持有的站点知识。
   --enqueue: {status:"ok", id, added:<n>, queue:{pos,len,next}}
   --next   : {status:"ok", id, queue:{pos,len,next}}
              两者都采用上面的 not_playing / ambiguous 形状 —— 同一套目标解析、
              同一套退出分类学 —— 但永远不会 ipc_failed：一个队列是播放器在磁盘上的状态，
              不打开任何 socket。它们自己的两种失败是
                {status:"error", reason:"queue_empty"}   --next 而这条曲目之后什么也没有
                {status:"error", reason:"queue_failed"}  队列文件写不下去
              两者都退出 4，两者都是格式良好、却没有生效的调用。`queue` 是写完之后从文件上
              **读回来**的，从不预测 —— 跟 --seek 对 `position` 遵守的是同一条规则：
              --next 是在**父进程**里挪动位置、然后才给子进程发信号，
              所以信封报告的是一个已经落在磁盘上的队列。
   --stop   : {status:"stopped", id, stopped:bool}   （单一目标）
            | {status:"stopped", scope:"all", stopped:bool}   （--all）
            | {status:"ambiguous", …}                （2 个以上播放器且没有 --id；退出 4）
   （--get-url 在 B-3 退役了：解析出一个流 URL 正是一次裸的 `yt-resolve` 调用**本身**，
    而播放器再发布一个它的拼法，就是一份契约有了两个名字。
    下面的 --info / --transcript 是 `yt-resolve` 的动词 —— 播放器不转发它们。）
   --info   : {status,engine,id,title,url,channel,uploader,upload_date,duration,duration_fmt,
              view_count,like_count,live_status,description,chapters} ; -J = 原始记录
              chapters = [{start_time,end_time,title}] | null ; 错误 → {status,engine,url,reason}
   --transcript : {status:"ok", engine, id, url, lang, is_auto, chars, segment_count, text}
              -J = **同一个**信封再加 segments:[{start,duration,text}…]（秒）——
              一个严格超集，跟搜索的 -J 之于它的 -j 是同一种关系
              （一个加宽的调用方永远不会丢掉一个它本来就在读的字段）。
              text 是那些 segment 文本用空格接起来的结果 —— 与默认（散文）模式印出来的
              **同一个**字符串，所以两种输出模式不可能漂移。
              `segments` 不在 -j 里，是因为它是同样的词**两遍**：在一条 444 cue 的自动轨上，
              完整信封是 52,732 字节，其中 `text` 是 16,916、`segments` 是 35,647 ——
              后者带着一模一样的文本外加它的时间戳。-j 是 17,074 字节 —— 小 3.1 倍，
              对这个动词存在的理由（把这个总结一下）没有丢掉任何信息
              （ARCHITECTURE.md §22，token 效率）。`chars` 与 `segment_count` 让精瘦的那种形式
              保持自描述：一个调用方能给上下文做预算，并且不必去取就知道 -J 会多出什么。
              原始的 json3 文档刻意**不是** -J 返回的东西：它不带 status/lang/is_auto，
              所以加宽反而会**丢**字段 —— 那是这套套件里 -J 契约在别处从不做的一件事。
              lang 是实际被写下来的那条轨，也就是这个视频恰好有的那条 --sub-lang 优先链的第一项。
              is_auto = 这条轨来自 YouTube 自动生成的字幕，而不是一条人工撰写的；
              这是从印出来的人工字幕字典判定的，不是从文件判定的（手工与自动落在同一个名字下）。
              错误 → {status:"error", engine, url, reason}，退出 1，与 --info 一致
              （engine 跟别处一样是必需的）。reason 是那个共享枚举再加上
              `no_subtitles_available`，后者也涵盖一条解析出零条可用 cue 的轨
              （一份空的转录是一次落空，不是一次空的成功 —— 一个被递了 {"text":""} 的调用方
              会去总结一段沉默）。
```

**队列的输入是 stdin，三种形状** —— 跟 `ut-playlist --add` 接受的那三种一样，理由也一样：
一条搜索结果不带 `engine`（那个字段在**信封**上），所以只有接下整个信封才能给一个条目
打上它来自哪个来源的标签。`--queue -` 与 `--enqueue -` 接受一个裸的条目数组、
一个 `ut-playlist --show -j` 信封（`.items`），或一个搜索信封（`.results`）；
一个条目是 `{engine, url, title?, duration?}`，而 `--engine` 只是给一个自己没有 engine 的条目
兜底的，所以**一个**队列可以混来源。关于这份 payload 的其它一切都是用法错误（**1**），
并且是在调用方自己的 shell 里、在寻址到任何播放器之前就抛出来的：解析不了的 JSON、
三种形状都不是、零个条目、一个 url 里带空白、一个不匹配 `[a-z0-9][a-z0-9_-]*` 的引擎名。
url 的检查不会比 argv 上的一个句柄更进一步 —— 哪些 id 是好的属于引擎知识 ——
但引擎**名字**在这里校验，因为它会在一个 detached 的子进程里变成一个命令名，
而在那里一次 `die` 只够得着一份日志。

**一个队列是即时解析的，一次一条曲目。** 一个流 URL 几小时就过期，
所以一个在入队时就解析好的队列会在放到一半时 403；代价是曲目之间的一个空档（那次引擎往返），
而这个设计决定是 AS-BUILT-player.md §9.5。有一个后果是契约性的：
一个解析失败的排队条目**不会**弄死播放器。队列往前走，那条曲目在 `failed[]` 里拿到它自己的墓碑，
键是 `<id>-q<pos>` —— 一条没放成的曲目，跟一个没放成的播放器是同一种形状，
于是一个读 `failed[]` 的调用方看到的是一个有名字的缺口，而不是一个无声的缺口。

磁盘上（运行时状态，随播放器一起死 —— 它不是一个播放列表）：
```json
{"schema":1,"pos":0,"items":[{"engine":"yt","url":"https://…","title":null,"duration":null}]}
```

**为什么 `--transcript` 是一次 yt-dlp 调用。** `--print` 蕴含 `--simulate`，
而一个在 simulate 的 yt-dlp 不写任何字幕文件 —— 所以 `--no-simulate` 才是那个让**单次**调用
既写下字幕、又报出描述它们所需的元数据的东西。（`--dump-json` 带着同样的蕴含，
这正是它不能当这里的载体的原因：它是那个看起来很自然、却悄无声息地根本不产出字幕的配方。）
印出来的字段只有 `%(subtitles)j` —— `%(automatic_captions)j` 在一个热门视频上，
把 YouTube 的机器翻译算进去之后能跑到 940 种语言 / 3.2 MB，
而人工字幕字典的那些键已经回答了 `is_auto`。字幕以 `--sub-format json3` 请求，
好让清洗保持是一个 jq 程序：json3 把时间戳作为结构化字段带着，而 VTT/SRT 会需要一个时间线解析器。
三种形状被丢掉 —— 开头那个窗口定义事件（没有 `segs`）、自动字幕的 rollup 事件
（`aAppend`，它唯一的 seg 是 `"\n"`），以及内联样式标记 —— 而这三种都从同样的两道过滤里掉出来：
先清洗文本，再丢掉空的。在**清洗后的文本**上过滤而不是在 `aAppend == 1` 上过滤是刻意的：
它移除了观察到的每一个 rollup 标记，同时保住了任何一个确实载着词的 `aAppend` 事件。

**错引擎的句柄是一个用法错误，不是一个信封。** `<engine>-resolve` 拿到一个 host 不是它自己站点的 URL 时
退出 **1**，往 stderr 写一条消息，且**完全不写信封** —— 什么也没尝试、什么也不可重试，
所以它跟 `--engine nope` 是同一类，绝不能与一次调用方也许会重试的抽取失败（2+）混为一谈。
这是对每一个引擎的契约，现在的和将来的：host 白名单是每个引擎一份显式清单
（AS-BUILT-engine.md §10），从不是子串匹配。裸 id 那条路是同一条规则的另一个方向 ——
一个不匹配这个引擎的形状的 id 同样是 1。

**一个信封，一行。** 套件写到 stdout 的每一份 `-j` / `-J` payload 都是单行 JSON ——
search、resolve、`--info`、`--transcript`、`-d`、`--status`、`--stop`、`--set-volume`，
以及上面的每一种错误形状。那正是让输出可以当 NDJSON 用的东西：
一个调用方读一行、解析它、就完了，不需要流式解析器，也不需要数花括号。
它同样让 `-J` 在形状上、而不只是在字段上，是 `-j` 的**严格超集**。

这条规则被那两个最老的读动词违反了很久。搜索在 `-j -n 3` 下印 26 行、`-J` 下印 76 行，
`--info -j` 印 16 行，那个解析动词（当时拼作 `--get-url`）也是漂亮打印的，
而 `--status` 只在播放器列表**为空**时才是紧凑的 —— 一旦有一个播放器存在它就开始漂亮打印，
也就是恰恰在有人在轮询它的时候。这里每一个都是一句裸 `jq`，
而那些生命周期动词一直用的是 `jq -nc`；修法是在五个点上加 `-c`
（`emit_search_json` ×2、`resolve_info`、`emit_stream`、`--status` 的那个 `jq -s`）。
`players/` 下的状态文件**不**受这条规则管，继续保持漂亮 ——
它们是一份被 jq 读的磁盘记录，不是一个信封。

## 4. 退出码、TTY、依赖

```
   0    成功；也包括 --status/--stop（永远）；130 被归一化（SIGINT；干净的 q 本来就退 0）
   1    用法/校验错误（die）、一个动词的标志门拒绝、uting 的非 TTY 拒绝、互相冲突的动作、
        没有句柄（D3）、一个里面带空白的句柄、--id/--all 用在生命周期动词之外、
        -d 配上一个动作或配上 -f ascii|viz、
        一个不带符号的 `--seek` 值（`--seek 30`）或一个负的 `--seek-to`、
        一份这个进程用不了的队列 payload（`--queue`/`--enqueue`：坏 JSON、三种 stdin 形状
        都不是、没有条目、url 里带空白、坏的引擎名）—— 在**父进程**里就拒了，
        所以一份畸形的队列永远到不了一个播放器，
        `--queue` 而没有 `-d`、或配上一个动作、或 argv 上带了句柄、
        一个不认识的 --engine、一个 host 不是这个引擎的 URL（AS-BUILT-engine.md §10 / 本文 §3）、
        --info / --transcript 取数失败（含 no_subtitles_available）
   2+   传播上来的 yt-dlp / mpv / HTTP 失败（播放、resolve -j、**搜索**失败 ——
        搜索即使 yt-dlp 退出 1 也报 2，好让一次工具失败永远不会与 1 混淆）。
        一个引擎解析不了的句柄落在**这里**，不是落在 1：播放器判断不了一个 id 的形状，
        所以"坏 id"是一个抽取结果（ARCHITECTURE.md §6）。
   4    --set-volume / --pause / --resume / --seek / --seek-to / --enqueue / --next /
        --stop：没有生效 —— 没有那个播放器、没有播放器、目标有歧义，或 mpv IPC 失败；
        对那两个队列动词还包括 `queue_empty`（--next 而当前曲目之后什么也没有）与
        `queue_failed`（队列文件写不下去），这两个是唯一从不牵涉 socket 的。
        -j 的 status/reason 说明是哪一种。这个切分就是重点：一次**畸形**的调用是 1，
        且永远到不了一个播放器（`--seek 30`）；一次格式良好、mpv 却不肯做的调用是 4
        （`--seek +30` 而什么也没在放）。
        与 1（用法）和 2+（传播上来的播放器失败）都不同。--stop 把"什么也没在放"
        当作幂等的成功（退出 0）；只有歧义才是退出 4。
        **ut-playlist 也用它**，含义相同 —— 调用是格式良好的，而存储答不出来：
        `locked`（被另一个写者持有；它宁可失败也不做无锁的写，因为这个存储是 durable 的，
        而一次无锁的写可能把用户刚加进去的东西丢掉）、`not_found`（一个点名了不存在的
        播放列表的动词）、`exists`（--rename 到一个已被占用的名字），以及
        `corrupt`（一个这个 build 读不了的文件）。1 留着表示它在这套套件里别处表示的东西：
        **调用**本身是畸形的 —— `invalid_name`、`invalid_input`（坏的 stdin、
        一个越界的 --index）。--del 一个不存在的播放列表是幂等的成功（0，`deleted:false`），
        跟什么也没在放时的 --stop 是同一条规则。

   TTY  ：uting 要求 stdin 与 stdout **双双**是 TTY（AS-BUILT-tui.md §11）。
          别的动词一律不需要 —— 每一个都在输入为空时报错，而不是提问（D1/D3）。
   依赖 ：它们现在是**按文件**分的，这正是那次拆分的意义所在 ——
          ut-play      ：要播放需要 jq + mpv；--status/--stop 只需要 jq
                         （--status 会机会性地用 nc 做那次实时读，没有 nc 就降级成
                         记录下来的 volume 加三个 null）；每一个 socket 动词
                         （--set-volume、--pause、--resume、--seek、--seek-to）
                         需要 jq+nc（nc 是惰性把关的，好让一次普通播放永远不索要它）。
                         那些队列动词（--queue、--enqueue、--next）只需要 jq：
                         一个队列是一个文件，而 --next 是用一个**信号**够到播放器的。
                         它**不**需要 yt-dlp，也不需要 curl。
          yt-search / yt-resolve / bili-resolve ：yt-dlp + jq。curl 是 yt-resolve 的一个
                         **可选**软依赖，用于那次 client 探测（AS-BUILT-engine.md §8.2）。
          bili-search  ：curl + jq —— curl 在这里是**必须**的；它就是传输。
          uting        ：jq，加上它组合的那些动词。ut-playlist 是**可选**的 ——
                         它不在，那两个播放列表键就这么说，别的什么也不变。
          ut-playlist  ：只要 jq。没有网络，没有 yt-dlp，没有 mpv。
          ut-history   ：只要 jq。同上，并且对播放器是**可选**的：PATH 上没有它，
                         什么也不记录、什么也不说（一项能力是靠"在那儿"来声明的）。
                         uting 的 h 键只在它在时才画出来。
          BSD 的 `nc -U` 在 macOS 上是原装的；Linux netcat 的 `-U` 缺口是一个已知的、
          有记录的限制（ARCHITECTURE.md §26 / 脚本注释）。
   -V   ：每一个入口点都在**任何**依赖门之前回答它，读 VERSION 并印出它自己的名字 ——
          为了知道你的版本号而需要装着 yt-dlp 是本末倒置的，
          而八个可执行文件不能有互相矛盾的余地（ARCHITECTURE.md §4）。
          断言是对 shell/ 下每一个有 shebang 的文件做的，不是对一份名字清单做的。
```

## 5. 配置面

按次的选择是标志；一次设定的调校是环境变量 —— 刻意留在标志之外，
好让每个动词的标志面保持窄。

```
   标志（每次调用）：  -n -m -M -s -f -S -l -j -J -d -h -V --color --theme --engine
                      --detach --status --stop --info --transcript --sub-lang
                      --set-volume --pause --resume --seek --seek-to --queue --enqueue
                      --next --id --all --volume
   环境变量（一次设定）：
                      UT_STATE_DIR  （默认 ${XDG_STATE_HOME:-~/.local/state}/uting）=
                        **用户级**的、durable 的状态根 —— 今天是 `playlists/`。
                        与播放器在 ${TMPDIR}/uting-$(id -u) 里的运行时状态截然不同 ——
                        后者重启即抹掉，任何用户亲手建起来的东西都不得住在那里。
                        用 XDG 而不是 ~/Library/Application Support，是因为用户面是一个终端，
                        而一次 Linux 移植不该需要第二套布局。
                        今天是 `playlists/` 与 `history/`。它不是一个方便旋钮：
                        tests/ 里的两个套件都设它，不设它它们就会写进用户真实的播放列表
                        和真实的收听历史。
                      UT_HISTORY          （默认开；0 = 关）= 一个 **detached** 播放器
                        是否给收听日志每条曲目写一行。只有 ut-play 在子进程里读它。
                        默认开，是因为一份出厂即关的历史不是历史 ——
                        在这个功能产出过一行之前，没有人会去找那个旋钮。
                        重开条件：一个共享账号 —— 那时"这个登录听了什么"不再是一个人的记录。
                      UT_DEFAULT_ENGINE   （默认 yt）= --engine 默认到哪个引擎。
                        **ut-play 与 uting 都读**，刻意是同一个变量：
                        一个已经挑过一次默认来源的用户，不该每个面再挑一次。
                        名字不在时，uting 回落到第一个装上的引擎。
                      YT_COOKIE_BROWSER   （默认 chrome = 登录开着；"none" = 只匿名）
                        —— 由每个**引擎**读，播放器从不读。变量名是**引擎名大写**加
                        `_COOKIE_BROWSER`（`YT_` / `BILI_` / …），与命令前缀同一条拼接规矩；
                        当前生效值靠 `<engine>-resolve --auth` 问出来（§3），
                        而不是靠调用方自己去读环境。
                      YT_AUDIO_FORMAT (ba)  YT_VIDEO_FORMAT (bv*+ba/b)
                      YT_VIDEO_FORMAT_FAST  —— 模式→格式表的那些值；它们跟那张表住在一起，
                        也就是住在每个 <engine>-resolve 里。
                      YT_ASCII_VO (tct)  YT_MPV_INPUT_CONF  —— 播放器侧的 mpv 旋钮。
                      YT_ASCII （1 = ASCII 字形回落；非 UTF-8 locale 下自动开；
                        由播放器与 uting 读 —— 遗留别名 YT_TUI_ASCII）。
                        它覆盖**整个**字形集：♫ ● ○ ❯ · ▶ ❚❚ • … → — ↑/↓ ←/→ ↵ ▘▝▗▖
                        以及那些条与轨的连排。验证方式是断言一个渲染出来的 pane
                        除了标签文字之外不含任何非 ASCII。
                      YT_LANG (en|zh) = uting 界面文字的语言；zh* locale 下默认 zh，
                        否则英文。帮助输出、错误与卡片的字段标签两种情况下都保持英文。
                      YT_THEME (minimal|mono|catppuccin|tokyonight|nord|gruvbox|
                        onedark) = uting 的配色家族（AS-BUILT-tui.md §11：一个强调色加一个状态色；
                        社区主题只在 COLORTERM=truecolor 下是 24-bit 的）。
                        --theme 压过环境变量；t 键在运行时实时循环它。
                      YT_BG (auto|light|dark) = 背景模式；auto 的链条：
                        $COLORFGBG → OSC 11 查询 → dark。Light = 该主题自己的浅色变体
                        （minimal 把青换成蓝）。
                      YT_SYNC (0|1|auto) = 同步重绘（DCS 1q/2q；auto：开，在 tmux 下关）。
                      YT_BRAND （=1：页眉 wordmark 用数学无衬线粗体，AS-BUILT-tui.md §11 字形一节；
                        opt-in，ASCII 模式压过它）。
                      NO_COLOR （=1：--color auto 渲染成朴素的；显式的 --color 压过它）。
   内部（由播放器为它自己的 detached 子进程设的，不是用户旋钮）：
                      YT_IPC_SOCK （每个播放器一个的 mpv IPC socket）  YT_DETACHED （=1：
                      没有终端，所以 mpv 安静且不过滤 stderr）  YT_PLAYER_ID （子进程把
                      title/format 补回哪一条记录，AS-BUILT-player.md §9.1）
   （颜色**模式**是 --color 这个标志，**不是**一个环境变量 —— 脚本在启动时把
    COLOR_MODE=auto 写死，只有 --color 会改它，所以一个 COLOR_MODE 的环境值永远不会被读。
    主题与背景**是**读环境变量的：YT_THEME / YT_BG。）
```

**`YT_` 前缀是历史遗留，并且刻意不去搅动它。** 套件叫 `uting`，新的引擎旋钮叫 `UT_DEFAULT_ENGINE`，
但重命名十来个正在工作的变量，会为了买文档里的一致性而弄坏每一个用户的 shell 配置。
新旋钮用 `UT_`；已有的保留 `YT_`。

Cookie 处理：`YT_COOKIE_BROWSER` 是按平台做存在性检查的（那个浏览器的 profile 目录在不在）；
不在的话，抽取就不带 cookie 地跑，而不是坏掉。在浏览器还开着时读它的 cookie 数据库
可能得到一次被锁住的读，并悄无声息地降级成未认证的抽取 —— 变通办法是关掉浏览器。
**只有引擎读它**，所以播放器没有任何 cookie 代码路径可供泄漏一份出去。

## 6. 加一个引擎 —— 清单

只有指针；每一项义务上面都已经陈述过一次。一个新来源 `foo` 恰好交付两个可执行文件，
别的什么也不改（ROADMAP D9）：

1. **`foo-search`** —— §1.2 那个面：标志 `-n -m -M -s -l -j -J --color -h -V`，
   一个 QUERY 位置参数（拒绝 URL，`--` 之后重新检查），§3 那个搜索信封且
   `engine:"foo"`，错误按 §3 且退出 2+（§4）。
2. **`foo-resolve`** —— §1.3 那个面：标志 `-f -S -j -J --color -h -V`
   加上**仅仅**这个站点支持的那些动词（§1.3：以"有没有"声明能力）；§3 那个解析信封
   （`stream_urls[]` 视频在前、`http_headers{}` 必需且不含凭据、`format` 不透明、`retried`）；
   一份显式的本站 host 白名单 —— 一个非本站的 URL 或一个畸形的 id 是用法错误，退出 1（§3）。
3. **`foo-resolve --auth`** —— cookie 决定读自 `FOO_COOKIE_BROWSER`（引擎名大写，
   §5），信封按 §3，且 `auth=="cookie"` 与 `cookie_browser != "none" and profile_found`
   等价。不吃位置参数，拒 `-f`/`-S`/`-J`，在依赖门之前作答。
   `tests/contract.sh` 把这几条当作对**每一个被发现的**引擎的不变量来断言，
   所以第三个引擎落地那天它就被覆盖了 —— 不是等谁想起来去加一行。
4. **两半都要：** `ENGINE_NAME` 从一个常量印出来；每一个信封（包括错误）里都有 `status` 与
   `engine`；一个信封一行（§3）；`-V` 在任何依赖门之前回答（§4）；
   门把跨界标志指向正确的动词（§2）。
5. **别的什么也没有：** 没有播放，没有生命周期，不写 `players/` —— 播放器靠名字找到
   `foo-resolve`（§1.1），而 `uting` 靠在 PATH 上和自己旁边扫描 `foo-search` + `foo-resolve`
   这一对来发现它（AS-BUILT-tui.md §11）。

引擎按动词自己挑传输（curl 或 yt-dlp 或别的任何东西）—— 接缝是信封，不是它背后的工具
（ROADMAP D11）。
