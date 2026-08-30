# AS-BUILT-contract —— uting 的 CLI 契约

那个**冻结面**（ARCHITECTURE.md §3.8）：任何一次重写之后仍然活着的东西，也是一次移植的验收规格。
这里写的全都是 as-built —— 对着八个脚本核过 —— 并按 ARCHITECTURE.md §3.8 的 semver 规则由 `VERSION` 定版。
**改动这份文件里的任何一条，都是一次刻意的、有记录的行为**（CLAUDE.md 硬规则 4），
从来不是某个功能的副作用。

写给两类读者，他们谁都不该需要去翻源码：

- **一个测试作者** —— 要对这八个命令中的任何一个写 JSON diff 测试，所需要的每一个信封、
  每一个退出码、每一种错误形状，都在 §1–§5；
- **第三个引擎的作者** —— §1.2/§1.3（引擎的两个命令面）、§2（它的门）、§3（它的信封）
  与 §6（清单）就是全部义务；`bili-search` / `bili-resolve` 没有满足任何这里没写的东西。

理由在 `ARCHITECTURE.md`（全文各处指过去）；流程在 `CLAUDE.md`。
一个事实一个地方：这里的 schema 别处一律不再陈述。

**公共 API 的边界**（semver 的版本化对象，ARCHITECTURE.md §3.8 由此选位数）：

```
  在里面：八个命令名本身 · 各自的 argv 与 flag 面 · 退出码表(0/1/2+/4) ·
          单行 JSON envelope 的字段与形状 · player record · 生命周期语义 ·
          引擎契约（<engine>-search / <engine>-resolve 两张 envelope） ·
          YT_* / UT_* / BILI_* 环境变量 · 配置面（四层链、两个文件的位置、
          键的前缀命名空间、缺出厂文件 = 2，§5）
  不在里面：内部函数名 · 渲染细节与主题 · 注释 · docs/ · tests/ · .claude/skills/ ·
          引擎背后用哪个原语（curl 还是 yt-dlp —— seam 是 envelope，ARCHITECTURE.md §3.4）
```

判一次 bump：把一批变更按这张表过一遍 —— 命中一条"在里面"且是破坏性的就走 y（0.y.z 期间），
否则加法与修复走 z；同批的加法项跟着走、不额外计。判据是表，不是感觉。

## 1. 命令规格

八个平级，四种形状：播放器、一个引擎的两半、UI，以及两个存储。
它们每一个都自己解析自己的 argv、自己拿着自己的门（ARCHITECTURE.md §4）——
没有一个可以委托过去的 core。

### 1.1 `ut-play` —— 播放器（与站点无关，非交互）

- **它拥有：** 播放、detached 生命周期、播放信封、退出码分类学、`players/`。
  **它不拥有任何站点知识：** 没有 yt-dlp 调用，没有 cookie 决定，没有格式字符串，没有 id 形状。
- **标志：** `-f -S -d -j -l -h -V` 加上长标志 `--engine --volume --start --detach --json --list
  --status --stop --set-volume --pause --resume --seek --seek-to --queue --enqueue --next
  --id --all --color --quality --help --version`。颜色只有 `--color`（没有 `-c`）；
  `-S` 是格式排序覆盖（没有 `-F`），原样转发给引擎；`--quality` 同理（没有短旗），
  `auto|low|medium|high` 四档在**门口**校验（bogus 档退出 1），档位原样转发给引擎 ——
  （mode, tier）→ yt-dlp sort 的映射表住在引擎里（§1.3），不在播放器里。
  `--start SEC` 是**启动时**的播放位置，只收非负整数秒（负数、`hh:mm:ss`、小数、非数字
  一律在门口退出 1）：**刻意不透传 mpv 自己的 `--start` 语法**（`-60` 从末尾算、`50%` 是分数），
  那会把 mpv 的语法发布到冻结面上，从此换不掉播放器；套件里的时间一律是秒
  （`duration`、`position`、`--seek-to`、收听行的 `seconds`）。它属于**播放路径**，
  与任何生命周期动词互斥 —— 移动一个已经在跑的播放头是 `--seek-to` 的活。
  它压过句柄自己带的偏移（§1.3 的 `start_seconds`），
  在一个队列里**只作用于第一条**（AS-BUILT-player.md §9.5）。
  `--` 结束选项解析：它之后的一切都是句柄
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
   ut-play --start 601 -- <handle>                从第 601 秒开始；压过句柄自带的偏移
   ut-play --quality high -- <handle>             质量档：auto|low|medium|high（默认 auto）
   ut-play                      → 用法错误，点名 <engine>-search / uting（ARCHITECTURE.md §3.2）
   ut-play -- "some query"      → 用法错误，点名 <engine>-search（有空白 ⇒ 不是句柄）
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
  `-n`/`-m`/`-M`/`-s` → "那是一个搜索标志 —— 用 `<engine>-search`"；`-J` → "那是一个引擎标志
  —— 试试 `<engine>-resolve --info -J`"；`--info`/`--transcript`/`--sub-lang` → "那是一个引擎
  动词"；`--get-url` → 取代了它的那个 `<engine>-resolve -j` 调用；其它任何不认识的长标志 →
  播放标志的清单。**每一句里的 `<engine>` 都是拼出来的**（`$ENGINE`：`--engine`，否则
  `UT_DEFAULT_ENGINE`），所以在第二个引擎下这些门臂点的是那个引擎的命令，而不是 `yt-`。
  **一处已知且接受的顺序依赖**：`--get-url` 与那三个抽取动词的 die 就在长选项归一化循环
  **里面**，所以 `--engine` 只有排在它们**前面**时才已被吃掉 ——
  `ut-play --transcript --engine bili` 仍会说 `yt-resolve`（§2 的门表同此）。

### 1.2 `<engine>-search` —— 一个引擎的第一半

- **它拥有：** 一个站点的查询路径、它自己的传输、它自己的 cookie 决定、它自己的结果整形
  与时长格式化器、它自己的门。**零播放、零生命周期逻辑。**
- **标志：** `-n -m -M -s -l -j -J --color -h -V`。位置参数：一个 QUERY。一个 URL 会被拒绝，
  并指向 `ut-play` —— 包括在 `--` 之后，那正是这项检查必须**重新施加**一次的地方，
  因为 `--` 停掉的是标志解析，不是参数校验。
- **信封：** `{status, engine, query, count, results[]}`，一行（§3）。
- **今天：** `yt-search`（yt-dlp）与 `bili-search`（curl + jq）。同一个信封，不同的传输 ——
  接缝是信封，不是它背后的工具（ARCHITECTURE.md §3.4）。

### 1.3 `<engine>-resolve` —— 一个引擎的第二半

- **它拥有：** 句柄文法与 host 白名单、模式→格式表、cookie 决定、这个站点的只读动词、
  yt-dlp 错误词汇表。**cookie 决定同时是可查询的** —— 它是这一半里唯一一件调用方
  在没有句柄的情况下也想知道的事（`--auth`，见下）。
- **标志：** `-f -S -l -j -J --color -h -V`（`-l` = 散文，且是**默认**输出模式）加上它**有**的那些动词：`--info`（两个引擎都有）、
  `--auth`（两个引擎都有）、`--transcript --sub-lang`（只有 `yt-resolve`，ARCHITECTURE.md §3.4）、
  `--parts`（只有 `bili-resolve`，ARCHITECTURE.md §3.4 同一条能力规矩）—— 以及流格式选择器 `--quality TIER`
  （`auto|low|medium|high`，两个引擎都有）。
- **`--quality` 是流格式选择器，只配 `resolve_stream` 用。** 它撞上 `--info` / `--parts` /
  `--transcript` 就退出 1（门语直说"它选择流格式，不适用于那个动词"）；它也不配 `--auth`。
  档位的含义在引擎内部解析：`quality_sort_for_tier(mode, tier)` 把 (mode, tier) 映射成
  一段 yt-dlp `--format-sort` 串（`audio` 模式下是 `abr` 排序，`video` 下是 `res` 排序 ——
  二维，因为 audio 档位对 `res:` 一无所知），那张表**只住在引擎里**；
  `auto` 不发 sort（引擎出厂行为），`-S` 压过 `--quality`（一次显式的覆盖赢过一档抽象）。
  一个解析信封**不**携带档位：它是被用掉的那个东西（`format` 已经如实报了）。
- **`-f` 只收规范模式**（`audio video fast ascii viz`）—— 别名表（`ba`、`bv`、`fst`、
  `asc`、`waves`…）是 `ut-play` 的：播放器在自己的标志解析处归一化，送到引擎的永远是
  规范拼写。引擎接缝只运载规范模式，于是别名表只有一张，第三个引擎落地那天就继承它。
- **`--auth` —— 这一半里唯一不吃句柄的动词。** 它问的是**引擎**怎么配的，不是某个句柄
  怎么样，所以它自己的门与别的动词反着来：一个位置参数是用法错误（1），
  `-f`/`-S` 同样是（它不解析流），`-J` 也是（`-J` 是 yt-dlp 的原始记录，而它根本不跑
  yt-dlp）。它在**依赖门之前**作答，和 `-V` 一样 —— 一个报告"我怎么配的"的动词，
  不该需要它正在报告的那个工具装在机器上；散文形态连 `jq` 都不需要。
  信封见 §3。
- **行为：** AS-BUILT-engine.md §10。非本站 host → 用法错误（1）。
- **以"有没有"声明能力（ARCHITECTURE.md §3.4）：** 一个引擎做不到的事，它就不为它准备动词。

### 1.4 `uting` —— 交互式终端 UI

- 命令面：`uting [--engine NAME] [-n N] [-m S] [-M S] [-s field] [-f audio|video|fast]
  [--volume N] [-p ROWS] [--color auto|always|never] [query]` —— 搜索整形的标志转发给
  `<engine>-search`；`-f`/`--volume` 是播放设置，每次播放都转发给 `ut-play`；`-p` 是每页行数；
  其余一律拒绝。`--volume` 只在启动时生效（没有运行时循环键，不像 `-f` 有 `v` ——
  见 ARCHITECTURE.md §26）。查询可选（缺了就提问）。要求 stdin 与 stdout 双双是 TTY，
  要求 `jq`，要求那些同级动词。
  `-f` 对着 `audio|video|fast` 校验：播放是 detached 的，而 `ascii`/`viz` 需要一个终端
  （AS-BUILT-player.md §9.2）。
  按键：方向键导航/翻页（`j`/`k` 是 `↓`/`↑` 的别名，只在列表视图；`/` 开着时它们是正在打的字）·
  Enter 非阻塞播放 · `Tab` 在两个视图间切换 ·
  `Esc` 回到列表（在卡片里）· `Space` 暂停 · `[`/`]` 快退/快进 ∓10s · `9`/`0` 音量
  （**卡片里的 `↑`/`↓` 不是音量** —— 它们是章节游标，见下）· `s` 停止 ·
  `v` 循环模式（audio→video→fast）· `f` 循环质量档（UT_QUALITY_CYCLE 的顺序，出厂
  auto→medium→high；档位是**规范拼写**，翻成 format-sort 是引擎的事，见 §1.4）·
  `e` 切换来源（只有一个引擎时隐藏）·
  `l` 切换界面语言（en↔zh，任一视图）· `t` 循环配色家族（任一视图）·
  `n` 新搜索 · `o` 排序 · `c` 多 P 部分（§1.3）· `i` 聚焦行的详情（§1.3 的 `--info`）·
  `/` 过滤 · `?` 键位提示两档切换（`core`↔`full`，任一视图；`？` 全角同绑）· `q` 退出 ·
  卡片里、且在播主语上按过 `i` 之后：`↑`/`↓` 在 `--info` 的 `chapters[]` 里移动游标、
  `Enter` 跳到选中章（`ut-play --seek-to <start_time>`，§1.1）—— 一次 seek，不重新 resolve。
  条目主语上同一批章节只是目录：那张卡没有播放头。两个键与它们的提示格随章节块**一起**出现、
  一起消失（矮面画不下时整块退场）。这不是新能力：`.chapters[].start_time` 与 `--seek-to`
  本来就都在这份契约里，P6 只是给它们加了键位。
  行数由两条**边**管，不由一个键管：`→` 越过最后一页**追加**一批（一次取数），
  `←` 在第 1 页**砍掉**一批（纯本地截断，不取数，地板是一屏）。
  这八个键改的设置会写回用户配置（§5「写回」）。
  `a` 把当前聚焦行加入一个播放列表 · `b` 把一个已存播放列表打开为行来源 ·
  `h` 把收听日志打开为行来源 · `c` 把聚焦行的多 P 部分打开为一个列表（§1.3 的 `--parts`；
  引擎没有那个动词时按键沉默 —— 同一个"以有没有声明能力"的降级；再按一次 `c` 回到搜索）。
  `c` 打开的部分列表是搜索行专用的：播放列表与历史的行上它走与 `o`/`e` 同一条拒绝路径
  （返回栈只有一层，存储的行上不打开第二个来源）。**这三个键在非搜索视图里连提示格都不占** ——
  一个量宽度的块不能拿一格去说"这里不行"（`AS-BUILT-tui.md` §11）。
  `i` 把聚焦行开成焦点卡片的 **item 主语**（一次 `<engine>-resolve --info`，按 `engine:url`
  单槽缓存；引擎没有那个动词时按键沉默）。它是那个主语**唯一**的入口，而且进门即取数 ——
  于是那张卡的每一帧都带着列表放不下的东西。任何行源都行：一行就是 `{engine,url}`。
  在**卡片里**按 `i` 则是对在播曲目叠一行 info，主语不变；它问的 engine 取自 `--status`
  的 `engine` 字段（§3），因为队列可以走到这个界面从没启动过的曲目、甚至另一个源。
  `a`/`b` 只在 `ut-playlist` 装了时出现（§1.5），`h` 只在 `ut-history` 装了时出现（§1.6）——
  跟单引擎安装下隐藏 `e` 是同一条规则。两者都**替换**屏幕上的行，且两者都是 **toggle**：
  打开一个存储的那个键把它关掉（再按一次 `h`、再按一次 `b`），
  从暂存的信封还原那次搜索而不是重跑那个查询，所以用户回去时看到的行就是他离开时的那些行。
  这个键在它自己的存储开着时会给自己换标签 —— 不印第二个键，`Esc` 不参与其中
  （AS-BUILT-tui.md §11 有这条规则，以及它背后那次一秒的测量）。
  `h` 不取名字 —— 日志只有一份 —— 并显示最新的 50 行。
  播放列表或日志在屏幕上时，那两个会**重新取数**的键 —— `o` `e` —— 会说一声然后什么也不做，
  而两条边（`→` `←`）在那里是**不出声的** no-op：存储没有"更多"可谈；
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
          --color -h -V                             --start --status --stop --set-volume
                                                    --id --all --color -h -V
   拒绝（→ "use ut-play"）：                  拒绝（→ "use <engine>-search"）：
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
一个把"这不是一个 URL"的拒绝只写在**不带** `--` 那条路径上的门，会让 `-- "some query"`
从它旁边走过去 —— 一路走到动作，跑成一次**搜索**、印出一份散文列表或者在 `-j` 下印出
一整个搜索信封，而这个动词的契约说的是它播放 URL。**一个只守着一种拼法的门，不是门。**
所以 `ut-play` 对 `--` 之后的任何东西施加空白测试，
而 `<engine>-search` 对它之后的每一个 token 施加 `reject_url`。

**为什么门不是一个层（ARCHITECTURE.md §3.1）。** 一个 core 加几个 wrapper 的模型里，门就是 wrapper 存在的理由：
core 实现一个宽的多态命令面（一个词是搜索、一个 URL 是播放），wrapper 的活是保证调用方
到达的是哪一半。搜索归 `<engine>-search`、抽取归 `<engine>-resolve` 之后，
播放器只剩下恰好一个动词 —— 没有别的操作可供一次绕过去够到，也就没剩下什么好让一个层去守。
留下来的是那些**错误文本**：它们如今是这个动词自己的门臂（§1.1）。

**为什么 `uting` 组合这些动词，而从不碰它们的内部（ARCHITECTURE.md §3.7）。** `fetch_json` 解析搜索信封，
而 `<engine>-search` 的 URL 拒绝正是让"`-j` = 搜索信封"这件事无条件成立的东西 ——
一个粘进 TUI 的 `n`（新搜索）提示里的 URL，除了变成一次被拒绝的搜索之外不能变成任何东西。
TUI 还**显式**传 `--engine`，**取自信封自己的 `engine` 字段**，从不让 `ut-play` 的默认值来决定：
装了两个引擎时，那个默认值会把第二个引擎的 URL 送给第一个引擎的 resolver，
而按 ARCHITECTURE.md §3.4 那是一个硬用法错误，不是一次悄无声息的贴错标签。
ARCHITECTURE.md §3.7 唯一被批准的例外是那个 mpv socket（AS-BUILT-player.md §9.3），
播放器把它的路径发布在 `-d -j` 信封里，正是为了让一个客户端可以用它。

## 3. 数据契约（JSON schema）

搜索信封（`<engine>-search -j`）：
```json
{ "status":"ok", "engine":"yt", "query": "lofi", "count": 25,
  "results": [ { "id":"…", "title":"…", "url":"https://www.youtube.com/watch?v=…",
    "channel":"…", "duration":213, "duration_fmt":"00h:03m:33s",
    "view_count":12345, "live_status":"not_live",
    "kind":"track", "access":"full" } ] }
```
`-j` = 上面那 10 个结果字段（高信噪比，比原始那条约 23 字段的 yt-dlp 记录小约 4 倍）。
`-J`/`--json-full` = 同一个信封，`results` 里装每一个原始字段。
时长未知时（一路直播）`duration` 与 `duration_fmt` **一起是 `null`**；`view_count` 也可以是 `null`。
失败时信封改为 `{status:"error", engine, query, count:0, results:[], reason}`，
`reason` 用的是与播放相同的那个枚举，退出码是 2+（AS-BUILT-engine.md §7 / 本文 §4）。

- **`engine` 是每一个引擎信封的必需键** —— search、resolve、`--info`、`--transcript`，
  以及它们各自的错误形状。它是那个同时也是命令前缀的 token，
  于是一个手里拿着结果的调用方靠字符串拼接就够到了对应的 resolver（`yt` → `yt-resolve`），
  而 `uting` 不需要一张映射表就能传 `ut-play --engine <那个值>`。
  **这就是 host 白名单保护的那个字段**（AS-BUILT-engine.md §10，ARCHITECTURE.md §3.4）：
  一个接受了别的站点的 URL 的 resolver，会在这里印出它自己的名字，那条路由声明就成了假的。
  每个引擎都从**一个常量**（`ENGINE_NAME`）印出自己的名字，而不是推导出来，
  所以信封和文件名不可能互相矛盾。
- **`status` 同样是必需键**，`"ok"` 或 `"error"` —— 这样一个调用方在看任何别的东西之前，
  可以先在一个字段上分支，套件写出的每一个信封都如此。
- **两个键都是引擎级的，不是 YouTube 级的：** `bili-search` 印出一模一样的信封，
  只是 `engine:"bili"`。一个漏掉其中任一个的第三引擎，将与一次被截断的读无从分辨。
- **`kind` 与 `access` 同样是行上的必需键，且枚举封闭** ——
  `kind` ∈ {`track`, `collection`, `multipart`}、`access` ∈ {`full`, `preview`, `paywalled`}。
  判据是**引擎无关的两问**，不是任何一个站点的字段名（否则第三引擎作者只能猜，
  而必填 + 封闭意味着猜的结果会以事实的面目发货）：
  - **`kind`** —— `ut-play --engine E -- <本行 url>` 会发生什么？恰好播**一个** = `track`；
    一个 handle 出**多个 part** = `multipart`；本行是**多个 handle 的容器** = `collection`。
  - **`access`** —— 匿名解出来的**时间轴**完整吗？完整 = `full`（**码率/音质降级仍是 `full`**）；
    被截断 = `preview`；解不出流 = `paywalled`。报的是站点事实，不是登录裁决（ARCHITECTURE.md §3.4）。

  **枚举装不下的新形态，按这两问映射到最近的值，映射记进 AS-BUILT-engine.md —— 枚举不为它长大。**
  两个字段是**引擎的判断**而不是站点的原始记录，所以 **`-J` 的行同样携带它们**，
  并且压过任何同名的原始字段：要更多数据的那个调用方，不该恰好是丢掉路由字段的那个。
  站点没有对应形态时就如实印默认值（`track`/`full`）——
  **恒为默认值是合法状态**，今天两个引擎都是（AS-BUILT-engine.md §7、§7.2）。
- **一行结果是一次调用。** 一行的存在意义就是 `ut-play --engine <engine> -- <url>`，
  所以 `url` 建不出来的记录**在信封之前**就被引擎丢掉，而不是带着 `url:null` 发货
  （AS-BUILT-engine.md §7.2 是这条规矩的实测由来）。`tests/contract.sh` 把它连同上面的
  封闭枚举一起，当作对**每一个被发现的**引擎 × `-j`/`-J` 两种形状的不变量来断言。

解析信封（`<engine>-resolve -j -f MODE -- <handle>`）：
```json
{ "status":"ok", "engine":"yt", "id":"dQw4w9WgXcQ",
  "url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "title":"…", "duration":213, "start_seconds":601, "mode":"audio", "format":"ba/b",
  "selected":"251 - audio only (medium)", "selected_resolution":"audio only",
  "stream_urls":["https://rr2---sn-….googlevideo.com/videoplayback?…"],
  "http_headers":{"User-Agent":"…","Accept-Language":"…"},
  "retried":false }
```
这就是播放器用来表达"我在放什么"的全部词汇，每一个键都在承重：

- **`stream_urls` 是一个数组，视频在前。** 单流时一个元素；引擎的格式把一条纯视频轨与一条纯音频轨
  合并时是两个，此时第 1 个元素是音频。播放器用 mpv 的 `--audio-file` 把它们接起来 ——
  那正是 mpv 的 `ytdl_hook` 会用一份合成 EDL 顺手做掉的事（AS-BUILT-player.md §8.1）。
- **`http_headers` 是必需键**，可以是 `{}`。它堵上了"只交一个流 URL"留下的那个洞：
  在一个检查 `Referer` 或钉死 `User-Agent` 的 host 上，一个光秃秃的流 URL 不足以取到东西，
  而播放器无从把它们发明出来。一个引擎**不得**在这里返回凭据头 ——
  播放器把这些放在 mpv 的 argv 上，那是 `ps` 读得到的地方。
- **`start_seconds` 是必需键**，取值 `null` 或一个**非负整数秒**：句柄要求从哪里开始，
  没要求就是 `null`。它与 `http_headers`（必需、可为 `{}`）、`kind`/`access` 同一套家法 ——
  第三个引擎作者不会"忘了实现"，而漏键与一次被截断的读也才分得开。
  **`url` 里不带这个偏移**，两个键各回答一个问题：`url` 说这是哪个媒体，`start_seconds` 说从哪开始。
  这不是洁癖 —— `ut-playlist --add` 存下来的正是这个 `url` 字符串，
  偏移搭在里面就意味着一首收藏的曲子从此每次都从 10:01 开始放。
  yt 那边是白拿的（`webpage_url` 本来就不带 `t`），
  bili 那边必须动手剥，因为那个站的 `webpage_url` 保留整个 query —— `?p=N` 就在里面
  （AS-BUILT-engine.md §10.4）。解析不出来的值（`?t=banana`）是 `null`，**不是错误**：
  它没有回答一个必须被回答的问题。小数向下取整（`601.5` → `601`）：这个键数的是
  "已经过去了多少秒"，四舍五入会把播放头推过调用方指的那一刻。
  `--info` 信封带同一个键，两个信封说同一件事。
  **`?t=0` 与"没带偏移"是两个不同的答案**（`0` vs `null`），
  而每一种把两者折进同一个值的写法都会在这里印错 —— `tests/contract.sh` 拿它当判别性输入。
- **`format`** 是引擎**发出去**的那个格式选择串。播放器把它原样记进播放器状态文件，从不去读它：
  `bv*+ba/b` 是一句 yt-dlp 表达式，而播放器不懂那门语言。
- **`selected` / `selected_resolution`** 是同一件事的**回答**那一半：yt-dlp 自己报的
  「我最后挑了哪个」（`251 - audio only (medium)`）以及它的分辨率（无视频时是 `audio only`）。
  与 `format` 成对读 —— 请求 vs 答案，这也正是 `tests/contract.sh` 断言两者**不相等**的原因：
  一个把请求回声进 `selected` 的引擎能过掉其余每一条检查。
  **零额外网络**：这两个值本来就在那份已经取回的原始记录里（`.format` / `.resolution`），
  从前被丢掉。取不到时是 `null`，与 `title`/`duration` 同一套可空约定。
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
- **这个信封承诺的是"发不发"，此外什么都不承诺 —— 而"此外"是两件事。**
  站点**认不认**（过期登录照样报 `cookie`），以及认了之后这个账号**够到什么**。
  第二件是量过的：本机实测 2026-08-26 —— 从 chrome 提取到 3159 个 cookie，
  profile 经浏览器确认**是登录状态**，B 站依然只供匿名音频档，
  因为那个账号不是大会员（AS-BUILT-engine.md §8.2）。
  所以 `auth:"cookie"` 与"更好的音质"之间**没有**蕴含关系，两个方向都没有。
  第一件（会话有效性）需要一次鉴权往返 —— 刻意不在这个动词里，也刻意不在这个信封里
  （ARCHITECTURE.md §3.4）。要那个的话，升级路径是把网络调用放到一个 `--auth --probe` 后面，
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

**枚举是那个共享的事实；分类器不是。** 它有三个读者，而它们刻意住在不同的文件里：
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
               players:[{id,pid,url,engine,mode,volume,paused,position,duration,title,
                         selected,selected_resolution,started_at,
                         queue:{pos,len,next,upcoming:[{title,url,engine,duration}…]}}…],
               failed:[{id,url,engine,mode,started_at,ended_at,exit_code,reason}…]}
              没有在放 / 没有失败时是空数组（仍然退出 0）
              detach 之后的头一两秒 title 是 null：解析是那个 detached 的**子进程**做的
              （父进程必须在毫秒级返回），它一拿到解析信封就把 `title`、`format` 与
              `selected`/`selected_resolution` 补进它自己的那条记录
              selected 是**引擎挑中**的那个格式（解析信封的同名键），回填之前是 null。
              请求那一半（`format`）**不在这个投影里**：它是一句 yt-dlp 表达式，
              而 --status 回答的是"现在在放什么"，不是"当初怎么问的"
              volume、paused、position 与 duration 是**一次往返**里从播放器的 socket 上
              实时读来的（AS-BUILT-player.md §9.3）。volume 回落到记录下来的启动值 /
              --set-volume 值；另外三个在 socket 问不到、或播放器答了 null 时是 null ——
              null 是"问不到"，**不是** false/0。position 与 duration 是整数秒，
              在 mpv 开始解码之前是 null（冷启动约 8s）；一路直播的 duration 一直是 null。
              一个活着的播放器上 queue 永远不是 null：每一次 detached 启动都写一个，
              而一个单独的句柄是一个长度为 1 的队列（AS-BUILT-player.md §9.5）。
              它是从播放器自己的队列文件上读的，不是从 socket 上 —— mpv 一次只被递一个 URL，
              从来不知道有一个列表。`next` 是 pos **之后**的那一条，最后一条曲目上是 `null`。
              `upcoming` 是**同一条队尾的列表形式**，每条带 `duration`（`next` 从来没有过），
              至多 5 条（`ut-play` 的 `QUEUE_UPCOMING_MAX`，那个数只声明在那一处）：
              队列没有上界而 --status --all 每个活播放器印一条记录，所以投出整条队尾等于
              把调用方的信封大小交给"别人排了多少首"决定。`len` 仍是诚实的总数，于是
              "队尾被截断"与"队列到底了"（空数组）永远分得清；`upcoming[0]` 就是 `next`
              多一个时长，重叠是**故意**的 —— `next` 是三处信封已经承诺的形状。
              url、engine 与 title 跟着**曲目**走：子进程每解析一次就补一次它自己的记录，
              所以十分钟后取的一次 --status 描述的是**此刻**在放的东西。
              engine 与 url 合起来就是**正在放的那次调用**（`ut-play --engine E -- URL`）——
              一条记录本来就该是一次调用，与 `ut-playlist` 的记录同一个形状（ARCHITECTURE.md §3.5）。
              少了它，一个读 --status 的调用方说得出在放什么、却说不出该找谁再放一遍，
              而一条队列可以混源（`--queue` 的 engine 是**每条**的），所以拿启动那一条去猜，
              恰好在混源队列上是错的。同一笔账，failed[] 也带 engine：
              一条重发不了的调用，在墓碑里同样重发不了。
              failed[] 是墓碑列表 —— 那些**自己**死掉的播放器，最新在前，至多 8 条，
              不超过一小时（AS-BUILT-player.md §9.2）。reason 是那个共享的播放枚举。
              一个正常结束或者被 --stop 掉的播放器永远不在里面，
              所以这个数组是一份**错误记录**，不是收听历史那个功能（ARCHITECTURE.md §3.5）——
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
   --enqueue: {status:"ok", id, added:<n>, queue:{pos,len,next,upcoming}}
   --next   : {status:"ok", id, queue:{pos,len,next,upcoming}}
              `queue` 与 --status 里的那个是**同一个对象**（同一个生产者），
              所以上面关于 next / upcoming / 封顶的每一句在这里也成立。
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
   （播放器**没有** --get-url：解析出一个流 URL 正是一次裸的 `<engine>-resolve` 调用**本身**，
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
   --parts  : {status:"ok", engine, id, title, url, count, total_duration,
              total_duration_fmt, parts:[{n, engine, url, title, duration, duration_fmt}…]}
              列出多 P 视频的各 P（?p=N）—— 一次 HTTP 请求，没有 yt-dlp。**只有
              bili-resolve 有它**（ARCHITECTURE.md §3.4）：一个 YouTube id 恰好就是一个文件，
              它"多条目"的形态是一份自有 URL 的播放列表，不是这个动词。
              parts[] 的元素**就是条目记录** —— `--parts -j | jq '{items:.parts}'`
              原样管进 `ut-playlist --add` 与 `ut-play --queue`，不需要字段映射，
              与 `--show` / `--ls` 的信封遵守同一条可拼接规矩。
              `total_duration` 与 `total_duration_fmt` 是**集合**的时长 ——
              搜索结果行只报单行的时长（§1.4 的 `total=` 字段显示的就是这个数字），
              两个数字不同不是错误，是"这一行代表什么"不同（P8）。
              单 P 视频**不是错误**：它列出 count 1，不是失败。
              它要求一个 id：b23.tv 短链是重定向不是 id，被拒（1）。
              取数失败（网络 / 记录里没有 parts）→ {status:"error", engine, url, reason}，
              退 **2**（一次工具失败，不是用法错误 —— 与抽取同类）。
   --quality : 见 §1.3 —— 流格式选择器，不配 --info / --parts / --transcript / --auth。
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
        没有句柄（ARCHITECTURE.md §3.2）、一个里面带空白的句柄、--id/--all 用在生命周期动词之外、
        -d 配上一个动作或配上 -f ascii|viz、
        一个不带符号的 `--seek` 值（`--seek 30`）或一个负的 `--seek-to`、
        一份这个进程用不了的队列 payload（`--queue`/`--enqueue`：坏 JSON、三种 stdin 形状
        都不是、没有条目、url 里带空白、坏的引擎名）—— 在**父进程**里就拒了，
        所以一份畸形的队列永远到不了一个播放器，
        `--queue` 而没有 `-d`、或配上一个动作、或 argv 上带了句柄、
        一个不认识的 --engine、一个 host 不是这个引擎的 URL（AS-BUILT-engine.md §10 / 本文 §3）、
        --info / --transcript 取数失败（含 no_subtitles_available）、
        --quality 撞上 --info / --parts / --transcript / --auth（它是流格式选择器，§1.3）、
        一个不认识的 --quality 档位、--parts 拿到一个它认不得的句柄形状（b23.tv 短链）
   2+   传播上来的 yt-dlp / mpv / HTTP 失败（播放、resolve -j、**搜索**失败 ——
        搜索即使 yt-dlp 退出 1 也报 2，好让一次工具失败永远不会与 1 混淆）。
        --parts 的取数失败同样落在这里（网络 / 记录里没有 parts —— 一次工具失败，
        与 --info 的"取数失败退 1"不同：--parts 的失败来自它**发起的那次请求**，
        --info 的失败来自引擎对已有取数的再解释，见 §3）。
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
          别的动词一律不需要 —— 每一个都在输入为空时报错，而不是提问（ARCHITECTURE.md §3.2/ARCHITECTURE.md §3.2）。
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
          BSD 的 `nc -U` 在 macOS 上是原装的；Linux 上任何带 `-U` 的变体都被接受 ——
          `netcat-openbsd` 的 nc，或 `ncat` —— 由 `resolve_nc_unix` 按能力探测
          （ARCHITECTURE.md §26；两个都没有时只有 socket 动词拒，播放与队列不受影响）。
   -V   ：每一个入口点都在**任何**依赖门之前回答它，读 VERSION 并印出它自己的名字 ——
          为了知道你的版本号而需要装着 yt-dlp 是本末倒置的，
          而八个可执行文件不能有互相矛盾的余地（ARCHITECTURE.md §4）。
          断言是对 shell/ 下每一个有 shebang 的文件做的，不是对一份名字清单做的。
```

## 5. 配置面

按次的选择是标志；一次设定的调校是环境变量或**配置文件** —— 刻意留在标志之外，
好让每个动词的标志面保持窄。

**两个文件，四层，一条链：**

```
   标志（每次调用）  >  环境变量  >  用户的配置  >  出厂默认值文件
```

**出厂默认值住在 `<checkout>/config`** —— 每个入口点从自己**解析后**位置的上一级读它，
和上面读 `VERSION` 同一个机制、同一个理由。**套件里每一个默认值都在那里声明，一次，
供八个入口点共用。** 在它之前，每个默认值是各脚本内联的 `: "${KEY:=值}"`，
于是一个跨引擎的值（`UT_MAX_SEARCH_RESULTS`）要写两遍、可以各自漂移而没有东西会发现 ——
这次搬迁当场就抓出了两处：`UT_PLAY_MODE` 在四个脚本里不一致、`UT_SORT_FIELD` 在三个里不一致
（根因是 `uting` 拿**轮换顺序**当**合法值域**用，见 §1.4）。

所以这个文件**不是可选的**：缺了它的 checkout 是坏的，并且会这么说 —— 一行话，退 **2**。
**没有给 `--version` / `--help` 留后门**，那条路试过：放行之后 `set -u` 会在一百行之后
报一句 `YT_ASCII_VO: unbound variable`，把一句清楚的话换成一句不清楚的。
一个缺了自己一部分的 checkout 不是**依赖门** —— yt-dlp / jq / mpv 没装时 `--version`
照样答 —— 它是坏 checkout。

**用户自己的文件是 `${XDG_CONFIG_HOME:-~/.config}/uting/config`**，没有扩展名，
和 `yt-dlp` 自己的 `~/.config/yt-dlp/config` 同一个拼法：格式是平的 `KEY=value`，
一个 `.toml`/`.yml` 会承诺这个套件加不了解析器（那是一条运行时依赖）的结构。
它被**先**读，所以它压过出厂默认值。`UT_CONFIG` 换掉这个路径，而且**只能从环境**来 ——
一个文件不能搬动自己，两个测试套件正是靠它从不去读用户真实的配置。
**出厂那份没有任何命令会写。用户那份由 `uting` 写回八个键** —— 见下面「写回」。

**写回（八个键，只写用户那份）。** `uting` 在运行时会改八个设置，它们**就地写回用户那份
配置**，让下一次会话从这一次停下的地方开始（一个每次会话都要重按的偏好等于没有偏好 —— ARCHITECTURE.md §3.6；重开触发器在 ROADMAP）。写回的是：

```
   UT_DEFAULT_ENGINE   e 键切来源            UT_SORT_FIELD      o 键换排序字段
   YT_THEME            t 键换配色家族        YT_LANG            l 键换界面语言
   UT_PLAY_MODE        v 键换播放模式        UT_START_RESULTS   → / ← 两条边改行数
   UT_PLAY_QUALITY     f 键换质量档          UT_KEYS            ? 键换提示块的档
```

白名单是硬的：**不在这八个里的键，写回路径根本够不着**（`uting` 的 `pref_value` 既是
键→变量的映射也是那张白名单，所以不存在第二处要同步的清单）。四条规则：

- **就地改，只有值会动。** 键自己的空白、值与行尾 `#` 注释之间那段空白、以及注释本身
  都逐字节搬过去；文件里的空行、注释行、被注释掉的键、以及这八个之外的每一行都不动。
  注释列**刻意不重排** —— 会重排的实现要去依赖那个知道一个中文注释每字两格的宽度层，
  而宽度层住在渲染路径里；按字节补齐会把中文注释全部错位，并且文件仍然合法、什么都不报。
  文件里没有的键**追加**一行到末尾；文件本身不存在就建目录、写一个三行表头再追加。
- **值必须能原样读回来。** 唯一的正确性判据是 round-trip：写下去的东西必须能被
  `ut_read_config` 一字不差地读回来，所以含 `#`、引号、换行、首尾空白或开头 `~/` 的值
  会被拒绝（这八个的值域是枚举和数字，今天到不了这条闸；它为第九个键存在）。
- **被环境变量压住的键拒绝写，并在屏幕上说一次。** 环境每次启动都压过文件，
  所以写下去就是记一个程序下次读到、然后扔掉的值 —— 一份记着自己会被忽略的值的文件在撒谎，
  而且是几个月后才被发现的那种。`uting` 在读配置**之前**记下这八个键里哪些已经在环境里，
  写回对这些键变成 no-op 加一行提示。
- **写是延后的，不是按键即写。** 一次 cycle 只置一个脏位；真正落盘发生在阅读器的空闲
  tick 与退出时。`t`/`l` 是可以连按的瞬时键，同步写等于每次按键整份重写文件，
  而那个循环同时还在把单字节拼成一个 UTF-8 字符。最坏情况因此是「进程死在一个 tick
  窗口里，丢一个偏好」，而不是「每次按键一次重写」。
- **不加锁**（写临时文件再 `mv -f`，一次可见）：两个 `uting` 同时开着是后写者赢，丢的是
  一个偏好而不是用户数据；为它在键循环里加一次锁自旋是更坏的交易。写不进去（只读的
  `~/.config`）是**软失败**：印一行短提示，本次会话不再重试，TUI 不会因此死掉。
  **临时文件落在 symlink 解析之后的真实路径旁边**：`UT_CONFIG` 指的很可能是一条指向
  dotfiles 仓库的符号链接，而 `mv -f` 落在链接本身上会把链接换成一个普通文件、把用户真正
  的那份**架空**（此后他在 dotfiles 里改的每一笔都不再生效），而且什么都不报。写之前先
  沿链走到真实文件（与八个入口点自解析用的是同一个惯用法，bash 3.2 没有 `readlink -f`），
  `cp -p`/`>`/`mv -f` 全部对着它做，原子性不变。这一条与 `ut-playlist` 的 temp+mv 不同，
  是因为**所有权不同**：那个存储改写的是它自己在自己目录里造的文件。

**没有第九个命令，刻意的**：ARCHITECTURE.md §3.5 要求每个功能都有 agent 面，而"设一个偏好"的 agent 面
早就存在且早就有文档 —— 就是这条链里的那个 `KEY=value` 文件本身。

**格式与安全边界**：`KEY=value`，一行一个，`#` 到行尾是注释，一对匹配的引号会被剥掉，
开头的 `~/` 展开成 `$HOME`。这个文件是**当数据读的，绝不 source** ——
一个会被执行的配置文件可以运行任何东西，而这个套件的整个安全故事就是它的输入是数据；
`eval` 从一个变量赋值，从不从那一行赋值，所以 `UT_X=$(cmd)` 存下的就是那九个字符。
**只有套件自己的命名空间可设**（`UT_` / `YT_` / `BILI_`，正则 `^(UT|YT|BILI)_[A-Z0-9_]+$`），
于是一个文件永远够不到 `PATH`、`TMPDIR` 或 `LD_PRELOAD`；而播放器为自己 detached 子进程
设的那四个**在允许的命名空间之内被拒**（见本节末），因为一个文件级的 `YT_IPC_SOCK`
会把每一个播放器都指向同一个 socket；`UT_CONFIG` 与 `UT_DEFAULTS`（两个配置文件各自的路径）
同样被拒 —— 一个文件不能搬动自己；`UT_VERSION` 也在名单上 —— 它是从 `VERSION` 那一行读进来的
**常量**，不是旋钮，只是穿着一个能被配置够到的前缀，而 `--version` 答的话不该由一个配置文件
改写。拒收名单共七个名字。载入块在**八个入口点里逐字重复**，
和 `VERSION` 读法一样：逐字节的副本可以 grep 出漂移，而一个 source 进来的文件
会把 `VERSION` 数据文件存在所要理正的依赖方向反过来。

**四个旋钮刻意不在出厂文件里 —— 前两个因为它们的"未设置"本身就是一次自动探测**（在文件里
给它一个值，和用户自己设了它无从区分，于是恰好废掉了作为其默认值的那次探测），
**后两个因为它们的默认值是一条平的 KEY=value 表达不了的链**：

```
   YT_LANG        未设置 = zh* locale 下 zh，否则英文
   YT_ASCII       未设置 = 非 UTF-8 locale 下自动开，且它经由遗留别名 YT_TUI_ASCII
                  回落 —— 文件里的一个值会让那条别名永远到不了
   UT_STATE_DIR   默认是 ${XDG_STATE_HOME:-$HOME/.local/state}/uting ——
                  一条穿过另一个变量的链，平的 KEY=value 文件表达不了，
                  而摊平成一个字面路径会悄悄丢掉本节承诺的 XDG 支持
   UT_START_RESULTS  未设置 = 跟随 UT_FETCH_BATCH —— 同样是一条穿过另一个变量的链。
                  它与上面三个不同的一点：它是**唯一一个 uting 会写进用户那份**的
                  「不在出厂文件里」的键，所以它第一次出现在任何文件里，
                  都是用户自己按了 `→` 或 `←`
```

这四个仍然内联（前两个与第四个在 `uting` / 各引擎，UT_STATE_DIR 在 `ut-playlist` /
`ut-history`），要钉住就在自己的配置或环境里设。

**按 SCOPE 分组，不按前缀分组。** `YT_` 前缀是历史遗留，**不**代表"只关 YouTube"：
`YT_THEME` 与 `YT_LANG` 只有 `uting` 读，`YT_ASCII` 由 `uting` 和全部四个引擎脚本读，
`YT_ASCII_VO` 由 `ut-play` 读 —— 而 `uting` 与 `ut-play` 都不知道什么是来源。
`config` 因此按作用域排（suite / player / tui / engine:yt / engine:bili）。

```
   标志（每次调用）：  -n -m -M -s -p -f -S -l -j -J -d -h -V --color --theme --engine
                      --detach --status --stop --info --auth --transcript --sub-lang
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
                      UT_DEFAULT_ENGINE   （默认 yt；**uting 写回**）= --engine 默认到哪个引擎。
                        **ut-play 与 uting 都读**，刻意是同一个变量：
                        一个已经挑过一次默认来源的用户，不该每个面再挑一次。
                        名字不在时，uting 回落到第一个装上的引擎。
                      UT_MAX_SEARCH_RESULTS （默认 200；0 = 不封顶）= 一条查询最多返回
                        多少**行**。按行数而不是页数算，因为行才是信封里装的东西：
                        `bili-search` 把它换算成一份翻页计划（那个端点每页 20，
                        请求是那台主机上稀缺的那一样），`yt-search` 用它夹住自己的
                        `ytsearchN`。200 正是 bili 从前固定花掉的那十页，所以实测出来的
                        预算没变；yt 侧则是**新**多了一个上限（从前只由站点何时不再发决定）。
                        它取代了 `bili-search` 从前的 `MAX_PAGES` —— 页数只可能是那一个
                        引擎的，`yt-search` 根本没有翻页循环给一个页数去落。
                      UT_SEARCH_RESULTS   （默认 20）= `<engine>-search` 的 `-n` 默认值。
                      UT_SORT_FIELD       （默认 relevance；**uting 写回**）= `-s` 的默认值。
                      UT_PLAY_MODE        （默认 audio；**uting 写回**）= `-f` 的默认值，
                        播放器与两个 resolve 半边共用一个值。
                      UT_PLAY_QUALITY     （默认 auto；**uting 写回**）= `--quality` 的默认值。
                        auto|low|medium|high 四档；档位的含义只在引擎内部
                        （quality_sort_for_tier，(mode, tier) → yt-dlp sort，§1.3），
                        播放器只转发档位、从不翻译它。`uting` 在启动时校验它
                        （bogus 档退 1；空值**归一成 auto** —— `f` 键要轮换这个值，
                        而一个空串谁都不匹配，第一次按下就会跳过 auto 落到第二档）。
                        `uting` 没有对应的旗标，刻意的：一个档位是**设一次的调音**而不是
                        一次请求的选择（CLAUDE.md 的旗标/配置键规矩），agent 面是
                        `ut-play --quality`。
                      UT_VOLUME           （默认空 = 不动 mpv 自己的）= `--volume` 默认值。
                      UT_DEAD_KEEP        （默认 8）= 保留多少条已死播放器记录
                        （另有一小时的时间上限）。与站点无关：播放器不知道来源。
                      UT_PAGE_ROWS        （默认 10）= `uting` 每屏一页多少行，`-p` 的默认值。
                        只是一个请求：display_list_menu 会按窗口高度把它往下 reflow。
                        它与 `bili-search` 的 `PAGE_SIZE`（远端 API 自己的页，**不是**旋钮）
                        和下面的 UT_FETCH_BATCH 是三件不同的事。
                      UT_FETCH_BATCH      （默认 20）= 两条边各走多大一**步**：`→` 越过
                        最后一页追加这么多行，`←` 在第 1 页砍掉这么多行。也是第一次抓多少行
                        的回落值（见下面 UT_START_RESULTS）—— 一个旋钮而不是两个，它们本来
                        就是同一个 20 出于同一个理由：Bilibili 的端点每页 20 且没有页大小
                        旋钮，于是 20 让每一次抓取都是整数页。它与 UT_SEARCH_RESULTS 同为
                        20 却不是同一件事 —— 那个是引擎一次返回的**总数**，这个是每按一次
                        动多少行的**步长**，放宽其中一个不该顺带放宽另一个。
                      UT_START_RESULTS    （**未设 = 跟随 UT_FETCH_BATCH**；`-n` 压过它；
                        **uting 写回**）= 一次查询**从多少行开始**。**刻意不在出厂 `config`
                        里**（见上面那四个旋钮）：它未设时的含义是"另一个键的值"，
                        一条平的 `KEY=value` 表达不了这种链。
                        它与 UT_FETCH_BATCH 必须是两个键 —— 把 200 写进
                        步长里，之后每按一次 `→` 就加 200 行。第一次出现在用户配置里，
                        是 `→` 或 `←` 之后写回追加的那一行。
                      UT_RESOURCE         （默认 1）= `uting` 在播放 chrome 里画不画
                        播放器自己的 cpu/内存读数（列表横幅的尾巴、卡片的元信息行）。
                        口径是播放器的**进程组**（wrapper + mpv + 可能的回退 mpv，
                        pgid == wrapper pid），不是整机 —— 整机负载任何系统工具都给，
                        这个进程组只有拿着 pid 的 uting 知道。读法是一次
                        `ps -A -o pgid=,%cpu=,rss=` 加 awk 按组求和（约 24ms）：
                        `ps -g` 在 macOS 与 procps 下语义不同，全表扫描是唯一一种
                        两个平台同一拼写的读法；%cpu 取 ps 自己的语义（衰减/生命期
                        均值，不是瞬时值），rss 两边都是 KB。没有对应旗标：设一次的
                        调音。bogus 值启动时退 1 并点名这个键（与 UT_KEYS 同一道闸）。
                      UT_RESOURCE_TICKS   （默认 3）= 每几秒采一次样：采样骑在 TUI 的
                        共享 1 秒钟（fetch_play_times，两个视图都经过的那一拍）上每
                        N 拍跑一次，渲染只读缓存对。空闲不采：没在播就没有可量的组，
                        而钟本来也只在播放时转。
                      UT_KEYS             （默认 `core`；**uting 写回**）= 键位提示块印
                        多少：`core` 只印这个视图自己的活（移动、对行的动作、回程、`q`，
                        外加 `?` 自己），`full` 印它有的每一个键。`?` 键现场切换并写回。
                        **不是一个 cycle**：两档一道门，所以它没有 `_CYCLE` 伴生键 ——
                        一个只有两个成员的轮换，其顺序不是一个可配置的问题。一个不认识的
                        值**在启动时就退 1 并点名这个键**，与 UT_PLAY_QUALITY 同一道闸。
                        它隐藏的是**提示**，不是键：full 档里的每个键在 core 档下照样能按。
                      UT_MODE_CYCLE / UT_SORT_CYCLE / UT_THEME_CYCLE / UT_QUALITY_CYCLE
                        （默认 `audio video fast` / `relevance view_count duration` /
                        `minimal catppuccin tokyonight nord gruvbox onedark mono` /
                        `auto medium high`）
                        = `v` / `o` / `t` / `f` 四个键各自轮换的**顺序**，空格或逗号分隔。
                        质量档那一份出厂时**是值域的子集**（没有 low）：轮换是会被顺手转过去的
                        东西，而降质是特意的选择；要它的人在自己那份里写一次。
                        **轮换顺序不是合法值域**：`-f` / `-s` 对着**封闭集**校验，
                        不对着 cycle —— 一个把 cycle 收窄到一项的用户是在说"别再在 v 上
                        给我看别的"，不是"拒绝 `-f audio`"。拿 cycle 当值域，只在它还是
                        一个等于全集的常量时才安全；它一变成可配置，就开始拒绝引擎接受的
                        值，并逼着 `uting` 的默认值与引擎的不一致（这次搬迁抓出的那个 bug）。
                        一个空的 cycle 或一个不认识的成员**在启动时就退 1 并点名那个键**：
                        空数组在 3.2 的 set -u 下会在第一次按键时中止，那离用户真正写下的
                        那一行太远了。
                      YT_COOKIE_BROWSER   （默认 chrome = 登录开着；"none" = 只匿名）
                        —— 由每个**引擎**读，播放器从不读。变量名是**引擎名大写**加
                        `_COOKIE_BROWSER`（`YT_` / `BILI_` / …），与命令前缀同一条拼接规矩；
                        当前生效值靠 `<engine>-resolve --auth` 问出来（§3），
                        而不是靠调用方自己去读环境。
                      YT_AUDIO_FORMAT (ba/b)  YT_VIDEO_FORMAT (bv*+ba/b)
                      YT_VIDEO_FORMAT_FAST  —— **yt** 那张模式→格式表的值；它们跟那张表
                        住在一起，也就是住在 yt-resolve 里。别的引擎的那张表按 §6 的
                        前缀规矩拼自己的名字，不复用 YT_ 拼写。
                      BILI_COOKIE_BROWSER (chrome)  BILI_AUDIO_FORMAT (ba/b)
                      BILI_VIDEO_FORMAT (bv*+ba/b)  BILI_VIDEO_FORMAT_FAST
                        —— bili 引擎自己的那组，与上面 yt 组逐一对应（bili-resolve 读）。
                      BILI_UA  BILI_BUVID  —— bili-search 的 HTTP 传输旋钮
                        （AS-BUILT-engine.md §7.1）。`BILI_UA` 的**出厂值是一个真的
                        浏览器 UA 串**，和别的默认值一样只声明在 `config` 里：空值不是
                        "发一个空头"，curl 对空值的语义是**根本不发这个头**。
                        `BILI_BUVID` 空是对的 —— 那一个是每进程现生成的。
                      BILI_RETRY_PAUSE (1) —— 412 突发之后那**一次**重试前等几秒。
                        刻意是引擎专属的：这个停顿是为**这台**主机的突发限流存在的，
                        而这个文件是套件里唯一一处手搭 HTTP 请求的地方；`yt-search`
                        走 yt-dlp，根本没有一条重试路径给一个共享旋钮去管。
                      YT_SUB_LANG_CHAIN (en,zh-Hans,zh,ja) —— `--transcript` 的字幕语言
                        优先链。**引擎专属，而且必须是**：`bili-resolve` 根本没有
                        `--transcript`（它点名那个标志只为说这个站点没有字幕轨）。
                        一个跨引擎的拼法会是一个半个套件必须忽略的旋钮，
                        那比没有旋钮更糟 —— 调用方分不出是哪一半。
                      YT_ASCII_VO (tct)  YT_MPV_INPUT_CONF  —— 播放器侧的 mpv 旋钮。
                      YT_ASCII （1 = ASCII 字形回落；非 UTF-8 locale 下自动开；
                        由 uting 与全部四个引擎脚本读，播放器不读它 —— 遗留别名 YT_TUI_ASCII）。
                        它覆盖**整个**字形集：♫ ● ○ ❯ · ▶ ❚❚ • … → — ↑/↓ ←/→ ↵ ▘▝▗▖
                        以及那些条与轨的连排。验证方式是断言一个渲染出来的 pane
                        除了标签文字之外不含任何非 ASCII。
                      YT_LANG (en|zh；**uting 写回**) = uting 界面文字的语言；zh* locale
                        下默认 zh，否则英文。帮助输出、错误与卡片的字段标签两种情况下
                        都保持英文。
                      YT_THEME (minimal|mono|catppuccin|tokyonight|nord|gruvbox|
                        onedark；**uting 写回**) = uting 的配色家族（AS-BUILT-tui.md §11：
                        一个强调色加一个状态色；社区主题只在 COLORTERM=truecolor 下是 24-bit 的）。
                        --theme 压过环境变量；t 键在运行时实时循环它。
                      YT_BG (auto|light|dark) = 背景模式；auto 的链条：
                        $COLORFGBG → OSC 11 查询 → dark。Light = 该主题自己的浅色变体
                        （minimal 把青换成蓝）。
                      YT_SYNC (0|1|auto) = 同步重绘（DCS 1q/2q；auto：开，在 tmux 下关）。
                      YT_ICON (note|phones) = 页眉那个两格图标槽里放哪个字形：
                        `note` = ♫ U+266B（一格，补一个空格填满槽），
                        `phones` = 🎧 U+1F3A7（East-Asian Wide，自己就占两格）。
                        两个都量成 2，所以 wordmark 起始列一样、查询在同一个字符处省略。
                        未设置 = 每次启动掷一次硬币；要一帧出两次一样就钉住它。
                        `YT_ASCII=1` 整个丢掉这个槽，并压过这个旋钮。
                        不认识的值退 1。只有 `uting` 读它。
                      YT_BRAND （=1：页眉 wordmark 用数学无衬线粗体，AS-BUILT-tui.md §11 字形一节；
                        opt-in，ASCII 模式压过它）。
                      YT_AMBIG_WIDE （=1：East-Asian Ambiguous 那批字形（· — • … 箭头 ─ ━
                        ○ ● ▶）量成两格。只在你的终端把 ambiguous 宽度设成双宽时才需要 ——
                        每个终端出厂都是关的（AS-BUILT-tui.md §11）。）
                      NO_COLOR （=1：--color auto 渲染成朴素的；显式的 --color 压过它）。
   内部（由播放器为它自己的 detached 子进程设的，不是用户旋钮）：
                      YT_IPC_SOCK （每个播放器一个的 mpv IPC socket）  YT_DETACHED （=1：
                      没有终端，所以 mpv 安静且不过滤 stderr）  YT_PLAYER_ID （子进程把
                      title/format 补回哪一条记录，AS-BUILT-player.md §9.1）
                      YT_DETACHED_LOG （detached mpv 的日志路径；死亡记录的分类器
                      从它尾部读）
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
别的什么也不改（ARCHITECTURE.md §3.1）：

1. **`foo-search`** —— §1.2 那个面：标志 `-n -m -M -s -l -j -J --color -h -V`，
   一个 QUERY 位置参数（拒绝 URL，`--` 之后重新检查），§3 那个搜索信封且
   `engine:"foo"`，错误按 §3 且退出 2+（§4）。**每一行还要算出 `kind` 与 `access`**
   （§3 的两问、封闭枚举、`-j` 与 `-J` 都要；没有信号就如实印默认值，不猜），
   并且**不把 `url` 建不出来的记录放进信封**。
2. **`foo-resolve`** —— §1.3 那个面：标志 `-f -S -l -j -J --color -h -V`
   加上**仅仅**这个站点支持的那些动词（§1.3：以"有没有"声明能力）；`-f` 只收那五个
   规范模式 —— 别名是 `ut-play` 的（§1.3）；§3 那个解析信封
   （`stream_urls[]` 视频在前、`http_headers{}` 必需且不含凭据、`format` 不透明、
   `selected`/`selected_resolution` 是提取器**挑中**的那一个而不是请求的回声、`retried`、
   **`start_seconds`**）；
   一份显式的本站 host 白名单 —— 一个非本站的 URL 或一个畸形的 id 是用法错误，退出 1（§3）。
3. **`start_seconds`（§3）—— 先量，再决定写不写解析代码。** 第一步是跑一次
   `yt-dlp -J '<一个带时间戳的本站 URL>' | jq .start_time`。**有值就白拿**：读它，
   归一成 `null` / 非负整数秒即可（`yt-resolve` 就是这样，YouTube 的十种写法一行解析代码都没写）。
   **没有就自己解**，在 `normalize_target` 里、任何网络请求之前，只认这个站**实测存在**的写法
   （`bili-resolve` 就是这样，yt-dlp 对 B 站任何形态都不给这个键）。
   本站根本没有时间戳语法就恒填 `null` —— 那是合法状态，不是缺口。
   同时检查这个站的 `webpage_url` 会不会把偏移带进 `url`；会的话就剥掉它，且**只剥它**。
4. **`foo-resolve --auth`** —— cookie 决定读自 `FOO_COOKIE_BROWSER`（引擎名大写，
   §5），信封按 §3，且 `auth=="cookie"` 与 `cookie_browser != "none" and profile_found`
   等价。不吃位置参数，拒 `-f`/`-S`/`-J`，在依赖门之前作答。
   `tests/contract.sh` 把这几条当作对**每一个被发现的**引擎的不变量来断言，
   所以第三个引擎落地那天它就被覆盖了 —— 不是等谁想起来去加一行。
5. **旋钮前缀：** 引擎自己的调校一律读 `FOO_*`（引擎名大写 —— cookie、格式、传输，
   同一条规矩；§5 里 `BILI_*` 那族就是样子）。`UT_*` 是套件级的（`UT_STATE_DIR`、
   `UT_DEFAULT_ENGINE`、`UT_HISTORY`），引擎不得新增；`YT_*` 是 yt 引擎自己的前缀，
   外加那批冻结的遗留套件级名字（§5 结尾）—— 它不是模板。
6. **两半都要：** `ENGINE_NAME` 从一个常量印出来；每一个信封（包括错误）里都有 `status` 与
   `engine`；一个信封一行（§3）；`-V` 在任何依赖门之前回答（§4）；
   门把跨界标志指向正确的动词（§2）。
7. **别的什么也没有：** 没有播放，没有生命周期，不写 `players/` —— 播放器靠名字找到
   `foo-resolve`（§1.1），而 `uting` 靠在 PATH 上和自己旁边扫描 `foo-search` + `foo-resolve`
   这一对来发现它（AS-BUILT-tui.md §11）。

引擎按动词自己挑传输（curl 或 yt-dlp 或别的任何东西）—— 接缝是信封，不是它背后的工具
（ARCHITECTURE.md §3.4）。
