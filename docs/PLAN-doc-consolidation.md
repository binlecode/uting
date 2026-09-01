# PLAN-doc-consolidation —— 文档体系收敛：why/how 归文档，what 归源码

状态：**已定案，已过冷读 pre-mortem，Phase 1 执行中**（2026-08-31 定案；CLAUDE.md 规则已先行落地，本 PLAN 驱动 docs/ 迁移）。

**分两个 Phase 执行**（pre-mortem 修正 #13：工作树里有在飞的功能改动 —— `shell/bili-search`、
`shell/yt-search`、`shell/uting`、`tests/contract.sh` 的 description 字段等 —— 与本迁移要碰的
文件重叠，不得纠缠）：

- **Phase 1（现在，纯 docs 侧）**：ARCHITECTURE 重写收编四份分册的 why；verification /
  ROADMAP / README / `config` 注释 / `.githooks` / `.claude/skills` 清扫。
  **四个分册文件此阶段一个都不删**——全部 8 个脚本与 3 个测试文件都还引用着它们的文件名。
- **Phase 2（在飞功能落地之后）**：`usage()` 补全（自成一次 z bump 提交）、shell/ + tests/
  引用清扫（只做正则范围内的引用改写，**不顺手删注释** —— pre-mortem 修正 #5）、
  最后一个提交只删四个文件（先过下方门禁）。

**pre-mortem 修正的处置**（冷读 subagent，2026-08-31；全文见对话，此处记结论）：
#1 门禁正则修正（见工作项 5）、#2 清扫范围扩到全树并点名 config/.githooks/.claude、
#3 usage-vs-解析器的机械 diff 脚本先行、#4 shell 侧工作重新定性（78/168 处在 usage heredoc 里，
6 个命令的 --help 可见变化 → 独立提交 + z bump）、#5 本迁移不做注释删减、#6 ut-play 的
"full schemas: AS-BUILT-contract.md §3" 指针式 help 必须先变成自足陈述、#7 终端帧默认存活
（帧是 how；丢弃任何一帧是计划里点名的决定，不是存活测试的结论；基线：ARCHITECTURE 143 行
框线、tui 67、player 16、engine 15）、#8 增加 D# 孤儿门禁（README、tests/contract.sh、
`.githooks/pre-push` 的失效 D17）、#9 audit-conformance SKILL.md 是一等迁移项（其 R8/R11 按
节号 sed 提取，去号后会静默空转）、#11 提交排序：收编（纯增）→ 清扫 → 删除（纯删）、
#12 存活台账记在 tmp/、#13 两 Phase（见上）—— 全部接受。
#10（引用格式门禁）**部分接受**：格式定为 `docs/ARCHITECTURE.md「章节名」`（指具体章时）
或裸文件名（指整份时），但不设 grep 门禁——为引用格式再造一套门禁正是刚废除的那类过度工程。
#14（上分支 + 原子落地）**改造接受**：单作者线性 main，按 #11 排序的提交序列直接上 main，
每个提交自身内部一致（收编后原件未删=有意的临时重复，本 PLAN 即其记录）。

## 已定的决定（对话中定案，此处为记录）

1. **持久文档（ARCHITECTURE 与 as-built）只为人类工程师服务，只写 why 与 how，从不写 what。** what —— argv、信封、
   退出码、默认值、键表、函数清单 —— 由源码、各命令的 `usage()` 与测试套件陈述；
   文档里复述即违规，无例外。一段文字要留下，必须说出代码说不出的东西：
   一个决定与它否掉的备选、一条被带日期的测量逼出来的规矩、一个跨文件的不变量、
   一个付出过调试代价的坑。
2. **全局节号/索引体系废除。** 视为过度工程：维护一套永久索引的成本高于它防住的
   那点引用失效（grep 几秒就能找到）。标题一律用普通命名标题，可自由重排；
   引用 = **文件名（大文件时 + 标题名）**，靠 grep 解析。墓碑、继承节号、
   `D#` 引用键一并废除（ROADMAP 条目按名字引用："打包 NO"、"Go 重写 NO"）。
3. **`PLAN-` 不同：它同时服务人类工程师与编码 agent。** 计划是从设计一路到实现规格的桥，
   为了让编码 agent 无歧义地写出源码，**必须**写到实现精度：核心处理逻辑、API 契约
   （字段、flag、信封、退出码）、逻辑规格与边界情况、验证矩阵；并且**跟踪真实源码
   实现与验证的落地进度**。它不构成复述负债，因为落地即删——进入持久文档的只有 why。
4. **分区保持六份不变；变的是内容规则与索引，不是文件数**（2026-08-31 以实测推翻了
   此前"六收敛为二"的决定：逐段读完四份分册共 3338 行后，engine/player/tui 约 85–90%、
   contract 约 60% 的内容本来就是新规则要**保留**的 why（实测逼出的规矩、被否的备选、
   跨文件不变量）——合并会产出一份约 3500 行的单文件，违反 CLAUDE.md 自己那条
   "某模块的 why 超出一章就分册"的规则。engine ~430 / player ~700 / tui ~950 行的
   存活量全都超章）。
   - 六份都留：ARCHITECTURE（伞）+ contract / engine / player / tui / verification。
   - **每份 AS-BUILT 开头强制同一个模板，三节按序：「结构」（这一域由什么构成、本文的地图）、
     「模块」（边界与隔离：拥有什么、刻意不拥有什么、执行哪条分层规矩）、
     「接口」（表面与形状：动词与信封点名，形状指向 `usage()` / `tests/contract.sh` /
     AS-BUILT-contract.md，绝不复述）**；随后才是 why 各章。ARCHITECTURE 的前三节是
     套件级镜像：定位与设计目标 → 系统全景 → 按模块的设计决定（辐辏的那个毂）。
   - contract 的 **what**（逐字段 schema、flag 全表、键表语义）在 Phase 2、`usage()`
     接住之后剪除；留下的是形状的 why 与 semver 边界。
5. **agentic DLC 三阶段，roadmap 为根：roadmap → plan → as-built。** research 不是
   ADLC 的阶段 —— 它是外部活动，按自己的节奏进行，产出以 roadmap 条目的形式进入
   生命周期；`RESEARCH-` 文档是条目背后的证据，位于生命周期之外。
6. CLAUDE.md 规则先行改写（已完成），docs/ 随后迁移到合规状态 —— 本 PLAN 的工作项。

## 迁移工作项

### 1. 去号与剪除（Phase 1，2026-08-31 已执行）

- [x] 全部节号删除：七份 docs（RESEARCH 除外）标题改命名标题，全库 `§N` 引用改
      「章节名」引用（`tmp/denumber.py` 机械改写 + 逐条人工修误配）。
- [x] ARCHITECTURE 剪除（处置台账，pre-mortem #12）：§7–§16 墓碑带与第三部分墓碑
      （纯指针，删）；§17 函数图（what，删 —— `fn_graph.py` 随手可再生成；其中两段
      非 what 迁入「命令拓扑」章：八脚本刻意重复的论证、源流）；§22 计分卡与
      §23 自评（自我陈述/与重复论证段冗余，删）；§24/25/27 存根（删）。
      1183 → 860 行。**终端帧一帧未动**（框线行数 ARCH 143 / engine 15 / player 16 /
      tui 67，与基线一致 —— pre-mortem #7）。
- [x] 四条工作流保留（how 的叙事）；「已知约束」「可移植性契约」保留。
- [x] **AS-BUILT 模板落地**：五份分册开头统一三节 —— 「结构」「模块」「接口」——
      随后才是 why 各章；旧散文序言（含"节号继承"说明）删除。
- [x] verification：去号 + 引用扫尾 + 失效的 PLAN 项键（P2…P13）改为日期。
- [x] ROADMAP：`D#` 键删除，条目改名字引用（打包 NO / 第三对引擎 NO / ut-search NO /
      list= NO / Go 重写 NO）；RESEARCH 内部节号保留，其指向 ROADMAP 的 D 键与
      已删节号的引用已修。
- [x] README / `config` 注释 / `.githooks`（含 pre-push 失效的 `D17`）/
      `.claude/skills/audit-conformance/SKILL.md`（R8/R11 与按节号的 sed 提取改为
      按标题名；R11 重写为新 doctrine 的漂移定义）。
- [ ] 冻结面的 what 剪除（contract 的逐字段 schema、flag 全表、键表语义）——
      **Phase 2**，`usage()` 接住之后（见工作项 4）。

### 4. 源码义务（Phase 2）：`usage()` 必须接住被删的 what

- [ ] 机械核对，不靠眼（pre-mortem #3）：`tmp/` 里落一个 diff 脚本 —— 每个命令的
      argv 解析器认的 flag 集 vs `usage()` 点名的 flag 集；每个 `-j` 发射器的顶层键集
      vs `usage()` 写的字段名。输出记入本 PLAN，缺口先补 `usage()`。
- [ ] 指针式 help 先变自足（pre-mortem #6）：`ut-play` 的
      "Output contracts (full schemas: AS-BUILT-contract.md §3)" 与
      "See AS-BUILT-contract.md §5" 这一类，必须改成 `usage()` 里的自足陈述，
      六个命令逐一过。此提交是 --help 可见变化 → **z bump，独立提交**。
- [ ] `tests/contract.sh` 已是形状的可执行陈述，本身不需要为此新增检查。
      契约 what 的文档段删除排在本项完成之后（A→E：先立替代，后删旧径）。

### 5. 全库引用清扫（grep 门禁；范围 = 全树除 .git/ 与 tmp/）

基线（2026-08-31 实测）：`§[0-9]` —— CLAUDE.md 0（已清零）、README 14、docs/ 630、
shell/ 168（其中 78 处在 usage heredoc 内，属 Phase 2 的 z bump 提交）、tests/ 32、
`config` 5、`.githooks` 2、`.claude/` 18。

- [ ] Phase 1：README 14 处、`config` 注释 5 处、`.githooks/pre-commit` 2 处与
      `pre-push` 的失效 `ARCHITECTURE.md D17`、`.claude/skills/audit-conformance/SKILL.md`
      18 处（含 R8/R11 规则文本与按节号的 sed 提取命令 —— 改为按标题名提取；
      R11 对函数图的 diff 随函数图删除一并改写或删除，不得留成空转）。
- [ ] Phase 2：shell/ 与 tests/ 的 200 处 —— 仅做引用改写（文件名，指具体章时
      `docs/ARCHITECTURE.md「章节名」`），不做注释删减。
- [ ] 门禁一（§ 归零）：`/usr/bin/grep -rn '§[0-9]' --exclude-dir=.git --exclude-dir=tmp . | /usr/bin/grep -v 'RESEARCH-tui-player.md'` 归零
      （RESEARCH 内部节号保留，见工作项 3）。
- [ ] 门禁二（D# 孤儿归零）：`/usr/bin/grep -rnE '\b(ROADMAP|ARCHITECTURE)[^)]{0,20}\bD[0-9]' --exclude-dir=.git --exclude-dir=tmp .` 归零。
- [ ] 门禁三（删文件前）：`/usr/bin/grep -rlE 'AS-BUILT-(contract|engine|player|tui)\.md' --exclude-dir=.git --exclude-dir=tmp .` 只剩本 PLAN 自身，
      随后一个纯删除提交移走四个文件与本条门禁的最后引用。

### 6. 收尾

- [ ] `tests/contract.sh --offline` 通过（文档迁移不该碰行为，但 usage() 若有增补需过门）。
- [ ] `capture-pane` 校验 README/ARCHITECTURE 中的终端帧未被误伤。
- [ ] 版本判定：docs-only 不 bump；若 usage() 增补属于加法，按 z 位单独判。
- [ ] 删除本 PLAN。

## 存活测试（迁移时逐段执行）

一段文字留下，当且仅当它属于以下之一，否则删除：

1. 一个决定 + 它否掉的备选与原因；
2. 一条由带日期的测量逼出来的规矩（日期随行）;
3. 一个跨文件才成立的不变量（如 4096 字节行、恰好一次抽取）；
4. 一个付出过真实调试代价的坑及其机理。

"这个 flag 做什么"、"信封有哪些字段"、"函数 X 负责 Y" —— 一律是 what，删。
