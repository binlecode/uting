# AS-BUILT-engine —— 什么是一个引擎：`<name>-search` + `<name>-resolve`

那两个认识**站点**的半边的实现：`yt-search` / `yt-resolve` 与 `bili-search` / `bili-resolve`。
查询整形与搜索的错误契约、Bilibili 的 HTTP 传输、登录 / PO-token 探测、句柄文法与 host 白名单、
解析信封、`--info` 与 `--transcript`。**这套套件里每一个与站点相关的事实，要么写在这里，
要么就是一次分层违规** —— 播放器与站点无关，TUI 是纯编排。

**这是第三个引擎的作者要读的那份文档**，与 `AS-BUILT-contract.md` §6 的清单并排看。

**分工。** `ARCHITECTURE.md` 留图、拓扑、接缝与决定；契约面（argv、信封、退出码）在
`AS-BUILT-contract.md`；而一个引擎**实际是怎么落地的** —— 哪一条规矩是被一次测量逼出来的、
哪里有坑以及为什么 —— 在这里。播放子系统与 detached 生命周期归 `AS-BUILT-player.md`。

**节号是继承来的**，沿用 `ARCHITECTURE.md` 原有的编号（§7、§8.2、§10 及其子节），
于是一条既有的 `§10.1` 引用只换文件名，编号从不变。这也是为什么这里有 §8.2 却没有 §8：
§8 是播放子系统、留在播放器那边，而 8.2 本来就是引擎知识。

**代码是唯一权威。** 这里点名的函数是 soft ref（文件 + 函数名）；伪码是形状，不是源码的副本。

**这份文档刻意不拥有的一件事**：一个 `-f MODE` 作为格式字符串*意味着什么*是引擎知识
（`format_for_mode()` 住在每个 `<engine>-resolve` 里），但 模式→格式→mpv 那张表只陈述一次，
就放在播放器的 mpv 选项集旁边，见 `AS-BUILT-player.md` §8.1。

---

## 7. 搜索子系统 —— 引擎的一个动词

搜索是一个引擎的一半（`ARCHITECTURE.md` §4），所以这一节描述的是 `yt-search`；
`bili-search` 是同一个信封架在不同传输之上（§7.1），它的 argv 规定在
AS-BUILT-contract.md §1。下面的一切 —— 那**一个** jq 程序、内部的 `FILTERED_JSON` 形状、
时长规则、错误契约 —— 是**两半都要实现**的东西，而两个文件**各自带一份自己的副本**是有意的：
一个与另一个引擎共享库的引擎，那个库最终会变成播放器不得不知道的东西（`ARCHITECTURE.md` §4）。

```
  QUERY、NUM_RESULTS、MIN/MAX_DURATION、SORT_FIELD、cookies
        │
        ▼
  ┌──────────────────────────────────────────────────────────────
  │ fetch_results()
  │  yt-dlp "ytsearch<N>:<QUERY>"
  │     [--match-filter "duration > MIN [and duration < MAX]"]      ← 只有被要求时才加
  │     [--cookies-from-browser <B>] --flat-playlist
  │     --dump-single-json -f ba --skip-download --quiet …
  │     stderr → 捕获；非零 rc ⇒ 错误信封 + 退出
  │        │
  │        ▼  **一个** jq 程序（JQ_PRELUDE + 整形）：
  │           按上下界 select → + {duration_fmt: dur|fmt_dur, kind, access}
  │           → sort_by(duration|view_count)|reverse
  │  FILTERED_JSON （数组；**内部**形状 —— 永不改动）
  └───────────────┬───────────────────────┬─────────────────────
      OUTPUT=list │            OUTPUT=json │ json_full
                  ▼                        ▼
           print_list()            emit_search_json()
        "♫ N. 标题 / 时长 /        {status,engine,query,count,results:[ 投影 ]}
         播放量 / url"             json：10 个精瘦字段；json_full：原始记录
```

`engine` 之所以在信封里，是因为一个拿着结果的调用方必须能把它**路由回**懂它的那个 resolver ——
`ut-play --engine <那个值>`（AS-BUILT-contract.md §3、D12）。它正是 host 白名单
（ROADMAP D12）存在要保其诚实的那个字段。

`print_list()` 读的是 **`FILTERED_JSON` 这个变量**，不是发出去的 `-j` 流。
投影只发生在发射点，所以 JSON 契约可以改而不必碰那个消费者。（schema → AS-BUILT-contract.md §3。）

**一个 jq 程序，不是每条一遍的循环。** 换成一个 bash `while read` 循环 —— 每条 fork 两次 jq、
`print_list` 每行再 fork 五次，`-n 25` 就是 175 个进程 —— 实测比这一个程序慢约 **40×**，
而且会把 `FILTERED_JSON` 里本来就带着的 `duration_fmt` 再推导一遍。

**时长格式化只住在一个地方：`JQ_PRELUDE` 里那个 jq 函数**（`fmt_dur`），
搜索整形与 `--info` 共用它。用 jq 而不用 bash，是因为每一个消费者本来就在用 jq 整形 JSON，
所以一个 bash 实现存在的唯一意义就是每行被 fork 一次。一个未知的时长产出 **`null`**，
而不是一个假的 `00h:00m:00s`，再由每个面自己决定怎么渲染它：
`print_list` 对直播打 `LIVE`、其余打 `--`，而 `uting` 显示 `● LIVE` ——
**一个原始的 `null` 不进人类输出**。

**时长上下界（`-m`/`-M`）是在**客户端**执行的，就在同一次 jq 里。** `--match-filter`
只是一个便宜的服务端预过滤，而且**只有真的要求了某个界时才发** ——
一个永远开着的 `duration > 0` 什么都过滤不掉。理由：在 `--flat-playlist` 下
yt-dlp 把条目标记为"不完整"，于是一个作用在"扁平条目并不携带的字段"上的过滤器 ——
一条直播没有 duration —— **判定不了，于是保留该条目**。所以只靠那个预过滤，`-m 999999`
仍然会返回一条直播结果；客户端那一遍按这个 flag 的字面意思排除掉时长未知的条目。验证过。

**搜索像其他每一个面一样有错误契约。** 没有它，一次 yt-dlp 失败会在 `set -e` 上带着原始
stderr 中止 —— 哪怕在 `-j` 下，交给 agent 的也是一个 jq 解析错误。`fetch_results` 捕获 stderr，
用引擎自己的 `classify_yt_dlp_error` 分类（**枚举是共享的，分类器不是** ——
AS-BUILT-contract.md §3），并为 `-j`/`-J` 发出
`{status:"error", engine, query, count:0, results:[], reason}`（散文路径：捕获到的 stderr 加一次
`die`）。退出码是 2+ —— **绝不是 1**，那个被 AS-BUILT-contract.md §4 留给用法/校验错误。

### 7.1 Bilibili 的传输 —— 同一个信封，架在一个手工拼出来的请求上（D11）

`bili-search` 用 `curl` + `jq` 而不是 yt-dlp 实现了上面的一切。这个拆法不是偏好，
它是**唯一**行得通的组合（实测，ROADMAP D11）：yt-dlp 的 `--flat-playlist` 用 0.9s 作答，
却**一个元数据都没有**（`BiliBiliSearchIE` 产出 `url_result(arcurl, aid)`，
把它刚刚解析出来的响应里的 标题/作者/时长/播放量 全丢掉了），而一次完整抽取会递归进
**每一个合集的每一个分 P** —— 这个站点的音乐结果压倒性地是多 P 的 ——
于是 `bilisearch10:` 在 120s 内根本跑不完。**一个手工拼的请求 0.71s 就答出信封需要的每一个字段。**

`fetch_page_once` 是**全套件唯一一处手工构造 HTTP 请求的地方**（`ARCHITECTURE.md` §5）。
参数以**数组**到达 curl，查询值经 `--data-urlencode` 送出，
于是一条含 `&`、空格或引号的查询是一个**值**，而绝不会变成第二个参数：

```
   GET <search/type>  search_type=video · keyword=<QUERY> · page=<N>
       [duration=<1|2|3|4>]               # 仅当 -m/-M 整个落进站点自己那四个粗桶之一
       [order=click]                      # 仅 -s view_count；relevance 就是站点默认，不发
       -H "User-Agent: $BILI_UA"          # 一个浏览器 UA；**不得**含 `curl`/`python`
       -H "Referer:    https://www.bilibili.com/"
       [-H "Cookie: buvid3=<uuidgen>infoc"]
       --compressed --max-time 15 --retry 0        # 重试与否由调用方决定
   ok ⇔ curl rc 0 **且** http 200 **且** 响应体自己的 `.code == 0` **且** 响应体不是一张风控券
```

三条请求层面的事实，每一条都是被测量逼出来的，不是选出来的：

- **`Referer` 是必需的，而且是唯一必需的东西。** 带上它端点答 `code:0`，
  不带就是 412（2026-08-23 实测）。它是一个公开常量，不是一种认证机制 ——
  yt-dlp 里每一个 Bilibili extractor 发的都是同一个。
- **`buvid3` 是一个**设备**标识，不是凭据**：没有账号、没有 token、不从任何浏览器 profile 读东西
  —— 引擎自己生成一个随机的（`uuidgen` + `infoc`，正是 yt-dlp 用的那个形状），
  进程退出就扔掉。它是**正确性，不是优化**：匿名连搜六次的结果是
  200 200 412 412 412 200，而带一个稳定 buvid3 是六次 200（2026-08-23 实测）。
- **`BILI_UA` 可以覆盖**，因为这个站点是**已知**会开始拒绝一个过时 UA 的
  （yt-dlp 里就有一个专门为此而来的提交），而一个不改代码就没法被推一把的套件，
  会需要发一次版本才能活下来。

这一小节里每一条带日期的数字都是**实测的，不是引用来的**，而这如今是唯一的选项：社区那份
权威文档（`SocialSisterYi/bilibili-API-collect`）已于 **2026-01-28 因 B 站律师函永久关停**，
只剩若干镜像。镜像里标注的现行分类搜索端点是 `…/wbi/search/type` 且要求 Wbi 签名，
而被划掉的旧链接 `…/search/type` —— 本引擎用的正是它 —— 在 **2026-08-26** 仍然只凭
`Referer` + `buvid3` 就答出真实结果。哪天它不再答，退路是 Wbi 签名，
而那条路不引入新依赖（key 全站通用、每日轮换，缓存一天即可；哈希是 md5）——
但那是届时的工作，不是现在的实现。

**这条手写的 HTTP 路径从不碰任何凭据**，而这就是穿过这个引擎中间的那条线：
登录状态只到达 yt-dlp、只在解析那一半、只经由 `--cookies-from-browser`。
正是它让 D11 对"为什么不做一个完整客户端"的回答（"那整块归 yt-dlp"）
对搜索这一半也同样为真。

**能让站点筛的就让站点筛 —— 这是请求数的问题，不是一个功能。** 这个端点每页固定 20 条、
**没有** page size 旋钮（`numResults` 上限 1000、`numPages` 上限 50），
于是一次带筛选的搜索唯一省得下来的请求，就是让每页那 20 行是本地那一遍会**留下**的行。
站点自己的 `duration` 是一个**粗**筛：1 = 10 分钟以下、2 = 10–30、3 = 30–60、4 = 60 分钟以上。
`duration_bucket` **只在**本地边界会接受的每一个时长都落在同一个桶里时才选那个桶 ——
要的是答案的一个**超集**，绝不是一次更窄的切割：一个会剪掉哪怕一行的桶，
会让服务端筛选改变**答案**而不只是**代价**，而桶的边界（正好 600s 算 1 还是 2？）
不是这个引擎能知道的事。所以一个跨两个桶的窗口（`-M 900`，帮助文本里的那个例子）拿 0、
得不到站点的任何帮助；而本地那对精确边界**无论如何都照跑** ——
`duration=1` 的意思是"10 分钟以下"，从来不是"$MAX_DURATION 以下"。
下推改变的不是**请求数**，而是那些请求的**产出** —— 翻页循环数的是站点发来的**原始行**
（`got`），不是本地留下的行，所以 `-n` 恒定花 `ceil(-n / 20)` 个请求，且**不会**为了凑满 `-n`
而多翻页（对这个主机，请求才是稀缺的那一样）。同一条查询，实测（2026-08-26）：
默认的一次请求（`-n 20`）进桶回来 **20** 行可用、跨桶 **1** 行；两次请求（`-n 25`）
进桶回来 **25** 行、跨桶 **6** 行，两者都是 1.4–1.8s。这也是它在 `contract.sh` 里被
`-M 600`/`-M 601` 那对输入钉住的原因（AS-BUILT-verification.md §27）。

**`order` 同理，但只有一个字段对得上。** `-s view_count` 要的是播放最多的那些，
而站点有 `order=click`：**问它**意味着到手的 20 行是整个结果集里播放最多的，
而不是最相关的 20 行在本地重排一遍 —— 同样的代价，一次正确性的收益。
`relevance` 就是站点自己的默认（totalrank），所以什么都不发，请求逐字节仍是被测量过的那一个。
`-s duration` **没有**服务端对应物（该端点按 click/pubdate/弹幕/收藏/评论排，不按长度），
于是它只把**已取回的那一组**重排 —— 这是一个站点不提供的排序所能诚实做到的极限。
即使站点已经排过，本地那一遍照排：本引擎**发布**的字段是 `.play`，
而发出的行必须按那个字段降序、未知在最后，这是只有那一遍守得住的承诺。
请求计划在**第一页之前只算一次**：一次搜索的每一页问的必须是同一个问题，
一个中途变了的筛选会把两个结果集翻成一页。

**这个主机会在三个不同的地方说"不"，三层都查。** 一个 HTTP 状态；一个装在 HTTP 200
响应体里的 `.code`；以及最安静的那一个 —— HTTP 200 **且** `code:0`，但 `data` 里装的是一张
风控券（`v_voucher`，一张验证码票）而不是结果数组（2026-08-26 对着 wbi 端点不签名实测）。
只读第一层会把一次限流报成一次零结果的**成功**，只读前两层会把一次验证码挑战报成同样的东西。
`fetch_page_once` 趁响应体还在手上就地判它，而且**两个条件都要**：一张券**加上**没有可用的
`result` 数组 —— 因为一次耗尽的翻页也会省略 `result`，而那不是一次拒绝。它落在 `network`
那一类，因为它就是 412 那同一个突发限流器换了身成功的衣服，因而同样**可重试**。

**重试是分类过的，不是一刀切。** `classify_http_error` 把 rc/http/`.code` 映射到套件那份
reason 枚举上，而**只有** `network` 那一类值得在 `RETRY_PAUSE` 之后再试一次；
一个 `forbidden` 或 `unavailable` 的回答一秒之后还会说同样的话，
而再问一次是对着一个**会计数**的主机多发一次请求。其余一切直接失败到 `search_fail` ——
退 **2**，绝不是 1（AS-BUILT-contract.md §4）。

**翻页在两个条件之一成立时停。** 只有当调用方**还想要**更多行**且**站点**还在给**时才请求下一页
（`MAX_PAGES` 给其余部分封顶），于是一条短尾巴不必付 `MAX_PAGES` 次往返。
一次耗尽的或空的搜索会**整个省略** `data.result` 而不是送一个 `[]`，
这正是那次读要写成 `.data.result // []` 的原因。

**整形用的是同一个 jq 程序** —— 只多一份活，因为这条传输返回的是一个*搜索 API 的*记录，
而不是一个 extractor 的。归一化后的字段被合并**盖在**原始记录之上，
于是 `-J` 保留站点发来的每一个字段，而 `-j` 投影出与 `yt-search` 同样的那十个字段，
并且 `title`/`duration` 在**两者**里都是清洗过、类型正确的值 ——
没有任何一个面会拿到那段 HTML 或那个 `"MM:SS"` 字符串。两处值得点名的归一化：
`url` 是**从 `bvid` 构造**的而不是取自 `arcurl`（后者是 `av` 拼法、走 `http://`），
因为规范的 BV URL 才是调用方要交回给 `bili-resolve` 的东西；
以及 `live_status` 是 **`null`，不是那个原始的 `0`** ——
在 `search_type=video` 下那个字段根本不是这套套件 is_live/was_live 的概念，
把那个 0 带过去会让某个渲染器画出一个站点从没声称过的直播状态。
**一个引擎不知道的字段是 null，而那个键仍然在**（AS-BUILT-contract.md §3）。
那十个字段里的 `kind`/`access` 是新来的两个，见 §7.2。

### 7.2 `kind` 与 `access` —— 引擎的判断落在哪里，以及 B 站为什么两个都是默认值

契约（AS-BUILT-contract.md §3）要求每一行都带 `kind` 与 `access`。两处实现事实：

**注入点在 `FILTERED_JSON`，不在 lean 投影里。** 它们是**引擎的判断**，不是站点的原始记录，
所以在整形那一步就合并**盖在**记录之上：`-j` 与 `-J` 由此一起拿到它们，且引擎的判断压过
任何同名的原始字段。只写进投影的实现会让 `-J` 少两个必填字段 —— 而每一条 `-j` 检查照旧全绿，
这正是 `tests/contract.sh` 那条不变式要跨**两种形状**断言的原因。

**两个引擎今天都印恒定的 `track`/`full`，而这是实测结论，不是占位。**
YouTube 一行就是一个视频，匿名抽取要么拿到完整时间轴要么什么都拿不到 —— 没有试听这种形态。
B 站这一侧曾以为 `episode_count_text` 与 `is_pay` 就是那两个信号，**2026-08-28 实测推翻**：

- `episode_count_text` 是 `ketang`（课堂）行的**课时数**。真有 200 个分 P 的
  「【经典】周杰伦全MV 【200P】」这一格是 `""`，而这一行与一条普通短单曲的
  **key 集合逐字段相同** —— `search_type=video` 根本不携带分 P 信号。
  真信号 `videos: 200` 只在 `x/web-interface/view` 里，那是**一行一个额外请求**：
  20 行就是对一个已经需要风控防御的端点 burst 20 发，代价与收益不成比例。
- `is_pay` 在四个查询 × 20 行里**无一非零**，而且在唯一那条确实付费的 `ketang` 行上也报 `0`：
  付费内容不在 `search_type=video` 这张表里。

于是 B 站两个字段都如实印默认值。**引擎说它知道的，不猜它没有的信号** ——
恒为默认值是合法状态（AS-BUILT-contract.md §3），而一个猜出来的 `kind` 会以事实的面目发货。
补上的条件：出现**不加请求**就能拿到的分 P / 付费信号，或搜索端点本身开始携带它。

**`ketang` 行不进信封。** 同一次实测发现的现役缺陷：`search_type=video` 会混进课堂记录，
它们**没有 `bvid`**，而**空串在 jq 里为真** —— 于是 `select(.id != null)` 把它们放了过去，
发出去的是 `id:""` / `url:null`，一条 `ut-play` 不可能消费的行（实测"钢琴" 20 行里 3 条）。
判据因此改为 **`select(.url != null)`：一行结果是一次调用，否则不是一行**
（AS-BUILT-contract.md §3）。这条判据同时覆盖将来任何"handle 建不出来"的形状，
而不只是今天漏进来的这一种；代价是 `-n 20` 可能答 17 行 —— 与 `-m`/`-M` 早已如此，
`-n` 说的是取多少，从来不是保证发多少。

## 8.2 登录、PO token，与"先探后播"的客户端选择 —— **在 `yt-resolve` 内部**

整个这一小节都是 YouTube 引擎的知识，住在 `shell/yt-resolve` 里。把它写在这儿，
是因为它正是解析信封为什么要带 `retried` 的原因，也因为"先探**后**播"如今是字面意义上的真：
探测发生在 mpv 启动**之前的一个进程**里、在引擎里，播放器只是把裁决转述出去。
`bili-resolve` 没有探测 —— 该站没有 PO token 的对应物 ——
这正是"第二个引擎可以干脆没有某样东西"的范本。

**登录默认是开的（`YT_COOKIE_BROWSER=chrome`）** —— 这是每个**引擎**自己去读的设置 ——
所以需要登录 / 会员 / 年龄限制的视频（匿名客户端根本看不见）能放。代价是：带上 cookie 之后，
yt-dlp 会切到 YouTube 的已认证客户端集，而那一组的 googlevideo 媒体 URL 可能需要一个
**GVS Proof-of-Origin（PO）token**，由 Google 的 BotGuard 证明机制签发（见 yt-dlp 的
PO Token Guide；标准提供者是 `bgutil-ytdlp-pot-provider`）。没有提供者时，
那些已认证的 URL 对*某些公开视频*会在一次朴素 GET 上 **403**，
而匿名客户端的 URL 不需要 token、干净地取到（HTTP 206）。
本机实测：同一个公开视频 → 带 cookie 403，不带 206。

朴素的修法 —— 先播、让 mpv 403、再匿名重播 —— 能用，但会在重试之前把 mpv 的一整墙错误糊在
屏幕上。默认做法改成：**在启动 mpv 之前先探哪一个客户端真的取得到媒体**，然后用赢家**播一次**。
`probe_raw` 从**已经解析出来的**记录里取第一个媒体 URL —— 它不做第二次抽取 —— 发一个
**开区间 ranged 请求**（`curl -I -r 0-`）：206/200 ⇒ 有权；403 ⇒ 缺 PO token，
与 mpv 加载到一半才会得到的裁决是同一个（对 HLS 的 `.m3u8` 播放列表，探的是第一个分片）。
匿名回退与匿名探测都用 `extractor-args=youtube:player_client=android`，
以确保 YouTube 的 CDN 给出的流不会在 range 请求上 403。

```
   resolve_stream()                          # shell/yt-resolve —— 真正的形状在这里
      FMT = format_for_mode(MODE)
      有 cookie 时：
         raw_c = dump_once(带 cookie)
         probe_raw(raw_c) 通过 ─────────────► emit_stream(raw_c, retried=0)   # 例如登录门后的视频
         否则 raw_a = dump_once(匿名 + android client)
              probe_raw(raw_a) 通过 ────────► emit_stream(raw_a, retried=1)
         两边都取不到，但带 cookie 那次解析成功 ► emit_stream(raw_c, 0)
                                                 # 保留 cookie，让 mpv 去吐真错误与真退出码
         都不成 ────────────────────────────► resolve_fail(rc)
      无 cookie（YT_COOKIE_BROWSER=none，或本机没有该 profile）：
         无从权衡，所以也不探 —— dump_once(匿名) → emit_stream(raw_a, 0) 或 resolve_fail
```

soft ref：`shell/yt-resolve` 的 `resolve_stream()` / `dump_once()` / `probe_raw()` /
`have_probe_tools()` / `emit_stream()`。**播放器一侧没有对应函数** ——
探测早在拆分时就整体搬进了引擎，任何还在 `ut-play` 里找 `play_url_with_probe` 的描述都是过期的
（这份文档在切出来时原样继承了那段过期伪码，这里按真代码改正）。

实现要点：`local COOKIE_ARGS=()` 借 bash 的动态作用域遮住全局量，
于是那一次解析可以丢掉 cookie 而不碰真正的设置；裁决以 `retried` 出现在**解析**信封里，
`ut-play` 把它**转述**进播放信封的 `retried`，而不是自己去观察（AS-BUILT-contract.md §3）。
代价：每次播放多一次解析 + 一个 1 字节 GET（cookie-403 的视频是两次）。
`curl` 是软依赖 —— 没有它就跳过探测、走回老的"播-失败-重播"（错误糊屏的回归也只在那条路上出现）。
`YT_COOKIE_BROWSER=none` 强制只走匿名（不读钥匙串、不探测）；
配了浏览器但本机没有 profile 时自动降级为匿名，而不是报错。

**这个决定是可查询的，靠 `--auth`（AS-BUILT-contract.md §3）。** 上面那两句里藏着一件
调用方看不见的事：cookie 究竟会不会被送出去，取决于**两个**条件 —— 变量不是 `none`，
**并且**那个 profile 目录真的在这台机器上。降级是静默的（那是对的：一个公开视频照样能放），
于是"我以为我登录着"和"这次是匿名的"在外面长得一模一样。`--auth` 就是把这两个条件的合成
结果印出来的那个动词，不吃句柄、不发包、不跑 yt-dlp。

**它报的是"发不发"，此外什么都不报 —— 而"此外"是两件事，不是一件。**
`auth:"cookie"` 之后还有两个独立的问号：站点**认不认**这份会话（过期登录照样报 `cookie`），
以及认了之后这个账号**够到什么**。两个都不在这个动词的射程内。
`retried` 也不是登录裁决：`retried:false` 说的是带 cookie 那次调用没有出错，仅此而已。

**本机实测 2026-08-26，而这组数字支持的是第二个问号，不是第一个。**
`yt-dlp --cookies-from-browser chrome` 从 chrome 提取到 **3159 个 cookie**；
那个 profile 经浏览器确认**是登录状态**；而 B 站给出的音频档位与匿名**完全一致**
（30216 / 30232 / 30280，顶格 181 kbps AAC；Hi-Res 30251 与 Dolby 30250 根本不在
format 表里），视频 format 表两边逐项相同，`1080P 高码率`（30112）带着 cookie 同样拿不到 ——
因为那个账号**不是大会员**。所以一次被**接受**的登录，在这个视频上与"根本没登录"
在外面看长得一模一样。

这条测量的用处正在这里：**音质永远不能用来反推这个字段，这个字段也永远不能用来预测音质。**
第一个问号（过期会话）是真实的设计关切，但**上面这组数字没有量到它** ——
量到它需要一次鉴权往返，这个套件刻意不做（ROADMAP D16）。

## 10. 解析 —— 引擎的第二半

`<engine>-resolve` 把一个**句柄**变成播放它所需的一切，并承载该站点的只读动词。
它从不播放：没有 mpv、没有生命周期、没有 `players/`。

```
   <engine>-resolve [-f MODE] [-S SORT] [-j|-J] -- <handle>   流 URL + 请求头
   <engine>-resolve --info [-j|-J] -- <handle>                只要元数据
   yt-resolve --transcript [--sub-lang L] [-j|-J] -- <handle> 字幕，清洗成纯文本
```

**句柄文法是每引擎自己的，host 白名单也是（ROADMAP D12）。** `normalize_target` 接受
**本**引擎某个 host 上的 URL，或者本引擎自己的媒体 id 形状：

| 引擎 | 接受的 host | 裸 id 形状 |
|---|---|---|
| `yt-resolve` | `youtube.com`、`youtu.be`、`youtube-nocookie.com` 及其子域 | 恰好 11 个 `[A-Za-z0-9_-]` |
| `bili-resolve` | `bilibili.com`、`b23.tv` 及其子域 | `BV…` / `av…` |

用的是**显式清单，不是子串匹配**：`*.youtube.com` 命中 `music.youtube.com` 而拒绝
`evilyoutube.com`，后者会被一个光秃秃的 `*youtube.com*` 放过去。

**来自另一个站点的 URL 是用法错误（1），不是抽取失败（2+）。** 什么都还没试、也没有什么可重试的
—— 调用方点错了引擎，这与 `--engine nope` 是同一个错误，因此记同样的分。这堵上了一个**能用**的
洞，而"能用"正是这一类洞难被看见的原因：没有白名单，任何 http(s) URL 都会被交给 yt-dlp
（1700+ 个支持站点），于是一条 Bilibili URL 经 `yt-resolve` 也解得好好的，
回来时贴着 `engine:"yt"` —— 在那个整份工作就是"把结果路由回懂它的解析器"的字段上撒谎。
代价如实记下：那些"只靠 URL"的源（Bandcamp、Apple Podcasts）放不了 —— 它们**意外**能播过 ——
而它们的修法是给它们写一对自己的引擎，绝不是放松 host 校验。

```
   resolve_stream(handle)                       # 光秃秃的那个动词 —— ut-play 调的就是它
      yt-dlp --dump-single-json --no-playlist -f <format_for_mode(MODE)>
             [--format-sort SORT] [--cookies-from-browser B]
      → 探测（仅 yt，§8.2 是它完整的形状）可能匿名重解一次并把 retried 置上
      prose: 打印流 URL
      -j:    {status,engine,id,url,title,duration,mode,format,stream_urls[],http_headers{},retried}
      -J:    yt-dlp 的完整原始记录
      error: {status:"error",engine,url,mode,reason}，退 2+
```

`stream_urls` 是**视频在前**：元素 0 是播放器要打开的那个，元素 1 —— 只有当选中的格式合并了
两条流时才有 —— 是它单独的音轨。`http_headers` 是**必需的，但可以是 `{}`**。
完整 schema 与这两条的理由：AS-BUILT-contract.md §3。

### 10.1 只要元数据（`--info`）

只读、不阻塞、无副作用；要 yt-dlp+jq，但永远不要 mpv。**两个引擎都有它。** 它存在的理由：
没有它的话，一个想知道某个视频*是什么*（描述、章节、上传者、日期、点赞数）的 agent，
就得离开这套生态、掉回原始的 `yt-dlp --dump-json` —— 与 JSON 搜索面当初消除的是同一种
"逃生口"失败。这是 LLM 优先而不是人体工学（对照被否掉的 `--url-only`，那个是**剥掉**接地信号）：
`--info` 是**增加** agent 推理所依据的接地。`duration_fmt` 来自引擎自己 `JQ_PRELUDE` 里的
`fmt_dur`（§7），所以在一个引擎内部，`--info` 与搜索在格式上不可能漂移 ——
而且时长未知时它是 `null`，不是 `"00h:00m:00s"`。

```
   resolve_info(handle)
      yt-dlp --dump-single-json --skip-download
             [--cookies-from-browser B]   # 只有选择了登录时才有
             --no-warnings --quiet
      prose: 可读段落（标题/频道/日期/时长/播放/点赞/直播/URL，
             然后 Chapters M:SS，然后 Description）        （失败即 die）
      -j:    精瘦、高信噪比的投影，与搜索 -j 的字段纪律一致：
             {status,engine,id,title,url,channel,uploader,upload_date,duration,duration_fmt,
              view_count,like_count,live_status,description,chapters}
             chapters = [{start_time,end_time,title}] | null
      -J:    完整原始 yt-dlp 记录（保真逃生口，与搜索 -J 同一角色）
      error: -j/-J → {status:"error",engine,url,reason} 退 1；prose → die
```

`bili-resolve --info` 用 `.channel // .uploader` 来填 `channel`，因为那个 extractor 按记录
只填其中之一 —— **信封的形状不得取决于是哪一个**。这是对一个引擎的通则：
**归一化到契约，绝不把 extractor 的方差原样发布出去。**

### 10.2 字幕（`--transcript`）—— 一个 `bili-resolve` 没有的动词（D13）

`yt-resolve --transcript` 取一条字幕轨，并把它清洗成可以直接丢进 prompt 的文本。信封、
`-j`/`-J` 的分工，以及"只许一次 yt-dlp 调用"的约束：AS-BUILT-contract.md §3，
`no_subtitles_available` 这个 reason 也规定在那里。

**Bilibili 不供字幕，所以 `bili-resolve` 根本没有 `--transcript`** —— 这个 flag 不被接受，
帮助里也不列它。这是"能力规矩"的微观版：**一个引擎靠"没有那个动词"来说明自己做不到什么**，
而不是发布一个永远答"没有"的动词 —— 后者让调用方分不清它与"今天不走运"或"被限流了"。
