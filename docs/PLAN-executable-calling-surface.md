# PLAN —— 让「调用面」里的示例真的被执行

**实现的 roadmap 条目：** `ROADMAP.md`「还没做的事」→ **让「调用面」里的示例真的被执行**。

**状态：** §1 / §2 / §3 / §4 全部已落地（2026-09-01）。前一个单元（「调用面」段本身）已落地并提交，见下面「已落地的前置」。

---

## 为什么

2026-09-01 四个 as-built 各得了一段「调用面」，CLAUDE.md 硬规则 2 为此开了唯一一个 carve-out。
那条 carve-out 自带一半的防腐：**写进去的每一条 refusal 必须先是 `tests/contract.sh` 的一条
检查**，所以被拒的组合有东西兜底 —— 代码一变会先红。

**另一半没有兜底：可跑的调用那几行。** flag 拼错、参数换序、某个组合以后不再合法，它们会一直
静静地错着。同一个 session 里就有现成的反例：`-f viz` 换了滤镜链，四句指着 `showwaves` 的
prose 立刻变成假的，没有任何检查发现，是事后 grep 全树抓到的。

所以这个单元要做的事只有一句：**把那些示例里离线跑得通的部分，变成套件真的跑一遍的东西。**

## 边界（先定死，否则会长成一个 example runner）

- **不引入新文件。** 检查落进 `tests/contract.sh`，跟着它已有的分节。
- **不解析文档。** 不写"从 markdown 里抽命令再执行"的东西 —— 那是一个 rig 层，撞
  CLAUDE.md 的 functional-only 强制条款，而且它会让文档变成可执行输入，谁改文档谁弄红套件。
  **方向是反的：检查是权威，文档是它的读者视图。** 落地时把文档里的示例行调整成与检查里
  实际跑的那条一致，不是反过来。
- **不测网络路径。** 真解析、真播放留在 prose 里，照 `AS-BUILT-player.md`「调用面」的做法
  标**「实测」**而不是「已证」，并写清为什么证不了。
- **不为凑数。** 一条示例只有在"拼错了会静默错下去"时才值一条检查；`--help` 能自己答的不算。

## 逐项

### 1. engine —— 三个只读动词的门（离线） · **已落地**

`AS-BUILT-engine.md`「调用面」的示例里，这几条不需要网络，因为门在 host 门之前答：

- `<engine>-resolve --auth -j` —— 无句柄、无请求、无 yt-dlp。**已有检查**
  （`every engine answers --auth -j`），只需确认文档那行与它一致。
- `<engine>-resolve --info -j -- <未被任何引擎认领的句柄>` —— 会走到 host 门。这里要证的是
  **`--info` 本身被接受**（不是被当成未知 flag 拒掉），所以断言的是错误文案属于 host 门。
- `bili-resolve --parts -j -- <同上>` —— 同理，且 `--parts needs no yt-dlp` 已有检查。

**done_when：** 每条示例的 argv 都被某条检查原样执行过一次；新增的断言是**文案**而不是
退出码（这三条都退 1）。**已达成：**

- 新检查 `every read-only verb reaches the host gate`：跟在只读动词 × 格式 flag 那条乘积后面，
  复用它的 `_ro_verb_has` 发现与同一个无人认领的句柄，按文档那行的 argv（`-j` 在动词前、
  `--` 在句柄前）跑，断言报回来的是 host 门那句 `needs its own engine`。**4 例**
  （yt 的 `--info`/`--transcript`、bili 的 `--info`/`--parts`），下限写成 `>= NENG` 而不是字面量。
- 顺带收进**第四个**只读动词 `--transcript` 与它的伴随 flag `--sub-lang zh-Hans` —— 同一个循环，
  白拿，而且文档那行本来就带着它。
- 判别输入（不改任何在产文件）：`yt-resolve -j --parts -- <无人认领>` 报的是
  `unknown flag`，**退的同样是 1**，文案不匹配即红 —— 所以钉的是文案不是退出码。
- `--auth` 那行改的是**文档**（`-j --auth` → `--auth -j`），与既有检查
  `every engine answers --auth -j` 实际跑的 argv 对齐，方向按上面「边界」那条。
- 两条检查都盖不住的事，已在注释里写明：某个引擎**删掉**一个动词 —— 发现会跟着适配，
  要钉它得有一张"谁有哪个动词"的表，而这一节存在的目的就是不要那张表。
- 文档那三条要真解析的行（`-f audio`、`--quality high`、`-S`）按「边界」留在 prose 里，
  标**「实测」**（2026-09-01 手跑验过，三条都 status ok）而不是「已证」。
- 顺手 resync 了 `contract.sh` 开头那段成本声明（它自己的规矩是"claim 要跑不是读"）：
  ~55s / ~20s、207 of 305，并写明为什么这里不给分节数字（管道一接输出就块缓冲，
  给 section header 打时间戳量的是 flush 不是活）。

`contract.sh --offline` **207 ok / 0 failed**；完整 **305 ok / 0 failed**。

### 2. contract —— 三种 stdin 形状的整条管道（离线） · **已落地**

`AS-BUILT-contract.md`「调用面」的四条管道，除了最后那条 `--enqueue` 需要一个在跑的播放器，
其余三条在一次性 `UT_STATE_DIR` 下完全离线。已有检查覆盖了**存储侧**
（`--ls feeds ut-playlist --add`、`a search envelope tags engine`），缺的是**文档里那条
管道原样跑一遍**：

```sh
<engine>-search -j -n N -- Q      | ut-playlist --add NAME     # 需要网络 → 用固定信封替代
ut-playlist --show NAME -j        | ut-play -d --queue -       # 会真起播放器 → 见下
ut-history --ls -n N -j           | ut-playlist --add NAME     # 离线
```

- 搜索那条：用一份**固定信封**（fixture，是数据不是替身）喂 `ut-playlist --add`，
  与文档里的管道等价，且不发包。
- `--queue` 那条：会真启动一个 detached 播放器，属于 `tests/playback.sh`。在 `contract.sh`
  里只证**形状被接受**（今天 `a --show envelope parses` 已经是 4，即形状对但没有可作用对象）；
  真起播的那一版加进 `playback.sh`,或者明确不加并在文档标「实测」。
- `ut-history` 那条：完全离线，直接落 `contract.sh`。

**done_when：** 三条管道各有一条检查跑过，且 `1 vs 4` 那张表的每一行都指得到一条现有检查。
**已达成：**

- **管道一（搜索 → `--add`）**：`contract.sh` 离线段，playlist 那一节开头。原来那行就是固定
  信封喂 `--add`，但带着 `-j`；改成文档那行的 argv（prose 模式，是另一条出口），并把管道
  自己的退出码单独断言成一条 —— `search envelope | --add: 0`。
- **管道二（`--show -j` → `-d --queue -`）**：**`playback.sh`**，不是 `contract.sh`：它真起
  播放器。原来那一节用 `jq -nc` 现搭一个数组，证的是数组那条臂，而文档登的是 `--show` 那条。
  现在条目先 `ut-playlist --add` 存进去、再 `--show -j` 读出来喂 `--queue`，跑的就是文档那行
  （`the list stored 2` + `--queue - launches`）。
- **管道三（`ut-history --ls` → `--add`）**：`contract.sh`，把既有的
  `--ls feeds ut-playlist --add` 硬化到文档 argv（左半加 `-n 20`，右半去掉 `-j`）。
- **管道四（`ut-history --ls` → `-d --queue -`）**：只证形状 —— 离线段用 `--enqueue` 问同一个
  `read_queue_items`，空闲答 4（`--ls reaches the queue gate`）。起播那半与管道二同一段代码，
  不另证，注释里写明这条 4 **不**证明 per-item engine tag 活着（未标 engine 的条目会落到
  播放器的默认引擎，两种写法都过这道门）。
- **管道五（`--show -j` → `--enqueue -`）**：`a real --show reaches the gate`，4。它与既有的
  `a --show envelope parses` 的区别就是本节存在的理由：那条喂的是**手写**对象，只证得了
  ut-play 认那个形状；这条左半是真 `--show`，`--show` 一旦漂移就红。
- 判别输入（不改任何在产文件，2026-09-01 跑过）：`{"status":"playlist","rows":[…]}`（把
  `items` 改名）→ **1**；`{"status":"playlist","items":[{"engine":"yt"}]}`（条目缺 url）→
  **1**；`{"status":"ok","engine":"yt","hits":[…]}`（把 `results` 改名）喂 `--add` → **1**。
  三条新检查各自要的那个值（4 / 4 / 0）都被分开了，都不是不可能红的检查。
- **`1 vs 4` 那张表**：前两行每个例子都指得到离线段的一条（不是 JSON / 空队列 / url 带空格 /
  engine 名可疑 / 没形状的对象；空闲 `--set-volume` `--pause` `--seek` `--next` `--enqueue`
  的 4 与 `not_playing`）。第三行原来**只有退出码**：`playback.sh` 的 `--set-volume no --id`
  答 4，而空闲调用**也**答 4 —— 把两者分开的只有 `status`，而它当时没有任何检查。补了
  `…and says ambiguous`（`status`/`reason`/`players` 三个字段一次断言）。它第一次跑是红的，
  原因是 `set -o pipefail` 下管道带的是 ut-play 自己的 4 而不是 jq 的判定 —— 正是
  `contract.sh` 的 `jq_ok` 为之存在的那个坑；改成先捕获再判。
- 「动作彼此排斥」那四条（`--status --stop`、`--status --id X`、`-d --stop`、
  `--queue -` 不带 `-d`）本来就各有一条，无需新增。
- 文档侧：`AS-BUILT-contract.md`「调用面」的五行加了「已证 / 形状已证」标注（照
  `AS-BUILT-engine.md` 同名段的写法），并补了一段说明**谁证的、各自付了什么代价**，以及
  1 vs 4 表第三行为什么只能在 `playback.sh`。顺带 resync 了两个套件的成本声明与
  `README.md`／`CLAUDE.md` 里过期的计数（README 还停在 278/193、~100s）。

`contract.sh --offline` **210 ok / 0 failed**；完整 **308 ok / 0 failed**；
`playback.sh` **51 ok / 0 failed**。

### 3. player —— viz 的五条示例（大部分要网络） · **已落地**

`-f viz` 的正例都要真解析。能离线证的只有 argv 被接受：

- `UT_VIZ_STYLE=wave` / `bars` 都过门（`UT_VIZ_STYLE: a legal value reaches the handle gate`
  已覆盖 `wave`，`bars` 没有）。
- `--start 90 --quality low -f viz` 的组合过门 —— 三个 flag 同时给，今天没有检查。
- `--engine bili -f viz` 过门。

**done_when：** 五条示例的 flag 组合都被门接受过一次（断言"不是这三个 flag 之一报的错"），
剩下的画面部分继续标「实测」。**已达成：**

- 新 helper `viz_reaches_engine`，跟在 `UT_VIZ_STYLE` 三条后面，五条示例各一条检查。
  断言比 done_when 写的更强：不是「不是这三个 flag 报的错」，而是**报回来的必须是引擎那句**
  `<engine>-resolve could not resolve` —— 也就是每个 flag 都被收下、组合合法、调用一路走到了
  引擎。句柄用一个没有引擎认领的 host，整条离线（host 门在 yt-dlp 之前答，量到 **0.05s**）。
- `--engine bili` 那条的判据是文案里的**引擎名**（`bili-resolve` 而不是 `yt-resolve`），
  所以它不是第一条的重复：一个被解析了又被丢掉的 `--engine` 会报 `yt`。
- `bars` 单独一条，理由写在注释里：既有那条驱动的是两成员枚举里的 `wave`，而**默认是另一个**
  —— 一道只放行自己默认值的门会在上面绿、在这里红。
- 判别输入（不改任何在产文件，2026-09-01 跑过）：`--quality ultra` → mode 门；
  `--start 90.5` → `--start` 的值门；`--engine nope` → 引擎名门；`-f vizz` → mode 门；
  `UT_VIZ_STYLE=bogus` → 那个键的门。五个全都不是 `could not resolve`，所以五条都能红。
- 文档侧：`AS-BUILT-player.md`「终端可视化」五行加了「已证」标注，并补一段写明**「已证」在
  这里证的是 argv 不是画面**，以及为什么判据是文案。`-f viz -j` 那条画面全无的陷阱仍然只标
  「实测」，理由原样保留。

### 4. tui —— 两道门的顺序（离线） · **已落地**

`AS-BUILT-tui.md`「调用面」说的"flag 门在前，TTY 门在后"今天有两条检查
（`uting refuses -f ascii/viz, naming the modes` 与 `…and it is the TTY gate, not a flag error`），
但**顺序本身**没有被直接证过：一个合法的 `-f` 加上一根管道,报的必须是 TTY 门。

**done_when：** 一条检查证 `uting -f audio </dev/null` 报的是 TTY 门,和一条证
`uting -f viz </dev/null` 报的是 mode 门 —— 同样的 stdin,不同的门,顺序就被钉住了。
**已达成，并且比原计划多收了一样东西：**

- 新 helper `uting_gate`（答 `tty` / `mode` / `unknown-flag` / `other`），**紧挨着**
  `-f ascii|viz` 那个循环放 —— 顺序这个claim要两条检查并排才读得出来，隔开就不成一句话了。
- 合法 `-f` 那一臂用的是 `-f video --volume 60`（文档自己那行）而不是计划里写的 `-f audio`：
  同一件事，且顺手把文档那行也跑了，不用为同一个claim多加一条。
- **顺带把「调用面」那五行 uting 示例全跑了** —— 管进 `</dev/null` 之后每一行都该落在 TTY 门，
  所以一条断言同时管两件事。**于是抓到了真的腐烂**：第五行写的是
  `uting --theme nord --lang zh`，而 **`--lang` 根本不是 uting 的 flag**（chrome 语言是
  `YT_LANG`，`l` 键实时轮换）。它就那么错着，直到这一节第一次真的跑它。文档已改成
  `YT_LANG=zh uting --theme nord "…"`，方向照本单元「边界」那条：检查是权威。
- 判别输入：文档那条**旧**的 `--lang zh` 行答的是 `unknown-flag` 而不是 `tty` —— 这条检查
  第一次跑就会红，这正是它存在的意义；`-n -40` 答的是 `-n` 自己的门。
- `AS-BUILT-tui.md`「调用面」加了「已证」标注、那段腐烂的记录，以及顺序是怎么被钉住的一段。

## 验证矩阵

| 项 | 怎么证 | 在哪 |
|---|---|---|
| 1 engine 只读动词的门 **已落地** | 真调用 + 文案断言 | `contract.sh` 离线段，4 例 |
| 2 三种 stdin 形状的管道 **已落地** | 固定信封 + 一次性 `UT_STATE_DIR` | `contract.sh` 离线段；起播那条在 `playback.sh` |
| 3 viz 的 flag 组合过门 **已落地** | 文案断言（必须是引擎那句 `could not resolve`） | `contract.sh` 离线段，5 例 |
| 4 两道门的顺序 **已落地** | 同一 stdin，两个 `-f`，两种文案 | `contract.sh` 离线段，5 例 |
| 画面本身 | 真 pane 抓帧 | 不入套件；文档标「实测」 |

**除了管道二，全部落在 `--offline` 之前**,所以这个单元几乎不延长 push 门；管道二
（真起播放器）落在 `playback.sh`，那本来就不是 push 门的一部分。

## 收尾

四项全部落地。`contract.sh --offline` **220 ok / 0 failed**（~19s）；完整
**318 ok / 0 failed**（~60s）；`playback.sh` **51 ok / 0 failed**（~82s）。
四个 as-built 的「调用面」里，能离线跑的示例现在都被套件真的跑过一遍；剩下标「实测」的那几条
各自写清了为什么证不了。抓到的两处真腐烂：`AS-BUILT-tui.md` 的 `--lang`（不存在的 flag），
以及 `playback.sh` 里队列那节证的是数组那条臂而文档登的是 `--show` 那条。

**本 PLAN 可以在 land 时删除。**

## 已落地的前置（2026-09-01，五个提交）

```
dba3440 docs: resync the four places that still named one lavfi filter
54f5fc7 0.4.8
c472dd8 docs: 接口 becomes 接口与 API and takes the calling surface
1584d26 tests: the option product gets checks
1efa157 ut-play: -f viz gets two pictures, drawn at the pane's real resolution
```

- CLAUDE.md 硬规则 2 的 carve-out 与三段式规格里的段名（`接口` → `接口与 API`）已改。
- 四个 as-built 的「调用面」段已写；`AS-BUILT-player.md` 另有「终端可视化」。
- 新增检查：`UT_VIZ_STYLE` 三条、终端渲染模式跨三个面的不可 detach、只读动词 × 格式 flag
  的 12 例乘积。`contract.sh --offline` 206 ok / 0 failed；`playback.sh` 49 ok / 0 failed。

## 交接时的未结项（不属于本单元）

- ~~push 门当时过不去~~ **已结（2026-09-01）。** 那两条红（`bili --parts envelope`、
  `one part is still a list`）不是回归，但也不只是环境：`x/web-interface/view` 从两个网络、
  每一种 header/cookie 组合都回 412。已由 `7b39373` 关掉 —— `--parts` 在 view 被拒后退到
  `x/player/pagelist`。完整 `tests/contract.sh` 现在 **304 ok / 0 failed**，push 门通。
- ~~worktree 里仍有三处**不属于本单元**的未提交改动~~ **已落地（2026-09-01，`a957c1b`）。**
  `README.md`、`shell/uting`、`docs/AS-BUILT-tui.md` 里那段双 rail / 章节视图是另一条线的
  在飞工作，本单元始终没有动它（`2bf4962` 用过滤后的 patch `git apply --cached` 只入了本批的
  hunk）。那条线自己收了尾：第二条 rail 缺的另一半是**光标也要跟着播放头走**，否则一章放完
  就钳在 100%、正在播的那一章在屏幕上没有东西。worktree 现在是干净的。
