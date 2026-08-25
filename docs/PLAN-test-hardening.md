# PLAN-test-hardening —— 测试套件加固（2026-08-25 核查产出）

> 状态：**8/14 已落地（批次 A 全部 + D1）**。三个批次按「零行为改动 → 唯一的行为改动 → 结构去重」排序，
> 每批一次提交、一次回归；`ut-history` 那一条挂在它自己的落地上。最后一条落地时删除本文件。
>
> | # | 条目 | 批次 | 状态 | 落地后并入 |
> |---|---|---|---|---|
> | A1 | `playback.sh` docstring 广告了一条它没有的检查（banner tick + 已删的 `pty_drive.py`） | A | ✅ 已落地 | 文件自身 · `ARCHITECTURE.md` §27 |
> | A2 | `playback.sh` 两处 "behind the gate"，门早拆了 | A | ✅ 已落地 | 文件自身 |
> | A3 | `contract.sh:443` "writes in the live state dir"，与 `:38-40` 自相矛盾 | A | ✅ 已落地 | 文件自身 |
> | A4 | §27 的 flakiness 记录：根因已修，`mkfake` 是死符号 | A | ✅ 已落地 | `ARCHITECTURE.md` §27 |
> | A5 | 检查数漂 1（实测 145，文档 144），且钉在三个地方 | A | ✅ 已落地 | `CLAUDE.md` · `ARCHITECTURE.md` §27 |
> | A6 | 耗时声明：`contract.sh` 没有（实测 84s）；`playback.sh` 的 "~35s" 实测 41s，改成 ~40s | A | ✅ 已落地 | 文件自身 · README · `CLAUDE.md` |
> | A7 | `capture-pane` SKILL.md:118 说版本出自 `ut-play` 的 `UT_VERSION` | A | ✅ 已落地 | 技能自身 |
> | B1 | `drive.sh` 不隔离 TMPDIR —— 会掐掉用户正在听的播放器 | B | 未开工 | 文件自身 · README |
> | B2 | `drive.sh` 的 `pgrep` 没作用域 —— 用户自己的 mpv 被报成孤儿 | B | 未开工 | 文件自身 |
> | B3 | `PRESSED_ENTER` 使 `-i` 永不回收 —— 正是人会按 Enter 的模式 | B | 未开工 | 文件自身 · README |
> | C1 | 缺 `jq_in`：「先捕获再过滤」手写了三遍 | C | 未开工 | 文件自身 |
> | C2 | `playback.sh` 两块逐字重复（孤儿检查、position 轮询）+ 一处空值守卫 | C | 未开工 | 文件自身 |
> | C3 | `contract.sh` 离线段前置、TUI 收尾；TMPDIR 论证只留一份 | C | 未开工 | 文件自身 · `ARCHITECTURE.md` §27 |
> | C4 | `playback.sh:296` 的 duration 只读一次，与换曲赛跑 —— **已实测变红**，并连带吞掉「曲终推进队列」 | C | 未开工 | 文件自身 · `ARCHITECTURE.md` §27 |
> | D1 | `ut-history` 的契约段（第八个入口，今天只被 `--version` 遍历碰到） | 随收听历史落地 | ✅ 已落地 | `AS-BUILT-contract.md` §1.6 · README · `CLAUDE.md` |
>
> 本文件是**核查产出**，不是新功能：除 D1 外没有一条要求测试覆盖新行为，全部是让「文件说的」
> 和「文件做的」重新对上、删掉三份重复、修掉一条竞态。
>
> **实测（2026-08-25，本机，走网络）**：`contract.sh` **84s / 145 ok / 0 failed**；
> `playback.sh` 连跑两次 —— 第一次 **34s / 35 ok / 1 failed**，第二次 **41s / 36 ok / 0 failed**。
> 那一红一绿同一条检查，就是 C4。

---

## 0. 开工前核查（2026-08-25，全部成立）

- **划分本身不动。** `contract.sh`（离线契约 + 夹具）/ `playback.sh`（真进程、真 socket）/
  `drive.sh`（驱动器，不断言）这条线成立，各自 docstring 已经写清归属，`CLAUDE.md` 的两表一致。
  本 plan 不搬任何一条检查跨文件——唯一的例外是 A1 里那条**本来就不在任何文件里**的声明。
- **不新增文件。** `.githooks/pre-commit` 拒绝 `tests/` 下的非 `.sh` 文件，而 `CLAUDE.md`
  的「harden before you extend」要求新文件必须能指名一个现有检查抓不到的生产故障。本 plan 指不出，
  所以一条都不加。
- **实测过的量**：`tests/` 共 1161 行，其中注释 476 行（`contract.sh` 293/352、
  `playback.sh` 134/179、`drive.sh` 49/82）。静态 `report` 调用点 137 个，循环展开后 145 条。
- **没有半成品**：`grep -rn "mock\|fake\|stub" tests/` 只命中规则本身的注释；套件里没有替身。
- **两个套件都跑过，数字是实测的**（2026-08-25）：`contract.sh` 84s / **145** ok（文档写的 144
  由此确认过期）；`playback.sh` 41s / 36 ok。同一天的另一次 `playback.sh` 是 34s / 35 ok / 1 failed
  —— 红的那条是 C4，红了就会跳过它下面那条队列声明，所以「35 ok」并不是「少证明一条」而是少两条。

---

## 1. 决定 T1 —— 计数不进 prose

**检查数只由套件自己打印，文档不再钉数字。**

`f009da3` 加了「通过 symlink 验证 VERSION」这一条之后，`CLAUDE.md:39` 与 `ARCHITECTURE.md:3021`
的 144 同时过期，而当时另一份施工文档写的 145 是对的（那份文档已随它自己的落地删除）——
同一个事实住在三个地方，于是漂了。
按「一个事实一个地方」，这个数字的唯一住所是 `contract.sh` 最后那行 `printf`。

- `CLAUDE.md:39` 的 `# the CLI contract, 144 checks` → 去掉数字，只留这行命令做什么。
- `ARCHITECTURE.md` §27 的「Last run」是一次**测量记录**，可以带数字，但要带日期，并且改成
  「按当次运行填」而不是当成常量维护。
- 什么条件会重开：无。计数没有任何读者需要提前知道。

## 2. 决定 T2 —— 隔离是所有入口的责任，不只是 suite 的

`contract.sh`（`0ca2f38`）和 `playback.sh` 都已经把 TMPDIR 指向自己的临时目录，理由写在各自头部：
`ut-play` 的 state dir 从 TMPDIR 推导且不吃覆盖，所以不重定向就意味着 `--stop --all` 会打到用户
正在听的那个播放器。**`drive.sh` 是同一套推导下最后一个没做的入口**，而它比两个 suite 更常被人手跑。

- 隔离不改变「跑的是什么」：pane 里是真 `uting`、真 `ut-play`、真 mpv，只是状态不落在用户的目录上。
- 一旦隔离，`PRESSED_ENTER` 这个分支就没有存在理由了（它当初的作用是「别去动用户的播放器」），
  于是 `-i` 模式的漏洞跟着消失——**一个修法解决三条**，这是把 B 批当成一次提交的原因。
- 血缘检查：`.claude/skills/capture-pane` 不引用 `drive.sh`，也不依赖 state dir 的位置，
  帧的内容不受影响（`grep -rn "drive.sh\|TMPDIR" .claude/skills/capture-pane/` 只命中 §118 那条
  与本 plan 的 A7 同源的版本说明）。

## 3. 决定 T3 —— Starting→Playing 那条声明：删掉，并记成一个有名字的缺口

`playback.sh:12-13` 声称它带着「Starting → Playing 靠 TUI 自己的 1s tick 翻转、无需按键」这条时序
断言，并说那是 `pty_drive.py` 最后被留着的理由。事实：该文件全文没有 tmux（`:22` 自己就写着
"no tmux and no terminal"），`ARCHITECTURE.md:3027` 也已经记下这个 case 随渲染器 rig 一起被移除。
**所以这条声明今天在任何地方都没有被证明**，`drive.sh -k Enter -w Playing` 只是等 banner 出现、不断言。

三个选项，选第三个：

1. **放回 `contract.sh` 的 TUI 段** —— 那段现在刻意不按 Enter；按了就等于 `contract.sh` 开始启动
   真播放器，破掉它自己的章程（「every live claim is playback.sh's」），还要接一套回收。否。
2. **在 `playback.sh` 里引入 tmux** —— 它的价值恰恰在于「不需要终端」，一条 TUI 断言会把
   tmux 变成这个文件的依赖。否。
3. **删掉声明，把缺口写进 §27 的取舍段落。** 与那段已有的诚实陈述同形：会翻车而测不到的东西
   （CJK 折行、右贴的 rail、重绘）就点名说测不到。采纳。

- 重开条件：如果 `contract.sh` 哪天接受「启动恰好一个真播放器并自己回收」这条章程改动，
  这条断言就属于它的 TUI 段——那是一次**契约级**的决定，要单独走，不许作为某个功能的副作用溜进来。

---

## 4. 批次 A —— 注释与文档漂移（零行为改动，一次提交）—— ✅ 已落地 2026-08-25

> **落地记录。** 七条全部改完，无一行可执行代码变动；两个套件跑绿。
> 本次实测（工作区含未落地的 `ut-history` 段）：`contract.sh` **177 ok / 0 failed / 79s**、
> `playback.sh` **42 ok / 0 failed / 67s**。§27 的「Last run」仍按 **HEAD**（145 / 36）记，
> 因为 as-built 只描述已落地的东西 —— `ut-history` 那 32 条随它自己的 plan 一起并入。
> C4 这一次没有变红（竞态本来就是抛硬币），批次 C 的修法不变。

改的全是注释和文档，不动一行会被执行的代码。**验证 = 两个套件跑绿且检查数不变**（A 批唯一能出的
错就是把注释改到了代码行上）。

| 条目 | 位置 | 动作 |
|---|---|---|
| A1 | `tests/playback.sh:12-13` | 删掉这两行；把「banner tick 无人证明」写进 §27 的取舍段（§3 的决定） |
| A2 | `tests/playback.sh:20`、`:114` | "behind the gate" → 说清真正的理由（真 peer 只在这里跑），门在 `:7` 已注明拆除 |
| A3 | `tests/contract.sh:443` | 「this writes in the live state dir」→ 改成「写在本文件 `:38-40` 私有的 TMPDIR 里」；顺手说明这段夹具**必须**排在 TUI 段之前（TUI 的 `--status` 轮询会 reap 掉墓碑夹具，见 C3 的排序约束） |
| A4 | `docs/ARCHITECTURE.md:3040-3050` | flakiness 记录降级为**已解决的历史**：根因（uid 共享 state dir）已由两处 per-run TMPDIR 修掉，「durable fix ... not built yet」不再成立；`mkfake` → `dead_record`。**同时换上 2026-08-25 实测到的那条**，它是不同的机制（一个 live 字段只读一次，与换曲赛跑）且**有修法**（C4），所以记成「已定位、随 C4 修」，不进「已接受的抖动」 |
| A5 | `CLAUDE.md:39`、`ARCHITECTURE.md:3021` | 按决定 T1 去数字 / 改成带日期的测量记录。**实测 145**（2026-08-25），文档两处的 144 确认过期 |
| A6 | `playback.sh:9`、README:180、`CLAUDE.md:138` 的 "~35s"；`contract.sh` docstring | **已实测**（2026-08-25，走网络）：`playback.sh` 全绿一次 **41s**（"~35s" 偏低但同量级 → 写 **~40s**，并注明含两个上限轮询，慢网络会更久）；`contract.sh` **84s**，此前根本没有耗时声明 —— 给它的 docstring 补上 **~85s**，并点明代价构成（约 15 次活的 engine 往返 + 一次 5s 锁自旋 + 一次约 25s 的 tmux 起 TUI）。`CLAUDE.md:165` 要求「每次提交前跑」，那这个数字就该挂在门口 |
| A7 | `.claude/skills/capture-pane/SKILL.md:118` | 「版本出自 `shell/ut-play` 的 `UT_VERSION`」→ 出自仓库根的 `VERSION` 文件（每个入口把它读进自己的 `UT_VERSION`）。后半句「重新截图而不是手改数字」保持不变 |

## 5. 批次 B —— `drive.sh` 的隔离与去分支（唯一的行为改动，单独一次提交）

按决定 T2，一处修法，三条同时消失：

1. 顶部 `UT_TEST_TMP=$(mktemp -d ...)` + `export TMPDIR`，`trap` 里 `rm -rf`——与两个 suite 同形。
2. 把 `TMPDIR` 显式喂进 pane。`:84-97` 的 `env_prefix` 只转发 `YT_*`/`UT_*`，而 tmux **server**
   带的是启动它那个 shell 的环境（这条教训 `:75-80` 已经写过一次），所以照 `contract.sh:587` 的
   写法显式传。
3. `:63`/`:65` 的 `pgrep -f 'mpv .*--input-ipc-server'` 收窄到 `=$STATE_DIR`——`playback.sh:238`
   的原话：不收窄的孤儿检查「在任何真的用 uting 的机器上是抛硬币」。
4. **删掉 `PRESSED_ENTER`**（`:52-53`、`:59`）：隔离之后无条件回收是安全的，`-i` 模式（人真的会
   在里面按 Enter）因此第一次被覆盖，`drive.sh:2` 的 "ALWAYS clean up" 和 README:184 的
   "always reaps" 也第一次成真。顺手删掉 `:132` 那个与 `:72` 完全相同的 EXIT trap 重装。

**怎么证明它能红**：隔离前后各跑一次 `tests/drive.sh -k Enter -w Playing`，同时在另一个窗口
起一个普通的 `uting` 并按 Enter。
- 修前：`drive.sh` 的 `--stop --all` 会把那个播放器一起掐掉（这就是缺陷本体），且 `pgrep` 把它
  数成孤儿、`drive.sh` 以 1 退出。
- 修后：那个播放器活着，`drive.sh` 以 0 退出，自己起的那个不留孤儿。
- 再跑 `tests/drive.sh -x 62 -y 20` 确认帧未变（隔离不该影响渲染）。

## 6. 批次 C —— 去重、排序，与一条实测到的竞态（C2+C4 同提交，C1/C3 各自一次）

**C1 `jq_in`。** helper 区（`contract.sh:66-86`）有 `rc`/`rc_in`/`jqv`/`jq_ok`，独缺「读 stdin 的
动词 + jq 过滤」这一格，于是「先捕获再过滤」被手写了三遍：`:403-404`、`:537-538`、`:555-556`，
每遍还配一段几乎同字的 pipefail 解释。加：

```sh
# jq_in <jq-filter> <payload> <command...>  — jq_ok 的 stdin 版。捕获在前、过滤在后，
# 原因与 jq_ok 相同（pipefail 会让管道带上左侧的退出码，于是 4 被当成 jq 的判决）。
jq_in() { local f=$1 p=$2; shift 2; jqv "$f" "$(printf '%s' "$p" | "$@" 2>/dev/null)"; }
```

三个调用点改成一行，重复的解释压成 helper 上方的一处。bash 3.2：无数组、无 `${var,,}`、
不写裸 `((...))` 语句。

**C2 `playback.sh` 的两块重复 + 一处守卫。**
- 孤儿检查（`:238-241` 与 `:321-324`，连注释都逐字一样）→ `no_orphans()`，注释只留一份。
- 「轮询直到 position 离开 0」（`:120-126` 与 `:217-222`）→ 一个**按字段**的有界轮询
  `wait_live <id> <field>`，而不是只管 position 的那一个：C4 要等的是 `duration`，同一个形状。
  两处的语义差别只在失败信息，由调用方给。三个调用点（position ×2、duration ×1）共用一份。
- `:160` 的 `before` 没有守卫：若 `.position` 回空，`$((before + 20))` 在 bash 3.2 里把空串当 0
  （已实测），于是 `--seek +30` 这条检查会在**没有基线**的情况下通过。补一个与 `:165` 同形的空值判定。

**C3 段序与那份重复的论证。**
- `contract.sh` 干的第一件事是活的网络搜索（`:107`），而全部离线检查——rejections、
  idle lifecycle、queue idle、death record、playlist store、version/non-TTY——排在约 15 次
  engine 往返之后。把离线段整块前移到第一个网络夹具之前，最常见的那类回归 2 秒就红。
  依赖检查已做：这些段不引用任何 `YT_*`/`BILI_*` 夹具（夹具在自己站点捕获，只被后面的
  parity 检查用），所以是纯粹的块移动，不是重写。
- **约束（写进注释，因为它是承重的）**：TUI 段留在最后。pane 里的 `uting` 每秒 `--status` 一次，
  而每个 lifecycle 动词都会 reap ——它必须排在墓碑夹具之后，否则 §27 记过的那种「夹具在断言前被
  删掉」会在单次运行内部重现（今天靠段序碰巧成立，明天靠注释成立）。
- `contract.sh:27-40` 与 `playback.sh:32-40` 是同一段 12 行的 TMPDIR 论证。留 `contract.sh`
  那份全文，`playback.sh` 缩成一句加指向；或两份都指向 §27。**只留一份。**
- 注释考古（「曾经试过又撤掉」「量过 0.04s」「是这么弄红的」）搬去 §27 的登记册。规则：
  **改了会让检查失效的留下**（为什么这个夹具、为什么 seek 顺序承重、为什么先 pause），
  **只记录历史的搬走**。逐段过，不批量删——这条是判断题，不是机械替换。

**C4 `playback.sh:296` 的 duration 与换曲赛跑 —— 实测红过。**

```
  run1 (34s):  FAIL  no duration on the queued player — cannot drive it to the end of a track
  run2 (41s):  ok    a track ending advances the queue (2)
```

同一条检查，同一台机器，无代码改动。机制：`--next` 之后上面那个轮询等的是**记录里的 url**
翻到第二首（父进程一推进 pos 就翻），但 `duration` 是**从 socket 活读**的 —— 此刻子进程可能才刚
杀掉第一首的 mpv、还在解析第二首的 handle，新 mpv 还没报出时长。于是：

```sh
dur=$(shell/ut-play --status -j | jq -r '.players[0].duration // empty')   # ← 只读一次
case "$dur" in "" | null) bad "no duration ..." ;;                         # ← 红，并跳过整个 case
```

- **代价比「一条红」大**：`duration` 拿不到，`case` 的另一支就整块不跑，「曲终自己推进队列」
  —— 队列存在的意义那一条 —— 一个字都没有被证明，而计分只少了 1（35 而不是 36）。
  这正是 `CLAUDE.md` 说的「一条没人见过它红的检查」的镜像：一条**红了却没人发现它顺手关掉了
  另一条**的检查。
- **修法**：用 C2 抽出的 `wait_live <id> duration` 换掉这一次读；等不到才算红，且失败信息要说清
  是「等不到时长」而不是「没有时长」。**不许用 `sleep` 兜**（`ARCHITECTURE.md` §25.1 的老账：
  这里的固定等待已经产出过错误结论）。
- **不改的**：`--seek-to $((dur - 4))` 这个把播放头推到曲末的手法保持不变 —— 它避开了「等一条
  六小时的流自己播完」，而这是这条声明唯一可行的驱动方式。
- **怎么证明它能红**：把 `wait_live` 的上限设成 0 次，这条必须红；恢复后连跑三次必须三次绿
  （竞态的检查只跑一次是看不出来的）。

**验证（C 批的全部意义在于「重构没有改变判决」）**：每一条改完都要能证明被守的东西还能红。
- `jq_in`：把 `ut-play --enqueue` 的 `require_live_target` 拆掉，`idle --enqueue says why` 必须变红
  （这正是当初写下这条检查的方法，`:396-399` 有记录）。
- `no_orphans`：手起一个 mpv 到本文件的 socket 目录，两处必须都红。
- `wait_live`：把 `--volume 0` 换成一个不存在的流，position 的两处必须都红；
  上限设 0 次，duration 那处（C4）必须红。
- `:160` 的守卫：把 `--seek` 的读回改成永远回空，`--seek +30` 那条必须从「通过」变红。
- 段序：只看「145 ok / 0 failed」和段落标题的顺序，条数不许变。

---

## 7. D1 —— `ut-history` 的契约段 —— ✅ 已落地 2026-08-25（`821f69f`）

> **落地记录。** 随收听历史一起进：`contract.sh` 32 条（disposable `UT_STATE_DIR`、`--ls`/`--record`
> 的信封、8KB 标题证明 4096 字节的原子性前提、坏行不遮蔽其余、`--clear --before`、整套 gate），
> `playback.sh` 6 条（真播完的播放器写下的行、被打断的行、两个引擎一个形状、`UT_HISTORY=0`）。
> 组件表、依赖图、README 与 `AS-BUILT-contract.md` §1.6 同时入表，`ut-play` 那条过期注释已清。
> 那份施工文档（步骤 3 的出处）已按 SDLC 规则删除，本节保留的是**它证明了什么**，不是它在哪。


`shell/ut-history` 已经是仓库里第八个入口（656 行、`--ls`/`--record`、自己的
`$UT_STATE_DIR/history/<YYYY-MM>.jsonl`），而 `tests/` 对它的全部覆盖是 `contract.sh:654-676`
那个「所有带 shebang 的文件」遍历顺手要到的 `--version`。`ut-play` 已经在改动中调它。

落地时**照抄 playlist store 那一段的模型**，不发明新形状：

- 一律在 disposable `UT_STATE_DIR` 下驱动（`:478-479` 已经把这个 export 建好了；这一段接着用，
  用完 `rm -rf` + `unset`）。**没有它，检查会写进用户真实的收听历史。**
- 该段要覆盖：`--ls -j` 的信封（`{status,count,items[]}`）、`--record -` 只吃 stdin 上一条记录、
  空 store 是 `ok`/`count==0` 而不是错误、坏 JSONL 行不遮蔽其余（`--ls` 的既有规矩）、
  `truncated` 的上报、gate（两个动作同时给 → 1、选择器无动作 → 1、播放类 flag → 1）、
  以及 1 vs 4 的划分与 store 的其余部分一致。
- **`ut-history` 落地时同时入表**：`CLAUDE.md` 的组件表与依赖图、README 的命令表今天仍是七个命令。
- 顺带清掉那处漂移（`shell/ut-play:760` 还写着收听历史是 ROADMAP §0 的 non-goal）——D14 之后
  不成立。**已清。**

---

## 8. 明确不做的

- **不加 `tests/lib.sh`**（共享 `report`/账房）。两个 suite 各自独立、可单独跑通是设计，
  不是巧合；`CLAUDE.md` 的「no rig layer」直接管这里。重复的是 20 行账房代码，可以接受；
  重复的**论证**不可以（C3 处理它）。
- **不加 `tests/all.sh`**。两条命令，`CLAUDE.md` 已经写明各自什么时候跑。
- **不加「跳过网络」的 env 开关**。set-once 的调优才用环境变量，而这会变成「绿是哪种绿」的
  第二种含义。段序前移（C3）用零个新概念拿到同样的快速反馈。
- **不加计时断言、不加渲染断言、不引入任何替身**。
- **不为提高条数加检查**。本 plan 净增的检查数是 0（D1 除外）。

---

## 9. 落地顺序与回滚

```
  A  批次 A（纯文档/注释）→ 跑两个套件，条数与之前一致（145 / 36）
  B  批次 B（drive.sh，唯一的行为改动）→ 按 §5 的「怎么证明它能红」做一次对照
  C  批次 C（helper 去重 + 段序 + C4 的竞态）→ 每条按 §6 的方法弄红一次，再跑两个套件；
     C4 与 C2 同一次提交（共用 wait_live），并且 playback.sh 连跑 3 次全绿才算完
  D  文档并入：§27 的取舍段（A1/A4）、`CLAUDE.md`/README 的耗时与计数（A5/A6）
  E  最后一次 headed（`tests/drive.sh -x 62 -y 20`）+ headless（两个套件）扫尾，
     并把当次的 145 / 36 与耗时填回 §27 的「Last run」
```

每批一次提交，互不依赖，可以单独 revert。破坏性的一步只有 C3 的块移动和 B4 的分支删除，
两者都排在它们的替代品已经证明过之后。D1 落地时删除本文件（其内容按上表并入 as-built）。
