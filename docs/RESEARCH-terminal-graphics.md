# RESEARCH-terminal-graphics —— 终端里显示图片：协议、国内同路项目，以及不加依赖能走多远

> **这份调研只回答一个被问出来的问题**：国内前沿的终端播放器怎么在终端里立刻显示图片
> （封面、缩略图、GIF），源里带图的时候他们怎么处理 —— 以及**本仓在"永不新增运行时依赖"
> 这条硬规则下，这件事能走到哪一步**。
>
> 它是 `RESEARCH-tui-player.md` 的一次定点补测，不是它的续集：那份调研在
> 「领域现状」里把"图形协议封面"归到了**别人为拿用户在卷、而"工作时放点音乐"零价值**的那一档，
> 但**没有量过成本**。零价值 + 未知成本无法支撑一条记录在案的 NO，这份文档补的就是成本那一栏。
>
> **两半，分界线是可信度：**
> - **实测那半 —— 「不加依赖能走多远」与「像素从哪来」**：全部在本机跑出来的字节数与
>   选项清单，命令与日期见下表，可以照着重跑。
> - **读的那半 —— 「协议这层已经收敛」「复用器是主要卡点」「国内同路项目」**：网络检索 +
>   一手 README / issue / man page，**读结论不如读出处**。
>
> 由它落定的决定：`ROADMAP.md` 的**图片不走 mpv 的 VO NO**。
> **这条 NO 否的是路线，不是功能**：贵的是 mpv 的 VO，不是"在终端里显示图片"这件事
> （见「但 mpv 不是唯一的路」）。

---

## 时效、方法与诚实边界

| 内容 | 日期 | 怎么来的 |
|---|---|---|
| 协议这层已经收敛 | 2026-09-01 | **读的** —— 各终端文档、chafa(1)、ratatui-image README、协议综述 |
| 复用器（tmux）这一卡点 | 2026-09-01 | **读的** —— tmux issue #4902、kitty discussion #8400；本机 tmux 版本号是实测 |
| 国内同路项目 | 2026-09-01 | **读的** —— 各项目 README 与 issue 原文 |
| **不加依赖能走多远** | **2026-09-01** | **实测** —— 本机 mpv v0.41.0（Homebrew）、tmux 3.7c、macOS 15 |
| **像素从哪来** | **2026-09-01** | **实测** —— 读本仓源码 + `mpv --list-options` |

实测那半的宿主写死在这里，否则数字没法读：**macOS，Homebrew 的 mpv v0.41.0，
tmux 3.7c，`TERM=xterm-256color`**，本机 `chafa` / `img2sixel` / `imgcat` / `viu` /
`timg` / `ueberzugpp` **一个都没装** —— 最后这条本身就是一个数据点：这些东西没有一个是
"用户机器上本来就有"的（对照本仓五个依赖的选取标准，`ARCHITECTURE.md`「定位与设计目标」）。

---

## 协议这层已经收敛（读的）

外面没有"新技术"，只有一条已经定型的优先级链：**Kitty graphics > iTerm2 inline >
Sixel > Unicode 半块 / ANSI 符号**。前三个是真像素，最后一个是兜底。

- **Kitty graphics protocol** —— 目前唯一同时给出高保真（32-bit RGBA）、流式传输、合成、
  **图像 id + 虚拟引用（传一次画多次）**、动画帧与 z-layer 的协议。Ghostty、WezTerm、
  Konsole 都实现了。它的 Unicode placeholder 放置模式让图像能参与文本布局与 scrollback ——
  这一条是"能不能做成 TUI 里的一个 widget"的关键。
- **Sixel** —— 1980 年代 DEC 的遗产，铺得最广，但保真度与体积都差一档。
- **iTerm2 inline images** —— iTerm2 与 WezTerm。
- **半块兜底** —— 用 `▀` 加前景/背景色，一格顶两个像素。任何终端都能画。
- **Alacritty 三个都不支持**（这是"必须有兜底"的原因，不是一个可以忽略的小众情况）。

工具层同样只有几个，全部是**外部程序或库**，没有"标准库里就有"的形态：
`chafa`（吃 JPEG/PNG/GIF/AVIF/SVG/WebP/TIFF/JPEG XL，`--animate` 直接放动图，
输出格式 `iterm|kitty|sixels|symbols` 自动探测）、`ratatui-image`（Rust widget，
sixel/kitty/iterm2/halfblocks，并会**向终端查询字体的像素尺寸**）、
`Überzug++`（Linux 上把真图覆盖在终端窗口之上，质量最好，但要 X11/Wayland）。

---

## 复用器（tmux）是这条路的主要卡点（读的）

- **Kitty 协议在 tmux 里要靠 DCS 透传**：`set -g allow-passthrough on`，外层还得是支持
  TGP 的终端。**开了也不一定通** —— kitty 自己的 discussion #8400 与 tmux issue #4902
  都是这个题目，问题出在 DCS 透传层本身。
- **Sixel 在 tmux 里要编译期开关**：`./configure --enable-sixel`，3.4 起原生。
- **zellij 更窄**：yazi 的适配层在 zellij 会话里只允许 sixel，在 tmux 会话里排除分块上传类协议
  —— 一个成熟实现被迫写死的这张矩阵，就是这层复杂度的度量。

**对本仓的直接后果**：`tests/contract.sh` 的 TUI 启动检查和 `tests/drive.sh` 全在 tmux 里跑。
也就是说图片这条路**在本仓的验证环境里默认是瞎的** —— 不是 bug，是既定事实，
它意味着任何图片功能都拿不到本仓其余部分那种"跑一遍就证明了"的覆盖。

---

## 国内同路项目怎么做的（读的）

| 项目 | 栈 | 图片这件事 |
|---|---|---|
| **MareDevi/bilibili-tui** | Rust / Ratatui | **做了，而且是最接近本仓的那个对照物**：搜索列表里直接出封面，自动探测 **Kitty / Sixel / iTerm2**，其余降级 ASCII；播放走**外部 mpv + yt-dlp**。分层与本仓同构 |
| **sxyazi/yazi** | Rust | 不是播放器，但**适配层是这条路的天花板**：Kitty / iTerm2 / Sixel 原生 + Überzug++ + chafa 兜底，按终端**和复用器**选后端，还带视频抽帧与 GIF |
| **go-musicfox** | Go / Bubbletea | **提过，被否了。** issue #312（2024-08）请求在播放页右侧显示封面，请求里已经写好了方案（Unix 用 kitty、macOS 用 iterm2、Windows 用 chafa 转字符）—— 维护者 **closed as not planned**，无 PR、无版本 |
| **teee32/biliterminal** | Python / curses | 列表**没有缩略图**，自述原因是"curses 终端没有图片和瀑布流组件"；只有 `V` 键把当前视频整段放成 ASCII 画面 |
| **404name/bilibili-terminal** | Go / termui | 同步拉图 + 音频，早期实验性 |

**两条要看清的**：

1. **国内做成了的只有一个**（bilibili-tui），而它是 Rust + 一个现成的图像 widget 库
   （`ratatui-image` 那一层），**图片能力是库给的，不是它自己写的**。
2. **规模最大的那个国内同行主动否掉了这件事**（go-musicfox，`RESEARCH-tui-player.md`
   「领域现状」量到 2513★）。一个 Go 项目、有 Bubbletea、有现成的 chafa 可调，
   拿到一份写好方案的 issue，仍然判定不值得做 —— 这是本轮最强的一条外部证据。

---

## 不加依赖能走多远：mpv 本身就是一个终端图形后端（实测，2026-09-01）

这是本轮唯一的好消息，也是唯一被真正量过的一段。

**mpv 已经是本仓的依赖，而它自带终端图形输出。** 本机 `mpv --vo=help`：

```
  tct     true-color terminals
  kitty   Kitty terminal graphics protocol
```

**`sixel` 不在** —— 且原因可核对：Homebrew 的 mpv formula 的依赖列表里没有 `libsixel`
（`brew info --json=v2 mpv`）。所以在 macOS 上，"零新依赖"的图形后端**只有 kitty 与半块两档**，
sixel 这一档要用户自己重编 mpv，等价于一个新依赖。

`--list-options` 里这一族比想象中完整 —— 它有**格子级放置**：

```
  --vo-kitty-cols / --vo-kitty-rows / --vo-kitty-left / --vo-kitty-top
  --vo-kitty-width / --vo-kitty-height / --vo-kitty-use-shm
  --vo-kitty-auto-multiplexer-passthrough   (Flag, default: no)
  --vo-tct-width / --vo-tct-height / --vo-tct-algo / --vo-tct-256
```

`--vo-kitty-auto-multiplexer-passthrough` 尤其值得记：**mpv 自己带了复用器透传**，
上一节那条卡点它至少给了一个开关。

### 但它是一个 VO，不是一个 widget —— 这是决定性的一条

把一帧的输出重定向到文件再看字节流，一个 320×180 的源帧（`av://lavfi:testsrc` 生成，
不走网络），`--vo=kitty --vo-kitty-cols=24 --vo-kitty-rows=7 --vo-kitty-alt-screen=no --frames=1`：

```
\e[?25l          藏光标
\e[?1003h        开启鼠标上报          ← 抢输入
\e_Ga=d;\e\      删除所有已传图像
\e[2J            清整屏                ← 抢屏幕（alt-screen=no 也照清）
\e[0;0f          光标归位
\e_Ga=T,f=24,s=320,v=180,C=1,q=2,m=1;AAAA…   图像本体
```

**它要整块屏，还要走鼠标上报**。`uting` 自己拥有终端（自绘、自管 echo 与光标、
逐键重绘），把一个会 `\e[2J` 的 VO 塞进一行里是不可能的 —— 这不是调参能绕开的，
VO 的语义就是"整个显示面归我"。

### 载荷的量级也不成立

| 显示格子 | `--vo=kitty` | `--vo=tct` |
|---|---:|---:|
| 默认（不指定） | 461,960 字节 | 125,864 字节 |
| 24×7 格 | **461,951 字节** | 12,480 字节 |

**kitty 那一列与格子大小无关**，因为 kitty 协议传的是**原图**，缩放交给终端做；
tct 那一列随格子缩，因为半块是在 mpv 这边栅格化的。

再看载荷本身：一帧 = **1 次传输、112 个 4096 字节分块**，`f=24` 是**未压缩 RGB**，
而且 **没有 `i=`（图像 id）** —— 也就是拿不到 kitty 协议最值钱的那个特性
"传一次、画多次"，每一帧都是整幅重传，前面还跟一个 `a=d`（删除所有）。

**于是每行一张缩略图，走这条路在字节上就先死了**（下一节的手写路线便宜得多，但也没便宜到能每行一张）：一屏 20 行 ≈ **9MB 一次重绘**，
而实时过滤是**逐按键重绘**。对照下一节自己量的数字：**整整 10 秒的全动态视频**
走 half-blocks 才 7.3MB。一次静态列表重绘要一整段视频的量级，这个比例不需要再讨论。

### `--vo-tct-algo`：省一半字节，买一个糊的边（实测，2026-09-01）

同一首曲子、同一个 120×30 pane、10 秒 viz，两种 algo：

| `--vo-tct-algo` | CPU（10s） | 写出的转义序列 | 纵向级数 |
|---|---:|---:|---|
| `half-blocks`（出厂） | 0.69s | 7.3 MB | `rows × 2`，1:1 不缩放 |
| `plain` | 0.64s | 3.6 MB | `rows × 1`，mpv 要降采样 |

**字节省一半、CPU 一样**，所以它看起来是白拿的。把柱顶放大看就知道代价不在"格子粗一倍"：
画布是按半格算的 `rows × 2`，而 plain 只吃 `rows × 1`，于是 mpv 降采样、柱顶被混成一格
半亮的青；half-blocks 是 1:1，边缘是硬的。而省下的那 370KB/s 本来就不是瓶颈 ——
这就是 `ROADMAP.md`「`--vo-tct-algo=plain` NO」拒掉它的那笔账。

### 但 mpv 不是唯一的路 —— 自己发协议（实测，2026-09-01）

**上面那两条都是 mpv 的属性，不是这条路的属性。** kitty 协议是一段转义序列，
谁都能发；而发它需要的两件工具本机都在 `/usr/bin` 里：

```
/usr/bin/base64      /usr/bin/fold
```

**这不是新依赖** —— 两个都在 POSIX 工具箱里、macOS 与 Linux 同在，
性质与本仓已经在用的 `awk`/`sed` 相同（对照五个真依赖的清单：yt-dlp、jq、mpv、nc、curl）。
而**图片本身用已有的 `curl` 取**。

关键差别在于协议的 `f=` 参数，**而这里有一个反直觉的限制**：终端只需理解**三种**格式 ——
`f=24`（RGB）、`f=32`（RGBA，默认）、`f=100`（**PNG，仅 PNG**）。规范的设计原则明写
"不应要求终端理解图片格式"，**格式转换是客户端的活**。**JPEG 不在其中。**

**而两个站点发的都不是 PNG** —— 并且**扩展名会骗人**：实测一条真 YouTube 缩略图 URL
以 `.jpg` 结尾，服务器返回的 `Content-Type` 是 **`image/webp`**。

于是要么放弃这条路，要么找一个不新增依赖的解码器。**解码器已经装着了：mpv。**
用 `--vo=image` 把它当**转码器**而不是 VO —— 它输出一个文件，
**一个转义序列都不发**，那两条"抢屏幕、抢鼠标"的毛病与这个用法无关。

```
curl ──► 字节流 ──► mpv 解码 + 缩放（--vo=image） ──► PNG ──► base64 | fold ──► \e_G… f=100
```

**同一张真 YouTube 缩略图，实测（2026-09-01）**：

| 路线 | 载荷 | 4096 分块 | 什么时候付 |
|---|---:|---:|---|
| `mpv --vo=kitty`（`f=24`，未压缩） | 461,951 字节 | 112 | **每一帧** |
| 手写 `f=100`，转码不缩放 | 170,888 字节 | 42 | 每张一次（可缓存） |
| **手写 `f=100`，先缩到 192px 宽** | **52,012 字节** | **13** | **每张一次（可缓存）** |

转码本身 **0.11s**。**8.9 倍** —— 但真正的差距不在这个倍数上，在最后一栏：VO 那条**每帧重传**，手写这条**每张一次**，且 `i=`（图像 id）还能让同一张图
**传一次、画多次**。

三个"走不通"的理由里，**只有第三个（复用器）对手写路线仍然成立**：

| 上面的理由 | 对 mpv VO | 对手写发射器 |
|---|---|---|
| 抢屏幕（`\e[2J`）、抢鼠标（`\e[?1003h`） | 成立 | **不成立** —— 只发 `\e_G…`，一个 CSI 都不发 |
| 载荷量级 | 成立（462KB **每帧**） | **不成立**（52KB **每张一次**） |
| 复用器（tmux）要 DCS 透传且常不通 | 成立 | **同样成立** |

**bash 3.2 那一侧也不构成阻力**：`base64 | fold -w 4096` 出来只有 13 行，
读 13 行没有任何二次方风险（对照 `ARCHITECTURE.md`「可移植性契约」里 `${var//}` 那条）。

**所以这一节的结论要写清楚，别被前两段带偏**：**贵的是 mpv 的 VO，不是这条路。**
真正剩下的代价是**终端能力探测 + 复用器 + 图像的生命周期**（`uting` 逐键重绘，
而 kitty 图像不会被 `\033[K`/`\033[J` 擦掉，必须显式 `a=d`）—— 那是工程量，不是墙。

**探测这件事本仓已经有先例**：`shell/uting` 的 OSC 11 背景色查询就是同一个形状 ——
发一段查询、用 `read -rsn1 -t 1` 逐字节收回复、**在 tmux 下直接跳过**、
并把"一次未应答的探测花 1 秒"这个代价写在注释里。TGP 的能力查询
（`\e_Gi=<id>,s=1,v=1,a=q,t=d,f=24;<1px>\e\` → `\e_Gi=<id>;OK\e\`）可以照抄这个形状。

### 已经能用、但没人量过的那一格

`YT_ASCII_VO` 已经是一个配置键（出厂 `tct`），`ut-play` 用 `mpv_supports_vo` 在门口把关，
源码注释里明写"指到 sixel 或 kitty 的用户不受影响"。本机 mpv 支持 kitty，
**所以 `YT_ASCII_VO=kitty` 的 viz 今天就能跑** —— 这一格不需要做任何事，
只是从未被量过（本轮也没量：本机终端不支持 TGP，看不到画面，见下面的问号）。

---

## 像素从哪来：`-J` 里已经有了（实测，2026-09-01）

一个先入为主的判断在这里被推翻了：**缩略图 URL 不是契约缺口。**

- `yt-search` 的 `emit_search_json` 注释直接点名：`-j` 精简掉的那 ~23 个原始字段里
  就有 **thumbnail arrays**，而 **`-J`（`OUTPUT_MODE=json_full`）保留全部原始字段**。
- `bili-search` 的 jq 是把规范化字段 **merge 在原始记录之上**（源码注释写明这是为了
  "`-J` keeps every field the site sent"），所以站点的 `pic` 字段**原样留在 `-J` 里**。

也就是说：真要做图片，**引擎侧一个字节都不用改，两个引擎的 `-J` 现在就交得出图片 URL**。
成本全部在渲染那一侧 —— 这恰好是上一节证明走不通的那一侧。

---

## 本轮没能确定的问号

诚实记下来，免得下一轮重复踩：

1. **`--vo-kitty-auto-multiplexer-passthrough=yes` 在 tmux 里到底通不通**，
   以及通了之后 `\e[2J` 会不会被 tmux 限制在本 pane 内 —— 本机终端不支持 TGP，无法验证。
   **这是最该先补的一条**，因为它是"mpv 的 kitty VO 能不能只占一个 pane"的唯一希望。
2. **`--vo-kitty-use-shm=yes` 是否让载荷降到共享内存句柄那个量级**，从而推翻上面的字节结论。
   同样受限于本机终端。
3. **kitty 协议的图像 id / 虚拟引用（传一次画多次）mpv 有没有暴露** —— 观测到的载荷里没有
   `i=`，但没有读 mpv 源码确认这是"没实现"还是"本次路径没走到"。
4. **bilibili-tui 的封面到底是每行一张还是只有焦点行一张**，以及它的重绘频率 ——
   只读了 README，没装起来跑。这一条直接关系到上面那个 9MB 的推算对不对。
5. **手写发射器产出的 PNG，真终端到底收不收** —— 本机终端不支持 TGP，
   整条管线只量到了字节，没量到像素。这是 `PLAN-terminal-thumbnails.md` A 阶段的前置。
6. **iTerm2 inline images 的载荷量级**（它是 base64 的 PNG，可能比 mpv 的未压缩 RGB 小一个量级）
   —— 但它不是 mpv 能发的协议，要发就要自己写发射器，所以本轮没量。

---

## 出处

**协议与工具**
- **Kitty graphics protocol 规范本身**（`f=24/32/100` 与"不要求终端理解图片格式"的设计原则）：https://sw.kovidgoyal.net/kitty/graphics-protocol/
- Kitty graphics protocol 的终端支持面：https://terminfo.dev/extensions/kitty-graphics-protocol
- 协议综述（kitty / sixel / iterm2 的取舍）：https://akmatori.com/blog/terminal-graphics-protocols
- Sixel 支持面追踪：https://www.arewesixelyet.com/
- chafa 官网与 man page：https://hpjansson.org/chafa/ · https://man.archlinux.org/man/extra/chafa/chafa.1.en
- ratatui-image：https://github.com/ratatui/ratatui-image
- 协议探测（环境变量法）：https://github.com/sindresorhus/supports-terminal-graphics
- 终端里显示图片的方法总表：https://github.com/o2sh/onefetch/wiki/Images-in-the-terminal

**复用器**
- tmux issue #4902（kitty image protocol）：https://github.com/tmux/tmux/issues/4902
- kitty discussion #8400（tmux / neovim / 图形协议）：https://github.com/kovidgoyal/kitty/discussions/8400
- yazi 的协议选择矩阵：https://deepwiki.com/sxyazi/yazi/6.2-image-rendering-protocols

**国内同路项目**
- MareDevi/bilibili-tui：https://github.com/MareDevi/bilibili-tui
- sxyazi/yazi：https://github.com/sxyazi/yazi
- go-musicfox issue #312（closed as not planned）：https://github.com/go-musicfox/go-musicfox/issues/312
- teee32/biliterminal：https://github.com/teee32/biliterminal
- 404name/bilibili-terminal：https://github.com/404name/bilibili-terminal

---

## 怎么重跑这份调研

**实测那半**（成本：几分钟，不走网络）：

1. `mpv --vo=help` —— 这台机器上有哪几档终端 VO。**sixel 的有无是宿主属性，不是 mpv 属性**，
   要一起记下 mpv 是怎么装的。
2. `mpv --list-options | grep -i 'kitty\|tct'` —— 放置与透传选项有没有变。
3. 用 `mpv "av://lavfi:testsrc=size=320x180" --frames=1 --vo=image` 造一帧（**不要用网络图片**，
   否则量到的是别人的 CDN），再把 `--vo=kitty` / `--vo=tct` 的输出**重定向到文件**数字节：
   这就是上面那张表。分块数用 `grep -o $'\033_Gm=[01]' | wc -l`。
4. **看字节流的头 200 字节**（`od -c`）—— 那里才写着它抢不抢屏幕、抢不抢鼠标。
   这一步比字节数更重要：它决定的是"能不能做成 widget"，而字节数只决定"值不值得"。
5. **手写路线要量的是转码后的 PNG，不是源图** —— 先确认协议这一版的 `f=100` 还是不是
   只收 PNG（读规范，别猜），再
   `mpv <源图> --frames=1 --vf=scale=192:-2 --vo=image --vo-image-format=png`，
   然后 `base64 | tr -d '\n' | wc -c` 数 base64 字符、除以 4096 算块数。
   **一定要用一张真的照片类缩略图**：合成测试图（testsrc）的 PNG 压缩率高得离谱，
   量出来会比真实情况乐观好几倍。

**读的那半**：直接读一手 README 与 issue，尤其是**被关掉的 issue** ——
go-musicfox #312 的价值全在那个 "closed as not planned" 上，任何综述文章都不会告诉你这件事。
