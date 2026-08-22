# PLAN-yt-low-cost-agent-tooling — Low-Cost Agent-Native Tooling Surface 补齐方案

> 状态：已实施 (2026-08-22)。契约与设计理由已并入 `docs/DESIGN.md` §12/§13/§14/§15/§27。  
> 关联设计：`docs/DESIGN.md` · `docs/ROADMAP.md`  
> 约束基线：**Zero-New-Deps / Zero-Build**，严格兼容 macOS 系统原生 **Bash 3.2**，仅依赖 `yt-dlp`、`mpv`、`jq`、`nc`。

---

## 1. 目标与定位 (Objective & Scoping)

在 `uting` 架构的 **人机双驱动（Dual-Surface）** 体系下，`yt-search` 与 `yt-play` 作为面向 AI Agent 与自动化脚本的 ACI（Agent-Computer Interface）表面，当前已在搜索过滤、单曲直链解析、异步 Detached 播放与进程隔离退出上做到了 85%+ 的闭环。

本项目旨在以 **极低代码增量（Low-Cost Shell Patching）** 补齐剩余的 ACI 盲区：

1. **内容理解与字幕提取**：补充 `--transcript`（`--subtitles`），让 Agent 无需手写复杂 `yt-dlp` 爬虫即可直接完成视频内容总结与知识提炼。

### Non-Goals（边界收敛）

- 不做多曲队列管理、本地音乐库扫描与播放历史持久化（遵从 `ROADMAP.md §0`，保持 Agent YouTube 原语的纯粹性）。
- 不引入 Python/Node 中间件，所有数据流转与清洗在 `shell/yt`（Core）中通过 `jq` 与管道完成。
- **不把 `--pause` / `--resume` / `--toggle-pause` / `--seek` 做成动词**（`DESIGN.md §26`）—— 待决，见 §5。

---

## 2. 接口契约规范 (Interface Specification)

所有扩展均严格继承现有设计模式：**核心逻辑只在 `shell/yt` 实现一次；`shell/yt-play` 负责参数门禁与提示重定向；`-j` 模式输出紧凑单行 JSON；显式返回 Exit Code（0 成功，1 错误，4 状态不适用）。**

### 2.1 视频字幕与文字稿提取

```bash
yt-play --transcript [--sub-lang LANGS] [-j|-J] <URL>
```

- **参数行为**：
  - 优先拉取人工精校字幕（Subtitles），缺省时自动回退到自动生成字幕（Auto-generated CC）；
  - `--sub-lang` 是**优先级候选链**：缺省 `en,zh-Hans,zh,ja`，取视频实际拥有的第一个；支持显式指定如 `--sub-lang zh-Hans,en`。改名自初版的 `--lang`，避免与 `YT_LANG`（TUI 界面语言）同名不同义；`--subtitles` / `--sub-langs` 为别名；
  - `--transcript` 为纯元数据只读查询，**不触发播放**，与 `-d` 互斥。

#### 输出契约

- **文本模式（默认）**：
  直接输出去除了 VTT/SRT 时间轴、样式标签和滚动重叠行的纯净段落文本，Agent 可直接放入 Prompt 进行总结。
- **精简 JSON 模式 (`-j`, exit 0)**：
  ```json
  {
    "status": "ok",
    "id": "dQw4w9WgXcQ",
    "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "lang": "en",
    "is_auto": false,
    "chars": 2287,
    "segment_count": 60,
    "text": "Full deduplicated clean transcript text..."
  }
  ```
- **高保真 JSON 模式 (`-J`, exit 0)**：同一 envelope **加上** `segments`，即 `-j` 的严格超集
  ```json
  {
    "...": "-j 的全部字段",
    "segments": [
      { "start": 0.0, "duration": 3.5, "text": "Never gonna give you up" },
      { "start": 3.5, "duration": 2.1, "text": "Never gonna let you down" }
    ]
  }
  ```
  `segments` 不进 `-j`：它与 `text` 装的是同一份文字。实测 444 段的轨上，完整 envelope 52,732 字节，
  其中 `text` 16,916、`segments` 35,647 —— 后者重复承载同一份文字再加时间轴。`-j` 因此落到 17,074
  字节、**缩减 3.1 倍**，对"拿去总结"这个本动词存在的用途零信息损失。这是 `DESIGN.md` §22
  token-efficiency 那一行的要求，也是 `-J` 在本套件其他地方一直遵守的关系：**同一 envelope 的超集，
  而不是换一种文档**（初版把 `segments` 放进 `-j`、把 raw json3 当 `-J`，两者都是 P0 冻结契约时
  必须返工的形状）。`chars` / `segment_count` 让精简形态自带尺寸信息：调用方能预算上下文，也知道
  `-J` 会多给什么，不必先取一遍。
- **无可用字幕 / 网络异常 (`exit 1`)**：
  ```json
  { "status": "error", "url": "...", "reason": "no_subtitles_available" }
  ```

---

## 3. 架构设计与改动清单 (Implementation Architecture)

### 3.1 `shell/yt`（核心引擎）

1. **文字稿解析器 (`resolve_transcript`)**：
   - 一次 `yt-dlp` 调用同时落盘字幕与拿到描述它所需的元数据：
     ```
     yt-dlp --skip-download --no-simulate --write-subs --write-auto-subs \
            --sub-langs "$langs" --sub-format json3 \
            --print "%(id)s" --print "%(subtitles)j" \
            -o "$dir/%(id)s.%(ext)s" --no-warnings --quiet "$url"
     ```
   - `--no-simulate` 是必需的：`--print` 隐含 `--simulate`，而 simulate 状态下 yt-dlp **不写任何字幕文件**。初版方案里的 `--dump-json` 有同样的隐含，因此那条命令跑不出字幕 —— 这是本方案唯一一处真正的实现修正。
   - 只 print `%(subtitles)j`（人工字幕字典，单行 ~15KB）用于判定 `is_auto`；`automatic_captions` 含机器翻译时可达 940 种语言 / 3.2MB，刻意不取。
   - `--sub-format json3` 让清洗保持为一段 `jq` 程序（`JQ_TRANSCRIPT`）：json3 的时间轴已是结构化字段，VTT/SRT 则需要一个时间轴解析器。三种要丢弃的形状（首个窗口定义事件、自动字幕的 `aAppend` 滚动重叠、行内样式标签）由"清洗后文本为空"这同一个过滤器一并吃掉。
   - 字幕落在 0700 的 state dir 下的临时目录，单个 EXIT trap 负责清理。
2. **参数路由（Long-Opt & Routing）**：
   - 在 long-opt 规范化循环中注册 `--transcript`、`--lang`。

### 3.2 `shell/yt-play`（门禁包装层）

- 更新白名单，放行新增 Flags；
- 拦截 `--transcript` 与播放 Flags（如 `-f`, `-d`, `--volume`）的非法组合；
- 更新 `-h` / `--help` 说明与示例。

### 3.3 文档同步

- 更新 `docs/DESIGN.md` 中对应的 ACI 合约章节。

---

## 4. 验证与测试矩阵 (Verification Plan)

| 测试项                | 触发命令                                                      | 预期结果                                                            |
| :-------------------- | :------------------------------------------------------------ | :------------------------------------------------------------------ |
| **语法检查**          | `bash -n shell/yt shell/yt-play shell/yt-search shell/yt-tui` | 0 报错，符合 Bash 3.2 规范                                          |
| **字幕提取 (纯文本)** | `yt-play --transcript <URL>`                                  | stdout 输出无时间轴的纯文本，stderr 无污染                          |
| **字幕提取 (JSON)**   | `yt-play --transcript -j <URL>`                               | 精简 envelope（含 `chars`/`segment_count`，无 `segments`）          |
| **字幕提取 (超集)**   | `yt-play --transcript -J <URL>`                               | 同一 envelope 加 `segments`；`del(.segments)` 与 `-j` 逐字段全等    |
| **字幕缺失容错**      | 对无字幕视频执行 `yt-play --transcript -j <URL>`              | Exit 1，返回 `{"status":"error","reason":"no_subtitles_available"}` |

---

## 5. 待决事项 (Pending)

- **运行时 IPC 播控动词**（`--pause` / `--resume` / `--seek`）—— 阻塞在一个决定上，不在本方案内。开工前置条件（任一成立）：解除 `ROADMAP.md §0` 的 MCP non-goal（`§9` 触发条件 1）；或在 `DESIGN.md §26` 增列"受限工具面 agent"为一等调用方，并同时约定动词**不进 TUI 路径**（TUI 继续直连 socket）。届时 `--seek` 需强制带符号表示相对、绝对另用 `--seek-to`；`--toggle-pause` 不做（`cycle pause` 不回值，无法兑现 envelope）。
- **`ROADMAP.md §6.2 / P0` 名下三件，独立先行**：`-d` 同步失败原因进 envelope；`--status` 增加 live `paused` 字段；`live_volume()` 泛化为通用属性读。
