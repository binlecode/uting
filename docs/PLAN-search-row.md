# PLAN-search-row —— 搜索行的形状定死 + `ut-search`

> **状态**：草拟，**未开工**。无外部前置 —— 所需的站点字段已实测存在（§2）。
> **实现的 ROADMAP 条目**：**D21**（`ut-search`）· **§11 第一条**（一条结果 ≠ 一个可播对象）。
> **是 `PLAN-engine-xmly.md` 的前置**：第三对引擎照着本文定死的行写，一次写对。
> **冷读预演已做**（2026-08-28，见 §8）：10 条 finding，全部接受，已编入正文 ——
> 其中两条击穿了原版"下游零改"的前提，§5 的承诺已按实情改写。
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
| 网易云 | `fee`（1=VIP 只给试听；8=可播、低码率） | `cloudsearch/pc` 响应 | 2026-08-28：`fee:1` 直链 720KB vs 应有 3.81MB（≈45 秒试听）。`fee:8` 时间轴完整 → 映射 `full`（§3 的判据句） |
| 喜马拉雅 | `is_paid` | `tracks/<id>.json` | 2026-08-28：resolve 侧可得；搜索侧待 Gate 0 后确认 |
| YouTube | 无同类形态 | — | 行即单视频；**两个新字段恒为默认值是合法状态** |

---

## 3. 行的新字段 —— 两个，不是一个

粒度和完整性**正交**（3.7 小时合集可以免费；45 秒试听是单曲），硬塞一个键就是重新搅在一起。

```json
{ "id":"…", "title":"…", "url":"…", "channel":"…",
  "duration":213, "duration_fmt":"…", "view_count":12345, "live_status":"not_live",
  "kind":"track",        ← 新：这一行是什么。 track | collection | multipart
  "access":"full" }      ← 新：匿名播放能拿到什么。 full | preview | paywalled
```

**枚举的定义是引擎无关的，各以它驱动的调用方决定来措辞**（冷读修正 —— 只用 B 站字段名
定义边界，第三引擎作者和站外引擎作者就只能猜，而必填 + 封闭意味着猜的结果会以事实的
面目发货）：

- **`kind`** —— `ut-play --engine E -- <本行url>` 会发生什么？
  恰好播**一个** track = `track`；一个 handle 出**多个 part** = `multipart`；
  本行是**多个 handle 的容器** = `collection`。
- **`access`** —— 匿名解出来的**时间轴**完整吗？
  完整 = `full`（**码率/音质降级仍是 `full`** —— 网易云 `fee:8` 映射到这里）；
  被截断 = `preview`（`fee:1` 的 45 秒）；解不出流 = `paywalled`。
  报的是站点事实，不是登录裁决（D16 的界线原样适用）。
- **两个都必填、枚举封闭**，与 `engine`/`status` 同级；引擎实现它，谁都不许扩展。
  **枚举装不下的新形态按上面两问映射到最近的值，映射记进 `AS-BUILT-engine.md` ——
  枚举不为它长大**（这句进契约 §3 的正文，第三引擎作者读的就是那里）。
- **`-J` 行同样注入这两个字段**（冷读补）：它们是**引擎的判断**，不是站点的原始记录，
  所以跟着每一种 results 形状走 —— 否则要更多数据的那个 agent 恰好丢了路由字段，
  且按契约自己的论证无从与截断区分。
- 不知道就如实填默认（`track`/`full`）；YouTube 恒为默认值是合法状态。
- 判据落在引擎（correctness 加在下面）；TUI 的呈现另开小改，字段先于呈现。
- `bili-search` usage 里 `-M` 那段话术保留：`kind` 是标注，`-M` 仍是排除的钝器。

**被否**：一键装两事（`flags[]` —— 必填 + 封闭两条都难敲死）；duration 阈值让 TUI 猜
（猜错一次 = 3.7 小时连播，agent 面拿不到）；只做 TUI 标记（半个功能，D14）。

---

## 4. `ut-search` —— 统一入口，fan-out 只向要它的人收费

### 4.1 形状（ROADMAP D21）

```sh
ut-search -- "周杰伦"                    # = UT_DEFAULT_ENGINE 那一个引擎（config 已有的键）
ut-search --engine bili -- "周杰伦"      # 选一个
ut-search --engine yt,bili -- "周杰伦"   # 显式 fan-out：逗号列表
ut-search --engine all -- "周杰伦"       # 发现到的全部（*-search + *-resolve 成对 glob，
                                         #   与 uting 的 scan_engines 同一条发现规则）
```

先例：Mopidy `library.search(uris=None)` 默认全 backend、`uris` 收窄（同拓扑 15 年实践）；
默认收窄成单引擎是本仓自己的账（部分失败要写进冻结信封，agent 读不到 log），
形状同 `git fetch`（默认 origin，`--all` 显式）。

### 4.2 转发什么

`-n -m -M -s -j -J -l --color` 原样透传 —— `ut-search` 自己不长搜索语义。
一个引擎独有的 flag 出现时退 1，报哪个引擎不认识它。

### 4.3 信封

**单引擎（默认路径）：`exec "$bin" "$@"`**（冷读修正 —— 让"逐字转发含退出码"成为**结构**
事实而不是待证命题；stdout、stderr、退出码天然全等）。

**多引擎**：

```json
{ "status":"ok", "query":"周杰伦", "count":40, "failed":0,
  "engines":{"yt":{"status":"ok","count":20},
             "bili":{"status":"ok","count":20}},
  "results":[ {…, "engine":"yt"}, {…, "engine":"bili"}, … ] }
```

- **行级 `engine`**。`ut-play --queue -` 的摄入已经逐行 `(.engine // $env)`（实测
  `read_queue_items`，无恙）；**`ut-playlist` 的 `results` 分支不是**（冷读击穿点 ——
  它只读信封级 `.engine`、缺了直接 error 且无视行级），修法见 §5。
- **`failed` 是多引擎信封的必需键**（冷读补）：0 = 引擎全数应答。只看 `.status` 的调用方
  会把"partial failure + 零 yt 行"读成"YouTube 没有这个查询的结果"，然后在 cookie 腐掉的
  那天起**永远静默降级** —— 契约 §3 要写明：多引擎调用方在 `status` 之外必须再看
  `failed > 0`；单引擎信封永不携带此键，键的在场同时就是形状的标记。
- **`engines{}`** 每格报 `status`/`count`，失败格多一个 `reason`。部分失败 ⇒ 信封
  `status:"ok"`、退 0；**全失败** ⇒ `status:"error"`、退 2+，**顶层不带 `reason`**
  （两个引擎可以因两个原因死，每格的 `reason` 在 `engines{}` 里 —— 这句进契约，
  否则读 `.reason` 的调用方在唯一一种 error 形状上拿到 null）。
- **无信封的孩子**（冷读补）：子进程非零退出且 stdout 不可解析 ⇒ 该格
  `{status:"error", reason:"unknown"}` —— 封闭枚举既有成员，永不发明第四套词汇。
  `ut-search` 因此把每个孩子的 stdout **与 stderr** 各收进临时文件（stderr 事后重放到
  自己的 stderr —— 两条流都满足 §25 的 fd 规矩）。
- **排序按字段分策**（冷读修正 —— 数字是跨站可比的，全轮转会把 `-s duration` 的承诺变成谎话）：
  `relevance` ⇒ 轮转交错（分数不可比，不编）；`view_count` / `duration` ⇒ 对各引擎已排序的
  列表做全局数值归并，null 沉底。
- **`-n` 是每引擎的**；**但 `UT_MAX_SEARCH_RESULTS` 封顶合并后的总行数**（冷读补 ——
  上限在引擎内部各自执行，fan-out 会把它乘引擎数；截断轮转/归并的结果不需要跨站比较，
  否掉总量 `-n` 的理由对它不适用。引擎内的钳制保留作纵深）。

### 4.4 实现事实（bash 3.2 的账）

- fan-out = 后台作业 + 每引擎两个临时文件（stdout/stderr），`wait` 后 jq 合并。
  **捕获悬挂的主张是结构性的**（孩子全部重定向、父进程 `wait` 完才打印），
  按 §27 的规矩记进"刻意不覆盖"登记而不是造一条不可能红的检查（冷读修正 ——
  原第 9 条无输入可分对错，而它一旦真红，光杆命令替换会把套件挂死在没有 `timeout` 的地板上）；
  留一条便宜的绊线：contract.sh 用套件既有的有界轮询模式后台跑一次 `out=$(ut-search …)`，
  超时即红而非悬挂。
- 延迟 = 最慢引擎（实测 bili 0.71s / yt 2–3s）。fan-out 是显式要求的，账调用方自己签。
- 发现规则与 `scan_engines` 相同（成对才算），独立实现（入口点不共享库 —— 既有的账，
  不在本 plan 里翻）。

### 4.5 名字与 D10

`ut-` 前缀 = 套件级命令。它不是任何 `X-search` 的第二拼法：存在理由是 fan-out + 合并信封
（任何现有命令做不到），单引擎转发是退化情形。`<engine>-search` 留在 PATH 上原样可用。
**agent 面收敛为 `ut-search` + `ut-play` 两个名字** —— 与 `ut-play → <engine>-resolve`（D9）
左右对称。

---

## 5. 会被改到的文件（冷读修正：原版两处"零改"承诺是假的，此表按实情记）

| 文件 | 改什么 |
|---|---|
| `shell/ut-search` | **新文件** |
| `shell/yt-search` / `shell/bili-search` | 各加 `kind`/`access`（yt 恒默认；bili 从已到手的响应字段算），`-j` 与 `-J` 都注入 |
| `shell/ut-playlist` | **一处 jq**（冷读击穿点）：`read_items` 的 `has("results")` 分支改逐行 `engine: (.engine // $e)`，仅当**两级都缺**才 error；配一条 `--offline` 夹具检查（合并形状信封进 stdin ⇒ `added == count`） |
| `shell/uting` | 三处（冷读击穿点 —— 原版"今天已如此"对搜索信封不成立）：(a) `build_all_rows` 行 engine 改 `(.engine // $e // "")`；(b) `FOCUSED_PAYLOAD` 重建单行信封时把**行的** engine 写进去（今天写的是信封级、fan-out 下为 null，会喂给 `read_items` 一个它拒收的形状）；(c) `fetch_json` 的 `CURRENT_ENGINE` 回退只在单引擎取数时成立，多选取数时留空、永不作行回退。外加 `e` 键从轮换升级为**引擎勾选单**（all / 逐个，条目来自 `scan_engines` 既有注册表），取数走 `ut-search` —— TUI 不自己长合并逻辑，人面与 agent 面吃同一条路径。`kind`/`access` 先不渲染 |
| `shell/ut-play` | **零行**（`read_queue_items` 已逐行回退，实测确认） |
| `config` | 无新键；`UT_MAX_SEARCH_RESULTS` 的注释补"也封顶 ut-search 合并后的总行数" |
| `docs/AS-BUILT-contract.md` | §3 行加两字段（含判据两问、映射不长大句、`-J` 注入句）+ `ut-search` 两张信封（含 `failed` 键、全失败无顶层 reason、排序分策）；§1 加命令节；§6 清单补"新引擎必须算 `kind`/`access`" |
| `docs/AS-BUILT-engine.md` | B 站判据（`episode_count_text`→`multipart`/`collection`、`is_pay`→`access`）；网易云 `fee:8`→`full` 的映射记录 |
| `docs/AS-BUILT-verification.md` | §27 "刻意不覆盖"登记加捕获悬挂的结构性主张 |
| `docs/ROADMAP.md` | §11 第一条随本 plan 落地删除；D21 状态 |
| `README.md` | 顶部示例块加 `ut-search` 一行；`## What it is` 加一段 |
| `VERSION` | 加法 → z 位；单独 commit（D13） |

**契约变更声明（D3）**：行加两个必填键是加法（既有键零改动），先例同 `retried` 的后加入，z 位。

---

## 6. 验证（`done_when` —— 执行，不是读）

| # | 检查 | 归属 |
|---|---|---|
| 1 | `bash -n shell/ut-search` + 既有全绿 | pre-commit / `--offline` |
| 2 | **每个发现到的引擎 × `-j` 与 `-J` 两种形状**：行含 `kind`+`access`，值在封闭枚举内 | `--offline`（夹具）+ live 半 |
| 3 | 单引擎转发全等 —— **确定性对**（冷读修正：两次独立活取的 byte-diff 是抛硬币）：URL 形查询（D8 固定拒答）与 `-s nope`（无效枚举），`ut-search` 与直调引擎 stdout、stderr、退出码三者全等 | `--offline` |
| 4 | `--engine yt,bili`：合并信封形状、行级 engine、`count`=Σ、`failed:0`；`-s duration` 下合并序为全局数值序 | live 半 |
| 5 | 部分失败 —— **真实环境而非替身**（冷读修正：原拟的 cookie 判别输入只会让引擎匿名回退**成功**）：构造一个含 curl/jq/nc、**不含 yt-dlp** 的 PATH 跑 `--engine yt,bili` ⇒ 信封 ok、`failed:1`、yt 格 `reason` 为枚举成员（无信封的孩子 → `unknown`）、退 0 | `--offline` |
| 6 | 全失败 ⇒ `status:"error"` 退 2+、顶层无 `reason`；`--engine nope` ⇒ 退 1 | `--offline` |
| 7 | B 站判别输入：已知合集 `kind:"collection"`；普通单曲 `kind:"track"` | live 半 |
| 8 | 合并信封 ⇒ `ut-playlist --add`（夹具，断 `added==count` 且逐行 engine 保留）；⇒ `ut-play --queue -`（夹具解析层） | `--offline` |
| 9 | `-n` 大 + 低 `UT_MAX_SEARCH_RESULTS` 环境 ⇒ 合并 `count` == 上限 | `--offline` |
| 10 | 捕获绊线：有界轮询后台跑 `out=$(ut-search --engine yt,bili -j …)`，超时红、不悬挂 | `--offline`（夹具引擎不可用也无妨 —— 绊的是悬挂，不是内容） |
| 11 | TUI 拆两半（冷读修正 —— drive.sh 按章程不断言，contract.sh 不起真播放器）：勾选单开合 + 双引擎取数后存活 → contract.sh 的 tmux 段；**Enter 路由到行的 engine** → `playback.sh`：从一份真实合并信封取一条 bili 行直接 `ut-play -d --engine bili`，断言播放器记录的 engine/url（路由事实是播放器记录的，不是 TUI 画面的）；drive.sh 保持 E 阶段的手动头戴用途 | 按格 |

---

## 7. 建造顺序（加面 = 结构性，走 A→E）

- **A** 行字段先行：`bili-search` 算 `kind`/`access`，`yt-search` 印默认值；契约断言跟上。
  —— A 半落地即解锁 `PLAN-engine-xmly.md`，不必等 `ut-search`。
- **B** `shell/ut-search`：先单引擎 `exec` 转发（确定性对断言），再 fan-out；
  同一步修 `ut-playlist` 的那处 jq（§5）—— 合并信封的第一个消费者要在信封存在的同一个
  commit 里就能吃它。
- **B2** TUI：三处 engine 来源修正 + 引擎勾选单（勾一个 = 今天的行为）。
- **C** 无删除步骤（纯加法）。
- **D** 文档按 §5 的表 resync。
- **E** tmux 头戴 + 两套无头。

---

## 8. 冷读预演 —— **已做**（2026-08-28）

plan 全文（不带作者会话）交给冷读者写失败回顾。**10 条 finding，全部接受**，已编入上文，
无一拒绝。除 plan 自标的三处（枚举封闭性、部分失败误读、悬挂断言可写性）外，最重的两条
是 plan 完全没标的、且各自击穿一句承诺：

1. `ut-playlist` 的 `results` 分支拒收合并信封（"下游零改"为假）→ §5 改为一处 jq + 夹具检查
2. `uting` 行 engine 取自信封级（"今天已如此"为假；fan-out 下每行路由到会话引擎，
   bili 行全部撞 D12 的墙）→ §5 的三处修正清单
3. 部分失败静默降级 → `failed` 必需键 + 契约句
4. 活取 byte-diff 是抛硬币 → 确定性对 + `exec` 结构化
5. 原拟的失败强制输入只会成功 → 无 yt-dlp 的 PATH + `unknown` 映射
6. 检查 9/10 一条不可能红、一条所有者被章程禁止 → 结构性登记 + 绊线；TUI 检查拆两半
7. `fee:8` 是 `access` 枚举的第一个反例 → 判据改为引擎无关的两问 + 映射不长大句
8. `UT_MAX_SEARCH_RESULTS` 被 fan-out 乘引擎数 → 合并后封顶
9. `-s duration` 全轮转违约 → 排序分策
10. `-J` 行悄悄缺必填字段 → 注入句 + 检查 2 扩两形状
