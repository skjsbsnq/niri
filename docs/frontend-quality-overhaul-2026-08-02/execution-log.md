# Tahoe Desktop 路线图执行日志

**用途**：T01-T24 的唯一状态锁与证据账本。
**当前状态**：T01 产品提交已推送并验证远端；docs-only 闭环 commit 待执行。
**禁止**：预填测试结果、审查结论、commit/push 收据或把计划写成已完成事实。

---

## 1. 状态表

| 任务 | 状态 | Commit subject / remote ref | 终审 | 备注 |
|---|---|---|---|---|
| T01 | COMPLETE | niri `6dca4819`（tahoe-layer-animations）/ main `3c265a8`（fix/tray-menu-pinned-surface-height） | 3 轮双审查 CLEAN | output layer teardown |
| T02 | PENDING | - | - | window/output lifetime |
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
baseline test failures: cargo test -p niri --lib = 544 passed（0 failed）；cargo fmt --all -- --check 有 70 处改动前既存的格式化漂移（非本任务引入，涉及 niri-config、handlers、input、tests 等既有文件；其中 niri.rs 4 处 1036/1437/1450/3529 均在本次 diff 之外）
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
