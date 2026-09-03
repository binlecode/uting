# PLAN-agents-audit —— AGENTS.md（=CLAUDE.md）的漂移审计与修正

**状态（2026-09-03）：审计完成，修复未动。** 审计对象是仓库守则文件本身：
`AGENTS.md` 是指向 `CLAUDE.md` 的符号链接，两者是同一内容。落地的定义是：下面
FIX-1 / FIX-2 / FIX-3 全部落实、验证矩阵全绿、本条 `PLAN-` 删除 —— 本计划只装
文档与注释修正，不碰任何行为。

**引用规范（本文件也照此写）**：按 `CLAUDE.md`「One fact, one place」与
「SDLC & Architectural Documentation」的规定，指路只用 **文件名 + 标题名**
（大文件）或 **可 grep 的符号/句子**，**不记行号**。行号是编辑一移动就作废的
稳定位置键；维护它、以及每次改完回填它，是纯 overhead —— 标题和符号由 grep
秒回。发现与修复条目因此只给锚，不给行。

## 范围与边界

- 审计方法：把 `CLAUDE.md` 里每条可核验的断言对着代码、`tests/`、
  `.githooks/`、`.claude/skills/`、`docs/` 实跑或实查。可核验的符号
  （`resolve_nc_unix` / `run_mpv` / `mpv_supports_vo` / 四处手写 HTTP seam /
  `weapi_params` / `probe_raw` / 十个入口点各一份的 `ut_read_config` / 两个技能
  / hooks 行为 / shell 里没有字面 `${var//`）全部属实，不在本条修复范围。
- 离线套件在沙箱外实跑：`tests/contract.sh --offline` = **258 ok, 0 failed**，
  约 28.8s，与 `CLAUDE.md`「Testing Guidelines」声称的「258 of 389」一致。
  沙箱内第一次跑出的 4 个 failed 是 tmux 无法连接自身 socket 的环境假象，
  不是回归。
- **不做**：不改任何行为、不动冻结面、不改 `tests/`、不改 `ROADMAP.md` 本身
  （ROADMAP 是现状的权威，漂移在别处）、不 bump `VERSION`（纯文档与注释，无
  契约/行为变化）。live 半场（388-389 总数）与 `tests/playback.sh` 需要网络和
  真 mpv，本审计环境不可达 —— 修复是文档/注释级，验证不需要它们。

## 发现

### F1（高）`CLAUDE.md` 对 ROADMAP 的摘要在过时后自相矛盾

`CLAUDE.md`「SDLC & Architectural Documentation」→ live-files 列表里
`docs/ROADMAP.md` 那一行把「a third engine pair」列为记录在案的 NO，并把
`ut-search` 当成已定的 NO，同时漏掉四条。而 `CLAUDE.md`「Project Overview」
自己说三对引擎今天都已落地（第三对就是网易云）；`ROADMAP.md`「记录在案的 NO」
里 `ut-search` 一条明说「第三对引擎落地」的触发器**已经触发**、它从「记录在案」
变成「待重新决定」。

- `ROADMAP.md`「记录在案的 NO」的逐站 NO 是**喜马拉雅**（第四对候选，`m`
  端点要 per-request `webtk`），不是笼统的「第三对引擎」。把第三对说成 NO，
  与已落地的网易云直接冲突。
- 漏掉的记录 NO：`list=`、`--vo-tct-algo=plain`、按键注册表、
  terminfo-truecolor（都在同一节）。mpv-VO 那条顺带钉死的两小条
  （chafa/img2sixel/kitty `icat` 是新增运行时依赖；缩略图 URL 不是契约缺口）
  也没带。
- 一个按 `CLAUDE.md` 行事的 agent 拿到的「什么还开着、什么已死」地图是错的。

### F2（中）写回键数「十」在族内不一致

代码、`CLAUDE.md` 与 as-built 文档都是**十**：`shell/uting` 的 `PREF_KEYS`
赋值有十个成员，`pref_value` 的 case 与之同长；`CLAUDE.md`「Project Overview」
与「Architecture & Core Components」的 config 行都写 ten keys；
`AS-BUILT-cli-contract.md`「配置面」的「写回」段写「十个键」。但
`CLAUDE.md` 点名作枚举权威的文件还在说更小的数：

- `config` 文件头注释段（「THIS FILE IS NEVER WRITTEN BY ANY COMMAND.」那句）
  仍写「`uting` writes eight keys back」，只列八个名字，**缺 `UT_ROW_INDEX`
  （`#`）与 `UT_LIST_MODE`（Tab）** —— 而 `CLAUDE.md`「Coding Style & Naming
  Conventions」明说「The keys are enumerated by the shipped `config` itself」。
- `docs/ARCHITECTURE.md`「命令拓扑与文件布局」里 config 那一段还写着
  「`uting` 的七键写回」。
- `shell/uting` 的 `PREF_KEYS` 上方注释、写回块标题注释、`pref_value` /
  `pref_listed` / `pref_value_ok` 上方的注释，以及 `shell/ut-play` config
  载入块注释，计数都还是 eight / ninth / all eight entry points。

根因（推测，可 grep 复证）：把写回从八键扩到十键（加 `#`、Tab 两个键）的那次
提交只改了 `usage()`、as-built 与 `CLAUDE.md`，漏了 `config` 表头、
`ARCHITECTURE.md` 和这几段代码注释 —— 正是这条守则自己警告的那类「文档追代码，
漂移可 grep」。

### F3（低）`CLAUDE.md` 状态错误枚举的措辞易误读

`CLAUDE.md`「Architecture & Core Components」的 `ut-playlist` 行写
「… `corrupt` — the last four split 1 vs 4 …」：六个枚举里真正退 4 的是
`not_found` / `exists` / `locked` / `corrupt`（第 1、2、5、6 位），退 1 的是
`invalid_name` / `invalid_input`（见 `shell/ut-playlist` 状态错误枚举注释）。
「最后四个」字面上是 `invalid_name`、`invalid_input`、`locked`、`corrupt` ——
1 和 4 混杂，怎么读都对不上实际分法。应写成显式的两个集合。

## 修复条目

### FIX-1 —— `CLAUDE.md`：重写 ROADMAP 摘要，按名对齐

目标位置：`CLAUDE.md`「SDLC & Architectural Documentation」live-files 列表里
`docs/ROADMAP.md` 那一行。去掉「a third engine pair」；`ut-search` 不再当已定
NO，而是「重开条件已触发（第三对引擎落地，2026-09-02），待重新决定」；补全漏掉
的 NO 名字。理由只留一句并指向 `ROADMAP.md`，名字集合与 ROADMAP「记录在案的
NO」双向一致。建议形状（落地时可微调措辞，名字集合不许变）：

```text
**Its recorded NOs, worth knowing before proposing them again, by name:** the
packaging NO (reference implementation — no installer, no `v*` tags), the
Ximalaya NO (a fourth-pair candidate; that site's `m` endpoint needs a
per-request `webtk`), the `list=` NO, the `--vo-tct-algo=plain` NO, terminal
images via mpv's VO (it clears the screen and ships uncompressed frames — the
route is dead, the feature is not; it also pins two adjacent no's: chafa /
img2sixel / kitty `icat` are new runtime dependencies, and the thumbnail URL is
not a contract gap), the keybinding-registry NO, the terminfo-truecolor NO, and
the Go rewrite (closed entirely, TUI and player alike: the differentiator is
the contract and the contract is language-independent; it reopens only for MCP
or single-file distribution). The `ut-search` NO is reopen-triggered (the third
engine pair landed when NetEase shipped) and pending re-decision, not settled.
```

`done_when`：该行不再含 `a third engine pair`；该行出现的 NO 名 ⊆ ROADMAP
「记录在案的 NO」的点名，且那一节现存的每一条 NO（打包 / 喜马拉雅 /
`ut-search` / `list=` / `--vo-tct-algo=plain` / mpv-VO / 按键注册表 /
terminfo-truecolor / Go 重写）在该行都能按名找到。

### FIX-2 —— 写回键数族内对齐为十

- **FIX-2a `config` 表头**：文件头「THIS FILE IS NEVER WRITTEN BY ANY
  COMMAND.」一段改为 ten，名单补全，与 `shell/uting` 的 `PREF_KEYS` 十个成员
  一一对应：
  ```text
  # THIS FILE IS NEVER WRITTEN BY ANY COMMAND. Your file is: `uting` writes ten keys back to
  # it when you change one at runtime (engine, sort field, playback mode, quality tier,
  # theme, chrome language, result count, key-hint tier, row numbers, list mode) — in place,
  # comments and layout kept. AS-BUILT-cli-contract.md「配置面」
  # (write-back), ARCHITECTURE.md「两个根数据文件」.
  ```
- **FIX-2b `docs/ARCHITECTURE.md`「命令拓扑与文件布局」**：config 那一段删掉
  计数本身（键数住 `config` 与 as-built，不在这里），「与 `uting` 的七键写回」
  →「与 `uting` 的写回」。
- **FIX-2c `shell/uting` 注释**：`PREF_KEYS` 上方
  「duplicated verbatim in all eight entry points」→ all ten entry points；
  写回块标题注释「The eight keys above」→ The ten keys above；`pref_value`
  上方「to add the ninth key」→ to add an eleventh key；`pref_listed` 上方
  「these lists are eight long」→ ten long；`pref_value_ok` 上方
  「The eight are … a ninth key cannot」→ The ten are … an eleventh key cannot。
- **FIX-2d `shell/ut-play` config 载入块注释**：
  「This block is duplicated VERBATIM in all eight entry points: eight
  independent executables share no library」→ all ten / ten independent
  executables。

`done_when`：全树 grep 不到 `eight keys back`、`七键写回`、`all eight entry`、
`The eight keys`、`ninth key`、`duplicated verbatim in all eight` /
`duplicated VERBATIM in all eight`（主题无关的合法「eight」—— 如主题列表的
eighth 名字、信封的 ten keys —— 不在名单内，逐条看过再放行）。

### FIX-3 —— `CLAUDE.md`：把错误分法写成显式集合

目标位置：`CLAUDE.md`「Architecture & Core Components」的 `ut-playlist` 行。
「the last four split 1 vs 4」→「the two input errors (`invalid_name`,
`invalid_input`) exit 1 and the four store refusals (`not_found`, `exists`,
`locked`, `corrupt`) exit 4 — the same 1 vs 4 split the rest of the suite
uses」。

`done_when`：该句不再出现可作「最后四个」读的措辞，两个集合与
`shell/ut-playlist` 的状态错误枚举注释一致。

## 验证矩阵

| 条目 | 验证 |
|---|---|
| FIX-1 | `rg -n "a third engine pair" CLAUDE.md` 为空；把 CLAUDE.md live-files 的 ROADMAP 一条里点名的 NO 与 `docs/ROADMAP.md`「记录在案的 NO」逐条双向比对 |
| FIX-2a | `config` 表头注释说 ten 且点名十个键；十个名字与 `shell/uting` 的 `PREF_KEYS` 成员双向一致（名单数 = 10） |
| FIX-2b | `rg -n "七键" docs/ARCHITECTURE.md` 为空 |
| FIX-2c/2d | `rg -n "eight keys|all eight entry|ninth key|eight long|in all eight" shell/uting shell/ut-play` 为空（放行前逐条看剩余「eight」是否主题无关） |
| FIX-3 | 目读 CLAUDE.md「Architecture & Core Components」的 `ut-playlist` 行；分法与 `shell/ut-playlist` 的状态错误枚举注释一致 |
| 全树 | `rg -n "writes eight keys|八键|七键写回" CLAUDE.md README.md config docs shell` 为空 |
| 回归闸 | `/bin/bash -n shell/*`；`tests/contract.sh --offline` = 258 ok, 0 failed |

## 收尾

- 提交按仓库规范一条逻辑一个 commit，建议两块：先
  「`CLAUDE.md: resync the ROADMAP digest and the state-error phrasing`」，
  再「`config, ARCHITECTURE, shell comments: the write-back set is ten keys,
  not eight or seven`」。每个 commit 前跑上面的回归闸。
- `VERSION` 不动；`ROADMAP.md` 不动；行为与契约面不动。
- 两个 commit 落地、回归全绿后，删除本条 `PLAN-`。
