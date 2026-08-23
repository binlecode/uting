# RESEARCH-bilibili-engine —— 第二引擎选型确认，与 B 站接入的产品级方案

2026-08-22 写。**外部调研 + 选型确认，实现方案待决**。按 `CLAUDE.md` 的五段流水线：这一段记"别人
怎么做的、实测是什么、选哪个"，**具体字段名与 flag 表属于 `PLAN-`**，排序属于 `ROADMAP.md`。
终结方式：蒸馏进那两处后删除本文件。

姊妹篇：`RESEARCH-tui-player-landscape-2026.md`（领域全景，问"谁在做"）。这份问"怎么做"。

---

## 0. 结论

**第二引擎 = Bilibili。已确认，理由见 §1。**

**推荐集成形态（2026-08-22 网调核实后修订）：全托管 yt-dlp + mpv，并把 `bilisearch` 的元数据
丢失问题修到上游去。**

> **修订记录**：本文初稿推荐"直连搜索 + yt-dlp/mpv 播放"（路径 C），理由是省掉 N+1 次往返。
> 网调核实后**撤回该推荐** —— 直连 B 站 API 与 2026 年的产品级实践**不对齐**，三条理由见 §2.5
> （法务、维护、技术正确性）。成本论据仍然成立，但正确的解法不是绕过 yt-dlp，而是**修 yt-dlp**：
> 同一个代码库里 `SoundcloudSearchIE` 已经在做正确的事，`BiliBiliSearchIE` 没做（§2.6）。

**其余候选的处置**（都不与 B 站竞争，属于不同类别）：

| 候选 | 处置 | 理由 |
|---|---|---|
| YouTube Music | **不算第二引擎** | 同一个站的另一个语料库（`music.youtube.com/search?q=…#songs`），同 extractor、同 cookie、同鉴权。属于"YouTube 引擎的检索面改进"，独立排期 |
| Bandcamp / Apple Podcasts / 喜马拉雅 | **不需要接** | URL-only，`yt-play <url>` 今天就能放。要做的是写进文档并纳入回归，不是写代码 |
| 网易云 / QQ音乐 | **排除** | extractor 存在但地域封锁 + VIP 门槛。`go-musicfox` 靠 `UnblockNeteaseMusic` 才活着 —— 那是持续军备竞赛，等于把 `ROADMAP.md` §5 的环境账加倍 |
| Spotify / Tidal / Deezer | **不可能** | yt-dlp 无 extractor（DRM） |
| Niconico | **排除** | 有 `nicosearch:` 前缀，但实测返回 0 条 |

---

## 0.5 验证状态（先划清界线）

**§3 叫"产品级技术方案"，但它是方案，不是实现。到本文写成为止，uting 的代码一行都没改，
uting 自己的入口（`yt-search` / `yt-play` / `--info` / `--transcript` / `yt-tui`）
对 B 站一次都没跑过** —— 所有测量都是裸 `yt-dlp` 或裸 `curl` 打出来的。

| 主张 | 验证方式 | 状态 |
|---|---|---|
| `bilisearch:` 前缀存在且可用 | 跑 `yt-dlp` | ✅ **实跑** |
| flat / 非 flat 的字段两难（1 次 vs N+1 次；合集仍空） | 跑 `yt-dlp` 三次，含一次更正重测 | ✅ **实跑** |
| 直连 `search/type` 可用、字段齐、**不需要 WBI**、只需 `buvid3` | 跑 `curl`（HTTP 200 / `code:0` / 20 条） | ✅ **实跑（单点）** |
| `"MM:SS"` 分钟无上限、`<em class="keyword">` 标记、合集占据头部 | 同一次 `curl` 响应体 | ✅ **实跑（单点）** |
| 裸流 URL 无 Referer 403、带 Referer 206 | `yt-dlp -g` + `curl -r 0-1023` 各两次 | ✅ **实跑（单点）** |
| `bilisearch` 丢字段的源码原因、WBI 算法、音频区 `lyric` 走 subtitles | 读 `yt_dlp/extractor/bilibili.py` | 📖 **读码，未跑** |
| ytdl_hook 转发 Referer 的机制与两个陷阱 | 读 `player/lua/ytdl_hook.lua` | 📖 **读码，未跑** |
| `bilibili-tui` / `cliamp` 的实现选择与代码量 | 读其源码 | 📖 **读码，未跑** |
| **§3 的整套方案**：seam 内分支、envelope 同构、`-s/--source`、时长第三种拼法、剥标记、万/亿、合集策略、header 契约修法 | — | ❌ **未实现、未跑** |
| **端到端播放**：mpv 真的放出一声 B 站的音频 | — | ❌ **从未发生** |
| 搜索第 2 页、登录态 `SESSDATA`、风控 `-412`、海外 IP、造 `buvid3` vs 服务端取 | — | ❌ **未测** |
| BAC / `Nemo2011` 归档与律师函、yt-dlp bilibili extractor 仍在维护 | GitHub API + 网络检索（§2.5） | ✅ **已核实** |
| B 站开放平台只有 投稿／直播／OAuth 三类，无搜索与播放地址 API；官方第三方展示手段是 iframe 外链播放器 | 网络检索官方站点与文档目录（§2.55） | ⚠️ **已核实（间接）** —— 官方文档站是 SPA，抓不到正文，结论取自各处一致的目录名与能力名，未见到逐条 API 清单 |
| §2.6 的上游 patch 真的能被 yt-dlp 接受 | — | ❌ **未验证**（已改为不提 PR，见 §2.7） |
| **`bilisearch` 因缺 Referer 而 412，加 `--add-header` 即修复** | 跑 `yt-dlp` 四次（含 UA 对照） | ✅ **实跑，根因已定位到源码** |
| **风控可在单 IP／数小时／约 15 次请求内触发** | 本轮探测把自己打进了风控态 | ✅ **实际遭遇**（非受控实验） |
| flat+Referer 0.93s／10 条／零字段 | 计时实跑 | ✅ **实跑** |
| 完整抽取 >120s（N=10）、单条 >100s | 计时实跑，**但在风控态下** | ⚠️ **实跑，非干净测量** |

换句话说：**"B 站这条路能不能走通"有证据，"这套方案对不对"没有。** 前者是本文的贡献，
后者要等 §5 的 A→E 一步步做出来，且 E 步的 `verify-suite` phase 4（audible）不可省。

---

## 1. 选型确认：为什么第二引擎是 B 站

四条论据，两条来自实测，两条来自领域调研。

### 1.1 内容面：华语内容唯一规模化的可取源

这是唯一一条不能被技术优化掉的理由。uting 的人机面是中英双语，作者是中文用户，而 YouTube 的华语
音乐语料在**质量与覆盖上都不是最优**。B 站是目前 yt-dlp 生态里唯一能规模化取到华语音乐内容的站
（网易云/QQ音乐见 §0 表）。

### 1.2 技术面（实测）：数据本身是拿得到的

> 本节证明的是**「B 站这条路走得通」**，不是"该用直连"。直连作为实现手段已在 §2.5 被撤回；
> 这里的实测保留下来，是因为它同时说明了 §2.6 那个上游 patch **应该能拿到哪些字段**。

```sh
BUVID="$(uuidgen)infoc"
curl -sS -G 'https://api.bilibili.com/x/web-interface/search/type' \
  --data-urlencode 'search_type=video' --data-urlencode "keyword=周杰伦" --data-urlencode 'page=1' \
  -H "User-Agent: $UA" -H 'Referer: https://www.bilibili.com/' -H "Cookie: buvid3=$BUVID"
```

实测（2026-08-22，单点）：`http=200`、`code=0`、20 条结果，**不需要 WBI 签名**：

```json
{"bvid":"BV1FPjy6TEiE",
 "title":"【<em class=\"keyword\">周杰伦</em>】50首精选合集/后台播放/无损音质/HIFI音质/…",
 "author":"超级爱下雨天","duration":"222:28","play":10697444,
 "pubdate":1781909545,"arcurl":"http://www.bilibili.com/video/av116779154212963"}
```

uting envelope 需要的 title / uploader / duration / view_count **一次拿全**。依赖只有 `curl` + `jq`
—— 两个已经在依赖表里的东西，**不新增任何运行时依赖**（`CLAUDE.md` 的硬规则之一）。

### 1.3 播放面：不需要自己解流

mpv 的 ytdl_hook 已经把最难的部分做完了（§3.3）。B 站接入**不需要**碰 DASH 选流、CDN 选点、
Referer 注入 —— 这些是 `bilibili-tui` 花了约 2500 行做的事（§3.6）。

### 1.4 生态面：新生代中文 TUI 项目集体选了同一条路

`RESEARCH-tui-player-landscape-2026.md` §2.4 的实测：2026 年建仓的中文 TUI 播放器
（`maboroshi`、`bighu630/music-tui`、`yueting`、`BiliBiliMusicPlayer`）**一律走 YouTube / B站 +
yt-dlp/mpv，不再碰网易云**。四个独立开发者在同一年收敛到同一组音源，是对 §0 那张排除表的旁证。

### 1.5 确认要付的三笔账

诚实记下，选型确认不等于零成本：

| 账 | 性质 |
|---|---|
| **`--get-url` 的契约缺陷**（§3.4）—— 裸 URL 无 Referer 即 403，实测复现 | **接入前必须先修**。这是契约变更，不是功能 |
| 音乐搜索头部结果**天然是长合集**（§3.7）—— 实测前三条全是"50首精选/100首合集"，时长 222 分钟 | 产品问题，不是技术问题。需要一个筛选或标注策略 |
| 三种新数据形状（§3.2.3）：HTML 高亮标记、`"MM:SS"` 分钟无上限、播放量的万/亿 | 都在渲染层与格式化层，可控 |

---

## 2. 三条集成路径，与为什么选 C

| 路径 | 含义 | 谁在用 |
|---|---|---|
| **A. 全托管 yt-dlp** | 搜索与解流都交给 yt-dlp | uting 今天（YouTube）、`cliamp`、`yt-x` |
| **B. 原生 API 直连** | 自己打 HTTP、自己签名、自己选流、自己拼 header | `bilibili-tui`、`go-musicfox` |
| **C. 混合** | 搜索直连 B 站 API，解流/播放交给 yt-dlp + mpv | ~~初稿推荐~~ **已撤回**（§2.5） |

> **术语澄清**：本文的"直连"指 **uting 自己打 B 站的 HTTP API**，不是"yt-dlp 有没有支持"。
> **yt-dlp 是支持 B 站搜索的** —— `BiliBiliSearchIE`，`_SEARCH_KEY = 'bilisearch'`，前缀 `bilisearch<N>:`。
> 问题不在有没有，在**它返回什么**（下一段）。早先草稿把这层叫"原生搜索"，与"原生 API 直连"（路径 B）
> 撞词，已统一改为"直连搜索"。

**A 为什么不够**：yt-dlp 的 `bilisearch` 在源码层面就把元数据丢了。`bilibili.py` 的
`BiliBiliSearchIE._search_results` 最后一行：

```python
for video in videos:
    yield self.url_result(video['arcurl'], 'BiliBili', str(video['aid']))
```

**只 yield 了 URL 和 aid**。同一份响应里的 `title` / `author` / `duration` / `play` / `pic` 被原样
丢弃 —— yt-dlp 的目标是"逐条完整抽取"，所以宁可让 `BiliBiliIE` 对每条结果再打一次
`/x/player/wbi/*`。

实测（2026-08-22）—— **更正**：本文早先一稿写"关掉 flat 也只多拿到 title"，那是抽样偏差，
命中的三条恰好都是合集/多P。重测后的准确结论是**两难，而不是"拿不到"**：

| 调用方式 | 请求数 | title | duration | view_count | uploader |
|---|---:|---|---|---|---|
| `--flat-playlist`（便宜） | 1 | ❌ | ❌ | ❌ | ❌ |
| 不加 flat（完整抽取） | **N+1** | ✅ | ✅ | ✅ | ✅ |
| 不加 flat，但结果是**合集/多P** | N+1 | ❌ | ❌ | ❌ | ❌ |

```
$ yt-dlp -J --playlist-items 1-3 "bilisearch3:告白气球 官方" | jq …
[{"t":"Roblox 音乐ID 告白气球","dur":69.488,"views":14917,"ch":"_沥川_"},
 {"t":"【4K60FPS】周杰伦《告白气球》超甜神曲！…","dur":210.132,"views":6335894,"ch":"音乐私藏馆"},
 {"t":null,"dur":null,"views":null,"ch":null}]          ← 第三条：合集/多P，全 null
```

所以代价是**在"1 次请求但没有元数据"和"N+1 次请求"之间二选一**，而第三行说明：即便付了 N+1,
**音乐搜索最常见的那类结果（合集）依然是空的**（§3.7）。直连一次调用则三种情况都拿得到。

**B 为什么过头**：见 §3.6 的账单。

**初稿的分界线**是"搜索直连、播放托管"，理由是 yt-dlp 在搜索这一步是净损失。**该结论已撤回**
（§2.5）—— 净损失是真的，但解法是修上游（§2.6），不是绕开。

**保留下来的那半条依然成立**：分界不在"站点"，在"操作"。只是四个操作现在都落在 yt-dlp 上，
差别在于哪一个需要向上游提 patch。

### 2.5 网调核实：直连 B 站 API **不对齐** 2026 年的产品级实践

三条理由，第一条是决定性的。

#### (1) 法务：这正是 2026-01 那封律师函点名的行为

- **2026-01-28**，B 站委托律所向 `SocialSisterYi/bilibili-API-collect`（**20,234★**，中文圈事实上的
  B 站 API 权威文档）发出停止侵权函，指控其**系统性收集、整理并公开分发 B 站非公开 API 接口**，
  明确列举了**调用逻辑、参数结构、访问控制与安全认证机制**。
- **2026-01-30 仓库归档**，默认分支被改名为 **`deprecated`**。贡献者的 fork 同步归档。
  存活的 fork 最大只有 99★ —— **这份文档共同体没有继承者**。
- **`Nemo2011/bilibili-api`（4,187★）**，中文圈最主流的 Python B 站客户端，**同样已归档**，
  最后一次提交 2026-07-06，commit message 是 `owari`（終わり）。

本文 §3.2 原本要写的东西 —— search 端点、参数表、`buvid3` 怎么伪造以过风控 —— **逐项落在那封函
点名的四类之内**。uting 是一个公开仓库，且 `SPEC-system.md` 的纪律要求把契约写清楚：那意味着
把这些内容永久固化在仓库里。

**对照之下，yt-dlp 是一个不同的风险位置**：186k★、非归档、2026-08 仍在推，B 站相关的知识住在
**它的**代码库里而不是 uting 的。uting shell out 给它，仓库里就没有任何 B 站 API 知识。
用户先前把 yt-dlp 称作 "useless extra" —— 在这一层它恰恰是**责任边界**。

#### (2) 维护：参考消失了，而 yt-dlp 的 extractor 还在被修

| | 直连自建 | yt-dlp |
|---|---|---|
| 上游参考 | **没有了**（BAC 已归档） | 自己就是上游 |
| 接口变更谁吸收 | 你 | yt-dlp 维护者 |
| 近期实绩 | — | `2026-07-03 [ie/bilibili] Fix API extraction (#13730)`、`2025-08-19 Handle Bangumi redirection`、`2025-07-21 Pass newer user-agent with API requests (#13736)` |

那条 2025-07-21 的 commit 尤其说明问题：**B 站会因为 UA 不够新就开始拒绝请求**，而这类变更由
yt-dlp 替所有下游吸收了一次。手搓的那条要自己发现、自己修，且没有文档可查。

#### (3) 技术正确性：`buvid3 = uuidgen + infoc` 不是 production-grade

那是照抄 yt-dlp 的权宜写法。正规做法（BAC 归档前的文档）：

- `GET https://api.bilibili.com/x/frontend/finger/spi` → 返回 `b_3`（buvid3）/ `b_4`（buvid4）
- 或 `GET/HEAD https://www.bilibili.com/`，从 `Set-Cookie` 里取 `buvid3` + `b_nut`
- 且 **UA 不能包含 `curl` / `python` 之类子串**，同 UA 不能短时间重复请求

而风控实际检查的是 **`buvid3` + `buvid4` + `b_nut` + `bili_ticket`** 一组，外加设备指纹激活
（ExClimbWuzhi）。也就是说 §3.2 那版方案**在风控收紧时会先坏，而且坏在没有上游可跟的地方**。
（本文写作时它是能用的 —— §1.2 的实测为真。"今天能用"与"产品级"是两件事。）

### 2.55 网调核实：B 站 API 是有的，但**做播放器要的那两个能力没有官方接口**

先把话说准，"B 站没有 API"是错的。分三层：

| 层 | 有没有 | 说明 |
|---|---|---|
| **① 非公开 web / App API** | **有，而且今天就能跑** | `api.bilibili.com/x/web-interface/search/type` 等，整个网站和 App 都靠它。§1.2 实测 `code:0 OK`。但**无官方文档、无稳定性承诺、有风控**，且 2026-01 的律师函把"系统性收集整理并公开分发这些接口"定性为侵权（§2.5） |
| **② 官方开放平台 API** | **有，但能力面很窄** | 有文档、有 appkey／签名、有服务协议。只有下表三类 |
| **③ 播放器需要的两个能力**（搜任意视频、取任意视频的播放地址） | **② 里没有** | 这是本节的全部结论 |

也就是说：**能用的那条路是非官方的，官方的那条路不覆盖我们要做的事。** 这两句都成立，
合起来才是准确表述 —— "没有 API"不是。

"不重复造轮子"的前提是轮子存在。就 ③ 而言，**官方轮子不存在。**

哔哩哔哩开放平台（`open.bilibili.com` / `openhome.bilibili.com`）实际提供的能力只有三类：

| 平台 | 面向谁 | 能做什么 |
|---|---|---|
| **稿件开放平台**（`arcopen`，`member.bilibili.com/arcopen/…`） | 创作者 / MCN / 合作方 | **投稿**与稿件管理 |
| **直播开放平台**（`open-live.bilibili.com`） | 互动玩法开发者 | 直播弹幕 / 礼物事件，appkey + 签名 |
| **OAuth 2.0**（`open.bilibili.com/doc/4/…`） | 第三方网页应用 | 让用户授权访问**该用户自己**的数据 |

**三类里没有一类提供"搜索任意视频"或"取任意视频的播放地址"。** 官方唯一认可的、给第三方展示
B 站视频的手段是**外链 iframe 播放器**（`player.bilibili.com`，官网有"外链播放器 - 使用说明"，
分享菜单里就能拿到嵌入代码）：

```html
<iframe src="//player.bilibili.com/player.html?bvid=BV…" allowfullscreen="true"></iframe>
```

对终端播放器毫无用处 —— 它是一个网页播放器，不吐流地址。

**最有力的反证恰恰是那封律师函**（§2.5）：如果存在官方的搜索/播放 API，
`bilibili-API-collect` 就没有存在的理由，那封函也无从谈起。**没有人会为"公开 API 的文档"发律师函。**

所以"不重复造轮子"在这里的正确落点不是找官方 SDK，而是 **复用社区已经造好并且还在维护的那个轮子
—— yt-dlp**（186k★、非归档、2026-07 仍在修 B 站 extractor）。它是这个领域事实上的唯一轮子，
而我们已经在依赖它。

### 2.6 正确的解法：修 yt-dlp，而不是绕开它

N+1 往返这个成本论据**仍然成立**。但 yt-dlp 自己的代码库里已经有正确写法 —— 是
`BiliBiliSearchIE` 没跟上，不是 yt-dlp 做不到：

```python
# soundcloud.py — SoundcloudSearchIE：把搜索响应里的元数据透传给 flat 结果
yield self.url_result(
    item['uri'], SoundcloudIE.ie_key(),
    **self._extract_info_dict(item, extract_flat=True))     # ← 元数据带过去了

# bilibili.py — BiliBiliSearchIE：只给 URL 和 aid，同一响应里的
#               title / author / duration / play / pic 全部丢弃
yield self.url_result(video['arcurl'], 'BiliBili', str(video['aid']))
```

**修法是让 bilibili 对齐 soundcloud 的既有模式** —— 把 `title` / `author` / `duration`（`"MM:SS"`
需转秒）/ `play` / `pic` 映射进 `url_result` 的 kwargs。这是一个小 patch，且**在同一代码库里有先例**，
不是新设计。

好处叠了三层：uting 一行 B 站 API 代码都不用写；`--flat-playlist` 一次请求就拿到全部字段
（成本回到与直连相同）；上游修好之后**所有 yt-dlp 下游都受益**，维护责任也留在 yt-dlp。

代价：**外部依赖，节奏不由 uting 控制**。在 patch 合并并进入 release 之前，B 站搜索只能在
"1 次请求无元数据"和"N+1 次完整抽取"之间选 —— 这是一个可以接受的过渡态（§5 的 B 步）。

### 2.7 实测推翻 §2.6：adaptor 不是"要不要"，是"必须"，而且第一件事只需一个 flag

2026-08-22 晚追测，两个新事实。**这两条都比 §2.6 的上游 patch 更紧急。**

#### (1) yt-dlp 的 B 站搜索**本身就是坏的** —— HTTP 412，根因是缺一个 Referer

```
$ yt-dlp --flat-playlist -J "bilisearch3:周杰伦"
yt_dlp.networking.exceptions.HTTPError: HTTP Error 412: Precondition Failed
```

同一时刻，手写 curl 打同一端点返回 `{"code":0,"message":"OK"}`。差异不在 UA
（`--user-agent` 换成 Chrome 仍 412），在 **Referer**：

```python
class BiliBiliSearchIE(SearchInfoExtractor):        # ← 注意基类
    def _search_results(self, query):
        videos = self._download_json(
            'https://api.bilibili.com/x/web-interface/search/type', query,
            note=..., query={...})                  # ← 没有 headers=
```

`BiliBiliSearchIE` **不继承 `BilibiliBaseIE`**，因而拿不到那份
`_HEADERS = {'Referer': 'https://www.bilibili.com/'}`；B 站每一个其他 extractor 都带着它，唯独搜索没有。

**修法是一个 flag，零 B 站 API 知识：**

```
$ yt-dlp --flat-playlist -J --add-header 'Referer:https://www.bilibili.com/' "bilisearch3:周杰伦"
{"n":3,"ids":["116779154212963","1415480","117125301671376"]}      ← 通了
```

这一条对 uting 是**纯增益**：`fetch_results` 已经在拼 yt-dlp 的 argv 数组，加一个 `--add-header`
即可；播放路径经 `--ytdl-raw-options` 同理。Referer 是公开值、不是认证机制，
与 §2.5 的法务顾虑无关。

#### (2) 完整抽取那条路**不可用**，不只是慢

| 路径 | N=10 耗时 | 元数据 |
|---|---|---|
| `--flat-playlist` + Referer | **0.93 s** | ❌ 一个字段都没有（`withTitle: 0`） |
| 完整抽取 + Referer | **>120 s 超时未完成** | — |
| 单条视频完整抽取 | **>100 s 超时未完成** | — |

**重要口径**：后两个数字是在**本机 IP 已被风控**的状态下测的 —— 同一条 BV 在当天早些时候
（约 15 次请求之前）`yt-dlp -g` 几秒就出结果。所以它们**不是干净的延迟测量**，而是另一件事的证据：

> **风控在单 IP、数小时、约 15 次请求内就会触发**，触发后**搜索端点仍可用、逐条视频抽取瘫痪**。

这把 §5 的过渡态（"先接受 N+1 完整抽取"）判了死刑：N+1 不只是慢，它**在风控下先死**，
而且 N 越大死得越快。**把 N+1 压成 1 次请求，从性能优化变成了可用性前提。**

#### (3) 于是 adaptor 分两件事，性质完全不同

| # | 做什么 | 形态 | 代价 | 状态 |
|---|---|---|---|---|
| **A1** | 给 B 站请求补 Referer，修 412 | **一个 flag**（`--add-header`） | 零 | 可以直接做 |
| **A2** | 让 flat 搜索保留元数据（1 次请求拿全字段） | **yt-dlp extractor override 插件** | 一个 Python 文件进 bash 仓库 | **需要决策** |

A2 的可行性已核实：yt-dlp 有一等公民的覆盖式插件 API
（`extractor/common.py:4120` 的 `__init_subclass__(cls, *, plugin_name=...)`，
它会 `setattr(sys.modules[...], super_class.__name__, cls)` **真的替换掉内建类**），
配合 `--plugin-dirs DIR`（2026.08.19 已有）可以**放在 uting 仓库内、每次调用时指过去**——
零安装步骤、不污染用户全局、不新增运行时依赖。

A2 的代价要如实记：插件必须**重新发出那次搜索请求**（父类把数据丢在自己方法里，`super()` 拿不回来），
所以约 12 行 B 站端点与参数会落进本仓 —— 比 §2.5 反对的"完整客户端"小得多，
且不含任何认证机制（WBI / buvid3 伪造 / 风控绕过一概不碰，那些仍由 yt-dlp 负责），
但**不为零**。这是 A2 需要一次明确决策、而不是顺手实现的原因。

---

## 3. 产品级技术方案

"产品级"与"能跑"的差别，在下面每一节末尾的**护栏**一行。

### 3.1 总体：seam 切在操作，不在站点

uting 的 core 已经是按操作组织的（`fetch_results` / `resolve_stream_url` / `run_mpv` /
`resolve_info` / `probe_media_fetchable`，见 `SPEC-system.md` §5）。**这正好是对的形状**，B 站接入
不需要引入 provider 抽象，只需要在既有 seam 内部按 source 分支：

```
  fetch_results(query, source)
      source=youtube  → yt-dlp "ytsearch${N}:${q}"      （今天）
      source=bilibili → curl /x/web-interface/search/type + jq   （新增）
                        ↓ 两条路都产出同一个 envelope
  resolve_stream_url(url)  → yt-dlp -g            （两站共用，需修 header，§3.4）
  run_mpv(url)             → mpv --ytdl-format    （两站共用，无需改动）
  resolve_info(url)        → yt-dlp --dump-json   （两站共用）
```

**护栏**：新增的 curl 路径必须产出**与 YouTube 路径逐字段同构的 envelope**。任何"B 站特有字段"
都不进 envelope —— 否则调用方要按 source 分支，契约就废了。

### 3.2 搜索层

> **本节状态：作为"直连"实现方案已撤回（§2.5）。** 保留全文的理由有二：
> (a) 其中的**数据形状**（`<em>` 标记、`"MM:SS"`、万/亿、`code!=0` 两层判断）与实现路径无关，
> 无论字段是 yt-dlp 给的还是直连拿的，uting 侧都要处理；
> (b) §2.6 的上游 patch 要把哪些字段映射进去，依据就在这里。
> **不要照本节去写 curl 调用。**

#### 3.2.1 端点与参数

`GET https://api.bilibili.com/x/web-interface/search/type`

必需：`search_type=video`、`keyword`、`page`。
必需 header：`User-Agent`（浏览器 UA）、`Referer: https://www.bilibili.com/`。
必需 cookie：**`buvid3`**。

`buvid3` 的取法 —— yt-dlp 的做法是不请求服务端，直接造一个（`bilibili.py:1920`）：

```python
if not self._get_cookies('https://api.bilibili.com').get('buvid3'):
    self._set_cookie('.bilibili.com', 'buvid3', f'{uuid.uuid4()}infoc')
```

格式是 `<uuid>infoc`。bash 侧 `uuidgen` 即可，macOS 自带。
（`bilibili-tui` 走的是另一条：`client.rs:1483` 有 `get_buvid3()` 向服务端要一个真的。造一个更省一趟，
但**风控强度未实测**，见 §3.8。）

#### 3.2.2 分页

响应里有 `numResults` / `page` / `pagesize`（字段名取自 `bilibili-tui/src/api/search.rs` 的
`SearchData`）。实测单页 20 条。**page 2 及以后未实测。**

#### 3.2.3 字段映射与三个必须处理的形状

| uting envelope | B 站 search API | 处理 |
|---|---|---|
| title | `title` | **必须剥 HTML**：`<em class="keyword">…</em>` |
| uploader | `author` | 直取 |
| duration | `duration` | **`"MM:SS"` 字符串，分钟无上限**（实测 `"222:28"` = 222 分 28 秒）。不是秒，也不是 `HH:MM:SS` |
| view_count | `play` | 整数。zh 下按万/亿格式化，en 下不 |
| id | `bvid` | 优先 `bvid` 而非 `aid`；`arcurl` 给的是 `av` 形式 |
| url | 由 `bvid` 拼 `https://www.bilibili.com/video/<bvid>` | 比直接用 `arcurl` 稳定 |
| upload_date | `pubdate`（epoch） | |

`bilibili-tui/src/api/search.rs` 为前三条各写了一个 helper（`display_title()` 剥标记、
`author_name()` 兜底"未知"、`format_play()` 输出 `1069.7万`）—— **两个独立实现撞上同一组坑**，
这三条不是本项目的特殊需求。

**护栏三条**：
1. **剥标记必须在宽度计算之前**。uting 的宽度层按显示单元格算 CJK，若把 `<em class="keyword">`
   算进去，40 列下的 reflow 会全错。
2. **`"MM:SS"` 是第三种时长拼法**（`ROADMAP.md` §7.5 已记了两种）。加在 core 的时长格式化函数里，
   不加在 `yt-tui` —— 「correctness 加在 core，让所有界面继承」。
3. **万/亿只在 zh 下用**。uting 有中英 i18n 且"无串泄漏"是已验证的性质，别在这里破。

#### 3.2.4 失败映射

`code != 0` 时响应体带 `message`。必须映射到 uting 既有的退出码分类与错误枚举，
**不新增枚举成员**（对照 2026-08-22 把 HTTP 429 归入 `network` 的先例：可重试是调用方唯一会分支的语义）。

**护栏**：curl 的 `-w '%{http_code}'` 与 body 里的 `code` 是两层，**两层都要判**。
HTTP 200 + `code: -412` 是 B 站表达"被风控"的常见形状。

### 3.3 播放层：交给 mpv 的 ytdl_hook，不要碰（已源码验证）

uting 现在的 `run_mpv()`（`shell/yt:320-368`）传 `--ytdl-format`，由 **mpv 自己的 ytdl_hook** 去调
yt-dlp。这一路对 B 站**不需要任何改动**，而且免费拿到两样东西。

#### 3.3.1 mpv 没有自己的抽取器 —— 它 exec 的就是 yt-dlp

`player/lua/ytdl_hook.lua:18`（mpv master，本机 mpv v0.41.0）：

```lua
paths_to_search = {"yt-dlp", "yt-dlp_x86", "youtube-dl"},
```

**"用 mpv 放一条 B 站页面 URL"在实现上就是一次 yt-dlp 调用。** 没有 yt-dlp，mpv 只能放直链媒体。
这一条决定了 yt-dlp 在本方案里**不是可选附件**：直连搜索只是把它从"搜索"这一个操作里移走
（因为在那里它是净损失），它仍然是 `resolve_stream_url` / `run_mpv` / `resolve_info` /
`--transcript` / `probe_media_fetchable` 五个操作里另外四个的抽取器。

#### 3.3.2 Referer 确实会被转发 —— 机制与两个陷阱

早先一稿把"ytdl_hook 会转发 header"标为**推断**。已读源码确认（`ytdl_hook.lua:141-160`）：

```lua
-- youtube-dl may set special http headers for some sites (user-agent, cookies)
local function set_http_headers(http_headers)
    local useragent = http_headers["User-Agent"]
    if useragent and not option_was_set("user-agent") then
        mp.set_property("file-local-options/user-agent", useragent)
    end
    local additional_fields = {"Cookie", "Referer", "X-Forwarded-For"}
    ...
    if #headers > 0 and not option_was_set("http-header-fields") then
        mp.set_property_native("file-local-options/http-header-fields", headers)
    end
```

`Referer` 在白名单里，所以 B 站的播放路径**确实免费拿到它**。但读到了两个必须记下的陷阱：

| 陷阱 | 后果 |
|---|---|
| **白名单只有四项**（`User-Agent` + `Cookie` / `Referer` / `X-Forwarded-For`） | 不是无差别转发。将来若某个站需要 `Origin` 或自定义头，ytdl_hook 会**静默丢弃** |
| **`not option_was_set(...)` 守卫** | 一旦 uting 自己传了 `--http-header-fields`（或 `--user-agent`），ytdl_hook **整段不再转发**，Referer 静默丢失。§3.4 修 `--get-url` 时如果顺手也往播放路径加 header，就会踩中这个 |

- **登录音质**。uting 已有 `YT_COOKIE_BROWSER` → `--cookies-from-browser`，`SESSDATA` 顺带就带上了。

#### 3.3.3 行业对齐：连最"原生"的 B 站客户端也 spawn mpv

`bilibili-tui` 自己实现了 WBI / DASH 选流 / CDN 测速（约 2500 行，§3.6），**但播放照样交给 mpv**
（`src/player/mod.rs`）：

```rust
/// Play a video using mpv with yt-dlp and report watch progress
let mut cmd = Command::new("mpv");                                    // :77
cmd.arg(format!("--http-header-fields=Referer: {webpage_url}"));      // :100
let ipc_path = mpv_ipc_path("bilibili-tui-mpv", &cid.to_string());    // :73
```

三点值得注意：它**手动注入 Referer**（因为自己解的流，没有 ytdl_hook 替它做 —— 正是 §3.4 的同一个
问题）；它用 `--input-ipc-server` + IPC 轮询 `time-pos`，**与 uting 现有的脱离终端播放器架构同构**；
连它的函数注释都写着 "with yt-dlp"。

场上的分法很清楚：**从网上取流的播放器用 mpv**（`yt-x`、`ytfzf`、`bighu630/music-tui`、
`mpv-mcp-server`、`termusic` 的 mpv 后端、`bilibili-tui`）；**放本地文件的才自建音频引擎**
（`kew`、`musikcube`、`Keet`）。`cliamp` 是唯一的例外（Go 的 beep + ALSA 自建管线，但解流仍用
yt-dlp）—— 而它有一整个 Go 音频生态可用，bash 没有。**uting 用 mpv 是对齐的，且几乎没有第二选项。**

**护栏**：`run_mpv()` 里那句 `extractor-args=youtube:player_client=android`（匿名时避免 403）
**是 YouTube 专属的**。B 站路径下它无害但无意义 —— 确认它不会被误当成通用设置，否则将来第三个引擎
会继承一个和自己无关的 extractor-arg。

### 3.4 解流层：`--get-url` 的契约缺陷（**接入前必须先修**）

实测（单点）：

```
$ URL=$(yt-dlp -g -f 'ba/b' https://www.bilibili.com/video/BV1FPjy6TEiE | head -1)
no Referer : 403
w/ Referer : 206
```

`resolve_stream_url()`（`shell/yt:1171`）跑的是 `yt-dlp -g`，把**裸 URL** 塞进 envelope 的
`stream_urls[]`。而 envelope 现在是：

```json
{"status":…, "url":…, "mode":…, "format":…, "stream_urls":[…]}
```

**没有任何位置放 header。** 拿到这个 URL 的 agent 直接请求就是 403。

**这是通用缺陷，不止 B 站** —— 任何校验 Referer/UA 的 CDN 都一样，只是 YouTube 不校验，所以一直
没暴露。按 `CLAUDE.md`「契约是冻结面」，给 `stream_urls` 加 per-stream header 是一次**需要明写的
契约变更**，不能作为 B 站特性的副作用悄悄发生。

2026-08-22 的 envelope 可观测性那一轮（commit `a967dc0`）已把「播放器死亡原因读不到」补上，
`ROADMAP.md` §6.2 的缺口随之关闭、其 `PLAN-` 也已按约定删除。**本条是同类的下一个洞**：
那一轮修的是「播放器状态说不出来」，这一条是「解出来的流别人用不了」。

三个可选形状（选型属 `PLAN-`）：
- `stream_urls` 从 `[string]` 变成 `[{url, http_headers}]` —— 破坏性变更
- 平级加一个 `http_headers` 对象（一次解流的所有流共用同一组 header，实际成立）—— 向后兼容
- 额外输出一条可直接执行的 `curl`/`ffmpeg` 参数串 —— 最省调用方的事，但把渲染塞进了契约

**护栏**：无论选哪个，**退出码分类不变**，且 `-j` 仍是单行。

### 3.5 认证层：复用现有 cookie 通道，不新建

`SESSDATA` / `bili_jct` / `DedeUserID` 三件套（`bilibili-tui/src/api/client.rs:136`）是 B 站登录态。
**uting 不需要自己管**：`--cookies-from-browser` 会从浏览器 profile 取，这条路已经存在且已按平台
做了存在性检查。

**护栏**：`CLAUDE.md` 的安全条款 —— **绝不记录 cookie 路径的内容或抽出的 token**。B 站的
`SESSDATA` 与 YouTube cookie 同级敏感，`players/<id>.json` 里一个字节都不能落。

### 3.6 为什么不自己解流（"原生"到底"原生"到哪一层）：`bilibili-tui` 的账单

如果连解流也走原生，代价是可量的（2026-08-22 抓取）：

| 文件 | 行数 | 做什么 |
|---|---:|---|
| `src/api/cdn.rs` | 707 | DASH 选流（`dash.audio` + `dolby` + `flac` 三源合并，按 `bandwidth` 取最大）、**多 CDN 主机测速排名**（`rank_urls`/`record_rank`，按吞吐/带宽算分） |
| `src/api/client.rs` | 1638 | cookie 三件套、`buvid3` 获取、nav 取 WBI key |
| `src/api/wbi.rs` | 129 | 签名 |

**约 2500 行只为把一条音频流放出来**，而 mpv 的 ytdl_hook 一行 `--ytdl-format` 做完同一件事、还免费
带 Referer。对照 `ROADMAP.md` §7 发现 1 的措辞：这属于"重写会**删掉**、而不是搬迁"的那类代码。

**第三方旁证**：`cliamp`（Go，3403★）有 11 个原生 provider（netease / qobuz / spotify / jellyfin /
plex / …）和一套完整的 provider 框架，**但 Bilibili 不在其中** —— 它的 `docs/yt-dlp.md` 把
YouTube / SoundCloud / NetEase / Bandcamp / Bilibili 归成同一类，走通用 yt-dlp 管线。一个有能力做
原生的项目选择不做，是对这笔账最有力的外部确认。

### 3.7 内容形态：一条搜索结果 ≠ 一个可播对象

`bilibili.py` 为 B 站拆了 **28 个 extractor 类**。音乐场景要认三种：

| 形态 | 标识 | 后果 |
|---|---|---|
| **分P（多集）** | `?p=N`，yt-dlp 生成 `_old_archive_ids: ['bilibili <aid>_part1']` | 一个 BV 里几十个 part。"播放第一条结果"要先决定放哪一 part |
| **合集 / 系列** | `BilibiliCollectionListIE` / `BilibiliSeriesListIE` | **这是产品问题**：实测搜"周杰伦"，前三条全是"50首精选合集""100首合集""最热门100首"，时长 222/271/419 分钟 |
| **音频区（au 号）** | `BilibiliAudioIE`，`/audio/au<id>` | B 站真正的**音乐区**：原生音频、带 `lyric`、有 `statistic`。与视频区是两套 API |

关于合集：**B 站音乐搜索的头部天然是长合集**，因为那是平台上音乐消费的主流形态。这不是 bug，
但一个"搜到 → 放上"的播放器如果第一条就丢给用户 3.7 小时的连播，体验是坏的。可选策略（属 `PLAN-`）：
按 `duration` 阈值标注、把合集单列一栏、或在焦点卡上显示"合集"标记。**至少要标出来**。

**音频区的顺带收益**：`BilibiliAudioIE` 把 `song.lyric` 作为 **subtitles** 暴露 —— 与 uting
2026-08-22 落地的 `--transcript` 是同一条管线。**歌词可以免费复用字幕路径，不需要新原语。**

### 3.8 WBI 签名：什么时候才真的需要

搜索**不需要**（§1.2 实测）。带 `wbi` 路径段的端点需要（`/x/player/wbi/playurl`、
`/x/web-interface/wbi/view/detail`、`/x/space/wbi/arc/search`）—— 也就是**只有走 B 路径才会遇到**。
社区权威说明：`socialsisteryi.github.io/bilibili-API-collect/docs/misc/sign/wbi.html`。

算法（yt-dlp 与 bilibili-tui 逐字节一致）：

```
1) GET https://api.bilibili.com/x/web-interface/nav
   lookup = basename(data.wbi_img.img_url) + basename(data.wbi_img.sub_url)   # 64 字符，去扩展名
2) mixin_key = ''.join(lookup[i] for i in MIXIN_KEY_ENC_TAB)[:32]             # 固定 64 项置换表
3) params 加 wts=<epoch>，按 key 排序，值里**删除**（不是转义）字符 !'()* ，urlencode
4) w_rid = md5(query_string + mixin_key)
```

**bash 3.2 可行性**：md5 有 `openssl dgst -md5`，排序有 `sort`，urlencode 可用 `jq -rR @uri`，
置换表用数组。**可实现但不轻松**，而按 §3.1 的方案根本用不到。**记录在此仅为将来 B 路径留档。**

**护栏（若将来真要写）**：`bilibili-tui/src/api/wbi.rs` 为它写了**带官方样例的固定向量单元测试**
（`mixin_key` 与 `w_rid` 各一条）。签名是纯函数、无网络 —— 这是这类代码唯一正确的测法，也是本仓
「rigs 必须驱动真实界面」规则的合法例外：它测的不是渲染或协议，是一个确定性变换。

### 3.9 风控、缓存与速率

- **风控**：`code: -412` 是 B 站的限流/风控信号（HTTP 仍是 200）。**未实测触发条件**。
- **缓存**：WBI key 会轮换，yt-dlp 有 `_wbi_key_cache` + `_WBI_KEY_CACHE_TIMEOUT`。若走 B 路径必须缓存。
  搜索路径无 key 可缓存，但 `buvid3` **应当在一次进程内复用**，不要每次搜索都换一个新 uuid。
- **地域**：本轮实测只有一个出口 IP。B 站有地域策略，海外 IP 下的行为**未测**。

**护栏**：uting 是 agent 优先的。一个会被风控的引擎意味着 agent 会拿到一个**可重试但当前失败**的
结果 —— 必须落在 `network` 这一类，而不是 `unknown`（调用方唯一无法据以行动的那个值）。

### 3.10 调用链：`-s bilibili` 相对现有系统的**增量**

> 现有系统的调用栈（三条形态、七个 yt-dlp 调用点、两处进程边界）已记入
> **`SPEC-system.md` §6.1**，含 ASCII 图。本节只记 B 站带来的**差异**，不重复那张图。

**差异一：搜索这一格的 yt-dlp 调用从 1 次变成 0 次。**
`fetch_results` 的 B 站分支走 curl + jq，`SPEC §6.1` 的调用点 #1 在该分支下不发生。
顺带绕开 yt-dlp 在 B 站上唯一坏掉的那条路（搜索的 412，§2.7）。

**差异二：其余六个调用点一个都不变，且都不会踩 412。**
#2–#7 收到的都是一条 B 站 URL，走 `BiliBiliIE(BilibiliBaseIE)`，自带
`_HEADERS = {'Referer': …}`。**412 只存在于 `BiliBiliSearchIE`**，因为只有它不继承那个基类。

**差异三（要修的）：两个"YouTube 形状"会被新引擎白白继承。**

| `SPEC §6.1` 的调用点 | 在 B 站上有必要吗 |
|---|---|
| #6 / #6' `probe_media_fetchable` | ❌ 它是 **googlevideo / GVS Proof-of-Origin token** 的补丁（`shell/yt` 顶部注释写明）。B 站没有 googlevideo、没有 PO token，`SESSDATA` 也不会让公开视频 403 —— 它只提升音质。更露骨的是无 cookie 时它硬塞 `--extractor-args "youtube:player_client=android"`，对 B 站 URL 是纯噪音 |
| #5 `detach_title_updater` | ❌ 它存在是因为 detach 时 core 手上只有 URL。而 B 站搜索**已经返回了 title** —— 让 `-d` 能接收已知标题即可整个省掉 |
| #7 `ytdl_hook` 那次 | ✅ **唯一真正解流的** |

**为什么这不只是效率问题**：每轮 yt-dlp 抽取内部还有数个 HTTP 请求（view/detail +
player/wbi/v2 + playurl，**这个乘数是推断，未实测**），而 §2.7 实测**约 15 次请求即触发风控**。
理想情况下 `-s bilibili` 的一次播放只该有 **1 次** yt-dlp。对应 P7 / P8。

---

## 4. 工程护栏：`cliamp` 的能力接口模型

上一轮讨论里"每个音源字段不齐"曾被当成"要写一份 per-source 字段降级策略表"。
`cliamp` 的 `docs/provider-development.md` 给了更好的模型：**必需接口极小 + 一组可选能力接口，
UI 用类型断言在运行时发现能力**。

```go
type Provider interface {          // 必需，只有三个方法
    Name() string
    Playlists() ([]playlist.PlaylistInfo, error)
    Tracks(playlistID string) ([]Track, error)
}
```

可选能力（节选）：`Searcher`、`AlbumBrowser`、`AlbumTrackLoader`、`PlaybackReporter`、
`ProgressReporter`、`CustomStreamer`、`Authenticator`、`FavoriteToggler`、`BrowseLabeler`、`Closer`。
外加**编译期断言**，缺哪个能力构建时就知道：

```go
var _ provider.Searcher = (*Provider)(nil)
```

**对 uting 的意义**：不写策略表，把差异建模成**能力声明**。B 站搜索有播放量但没有精确秒数、
YT Music 两个都没有 —— 与其在渲染层写 `if source == …`，不如让引擎在 envelope 里声明自己能提供什么，
让列表层按能力决定画不画那一列。这与「correctness 加在 core，让所有界面继承」是同一条原则。

Go 的类型断言在 bash 里没有对应物；等价物是**在 envelope 里放一个 capabilities 声明，或让缺失字段
为 `null` 并定义清楚语义**。**具体选哪个属于 `PLAN-`，不在本文范围。**

---

## 5. 落地顺序建议（套用 `CLAUDE.md` 的 A→E）

destructive 的一步放最后、最小，且先证明替代路径存在：

```
  A  先修 --get-url 的 header 契约（§3.4）。它与 B 站无关、独立可验，
     且是 B 站接入的前置条件 —— 不修就是接一个即刻半残的引擎。
  B  在 fetch_results 内部加 bilibili 分支，走 yt-dlp bilisearch，产出与 YouTube 逐字段同构的
     envelope。过渡态：先接受 N+1 次完整抽取（慢但正确），不碰播放、不碰 TUI。
     用 -j 的单行 envelope 做 headless 回归。
  B' 并行：向 yt-dlp 提 patch，让 BiliBiliSearchIE 对齐 SoundcloudSearchIE 的元数据透传（§2.6）。
     合并并进入 release 后，B 步的 N+1 自动塌成 1 次，uting 侧一行都不用改。
  C  接 -s/--source flag，让 yt-search / yt-tui 能选源。播放路径不改一行（§3.3）。
  D  时长第三种拼法、HTML 剥离、万/亿格式化 —— 全加在 core，不加在 yt-tui。
  E  文档同步（SPEC-system.md 的契约与函数图、README、usage()），
     再跑一次 verify-suite，phase 4 audible 必须真放一次 B 站的音频。
```

**每一步都可停**。A 单独有价值（修的是通用缺陷），B 单独可验（headless），C 之后才有用户可见变化。

---

## 6. 待蒸馏

### 6.1 进 `ROADMAP.md`（已决定）

| # | 条目 |
|---|---|
| R1 | **第二引擎确认为 Bilibili。** YT Music 归为 YouTube 引擎的检索面改进，独立排期；Bandcamp/播客 URL-only 已可用，不需要接；网易云/QQ音乐/Spotify系/Niconico 排除（理由见本文 §0）；SoundCloud 排除（产品决策：内容面不重合） |
| R2 | **`--get-url` 的 envelope 缺 per-stream header** —— 实测：B 站裸 URL 无 Referer 403 / 有 206。**契约缺陷**，通用（任何校 Referer 的站），YouTube 不校验故未暴露。**是 B 站接入的前置条件**。与 `a967dc0` 刚关闭的可观测性缺口同类同级，应接在其后 |
| R3 | **B 站搜索走 yt-dlp，不直连 B 站 API。** 初稿的直连推荐已撤回：2026-01 B 站律师函致使 `bilibili-API-collect`（20.2k★）与 `Nemo2011/bilibili-api`（4.2k★）双双归档，直连意味着把被点名的调用逻辑/认证机制固化进本仓、且无上游可跟。成本问题改由**向 yt-dlp 提 patch**解决（`BiliBiliSearchIE` 对齐 `SoundcloudSearchIE` 的元数据透传） |
| R4 | **B 站播放不走原生**（mpv ytdl_hook 免费拿 Referer + 登录音质；`bilibili-tui` 为此付约 2500 行；`cliamp` 有原生框架却选择不做，是旁证） |
| R5 | B 站**音频区 `/audio/au<id>` 的 `lyric` 走 yt-dlp 的 subtitles 通道** —— 与 `--transcript` 同管线，歌词免费复用，不需要新原语 |
| R6 | 引擎 seam 切在**操作**（search/resolve/play/info）而非**站点**（provider）—— uting 的 core 已是这个形状 |

### 6.2 进 `PLAN-`（可施工时展开）

| # | 待定的实现细节 |
|---|---|
| P1 | `--get-url` header 的 envelope 形状三选一（§3.4） |
| P2 | `-s/--source` 的 flag 名、缺省值、与 `yt-search`/`yt-play` 现有互斥 flag 的关系 |
| P3 | 差异建模：capabilities 声明 vs 字段为 `null` 并定义语义（§4） |
| P4 | 合集/长视频的产品策略：阈值标注 / 单列一栏 / 焦点卡标记（§3.7） |
| P5 | `"MM:SS"`（分钟无上限）接入 core 的时长格式化 |
| P6 | `buvid3` 的生命周期：进程内复用的具体位置 |
| P7 | **`-s bilibili` 下跳过 `probe_media_fetchable`** —— 它是 googlevideo / PO-token 的补丁，B 站无此问题（§3.10） |
| P8 | **给 `-d` 加"标题已知"入口**，跳过 `detach_title_updater` 那次 yt-dlp。搜索已经给了 title；YouTube 侧同样受益，只是那边不卡风控（§3.10） |
| P9 | 命名与入口：**不新开 `bili` / `yt-bili` 命令，用 `-s/--source` flag**（依据：per-request 用 flag、一个命令一个名字、生命周期与音源无关、壳按动词切不按站切；先例 `yt-dlp` 支持 1752 站仍叫 yt-dlp）。取值用规范名 `bilibili`；`yt-play` 无需改动，URL 自证音源 |

---

## 7. 局限

- **设计部分零实现**。见 §0.5 —— §3 是方案，不是代码；uting 自己的入口对 B 站一次都没跑过。
- **单点实测**。所有 HTTP 结果来自一个出口 IP、一个时刻。B 站有地域策略与风控（`-412`），
  换网络环境结论可能变。
- **未测的部分**：搜索第 2 页及以后；登录态（`SESSDATA`）；风控触发条件；海外 IP 行为；
  造 `buvid3` 与向服务端要 `buvid3` 的风控强度差异。
- **未实际放出声音**。本文证明了"URL 能取到、带 header 能连"，以及 ytdl_hook 的转发逻辑
  （`set_http_headers`，§3.3.2 已读源码，不再是推断），但**没有跑通一次真实播放**。
  端到端仍需 `verify-suite` phase 4（audible）确认 —— 这是 §5 的 E 步不可省的原因。
- **只读了两个第三方实现**（`cliamp`、`bilibili-tui`）。`termusic` 的 NetEase/Migu/KuGou provider、
  `go-musicfox` 的 UnblockNeteaseMusic 未读。
- **`cliamp` 的 provider 框架是 Go 的类型系统在撑**。搬到 bash 3.2 需要一个完全不同的等价物，
  本文只指出方向，未证明可行。
