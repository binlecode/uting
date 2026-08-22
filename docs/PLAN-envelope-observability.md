# PLAN-envelope-observability — 让 envelope 说出它今天说不出的三件事

> 阶段：**plan（可施工，未开工）**。三件都已决定，不含待决项 —— 待决的那批在 `ROADMAP.md` §11。
> 进度记在本文件（节标题后的 `[ ]` / `[x]`）；三件全 `[x]` 且契约进了 `docs/SPEC-system.md`
> 之后**删除本文件**。
> 依据：`ROADMAP.md` §6.2 / §10 P0 · `SPEC-system.md` §14/§26

---

## 0. 为什么这三件是一批

它们不是三个功能，是同一个毛病的三处出口：**播放器的真实状态在 envelope 里读不到。**

- `-d` 同步失败的原因只以散文形式活在 stderr —— `yt-tui` 得去解析 `die` 的措辞、剥 `Error: ` 前缀。
- `--status` 没有 `paused` 字段 —— agent 能不能暂停另说，暂停了也**观测不到**。
- `live_volume()` 只会读 volume 一个属性 —— 而第二个属性马上就要来了。

第二件是第三件的调用方，第三件让第二件不多花一次往返；第一件是 §6.2 认定的**唯一**契约漏洞。
三件都在 P0 名下，且都是"现在定字段、shell 里实现，Go 版继承一个没有洞的契约"（D3）。

**Non-goals**：不加运行时播控动词（`--pause` / `--seek`，见 `ROADMAP.md` §11 的触发条件），
不动 `yt-tui` 直连 socket 的读路径（每次按键起一条进程链正是 §26 否掉的东西）。

---

## 1. `[ ]` `-d` 同步失败原因进 envelope

**今天**：`-d` 启动前的同步失败（解析不到、私有视频、网络）只 `die` 到 stderr。`-d -j` 的成功
envelope 是 `{status:"started", id, pid, url, mode, started_at, title, sock, log}`，失败时**没有
对应的机读形状**。

**要做**：失败时输出与其他动词同族的错误 envelope，退出码沿用现有分类。

```json
{"status":"error","url":"...","mode":"audio","reason":"unavailable"}
```

- `reason` 复用共享枚举（`forbidden|unavailable|format_unavailable|network|unknown`），
  经 `classify_playback_error` 得出 —— 不要新写一套措辞。429 已归入 `network`。
- 退出码：沿用 `2+`（传递 yt-dlp/mpv 失败），**不是** 1；1 留给用法错误。
- 文本模式行为不变（仍是 `die` 一句话），只补机读形状。

**验收**：`yt-play -d -j -- <私有视频>` 得到上面的形状且 exit 2；`yt-tui` 不再需要读 stderr
措辞（把它那段剥 `Error: ` 前缀的代码删掉，这是本条真正的收益）。

---

## 2. `[ ]` `--status` 增加 live `paused`

**今天**：`--status` 的每条 player 记录是 `{id,pid,url,mode,volume,title,started_at}`。
`volume` 已经是**从 socket 实读**的（`live_volume()`，§9.3），理由是 state file 会撒谎 —— 任何
直接驱动 socket 的客户端（`yt-tui` 的 9/0）都会让记录值过期。`paused` 有完全相同的问题，却连
字段都没有。

**要做**：加 `paused`，同样实读，同样在读不到时优雅退化。

```json
{"id":"...","pid":123,"url":"...","mode":"audio","volume":55,"paused":false,"title":"...","started_at":"..."}
```

- 取值：mpv `get_property pause` → `true|false`；无 `nc`、socket 不在、或播放器不答时为 `null`
  （与 `volume` 现有的退化方式一致，不要伪造 `false`）。
- `null` 与 `false` 必须可区分：`false` 是"在放"，`null` 是"问不到"。
- 顺带修掉一处双面不一致：`yt-tui` 目前把暂停态记在本地 `CURRENT_PLAY_PAUSED`，外部改动它看不到。
  改为渲染时以实读值为准（TUI 仍直连 socket，不经动词）。

**验收**：`-d` 起一个播放器 → 用 socket 直接 `set_property pause true` → `--status -j` 报
`paused:true`；杀掉 socket 后报 `null` 而不是 `false`；无 `nc` 的环境下 `--status` 仍 exit 0。

---

## 3. `[ ]` `live_volume()` 泛化为通用属性读

**今天**：`live_volume(sock)` 硬编码 `get_property volume`，一次连接读一个属性。

**要做**：`live_props(sock, prop...)` —— 一次连接读多个属性，按 `request_id` 关联。

- **一个连接读完 `volume` 与 `pause`**：`--status` 每个播放器仍只付一次往返。这是把第 2 件做进
  去而不加成本的唯一方式，也是本条存在的全部理由 —— 在第 2 件落地前它是空想抽象，之后它有两个
  调用方。
- 必须保留现有的三条硬规则（它们都是踩出来的，见 §25.1）：按 `request_id` 关联而非行序（mpv 把
  异步事件插进每个客户端的流里）；`|| true` 包住管道（`set -euo pipefail` 下 nc 超时 / `head`
  提前关闭会在赋值处直接杀脚本）；`nc` 缺失时**软退化**返回空而不是报错（`--status` 的
  jq-only 依赖契约）。
- 参考实现已在 `yt-tui` 里：`fetch_play_times` 就是"一次连接三个属性"，`mpv_get_prop` 是单属性
  读。核心这一份要的是同样的形状，但保留核心侧"确认送达、失败退 4"的语义 —— **两边不要互相调用**，
  名字也不要取成一样（TUI 那个是 fire-and-forget）。

**验收**：`tests/mpv_ipc_mock.py` 驱动 —— `--reverse`（乱序回复不得错位）、`--null pause`
（`null` 不得渲染成 `false`）、默认模式（永不关连接的 peer 不得让 `--status` 付满 1 秒超时）。
另测无 `nc` 时 `--status` 的输出与退出码不变。

---

## 4. 落地顺序与验证

顺序由依赖决定：**3 → 2 → 1**（泛化读 → 用它加 `paused` → 独立的 `-d` reason）。第 1 件与另两件
无耦合，可先可后。

| 项 | 命令 | 预期 |
| :-- | :-- | :-- |
| 语法 | `/bin/bash -n shell/yt shell/yt-search shell/yt-play shell/yt-tui` | 0 报错（bash 3.2 是地板） |
| IPC 装置 | `tests/mpv_ipc_mock.py` 的 `--reverse` / `--null pause` / 默认（不关连接） | 见 §3 验收 |
| `--status` 契约 | `-d` ×2 → socket 直改 pause → `--status -j` | `paused` 实读；`volume` 行为不回退 |
| 无 nc 退化 | `PATH` 去掉 nc 后 `--status -j` | exit 0，`volume`/`paused` 为 `null` |
| `-d` 失败 | `yt-play -d -j -- <私有视频>` | 错误 envelope + exit 2 |
| 全套回归 | `verify-suite` phase 1–2（phase 4 会出声，按需） | 既有契约零变化 |
| shellcheck | `--severity=warning` | 仍 15 条（基线，见 `ROADMAP.md` §6.1） |

上线后：把三处契约写进 `SPEC-system.md` §14（envelope）、§9.3（实读语义）、§27（验证矩阵），
在 §26 划掉"`--status` 没有 `paused`"这条前置条件，然后**删除本文件**。
