# PLAN — 网易云引擎对（`ne-search` / `ne-resolve`）

**状态：未开工。** 决定已全部落定（见「决定」），实测证据已全部到手（见「量到的事实」），
下一步是按「实现规格」写两个脚本。

**它实现哪条路线图条目：** `ROADMAP.md`「第三对引擎 NO」里的**候选网易云**那半句 ——
「搜索半边验过…**resolve 半边没量过** —— 真开工第一步是量它」。那一步已在 2026-09-02 做完。
**本条不推翻任何 NO**：那条 NO 的作用域是喜马拉雅，网易云在同一条里是被点名的候选。

它同时解掉 `ROADMAP.md`「还没做的事」里的第一条 ——「一条搜索结果 ≠ 一个可播对象」。那条说
「**面已经在了**（行带必填的 `kind`/`access`），缺的是**信号**…本条等一个带真信号的引擎 ——
网易云的 `fee` 是量过的那个」。本 plan 就是那个引擎。

---

## 量到的事实（2026-09-02，除非另注）

每条都是执行出来的，不是读来的。复现脚本的**形状**记在这里，路径不记（`tmp/` 不可引用）。

| # | 事实 | 怎么量的 |
|---|---|---|
| 1 | **明文搜索端点已死** | `GET /api/search/get/web` 返回 `{"result":"35b174…"}` —— 十六进制加密块，不再是 JSON。**这更正了 `ROADMAP.md` 记的「明文」**，该处需就地改并标日期 |
| 2 | **weapi 搜索在纯 shell 下可行** | bash 3.2 + `openssl enc -aes-128-cbc` ×2 + 常量 `encSecKey` + curl + jq → `POST /weapi/cloudsearch/pc` 答 `code:200`，"周杰伦" 278 条 |
| 3 | **RSA 那步不必在运行时做** | 那个「随机 16 位 key」由调用方自选，无人校验其随机性。固定成常量后 `encSecKey` 是一个 256 字符十六进制常量。动态算亦可：`openssl pkeyutl -pkeyopt rsa_padding_mode:none` 就是无 padding 模幂 |
| 4 | **系统自带的 LibreSSL 够用** | macOS `/usr/bin/openssl`（LibreSSL 3.3.6）跑通 2 和 3，不需要 Homebrew 的 OpenSSL |
| 5 | **搜索零凭据** | 事实 2 那次请求只带 `Referer` + 浏览器 UA + `Cookie: os=pc`，无 token、无 profile 读取 |
| 6 | **`fee` 在搜索响应里** | `.result.songs[].fee`，不需要额外请求。取值实测只见 0 / 1 / 8（500 行里 `fee:4` 为 0 条） |
| 7 | **`yt-dlp` 的 `netease:song` 可用** | `-J` 出 id/title/duration/formats；format_id 为 `standard`/`higher`/`exhigh`（免费账号档位上限） |
| 8 | **`fee:8` 拿完整音轨** | id=5257138：`size:12764517`、`br:320001`、`time:319039`、`level:"exhigh"` |
| 9 | **`fee:1` 两条路径结果不同** | weapi 答 `size:0 / br:0 / level:null`（解不出流）；yt-dlp 走 eapi 答一个可播的 **30 秒片段**（被截断）。**这条是 `access` 映射的全部依据** |
| 10 | **登录链路通，但免费账号无增益** | Chrome cookie → `MUSIC_U` → `account/get` 答 `code:200`、`hasProfile:true`、**`vipType:0`**。带/不带 cookie 拿到的档位**逐字段相同** |
| 11 | **歌词是明文 GET** | `GET /api/song/lyric?id=N&lv=-1&kv=-1&tv=-1` 答 `code:200`，`.lrc.lyric` 是 LRC 文本。零加密、零凭据 |
| 12 | **免费账号可听比例 57%，且分布双峰** | 10 个查询 × 50 行 = 500 行的 `fee` 统计。Taylor Swift 6% / 陈奕迅 24% / 周杰伦 30% / 王菲 36% ‖ jazz 62% / 电子 72% / 古典 76% / 邓丽君 84% / 钢琴 88% / lofi 98% |

**事实 12 是这个引擎的定位，必须写进 `usage()`**：搜歌手名大概率撞 VIP 墙，搜器乐/长尾/华语
老歌几乎全通。样本 500 行、强依赖查询词，不是普适常数。

**不在本 plan 范围内、也没量的：** VIP 账号下 `lossless`/`hires`/`jymaster` 是否解锁（手头无
VIP 账号）。它不影响能否实现，只影响能听到多少，所以不阻塞落地。

---

## 决定

每条都记下**被否掉的替代方案**，否则这段就是在复述代码。

### D1 — 引擎名是 `ne`

`ne-search` / `ne-resolve`，配置前缀 `NE_*`，`--engine ne`，记录里 `{"engine":"ne"}`。

否掉 `netease`（比 `yt`/`bili` 长一倍，`--engine netease` 打字长）与 `wy`（对非中文使用者
不可读）。**落定后不得有第二种拼法** —— 帮助文本、错误、文档、PATH 入口一律 `ne`。

### D2 — openssl 是**引擎局部**依赖，缺失则该引擎不可用

`CLAUDE.md` 写的是「Never add a runtime dependency」。这是一次显式例外，范围划在引擎内：

- 只有 `ne-search` 用 openssl（`ne-resolve` 走 yt-dlp，`--transcript` 是明文 GET，都不碰）。
- 探测不到 openssl → `ne-search` 走既有的 `require_cmd` 门，死在 yt-dlp 之前，其余七个命令与
  另两个引擎**照常工作**。
- 因此**不写进 `CLAUDE.md` 的 Runtime Environment 必需列表**。

否掉「提升为套件必需依赖」：那会让不用网易云的人也背上这条，且 `tests/contract.sh` 的 host gate
不变式会因此对 bili/yt 用户变严。依赖随引擎对进出，正是「加一个源就是加一对脚本」的隔离承诺。

### D3 — `fee` 首先去填 `access`，其次才用于过滤

`access ∈ {full, preview, paywalled}`（`AS-BUILT-cli-contract.md`「数据契约」）今天被两个在产
引擎恒印 `full`，因为它们**算不出**这个信号。网易云能。映射：

| `fee` | `access` | 依据 |
|---|---|---|
| 0、8 | `full` | 事实 8：完整音轨 |
| 1 | `preview` | 事实 9：`ne-resolve` 实际走的路径给出**可播但截断**的 30 秒流 |
| 4 | `paywalled` | 需购专辑；实测 0 条，按站点语义填 |
| 缺失/其他 | `full` | 「引擎说它知道的，不猜它没有的」—— 未知不降级 |

`fee:1` 选 `preview` 而非 `paywalled`：以 `ne-resolve` **实际走的**路径为准，行里的承诺是一个
**下界**，VIP 账号拿到更多不算违约。这也让 `access` 不随登录状态变 —— 合
`AS-BUILT-cli-contract.md:342`「报的是站点事实，不是登录裁决」。

### D4 — 搜索默认过滤掉 `access != "full"`，配置键可翻开

`NE_INCLUDE_VIP=0`（默认）丢掉；`=1` 全返回。理由是「一条记录就是一次可执行调用」——
存进 `ut-playlist` 的行必须能跑，而不是一个可能被拒的引用。

这是**配置键不是 flag**：有没有 VIP 是 set-once 属性，不是每次请求的选择
（`CLAUDE.md`「Coding Style」）。

代价是结果数变少且原因不显性 —— 由 D5 的多取补偿，并在 `usage()` 里说明。

否掉「全返回 + TUI 灰显」：那是把引擎的判断挪进 UI，违反「引擎能修的别在 UI 修」，且
`access` 已经是 agent 面的答案，再加 TUI 标记是重复而非补充。

### D5 — 过滤造成的缺口由**多取**补，不由降低承诺补

`-n N` 说的是取多少，从来不是保证发多少（既有语义，见 `bili-search` 的 `-M` 说明）。但
57% 的通过率会让 `-n 20` 常态答 12 行，体验上过窄。因此：

- 首次请求 `limit = min(N × 2, 100)`（100 是该端点单次上限）。
- 过滤后不足 N 且服务端还有更多 → 按 `offset` 续页，直到满 N 或撞 `UT_MAX_SEARCH_RESULTS`
  或服务端耗尽。
- 请求数上限硬编码为 **3**：再多是对一个有风控的端点 burst，收益递减。

多取因子与页数上限**不做配置键** —— 保持 flag/config 面窄。

### D6 — 搜索**永不**发凭据

与 `bili-search` 同形（事实 5 已证匿名 200）。`NE_COOKIE_BROWSER` 只由 `ne-resolve` 读。
这条要在 `usage()` 里明说，和 bili 一样。

### D7 — 首版动词面

- **有**：`ne-search`（查询→结果信封）、`ne-resolve`（句柄→解析信封）、`--info`、`--transcript`。
- **无，且以缺席声明**：`--parts`（单曲无分 P）、`--auth`（事实 10 —— 免费账号下认证与匿名
  拿到的档位逐字段相同，这个动词现在没有可报的东西；VIP 账号出现时再开）。

`--transcript` 进首版是因为事实 11：明文 GET，近乎零成本，且是这个引擎相对 bili 的真实差异点。

---

## 实现规格

### `ne-search`

**传输**：`curl` + `openssl`。这是套件里第三处「自己拼请求」的地方（另两处是 `bili-search` 的
`fetch_page_once` 与 `bili-resolve` 的 `fetch_view_once`），seam 名 **`fetch_page_once`**，与
bili 同名同位。

**weapi 封装**（seam：`weapi_encrypt`，`ne-search` 内唯一调 openssl 的函数）：

```
presetKey = 0CoJUm6Qyw8W8jud      iv = 0102030405060708
step1 = base64( AES-128-CBC( payload_json, presetKey, iv ) )
params = base64( AES-128-CBC( step1,        presetKey, iv ) )    # 固定 key（D3/事实 3）
encSecKey = <下面那个 256 字符常量>                                # 编译期算好，运行时不算
```

两次 AES 都是 `openssl enc -aes-128-cbc -K <hex> -iv <hex> -a -A`。`-A` 必须有，否则 base64
带换行。

`K = presetKey = 0CoJUm6Qyw8W8jud` 时，那个常量是（2026-09-02 实测：用它发出的搜索答
`code:200`）：

```
bf50d0bcf56833b06d8d1219496a452a1d860fd58a14c0aafba3e770104ca77dc6856cb310ed3309039e686
5081be4ddc2df52663373b20b70ac25b4d0c6ca466daef6b50174e93536e2d580c49e70649ad19365848
99e85722eb83ceddfb4f56c1172fca5e60592d0e6ee3e8e02be1fe6e53f285b0389162d8e6ddc553857cd
```

（写成三行只为排版，**实际是一个 256 字符的连续串，无换行**。）

**它怎么来的，写下来免得下次没人敢动它**：它是 `RSA(reverse(K))` —— **反转过的** key，不是
key 本身。输入必须**正好 128 字节**：112 个零字节在前，16 字节的 `reverse(K)` 在后；无 padding
模幂，公钥是下面这个。改了 `K` 就必须重算，而配错的唯一症状是端点答一个通用错误码 —— 这正是
验证矩阵里那条「已知向量」检查存在的理由。

```sh
# 重算配方（一次性，不进产线代码）
K='0CoJUm6Qyw8W8jud'
{ head -c 112 /dev/zero; printf '%s' "$(printf '%s' "$K" | rev)"; } > /tmp/in.bin
openssl pkeyutl -encrypt -pubin -inkey pub.pem -pkeyopt rsa_padding_mode:none \
    -in /tmp/in.bin | xxd -p -c 256
```

公钥（网易云的公开常量，非机密）：

```
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6
sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgT
z+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB
-----END PUBLIC KEY-----
```

（同样，PEM 的 base64 体在原文里是**一行**；上面按 88 列折行只为排版，重算前需接回一行。）

**请求**：

```
POST https://music.163.com/weapi/cloudsearch/pc
Referer: https://music.163.com
User-Agent: $NE_UA
Cookie: os=pc
--data-urlencode params=…   --data-urlencode encSecKey=…
payload: {"s":<query>,"type":"1","limit":<L>,"offset":<O>,"csrf_token":""}
```

参数以**数组**送进 curl，值走 `--data-urlencode` —— 查询里的 `&`、空格、引号是值，不是第二个参数。

**信封**：与 `yt-search`/`bili-search` **逐字段相同**。

```
{"status","engine","query","count","results":[{id,title,url,channel,duration,
  duration_fmt,view_count,live_status,description,kind,access}, …]}
```

字段来源：

| 字段 | 来自 | 备注 |
|---|---|---|
| `id` | `.id`（数字转字符串） | 就是 `ne-resolve` 的输入 |
| `title` | `.name` | 过既有的 `clean_title` |
| `url` | `"https://music.163.com/song?id=" + .id` | |
| `channel` | `[.ar[].name] \| join(", ")` | 艺人；多艺人逗号分隔 |
| `duration` | `.dt / 1000 \| floor` | 毫秒→秒 |
| `duration_fmt` | `duration \| fmt_dur` | 既有函数 |
| `view_count` | **恒 `null`** | 该端点无播放数。`.pop` 是 0–100 的热度，**不是**计数，印成 `view_count` 是发一个假事实 |
| `live_status` | 恒 `null` | 无直播形态 |
| `description` | `.al.name` | 专辑名 |
| `kind` | 恒 `"track"` | 单曲端点，无容器形态 |
| `access` | 由 `.fee` 按 D3 映射 | **本引擎存在的理由之一** |

**整形只发生一次，在一个 jq 程序里** —— 与 bili 同规矩（`AS-BUILT-engine.md`）。`kind`/`access`
在 `FILTERED_JSON` 那一步**盖在**记录之上，不进 lean 投影，这样 `-j` 与 `-J` 一起拿到。

**行判据**：`select(.url != null)` —— 与 bili 同一条，覆盖任何「handle 建不出来」的形状。

**`-s view_count`**：`view_count` 恒 null，该排序退化为**保持站点顺序**，不报错。在 `usage()`
里说明。`-s duration` 正常工作。

**失败**：`search_fail` 同形 —— JSON 模式发
`{status:"error",engine,query,count:0,results:[],reason}`，**exit 2**。`reason` 词汇表：

| `reason` | 何时 |
|---|---|
| `openssl_missing` | 依赖门（D2）。这是唯一一个 bili/yt 没有的 reason |
| `network` | curl 非零 |
| `blocked` | HTTP 非 200，或 `code` 非 200 |
| `no_results` | 200 但过滤后 0 行 |

### `ne-resolve`

**传输**：`yt-dlp`（seam `dump_once`）+ 一处明文 curl（seam `fetch_lyric_once`，仅 `--transcript`）。

**句柄语法**（`normalize_target`，与 `bili-resolve` 同位同名）：

```
https://music.163.com/song?id=N      → 规范形
https://music.163.com/#/song?id=N    → 剥掉 #/，同上
https://y.music.163.com/…?id=N       → 移动端分享链
^[0-9]+$                             → 裸数字即歌曲 id（对齐 bili 收裸 BV/av）
其他                                  → die「'X' is not a NetEase handle (expected a
                                        music.163.com song URL or a numeric song id)」
```

主机白名单：`music.163.com`、`y.music.163.com`。

**信封**：`{stream_urls[], http_headers{}, title, duration, format, start_seconds}` —— 与另两个
引擎同形。`start_seconds` 恒 0（该站链接不带起播偏移，**恒填而非省略**，与
`AS-BUILT-engine.md:458` 的规矩一致）。

**(mode, tier) → format 表**（住在这个文件里，`--quality` 在**这里**翻译，永不在播放器）：

| tier \ mode | audio |
|---|---|
| `low` | `standard` |
| `medium` | `higher` |
| `high` | `exhigh` |
| `auto` | `NE_AUDIO_FORMAT`（默认 `ba/b`，交给 yt-dlp 选最好） |

**video / fast 模式**：该站单曲**没有视频轨**（MV 是另一种句柄，不在首版）。这两个模式解析到
同一条音频流，并在 `-j` 的 `format` 字段如实报音频格式 —— 不报错，也不假装有视频。

**`--info`**：走 yt-dlp 的 `-J`，出该站能给的元数据。无章节概念 → `chapters: []`。

**`--transcript`**：

```
GET https://music.163.com/api/song/lyric?id=N&lv=-1&kv=-1&tv=-1
Referer: https://music.163.com     Cookie: os=pc
```

信封与 `yt-resolve --transcript` 逐字段相同：`{status,engine,id,url,lang,is_auto,chars,
segment_count,text}`。

- `text`：`.lrc.lyric` 剥掉 `[mm:ss.xx]` 时间戳后的纯文本。
- `segment_count`：LRC 的行数（剥壳前）。
- `chars`：`text` 的字符数。
- `lang`：恒 `"zh"`（该站歌词无语言标注；**这是恒定默认值，不是猜测** —— 与 bili 恒印
  `track`/`full` 同性质）。
- `is_auto`：恒 `false`（网易云歌词是投稿的，不是机器生成）。
- **边界**：`.nolyric == true`（纯音乐）→ `transcript_fail`，reason `no_transcript`，exit 2。
  `.lrc.lyric` 缺失或空 → 同上。

**cookie 决策**：`NE_COOKIE_BROWSER`（默认 `chrome`，`none` = 匿名），只在这个文件里读，
经 `--cookies-from-browser` 交给 yt-dlp。事实 10 说明它对免费账号无增益，但对 VIP 账号有 ——
所以默认开着，与 `YT_`/`BILI_` 同规矩。**探测不到 profile 则匿名降级，不报错。**

### 新配置键（加进根 `config`，新一段 `── scope: engine ne ──`）

```
NE_COOKIE_BROWSER=chrome    # 只由 ne-resolve 读 —— ne-search 不发任何凭据
NE_AUDIO_FORMAT=ba/b
NE_INCLUDE_VIP=0            # 1 = 搜索也返回 access != "full" 的行（D4）
NE_UA=Mozilla/5.0 (Macintosh; …) Chrome/…   # 浏览器 UA
```

`config` 顶部那句「Only UT_ / YT_ / BILI_ keys are read」**必须同步加上 NE_**，否则新键读不到。
这是本 plan 里最容易漏的一处。

---

## 边界情况

| 情形 | 期望行为 |
|---|---|
| openssl 缺失 | `ne-search` 死在依赖门，reason `openssl_missing`，exit 2。`ne-resolve` 的所有动词**照常工作** |
| `ne-search` 存在但 `ne-resolve` 不存在（或反之） | `uting:365` 的 registry 要求成对，单边不被发现 —— 无需额外处理，但要在验证矩阵里断言 |
| 查询含 `&` / 空格 / 引号 / emoji | 走 `--data-urlencode`，是值不是参数 |
| 查询为空 / 只有空白 | 走既有的空参数门，exit 1（用法错） |
| `fee:1` 占满整页 | 过滤后 0 行 → 续页（D5）→ 仍 0 行 → reason `no_results`，exit 2 |
| `-n` 大于 100 | 分页取，受 `UT_MAX_SEARCH_RESULTS` 与 3 页硬上限约束 |
| 歌曲已下架（`code:200` 但无 `.data[0].url`） | `ne-resolve` 报解析失败，exit 2，reason 用 yt-dlp 的错误词汇 |
| 纯音乐（`nolyric`） | `--transcript` → reason `no_transcript`，exit 2 |
| 该站返回 `code:-462`（限流） | reason `blocked`，exit 2。**不重试** —— `BILI_RETRY_PAUSE` 那种一次重试是 412 burst 专用，此处无实测依据，不预先加 |

---

## 验证矩阵

**规矩：每一条都是 `tests/` 里的一行，不是文档里给人抄的散文。**
并且按「Harden before you extend」——**优先加强既有检查**，只有在既有检查确实够不到时才新增。

### 加强既有（首选）

| 既有检查 | 怎么加强 | 为什么这是加强而非新增 |
|---|---|---|
| host gate 跨**所有已发现引擎**的不变式 | 自动覆盖 `ne` —— 但要断言 `ne-search` 的 openssl 门与另两个引擎的 yt-dlp 门**发同一句话**（`contract.sh:1013` 那条「message is the discriminator」） | registry 是发现出来的，第三对落地即被扫到 |
| `kind`/`access` 枚举不变式（`contract.sh:1717`） | 今天只断言取值合法。加强为：**`ne` 的 `access` 必须不恒等于 `full`** —— 用一个已知含 `fee:1` 的固定查询喂进去 | 这是**判别性输入**：恒印默认值的实现会红，真算 `fee` 的实现才绿。正是 `CLAUDE.md` 要的那种检查 |
| 信封字段集跨引擎逐字段相同 | 自动覆盖 | 同上 |
| `-j` / `-J` 两种形状都带 `kind`/`access` | 自动覆盖 | 那条不变式本来就跨两种形状断言 |
| 空参数路径（3.2 地板） | 自动覆盖 | |

### 必须新增（既有确实够不到）

| 新检查 | 它抓什么既有检查抓不到的产线故障 | 落在哪 |
|---|---|---|
| weapi 编码的**已知向量**：固定 payload + 固定 key → 断言 `params` 逐字节等于记录值 | 加密拼错时，端点只会答一个通用错误码，任何「跑一次看绿不绿」的检查都会把它读成网络问题。这是套件里唯一一处**自己实现密码学**，必须钉住 | `contract.sh --offline`（纯计算，零网络） |
| `fee` → `access` 映射表：喂**固定的搜索信封 fixture**（真实数据，非 stand-in），断言三种 `fee` 出三种 `access` | 上面那条加强要网络；这条在 offline 半边钉住映射本身 | `contract.sh --offline` |
| `NE_INCLUDE_VIP=0/1` 改变行数 | D4 的开关是配置键，没有 flag 会走到它 | `contract.sh --offline`（同一份 fixture） |
| 句柄语法：四种合法形 + 三种非法形的退出码 | `normalize_target` 是纯函数式的门，offline 可全覆盖 | `contract.sh --offline` |
| `NE_COOKIE_BROWSER=definitely-not-a-browser` → 答 `anonymous` | `CLAUDE.md` 点名的判别性输入范式：env-var-alone 的捷径实现会答 `cookie` 而变红 | `contract.sh --offline` |
| 一次真的 `ne-search -j` → 管进 `ne-resolve` → 管进 `ut-play -d` | 只有这里才证明三方信封真的对得上 | `playback.sh`（要网络与真播放器） |

**不做的检查**（写下来免得下次有人补）：

- 不断言具体歌曲的 `fee` 值 —— 站点会改，那是把别人的运营决定钉进我们的套件。
- 不对网易云计时 —— 有风控，红了也是网络的错。
- 不 mock 那个端点。搜索半边要真跑就在 `playback.sh` 跑，或者不证。

---

## 落地清单

按 `CLAUDE.md` 的 A→E（这是结构性变更：新增surface）。

- [ ] **A** 写 `shell/ne-search` + `shell/ne-resolve`，与既有引擎并置；`tests/drive.sh` 在
      tmux 里驱一遍 TUI，确认 registry 扫到第三个引擎且 `e` 键能切到它
- [ ] **B** 无需 repoint —— registry 是发现出来的，没有要改的调用方。跑
      `tests/contract.sh --offline`
- [ ] **C** 无删除步 —— 纯新增
- [ ] **D** 文档：
  - [ ] `config` 加 `── scope: engine ne ──` 一段，**并把顶部白名单句改成 `UT_ / YT_ / BILI_ / NE_`**
  - [ ] `ROADMAP.md`「第三对引擎 NO」：把「明文」那半句就地更正为「weapi + openssl」，标
        2026-09-02；把「resolve 半边没量过」换成量到的结论
  - [ ] `ROADMAP.md`「一条搜索结果 ≠ 一个可播对象」：`ne` 落地后这条的「等一个带真信号的引擎」
        已满足，改写或移出
  - [ ] `AS-BUILT-engine.md`「`kind` 与 `access`」：加第三个引擎那一段 —— **为什么它算得出而
        另两个算不出**（`fee` 在搜索响应里，零额外请求）
  - [ ] `AS-BUILT-engine.md`：weapi 那一段的 why —— 明文端点死了、RSA 为何不必在运行时算、
        openssl 为何是引擎局部依赖
  - [ ] `CLAUDE.md` 的架构表加两行；依赖图加 `ne` 两行；**Runtime Environment 不加 openssl**（D2）
  - [ ] `README.md` 的引擎列表
  - [ ] 两个脚本的 `usage()`：事实 12 的定位说明、`-s view_count` 退化、搜索零凭据、
        `--parts`/`--auth` 以缺席声明
- [ ] **E** `tests/contract.sh`（全量）+ `tests/playback.sh` + tmux 驱一遍
- [ ] `VERSION` 判断：新增引擎对是**加法** → `0.y.z` 的 **z**。单独一个 commit
- [ ] 删掉本 plan

---

## 开放问题

无。四个决定（引擎名、fee 过滤、openssl 范围、首版动词面）与 `access` 映射均已在
2026-09-02 的交互里落定并记在上面。
