# PLAN-search-row —— 搜索行的形状定死 + `ut-search`

> **状态**：草拟，**未开工**。无外部前置 —— 所需的站点字段已实测存在（§2）。
> **实现的 ROADMAP 条目**：**D21**（`ut-search`）· **§11 第一条**（一条结果 ≠ 一个可播对象）。
> **是 `PLAN-engine-xmly.md` 的前置**：第三对引擎照着本文定死的行写，一次写对。
> **落地即删**：契约拆进 `AS-BUILT-contract.md` §3，站点事实进 `AS-BUILT-engine.md`。

---

## 1. 一句话

搜索结果的**行**获得两组它今天缺的字段 —— "这一行是不是一个可播对象"（粒度）与
"播出来是不是完整的"（付费/试听）—— 同时 **`ut-search`** 作为统一入口落地：
默认单引擎（`UT_DEFAULT_ENGINE`），`--engine` 选子集或全部，只有显式要求才 fan-out。
两件事改的是同一张行，所以是一个 plan：分两次做要在三个引擎 + 契约 + 断言上过两遍。

---

## 2. 已验证的站点事实（实测日期见各行；开工前重跑）

| 站 | 字段 | 在哪 | 实测 |
|---|---|---|---|
| B 站 | `episode_count_text` / `is_union_video` / `is_pay` | `search/type` 响应，`bili-search` 已经拿到的那份 JSON 里 | 2026-08-28：搜"周杰伦"第一条 `duration:"222:28"`，字段俱在。**零额外请求** |
| B 站 | 分 P（一个 BV 几十 part） | 同上（`episode_count_text`） | 同上 |
| 网易云 | `fee`（1=VIP 只给试听，8=可播低码率） | `cloudsearch/pc` 响应 | 2026-08-28：`fee:1` 曲目直链 720KB vs 应有 3.81MB（≈45 秒试听）。**零额外请求** |
| 喜马拉雅 | `is_paid` | `tracks/<id>.json` | 2026-08-28：resolve 时可得；搜索侧字段待 Gate 0（`PLAN-engine-xmly.md` §3）后确认 |
| YouTube | 无同类形态 | — | 搜索结果就是单视频；`--flat-playlist` 下行即对象。**两个新字段恒为默认值**，这是合法状态 |

---

## 3. 行的新字段 —— 两个，不是一个

粒度和完整性是**正交**的两件事（一个 3.7 小时合集是免费的；一首 45 秒试听是单曲），
硬塞一个键就是把两个问题重新搅在一起。

```json
{ "id":"…", "title":"…", "url":"…", "channel":"…",
  "duration":213, "duration_fmt":"…", "view_count":12345, "live_status":"not_live",
  "kind":"track",        ← 新：这一行是什么。 track | collection | multipart
  "access":"full" }      ← 新：匿名播放能拿到什么。 full | preview | paywalled
```

- **`kind`** —— 粒度。`track` = 一行一个可播对象（今天的隐含假设，写成显式值）；
  `collection` = 合集/连播（B 站 50 首合集）；`multipart` = 一个 handle 多个 part（B 站分 P）。
  **封闭枚举**，与 `reason` 枚举同规矩：引擎实现它，谁都不许扩展。
- **`access`** —— 完整性。`full` = 匿名拿全曲；`preview` = 播得出但被截（网易云 fee:1 的 45 秒）；
  `paywalled` = 匿名解不出流。**报的是站点事实，不是登录裁决**（D16 的界线原样适用：
  它说"匿名会拿到什么"，不说"你登录后会拿到什么"）。
- **两个都必填**，与 `engine`/`status` 同级：一个漏掉它们的引擎与截断的读无从分辨
  （契约 §3 的既有措辞直接覆盖）。不知道就如实填默认（`track`/`full`）——
  **YouTube 恒为默认值是合法的**：站点没有这两种形态，不是引擎没实现。
- **判据落在引擎**（correctness 加在下面）：`bili-search` 从 `episode_count_text`/`is_pay` 算，
  TUI 只渲染，agent 只读字段。TUI 的呈现（焦点卡标记/单列/阈值染色）是**后续独立小改**，
  不在本 plan 的验收里 —— 字段先于呈现。
- **`-M` 那段 usage 话术保留**：`kind` 是标注，`-M` 仍是排除的钝器，两者不互替。

**被否**：
- 一个键装两件事（`flags:["collection","paid"]`）—— 数组字段让"必填 + 封闭枚举"两条都难敲死；
- `duration` 阈值让 TUI 自己猜 —— 猜错一次就是 3.7 小时连播，且 agent 面拿不到；
- 只做 TUI 标记 —— 半个功能（D14 的硬约束原文）。

---

## 4. `ut-search` —— 统一入口，fan-out 只向要它的人收费

### 4.1 形状（ROADMAP D21）

```sh
ut-search -- "周杰伦"                    # = UT_DEFAULT_ENGINE 那一个引擎（config 已有的键）
ut-search --engine bili -- "周杰伦"      # 选一个
ut-search --engine yt,bili -- "周杰伦"   # 显式 fan-out：逗号列表
ut-search --engine all -- "周杰伦"       # 发现到的全部（按 *-search + *-resolve 成对 glob，
                                         #   与 uting 的 scan_engines 同一条发现规则）
```

先例：Mopidy `library.search(uris=None)` 默认全 backend、`uris` 收窄 —— 同拓扑 15 年实践；
默认收窄成单引擎是本仓自己的账（部分失败要写进冻结信封，agent 读不到 log），
形状同 `git fetch`（默认 origin，`--all` 显式）。

### 4.2 转发什么

`-n -m -M -s -j -J -l --color` 原样透传给每个引擎 —— **`ut-search` 自己不长搜索语义**，
它对 flag 的全部工作是解析 `--engine`、验证其余 flag 是引擎们共有的、然后照发。
一个引擎独有的 flag 出现时退 1，报哪个引擎不认识它。

### 4.3 信封 —— 单引擎时逐字等于今天

- **单引擎**（默认路径）：**逐字**转发该引擎的信封，`ut-search` 不改写一个字节。
  于是默认路径零新语义，且引擎信封的既有断言自动覆盖它。
- **多引擎**：信封级 `engine` 不可能有单一值，所以：

```json
{ "status":"ok", "query":"周杰伦", "count":40,
  "engines":{"yt":{"status":"ok","count":20},
             "bili":{"status":"ok","count":20}},
  "results":[ {…, "engine":"yt"}, {…, "engine":"bili"}, … ] }
```

  - **行级 `engine`** —— 恰好是 `ut-playlist --add` 已接受、`ut-history --ls -j` 已在印的
    形状（items 数组），所以 `ut-search -j | ut-playlist --add` / `| ut-play -d --queue -`
    **下游零改**。
  - **`engines{}` 替代信封级 `engine`**：每个引擎报自己的 `status`/`count`（失败的引擎多一个
    `reason`）。部分失败 ⇒ 信封 `status:"ok"` + 那一格 `status:"error"`；**全失败** ⇒ 信封
    `status:"error"`，退 2+。**一个引擎都选不出**（`--engine` 点名了不存在的）⇒ 退 1。
  - **排序**：轮转交错，各引擎保持自己的次序。跨站相关性分数是编出来的，不编。
  - **`-n` 是每引擎的**：`-n 20 --engine yt,bili` 最多 40 行。总量截断要跨站比较，回到上一条。

### 4.4 实现事实（bash 3.2 的账，如实记）

- fan-out 并行 = 后台作业 + 每引擎一个临时文件，`wait` 后 jq 合并。
  **`ut-search` 的 stdout 是被捕获的**，所以那条硬规矩直接适用
  （`AS-BUILT-verification.md` §25：裸 `&` 的子进程必须重定向自己的 fd —— 一次命令替换
  等的是管道的每一个写者）。这是这个命令最容易写错的一处，pre-mortem 重点。
- 延迟 = 最慢引擎（实测 bili 0.71s / yt 2–3s）。fan-out 是显式要求的，这笔账调用方自己签的。
- 发现规则与 `uting` 的 `scan_engines` 相同（成对才算），但**独立实现**（两个入口点不共享库
  —— 与 8 份 `die` 同一笔既有的账，不在本 plan 里翻）。

### 4.5 名字与 D10

`ut-` 前缀 = 与站点无关的套件级命令（`ut-play`/`ut-playlist`/`ut-history` 同族）。
它**不是**任何 `X-search` 的第二拼法，因为它有一件任何现有命令做不到的事（fan-out + 合并信封）；
单引擎转发是那个能力的退化情形，不是命令存在的理由。`<engine>-search` 保持在 PATH 上原样可用
（`yt-resolve` 也在 PATH 上 —— 直接调低层不是第二拼法）。**agent 面收敛为 `ut-search` + `ut-play`
两个名字**，加第三个源不再加 agent 要认识的名字 —— 对称补齐：播放半边早就是
`ut-play → <engine>-resolve` 这个形状（D9）。

---

## 5. 会被改到的文件

| 文件 | 改什么 |
|---|---|
| `shell/ut-search` | **新文件** |
| `shell/yt-search` / `shell/bili-search` | 各加 `kind`/`access` 两字段（yt 恒默认值；bili 从已到手的响应字段算） |
| `shell/uting` | 搜索取数从"单引擎 + `e` 轮换"升级为**引擎多选**：`e` 打开一张勾选单（all / yt / bili / …，条目来自 `scan_engines` 的既有注册表，不新增表），勾多个 = 取数走 fan-out，标题栏印当前选集。行级 `engine` 已在信封里，Enter 播放取**该行**的 engine（今天已如此，`ut-play --engine 行的值`）。`kind`/`access` 先不渲染 —— 呈现另开小改 |
| `shell/ut-play` / resolve 们 / 两个 store | **零行** —— 行形状变宽不变形，store 摄入的键本来就是挑着取的 |
| `config` | 无新键（`UT_DEFAULT_ENGINE` 已存在） |
| `docs/AS-BUILT-contract.md` | §3 行加两字段 + `ut-search` 的两张信封；§1 加 1.x 命令节；§6 清单补"新引擎必须算 `kind`/`access`" |
| `docs/AS-BUILT-engine.md` | B 站的判据（`episode_count_text`→`multipart`/`collection`、`is_pay`→`access`） |
| `docs/ROADMAP.md` | §11 第一条随本 plan 落地删除；D21 状态 |
| `README.md` | 顶部示例块加一行 `ut-search`；`## What it is` 加一段 |
| `VERSION` | 行加字段 = 加法（既有键一个没动）→ **z 位**；单独 commit（D13） |
| `tests/contract.sh` | 跨引擎不变量加两条：每个发现到的引擎行里 `kind`/`access` 必在且值在枚举内；`ut-search` 单引擎信封与直调该引擎 **byte-diff 相等** |

**契约变更声明（D3 要求的"深思熟虑的、成文的动作"——就是本文件）**：
行加两个必填键是**加法**（没动任何既有键），但"必填"意味着旧读者若做严格 schema 校验会看到新键
—— 本仓信封的既有先例（`retried` 后加入）同样处理为 z 位加法。

---

## 6. 验证（`done_when` —— 执行，不是读）

| # | 检查 | 归属 |
|---|---|---|
| 1 | `bash -n shell/ut-search` + 既有全绿 | pre-commit / `--offline` |
| 2 | **每个发现到的引擎**：行含 `kind`+`access`，值在封闭枚举内 | `contract.sh --offline` 起（用夹具信封）+ live 半 |
| 3 | `ut-search -j -- q` 与 `$(UT_DEFAULT_ENGINE)-search -j -- q` **byte-diff 相等** | `contract.sh` live 半 |
| 4 | `--engine yt,bili`：合并信封形状、行级 engine、轮转交错、`count` = Σ | live 半 |
| 5 | 部分失败：一个引擎强制失败（`YT_COOKIE_BROWSER` 判别式那类**输入**，不许改源码）⇒ 信封 ok、那格 error、退 0 | live 半 |
| 6 | 全失败 ⇒ `status:"error"` 退 2+；`--engine nope` ⇒ 退 1 | `--offline` |
| 7 | B 站判别性输入：一条已知合集（如实测那条 50 首）`kind:"collection"`；一条普通单曲 `kind:"track"` | live 半 |
| 8 | `ut-search --engine yt,bili -j | ut-playlist --add t` 零改动直通 | `--offline`（夹具）|
| 9 | 裸 `&` 账：`ut-search -j` 在命令替换里不悬挂（fan-out 子进程 fd 已重定向） | `--offline` |
| 10 | TUI：勾选单开合、勾两个引擎后取数、Enter 播放路由到行的 engine、TUI 退出无遗留播放器 | `drive.sh` 驱动 + `contract.sh` 的 tmux 段 |

第 5 条沿用套件的判别性输入方法（`prove-checks-by-input`），不破坏源码。

---

## 7. 建造顺序（加面 = 结构性，走 A→E）

- **A** 行字段先行：`bili-search` 算 `kind`/`access`，`yt-search` 印默认值；契约断言跟上。
  —— 这半落地后 **`PLAN-engine-xmly.md` 即可解锁**，不必等 `ut-search`。
- **B** `shell/ut-search`：先单引擎转发（byte-diff 断言），再 fan-out。
- **B2** TUI 的引擎勾选单（`e` 键从轮换升级为多选清单；勾一个 = 今天的行为）。
  取数改走 `ut-search --engine <选集>` —— TUI 因此**不自己实现合并**，它只是 fan-out 的
  又一个调用方；agent 面与人面吃的是同一条路径（D14 那条"验收形状"反着用也成立）。
- **C** 无删除步骤（纯加法）。
- **D** 文档按 §5 表 resync；README 示例。
- **E** tmux 头戴 + 两套无头。

---

## 8. 冷读预演（**待做**）

交给冷读者全文，不带对话。请他重点打：§3 两个枚举的封闭性能不能真的守住（第三个引擎想加值时
发生什么）、§4.3 部分失败信封会不会被只看 `status` 的旧调用方误读成"全好"、§6 第 9 条那个
后台作业悬挂到底怎么可靠地断言。
