# PLAN-engine-xmly —— 第三对引擎：喜马拉雅

> **状态**：**Gate 0 已跑，未通过 —— 本 plan 按 §3 原文停**（2026-08-28）。
> 一份真登录的 24 条 cookie jar 过不了风控：`www` 侧与匿名逐字同答 `riskLevel:5`，
> `m` 侧认了登录却卡在 `webtk缺失`，而 `webtk` **不是 cookie**（§3.1 的判别输入）。
> 拦路的东西住在 cookie jar 之外，`XMLY_COOKIE_BROWSER` 这个机制**够不到它**。
> **第三对引擎的工作到此暂停**（2026-08-28，用户裁定）—— 不是改做网易云，是先不做第三对。
> 本文件**保留**：它装着 §2.2 那批实测、§3.1 的判别输入，以及重开条件。
> 恢复时的建议起点是 §9 第 1 项（网易云），理由见 §3.1；那不是已定的事。
> 前置一，`PLAN-search-row.md` 的 A 半：已落地（行带 `kind`/`access`），与本裁定无关，照常有效。
> §2.1 的 a/b/d 已补齐（§2.2），c 的 +1h 复测未做且现已无关紧要。
> **实现的 ROADMAP 条目**：**D20**（第三对引擎选喜马拉雅）· **D19**（引擎按 site 切不按 stack 切 —— 本引擎是它的第一个实例）。
> **冷读预演已做**（2026-08-28，见 §8）：11 条 finding，全部接受，已编入正文。
> **落地即删**：内容按 `CLAUDE.md` 的规矩拆进 `AS-BUILT-engine.md` / `AS-BUILT-contract.md`，本文件删除。

---

## 1. 为什么是这一对，以及它证明什么

加它不只是"多一个音源"。它是套件里**第一个 `X-resolve` 不以 yt-dlp 为主路径的引擎** ——
免费条目由站点自己给直链，`curl` + `jq` 就够。`bili-search` 已经证明了 search 半边可以不用
yt-dlp；这一对补上 resolve 半边，于是"**seam 是 envelope，不是背后那个工具**"（D11）在两个
半边上都有实例，而不再只是一句写下来的原则。

它同时是 **D19 的第一个实例**：一个 source 内部同时用两条 stack（免费 curl / VIP yt-dlp），
这正是"按 stack 切 resolver"会被撕成两个文件、而按 site 切只是一个 `if` 的那个案例。

**它的两个"第一次"要如实认领**（冷读修正）：它是套件里**第一个搜索半边送凭据的引擎**，
且那不是 `yt-search` 模式的"第二例" —— `yt-search` 的 cookie 决定只有一行，因为解密浏览器
cookie store 的是 yt-dlp；curl 做不了这件事，所以本引擎要自带取 cookie 的机制（§4.2）。

---

## 2. 已验证的事实（2026-08-28 实测，本机，无凭据，yt-dlp 2026.08.19）

**每一条都是跑出来的，不是读文档得出的。** 开工前重跑一遍 —— 站点会变。

| 面 | 端点 / 命令 | 结果 |
|---|---|---|
| 单条音频（**能用**） | `curl -s https://m.ximalaya.com/tracks/47740352.json` | 明文 JSON：`title` / `duration` / `is_paid` / **`play_path_64`、`play_path_32` 直链** |
| 直链可取性 | `curl -r 0-2000 <play_path_64>` | **HTTP 206**，真字节 |
| 速度对比 | 同一条 sound | **curl+jq 305ms** vs **yt-dlp 1082ms**（3.5×） |
| 专辑曲目表 | `revision/album/v1/getTracksList` | `ret:401 用户未登录` |
| 搜索（web） | `revision/search/main` | 风控：`{"reason":"risk invalid","riskLevel":5}` |
| 搜索（mobile） | `m-revision/page/search` | `{"ret":303,"needLogin":true,"loginUrl":"…/passport/login"}` |
| 搜索（其他） | `revision/search/all` · `mobwsa/search/v3` · `openapi-search/v1` | 404，端点不存在 |
| 绕风控尝试一 | 先取首页 cookie（华为 WAF `HWWAFSESID`）再搜 | 仍 `riskLevel:5` |
| 绕风控尝试二 | 补 `xm-sign`（`revision/time` + `md5("himalaya-"+ts)` 那套） | 仍 `riskLevel:5` |

### 2.1 尚未量、开工前**必须**补齐的行（冷读补：这些今天是空格，不是事实）

| # | 要量什么 | 为什么 |
|---|---|---|
| a | **VIP 分支实跑**：`yt-dlp -g` 一个真 `is_paid:true` 的 sound（Gate 0b，§3） | §2 原版那行"yt-dlp 已实现并维护"是**读源码**得出的 —— 正是本仓明令要标注的证据强度。mpay/RC4 那套若已 bitrot 或需要 VIP 账号，D19 的展示件当天就塌一半 |
| b | **真实 URL 形状**：从网页地址栏、分享按钮、m 站各拷一条 sound 的 URL，逐字记录 | §4.4 的 handle 表今天是**推断**的；该站历史上有 `/{分类或专辑}/sound/<id>` 形状，表若比现实窄，用户贴自己浏览器的 URL 会被退 1 |
| c | **`play_path_64` 的 TTL**：取到直链一小时后重新 `curl -r 0-2000` 同一条 | 206 探测是在取到后几秒做的。若直链带签名 TTL，暂停几小时的播放器 mpv 重连会死在半场 —— 队列的 just-in-time resolve 保护的是**开播**，不是重连 |
| d | **tracks 端点自身的风控**：Gate 0 的 burst（§3 第 3 段）同时打 `tracks/<id>.json` 十次 | Gate 0 原版只测了搜索端点；resolve 主路径挂上同一个 WAF 时的行为要归进错误词汇（§4.3） |

### 2.2 §2.1 的执行记录（2026-08-28 第二轮，本机，无凭据，yt-dlp 2026.08.19）

**基线先复现了 §2**：匿名 `revision/search/main` 仍 `riskLevel:5`；
`m.ximalaya.com/tracks/47740352.json` 仍明文，`is_paid:false`，双直链在场。

| # | 结果 | 对本 plan 的作用 |
|---|---|---|
| a | **Gate 0b 已跑 → 红，但 extractor 没有腐。** 匿名 `yt-dlp -g` 打一条真 `is_paid:true` 的 sound（`700000000`，`is_free:false`，三个 `play_path_*` 全空）→ `ERROR: An extractor error has occurred. (caused by KeyError('fileId'))`，**崩，不是一句干净的拒绝**。判别输入分开了两种解释：同一个 yt-dlp 匿名解**免费** sound 两条（`47740352` → `group31/…m4a`、`620000000` → `storages/…aac`）**都成功** —— 所以 mpay/RC4 那条路没 bitrot，红的是"付费 + 无权益"。**VIP 账号下能不能通,本机量不了**（无任何 ximalaya 登录），这一格仍是空的 | **D19 的展示件塌了一半**：`is_paid:true` 分支今天交付不了"yt-dlp 兜住 VIP"。裁定见 §3 |
| b | **URL 形状实测收窄，且站点自己已经改口。** 该 sound 页面的 `rel="canonical"` 就是 `https://www.ximalaya.com/sound/47740352` —— 站点今天的规范形状。yt-dlp 只吃 `/sound/<id>`（`www` / `m` / 带尾斜杠都行）；`/{分类}/{专辑}/{曲目}` 那个历史形状是 `Unsupported URL`；`/album/<aid>/sound/<id>` 更糟 —— yt-dlp 把**专辑 id** 当成目标去解，崩在同一个 `KeyError` 上 | §4.4 的 handle 表**不是变窄，是多了一项工作**：历史形状与 `/album/…/sound/…` 必须由本引擎**自己归一化成 `/sound/<id>`** 再交给 yt-dlp。句柄文法是引擎的活（`AS-BUILT-contract.md` §1.3），所以这是本引擎的工，不是缺陷 |
| c | **未完。** 直链已捕获、`t0` 已记（`tmp/` 下，2026-08-28 14:42:20），**t+1h 的复测还没做**。已知的半边：`play_path_64` **不带任何查询串** —— 无签名、无 expiry 参数，且它与同一条 sound 的 `yt-dlp -g` 输出**是逐字同一条 URL**。t=0 的 ranged GET **206 / 2001 字节** | 无签名让"直链带 TTL"变得不像，但**那是假设不是测量** —— 这一格在 +1h 复测落下之前不许当成事实。curl 路径与 yt-dlp 路径同一条 URL，则把 §4.3 的"永远先走 curl"从一次取舍变成了纯粹的提速：**同一个答案，快 3 倍**（本轮复测 curl 347ms vs yt-dlp 1059ms，§2 那组 305/1082 复现） |
| d | **绿。** 无凭据连打 `tracks/<id>.json` 十次，**10/10 作答，4 秒**，零风控 | resolve 的主路径**不挂在**搜索那个 WAF 上。§4.3 的错误词汇表因此不需要为 resolve 侧的 `riskLevel` 准备一支；顺带测到另一种拒答形状 `{"res":false,…,"needLogin":…}`（下架/不可达），那一支要进表 |

**顺带落到手里的两条事实**（不在 §2.1 的清单上，但改设计）：

- **`is_paid:false` 并不蕴含直链在场。** `480000000` 是 `is_paid:false` 而 `play_path_64` 为空。
  §4.3 的分叉判据写的是 `is_paid:false` **且** `play_path_64` 非空 —— 两个条件，
  现在这条"免费但没有直链"的实例证明了第二个条件不是多余的。
- **`access` 的判据在 resolve 侧现成，在 search 侧仍未知。** `is_paid` 就在 `tracks/<id>.json` 里，
  但 `kind`/`access` 是**行**上的必填字段，而行来自搜索 —— 搜索今天被风控挡着，
  所以"搜索响应里有没有 `is_paid` 同类字段"在 Gate 0 通过之前**量不了**。

---

## 3. Gate 0 —— 开工的门（三段式 + Gate 0b；**已跑，未通过**，见 §3.1）

> **一个真登录 cookie 能不能过 `riskLevel:5`？—— 且过的是不是"登录"？**

不能，则本 plan **停**：引擎 = 两个动词（D9），只有 resolve 没有 search 的东西不是引擎。
退路记在 §9。

**cookie 的取用与卫生**（这段先于命令，因为原版的命令本身就违反了仓规）：
浏览器 cookie 用 `yt-dlp --cookies-from-browser chrome --cookies tmp/xmly-jar.txt` 导出
（yt-dlp 是本仓已有依赖，且是唯一会解 Keychain 的），jar 落在 `tmp/`（gitignored）、
`chmod 600`、验证完即删。**cookie 永不出现在 shell 命令行的字符串里** ——
历史文件也是 `ps` 之外的另一条泄漏路（`CLAUDE.md`："Never log a cookie path's contents
or an extracted token"）。

三段，都要留下 §2 格式的执行记录：

1. **判别对**：带 jar（`curl -b tmp/xmly-jar.txt …`）打 `revision/search/main` → 若回
   `result` 数组则绿；**随后同一命令去掉 `-b` 再跑**，确认仍 `riskLevel:5` ——
   否则证明的是"端点又通了"，不是 jar 起了作用。
2. **二分**（冷读补）：jar 里同时有**会话凭据**（登录 token）和**设备指纹** cookie
   （`HWWAFSESID` 一族）。各留一半重放：若**设备半**就够 —— 机制要如实改名
   （那不是登录决定，`XMLY_COOKIE_BROWSER` 的语义要重想），且要预期设备 cookie
   随浏览器轮换、导出的 jar **几天就腐** —— 落地当周能用、之后静默衰减，是这条分支的
   预期事故形状。
3. **burst**（冷读补）：同一 jar 60 秒内 10 次搜索 + 10 次 `tracks/<id>.json`，全绿才算过。
   一次通过只是对一个**自适应**控制器的点采样；contract.sh 的调用节奏就是这个形状。

### 3.1 执行记录（2026-08-28）—— **Gate 0 未通过**

> **门问的那句话有了答案：一个真登录 cookie 过不了 `riskLevel:5`。过不了的原因不是登录无效，
> 而是拦路的东西根本不是 cookie。**

**取凭据**：按 §3 的卫生规矩，`yt-dlp --cookies-from-browser chrome --cookies <jar>` 导出，
`umask 077`、滤到 ximalaya 域、全量 jar 当场销毁，cookie 只经 `-b <jar文件>` 到 curl，
从未进过 argv。**验证完两份 jar 都已销毁。**

第一次导出得 **11 条**（登录后、尚未在站内搜索过）：会话半 `1&_token` / `1&remember_me` /
`1_l_flag`（外加 passport 域的 `s&e` / `s&a`），设备半 `HWWAFSESID` / `HWWAFSESTIME` /
`x_xmly_traffic` / `_xmLog` / `impl` / `trackType`。
随后在 Chrome 里**真的执行了一次站内搜索**并重导，得 **24 条** —— 多出 13 条,含 `web_login`、
`crystal`、`wfp`、`assva5` / `assva6` / `cmci9xde` / `pmck9xge` / `vmce9xdq` / `DATE`
（华为 WAF 那族动态令牌）与百度统计的 `Hm_*`。

**第 1 段·判别对 —— 红，且两个端点红得不一样。**

| 端点 | 带 24 条 jar | 不带 jar（对照） | 读法 |
|---|---|---|---|
| `www` `revision/search/main` | `{"ret":200,…,"riskLevel":5}` | **逐字相同** | 登录在这里**什么也没买到**。对照证明的不是"端点又通了"，而是 jar 对它完全无效 |
| `m` `m-revision/page/search` | `{"ret":0,…,"isIllegal":true,"sq":"webtk缺失"}`，三个结果数组全空 | `{"ret":303,"needLogin":true}` | 登录**被认了**（不再要求登录），但搜索仍被拒，理由换成了缺 `webtk` |

`m` 侧那对是本次最有信息量的一格：它把"登录无效"从嫌疑里排除掉了 —— jar 确实改变了答案。
（`-v` 核对过 9 条 cookie 真的上了 `Cookie:` 头；passport 域那 2 条不适用于 `www`/`m`，符合预期。）

**`webtk` 不是 cookie —— 这是本次的判别输入，也是判死本 plan 的那一条。**
在 Chrome 里真搜过一次之后重导，24 条里**没有任何一条叫 `webtk`**；
`m` 的搜索页只有 7200 字节的壳，`webtk` 字样不在页面里，
两个 JS bundle 里也搜不到（`dws2.0.0.js` 直取回 0 字节）。
结论：它是**每请求现算的令牌**，住在 cookie jar 之外。
于是 §4.2 设想的整套机制 —— "`XMLY_COOKIE_BROWSER` 指浏览器 → yt-dlp 当解密器导 jar →
curl `-b` 送出" —— **在原理上就够不到它**。不是这次没配好，是这条路不通。

参数形状也排查过了，空结果不是参数写错：`core=all|track|album`、`+device=iPhone`、
`+condition=relation`、以及一个纯 ASCII 查询，八种组合全部 `ret:0` + `isIllegal:true` + 零结果；
去掉 `core` 或把 `kw` 换成 `keyword` 则连 JSON 都不成形。

**裁定：按 §3 原文，本 plan 停。**
门的原话是"不能，则本 plan **停**：引擎 = 两个动词（D9），只有 resolve 没有 search 的东西不是引擎"。
resolve 半边其实**很健康**（§2.2：免费条目 curl 305→347ms 直出、10/10 无风控、
与 yt-dlp 同一条直链），但那恰恰是 D9 明令不算数的那一半。

**不采取的两条路，以及为什么**：
- **实现 `webtk`**：那是把一个混淆过的反爬 bundle 逆向进 bash。它违反本仓"引擎只做薄薄一层"的
  取向，且反爬令牌是持续腐化的东西 —— §2 记的 `xm-sign` 尝试已经是同一类努力失败过一次。
- **只做 `xmly-resolve`**：§9 第 2 项已经答过，不行。

**建议的下一步：§9 第 1 项，第三对引擎改用网易云。**
它在 §9 里是量过的：搜索端点明文、公开、**零凭据**，形状与 B 站完全一致，零新机制；
且 `fee` 就在搜索响应里，`access:"preview"` 的判据现成 —— 那正是本 plan 拿 `is_paid` 想做、
却因为搜索半边不通而**在 search 侧始终没量到**的那件事（§2.2 末条）。
**代价要如实认领**：它证明不了 D19（一个 source 两条 stack）。
D19 需要另找展示件，或者接受它暂时只是一条写下来的原则。

**重开条件**（§9 第 3 项）：站点风控会变。重跑的入口是本节第 1 段那张两行表 ——
`m` 侧一旦不再答 `webtk缺失`，这道门就值得重走一遍。记下日期：**2026-08-28**。

**Gate 0b（冷读补，独立于搜索）**：无凭据 `yt-dlp -g 'https://www.ximalaya.com/sound/<真 is_paid:true id>'`。
逐字记录结果进 §2.1a。失败则**当场二选一并写进 §4.3**：paid 条目的契约答案是
`{status:"error", reason:"forbidden"}`（引擎如实说"匿名解不了"），或 Gate 0b 与 Gate 0
并列为停止条件。§7 的建造顺序在两个 Gate 都有执行记录之前不开始。

---

## 4. 设计

### 4.1 命名（D10）

`xmly-search` / `xmly-resolve`。**落选**：`ximalaya-*`（命令前缀过长，且与另外两个 2–4 字母的
站名前缀不成一族）、`xima`（站点自己不这么缩写）。`XMLY` 是该站通行缩写。

### 4.2 `xmly-search` —— 第一个搜索半边带凭据的引擎（**不是** yt-search 的第二例）

- transport：`curl` + `jq`，信封形状与 `bili-search` 同。
- **cookie 机制是本引擎自己的，且是一个此前不存在的机制**（冷读修正）：
  `XMLY_COOKIE_BROWSER` 指的浏览器 profile 由 **yt-dlp 充当解密器** ——
  每次调用 `yt-dlp --cookies-from-browser "$XMLY_COOKIE_BROWSER" --cookies <jar>` 导出、
  jq/grep 滤到 `ximalaya.com` 域、jar 放进进程私有 `mktemp -d`、`chmod 600`、
  与 transport 同一个 trap 里删除。**代价如实记**：search 半边因此
  `require_deps yt-dlp curl jq`（usage 与 `AS-BUILT-engine.md` §7 都要写），
  且每次搜索多付一次 Keychain 解密的延迟 —— 这笔账是 Gate 0 之后要实测的。
- **transport 硬规矩**（冷读补，事故级）：cookie 到 curl **只**经 `-b <jar文件>` ——
  永不作为 argv 字符串、永不 `-H "Cookie: …"`。`bili-search` 那个 argv 头由
  "buvid3 是设备号而非凭据"担保（其源码注释原话），**担保不迁移到这里**。
  这是契约 §3 禁止凭据头进 `http_headers` 的同一威胁模型（`ps` 可读 argv），提前一个进程适用。
- 输出：`AS-BUILT-contract.md` §3 的搜索 envelope + `PLAN-search-row.md` 的 `kind`/`access`。
- **风控拒答归进封闭 reason 枚举**（冷读补）：搜索被 `riskLevel` 拒 → `network`（可重试），
  与 `bili-search` 把风控券判 `network` 同一先例 —— 于是套件中途一次风控红是**被分类的红**。
- `auth` 语义与 D16 一致（报 cookie 决定，不做登录裁决），但**本引擎的特殊之处写进 usage**：
  这里 `auth=none` 意味着搜索**会失败**（站点要登录态），是套件里唯一一处 cookie 决定与
  "能不能用"直接挂钩的引擎。Gate 0 第 2 段若判出"设备半就够"，本段语义随之重写。

### 4.3 `xmly-resolve` —— 两条 stack，一个文件（D19 的实例）

```
  handle → m.ximalaya.com/tracks/<id>.json   (curl，305ms，永远先走这条)
             │
             ├── is_paid:false 且 play_path_64 非空 → emit_stream        ← curl 路径
             ├── is_paid:true                        → yt-dlp（mpay+RC4） ← yt-dlp 路径
             └── tracks 端点被风控拒                  → 回落 yt-dlp（它也解免费条目），
                                                       仍失败才报错
```

- **`is_paid` 是分叉判据，不是猜测** —— 就在第一次 curl 的响应里，不多一次往返。
- 两条路径回同一**形状**的 resolve envelope。**"调用方看不出走了哪条"原句删除**（冷读修正：
  它与验收第 4 条直接矛盾）——正确的说法是**同形状、同键集；值如实**：
  - **`format`**：curl 路径填 `"play_path_64"` —— 如实、不透明，播放器照录不读
    （契约 §3 本来就定义它为"引擎实际用掉的那个"，不限定是 yt-dlp 表达式）；
    yt-dlp 路径与 `bili-resolve` 同义。**这个值同时就是验收第 4 条的观测点。**
  - **`retried`**：恒 `false`（本引擎无匿名回落一说），且**永不复用**来表达 stack 回落。
- **curl 路径的错误词汇**（冷读补 —— 没有这张表，一条下架的免费曲会发出畸形的"成功"）：

  | 情形 | reason（封闭枚举，不新增成员） |
  |---|---|
  | curl rc≠0 | `network` |
  | HTTP 404 / 响应 `ret`≠0 | `unavailable` |
  | 风控拒答（回落 yt-dlp 后仍败） | `network` |
  | `is_paid:false` 但 `play_path_64` 空/null（下架、区域锁） | `unavailable` |

- `http_headers`：直链实测 206 不需要 Referer，但仍按站点事实填，**绝不放 Cookie/Authorization**。
- **`--transcript` 不做**（站点无字幕，动词的有无声明能力）。`--info` 做。`--auth` 做。

### 4.4 handle 语法与 host 白名单（D12）

表**从 §2.1b 的三条实测 URL 导出**，不从推断导出（冷读修正）。起点假设（待 §2.1b 校正）：

| 收 | 例 |
|---|---|
| `https://www.ximalaya.com/…/sound/<id>` | 网页 URL（路径中段按实测放宽） |
| `https://m.ximalaya.com/sound/<id>` | 移动 URL |
| `sound/<id>` · 裸 `<id>` | 短 handle |

白名单：`ximalaya.com` / `www.ximalaya.com` / `m.ximalaya.com`。别站 URL 一律退 1。
**`xmcdn.com` 刻意不进白名单**（冷读补）：它是流的 host，不是 handle 的 host ——
白名单把的是 handle 门；将来谁想"顺手"接受贴来的流 URL，这句话就是挡它的。

**`album/<id>` 第一版不收** —— 与 B 站合集是同一个问题（ROADMAP §11 第一条），一起解。

### 4.5 mode → format 表 —— 五个模式全表（冷读修正：原版只裁了 video 一个）

`-f` 的枚举是 `audio | video | fast | ascii | viz`（契约 §6），纯音频站上五行同答：

| mode | 行为 |
|---|---|
| audio / video / fast / ascii / viz | 全部走音频路径；`mode` 回显调用方的词，`format` 说实话（§4.3） |

一句话定语义：**`mode` 是调用方说的，`format` 是引擎做的** —— 与契约 §3 的分工一致。
`ascii` 在无视频可渲染时播放器自然退到纯音频输出，这是播放器已有行为，引擎不用管。
**被否**：`-f video` 退 1 —— 播放器不认识站点，无从预判，会让切源的 `ut-play -f video` 无辜炸掉。

---

## 5. 会被改到的现有文件（`ut-play` 与 `uting` 各零行）

| 文件 | 改什么 |
|---|---|
| `config` | 加 `XMLY_COOKIE_BROWSER=chrome`（D18：出厂默认值声明在这里） |
| `docs/AS-BUILT-engine.md` | §7/§8.2/§10 加本站三段站点事实，含 §4.2 的 cookie 机制与依赖面 |
| `docs/AS-BUILT-contract.md` | §5 配置键清单；§6 加引擎清单按本次实际经历校正 |
| `docs/ROADMAP.md` | D20 状态；§11 album 条与合集条目合并处 |
| `README.md` | 三源；`## What it is` 的引擎段 |
| `VERSION` | 加法 → z 位，单独 commit（D13） |

`shell/ut-play`、`shell/uting`、另外两对引擎：**零行**。若中途发现必须改 —— 停下来看，
那是设计出了问题，不要顺手改。

---

## 6. 验证（`done_when` —— 逐条**执行**，不是读）

既有跨引擎不变量（host gate、envelope 形状、cookie 判别输入）对第三对引擎自动生效
（contract.sh 按发现到的引擎断言）—— 不为它们新写检查。

| # | 检查 | 归属 |
|---|---|---|
| 1 | `bash -n shell/xmly-*` | pre-commit |
| 2 | 既有跨引擎断言全绿（含 `XMLY_COOKIE_BROWSER=definitely-not-a-browser` → `anonymous`） | `contract.sh --offline` 自动 |
| 3 | `xmly-search -j -n 5 -- "唐诗"` → 5 条、字段齐。**门槛**（冷读修正）：仅当本引擎自己的 auth 判定为 `cookie` 且 `profile_found:true` 才跑，否则**具名跳过**并记进 `AS-BUILT-verification.md` §27 的未覆盖清单 —— 一台没有作者账号的机器不为账号的缺席变红。**每次全量跑至多一次搜索调用** —— 别拿真实账号去锤一个对陌生人答 riskLevel:5 的端点 | `contract.sh` live 半 |
| 4 | `xmly-resolve -j -- sound/47740352` → 直链可取（206），且信封 `format=="play_path_64"`（§4.3 的观测点 —— 不做时序断言） | `contract.sh` live 半 |
| 5 | **VIP 分叉**：一个真 `is_paid:true` 的 sound → 同形状 envelope、`format` 为 yt-dlp 语义 | live 半；无稳定 fixture 就如实记 §27 未覆盖，**不用替身变绿** |
| 6 | curl 路径错误词汇：一个不存在的 sound id → `{status:"error", reason:"unavailable"}` 退 2+ | live 半 |
| 7 | `ut-play -d --engine xmly -- <handle>` 真起播、真写 history 行 | `playback.sh` |
| 8 | TUI 发现第三对、列表能出、Enter 能播 | `drive.sh` |

---

## 7. 建造顺序（A→E，加面属结构性变更）

**前置**：Gate 0 三段 + Gate 0b 全部有 §2 格式的执行记录；`PLAN-search-row.md` A 半已落地。

- **A** 先 `xmly-resolve`，对着已有的 `ut-play --engine` 跑通。
- **B** 再 `xmly-search`；TUI 靠 glob 自动发现，不改它。
- **C** 无删除步骤（纯加法）。发现要改 `ut-play`/`uting` → 回 §5 最后一句。
- **D** 文档按 §5 的表 resync。
- **E** tmux 头戴一遍 + 无头两套。

---

## 8. 冷读预演 —— **已做**（2026-08-28）

按 `CLAUDE.md` 的规矩，plan 全文（不带作者会话）交给了冷读者写失败回顾。**11 条 finding，
全部接受**，已编入上文；无一拒绝。除 plan 自标的三处（Gate 0 判别性、VIP fixture、`-f video`）
外，冷读者找出了五处 plan 完全没标的，按伤害排序：

1. cookie 取用机制缺位（`XMLY_COOKIE_BROWSER` 原是没接线的旋钮）→ §4.2 重写
2. cookie 过 argv 的 `ps` 泄漏（含 Gate 0 原版命令自己就犯）→ §4.2 硬规矩 + §3 卫生段
3. VIP 分支从未实跑（"读源码得出"混进了"全是跑出来的"表）→ Gate 0b + §2.1a
4. contract.sh live 半被一个人的账号劫持 + 测试节奏烧账号 → 第 3 条门槛重写
5. "看不出走了哪条"与验收第 4 条自相矛盾 → `format` 如实分值，矛盾句删除
6. `format`/`retried` 在 curl 路径无定义 → §4.3 两句敲死
7. curl 路径无错误词汇（下架免费曲会发畸形成功）→ §4.3 错误表 + 风控回落
8. Gate 0 一次通过证明力不足 → 三段式（判别对 / 二分 / burst）
9. handle 表是推断的 → §2.1b 实测导出
10. mode 表只裁了五分之一 → §4.5 全表
11. `xmcdn.com` 白名单蠕变风险 + 直链 TTL 未量 → §4.4 一句 + §2.1c

---

## 9. Gate 0 不通过时的退路

1. **换网易云做第三对。** 实测（2026-08-28）：搜索 `music.163.com/api/cloudsearch/pc`
   **明文、公开、零凭据**（`code:200`，271 条，`{id,name,ar[],dt,fee}`）；解流必须 yt-dlp
   （明文 `song/enhance/player/url` 回 `url:null, code:404`），3585ms，与 `bili-resolve` 同档。
   **形状与 B 站完全一致**，零新机制 —— 代价是它证明不了 D19。
   **VIP 的代价可量**：`fee:1` 的曲子只给约 45 秒试听（720KB vs 应有 3.81MB），
   `fee` 就在搜索响应里 —— `access:"preview"`（`PLAN-search-row.md`）的判据现成。
2. **只做 `xmly-resolve` 半边**：**不行**。引擎 = 两个动词（D9）。
3. **等**：站点风控会变，记下日期，半年后重跑 §2 的表。
