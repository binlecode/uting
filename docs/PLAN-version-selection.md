# PLAN —— 版本选择：质量档、分 P、章节

**落地于** `ROADMAP.md`「还没做的事」第 1 条（「B 站的一条搜索结果 ≠ 一个可播对象 —— 合集至少要标出来」）。
那一条点名了**分 P** 是同一问题的第二种形态，并把「选哪一种标法」留给 `PLAN-` 展开。本文档是那次展开，
外加一条它没覆盖的轴：**质量档**。

**版本影响**：三项都是**新增**（新动词、新标志、新键位，不改任何既有信封字段的含义），
按 `CLAUDE.md` 的 semver 规则是 **z 位**。落地后 `0.3.11` → `0.3.12`
（本计划写就时基线还是 `0.3.10`；另一条线在 2026-08-29 把 `VERSION` 推到了 `0.3.11`，与本计划无关）。

---

## 0. 状态

| # | 条目 | 状态 |
|---|---|---|
| P1 | `<engine>-resolve --parts` 动词 + 信封 | **已落**（2026-08-29；`bili-resolve` + `tests/contract.sh`，契约文档留给 P9） |
| P2 | `uting` 的 parts 行源（`LIST_SOURCE="parts"`，`c` 键） | **已落**（2026-08-29；`shell/uting` + `contract.sh` 的 tmux 面上一条 `c` 能力门见证，257 项全绿；五次 drive 实测记在 §13） |
| P3 | `--quality TIER` 贯穿 `ut-play` → `<engine>-resolve` | **已落**（2026-08-29；`ut-play` + 两个 resolve 半边 + `config`；`contract.sh` 256 项 + `playback.sh` 44 项全绿；档位效果与 `-S` 压过 `--quality` 均实测） |
| P4 | `uting` 的质量档键位（`f`）与写回 | **已落**（2026-08-29；`shell/uting` + `config` 的 `UT_QUALITY_CYCLE`；`contract.sh` 263 项全绿，其中三条新检查在 tmux pane 上：`quality=` 在 auto 上不印、`f` 追加写回 `UT_PLAY_QUALITY=medium`、状态行跟上；四个 cycle 键的「不认识的成员退 1」由一条加固过的循环统一陈述） |
| P5 | **焦点卡扩成「条目视图」**，元数据不另开渲染器 | **在建**，**P6 的前置**。前置 F04 **已落**（2026-08-29；`JQ_TEXT_DEFS` 一份定义，两个 row builder 与 `apply_player_record`（含 `queue.next.title`）共用；实测见 §13 末）。**A 步已落**（`CARD_SUBJECT` + `card_subject_head` / `card_meta_row` 抽出 + `card_item_body`，屏幕零变化，旧新双树逐帧对照）。**B 步的门已落**（`i` 键 + `ENGINE_INFO_OK` 探测 + `apply_item_info` + 单槽缓存 + `nav_tick` 按 subject 早返回 + Tab 进门即复位 subject；`contract.sh` 268 项全绿，其中三条新检查在 tmux 面上，并把面里的 `YT_LANG` 钉成 en 才能断言 chrome 字串）。**余下：在播分支的前方队列块（§11 修订一）、`selected` 格式行、卡内 `i` 对在播曲目叠 info、F05 提示格按视图态把门、文档重同步** |
| P6 | 章节 → 条目视图里的 seek 目标 | 未开工，排最后 |
| P7 | Enter 语义不变 | **无需改动**，记录在案以免日后当成疏漏 |
| P8 | 时长不一致 → 在 parts 视图表头说清 | 已落（随 P2，2026-08-29） |
| P9 | 文档重同步（六个 as-built + `config` + `CLAUDE.md`） | **已落**（2026-08-29；audit 清单 + 契约 §1.1/§1.3/§1.4/§3/§4/§5、§17 六个函数、engine/tui/player/verification、CLAUDE.md。「六个键」的文本当时**刻意没动**，P4 落地时一并改成「七个」，见 §6） |
| P10 | 退役 `p`/`P` 的 Tab 别名（键位审计 §12） | 未开工，两行级 |
| P11 | `j`/`k` = ↓/↑ 别名（键位审计 §12） | 未开工，两行级 |
| P12 | `?` 随时呼出/收起 keymap（用户新增，2026-08-29） | 未开工 |
| P13 | resolve 信封加 `selected` / `selected_resolution`（**§5.2**，本计划两项契约动作里的第二项） | **已落**（2026-08-29；两个 resolve 半边 + `ut-play` 的记录/回填/`--status` 投影；`contract.sh` 265 项 + `playback.sh` 45 项全绿）。落地时比 §5.2 多做了一处：`--status -j` 的**投影是一份写死的键集**，不是记录的透传，所以 `selected` 不加进那份键集就永远到不了调用方 —— §13 里 player record 那条检查本身就够不着。请求那一半（`format`）**没有**跟着进投影：它是一句 yt-dlp 表达式，而 `--status` 回答的是「现在在放什么」 |

§4 的编号 = 阅读顺序 = 上表的编号，**一套号，不是两套**。P9 与 P13 是表上仅有的两行
没有 §4 小节的条目：前者是文档重同步，后者的正文就是 §5.2 —— 都不是设计决定，所以不占 §4 的号。

§9 的三个开放问题**已由用户拍板**（2026-08-29），答案就地记在那一节。

---

## 1. 触发这份计划的三件事

用户的原话是「list 模式下选中项的详情不全 —— 媒体详细信息、选了哪个版本播的」，追问后收敛为两条轴
（质量档、分 P/章节），一条被实测顶出来的 bug。

### 1.1 行在说一件播不出来的事（实测）

```
bili-search 那一行         BV1vKEn6eE6Q   10h:32m:03s   ← 500 集加起来
bili-resolve --info 裸句柄  BV1vKEn6eE6Q   00h:12m:06s   ← 只有第 1 P
bili-resolve --info ?p=7   BV1vKEn6eE6Q   00h:06m:22s   ← 第 7 P
```

按回车放出来的是 12 分 06 秒，行上写的是 10 小时 32 分，第 2–500 P 在界面上**根本够不着**。
这正是 §11 那一条说的「不标不行」，只是它举的例子是合集时长，实测出来的这个更硬：**行不是含糊，是不对。**

### 1.2 「选了哪个版本播的」今天答不出来

两个 resolve 半边都已经在跑 `yt-dlp --dump-single-json -f "$FMT"`，那份原始记录里**已经带着答案**
（`.format` = `"234 - audio only (Default, high)"` / `"96 - 1920x1080"`、`.resolution`、`.ext`、`.fps`），
但信封只发 `format`，而那是**格式选择串**（`ba/b`）—— 是请求，不是回答。

### 1.3 选不了版本

`-S`（format-sort）其实已经贯通了：`ut-play:427` 转发给引擎，`:1580` 再转发给脱离子进程。
`ut-play -f video -S res:720 -- URL` 今天就能放 720p。缺的是**任何地方都不列出有哪些档**，
以及一个人能按的键。

---

## 2. 实测到的事实（本计划的证据基座，2026-08-29）

每一条都是跑出来的，不是读出来的。

1. **一个普通视频有 44 个 format**（去掉 storyboard 剩 40）。同一个 1080p 出现 5 次：
   `137`(avc1) `248`(vp9) `399`(av01) `614` `616`(Premium)。音频是 `139/249/250`(~50k)、`140/251`(~130k)。
   **一个 40 行的原始列表不是可选的东西，但它干净地收敛成 ~6 个档。**

2. **两个引擎的 `--info` 都带 `chapters`，且两边都真有值。**
   `yt-resolve --info` → `Intro · I. Allegro con brio · II. Andante · III. · IV.`；
   `bili-resolve --info` → `引言 · Flower Dance · 卡农 · Luv Letter · River Flows in You`。
   **章节不是 B 站独有的**，它是一个已经在册的跨引擎字段。

3. **分 P（`?p=N`）是 B 站独有的。** YouTube 一个 id 就是一个文件，它的多条目对应物是 playlist（另一个 URL）。
   `bili-resolve` 特意让 URL 查询串原样透传（`shell/bili-resolve:335`），所以 `?p=7` 今天就能解、就能播。

4. **搜索响应里没有分 P 计数 —— 实测，这条否掉了两个方案。**
   直接打 `search_type=video` 端点，取那条 500 集视频的全部数值字段：
   `play favorites review like danmaku pubdate is_pay is_union_video …`，**没有一个是 P 数**。
   `episode_count_text`（`共112课时`）只在 `ketang` 付费课记录上有值，而那些记录没有 `bvid`，
   `bili-search` 早就用 `select(.url != null)` 丢掉了。
   API 给的 `duration` 是 `632:3`（MM:SS），即 10h32m03s —— **只有聚合时长，没有第 1 P 的时长。**

5. **`ut-play -S` 与 `<engine>-resolve -S` 已贯通**（`ut-play:204/427/1580`），是今天唯一的换版本手段。

6. **套件里没有任何 format 列举动词**（全树 grep 无 `--list-formats`）。

7. **`V` 不是空键。** 派发是大小写同绑的（`v | V) cycle_mode`），`n o e l t a b d h q` 同理，
   `p/P` 是未公开的 Tab 别名。**空字母只有 `c f g i j k m r u w x y z`。**

8. **分 P 枚举的两条路线，实测对决（2026-08-29，同一 BV）：**
   `curl GET /x/player/pagelist?bvid=…` + bili-search 同款 UA/Referer、零凭据 → **200 / code 0 /
   0.38s / 一次请求 / 100 条，每条带真标题（`part`）与整数秒时长**（P1=727、P7=383，与
   `--info` 实测的 726.855/382.572 吻合）。`yt-dlp --flat-playlist`（带 bili-resolve 同款
   浏览器 cookie）→ 2.3s 能通，**但每条只有 `{ie_key,_type,url}` —— 无标题无时长**，
   正是 ARCHITECTURE D19 记过的「flat 无元数据」；匿名则 412。**机制只能是手搓 HTTP，不能是 yt-dlp** ——
   打哪个端点由 §5.1 定（那里改成了 `view`，理由与实测同样记在那）。

9. **「全500集」是标题营销：pagelist 实报 100 P。** 搜索行的聚合时长（37923s ≈ 100 P × 平均 379s）
   与 100 P 自洽。信封示例与 mock 里凡写 500 处均按 100 修正。

---

## 3. 三条轴是三件事，不要合成一个功能

| 轴 | 它到底在选什么 | 换档的动作 | 跨引擎？ |
|---|---|---|---|
| **质量档** | 同一段内容的**不同编码** | 换 format 选择 → 重新 resolve | 是（yt-dlp 概念） |
| **分 P** | 同一个号底下的**另一个文件** | 换句柄 → 重新 resolve | 否（只有 B 站） |
| **章节** | 同一个文件里的**一个偏移** | `--seek-to`，**不重新 resolve** | 是（两边都有值） |

把它们捏成一个「详情视图」是这份计划最容易犯的错：分 P 是**可播的行**，章节是**seek 目标**，
质量档是**下一次播放的参数**。三种东西，三个归宿。

---

## 4. 决定

### P1 —— `--parts` 归 resolve 半边，不归 search 半边

**照 ARCHITECTURE D15 的原样。** 它否掉「往搜索信封里加 `auth` 字段」的两条理由，这里逐条对上：

- **两个引擎不对称**：B 站有分 P，YouTube 没有。让 `yt-search` 报一个恒为 `null` 的字段，
  描述的是「这个站没有这个概念」，不是这条结果的事实。
- **搜索半边算不出来**：§2 第 4 条实测，搜索响应里根本没有 P 数。要让 `bili-search` 报它，
  得**对每条结果多打一次 `/x/web-interface/view`** —— 而 `bili-search` 的稀缺资源恰恰是请求数
  （ARCHITECTURE D19 量过：非 flat 的 yt-dlp 搜索 10 条要 >120s）。

而 resolve 半边**一次调用就知道**。引擎用动词的有无声明能力（`AS-BUILT-contract.md` §1.3 末条）：
`bili-resolve` 长出 `--parts`，`yt-resolve` 永远不长。第三个引擎当天自愿加入。

### P2 —— parts 是自己的 `LIST_SOURCE`，复用 list 渲染器

「自己的视图」赚到的是自己的 `LIST_SOURCE` 值、自己的返回栈行为、自己的状态行标签，
**不是自己的渲染器**。一个 part 是 `{engine, url, title, duration}` —— 正好是 `ut-playlist` 存的记录、
`ut-play --queue` 消费的记录。走既有渲染器白拿：分页、reflow、活过滤、Enter 播放、`+` 入队、
`a` 存进播放列表、details 块。

先例就在文件里，`open_playlist`（`shell/uting:3436`）自己写着：
> *列表视图不变 —— 同一个渲染器、同一个过滤、同一套键 —— 因为播放列表信封产出的是搜索一样的七字段行。变的是 `LIST_SOURCE`。*

**触发是 `c` 键（集 / collection），开也是它、关也是它。** 它属于**已经存在的那个键族** ——
`b` 换成播放列表、`h` 换成收听日志、`c` 换成分 P —— 三个键做同一件事：把行源换掉。
照 `h`/`b` 已定的规矩（`shell/uting:3496` 那段注释）：一个 toggle 不需要第二个键去学。
**不用 `Esc`** —— 在 bash 3.2 的地板上，孤立的 `Esc` 与方向键首字节无法区分，
只能等满一秒（`read -t` 只收整数），一个要一秒的「返回」键读起来就是坏的。

**选中项变化时什么都不发生。** 一次按键，一次 fork。

**它不触犯「没有第三个视图」那条决定**（`AS-BUILT-tui.md` §11，见 P5）：
被否掉的是**第二个渲染器**，而 parts 一个新渲染器都不加 —— 它走的就是 `display_list_menu` 本身。

### P3 —— 质量档是**规范档位**，不是一个 `-S` 串

**这是最容易做错的一处。** 把 `res:720` 放进 `uting` 的配置里，就是让 TUI 拿着一个 yt-dlp 表达式 ——
正是 `format_for_mode` 住在引擎里的那条理由（`shell/yt-resolve:327`）：
> *`bv*+ba/b` 是一个 yt-dlp 表达式，播放器绝不该学会读它。*

所以档位走 `-f MODE` 一模一样的形状：**调用方送规范档位，引擎查自己的表。**

```
  ut-play --quality high -f video -- URL
     └─→ bili-resolve --quality high -f video -j -- 句柄
            └─→ quality_sort_for_tier(mode, tier) → "res:1080"  ← yt-dlp 串只在这里
```

`-S` **保留**，作为专家逃生口，且**显式压过抽象**：两个都给时 `-S` 赢。
（`-S` 是 sort 不是 selector，所以它与既有的 mode→format 表**叠加**而非替换 ——
这也是选 format-sort 而不是显式 format id 的理由：档位缺失时它退化到最近的一档，
而一个显式 id 在没有那个 id 的视频上是硬失败。）

### P4 —— 键位 `f`，写回配置

`f` 循环质量档（`V` 不空，见 §2 第 7 条）。状态行多一个字段：

```
今天：  engine=yt · results=20 · sort=relevance · mode=audio (audio-only)
之后：  engine=yt · results=20 · sort=relevance · mode=video · quality=high
```

`auto` 档不印（`min=`/`max=` 在默认值 0 时不印，同一条规矩 —— `shell/uting:2372` 那段注释）。

### P5 —— 焦点卡**就是**条目视图；不新开渲染器

**这一条推翻了本计划初稿里的「一个 `i` 详情视图」。** 初稿打算再开一个整屏视图来放
上传日期、点赞、description、章节 —— 那正是 `AS-BUILT-tui.md` §11 已经写下并否掉的形状：

> **只有两个视图，而没有第三个正是重点。** 一个 "mini player" —— 用三行渲染与卡片相同的
> 四个事实 —— 会是**一个状态两个渲染器，也就是会漂移的重复**：光"进度条在哪儿构建"
> 就够两边分歧，而每一次卡片改动都得做两遍、或者明知故犯地跳过一遍。

一个「详情卡」与一个「Now Playing 卡」都是**关于一个条目的一屏事实**：标题按词换行、
频道行、元信息行、rail —— 四样全要重写一遍，还得靠人盯着让两边长得像。这就是那条决定说的漂移。

**所以：焦点卡的主语从「正在播的那一条」放宽成「你问的那一条」，视图数仍然是二 ——
且进入的键决定主语（第二轮审议修订，见下）：**

```
            subject = 你问的那一条
                  │
    Tab ──────────┤────────── i（列表/分P视图里，对选中行）
  在播曲目（语义不变）          任意行，附带一次 --info（拉取 + 按 id 缓存）
    │                           │
    │ 标题 · 频道 · 元信息        │ 标题 · 频道 · 元信息
    │ 已播/总长（%）· 进度条      │ uploaded · likes · 章节 · description
    │ 前方队列块（接下来几条）     │ audio · quality 档（将会放的那个）
    │ selected 格式（真放的那个）  │ "Enter 播放"
```

**为什么不是「Tab 主语放宽到选中行」（本条的上一版）：** 那一版里，未在播、未按 `i` 的条目视图
只有标题、频道、时长、播放量、id、mode、quality —— **每一个字段列表屏上都已经有**
（details 块五个，状态行两个）。一帧全屏的 chrome 复读是退化帧。把 `i` 本身当门（进门即取数），
退化帧就**不可达**：条目视图的每一帧都带着列表放不下的东西。附带的收益是 `Tab` 的语义
**完全不变** —— 上一版必须写进 `AS-BUILT-tui.md` 的那处既有键行为变更整个消失。

选中行正好是在播曲目时，`i` 走在播分支再叠 info（章节成为 seek 目标，P6）—— 仍是同一个渲染器。
`Tab` 在没有播放时保持今天的空态卡。

**为什么这个视图仍然存在（而不是塞回列表下方的 details 块）：**

1. **`i` 的载荷是变高的**（50 条章节、一段 description），而 details 块是**先于行计费的 chrome**
   （AS-BUILT-tui §11）：塞进去，80x24 的列表只剩 2–3 行 —— 这正是 §10 第 2 条否掉的方案。
2. **章节成不了行**（parts 的招数用不上）：一行是一次调用（`{engine, url}` = `ut-play` 的 argv），
   章节是**活播放器里的一个偏移** —— 变成行就得给 item 记录加起始偏移字段，契约蔓延进
   playlist / queue / history 三处。
3. **在播那一面**（进度条、前方队列块、`selected` 格式）本来就是卡片的本职，F02/F03 只是让它把屏挣满。

parts 确实全程不经过条目视图 —— 一个 part 是一次调用，所以那条轴整个是列表形状的，这是对的而非疏漏。

**代价与取数（约束「选中项变化不自动加载」仍然成立）：**

| 入口 | 网络 |
|---|---|
| `Tab`（在播曲目 / 空态） | 零 —— 今天的卡片，原样 |
| `i`（选中行） | 恰好一次 `--info`，既有 spinner，按 id 缓存；第二次进同一条，零 |

**缓存机制（bash 3.2，无关联数组）：单槽** —— `INFO_CACHE_KEY`（`engine:id`）+
`INFO_CACHE_JSON` 两个全局，命中即免取。单槽已覆盖真实节奏（回看刚看过的那条）；
多槽是平行数组的复杂度，买不到对应的行为。会话内有效，不落盘。

**本条经设计审议修订两轮**（§11）：第一轮（对照 critique）—— 在播分支的队列从一行扩成**前方队列块**；
标题清洗在两个摄入点统一是本条**前置**；`i`/`c` 的提示格按视图态 + 能力共同把门。
第二轮（用户质询「条目视图是否退化为 details 块的复读」）—— 成立，修法即上文的「i 即门」。

### P6 —— 章节是条目视图里的 seek 目标（P5 之后）

章节是**同一个文件里的偏移**，选一个就是 seek，而 `ut-play --seek-to` 已经在了。
放进 list 会逼着 item 记录长出一个「起始偏移」字段 —— 那是契约蔓延，
换来的只是把一个 seek 伪装成一个 row。它住在 P5 那个条目视图里：
subject 正在播时章节可跳，不在播时章节只是一份目录。
**排最后**，因为它是三条轴里唯一一条不阻塞其它两条的；它的选中交互（方向键？数字？）
留到 P5 落地后再定 —— 那时才知道卡片还剩多少行。

**键位审计（§12）给本条添了一个输入项：卡内 `↑/↓` 今天绑的是音量 ±5 —— 与 mpv 的
「↑/↓ = seek ±60s」反义，且与 9/0 纯冗余。本条落地时把卡内 ↑/↓ 让给章节/队列选择**，
音量回归 9/0 独占；在那之前不动（改已发行为要有自己的载体，这个载体就是 P6）。

### P7 —— Enter 的语义不变

在一条 100 P 的行上按 Enter，**照旧放第 1 P**。理由两条：

- 让 Enter 按站点事实改变行为，就是把站点知识塞进 TUI 的播放路径；
- 要知道它是不是分 P，得在**每次播放前**多一次网络往返。

整体入队是 parts 视图里的显式操作（`--parts -j` 原样管进 `ut-play -d --queue -`，
和 `ut-history --ls -j` 已有的性质一样）。

### P8 —— 时长不一致：**行修不了，只能在 parts 视图里说清**

**我在写这份计划的过程中推翻了自己先前的建议。** 先前跟用户口头推荐的是
「搜索报第 1 P 的时长 + 加一个 P 数字段」，§2 第 4 条的实测把它**两半都否了**：
搜索响应既没有 P 数，也没有第 1 P 的时长 —— 它只有聚合时长这一个数字。
要拿到任何一个，都得对每条结果多打一次 API。

于是诚实的形状是：

- **搜索行的 `duration` 保持聚合值**（那是 API 给的唯一数字，改成别的都是猜）；
- **不对**在于「按 Enter 只放第 1 P」这件事没人说过 —— 所以说清它的地方是 parts 视图的表头：

```
  parts='【全500集】…钢琴教程'  ·  items=100  ·  engine=bili
  合计 10h:32m:03s  ·  第 1 P 12:06
```

- §11 那一条要的「标出来」，在**搜索列表**这一层今天只剩一种可能：**按 duration 阈值的启发式标注**
  （那一条自己列的第一个选项）。**本计划不做它**，理由写进 §10 被否方案。

### P10 —— 退役 `p`/`P` 的 Tab 别名（键位审计 §12 的第一条）

`p` 在 **mpv、ncmpcpp、cmus 三家全是「暂停」**，而这里它是一个**不在任何提示里**的视图切换别名
（`shell/uting:4344`）：一个播放器用户按 `p` 想暂停，得到的是换屏。未公开 + 三家反义，
两条单独都够退役；顺带把一个字母还给本已砍半的键空间（大小写同绑，26 个可用位）。
TUI 键位不属于冻结面（ARCHITECTURE D17 只冻 CLI），零契约成本。落地是删一个 `||` 条件 + grep 门。

### P11 —— `j`/`k` = ↓/↑ 别名（键位审计 §12 的第二条）

现代 TUI 的桌面赌注（lazygit / k9s / yazi / gh-dash / spotify-player 全数支持）；`j`/`k` 现在空着，
cmus 的 j/k 本来就是导航，零反义。**只取 j/k，不取 hjkl 全套** —— `h` 已是 history（`b/h/c`
行源键族的内聚更值钱），`g/G` 配对被大小写同绑封死，半套 vim 比没有更糟，j/k 单独成立。
只在列表视图生效（卡内方向键另有职责，见 P6）。落地是 move_selection 的 case 各加一个模式。

### P12 —— keymap 分两档，`?` 随时切换（用户新增，2026-08-29）

**两条用户输入合成一条设计：keymap 有独立的呼出/收起键，且每个视图默认只显示核心键。**

- **两档，不是开关**：`core`（默认）↔ `full`，`?` 键切换。core 是**一行**——本视图自己的活：
  导航、对行动作、回程、`q`，加 `?` 自己（它是通往其余键的门，永远在印）。
  engine/store/调优/播控键（`v f o e l t a b h c d s > + [ ] 9 0 Space` 一族）住 full 档。
  各视图的精确成员表是落地细节，规则先定：**core = 这个视图的本职**。
- **全隐藏不设手动档**：core 只占一行，再省这一行的代价是全部可发现性；短终端下
  既有的 nav_ok 门照旧自动降级到横幅尾部 mini-hint —— 自动降级是 reflow 的活，不是用户的档位。
- **`？`（全角）与 `?` 同绑** —— 这是一个双语（你听）TUI，zh 输入法下的 shift-/ 出的是全角问号，
  utf8_complete 本来就会把它组装成一个键。
- **`?` 加入写回家族**：`UT_KEYS=core|full` 进 `config`，`?` 现场切换并写回用户文件 ——
  与 v/o/e/l/t/f 同一条 ARCHITECTURE D16 机制，没有新形状。PREF_KEYS 再 +1（P9 清点时一并改）。
- **业界对照**：`?` 是 lazygit / k9s / tig / less / ranger 的通用 help 键，此处空闲、零反义。
  被否的替代：一个独立的全键 overlay（第二个键文档面 ——「相邻两行 chrome 不得都记键」
  那条关切的放大版）；三态循环 core→full→hidden（第三态省一行、丢全部提示，不成交易）。
- **与既有机制的关系**：量高计费的 print_hints 机器原样 —— 只是量当前档；F05 的视图态门
  在两档内都生效（动不了的键哪档都不印）。

---

## 5. 契约变更（全部是新增；`AS-BUILT-contract.md` §3 在 land 时重同步）

### 5.1 `<engine>-resolve --parts -j`（新动词，只有具备的引擎才有）

```json
{"status":"ok","engine":"bili","id":"BV1vKEn6eE6Q",
 "url":"https://www.bilibili.com/video/BV1vKEn6eE6Q",
 "title":"【全500集】…","count":100,
 "total_duration":37923,"total_duration_fmt":"10h:32m:03s",
 "parts":[{"n":1,"engine":"bili",
           "url":"https://www.bilibili.com/video/BV1vKEn6eE6Q?p=1",
           "title":"基础乐理入门","duration":727,"duration_fmt":"00h:12m:07s"}, …]}
```

- **机制：`curl GET /x/web-interface/view?bvid=<id>`**，UA/Referer 与 bili-search 同款，零凭据。
  这给 `bili-resolve` 添了第二个传输原语，先例与理由都是现成的：`yt-resolve` 的 `probe_raw`
  已经在 resolve 半边用 curl，ARCHITECTURE D19 的分界本来就按「操作选传输」。新 seam 名 `fetch_view_once`，
  与 `fetch_page_once` 同族 —— **本套件第二处手搓 HTTP 请求，只许这两处**。curl 是本动词的门：
  缺失 → `require_cmd` 同款 `die`（用法层 1，同 bili-search 对 curl 的既有姿态）。
- **端点改过一次，理由记在这里（2026-08-29，本节初版写的是 `/x/player/pagelist`）。**
  §2 第 8 条的对决是 pagelist vs `yt-dlp --flat-playlist`，它证明的是**「机制不能是 yt-dlp」**，
  这一条不变。但 pagelist 的响应是 `{code,message,ttl,data[]}` —— **没有视频标题**，
  填不了本节自己写下的 `title`，也填不了散文首行 `♪ 标题`。同一句柄实测 `view`：
  **200 / code 0 / 0.43s / 一次请求 / 零凭据**，`.data.title` 是真标题，`.data.duration` = 37923
  = 100 个 `.data.pages[]` 的时长之和（实测吻合），而 `.data.pages[]` 与 pagelist 的 `data[]`
  **形状逐字段相同**。同样的一次请求、同样的延迟，多两个字段 —— 所以走 `view`。
  **已知风险**：站方在把 `view` 迁往 WBI 签名拼写（`/x/web-interface/wbi/view`），未签名的这条
  今天仍答（实测 2026-08-29），但它比 pagelist 更可能先被退役。真退役了，退路是 pagelist +
  `title: null`，信封形状不变（本节第三个被否选项，见下）。
- `title`（顶层）取 `.data.title`；`total_duration` 取 `.data.duration`；parts 每条的
  `title` 取 `.data.pages[].part`（真实分 P 标题），`n` 取 `page`，`duration` 是整数秒，
  `duration_fmt` 走引擎已有的 `fmt_dur`。**一次请求填满整张信封，不再另请求。**
- **散文形态（`-l`，默认）**：首行 `♪ 标题`，次行 `  - parts: N   total: <fmt>`，然后每 P 一行
  `  <n>. <part 标题>  <fmt>` —— 与 `--show`/`--info` 的散文语汇同族。`-J` 印 `view` 的原始记录。
- `parts[]` 每个元素**就是 item 记录**（带 `engine` + `url`），所以
  `--parts -j | jq '{items:.parts}' | ut-playlist --add …` 与 `… | ut-play -d --queue -` 都不需要改字段名。
- 单 P 的句柄：`count: 1`，`parts` 一个元素。**不是错误**。
- 门：一个位置参数必需；`-f`/`-S`/`--quality` 是用法错误（它不解流）。
- 错误信封同 `--info`：`{status:"error", engine, url, reason}`，退出 1 / 2+
  （`view` 的 `code != 0` 或 HTTP 非 200 → reason `network`，退出 2）。
- **uting 的 `c` 键提示门怎么免网探测能力**：照 `refresh_engine_auth` 的节奏在换引擎时探一次，
  探法是**无句柄调用** `<engine>-resolve --parts`：有此动词 → usage 错（缺句柄）；没有 →
  stderr 带套件稳定的 `unknown flag` 词形（AS-BUILT-contract §2 的门模型保证这个词形）。
  一次 fork、零网络，结果缓存在 `ENGINE_PARTS_OK`，与 `ENGINE_AUTH` 同刷新点。

### 5.2 resolve 信封加两个字段（`--parts` 之外的**唯一**契约动作）

```
  今天： {…, "mode":"audio", "format":"ba/b", …}
  之后： {…, "mode":"audio", "format":"ba/b",
             "selected":"234 - audio only (Default, high)",
             "selected_resolution":"audio only", …}
```

`format` 的含义**不变**（仍是请求的选择串，`AS-BUILT-engine.md` 已如此定义），
新增的 `selected` 是 yt-dlp 自己的回答，直接取 `.format` / `.resolution`。
**零额外网络** —— 这两个值已经在那份原始记录里，今天被扔掉。

`ut-play` 把 `selected` 一并记进 player record（它已经在记 `format`，`ut-play:1594` 那行加两个键），
焦点卡的 meta 行于是能从「`audio`」变成「`234 audio m4a`」。

### 5.3 `--quality TIER`（`ut-play` 与两个 resolve 半边）

规范档位：`auto | low | medium | high`（初版曾有 `max`，删了 —— 引擎的默认 format 表
本来就取最优，`max` 与 `auto` 无从区分）。**别名表归 `ut-play`**（照 §1.3 对 `-f` 的规定：
引擎接缝只运载规范拼写）。

**`quality_sort_for_tier(mode, tier)` 的出厂表**（两个引擎各持一份同值副本，ARCHITECTURE D21 允许的引擎间复制）：

| mode \ tier | low | medium | high |
|---|---|---|---|
| video / fast / ascii | `res:360` | `res:720` | `res:1080` |
| audio / viz | `+abr`（最小码率） | `abr:128`（封顶 ~128k） | 空（引擎默认已是最优） |

`auto` 与所有空格 = 不发 `-S`。**这张表住代码，不进 `config`** —— 与 format 串进 config
（`YT_AUDIO_FORMAT` 等）刻意不对称：档位抽象的全部意义就是用户不写 yt-dlp 串，
要自定串的用户用 `-S`（逃生口，两个都给时 `-S` 赢）。表值是 land 时可调的出厂细节，
形状（二维、空=不发）是决定。

---

## 6. 配置键（`config`，出厂默认；`AS-BUILT-contract.md` §5 在 land 时补表）

```
UT_PLAY_QUALITY=auto                        # --quality 的默认值
UT_QUALITY_CYCLE=auto medium high           # f 键循环的顺序
UT_KEYS=core                                # keymap 档位：core | full（? 键现场切换，P12）
```

**`PREF_KEYS` 从六个变成七个**（P4 落地：+`UT_PLAY_QUALITY`），P12 落地时再 +`UT_KEYS` 成八个。
「六个键」那句散文分布在 `CLAUDE.md`（两处）、`config` 抬头、ARCHITECTURE D16、
`AS-BUILT-contract.md` §5（七处）、`ARCHITECTURE.md`（三处）、`AS-BUILT-tui.md`、
`AS-BUILT-verification.md`（两处）、`README.md` —— **P4 已把它们全改成「七个」**；
P12 落地时同一批地方再改一遍成「八个」。（`AS-BUILT-tui.md` §591 的「六个键」是
**焦点卡片提示行**的键数，与写回无关，刻意不动。）

---

## 7. 键位

| 键 | 视图 | 动作 | 何时不出现在提示块 |
|---|---|---|---|
| `Tab` | 两个 | list ↔ 卡（主语 = 在播曲目/空态，**语义不变**） | 从不 |
| `c` | list | 把选中行的分 P 换成行源（`b`/`h` 的同族） | 引擎没有 `--parts` 时（同 `e` 在单引擎下的规矩） |
| `i` | list / parts / 卡 | 打开条目视图于选中行（卡内：对在播曲目），附带一次 `--info`（拉取 + 按 id 缓存） | 引擎没有 `--info` 时 |
| `f` | list | 循环质量档 | full 档 |
| `?` / `？` | 两个 | keymap core ↔ full（P12） | 从不 —— 它是门 |
| `j` / `k` | list | ↓ / ↑ 别名（P11） | 不印 —— 方向键的影子，不占格 |
| ~~`p`/`P`~~ | — | ~~Tab 别名~~ **退役**（P10） | — |

`Tab` **不改任何既有语义**（第二轮审议撤销了初版的主语放宽 —— P5）。新增的行为全部挂在新键上，
所以 `AS-BUILT-tui.md` 的重同步是**新增段落**（`i` 与条目视图），不是既有键的改写。

提示块的规矩是文件里已经执行了四处的那条：**一个动不了的键不许占一格**
（单引擎下的 `e`、无 `ut-playlist` 时的 `a`/`b`、播放列表外的 `d`、无播放器时的 `+`/`>`）。
`i` 的能力探测**照 `refresh_engine_auth` 的原样**（`shell/uting:401`）：调用动词，
非零退出就让字段消失 —— 不预先问，也不每次选中变化时问。

---

## 8. 落地顺序

P1/P2 与 P5 是**结构性**的（新动词、新 `LIST_SOURCE`、一个既有视图的主语变了），各自走 A→E。

**P1/P2（分 P）：**

```
A  bili-resolve --parts 先落地并在 tmux pty 里验；uting 未动，agent 面已经可用
B  uting 接上 c 键与 LIST_SOURCE="parts"；tests/drive.sh 驱动，跑无头回归
C  无可删的旧路径 —— 本计划不退休任何东西，C 步为空（照实记，不假装有）
D  文档：AS-BUILT-contract §1.3/§3、AS-BUILT-engine §10、AS-BUILT-tui §11
E  headed（tmux）+ headless 全扫
```

**P5（条目视图）—— 第二轮修订后 Tab 不动了，这一支随之变小：**

```
A  前置先落：标题清洗统一到两个摄入点（F04，已落）；卡片长出「subject 不在播」的渲染分支，
   暂无入口 —— 屏幕上看不出任何变化（tests/drive.sh -k Tab 验既有卡没崩）
B  i 键接入：列表/分P视图里对选中行开条目视图（取数 + spinner + 按 id 缓存），卡内对在播曲目叠 info；
   nav_tick 那条 `TUI_VIEW_MODE == "card"` 早返回改成「subject 在播才早返回」，
   否则从条目视图 Tab 回列表那一刻横幅的读数是陈的
C  无可删的旧路径 —— Tab、S_NOTHING、既有卡全部原样，C 步为空（照实记）
D  AS-BUILT-tui.md §11：新增 i 与条目视图一段；mini player 那段原样不动（它否的仍被否着）
E  headed + headless 全扫
```

P3/P4 是就地小改（多一个标志、多一张表、多一个键），不需要 A→E。
**P6 必须排在 P5 之后**，独立成一个 commit。

---

## 9. 已拍板（2026-08-29，用户）

1. **`quality_sort_for_tier` 按 (mode, tier) 二维。** audio 模式下 `res:1080` 毫无意义，
   该是 `abr` 排序 —— 只按 tier 的一维表会让 audio 档位变成一个不做事的键。
   代价是每个引擎多一张二维表；这是引擎自己的表，正是它该待的地方。
2. **返回栈保持一层：`c` 只作用于搜索行。** `stash_search`（`shell/uting:3513`）
   开头就是 `stored_rows && return 0` 且只有一个槽位，所以在播放列表的行上按 `c` 会
   走 `search_only()` 那条已经存在的拒绝路径（和 `o`/`e` 一样），**不是新写一条**。
   真需要两层栈时再加，那天它是一个独立的、可单独回滚的改动。
3. **不为质量档新增 `ROADMAP` D 条。** 它不推翻任何决定、也不产生需要活过重写的约束，
   land 时只进 `AS-BUILT-contract.md`。

**仍然开着的一个**（P5 落地后才答得了）：章节在条目视图里怎么选 —— 方向键、还是数字键？
那取决于合并之后卡片还剩多少行，量了再定。

---

## 10. 被否方案

- **另开一个 `i` 详情视图（本计划初稿的方案）。** 被 `AS-BUILT-tui.md` §11 已经写下的那条决定否掉 ——
  详见 P5。**这不是一条新决定，是初稿漂离了仓库自己的教条**：一个详情卡与一个 Now Playing 卡
  是同一件东西的两个渲染器，而那正是 mini player 当年被否的原因。
  合并之后视图数仍是二，`Tab` 的职责仍是"离开再回来"。
- **在 details 块里内联展开完整元数据。** 用户最初要的就是这个，量过之后否掉：details 块是
  **变高的 chrome，且在行被画出来之前就测量**（`AS-BUILT-tui.md` §636）。它每多一行就少一行结果。
  一段 description 加一串章节会把 80x24 的列表压到 2–3 行。改成一个显式触发的视图。
- **选中项变化时自动抓 `--info`。** 每一次方向键都排一个 yt-dlp 进程；按住 ↓ 走过 20 行就是 20 次抽取。
  文件里今天也没有任何异步取数路径。
- **显式 format id（`137` / `248` / `399`）。** 40 个选项、需要新的列举动词**和**一个 id 透传，
  且在没有那个 id 的视频上硬失败。format-sort 在同样的表达力下会优雅退化。
- **搜索列表里按 duration 阈值标「合集」。** §11 第 1 条把它列为可选项，本计划不做：
  实测（§2 第 4 条）表明阈值分不开「3 小时的单文件合集」与「500 P 的分 P」——
  `BV1xpQKBpEW7`（2h55m）是前者、`BV1vKEn6eE6Q`（10h32m）是后者，两者在搜索响应里**长得一模一样**。
  一个把两者混为一谈的标记，是在一个本来只是含糊的地方新造一处不准确。
  真信号在 resolve 半边，`c` 键就是去取它 —— 这与 §11 那一条「等一个带真信号的引擎」是同一个道理。
- **让 Enter 在分 P 上整体入队。** 见 P7。

---

## 11. 设计审议（2026-08-29，对照 2026-08-28 的 TUI critique 画布）

新 op flow 与视图设计整体过了一遍那份 critique（九条 finding、六条从仓库提炼的原则）。
逐条对上之后，**采纳三条修订、留两个候选、确认一处汇合**：

**汇合：** F03（焦点卡 27% 满 ——「要么挣得这块屏，要么别占」）与 P5 是同一个结论的两次独立到达；
critique 自己列的填充候选（前方队列、transcript、本曲目的收听史）就是条目视图的内容清单。

**采纳进计划的三条修订：**

1. **前方队列块（F02 + F03）。** 在播分支不止一行 `n/N · next`，而是列出接下来几条的标题与时长 ——
   TUI 里唯一能**读**队列的地方，补上「可写不可读」那半边。数据已在 `--status -j` 的 `queue` 键里。
2. **标题清洗统一（F04），P5 的前置。** `build_all_rows` 的 jq clean 与 `apply_player_record` 的
   raw title 在合并后的视图里成了**同一个主语的两种拼法**（方向键移到在播行上，标题会换写法）。
   一个清洗器，两个摄入点都过它。
3. **提示格规则从安装态扩到视图态（F05）。** `c` 只在 search 视图 + 引擎有 `--parts` 时出现；
   `i` 只在引擎有 `--info` 时出现；顺手把 store 视图里三个死格（`m`/`o`/`e`）修掉 —— P2 反正要动同一段。

**留给用户的两个候选（审议建议、本计划未承诺 —— 各要一次额外 fork/网络）：**

- 条目视图里加一行本曲目的收听史（`听过 3 次 · 上次 2 天前`，`ut-history --ls -j` 按 url 过滤）；
- `i` 的取数里带 transcript 摘要（`yt-resolve --transcript` 已有）。

**明确不归本计划的：** F01（history 视图丢四个字段 —— 独立缺陷，独立修）、F07（混合列表的行引擎 ——
条目视图顺带缓解：它的免费层印 engine，但行本身的修法另议）、F08 / F09（低危，另议）。

**第二轮（2026-08-29，用户质询）：「条目视图是否退化成了 details 块的复读？」——
对未在播、未按 `i` 的那一帧，成立。** 上一版让 `Tab` 的主语放宽到选中行，而那一帧的每个字段
（标题/频道/时长/播放量/id/mode/quality）列表屏上全有。修订：**`i` 即门** —— 进入非在播主语的
唯一入口是 `i` 本身（进门即取数），`Tab` 语义完全不变。退化帧从此不可达，`AS-BUILT-tui.md`
的既有键行为变更整个消失，P5 的 C 步清空。视图保留的三条理由（`i` 载荷变高、章节成不了行、
在播面是卡片本职）就地记在 P5。

---

## 12. 键位审计（2026-08-29，全表实证 + 业界对照）

对 `shell/uting` 的派发表逐键扫描（主循环 + 卡 + 过滤/输入模态），对照 mpv（本套件驱动的对端，
权重最高）、ncmpcpp/cmus、vim/less、以及现代 TUI 一族（lazygit/k9s/yazi/gh-dash）。
产出：P10 / P11 / P12 三个工作项、P6 的一个输入项、以下判定记录。

**逐字对齐（保持）**：`9/0` 音量、`Space` 暂停、卡内 `←/→` seek ±5（三者 = mpv 原键）；
`>` 跳下一首（mpv playlist-next）；`/` 过滤 + Enter 播放高亮（vim/less + fzf accept）；
`a`/`d`（ncmpcpp）；`o` 排序（ranger）；`i` info（ranger/nnn/mc）；`q` `s` `Enter` `Tab` 通行义。

**有张力、判定保持 —— 再被提案前先读这里（recorded-NO 性质）：**

| 键 | 张力 | 保持的理由 |
|---|---|---|
| `n` 新搜索 | vim/播放器语系 `n`=next | next 已在 `>`（mpv 对齐）；new 助记 + 提示条常驻 |
| `[ ]` seek ∓10 | mpv 的 `[ ]` 是变速 | 列表 ←/→ 归分页；本套件无变速概念，按错无害 |
| `f` 质量档 | mpv `f`=全屏；CLI `-f` 是 mode | 本仓从无「键=旗标首字母」约定（`o`↔`-s`、`v`↔`-f` 早已交叉）；detached 无全屏概念 |
| `+` 入队 | ncmpcpp `+`=音量 | 音量归 9/0（mpv 对齐更值钱）；append 助记强 |
| `h` 历史 | vim `h`=左 | 不采 hjkl 全套；`b/h/c` 行源键族内聚更值钱 |
| `c` 分 P | cmus `c`=暂停 | Space 已覆盖暂停；collection 助记成立 |
| 大小写同绑 | 键空间 26 位而非 52，`g/G` `n/N` 配对永不可用 | caps-lock 安全换的；不为任何单键开例外（v/V 拆分已自我否决） |
| ←/→ 边缘取数 | 导航键偶尔花一次网络 | 0.3.10 审过的决定；有 spinner；filter 开着不触发 |

**保留字**：`<` 显式留给将来的队列回退（mpv 的 `< >` 是一对，`>` 已用其一）——
前提是 `ut-play` 先长出对应动词，键永远跟着动词走，不倒过来。

**移交 P6 的一项**：卡内 `↑/↓` 今天是音量 ±5 —— 与 mpv「↑/↓ = seek ±60s」反义、与 9/0 冗余；
P6 落地时让给章节/队列选择（见 P6 内注）。

**顺带证伪的一条陈旧证据**：critique 画布 ListView 帧里的 `m more` 是 v0.3.9 的 ——
0.3.10 已把它换成 ←/→ 边缘取数（commit 4a046f5），今天派发表里没有 `m`。
当前空闲字母：`g m r u w x y z`（P10 落地后加回 `p`）。

---

## 13. 验证矩阵（每条都是「执行的 done_when」，不是散文）

**先加检查、后动代码的顺序不变；除新增行外全走「harden before you extend」——
能力不对称是既有 discovered-engines 循环没见过的形状，是本节唯一的新形状。**

**本节在 P1 落地时改过三处，理由记在这里（2026-08-29）：**

1. **`ut-play --queue -` 换成 `--enqueue -`。** `--queue` 不带 `-d` 是**在 argv 上**被拒的
   （「`--queue` 要起分离播放器」），那个门**根本不读 stdin** —— 换句话说，任何载荷都绿，
   连空的都绿：一条**不可能红**的检查，正是 CLAUDE.md 明令要拒的形状。`--enqueue` 先解析条目、
   再发现没有播放器可交（`not_playing` / 4），而畸形载荷在同一个面上是 1（两者都实测）。
   那个 4 与 1 的落差才是这条检查能红的地方。
2. **「信封形状」从 offline 挪到 live。** 断言对象是**冻结的 fixture** 时，无论引擎变成什么样
   它都满足过滤器 —— 同样是「不可能红」。真形状只有真调用能证，所以整块搬进 live 半边，
   并且**逐个 part 断言**（`?p=N` 是按元素拼的，差一或基址带上调用方查询串要到第二个元素才露）。
   offline 半边留下的是**管道**，那里的被测者是 `ut-playlist` 与 `ut-play`，fixture 是输入 —— 合法。
3. **补一条 live 检查：fixture 的键集必须仍等于真信封的键集。** 上面两条各自留了一个洞：
   冻结的 fixture 可能悄悄变成「一个旧引擎的描述」，而 live 形状检查不看 fixture。
   一条键集比对把两边焊上，任一侧加/改/删字段都红。
4. **补一条与 `--parts` 无关、但由它逼出来的守卫：真 `UT_STATE_DIR` 的指纹。**
   本节新加的那段 fixture 管道**写进了用户真实的 playlist 仓库** —— 它排在
   `unset UT_STATE_DIR`（听历史那节的收尾）之后，一句不带 `export` 的赋值只对本 shell 可见，
   子进程于是回落到 `~/.local/state/uting`，留下一个 80 行的 `parts` 列表（已删除）。
   `contract.sh` 早有一对真**配置文件**指纹（uting 会写它），却**从没有过状态目录的**：
   靠的是三处各自记得把 `UT_STATE_DIR` 指向一次性目录 —— 那种「靠记得」的纪律，
   加第四处的那天就断。现在整轮跑前后各取一次 `ls -R` 的 cksum，同样两侧对比、
   两个出口都断言。**这条不是 P1 的功能检查，是 P1 的事故留下的护栏。**

### contract.sh --offline（hermetic，每次 commit）

| 检查 | 断言 |
|---|---|
| `--parts` 无句柄 | 两引擎行为分叉且各自正确：`bili-resolve --parts` → 1 + usage 词形；`yt-resolve --parts` → 1 + `unknown flag` 词形。**这一对同时就是 `c` 键提示门探测的可行性证明**（§5.1 末条） |
| `--parts` 的旗标门 | `bili-resolve --parts -f audio -- BV…` → 1（它不解流） |
| `ut-play --quality` 门 | 非法档位 → 1；合法档位 + `--engine`/句柄缺失照旧走各自的门 |
| `--quality` 转发 | 照 `-S` 既有检查的形状加：焊死在 §2 第 5 条那三处的旁边 |
| config 校验 | `UT_KEYS=bogus` / `UT_PLAY_QUALITY=bogus` → uting die 1（validate_cycle 同族） |
| **fixture 管道**（零网络） | 一份**捕获的** `--parts` 信封（`av170001`，10 P，2026-08-29 真录）→ `jq '{items:.parts}' \| ut-playlist --add`（一次性 `UT_STATE_DIR`）→ `--show -j` 逐字段回读（engine/`?p=` 前缀/title/duration）；同一份 → `ut-play --enqueue -` → 4 + `not_playing` |
| `--parts` 不拉 yt-dlp | `PATH=/usr/bin:/bin` + 死代理 → **2**（够到传输后失败），不是 1（依赖门先死）。本条**新增**，不在初版 §13 里 |

### contract.sh（live 半，每次 push）

| 检查 | 断言 |
|---|---|
| `bili-resolve --parts -j -- BV1vKEn6eE6Q` | status ok、单行、`count >= 2` 且 `count == (parts\|length)`、`title`/`total_duration`/`total_duration_fmt` 非空、**每个** part 带 `n/engine/title/duration/duration_fmt` 且 `url == (顶层 url + "?p=" + n)`；耗时 < 5s（`view` 是一次请求，实测 0.5s，十倍余量 —— 会绊倒它的是多出来的一次往返，不是慢一点的下午） |
| fixture 未腐 | 上面这份真信封的键集（顶层 + `parts[0]`）**逐字等于** offline 半边那份冻结 fixture 的键集 |
| 单 P 不是错误 | `--parts -j -- BV1mL411E7Fb`（单 P 句柄）→ ok、`count == 1`、`parts[0].url == url + "?p=1"`。**这条也是新增**：把「没得选就报错」这个似是而非的实现挡在门外，而它能过其余每一条 `--parts` 检查 |
| `yt-resolve -j` 的 `selected` | 非空字符串，且 ≠ `.format`（答案 ≠ 请求） |
| `bili-resolve -j` 的 `selected` | 同上 —— 不变式对**全部 discovered 引擎**陈述，capability 检查（--parts）才允许分叉 |

### playback.sh（播放器动过才跑）

| 检查 | 断言 |
|---|---|
| player record 的 `selected` | 真播一条后 `--status -j` 里 `.selected` 非 null（backfill 路径，同 title/format 既有检查旁） |
| `--quality` 贯穿真播 | `ut-play -d --quality low -f audio` 起真播放器、正常 stop —— 证明 `-S` 叠加不碎流 |

### contract.sh 的 tmux 面（P2 落地时加的一条，2026-08-29）

`c` 的**能力门**在活的 TUI 上有一条断言，而且它**不看提示块**（画面不进套件）：那个面跑的是
yt（`config` 的出厂默认，且它的 `UT_CONFIG` fixture 里没有这个键），所以 `c` 必须**什么都不做**。
证人是**它后面那个键**：一个没有门的 `c` 会去调 `yt-resolve --parts`，收到 offline 半边已经钉住的
`unknown flag` 拒绝，然后把面停在 press-any-key 上 —— 而停住的面会**吃掉下一个按键**。
于是 `c` 之后紧跟既有的 `h`：`h` 打不开日志，就是 `c` 越了界。一次测量，两条断言
（`…so the c before it was inert` 与 `h opens the log as the rows` 共用一个变量 ——
套件里已有的那种形状）。

**正向那半为什么不进套件**：`c` 真开出 parts 视图，要一条**搜索结果第一行恰好是多 P** 的
bili 查询 —— 那是拿站方排序做回归，正是本节末尾自己列的反例（「不给 100 这个数做回归」）。
正向路径由下面的 drive 驱动，**套件里没有它，这话是照实说的**。

### tests/drive.sh（TUI 改动的驱动，断言存活）

**P2 落地时实跑的五次（2026-08-29，均 100x30）：**

| 驱动 | 看到的 |
|---|---|
| `UT_DEFAULT_ENGINE=bili -q '钢琴教程' -k c -w 'parts='` | 表头 `parts='【全500集】…'`、`engine=bili  items=100  total=10h:32m:03s`；行是真分 P 标题与各自时长（第 1 行 12:07），details 块是 `?p=1`，提示块 `c 返回搜索列表` |
| `… -k 'c c'` | 回到 `query='钢琴教程'`、`results=17`、`auth=chrome`，提示块回到 `c 分P` |
| `UT_DEFAULT_ENGINE=bili -q '周杰伦 稻香' -k c` | `分P: 这个视频只有一 P` + 按任意键 —— 单 P 不开视图 |
| `UT_DEFAULT_ENGINE=yt -q 'lofi hip hop' -k c` | 提示块里没有 `c`，按下去什么都不发生 |
| `UT_DEFAULT_ENGINE=yt -q '周杰伦' -k 'e x'` | 换到 bili 后 `c 分P` 出现 —— `refresh_engine_caps` 在换引擎点也刷了（`x` 是拿来消掉 `mark_pref` 那条环境固定提示的） |

- `-k c`（bili 行）→ 等 `parts=` 出现在帧里 → `-k c` 回 → reap；
- `-k i` → 等 spinner 消失 → `-k i` 回；`-k '?'` 两次（core↔full 往返活着）；
- `-k j -k k`（选中移动不崩）；P10 后：`-k p` **不再**切视图（发 p、断言帧仍是列表）。
- 布局照旧不进套件 —— 新帧进文档时走 `capture-pane`。

### 反例（不做的检查，免得再被提案）

- **不 mock `view`**：curl 打不到就不测 —— 「真依赖造不出的覆盖就是没有的覆盖」（CLAUDE.md 测试规矩）。
- **不断言 parts 视图的画面形状**（列对齐、表头字序）—— 套件断存活，capture-pane 管画面。
- **不给 100 这个数做回归**（站方数据会变），断言的是 `>= 2` 与形状。
- **F04（标题清洗统一）不进套件，实测记在这里。** 它的可观测面要求**同一个进程里同时有真播放器和 TUI** ——
  `contract.sh` 的 tmux 面在 offline 半边（无播放器），`playback.sh` 驱动 `ut-play` 而不渲染卡片：
  两个套件谁都到不了那一帧。造得出那一帧的唯一办法是给 TUI 喂一个假 pid 的状态文件，而那是
  CLAUDE.md 明令拒的 stand-in。所以照实说：**这条覆盖套件没有**，用 driver 实测并把结果记下 ——
  `tests/drive.sh -k 'Enter Tab' -w Playing`（2026-08-29，`lofi hip hop` 首条标题带 📚）：
  卡片读作 `lofi hip hop radio beats to relax/study to 2026-08-29 22:04` —— 📚 已去，
  而末尾的日期证明这一行来自**播放器记录**（行标题没有日期），即走的正是 `apply_player_record` 那条路。
  改前同一帧会带着 📚。
