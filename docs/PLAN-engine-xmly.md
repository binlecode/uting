# PLAN-engine-xmly —— 第三对引擎：喜马拉雅

> **状态**：草拟，**未开工**。卡在 Gate 0（搜索需要登录态，尚未验证登录 cookie 能否过风控）。
> **实现的 ROADMAP 条目**：**D20**（第三对引擎选喜马拉雅）· **D19**（引擎按 site 切不按 stack 切 —— 本引擎是它的第一个实例）。
> **落地即删**：内容按 `CLAUDE.md` 的规矩拆进 `AS-BUILT-engine.md` / `AS-BUILT-contract.md`，本文件删除。

---

## 1. 为什么是这一对，以及它证明什么

加它不只是"多一个音源"。它是套件里**第一个 `X-resolve` 不以 yt-dlp 为主路径的引擎** ——
免费条目由站点自己给直链，`curl` + `jq` 就够。`bili-search` 已经证明了 search 半边可以不用
yt-dlp；这一对补上 resolve 半边，于是"**seam 是 envelope，不是背后那个工具**"（D11）在两个
半边上都有实例，而不再只是一句写下来的原则。

它同时是 **D19 的第一个实例**：一个 source 内部同时用两条 stack（免费 curl / VIP yt-dlp），
这正是"按 stack 切 resolver"会被撕成两个文件、而按 site 切只是一个 `if` 的那个案例。

---

## 2. 已验证的事实（2026-08-28 实测，本机，无凭据，yt-dlp 2026.08.19）

**每一条都是跑出来的，不是读文档得出的。** 开工前重跑一遍 —— 站点会变。

| 面 | 端点 / 命令 | 结果 |
|---|---|---|
| 单条音频（**能用**） | `curl -s https://m.ximalaya.com/tracks/47740352.json` | 明文 JSON：`title` / `duration` / `is_paid` / **`play_path_64`、`play_path_32` 直链** |
| 直链可取性 | `curl -r 0-2000 <play_path_64>` | **HTTP 206**，真字节 |
| 速度对比 | 同一条 sound | **curl+jq 305ms** vs **yt-dlp 1082ms**（3.5×） |
| VIP 条目 | yt-dlp `XimalayaIE` | `is_paid:true` → `mpay.ximalaya.com/mobile/track/pay/<id>/<ts>` + RC4 解 `ep` + 解 fileId seed，**yt-dlp 已实现并维护** |
| 专辑曲目表 | `revision/album/v1/getTracksList` | `ret:401 用户未登录` |
| 搜索（web） | `revision/search/main` | 风控：`{"reason":"risk invalid","riskLevel":5}` |
| 搜索（mobile） | `m-revision/page/search` | `{"ret":303,"needLogin":true,"loginUrl":"…/passport/login"}` |
| 搜索（其他） | `revision/search/all` · `mobwsa/search/v3` · `openapi-search/v1` | 404，端点不存在 |
| 绕风控尝试一 | 先取首页 cookie（华为 WAF `HWWAFSESID`）再搜 | 仍 `riskLevel:5` |
| 绕风控尝试二 | 补 `xm-sign`（`revision/time` + `md5("himalaya-"+ts)` 那套） | 仍 `riskLevel:5` |

**结论**：解流那半边今天就能写；**搜索那半边要登录态**，而这是整个 plan 的前置。

---

## 3. Gate 0 —— 开工的唯一前置（未验证）

> **一个真登录 cookie 能不能过 `riskLevel:5`？**

不能，则本 plan **停**：引擎 = 两个动词（D9），只有 resolve 没有 search 的东西不是引擎。
那时的退路记在 §9。

验证方法（**第一步就做，不要先写代码**）：

```sh
# 从浏览器取 ximalaya 的 cookie（只取这个域），带上再打同一个端点
curl -s -b "<ximalaya cookies>" -A "<真实 UA>" \
  -H "Referer: https://www.ximalaya.com/search/%E5%94%90%E8%AF%97" \
  "https://www.ximalaya.com/revision/search/main?core=all&kw=%E5%94%90%E8%AF%97&page=1&rows=3&spellchecker=true&condition=relation&device=iPhone"
```

- 回 `{"ret":200,"data":{"result":…}}` 且带曲目字段 ⇒ **Gate 0 通过**，按 §4 建。
- 仍回 `riskLevel` ⇒ 风控看的不是登录态而是设备指纹 ⇒ 停，走 §9。

**判别性要求**：通过之后还要再跑一次**不带 cookie** 的同一条命令，确认它仍然红。
否则证明的是"这条端点又通了"，不是"登录 cookie 起了作用"。

---

## 4. 设计

### 4.1 命名（D10）

`xmly-search` / `xmly-resolve`。**落选**：`ximalaya-*`（命令前缀过长，且与另外两个 2–4 字母的
站名前缀不成一族）、`xima`（站点自己不这么缩写）。`XMLY` 是该站通行缩写，也是 CDN 域
`xmcdn.com` 的同源缩写。

### 4.2 `xmly-search` —— 第一个搜索半边带凭据的引擎

- transport：`curl` + `jq`，与 `bili-search` 同一形状。
- **但它送 cookie** —— `bili-search` 零凭据，`yt-search` 做 cookie 决定；本引擎属后者，
  所以**不是新机制，是第二例**。配置键 `XMLY_COOKIE_BROWSER`（D18，出厂默认写进 `config`）。
- 输出：`AS-BUILT-contract.md` §3 的搜索 envelope，**一个字段都不加**。
- `auth` 的含义与 D16 一致：报的是 cookie 决定，不是"你登录着"。**本引擎的特殊之处要如实写进
  usage**：这里 `auth=none` 意味着搜索**会失败**（而不是像 bili 那样正常工作），
  因为站点要登录态 —— 这是唯一一处 cookie 决定与"能不能用"直接挂钩的引擎。

### 4.3 `xmly-resolve` —— 两条 stack，一个文件（D19 的实例）

```
  handle → m.ximalaya.com/tracks/<id>.json   (curl，305ms，永远先走这条)
             │
             ├── is_paid:false → play_path_64 就是直链 → emit_stream        ← curl 路径
             └── is_paid:true  → yt-dlp（mpay + RC4，交给依赖去维护）        ← yt-dlp 路径
```

- **`is_paid` 是分叉判据，不是猜测** —— 它就在第一次 curl 的响应里，所以不多一次往返。
- 两条路径**回同一张 resolve envelope**（`{stream_urls[], http_headers{}, title, duration, format}`）。
  调用方看不出走了哪条 —— 这就是 seam 是 envelope 的意思。
- `http_headers`：直链实测 206 不需要 Referer，**但仍按站点事实填**，且**绝不放 Cookie/Authorization**
  （`AS-BUILT-verification.md` §25 的那条风险）。
- **`--transcript` 不做**：站点无字幕，引擎用动词的有无声明能力（与 `bili-resolve` 同）。
- `--info` 做。`--auth` 做。

### 4.4 handle 语法与 host 白名单（D12）

| 收 | 例 |
|---|---|
| `https://www.ximalaya.com/sound/<id>` | 网页 URL |
| `https://m.ximalaya.com/sound/<id>` | 移动 URL |
| `sound/<id>` · 裸 `<id>` | 短 handle |

白名单：`ximalaya.com` / `www.ximalaya.com` / `m.ximalaya.com`。**别站 URL 一律退 1**，
不转交、不通配。

**`album/<id>` 第一版不收** —— 一个 album 是几十上百条，"一个 handle = 一个可播对象"
这条不能破。它与 B 站合集是**同一个问题**（`ROADMAP.md` §11 第一条），应该一起解，不在本 plan 内。

### 4.5 待定的一个决定：`-f video` 在一个纯音频站上是什么

推荐答案：**等价于 audio，`format` 字段如实报音频**。理由：`-f` 是每次调用的模式 flag、
不是能力声明（能力用动词的有无声明），而一个搜到就想放的调用方不该因为默认模式撞在一个
usage 错误上。**被否**：退 1 —— 那会让 `ut-play -f video` 在切到这个源时炸，
而播放器不认识站点、无从预判。

---

## 5. 会被改到的现有文件（`ut-play` 与 `uting` 各零行）

| 文件 | 改什么 |
|---|---|
| `config` | 加 `XMLY_COOKIE_BROWSER=chrome`（D18：出厂默认值声明在这里） |
| `docs/AS-BUILT-engine.md` | §7/§8.2/§10 加本站的三段站点事实 |
| `docs/AS-BUILT-contract.md` | §5 配置键清单；§6 加引擎清单按本次实际经历校正 |
| `docs/ROADMAP.md` | D20 状态；§11 若 album 那条并进合集条目 |
| `README.md` | 三源；`## What it is` 的引擎段 |
| `VERSION` | **加法 → z 位**，单独一个 commit（D13） |

`shell/ut-play`、`shell/uting`、另外两对引擎：**零行**。这是这套架构要兑现的那句话，
本次就是它的第三次检验 —— 如果发现必须改，那是设计出了问题，停下来看，不要顺手改。

---

## 6. 验证（`done_when` —— 逐条**执行**，不是读）

**先算清哪些是白拿的**：`contract.sh` 的 host gate、envelope 形状、cookie 决定的判别性输入，
都是按**发现到的每一个引擎**（`<name>-search` + `<name>-resolve` 对）写的不变量 ——
所以这一对落地当天自动被覆盖。**这正是"harden before you extend"的红利，不要为它新写检查。**

| # | 检查 | 归属 |
|---|---|---|
| 1 | `bash -n shell/xmly-*` | pre-commit |
| 2 | 既有的跨引擎断言全绿（host gate 退 1、envelope 字段、`XMLY_COOKIE_BROWSER=definitely-not-a-browser` → `anonymous`） | `contract.sh --offline` 自动 |
| 3 | `xmly-search -j -n 5 -- "唐诗"` → 5 条，字段齐 | `contract.sh` live 半 |
| 4 | `xmly-resolve -j -- sound/47740352` → 直链可取（206），**且走的是 curl 路径** | `contract.sh` live 半 |
| 5 | **VIP 分叉**：一个真 `is_paid:true` 的 sound → 同一张 envelope，走 yt-dlp 路径 | `contract.sh` live 半，**需要一个稳定的 VIP fixture id** |
| 6 | `ut-play -d --engine xmly -- <handle>` 真起播、真写 history 行 | `playback.sh` |
| 7 | TUI 切到第三个源、列表能出、Enter 能播 | `drive.sh` |

**第 5 条是这份 plan 里最容易被跳过的一条**，因为它要一个会变的外部对象。
找不到稳定的 VIP id 就**如实记进 `AS-BUILT-verification.md` §27 的未覆盖清单**，
不要用一个替身把它变绿 —— 套件里没有替身。

---

## 7. 建造顺序（A→E，加面属结构性变更）

- **A** 先 `xmly-resolve`，对着**已有**的 `ut-play --engine` 跑通（引擎名即命令前缀，不需要注册表）。
- **B** 再 `xmly-search`；TUI 靠 glob 自动发现这一对，不改它。
- **C** 本次**没有删除步骤** —— 纯加法。若中途发现要改 `ut-play`/`uting`，回 §5 的最后一句。
- **D** 文档按 §5 的表 resync。
- **E** tmux 头戴一遍 + 无头两套。

---

## 8. 冷读预演（**待做** —— 必须由本次会话之外的读者做）

`CLAUDE.md` 要求 plan 在开工前被冷读者写一份失败回顾。**本节现在是空的，这是一个缺口，不是一个格式。**
交给冷读者的是本文件全文，不带这次对话。已知要请他重点打的三处：Gate 0 的判别性、
第 5 条 VIP 覆盖的可持续性、以及 §4.5 那个 `-f video` 的决定。

---

## 9. Gate 0 不通过时的退路

1. **换网易云做第三对。** 实测（2026-08-28）：搜索 `music.163.com/api/cloudsearch/pc`
   **明文、公开、零凭据**（`code:200`，271 条，`{id,name,ar[],dt,fee}`）；解流必须 yt-dlp
   （明文 `song/enhance/player/url` 回 `url:null, code:404`），3585ms，与 `bili-resolve` 同档。
   **形状与 B 站完全一致**，等于零新机制 —— 代价是它证明不了 D19（两条 stack 那件事）。
   **VIP 的代价可量**：`fee:1` 的曲子只给约 45 秒试听（720KB vs 应有 3.81MB），
   而 `fee` 就在搜索响应里 —— 与 B 站合集同类，**该由引擎在 envelope 里标出来**。
2. **只做 `xmly-resolve` 半边**：**不行**。引擎 = 两个动词（D9）。一个只能解流的脚本没有入口，
   与 D12 拒掉 URL-only 音源是同一个理由。
3. **等**：站点风控是会变的，记下日期，半年后重跑 §2 的表。
