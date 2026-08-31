# PLAN —— 视图塌缩：取消焦点卡，`i` 成为第五个 row source

**状态：** 已定稿，未 pre-mortem，未动工。
**开工第一件事是 pre-mortem（`discuss-with-me`），不是写代码。**

---

## 0. 它从哪来

不是 ROADMAP 的 `D#` —— ROADMAP 只记还开着的事，这条是**已裁决**的实现工作。
它的两个来源：

1. 2026-08-28 那版 TUI critique 的 **F03**：焦点卡在 100×30 上只填满 27%（30 行里 8 行），
   而它换来的是第二个渲染器。当时的结论是"要么把整屏挣回来，要么别占它"。
2. 本人 2026-08-30 的裁决：**别占它**。

设计画布（三个未采用的探索方向 + 条/块拆解 + 本方案）：
`https://claude.ai/code/artifact/c20bd7ac-2601-4155-ab6b-56805b5ee439`

---

## 1. 一句话

**两个渲染器塌成一个。** `TUI_VIEW_MODE` 和 `CARD_SUBJECT` 两个状态变量整个消失，
`LIST_SOURCE` 从四个值变五个 —— `i` 变成第五个 row source，进出同一个键，
和 `b` / `h` / `c` 完全一样的机制。

---

## 2. 已定的决定

每条都定了，别在实现时重新讨论。

- **D-a 取消焦点卡。** 全 app 只剩一个渲染器（列表）。
- **D-b `i` 打开 version 模式**，就地替换列表的行；再按 `i` 回 search 列表。
  用 `open_parts()` 的骨架，不是新机制。
- **D-c 不动 list layout。** 表头、状态行、提示块、两条满宽轨、分页点、详情块，
  一律不改。version 模式套用今天的 chrome，就像 `b`/`h`/`c` 那样。
  —— 本方案**不含任何样式工作**。画布上那三个极简方向（A/B/C）**未采用**，留作依据。
- **D-d `i` 的主语 = 光标所在的行**，不分它在放、暂停还是没开始。一条规则，不分支。
  正在放的那行本来就在列表里，方向键就能到。
- **D-e chapter 行按 Enter 的语义：「从这儿开始放」。**
  这一版正在放 → 对活着的播放器 `seek`（今天 `seek_chapter` 的行为，一字不差）；
  没在放 → `ut-play --start SEC` 起一个新的。两个分支对用户是同一件事。
- **D-f `Tab` 空出来，本方案不给它派新活。** 空着比硬塞一个功能好。
  `ESC` 从卡片那份职责退休；在列表里它仍然是"清除过滤"，不变。
- **D-g 纯显示的损失，接受并直说。** layout 不动的前提下，
  **进度条**、**queue-ahead 块**、大标题没有去处。
  列表的 `▶ Playing:` 那行保留标题、`00:04 / 01:01:13` 和资源读数。
  丢的是"进度画出来的那条线"和"接下来放什么"，**不是任何一个能按的键**。
  补不补是**以后另开的一个单元**，不在本方案内。

---

## 3. 还没定的（开工前需要一个答复）

- **O-1 `f` 键（循环 quality）要不要删。**
  它和 version 列表里的 quality 行重了。
  *建议：删* —— 一件事一个地方，且 quality 不是每首都要调的东西。
  留着也行，那它就是个快捷方式。**这条不定，version 模式仍可开工**，只是收尾时要回来。
- **O-2 version 模式收哪几条轴。** 建议三条全收（见 §5），
  但只做 chapter 一条也是成立的最小版本 —— parts 今天已经有 `c` 键了，会重。
  *建议：chapter + quality 两条，parts 保持在 `c`*（否则 `i` 和 `c` 内容重叠）。

---

## 4. 代码盘点

行号是 2026-08-30 `shell/uting`（5594 行、v0.4.1）的现状，实现时以 grep 为准。

### 4.1 删

| 符号 | 位置 | 说明 |
|---|---|---|
| `display_now_playing_card()` | 3676 | 卡片主渲染器 |
| `card_subject_head()` `card_meta_row()` `card_info_row()` `card_queue_block()` `card_chapter_block()` `card_item_body()` | 3336 / 3359 / 3417 / 3457 / 3518 / 3590 | 卡片的六个分块渲染器 |
| `TUI_VIEW_MODE` | 1254，共 9 处 | 两态变量 |
| `CARD_SUBJECT` `CARD_PLAY_INFO` | 1325 / 1296 | 主语与"卡片正显示在播信息"标志 |
| `CARD_TEXT_W` `CARD_HEAD_LINES` `CARD_INFO_ROW` `CARD_QUEUE_LINES` `CARD_CHAP_MAX` `CARD_CHAP_LINES` `CARD_CHAP_ACTIVE` `CARD_SELECTED_MAX` `CARD_DESC_MAX` | 3334–3589 | 卡片布局量 |
| `move_chapter()` `CHAP_SEL` | 2366 / 1348 | 章节游标 —— 被普通行导航取代 |
| 卡片键处理段 | 5526–5562 | 整段 |
| `Tab` 分支 | 5494–5508 | 整段 |

`CARD_` 71 处 · `card_` 36 处 · `CHAP_` 54 处 —— **删之前逐个 grep 过 gate**（安全演进法 C 步）。

### 4.2 留（陷阱：名字带 card/ITEM 但不是卡片的）

| 符号 | 谁在用 | 为什么不能删 |
|---|---|---|
| **`card_divider()`** | `print_details()` 2166 · **列表自己的轨 3069** | **名字骗人。列表在用。留。**本方案不改名（改名是另一个单元） |
| `apply_player_record()` | 列表的 `▶ Playing:` 横幅 | 横幅留着 |
| `fetch_item_info()` | 即将成为 version 行的数据源 | 见 §4.3 |
| `ITEM_CHAP_SEC[]` `ITEM_CHAP_TIME[]` `ITEM_CHAP_TITLE[]` `ITEM_CHAP_TW` | 即将成为 chapter 行 | `--info` 的载荷，**不是**卡片的 |
| `ITEM_TITLE` `ITEM_CHANNEL` `ITEM_DUR_FMT` `ITEM_VIEWS` `ITEM_UPLOADED` `ITEM_LIKES` `ITEM_DESC` `ITEM_CHAP_N` | version 模式的表头/详情块 | 同上 |
| `seek_chapter()` 2382 | D-e 的"在放就 seek"那一半 | 留 |

### 4.3 改 / 新增

- `open_item()` 4681 —— **只改最后两行**。今天是
  `CARD_SUBJECT="item"; TUI_VIEW_MODE="card"`；改成
  `build_version_rows` + `stash_search` + `LIST_SOURCE="versions"` + `load_rows`。
  前面的 fetch（`fetch_item_info "$row_engine" "$url"`）一字不动。
- `open_playing_info()` 4706 —— 并入 `open_item()`。D-d 之后不再有"卡片上的 i"这回事。
- **新** `build_version_rows()` —— 把 `ITEM_CHAP_*`（+ O-2 定的其它轴）转成
  **七字段 item 记录**（`url · title · duration_fmt · views · channel · live · engine`），
  和 `build_playlist_rows()` 出同样的形状。chapter 行多带一个偏移，见 §5。
- `open_versions()` 的开关半边 —— 抄 `open_parts()` 4599 的骨架
  （`LIST_SOURCE` 相等则 `back_to_search`；`ENGINE_INFO_OK` 门；`stash_search`）。
- 提示块 —— `i versions` / 模式内就地改词 `i back to results`（`b` 已有的做法）；
  **`Tab 视图` 从提示块消失**，这不是布局改动，是"不能动作的键不许占一格"这条既有规矩自然生效。

---

## 5. version 行的形状（等 O-2 定）

一句话：**同一个东西的另一种放法**。每一行都是一次 call，所以什么新字段都不用加。

| 轴 | 是什么 | 行记录 | 已存在的东西 |
|---|---|---|---|
| chapter | 同一个文件里的一个偏移 | `{engine, url, title, start_seconds}` | `--info` 的 `chapters[]` + `ut-play --start SEC` |
| quality | 同样内容的另一种编码 | `{engine, url, title, quality}` | `ut-play --quality`，引擎侧 (mode,tier) 表 |
| ~~part 分P~~ | 同一个 id 下的另一个文件 | —— | 已经是 `c` 键，建议不重复收 |

**关键事实（值得单独记一笔）：**
2026-08-29 那版方案**否决过**"章节当行"，理由是它会把一个 start-offset 字段推进 item record，
再从那里推进 playlist、queue 和 history。**那条理由在 0.4.0 之后已经失效** ——
`start_seconds` 已经是 resolve 信封里的字段（`yt-resolve` · `bili-resolve` · `ut-play` 三个脚本都有），
`ut-play --start SEC` 也已落地（commit `ae8f261` / `f79b484`）。
所以一个 chapter 行**已经是一个合法的 call，不需要任何新字段**。
Enter 播、`+` 入队、`a` 存歌单，全部是继承来的。

---

## 6. agent 面 —— 为什么不需要新 verb

ROADMAP 的规矩：每个功能都要有 agent 面（一个 verb + 一个 `-j` 信封）陪着它的键位，
否则只是半个功能（ARCHITECTURE §3.5）。

**本方案的 agent 面已经全部存在**，因为 version 模式只是把已有的 `-j` 输出组合成行：

```
<engine>-resolve --info -j   → .chapters[]   （章节，含 start_time）
ut-play --start SEC          → 从偏移起播
ut-play --quality TIER       → 换编码
<engine>-resolve --parts -j  → 分P（已由 c 键覆盖）
```

一个 agent 要做 TUI 里 `i` 能做的事，今天就能做，不用等本方案落地。
**所以本方案不新增任何 CLI 表面，契约冻结面一个字不动。**

---

## 7. 阶段（安全演进法 A→E —— 这是结构性改动：它退休一条路径）

| 步 | 做什么 | 出口 |
|---|---|---|
| **0** | **pre-mortem**（`discuss-with-me`，冷读者只拿这份 plan） | 每条预防性修正被接受或明确拒绝，写回本文件 |
| **A** | 先建新路：`build_version_rows()` + `open_versions()` 开关，**卡片仍在**。tmux 里验 | `i` 能开能关，交互路径一刻也没缺过 |
| **B** | 把 `i` 改绑到新路，`Tab` 解绑。跑无头回归 | `tests/contract.sh --offline` 绿 |
| **C** | **删卡片**（§4.1）—— 破坏性的一步，最后且最小。每个删掉的符号先 grep gate | 无悬空引用；再回归一次 |
| **D** | 文档：`AS-BUILT-tui.md` §11（两个视图 → 一个）、`ARCHITECTURE.md` 的控制流图与函数表、`README.md` 键位表、`usage()` | 一处事实一处写 |
| **E** | tmux headed + 无头全扫 | 见 §8 |

§4.2 那张"留"的表是 **C 步的护栏** —— `card_divider` 那条尤其。

---

## 8. done_when（逐条执行，不是逐条读）

- [ ] `/bin/bash -n shell/*` 全绿（pre-commit 钩子也拦，这是 `--no-verify` 的后备）
- [ ] `tests/contract.sh --offline` 绿（每次提交；~16s）
- [ ] `tests/contract.sh` 全跑绿（推之前；~118s）
- [ ] `tests/playback.sh` 绿 —— **本方案不碰播放器，但 D-e 的 seek 路径碰了活播放器**，所以要跑
- [ ] `tests/drive.sh -k 'i' -w <version 模式的标记>` —— 真的进得去
- [ ] `tests/drive.sh -k 'i i'` —— 真的回得来，且回到 search
- [ ] `tests/drive.sh -k 'Tab'` —— Tab 现在什么都不做，且**没把 TUI 弄死**
- [ ] `tests/drive.sh -x 62 -y 20` 与 `-x 62 -y 12` —— 窄屏没崩（layout 没改，但行来源换了）
- [ ] `grep -n 'TUI_VIEW_MODE\|CARD_SUBJECT\|CARD_PLAY_INFO\|display_now_playing_card' shell/uting` 无输出
- [ ] `grep -n 'card_divider' shell/uting` **仍有输出**（护栏：它是列表的，不是卡片的）
- [ ] shellcheck 基线计数**重新量过**并写回 `RESEARCH-tui-player.md` §5.1（删代码会改这个数）
- [ ] as-built 文档 resync 完（§7 D 步）
- [ ] O-1（`f` 键）有了答复并落实
- [ ] 本文件删除 —— plan 落地即删，不归档

## 9. 验证矩阵里诚实的那一格

`i` 开出来的行**需要一次真实 `--info` 抓取**，所以"行内容对不对"这条
**离线证不了**，只能在 `contract.sh` 的联网那半边证。
离线能证的是**门**：引擎没有 `--info` 时 `i` 什么都不做（`ENGINE_INFO_OK` 为假），
以及提示块里那一格不印 —— 这两条按"不能动作的键不许占一格"的既有检查加固，
不新开文件。

**不许**为了让它离线可测而加任何 mock / stub / 替身 —— 抓不到就是抓不到，直说。
