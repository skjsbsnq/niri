# Tahoe Desktop 路线图执行日志

**用途**：T01-T24 的唯一状态锁与证据账本。
**当前状态**：T02 完成——产品提交已推送并验证远端；docs-only 闭环 commit 待执行（closure reviewer 后）。
**禁止**：预填测试结果、审查结论、commit/push 收据或把计划写成已完成事实。

---

## 1. 状态表

| 任务 | 状态 | Commit subject / remote ref | 终审 | 备注 |
|---|---|---|---|---|
| T01 | COMPLETE | niri `a44ce8b1`（tahoe-layer-animations）/ main `85adaaa`（fix/tray-menu-pinned-surface-height） | 3 轮双审查 CLEAN（rework 轮） | output layer teardown + rework（Tahoe pending/锁范围/实际 build） |
| T02 | COMPLETE | niri `eeb7169a`（tahoe-layer-animations）/ main `4feff69`（fix/tray-menu-pinned-surface-height） | 7 轮双审查，最终轮双 CLEAN | window/output lifetime（is_none_or focus owner + STAB-03 证据关闭 + 7 测试） |
| T03 | PENDING | - | - | layer lock/damage/redraw |
| T04 | PENDING | - | - | pointer/focus transaction |
| T05 | PENDING | - | - | thumbnail budget |
| T06 | PENDING | - | - | QsPaths |
| T07 | PENDING | - | - | FileView async |
| T08 | PENDING | - | - | TahoeGlass mapping |
| T09 | PENDING | - | - | TahoeGlass feedback |
| T10 | PENDING | - | - | blur reuse |
| T11 | PENDING | - | - | glass capture semantics |
| T12 | PENDING | - | - | shared backdrop gate |
| T13 | PENDING | - | - | linear-light gate |
| T14 | PENDING | - | - | island geometry |
| T15 | PENDING | - | - | island interaction |
| T16 | PENDING | - | - | active-state budgets |
| T17 | PENDING | - | - | theme/material/type |
| T18 | PENDING | - | - | controls/a11y |
| T19 | PENDING | - | - | popup/scroll/focus |
| T20 | PENDING | - | - | icon/radius/shadow |
| T21 | PENDING | - | - | async action truth |
| T22 | PENDING | - | - | logging/diagnostics |
| T23 | PENDING | - | - | multi-output/hot-plug |
| T24 | PENDING | - | - | final soak/regression |

合法状态只有：`PENDING`、`IN_PROGRESS`、`BLOCKED`、`RESOLVED-NO-CODE`、`COMPLETE`。任何时刻最多一个 `IN_PROGRESS`。

---

## 2. 基线指纹

在 T01 开始时填写，不能沿用本文档创建时的假定值：

```text
timestamp: 2026-08-03T~10:00+08:00
main branch / HEAD: fix/tray-menu-pinned-surface-height / 78dc847
main remote ref: origin (github.com/skjsbsnq/niri.git)
niri branch / HEAD / remote ref: tahoe-layer-animations / 0cf398c4 / origin
quickshell branch / HEAD / remote ref: v0.3.0-43-g5a984c7（子模块，未动）
deployed niri version: 与源码 0cf398c4 同基线（研究快照），本次不部署
deployed quickshell version: 未变
deployed shell manifest: 未变
worktree pre-existing changes: 主仓库未跟踪 .zcode/、Testing/、docs/frontend-quality-overhaul-2026-08-02/；niri 子模块干净
baseline test failures: cargo test -p niri --lib = 544 passed（0 failed）；cargo fmt --all -- --check 有 70 处改动前既存的格式化漂移（非本任务引入，涉及 niri-config、handlers、input、tests 等既有文件；其中 niri.rs 4 处 1036/1437/1450/3483 均在本次 diff 之外；rework 轮 closure reviewer 复核：70 处总量在 0cf398c4/6dca4819/a44ce8b1 三态实测一致，原记录行号 3529 实为 6dca4819 态数值，已按 0cf398c4 态修正）
runtime warning summary: 未采样（本任务为纯源码/测试任务，不重启会话）
```

---

## T01 output layer teardown 闭环

**状态**：COMPLETE
**开始时间**：2026-08-03
**结束时间**：2026-08-03
**roadmap 引用**：`roadmap.md#T01`（第 75-94 行）；发现 `research-report.md#STAB-01`
**执行者上下文**：OpenCode / DeepSeek V4 Flash 会话（niri 子仓库 `tahoe-layer-animations` 分支）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| STAB-01: `Niri::remove_output()` 只向 layer 发 close，随后从 layout 移除 output | `src/niri.rs:3290-3295`（旧代码 3291-3293 仅 send_close 循环） | CURRENT-CONFIRMED | 成立 |
| STAB-01: `layer_destroyed()` 只扫描 `layout.outputs()`，找不到已移除 output 时 mapped 条目永不清理 | `src/handlers/layer_shell.rs:60-87`（found=None 分支无任何清理） | CURRENT-CONFIRMED | 成立 |
| STAB-01: null commit 路径找不到 output 时提前返回 | `src/handlers/layer_shell.rs:106-118`（`return false`） | CURRENT-CONFIRMED | 成立 |
| STAB-01: `mapped_layer_surfaces` 条目残留并参与动画/shader/规则推进 | `src/niri.rs:4596-4602`（values_mut 全表推进）、`4687-4690`（shader） | CURRENT-CONFIRMED | 成立 |
| 无第二张索引表、无 hot-plug 旁路可复用的既有 teardown 机制 | 全仓 rg：`mapped_layer_surfaces` 仅一张；`remove_output` 生产调用仅 `src/backend/tty.rs:1610` | CURRENT-CONFIRMED | 成立（原地改造） |

### 2. 工作树与范围

开始时 `git status --short`（niri 子模块）：

```text
（干净，无用户改动）
```

允许修改：

- `niri/src/niri.rs`（`remove_output` 及新增私有 teardown helper）
- `niri/src/tests/mod.rs`（注册新测试模块，一行）
- `niri/src/tests/output_teardown.rs`（新增测试文件）

明确禁止修改：

- `src/handlers/layer_shell.rs` 及所有正常 unmap/destroy teardown 路径（A01.4 行为保持）
- `src/layer/mapped.rs`、`src/protocols/tahoe_glass.rs` 等 authority 文件
- 主仓库 `.zcode/`、`Testing/`、docs 目录其他文件（用户项）

定义/调用点/测试搜索：

| `rg` 命令 | 命中数 | 修改点 | 不修改点及理由 |
|---|---:|---|---|
| `remove_output` (src/) | 3 | `src/niri.rs:3290`（定义） | `src/backend/tty.rs:1610` 唯一生产调用者（走新逻辑，不改）；`screencopy.rs:251` 为协议内部状态，职责不同 |
| `mapped_layer_surfaces` (src/ 非 tests) | ~22 | `src/niri.rs:3399`（teardown 移除） | 其余为 get/get_mut/values_mut/contains_key，全部经 `layout.outputs()`/`output_state` 可达 output，teardown 后不可达 |
| `unmapped_layer_surfaces` | 8 | `src/niri.rs:3402`（teardown 移除） | `layer_shell.rs:47/58/154/263` 常规路径不改（幂等 remove 与 teardown 共存安全） |
| `closing_layers` | ~20 | `src/niri.rs:3408`（retain 取消） | 推进/渲染路径不改，按 `closing.output` 过滤已覆盖 |
| `unmap_layer` (smithay) | 3 处调用 | `src/niri.rs:3404` | `layer_shell.rs:82` 正常 destroy 路径不改 |

### 3. 旧实现失败基线

| 测试/probe | 旧结果 | 为什么能捕获根因 |
|---|---|---|
| `output_removal_tears_down_layers_foreign_rects_and_tahoe_transform`（A01.1） | FAIL：layer map 仍含两 layer；mapped/unmapped 残留；directive 未清；foreign rect 未清；closing 动画未取消 | 旧 `remove_output` 只 send_close；`layer_destroyed` 找不到已移除 output → 六类状态全部残留 |
| `remove_output_with_unmapped_layer_cleans_up_without_panic`（A01.3c） | FAIL：unmapped 条目残留 | null commit 已 unmap 的 layer 在 output 移除后无任何清理路径 |
| `remove_last_output_with_mapped_layer_does_not_panic`（A01.3a） | FAIL：mapped 条目残留 | 同上 |
| `repeated_output_add_remove_returns_mapped_layer_holdings_to_baseline`（A01.2） | FAIL：cycle 0 即残留 | 每次 remove 残留一个 mapped 条目 → 100 次线性增长 |

全部 4 个新测试在旧实现上失败、新实现上通过（红绿证明），走真实协议 roundtrip（map/unmap/null commit/destroy + Tahoe `set_transform` + wlr foreign `set_rectangle`）。

### 4. 实现机制

- 原 authority：`Niri::remove_output`（内联 send_close）+ `layer_destroyed`/`layer_shell_handle_commit`（常规 teardown）。
- 原地重构方式：`remove_output` 在 `layout.remove_output` 之前调用新私有方法 `teardown_layer_shell_for_removed_output`（`src/niri.rs:3365-3412`）：(1) 对全部 layer 发送 `send_close`；(2) layer-map 锁内仅收集 `LayerSurface` 列表，guard 即刻释放；(3) 逐层按固定顺序清理：`with_windows_mut` 清 foreign-toplevel rect hint → `mapped_layer_surfaces.remove`（`MappedLayer::Drop` 移除 pre-commit hook）→ 存在时 `clear_transform_directive_on_unmap` → `unmapped_layer_surfaces.remove` → `unmap_layer` 移除 layer-map 槽位；(4) `closing_layers.retain` 取消引用该 output 的 close 动画。
- 被删除的旧/重复 authority：`remove_output` 中原来的内联 send_close 循环（移入 helper，语义不变）。
- 生命周期、失败、取消、destroy、scale/reduced 边界：output 已不可渲染 → 不启动 close 动画（无旧 output 强引用），已运行动画显式取消；client 不响应 close → teardown 不依赖其响应，后续 null commit/configure/destroy 全部走 `layer_shell_handle_commit`/`layer_destroyed` 的幂等路径；最后 output/非最后 output/已 unmap layer 均覆盖（A01.3 四次序）。
- 为什么没有平行接口：不新增 map/字段/公开 API；复用既有 `clear_foreign_toplevel_rect_for_source`、`clear_transform_directive_on_unmap`、smithay `LayerMap::unmap_layer`；helper 私有且唯一调用点。
- 为什么没有加入范围外功能：diff 仅 3 文件（niri.rs +49/-3、tests/mod.rs +1、新测试文件），无配置/依赖/视觉变化。

### 5. 验收逐条

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见上节 | PASS | 搜索表 + 未改点逐项理由 |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名、无新接口/flag |
| G03 | 专项+全量测试 | PASS | 见下 |
| G04 | 红绿证明 | PASS | 4 新测试旧实现失败（第 3 节） |
| G05 | 双审查 | PASS | 第 6 节（两轮双审查全部 CLEAN） |
| G06 | commit/push 顺序 | PASS | 第 7 节 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话 |
| A01.1 | `output_removal_tears_down_layers_foreign_rects_and_tahoe_transform` | PASS | 两 layer map → remove → null commit + destroy 后 map/mapped/unmapped/foreign rect/Tahoe directive 全空；hook 由 MappedLayer Drop 移除 |
| A01.2 | `repeated_output_add_remove_returns_mapped_layer_holdings_to_baseline` | PASS | 100 次 add/remove 循环，每轮 mapped/unmapped/layer map 三持有量归基线，无线性增长 |
| A01.3 | 4 个测试覆盖四种次序 | PASS | 最后 output（测试 3）、非最后（1/2）、已 unmap（2）、client 不响应 close（1/4）均不 panic |
| A01.4 | 既有 layer_shell 快照测试 + 测试 1 正向断言 | PASS | `closing_layers.len()==1` 正向断言 close snapshot 仍启动；548 全量通过 |
| A01.5 | NIRI_FULL + PROTOCOL_FULL | PASS（fmt 基线失败除外，见下） | 见全量配置 |

全量配置：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---:|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移全部改动前既有（niri.rs 4 处与本 diff 无关，tests/mod.rs 与 output_teardown.rs 零 diff）；本任务不修复任务外格式化 |
| NIRI_FULL | `cargo test -p niri --lib` | 0 | 548 passed / 0 failed（含 4 个新测试） |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import） |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC（niri/quickshell/权威 三处 sha256 一致） |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

### 6. 独立审查

#### 轮次 1（首次双审查）

- Reviewer A 结论：根因完整消除 CONFIRMED；调用点 CLEAN；锁/生命周期 CLEAN；不变量 CLEAN；红绿证据 CONFIRMED；1 处 NOT-A-FINDING（注释“same order as layer_destroyed”措辞与 layer_destroyed 实际次序略有出入，无行为后果）。
- Reviewer B 结论：单入口/无残留 authority CLEAN；无平行接口 CLEAN；范围 CLEAN；A01.1-A01.5 证据 CONFIRMED（A01.5 cargo 部分 PLAUSIBLE）；1 处 PLAUSIBLE（同一注释措辞）。
- CONFIRMED 修复：无。
- PLAUSIBLE 裁决：接受并修复——niri.rs 注释改为“same set of state as the regular teardown paths (layer destroy and the unmap commit branch) + 相对顺序不影响正确性”（独立容器）。

#### 轮次 2（修复后新双审查）

- Reviewer A（全新）：全部 CLEAN；1 条记录性 NOT-A-FINDING（post-removal Tahoe 新 directive commit → 单次 redraw-all，既有无泄漏行为）；注释修复 CLOSED。
- Reviewer B（全新）：**2 条 CONFIRMED**：① `tests/mod.rs` 中 `mod output_teardown;` 未按字母序（引入新 fmt 违规）→ 已移至 `lifecycle_observe` 与 `r15_perf_baseline` 之间；② `output_teardown.rs:329` 恒真断言 `server_surface.alive() || …`（wl_surface 从未销毁，alive() 恒真）→ 已删除该行。1 条 PLAUSIBLE（execution-log 需在 commit 前补齐 → 本文档）。
- CONFIRMED 修复：两处均已修复并复验（tests/mod.rs 与 output_teardown.rs fmt 零 diff；4 测试全绿）。

#### 最终轮次（修复后新双审查）

- Reviewer A（全新上下文）：CLEAN —— 根因消除/调用点/锁与生命周期/不变量/红绿证据/注释 六问全 CLEAN；前两轮三处 finding 全部 CLOSED；1 条 NOT-A-FINDING（on-demand focus/idle inhibit/popup 邻居状态自愈或镜像既有语义）。
- Reviewer B（全新上下文）：CLEAN —— 调用点迁移 CONFIRMED 完整、无平行接口、范围 3 文件、A01.1-A01.5 逐条 CONFIRMED（复跑验证）、注释语义 CONFIRMED。
- 两者审查的最终 diff 标识：niri 工作树 diff（src/niri.rs +52/-3、src/tests/mod.rs +1、新 src/tests/output_teardown.rs），`git diff --check` 干净。

### 7. 产品 Commit 与 push 收据

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `6dca4819d9b34e5ae0e8ab6632596ef0a9c061f7` | `fix(layer): T01 output layer teardown closure — release all layer-shell state before output leaves layout` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `0cf398c4..6dca4819` 成功 | `git merge-base --is-ancestor 6dca4819 origin/tahoe-layer-animations` exit 0 |
| main | `3c265a8bffa581de87e34e77566002c202dad3ca` | `fix(submodule): bump niri for T01 output layer teardown closure` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `78dc847..3c265a8` 成功 | `git merge-base --is-ancestor 3c265a8 origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → 6dca4819（= 已推送 niri commit hash）
```

### 8. 未覆盖、用户现场项与后续边界

- 未覆盖：无产品代码缺口（A01.1-A01.5 全通过）。
- 需要用户授权的实时验证：无（纯源码/测试任务，未重启会话、未真实拔插）。
- 发现但属于后续任务的事项（只记录，未修改）：
  - `layer_shell_on_demand_focus` 在移除 output 时不清空单槽：`update_keyboard_focus`（`src/niri.rs:1186-1205`）在 mapped 条目缺失时自愈清除，行为与改动前一致；属于 T04（focus transaction）边界，未越界修改。
  - post-removal 的 Tahoe 新 directive commit 会触发一次 `RedrawAttribution::all(Unlocatable)` 全输出 redraw：既有通用 unlocatable 行为，无泄漏、不 panic，属 T03/T11 归因范围，未越界修改。
  - smithay pre-commit hook 对已 unmap 的 layer 再次裸 null commit（不重发 configure props）报 `InvalidSize` 协议错误：client 协议违规的既有行为，与 output 是否移除无关（已在无移除场景复现），不属于 niri 缺陷。

### 9. 完成判定

**最终状态**：COMPLETE
**理由**：A01.1-A01.5 + G01-G08 全部满足；红绿测试证明；两轮（3 个全新 reviewer 组合）独立审查最终 diff 全部 CLEAN，无未裁决 finding；niri 与主仓库产品 commit 均已 push 且远端 ancestor 验证 exit 0；fmt 基线失败（70 处）为改动前既有并如实记录。
**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 10. 闭环记录审查与推送

- Closure reviewer（全新只读上下文）：完成，全部 PASS —— 两仓库 full hash/subject/parent/branch/remote ref/ancestor exit code/子模块指针逐项与记录精确一致；工作树冻结（niri 干净，主仓库仅用户原有未跟踪项）；无夸大或未执行内容；确认状态可置 COMPLETE，允许 docs-only closure commit。
- 产品 commit hash/remote receipt 是否逐项准确：是（clousre reviewer 实测核对）
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T01 close task record`
- closure push remote ref：`origin/fix/tray-menu-pinned-surface-height`
- closure remote ancestor 验证 exit code：待 push 后以命令输出验证（本 commit 不记录自身 hash，由后续 `git log --format=%H -- execution-log.md` 解析）

---

## T01 rework：Tahoe pending 状态与锁范围（用户指令退回重做）

**状态**：COMPLETE（rework 闭环，见第 9/10 节）
**开始时间**：2026-08-03
**roadmap 引用**：`roadmap.md#T01` 必须机制（锁内只收集必要对象/geometry；Tahoe directive 清理顺序显式）；`CONSTRAINTS.md` §0.11（修改 niri 源码必须构建实际二进制——上一轮仅 check/run lib 测试，未产出二进制）
**退回理由（用户指令）**：① T01 实现把 `send_close()` 置于 layer-map guard 内（IPC 发送跨锁，违反 roadmap“锁内只收集必要对象/geometry”与 STAB-04 方向）；② teardown 只清 `transform_directive`，wl_surface 上的 Tahoe glass `pending` regions / `pending_dirty` / `pending_transform` / `committed` 全部残留，孤岛提交会重新发布 directive、同 wl_surface 重新映射会继承已移除 output 的 glass 状态；③ 上一轮没有实际二进制 build；④ 需全新双审查。

### 1. 前提核实（2026-08-03）

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| `teardown_layer_shell_for_removed_output` 在 guard 内发送 `send_close` | `src/niri.rs:3384-3386`：`for layer in layer_map_for_output(output).layers() { layer.layer_surface().send_close(); }`，guard 存活期间执行协议 IPC | CURRENT-CONFIRMED | 成立（锁范围缺陷） |
| teardown 只清 Tahoe `transform_directive`，pending/committed 残留 | `src/niri.rs:3401-3403` 调用 `clear_transform_directive_on_unmap`（`src/protocols/tahoe_glass.rs:369-380` 仅置 `transform_directive = None`）；`TahoeGlassSurfaceInner`（tahoe_glass.rs:190-203）的 `pending`/`pending_dirty`/`pending_transform`/`committed` 无任何清理 | CURRENT-CONFIRMED | 成立（Tahoe pending 状态缺陷） |
| 残留 pending 状态在孤岛提交时重新发布 | `on_surface_commit`（tahoe_glass.rs:420-556）在 `CompositorHandler::commit`（compositor.rs:69）对任何 commit 先于 `layer_shell_handle_commit` 运行；`pending_dirty` 时会重新 validate/commit regions 并发布 directive（tahoe_glass.rs:432-543） | CURRENT-CONFIRMED | 成立 |
| 同 wl_surface 重新映射继承旧状态 | `MappedLayer::new`（mapped.rs:142-178）以 `presentation_transform: IDENTITY`、`seen_transform_epoch: 0` 起步，但 render 路径直接读 `get_committed_regions`（mapped.rs:437、810）；`on_surface_commit` 先于 layer-shell commit 处理（compositor.rs:65-69），旧 pending 会在 mapping commit 上落地 | CURRENT-CONFIRMED | 成立 |

### 2. 工作树与范围

- 主仓库：仅未跟踪用户项 `.zcode/`、`Testing/`、docs 目录（用户项，不触碰）。
- niri 子模块：干净（HEAD `6dca4819`）。
- 允许修改：`niri/src/niri.rs`（teardown 锁范围）、`niri/src/protocols/tahoe_glass.rs`（teardown 用全量状态清理）、`niri/src/tests/output_teardown.rs` + `niri/src/tests/client.rs`（回归测试及测试夹具最小 helper）、`execution-log.md`。
- 禁止修改：`src/handlers/layer_shell.rs` 常规 unmap/destroy 路径、`src/layer/mapped.rs` 等 authority、Quickshell、shell、主仓库用户项。

### 3. 搜索清单（rg）

| `rg` 命令 | 命中数 | 修改点 | 不修改点及理由 |
|---|---|---:|---|---|
| `send_close` (src/niri.rs) | 2 | `niri.rs:3384-3386`（移出 guard） | `niri.rs:3385` 语义保持（close 仍发送，顺序移至收集之后） |
| `clear_transform_directive_on_unmap` | 3 处调用 + 1 定义 | `niri.rs:3402`（teardown 改为全量清理） | `layer_shell.rs:74`（layer destroy 路径，pending 是常规双缓冲协议状态，保持）与 `layer_shell.rs:241`（null-commit unmap 路径，保持）；`tahoe_glass.rs:369` 定义保持 |
| `pending_dirty` / `pending_transform` / `pending` (tahoe_glass.rs) | ~30 | 新增全量清理函数（清 pending/pending_dirty/pending_transform/committed/directive） | `claim_controller`/`clear_if_owner`/`on_surface_commit` 语义不变（常规生命周期） |
| `remove_output` (src/) | 3 | `niri.rs:3290`（teardown 内部，不改签名） | `backend/tty.rs:1610` 生产调用者；`screencopy.rs:251` 职责不同 |

### 4. 旧实现失败基线（红绿证明）

在 6dca4819（旧实现）上运行两个新回归测试，均按预期失败并命中目标缺陷：

| 测试/probe | 旧结果 | 为什么能捕获根因 |
|---|---|---|
| `orphaned_commits_do_not_reapply_tahoe_glass_state_after_output_removal` | FAIL：teardown 后 `test_pending_state` 为 `(1, true, true)`（pending regions/pending_dirty/pending_transform 全部残留） | 旧 teardown 只清 directive；残留 pending 会在孤岛 null commit 上重新 commit regions、发布 directive、触发 redraw（后续断言全部命中） |
| `remapped_surface_does_not_inherit_removed_output_glass_state` | FAIL：新 output 上同 wl_surface 重新映射后 `get_committed_regions` 非空、directive 存在（旧 pending 在 mapping commit 上落地，日志证实 `committed Tahoe glass regions old_count=0 new_count=1` + `committed Tahoe glass transform directive Set(...)`） | 旧 pending/committed 无清理；`on_surface_commit` 先于 layer-shell commit 运行，把旧 output 的 glass 状态套到新映射 |

红跑前置说明（closure reviewer 复核补充）：红跑需把 rework 新增的 `#[cfg(test)] test_pending_state` 观察性 accessor 一并回填到旧树（否则旧树缺符号无法编译测试）；该 accessor 纯只读、不影响行为，断言失败值 `(1, true, true)` 与 log 记录逐字一致，红绿结论不受影响。

### 5. 实现机制（rework 增量）

- **锁范围**：`teardown_layer_shell_for_removed_output` 先在单一短 guard 内收集 `Vec<LayerSurface>`，guard 即刻释放；`send_close()` 移到锁外执行。锁内不再有任何协议发送；每层清理（foreign rect → mapped 条目/Drop 移 hook → Tahoe 全量清理 → unmapped 条目 → `unmap_layer` 单次短锁）仍在锁外，`unmap_layer` 每次短锁只做 map 原子操作。
- **Tahoe pending 状态**：`src/protocols/tahoe_glass.rs` 新增 `clear_glass_state_on_output_removal`（原地扩展既有 authority，非平行接口）：一次性清 `pending`、`pending_dirty`、`pending_transform`、`committed`、`transform_directive`；不排队 damage、不发布 identity reset（layer 已离开 map，无可见面；下次 mapping 以 IDENTITY 起步）、epoch 不回卷（后续 directive 仍视为 fresh）。teardown 对每个被拆 layer 的 wl_surface 调用它（包括已 unmap 的 layer，其 surface 同样可能携带 pending 状态）；旧调用 `clear_transform_directive_on_unmap` 在该路径被取代（常规 layer destroy / null-commit unmap 路径不动，pending 仍是常规双缓冲协议状态）。
- 测试夹具最小 helper：`tests/client.rs` 新增 `destroy_layer`（返回并复用 viewport——wl_surface 终生只允许一个 viewport 对象，smithay 会对此 post BadValue）/`create_layer_on_surface`；`output_teardown.rs` 新增 `output_by_name`（fixture 的 `niri_output` 按位置索引，output 移除后会错位）。

### 6. 验收逐条（rework 轮）

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见上节 | PASS | 搜索表 + 未改点逐项理由 |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名（`clear_glass_state_on_output_removal` 为既有 authority 的原地扩展，唯一调用点）；无新接口/flag |
| G03 | 专项+全量测试 | PASS | 见全量配置 |
| G04 | 红绿证明 | PASS | 2 个新测试旧实现失败（第 4 节），新实现通过 |
| G05 | 双审查 | 进行中 | 第 7 节（本轮全新双审查） |
| G06 | commit/push 顺序 | 待执行 | 第 8 节 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话 |
| A01.1 | `output_removal_tears_down_layers_foreign_rects_and_tahoe_transform` | PASS | 复跑通过（teardown 语义不变，dir rect/directive 清理断言保持） |
| A01.2 | `repeated_output_add_remove_returns_mapped_layer_holdings_to_baseline` | PASS | 复跑通过，100 次循环无增长 |
| A01.3 | 四次序测试 | PASS | 4 个测试全通过（最后/非最后/unmap/不响应 close） |
| A01.4 | close snapshot 正向断言 | PASS | `output_removal_tears_down...` 中 `closing_layers.len()==1` 保持 |
| A01.5 | NIRI_FULL + PROTOCOL_FULL | PASS（fmt 基线失败除外） | 见全量配置 |
| 新增 | pending 状态/锁范围回归（2 个测试） | PASS | 见第 4/5 节 |

全量配置（rework 轮）：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---:|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移全部改动前既有；本次 4 个改动文件 fmt 零 diff（tahoe_glass.rs:1346、tests/client.rs:880 为既有漂移，不在本 diff） |
| NIRI_FULL | `cargo test -p niri --lib` | 0 | 550 passed / 0 failed（548 旧 + 2 新） |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import） |
| 实际二进制 | `cargo build -p niri` | 0 | `target/debug/niri`（780,683,328 bytes） |
| 实际二进制 | `cargo build --release -p niri` | 0 | `target/release/niri`（138,730,952 bytes）——上一轮缺失的实际 build 已补齐 |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

### 7. 独立审查（rework 轮）

#### 轮次 1（首轮双审查，rework diff）

- Reviewer A 结论：机制层 CLEAN —— 锁范围与 Tahoe pending 残留两根因均结构性消除；F2-F10 全部 NOT-A-FINDING（红绿实测、epoch 不回卷、Drop 顺序、已 unmap layer 清理、无遗漏调用点、无重入/UAF/泄漏）。1 条 PLAUSIBLE（F1）：teardown doc comment "no IPC...under the layer-map lock" 过度声明——smithay `unmap_layer` 内部持锁发送 output-leave/configure（与常规路径一致），要求收窄注释措辞。
- Reviewer B 结论：CLEAN —— 无 CONFIRMED/PLAUSIBLE；六问全部闭合；1 处记录性小瑕疵（execution-log 中 fmt 漂移行号 tahoe_glass.rs:1356 应为 1346）。
- 修复：① niri.rs teardown doc comment 收窄为 "no niri-level protocol send or window/surface state mutation" 并注明 smithay unmap_layer 行为与常规路径一致；② execution-log 行号 1356→1346。修复后 fmt 70 处基线、6/6 测试通过。

#### 轮次 2（注释措辞复查，新双审查）

- Reviewer A（全新）：全部 CLEAN；F1-F6/F8-F10 NOT-A-FINDING 或 CLEAN；F7 PLAUSIBLE：结论句 "no IPC...by this function" 仍过度声明（unmap_layer 正是本函数调用且内部持锁发送），要求结论句同样加 niri-level 限定。
- Reviewer B（全新）：CLEAN —— 六问全部闭合；行号笔误已修正、G05/G06 如实标注未完成、无夸大记录。
- 修复：结论句改为 "so no niri-level IPC and no niri-level window/surface state mutation ever happens under the layer-map lock"（纯注释一行）。修复后 fmt 70 处基线、6/6 与全量 550 测试通过。

#### 轮次 3（最终双审查，最终 diff）

- Reviewer A（全新）：**CLEAN** —— 根因消除 CONFIRMED（真实修复，非隐藏）；红绿机制 CONFIRMED（旧实现失败断言与缺陷机制对应）；锁重入/协议时序/生命周期/UAF/泄漏/调用点遗漏/验收逐条全部 NOT-A-FINDING 或 CONFIRMED；最终 doc comment 措辞（niri-level 限定 + smithay 例外披露）与 smithay 源码行为逐字相符、句内自洽。
- Reviewer B（全新）：**CLEAN** —— 调用点完整迁移、无平行接口（两函数语义不同、调用点不交叉）、无范围外功能、A01.1-A01.5 + 2 新回归逐条可复跑、注释与记录（含行号、字节数、测试计数）逐项属实。
- 两者审查的最终 diff：niri 工作树相对 0cf398c4 的全量 T01 diff（/tmp/opencode/t01_full_diff.patch，762 行，含 6dca4819 与 rework 增量），`git diff --check` 干净。

### 8. 产品 Commit 与 push 收据（rework 轮）

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `a44ce8b1060b412ea98ecdbbcfb927751510872f` | `fix(layer): T01 output teardown rework — drop Tahoe pending/committed state on removal, close outside map lock` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `6dca4819..a44ce8b1` 成功 | `git merge-base --is-ancestor a44ce8b1 origin/tahoe-layer-animations` exit 0 |
| main | `85adaaae9bc498d0f32b67022242917de9e806ff` | `fix(submodule): bump niri for T01 output teardown rework (Tahoe pending/committed teardown, close outside map lock)` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `ead990a..85adaaa` 成功 | `git merge-base --is-ancestor 85adaaa origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → a44ce8b1（= 已推送 niri commit hash）
```

### 9. 完成判定（rework 轮）

**最终状态**：COMPLETE
**理由**：退回重做的四项要求全部落实——①锁范围（send_close 移出 layer-map guard，guard 内仅收集）；②Tahoe pending 状态（clear_glass_state_on_output_removal 全量清理 pending/pending_dirty/pending_transform/committed/directive）；③2 个红绿回归测试（旧实现 6dca4819 上以缺陷对应断言失败）；④实际二进制构建（debug + release）。A01.1-A01.5 + G01-G08 满足；三轮全新双审查全部 CLEAN（中间 PLAUSIBLE 均已按修复要求闭合）；niri 与主仓库产品 commit 均已 push 且远端 ancestor 验证 exit 0。
**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 10. 闭环记录审查与推送（rework 轮）

- Closure reviewer（全新只读上下文）：完成，PASS —— 两仓库 full hash/subject/parent/branch/remote ref/ancestor exit code/子模块指针/测试计数/fmt 基线/二进制字节数逐项与记录精确一致；红绿证明独立复现为真；工作树冻结（niri 干净，主仓库仅用户原有未跟踪项与本文档）；确认状态可置 COMPLETE，允许 docs-only closure commit。2 项 MINOR 记录精度问题已随本 closure 修正（基线指纹行号 3529→3483 并注明三态一致；红跑含回填 test-only accessor 的说明）。
- 产品 commit hash/remote receipt 是否逐项准确：是（closure reviewer 实测核对）
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T01 close task record`
- closure push remote ref：`origin/fix/tray-menu-pinned-surface-height`
- closure remote ancestor 验证 exit code：待 push 后以命令输出验证（本 commit 不记录自身 hash，由后续 `git log --format=%H -- execution-log.md` 解析）

---

## T02 window/output 生命周期 panic 清理

**状态**：IN_PROGRESS（产品实现 + 双审查完成，commit/push 进行中）
**开始时间**：2026-08-03
**roadmap 引用**：`roadmap.md#T02`（第 95-114 行）；发现 `research-report.md#STAB-02/STAB-03`（第 77-88 行）
**执行者上下文**：OpenCode / DeepSeek V4 Flash 会话（niri 子仓库 `tahoe-layer-animations` 分支）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| STAB-02: 最小化父窗口后创建 transient dialog，`Workspace::add_tile` 的 NextTo 分支 `active_window().unwrap()` panic | `src/layout/workspace.rs:646`；`active_window()`（workspace.rs:474-480）在 `scrolling.active_window()`（scrolling.rs:575-586，active tile 最小化返回 None）或 `floating.active_window()`（floating.rs:426-433，active_window_id 最小化返回 None）时为 None | CURRENT-CONFIRMED | 成立（红测试在 a44ce8b1 上于 workspace.rs:646:75 真实 abort：`called Option::unwrap() on a None value` + `panic in a function that cannot unwind`，即 FFI 回调内 abort） |
| STAB-03: `queue_redraw()` 对 `output_state` 无保护取值与 grab/动画定时器在 hot-unplug 时交叉 | 全部延迟 output 回调已有守卫：动画 redraw timer（niri.rs:4246 `let Some(...) else Drop`）、estimated-vblank timer（tty.rs:1813 `let Some(...) else`）、tty idle redraw（tty.rs:1558-1563 `contains_key`）、screencast timer（pw_utils.rs:943-945 `contains_key`）、screencast cast redraw（screencasting/mod.rs:160-162 `Weak::upgrade`）、vblank（tty.rs:1681-1697 现查 + guard）；`remove_output`（niri.rs:3300-3309）移除两类已跟踪 timer token | CURRENT-SATISFIED | 前提不成立（无 core、无 panic）：按 roadmap「若前提不成立，应以证据关闭任务，不做防御式散改」以测试+审计证据关闭，不修改生产代码 |
| 无 `queue_redraw_safe`/平行接口需要引入 | 全仓 rg 无该符号；`queue_redraw` 的 unwrap（niri.rs:4191）保留为活-output 不变量哨兵，所有延迟回调在调用前先验证成员资格 | CURRENT-CONFIRMED | 符合 roadmap 必须机制「不引入 queue_redraw_safe() 与旧 queue_redraw() 长期并存」 |

### 2. 工作树与范围

开始时 niri 子模块干净（HEAD `a44ce8b1`）；主仓库仅用户未跟踪项 `.zcode/`、`Testing/`、docs 目录。

允许修改：

- `niri/src/layout/workspace.rs`（NextTo 分支激活判定，唯一产品改动）
- `niri/src/tests/window_lifecycle.rs`（新增测试文件，7 个测试）
- `niri/src/tests/mod.rs`（注册一行，字母序）
- `execution-log.md`

明确禁止修改：

- `src/niri.rs`、`src/backend/`、`src/screencasting/`（STAB-03 已有守卫 authority 文件，前提已满足）
- Quickshell、Tahoe shell、主仓库用户项

定义/调用点/测试搜索（G01 清单）：

| `rg` 命令 | 命中数 | 修改点 | 不修改点及理由 |
|---|---:|---|---|
| `active_window()\.unwrap\|active_window_mut()\.unwrap` (src/ 非 tests) | 1 | `workspace.rs:646`（唯一失效前提调用点，已修） | 其余 14 处 `active_window()` 均 `.map`/`.is_some_and`/`.is_none` 安全组合（workspace.rs:476/478/805/874/1637、floating.rs:1741、monitor.rs:885/1042、layout/mod.rs:2656/3737/4811、ipc/server.rs:730/778、input/mod.rs:2281 等）；`workspace.rs:661-665` `tiles_with_render_positions().find().unwrap()` 前提不同（next_to 必须仍在布局；父已销毁时 compositor.rs:185-199 查找失败回退 Auto，测试 3 实证） |
| `output_state\.(get_mut\|get)\(.+\)\.unwrap()` (src/ 非 tests) | 20 | 无（STAB-03 证据关闭） | 延迟回调类全部已守卫：tty.rs:1558-1563（contains_key）、pw_utils.rs:943-945（contains_key）、niri.rs:4246-4249（get_mut else Drop）、tty.rs:1694/1813（入口 guard）、screencasting/mod.rs:160（Weak::upgrade + niri.rs:3311 stop_casts_for_target）；同步渲染路径（niri.rs:2224/2416/4789/4804/5055/5109/5227/5245/5355/5749/7122、tty.rs:1914/1941/1991/2300/3010、winit.rs:238/285、headless.rs:158）在 `redraw_queued_outputs` 对 output_state 的活遍历内或同步 IPC/render 路径，output 必存活；`queue_redraw`（niri.rs:4191）unwrap 哨兵仅被已验证成员资格的调用者触及（M2 变异证明） |
| `queue_redraw_safe\|QueueRedrawSafe` (全仓) | 0 | - | 未引入（roadmap 禁止替代） |

### 3. 旧实现失败基线（红绿证明）

在 a44ce8b1（旧实现）上运行新测试：

| 测试/probe | 旧结果 | 为什么能捕获根因 |
|---|---|---|
| `dialog_of_minimized_parent_maps_visible_and_focused`（A02.1） | FAIL：`workspace.rs:646:75` `called Option::unwrap() on a None value` + FFI 内 abort | 父窗口最小化后 `active_window()==None`，NextTo 分支 Smart 激活判定 unwrap panic，dialog 无法放置 |
| `dialog_of_minimized_floating_parent_maps_without_panic`（A02.2 floating） | FAIL：同一 panic | floating 父窗口最小化同样使 active_window()==None（floating.rs:426-433），panic 在分支前发生，与布局无关 |

STAB-03 侧（A02.3）双变异证明（G04 确定性 A/B，在最终代码上复现，均恢复）：

- M1（回调错误重绘剩余 output）：`assertion failed: stale callback must not redraw the remaining output, left: "Idle" right: "Queued"`（window_lifecycle.rs:509）——证明 out2 状态比较断言有判别力。
- M2（去掉 contains_key 守卫，回调对已移除 output 直接 queue_redraw）：`niri.rs:4191:55 called Option::unwrap() on a None value`——证明守卫是防 stale-callback panic 的必要机制，且 queue_redraw unwrap 仍存在（不变量哨兵）。

### 4. 实现机制

- 原 authority：`Workspace::add_tile` 的 `WorkspaceAddWindowTarget::NextTo` 分支（workspace.rs:645-692）。
- 原地修复：`self.active_window().unwrap().id() == next_to` → `self.active_window().is_none_or(|win| win.id() == next_to)`（workspace.rs:651-652），加 why 注释。三态语义：`ActivateWindow::Yes/No` 经 `map_smart`（layout/mod.rs:877-883）原样透传不变；`Smart` 分支 `Some(win)` 与旧行为逐位等价（`win.id() == next_to`）；唯一行为变化是 `None`（工作区所有窗口最小化，父窗口被最小化的 dialog 场景）从 abort 变为激活新 dialog——「选择合法 placement owner，而非 early return 丢窗口」：窗口在 `add_tile` 中无条件放置（floating `add_tile_above`/scrolling `add_tile_right_of`），激活语义与 Auto 分支一致。
- 被删除的旧 authority：`active_window().unwrap()`（生产代码清零）。
- STAB-03：无生产改动。三种处置明确：受跟踪 timer（animation-redraw/estimated-vblank）由 `remove_output`（niri.rs:3300-3309）取消；到达的 stale 回调（tty idle/pw timer 形态）由 contains_key 守卫丢弃；其余同步路径 output 必存活。
- 为什么没有平行接口：不改签名、不新增 API；`queue_redraw` 及其 unwrap 保持单一 authority。
- 为什么没有加入范围外功能：diff 仅 3 文件（workspace.rs +8/-1、tests/mod.rs +1、新测试文件），无配置/依赖/视觉变化。

### 5. 验收逐条

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见第 2 节 | PASS | 搜索表 + 未改点逐项理由 |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名、无 `queue_redraw_safe`、无新接口/flag |
| G03 | 专项+全量测试 | PASS | 见全量配置 |
| G04 | 红绿证明 | PASS | 2 红测试旧实现 panic（第 3 节）+ M1/M2 双变异 A/B 证据 |
| G05 | 双审查 | PASS | 第 6 节（7 轮，最终轮双 CLEAN） |
| G06 | commit/push 顺序 | 进行中 | 第 7 节 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话（全部 headless fixture） |
| A02.1 | `dialog_of_minimized_parent_maps_visible_and_focused` | PASS | 双 output 夹具：父最小化 → 切 active output → dialog 打开：mapped、非 minimized、成为其 workspace 的 active window（focus owner）、与父同 output 同 workspace（位置合法，错误放置到 active output 会失败）；session 不 abort；restore 父窗口后 dialog 保持 mapped |
| A02.2 | floating / destroy / restore | PASS | floating 父最小化不 panic（测试 2）；父销毁先于 map → compositor.rs 父查找失败回退 Auto 不 panic（测试 3）；restore 后 dialog 存活（测试 1 尾段）；tiled(scrolling) 由测试 1 覆盖 |
| A02.3 | cancel / drop / queued-at-removal 三个测试 | PASS | ①animation deadline 排队中移除 output，compositor loop 越过 deadline 不 panic、out2 保持 tracked（取消 token niri.rs:3300-3309 为源码证据）；②合成 deferred 回调（生产同模式）在移除后真实到达（fired 标志断言），contains_key 守卫丢弃，out2 排空后 Idle 前后不变；③仅 Queued 时移除不 panic；M1/M2 变异证明判别力 |
| A02.4 | 同类 unwrap 全仓审计 | PASS | 唯一 `active_window().unwrap()` 已修复；20 处 `output_state.*.unwrap()` 逐点不变量见第 2 节 |
| A02.5 | 全量 lib 测试 + `dialog_of_unfocused_parent_does_not_steal_focus` | PASS | 557 passed（含 placement/fullscreen/minimize 既有套件）；不聚焦父的 dialog 不抢焦点（锁定 Some≠next_to 旧语义） |

全量配置：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---:|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移全部改动前既有（与 T01 基线一致）；本次 3 个文件 fmt 零 diff |
| NIRI_FULL | `cargo test -p niri --lib` | 0 | 557 passed / 0 failed（550 旧 + 7 新） |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import） |
| 实际二进制 | `cargo build -p niri` | 0 | `target/debug/niri`（780,684,504 bytes） |
| 实际二进制 | `cargo build --release -p niri` | 0 | `target/release/niri`（138,732,056 bytes） |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

### 6. 独立审查（7 轮，最终轮双 CLEAN）

| 轮次 | Reviewer A | Reviewer B | 处理 |
|---|---|---|---|
| 1 | CLEAN；1 PLAUSIBLE（A02.3 断言措辞） | CLEAN；2 PLAUSIBLE（同断言措辞 + contains_key 代理） | 修注释；A02.1 改双 output 位置断言 + workspace 级 focus-owner 断言 |
| 2 | 1 PLAUSIBLE（双 output 位置断言在单 output 夹具下恒真） | 空返回（并入第 3 轮） | A02.1 改双 output + focus_output 切活动 output 可失败断言 |
| 3 | CLEAN（记录要求：STAB-03 按证据关闭） | NOT CLEAN：1 CONFIRMED（回调到达场景未构造、注释过度声明） | 新增第 7 测试（合成回调真实到达 + fired 标志 + 排空比较）；修注释 |
| 4 | CLEAN | 1 PLAUSIBLE（out2 状态比较恒真：排空位置在 remove 之前） | 排空移到 remove_output 之后 + Idle premise；M1/M2 复现 |
| 5 | NOT CLEAN：1 CONFIRMED（排空位置错误导致比较死代码）+ 2 PLAUSIBLE（注释过度声明） | NOT CLEAN：1 CONFIRMED（同注释）+ 2 PLAUSIBLE（记录义务） | 修正排空位置；取消测试注释改写为复合安全性质并 dispatch compositor loop；fixture 注释改正 |
| 6 | CLEAN | CLEAN（1 个 nit：行号引用） | 注释行号放宽为 3300-3309 |
| 7（最终） | **CLEAN**（根因消除 CONFIRMED、无遗漏、锁/生命周期/协议 CLEAN、Axx 证据真实、M1/M2 构成 G04 确定性 A/B、注释一致） | **CLEAN**（迁移完整、无平行接口、范围 3 文件、A02.1-A02.5 逐条可复跑、合成回调测试有效、G01-G08 满足） | - |

审查的最终 diff 标识：niri 工作树 diff（`src/layout/workspace.rs +8/-1`、`src/tests/mod.rs +1`、新 `src/tests/window_lifecycle.rs` 约 540 行），`git diff --check` 干净。

### 7. 产品 Commit 与 push 收据

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `eeb7169a352e928123871a74475cbe52d8e93b2d` | `fix(layout): T02 window/output lifecycle panic cleanup — dialog focus owner when all minimized, stale redraw disposition tests` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `a44ce8b1..eeb7169a` 成功 | `git merge-base --is-ancestor eeb7169a origin/tahoe-layer-animations` exit 0 |
| main | `4feff6970a37c08a6e1b423badf65ad926bc9b33` | `fix(submodule): bump niri for T02 window/output lifecycle panic cleanup` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `73f7186..4feff69` 成功 | `git merge-base --is-ancestor 4feff69 origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → eeb7169a（= 已推送 niri commit hash）
```

### 8. 未覆盖、用户现场项与后续边界

- 未覆盖：无产品代码缺口（A02.1-A02.5 全通过）。STAB-03 侧 tty estimated-vblank/vblank 与 screencast 的真实守卫路径在 headless 夹具不可达，以源码审计 + M1/M2 变异证据闭合（headless 中可构造的 arrival 路径已直接测试）。
- 需要用户授权的实时验证：无（纯源码/测试任务，未重启会话、未真实拔插）。
- 发现但属于后续任务的事项（只记录，未修改）：
  - NextTo Smart 激活不切换 `active_monitor_idx`（layout/mod.rs:1306 `map_smart(\|\| false)`）：多显示器下 dialog 聚焦于非活动 monitor 是既有模型（旧代码此处 abort，无回归），非 T02 范围。
  - `queue_redraw` 的 unwrap（niri.rs:4191）作为活-output 不变量哨兵保留：未来新增延迟回调若忘记先验证成员资格将 abort 会话；已在测试中以 M2 变异固化该契约，属 T03/T11 归因体系的长期 guardrail。

### 9. 完成判定

**最终状态**：COMPLETE
**理由**：A02.1-A02.5 + G01-G08 满足；2 个红测试旧实现 panic、新实现通过；M1/M2 双变异构成 G04 确定性 A/B；7 轮双审查最终轮双 CLEAN；fmt 基线 70 处为改动前既有；557 全量测试通过；实际二进制 debug+release 构建通过；niri 与主仓库产品 commit 均已 push 且远端 ancestor 验证 exit 0。
**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 10. 闭环记录审查与推送

- Closure reviewer（全新只读上下文）：待执行。
- 产品 commit hash/remote receipt 是否逐项准确：待 closure reviewer 实测核对。
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T02 close task record`
- closure push remote ref：`origin/fix/tray-menu-pinned-surface-height`
- closure remote ancestor 验证 exit code：待 push 后以命令输出验证（本 commit 不记录自身 hash，由后续 `git log --format=%H -- execution-log.md` 解析）

---

## 4. 阻塞记录要求

任务进入 `BLOCKED` 时必须记录：

- 已连续复现的阻塞条件和证据。
- 已尝试的安全替代路线。
- 为什么继续需要用户权限、外部状态或 roadmap 变更。
- 当前工作树和是否存在未提交实现。
- 明确写出“下一任务不得开始”。

解除阻塞后只能恢复同一任务，不能跳转。

---

## 5. 路线图收尾记录

T24 完成后填写：

```text
final timestamp:
main/niri/quickshell remote commits:
deployed versions and parity:
T01-T24 status audit:
unresolved review findings: must be none
remaining user-operated validations:
60-minute soak artifact paths:
frame/memory/resource comparison artifact paths:
final runtime warning summary:
```
