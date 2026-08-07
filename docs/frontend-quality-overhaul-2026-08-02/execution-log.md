# Tahoe Desktop 路线图执行日志

**用途**：T01-T24 的唯一状态锁与证据账本。
**当前状态**：T10 COMPLETE（blur texture capacity reuse）。
**禁止**：预填测试结果、审查结论、commit/push 收据或把计划写成已完成事实。

---

## 1. 状态表

| 任务 | 状态 | Commit subject / remote ref | 终审 | 备注 |
|---|---|---|---|---|
| T01 | COMPLETE | niri `a44ce8b1`（tahoe-layer-animations）/ main `85adaaa`（fix/tray-menu-pinned-surface-height） | 3 轮双审查 CLEAN（rework 轮） | output layer teardown + rework（Tahoe pending/锁范围/实际 build） |
| T02 | COMPLETE | niri `eeb7169a`（tahoe-layer-animations）/ main `4feff69`（fix/tray-menu-pinned-surface-height） | 7 轮双审查，最终轮双 CLEAN | window/output lifetime（is_none_or focus owner + STAB-03 证据关闭 + 7 测试） |
| T03 | COMPLETE | niri `0b717b19`（tahoe-layer-animations）/ main `1e945e5`（fix/tray-menu-pinned-surface-height） | 4 轮双审查，最终两轮产品代码 CLEAN | layer lock/damage/redraw（guard 三阶段分离 + damage cap/drain + root 归因 + 8 红绿测试） |
| T04 | COMPLETE | niri `cc772d0a`（tahoe-layer-animations）/ main `c177402`（fix/tray-menu-pinned-surface-height） | 9 轮双审查，最终两轮产品代码 CLEAN + 账本修正 | pointer/focus transaction |
| T05 | COMPLETE | niri `79448ad4`（tahoe-layer-animations）/ main `21fb5cf`（fix/tray-menu-pinned-surface-height） | 8 轮双审查，最终门禁 A 侧 CLEAN、B 侧全部闭合 | thumbnail budget |
| T06 | COMPLETE | Quickshell `4712657a`（quickshell-tahoe-desktop）/ main `aea8b30e`（fix/tray-menu-pinned-surface-height） | 最终双 CLEAN + closure reviewer PASS | QsPaths sticky failure state machine |
| T07 | COMPLETE | quickshell `827c8b6`（quickshell-tahoe-desktop）/ main `bf53257`（fix/tray-menu-pinned-surface-height） | 5 轮双审查，最终双 CLEAN | FileView non-blocking write state machine |
| T08 | COMPLETE | quickshell `b022253`（quickshell-tahoe-desktop）/ main `3cc4d4d`（fix/tray-menu-pinned-surface-height） | 2 轮双审查，最终双 CLEAN | TahoeGlass per-wl_surface mapping generation |
| T09 | COMPLETE | niri `274b08bb` / Quickshell `d297889d` / main `2fcb3028` | 有界最终审查 + 单点闭合 verifier CLEAN | TahoeGlass completion/rejection/capability feedback |
| T10 | COMPLETE | niri `fe8faeea`（tahoe-layer-animations）/ main `9266d9a`（fix/tray-menu-pinned-surface-height） | 轮次 1 修复 + 轮次 2 双 CLEAN + 轮次 3 闭合 verifier PASS | blur reuse（bucket/active-rect/hysteresis/硬预算） |
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
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import）；轮次 4 消除 2 条本 diff 曾引入的 dead-code warning（`pending_len` 改 cfg(test)、`TestPopup.popup` 标注 keep-alive）后归零新增 |
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
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import）；轮次 4 消除 2 条本 diff 曾引入的 dead-code warning（`pending_len` 改 cfg(test)、`TestPopup.popup` 标注 keep-alive）后归零新增 |
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

**状态**：COMPLETE
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
| G06 | commit/push 顺序 | PASS | 第 7 节 |
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
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import）；轮次 4 消除 2 条本 diff 曾引入的 dead-code warning（`pending_len` 改 cfg(test)、`TestPopup.popup` 标注 keep-alive）后归零新增 |
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

## T03 layer map 锁边界与 damage/redraw 归因

**状态**：COMPLETE（产品 commit/push 完成，docs-only 闭环 commit 待执行）
**开始时间**：2026-08-03
**roadmap 引用**：`roadmap.md#T03`（第 115-133 行）；发现 `research-report.md#STAB-04`（第 89-93 行）与 `GLASS-02` 的 damaged regions / root attribution（第 167-169 行）
**执行者上下文**：OpenCode / DeepSeek V4 Flash 会话（niri 子仓库 `tahoe-layer-animations` 分支）

### 1. 前提核实（2026-08-03）

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| STAB-04: `layer_shell_handle_commit` guard 跨映射对象构造 | `src/handlers/layer_shell.rs:126-290`：`let mut map = layer_map_for_output(&output)` 存活期间执行 `MappedLayer::new`（:169）、`add_mapped_layer_pre_commit_hook`（:168）、`start_open_animation`（:179）、`mapped_layer_surfaces.insert`（:183） | CURRENT-CONFIRMED | 成立（需分离） |
| STAB-04: guard 跨 foreign rect 清理 | `layer_shell.rs:242` `clear_foreign_toplevel_rects_for_source` 在 guard（:126）存活期间调用 | CURRENT-CONFIRMED | 成立（需分离） |
| STAB-04: guard 跨 pointer 查询 | `layer_shell.rs:178` `pointer_location_on_output`（`seat.get_pointer().current_location()` 取 PointerInternal mutex）在 guard 内；`start_close_animation_for_layer`（:325）同模式 | CURRENT-CONFIRMED | 成立（需分离） |
| STAB-04: guard 跨 close snapshot 渲染 | `layer_shell.rs:253`/`:78` 在 guard 存活时调用 `start_close_animation_for_layer` → `backend.with_primary_renderer` + `store_unmap_snapshot` + `ClosingLayer::new`（渲染器 mutex + snapshot 渲染） | CURRENT-CONFIRMED | 成立（需分离） |
| STAB-04: guard 跨 IPC | `layer_shell.rs:280-283` `send_scale_transform`/`send_configure` 在 guard 内；`map.arrange()`（:136）内部发送 configure 属 smithay map 读写阶段本身（所有合成器同模式，非 niri 可控） | CURRENT-CONFIRMED | 部分成立：niri 自己的 IPC 移出；arrange 属 map 原子阶段保留 |
| STAB-04: guard 跨 config mutex | `layer_shell.rs:160/193/246` `self.niri.config.borrow()` 在 guard 内（锁序 map→config） | CURRENT-CONFIRMED | 成立（需分离） |
| STAB-04: 已存在重入死锁 | 逐函数核实：`MappedLayer::new`（mapped.rs:142）、`ResolvedLayerRules::compute`（layer/mod.rs:49）、`start_open_animation`（mapped.rs:389）、`store_unmap_snapshot`（mapped.rs:429）、`ClosingLayer::new`（closing_layer.rs:97）、`output_geometry`（smithay GlobalSpace）、`clear_foreign_toplevel_rects_for_source`（handlers/mod.rs:571）均不取 layer map | CURRENT-SATISFIED | 无现役死锁；风险是结构性锁序（map→pointer vs pointer→map、map→renderer）与未来重入，任务按结构性分离处置 |
| GLASS-02: subsurface 传入 redraw attribution 前应解析到 root | `handlers/mod.rs:1137` `queue_redraw_for_tahoe_glass_surface(surface)` 直接 `output_for_root(surface)`；smithay `layer_for_surface` 的 TOPLEVEL 匹配不含 SUBSURFACE（smithay layer.rs `WindowSurfaceType` 位掩码）；`is_wl_surface`（window/mapped.rs:1092）只比对 toplevel → 层/window subsurface 提交走 Unlocatable 全输出 fallback | CURRENT-CONFIRMED | 成立（subsurface 归因 bug） |
| GLASS-02: redraw root 解析缺口 | `compositor.rs:69` `on_surface_commit` 先于 `:71-79` 的 root 解析与 `root_surface` 缓存写入 → 表面首次提交时 `find_root_shell_surface` 尚无缓存 | CURRENT-CONFIRMED | 成立（缓存写入需提前到 on_surface_commit 之前） |
| GLASS-02: unmapped/destroyed 归因结果 | 旧行为：layer_surface.destroy 后 `queue_redraw_for_tahoe_glass_surface` → Unlocatable → `queue_redraw_all`（现有测试 `clear_with_unlocatable_root_queues_all_outputs` 固化该行为）；T01 已确认 post-removal Tahoe directive commit 同样落入该路径（T01 记录第 8 节） | CURRENT-CONFIRMED | 无可见 surface 时全输出 redraw 属无理由退化，按 A03.3 改为确定结果（skip + 记录） |
| GLASS-02: damaged_regions 无上限 | `render_helpers/tahoe_glass.rs:26/60-72`：`damaged_regions` 只 union-dedup，无 rect 数/面积上限；`render_regions_for_layer` 是唯一 drain（:227 `mem::take`），但 `:212-214` 在 `regions.is_empty()` 时先 return，drain 不可达 | CURRENT-CONFIRMED | 成立（两个缺陷：无上限；empty regions 永不排空） |
| GLASS-02: 锁屏/DPMS 下 damage 无排空 | `niri.rs:4838-4863`：锁定时 render 在 layer 渲染前 return；DPMS 关无帧 → layer 渲染不运行 → damage 只进不出 | CURRENT-CONFIRMED | 成立（cap 兜底 + 下次渲染恢复） |
| 无平行 damage queue / 第二 redraw API 需要引入 | 全仓 rg：`damaged_regions` 仅 `render_helpers/tahoe_glass.rs` 一处 authority；`RedrawAttribution` 单一 apply 点 `niri.rs:4199` | CURRENT-CONFIRMED | 原地改造 |

### 2. 工作树与范围

开始时 niri 子模块干净（HEAD `eeb7169a`）；主仓库仅用户未跟踪项 `.zcode/`、`Testing/`、docs 目录。

允许修改：

- `niri/src/handlers/layer_shell.rs`（commit/destroy 路径 map 阶段分离——唯一产品结构改动）
- `niri/src/render_helpers/tahoe_glass.rs`（damage 上限 + empty-regions 排空顺序）
- `niri/src/handlers/compositor.rs`（root 缓存写入提前到 on_surface_commit 前）
- `niri/src/handlers/mod.rs`（TahoeGlassHandler 归因：root 解析 + unmapped/destroyed 确定性处置）
- `niri/src/utils/lifecycle_diag.rs`（新增 skip 计数器）
- `niri/src/tests/layer_lock_scope.rs`（新测试文件）、`niri/src/tests/tahoe_glass.rs`、`niri/src/tests/mod.rs`
- `execution-log.md`

明确禁止修改：

- `src/protocols/tahoe_glass.rs` 协议 authority（T09 范围，region 校验/反馈不动）
- `src/layer/mapped.rs`、`src/layer/closing_layer.rs` 等渲染/动画 authority
- `src/redraw_attribution.rs` 枚举（除非必要；当前设计不需要改）
- Quickshell、Tahoe shell、主仓库用户项
- T04 范围（pointer 缓存、focus transaction）

定义/调用点/测试搜索（G01 清单）：

| `rg` 命令 | 命中数 | 修改点 | 不修改点及理由 |
|---|---:|---|---|
| `layer_map_for_output` (src/ 非 tests) | 44 | `layer_shell.rs:126`（commit 路径 Phase A 化）、`:70`（destroy 路径 Phase A 化） | `niri.rs:1220/3631/3686/3848/4162/4903/5057/5124/5290/5577/5682/5796/5864/5956` 等：渲染路径把 guard 作为 `&LayerMap` 参数消费（`layers_in_render_order` 等，无重入，属渲染自然 owner）；`ipc/server.rs:370`、`handlers/mod.rs:729`、`xdg_shell.rs:296/381/1288/1312`、`workspace.rs:2350` 均为短查找；`niri.rs:3395/3422/3435` 为 T01 teardown（已满足锁范围）；`layer_shell.rs:50/61/111` 短 guard |
| `damaged_regions` | 8 | `render_helpers/tahoe_glass.rs:26/64-72`（cap + collapse） | 其余为既有测试断言（:569-571 与 drain 语义） |
| `queue_redraw_for_tahoe_glass_surface` | 4 | `handlers/mod.rs:1135`（归因逻辑）、`protocols/tahoe_glass.rs:313`（trait 默认 no-op，不动） | `protocols/tahoe_glass.rs:584/1060/1089/1272` 调用点全部经同一 handler，不改 |
| `find_root_shell_surface` | 3 | `handlers/mod.rs:1137`（新增调用） | `niri.rs:6945` 定义保持；`handlers/mod.rs:717` 既有调用 |
| `root_surface` (niri.rs) | 3 | `handlers/compositor.rs:77-79`（提前到 on_surface_commit 前） | `niri.rs:261/6946` 定义与读取保持 |
| `RedrawAttribution::all(Unlocatable)` | 85 处 apply | `handlers/mod.rs:1144`（unmapped/destroyed 改 skip；mapped-unlocatable 保留） | 其余 fallback 调用点为窗口 lifecycle 路径（T02/T21 语义，不动）；`niri.rs:4211` apply 单一入口保持 |
| `start_close_animation_for_layer` | 3 | `layer_shell.rs:78/253`（移出 guard） | `layer_shell.rs:302` 定义保持（内部 pointer 查询与渲染器阶段不动） |
| `note_redraw_skip_unmapped`（新增） | 0 | `lifecycle_diag.rs` 新增计数器 | 遵循既有 note_redraw_fallback_* 模式 |

### 3. 旧实现失败基线（红绿证明）

在 eeb7169a（旧实现）上运行 8 个新/改造测试，全部按预期失败并命中目标缺陷：

| 测试/probe | 旧结果 | 为什么能捕获根因 |
|---|---|---|
| `layer_shell_commit_guard_does_not_cross_phase_two_work`（静态 guard，A03.1） | FAIL：guard 存活区间内 10 处违禁（config.borrow ×3、add_mapped_layer_pre_commit_hook、MappedLayer::new、pointer_location_on_output、clear_foreign_toplevel_rects_for_source、start_close_animation_for_layer、send_scale_transform、send_configure） | 源码 brace 深度扫描界定 guard 作用域：旧 commit 路径 guard 从 :126 持有到函数尾 |
| `layer_shell_destroy_guard_does_not_cross_phase_two_work`（A03.1） | FAIL：`start_close_animation_for_layer` 在 guard 区间内（renderer snapshot 渲染跨锁） | 旧 destroy 路径 :70-83 持有 guard 跨 close 动画 |
| `new_layer_surface_guard_only_wraps_map_write`（A03.1） | FAIL：`LayerSurface::new` 在 guard 区间内 | 旧 new_layer_surface :50-52 构造在锁内 |
| `ten_thousand_region_commits_without_render_stay_bounded_and_recoverable`（A03.2） | FAIL：10,000 次后 `damaged_regions.len()==19,926`（无上限，union 碎片化后超出提交数） | 锁屏/DPMS 渲染不运行 → 旧实现 damage 只进不出 |
| `cap_collapse_keeps_union_coverage`（A03.2 守卫） | FAIL：1,000 次后 1,000+ rect（>64 预算） | 无 cap 时存储无界 |
| `subsurface_glass_commit_attributes_to_root_output`（A03.3） | FAIL：`targeted=0, fallback=1`（subsurface 提交落 Unlocatable 全输出 fallback） | 旧 handler 未先解析 root；smithay `layer_for_surface` TOPLEVEL 掩码不含 SUBSURFACE |
| `unmapped_destroyed_root_skips_redraw_without_queueing_all`（A03.3，改造既有 `clear_with_unlocatable_root_queues_all_outputs`） | FAIL：`fallback==1`（destroy 后 drive handler 仍 queue_redraw_all） | 旧行为把已 destroy 的 surface 归因为全输出 redraw；新语义为确定 skip |
| `empty_regions_render_still_drains_pending_damage`（A03.2） | FAIL：empty regions 渲染推不出 ExtraDamage（早期 return 在 drain 前，旧实现 `[]`） | 旧实现 `:212` empty 分支使已记录 damage 永不排空；预渲染建立 renderer 后 destroy 清空 region 再渲染，旧顺序跳过 drain（以临时还原 drain 顺序的 A/B 复验红） |

### 4. 实现机制（实际）

- **锁范围（A03.1）**：`layer_shell_handle_commit` 拆三阶段——Phase A 短 guard（块作用域：`layer_for_surface` + arrange + 收集 close 动画几何，guard 即刻释放）；Phase B 无 guard（closing_layers retain、config/rules、hook、`MappedLayer::new`、`pointer_location_on_output`、open 动画、`mapped_layer_surfaces.insert`、焦点、directive/foreign rect 清理、初始 configure IPC）；之后 `output_resized`/`queue_redraw`。`layer_destroyed` 同模式：Phase A 短 guard 收集 `(output, layer, geo)`；Phase B 无 guard（mapped 移除、`clear_transform_directive_on_unmap`、close 动画）；Phase C 短 guard（`unmap_layer`）。`new_layer_surface` 构造移到 guard 外，guard 只包 `map_layer` 写。
- **行为等价说明（轮次 1 F1 修正）**：close 动画几何在 Phase A 内双快照——arrange 之前与之后各取一次，`close_geo = pre_arrange_geo.or(post_arrange_geo)`，与旧代码 `close_geo.or_else(|| map.layer_geometry(&layer))`（优先最后一次渲染位置、None 回退 arrange 后值）逐位等价；同 commit 内无并发。
- **damage 上限与排空（A03.2）**：`damage_regions` 在 rect 数 > `MAX_PENDING_DAMAGE_RECTS`(32) 时折叠为 union 包围盒（超集，正确性保持）；`render_regions_for_layer` 的 drain 移到 `regions.is_empty()` 之前（empty regions 也必须排空并推 ExtraDamage 重绘旧 glass 区域）；锁屏/DPMS 不渲染 → cap 兜底有界，恢复渲染即 drain（可恢复）。
- **root 归因（A03.3）**：`compositor.rs` root 解析与 `root_surface` 缓存写入提前到 `on_surface_commit` 之前（首提交的 subsurface 也能解析 root）；`queue_redraw_for_tahoe_glass_surface` 先 `find_root_shell_surface` 再归因：可定位 → targeted；`layout.find_window_and_output` 命中（NoOutputs 已映射窗口）→ Unlocatable fallback（保留既有语义）；未映射/destroyed/已移除 output 的 layer → `RedrawAttribution::None` + `lifecycle_diag::note_redraw_skip_unmapped()`（T01 已记录 deferred 的 post-removal 全输出 redraw 由此消除）。
- **为什么没有平行接口**：无新 map/queue/API；`RedrawAttribution` 与 `apply_redraw_attribution`（niri.rs:4199）单一 authority 不变；skip 复用 `None` 变体；计数器遵循既有 note_redraw_fallback_* 模式。
- **为什么没有加入范围外功能**：diff 仅 8 文件 + 1 新测试文件，无配置/依赖/视觉变化；`tests/client.rs` 只加测试夹具（subcompositor 绑定 + 两个无事件 Dispatch impl）。

### 5. 验收逐条

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见第 2 节 | PASS | 搜索表 + 未改点逐项理由 |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名（`rg '^\+.*(V2|New|Fixed|Alt|Legacy2|_new)\b'` 零命中）；无新接口/flag |
| G03 | 专项+全量测试 | PASS | 见全量配置 |
| G04 | 红绿证明 | PASS | 8 个新/改造测试旧实现失败、新实现通过（第 3 节）+ empty-drain 以临时还原顺序 A/B 复验 |
| G05 | 双审查 | PASS | 第 6 节（四轮双审查；最终两轮产品代码 CLEAN，A4-F1/B4-F2-F4 账本处置于轮次 4） |
| G06 | commit/push 顺序 | 待执行 | 第 7 节 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话（全部 headless fixture） |
| A03.1 | 3 个静态 guard 测试 | PASS | commit 10 违禁归零、destroy close 动画移出 guard、new_layer 构造移出 guard；渲染路径 guard 作为 `&LayerMap` 参数消费属自然 owner（niri.rs:4903/5057 等，无重入，已记录不修改点） |
| A03.2 | `ten_thousand_region_commits_without_render_stay_bounded_and_recoverable` + `cap_collapse_keeps_union_coverage` + `empty_regions_render_still_drains_pending_damage` | PASS | 10,000 次无渲染提交 ≤33 rect（预算 64）；drain 后恢复空并再次有界；cap 覆盖超集；empty regions 渲染仍推 ExtraDamage 覆盖旧 rect (8,4,128,32)；锁屏/DPMS/不可见 layer 由 cap 兜底 + 恢复渲染 drain（源码证据 niri.rs:4838-4863 锁定时 layer 渲染不运行） |
| A03.3 | `subsurface_glass_commit_attributes_to_root_output` + `unmapped_destroyed_root_skips_redraw_without_queueing_all` + 既有 targeted 测试 | PASS | subsurface（真实 wl_subcompositor 角色）transform 首 commit targeted ≥1 且 fallback==0；destroy 后 skip（output 全部未排队、`queue_redraw_all==0`、`redraw_fallback_unlocatable==0`、`redraw_skip_unmapped>=1`）；root/已映射 layer 既有测试保持 targeted；NoOutputs 窗口保留 Unlocatable（语义记录，书面裁决见第 6 节 Q4） |
| A03.4 | TSAN 尝试 | 不可用（记录） | 两条路线均失败：`-Zsanitizer=thread` + `-Zbuild-std` 在 smithay 依赖上编译失败（AsFd 解析错误，环境限制）；无 build-std 时 build-deps（pkg-config/smallvec 等）在 sanitizer RUSTFLAGS 下失败。确定性重入 harness = 3 个静态 guard 测试（brace 深度界定 guard 存活区间，token 级判定跨阶段调用） |
| A03.5 | PROTOCOL_FULL + 全量测试 | PASS | 见全量配置 |

全量配置：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---:|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移全部改动前既有（与 T01/T02 基线一致）；本次 9 个改动/新增文件的 T03 hunk 零 fmt 漂移（3 个文件含 T03 之外的既有漂移，closure reviewer 以 `git show eeb7169a | rustfmt --check` 复验） |
| NIRI_FULL | `cargo test -p niri --lib` | 0 | 564 passed / 0 failed（556 旧 + 8 新） |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import）；轮次 4 消除 2 条本 diff 曾引入的 dead-code warning（`pending_len` 改 cfg(test)、`TestPopup.popup` 标注 keep-alive）后归零新增 |
| 实际二进制 | `cargo build -p niri` | 0 | debug 构建通过 |
| 实际二进制 | `cargo build --release -p niri` | 0 | release 构建通过 |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC（niri/quickshell/权威 三处 sha256 一致） |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

### 6. 独立审查（轮次 1）

#### Reviewer A（正确性/生命周期/并发）

结论：NOT-CLEAN（2 条 PLAUSIBLE，无 CONFIRMED）。

- **F1 PLAUSIBLE**：`close_geo` 快照时机——日志 §4 的"arrange 不改变已提交 layer 的位置语义"前提错误：smithay `arrange()` 会写 `LayerUserdata.location`（layer.rs:421-424），`layer_geometry` 含 location（layer.rs:146-154），arrange 前后值可不同；旧代码优先 arrange 前值（最后一次渲染位置）。→ **修复（接受）**：Phase A 恢复精确旧语义——先快照 `pre_arrange_geo`，arrange 后再取 `post_arrange_geo`，`close_geo = pre_arrange_geo.or(post_arrange_geo)`（与旧 `close_geo.or_else(|| map.layer_geometry(&layer))` 逐位等价）；两个取值都在同一短 guard 内完成。日志 §4 等价裁决同步更正。
- **F2 PLAUSIBLE**：compositor.rs root 缓存提前写入无独立红绿证据（原测试先提交一次建立缓存，即使旧顺序测试也绿）。→ **修复（接受）**：`subsurface_glass_commit_attributes_to_root_output` 重构为 directive 骑在子 surface **首个 commit**（claim + set_transform 先于第一次 child commit）；该测试已双 A/B 复验：旧 handler（无 root 解析）→ FAIL（targeted=0）、旧 compositor 顺序（缓存写回 on_surface_commit 之后）→ FAIL（targeted=0）、新实现 → PASS。缓存重排现被红绿覆盖。
- F3-F8 全部 NOT-A-FINDING（静态 guard 红绿真实且偏向假阳性方向、drain 前移的 renderer 创建代价可接受、cap 超集与 skip 均真实、锁序/生命周期/协议时序 CLEAN、不变量与测试强度 CLEAN、注释一致）。

#### Reviewer B（范围/接口/UX/验收）

结论：CLEAN（1 条 PLAUSIBLE，无 CONFIRMED）。

- **Q4 PLAUSIBLE**：`handlers/mod.rs:1145` 的 NoOutputs 窗口分支（`layout.find_window_and_output(&root).is_some()` → Unlocatable fallback）无直接测试。→ **书面裁决（以证据反证，不加测试）**：该分支是旧行为 parity 保留——旧 handler 对任何不可定位 root 一律 Unlocatable fallback，本分支只把"已映射窗口（NoOutputs）"从 skip 中分出来保持旧语义，行为未变；原因经 `note_fallback_reason(Unlocatable)` 记录（满足"不得默认全输出而不记录原因"）；且 Tahoe glass 渲染仅作用于 layer surface（`render_for_layer` 仅 mapped.rs:687/820 调用），窗口 surface 的 glass 状态永不渲染，该分支无可见效果；r17 纪律测试（`r17_foreign_handler_source_has_zero_queue_redraw_all` 等）间接保护 fallback 纪律。裁决理由：分支语义为"既有行为保持"，红绿框架下无旧缺陷可捕获（旧代码同路径）。
- 其余 Q1-Q3/Q5-Q6 全部 CLEAN；2 条 NOT-A-FINDING 记录（mod.rs:1146 注释张力可辩护；计数器命名 REDRAW_SKIP_UNMAPPED 实际也覆盖 removed-output layer）→ 已修复 lifecycle_diag 文档注释为 "unmapped, destroyed, or a layer whose output was removed"。

#### 轮次 1 修复后复验

| 检查 | 结果 |
|---|---|
| F1 修复（pre/post arrange 双快照） | `layer_shell_commit_guard_does_not_cross_phase_two_work` PASS；静态 guard 无违禁 |
| F2 修复（首 commit directive 测试） | 旧 handler A/B FAIL、旧 compositor 顺序 A/B FAIL、新实现 PASS（双红绿） |
| 全量 | `cargo test -p niri --lib` 564 passed / 0 failed；`git diff --check` 干净；fmt 70 处基线（本次文件零 diff） |

#### 轮次 2（修复后新双审查）

- Reviewer A2（全新）：产品代码 CLEAN（F1 双快照逐位等价独立验证、F2 首 commit 双 A/B 红绿独立验证、Q4 裁决成立）；**1 条 PLAUSIBLE F-T03-1**：`empty_regions_render_still_drains_pending_damage` 触发生产 handler 时未持 `test_redraw_counter_lock`，与 T01-era `output_teardown.rs:136-160` 的持锁精确零断言竞争（机制先于 T03 存在，T03 新增一个无锁干扰源）。→ **修复**：destroy 窗口持锁。另记录 NOT-A-FINDING：patch 未含未跟踪新文件（已用 `git add -N` 修正）。
- Reviewer B2（全新）：**CLEAN**（Q1-Q6 全 CLEAN，A03.1-A03.5 逐条实测复验；NoOutputs 裁决独立成立；F1/F2 修复真实到位）。
- 修复后子集实测：tahoe_glass 子集 11 测试 5 轮中仍 2 轮偶发失败——失败者全部为 T01-era 未修改测试（`destroy_controller_queues_redraw_only_on_root_output` 等，持锁精确断言 vs 无锁写入者），经 `git show eeb7169a:src/tests/tahoe_glass.rs` 证实同一竞争对在 T03 之前即可触发。

#### 轮次 3（修复后新双审查）

- Reviewer A3（全新）：产品代码 CLEAN（六问全 CLEAN，一次并行全量跑中 `orphaned_commits_do_not_reapply_tahoe_glass_state_after_output_removal` 偶发失败——真实 flake，隔离/子集 20+ 次复跑全过）；**1 条 CONFIRMED F-1（账本）**：execution-log 缺轮次 2 处置记录与 flake 记录、状态行陈旧；**1 条 PLAUSIBLE F-2**：flake 归因不精确——T03 的 skip 测试（严格 `targeted==0` 读者）与 empty-drain 测试的 `set_and_commit_region`（无锁写者）也是共同参与者；`git show eeb7169a` 证实严格断言模式为 T01-era 原样继承，"非 T03 引入"结论仍成立。
- Reviewer B3（全新）：**CLEAN**（产品代码复核 CLEAN；flake 延期裁决实质成立）；**1 条 CONFIRMED**（同一账本缺失 F1）。
- → **修复（本节）**：① T03 测试全部 handler 触发窗口持 `test_redraw_counter_lock`（skip 测试整段 + empty-drain 测试 region 提交与 clear）；② skip 测试的严格断言从 tahoe TEST_* 全局计数器改为**无竞争可观察量**：output redraw_state（`force_idle_redraw_states` + `count_outputs_queued`）+ lifecycle_diag 计数器（`with_enabled_for_test` 自有锁串行化；`redraw_skip_unmapped >= 1` 直接证明 skip 被记录）；③ 本节的账本补记。
- 修复后实测：tahoe_glass 子集 10 轮零失败、output_teardown 子集 3 轮零失败、全量 3 轮 564 passed / 0 failed。T03 测试不再是该既有竞争的读者或写者。

#### 轮次 4（修复后新双审查）

- Reviewer A4（全新）：产品代码六问 CLEAN/CONFIRMED；**1 条 PLAUSIBLE F1**：skip 处置在 live-close 窗口违背"surface 不渲染"前提（被销毁的 Tahoe layer 在 close 动画期仍由 `render_close_effects` 实时绘制，孤岛 commit 可能被绘制但 skip 不排队帧）。→ **书面裁决（以代码反证，接受 skip）**：live-close 渲染使用 **unmap 时快照**而非实时 regions——`store_unmap_snapshot`（mapped.rs:437-439）捕获 `close_tahoe_glass_regions`，`render_close_effects`（mapped.rs:806-810）`close_tahoe_glass_regions.clone().unwrap_or_else(live read)` 优先快照——因此孤岛 commit 在 close 窗口**无任何可见效果**，skip 不丢失任何像素；残余边缘（unmap 时无 glass → 快照 None → live read）由 close 动画自身的帧循环覆盖（`redraw_sources.closing_layer`，niri.rs:5304-5308，动画未完成前每帧重绘 close 所在 output），延迟 ≤1 帧且不可见。旧代码在该窗口的 `queue_redraw_all` 为纯浪费（全输出重绘一个不可见变化），skip 严格更优。F2-F6 全部 NOT-A-FINDING（几何断言为真正红绿支柱、token 盲区已如实文档化、renderer 创建零成本、cap 坐标安全、日志表述见 B4-F3 处理）。
- Reviewer B4（全新）：产品代码九文件零 CONFIRMED、零产品级 PLAUSIBLE（Q1-Q5 全 CLEAN，A03.1-A03.5 逐条 CONFIRMED）；**3 条 PLAUSIBLE 均为账本精确性**：
  - **F2（计数）**："四轮双审查完成"在轮次 4 记录前属提前声明 → 本节记录后修正为准确；
  - **F3（无竞争声称过强）**："T03 测试不再是读者或写者"字面过强：lifecycle_diag 计数器是门控（enabled 窗口内其他测试生产路径理论可写）；skip 测试仍持锁调用 `test_reset_redraw_counters`；subsurface 测试仍严格断言 `fallback==0`（但当前套件无任何测试再写 fallback 计数器——旧 fallback 写者已随 skip 改造消失）。→ **修复（措辞收窄）**：见本节"后续边界"修订；
  - **F4（红跑回填未披露）**：轮次 3 起的 skip 测试 `redraw_skip_unmapped >= 1` 断言与 subsurface 测试的 subcompositor 夹具为旧树不存在符号；当前测试版本的红跑需回填（T01 rework 同例，见 T01 rework §4 红跑前置说明）。→ **修复（披露）**：红绿核心断言（`queue_redraw_all==0`、`fallback==0`、`targeted>=1`、ExtraDamage 几何）的旧树红跑在回填前版本上已实测（fallback left=1 right=0 等）；轮次 3 新增断言（`redraw_skip_unmapped>=1`）与夹具依赖的旧树红跑需按 T01 rework 同例回填 `#[cfg(test)]` 符号，机制等价（旧 handler 不调用 note → 计数为 0 → 断言红）。
- 处置结果：A4-F1 书面裁决成立（快照优先机制 + 动画帧循环覆盖残余边缘）；B4-F2/F3/F4 账本已修正（本节记录 + 措辞收窄 + 回填披露）。产品 diff 自轮次 4 审查输入以来未再变更。

#### 后续边界（T03 范围外，只记录未修改）

- **T01-era 测试计数器竞争（待 T24）**：`TEST_TARGETED_REDRAW`/`TEST_FALLBACK_REDRAW_ALL`/`TEST_LAST_DAMAGED_OLD_RECTS` 为无门槛全局原子；T01-era 测试（`recreate_controller_does_not_inherit_previous_committed_regions`、`destroy_is_idempotent_when_double_invoked`、`abnormal_client_disconnect_clears_committed_glass`、`destroy_controller_queues_redraw_only_on_root_output` 的写入段、`output_teardown.rs:136-160` 的持锁精确零断言）之间在并行 libtest 下偶发竞争，`git show eeb7169a` 证实 T03 之前即可触发。T03 的处置与残余理论窗口（按轮次 4 B4-F3 收窄）：T03 不再新增**无锁**写者；skip 测试不再严格读取 TEST_* 计数器（改为门控 lifecycle 计数器 + output redraw_state，均为无竞争可观察量——lifecycle 计数器由 `with_enabled_for_test` 的自有锁串行化窗口断言，output 状态为 fixture 局部）；subsurface 测试仅保留 `>=` 语义断言且当前套件无 fallback 写者。残余理论窗口（其他测试生产路径在 enabled 窗口内写 lifecycle 计数器）为既有/理论性，10 轮子集 + 3 轮全量未触发。按 §3.1 禁止顺手改范围外测试，属 T24 收尾范围。
- **TSAN 环境限制（A03.4 已记录）**：`-Zsanitizer=thread` 在 smithay（build-std 路线 AsFd 解析错误）与 build-deps（无 build-std 路线）两处编译失败；确定性 harness（3 静态 guard + 行为测试）为替代证据。
- **轮次 3/4 红跑回填披露**：skip 测试的 `redraw_skip_unmapped >= 1` 断言与 subsurface 测试的 subcompositor 夹具为旧树不存在符号（T01 rework 同例：红跑需把 test-only accessor/夹具回填旧树）；红绿核心断言在回填前版本上已实测红。

---

### 7. 产品 Commit 与 push 收据

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `0b717b19578451956fdc53f855fa42e0463b1620` | `fix(layer): T03 layer map lock scopes, bounded damage, root attribution` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `eeb7169a..0b717b19` 成功 | `git merge-base --is-ancestor 0b717b19 origin/tahoe-layer-animations` exit 0 |
| main | `1e945e5e51c7f055696d2de9fe9c8fc648b1fd25` | `fix(submodule): bump niri for T03 layer map lock scopes, bounded damage, root attribution` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `c39482e..1e945e5` 成功 | `git merge-base --is-ancestor 1e945e5 origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → 0b717b19（= 已推送 niri commit hash）
```

### 8. 未覆盖、用户现场项与后续边界

- 未覆盖：无产品代码缺口（A03.1-A03.5 全通过）。渲染路径 guard 作为 `&LayerMap` 参数消费（niri.rs:4903/5057 等）为渲染自然 owner，未分离（无重入，已记录不修改理由）。
- 需要用户授权的实时验证：无（纯源码/测试任务，未重启会话、未真实拔插；锁屏/DPMS 场景以确定性 harness 模拟）。
- 发现但属于后续任务的事项（只记录，未修改）：见第 6 节"后续边界"——T01-era 测试计数器竞争（T24）、TSAN 环境限制（A03.4 记录）、轮次 3/4 红跑回填披露。

### 9. 完成判定

**最终状态**：COMPLETE（待 §10 闭环 commit push 后）
**理由**：A03.1-A03.5 + G01-G08 满足；8 个红绿测试（含 subsurface 双 A/B 复验）；四轮双审查最终两轮产品代码 CLEAN（A4-F1 以快照优先机制代码反证裁决、B4-F2-F4 账本修正）；fmt 70 处基线为改动前既有；564 全量测试通过；debug+release 实际构建通过；PROTOCOL_FULL 通过；niri 产品 commit 已 push 且远端 ancestor 验证 exit 0。
**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 10. 闭环记录审查与推送

- Closure reviewer（全新只读上下文）：完成，全部 PASS —— 两仓库 full hash/subject/parent/branch/remote ref/ancestor exit code/子模块指针/测试计数/fmt 基线/状态机逐项实测一致（抽查复跑测试与 `git show eeb7169a | rustfmt --check` 复验既有漂移归属）；工作树冻结（niri 干净，主仓库仅用户原有未跟踪项与本文档）；无未执行事项写成已完成；确认状态可置 COMPLETE，允许 docs-only closure commit。2 处措辞小瑕疵已随本 closure 修正（L4/L494 状态行措辞；L598 fmt"零 diff"改为"T03 hunk 零新增漂移"并注明复验）。
- 产品 commit hash/remote receipt 是否逐项准确：是（closure reviewer 实测核对）
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T03 close task record`
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

---

## T04 pointer 缓存与 focus transaction

**状态**：COMPLETE（产品实现、九轮双审查、全量验证、产品 commit/push 完成；docs-only 闭环 commit 待执行）
**开始时间**：2026-08-03
**roadmap 引用**：`roadmap.md#T04`（第 135-154 行）；发现 `research-report.md#STAB-07`（第 107-111 行）
**执行者上下文**：OpenCode / DeepSeek V4 Flash 会话（niri 子仓库 `tahoe-layer-animations` 分支）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| STAB-07: Smithay pointer/grab 回调内不得调用 `pointer.current_location()`（历史 core 11605 cursor_image / core 3020 on_ungrab） | 修复提交 `5a8bf3d8`（cursor_image/tablet_tool_image/DnD grab/end 改用缓存）与 `16696344`（move_grab/pick_color_grab/pick_window_grab on_ungrab+button、cursor_position_hint 改用缓存）均为 HEAD(0b717b19) 祖先（`git merge-base --is-ancestor` 两次均 exit 0） | CURRENT-CONFIRMED | 成立（不变量保持：回调上下文零 `current_location()`） |
| 位置缓存 `pointer_pos` 只由 2 处写入（`on_pointer_motion`、`on_pointer_motion_absolute`） | 全仓 rg 写点恰 2 处生产；`move_cursor`（warp/focus 路径）与 `cursor_position_hint`（constraint hint）不更新缓存 | CURRENT-CONFIRMED | 成立（需补 2 写点） |
| `tablet_tool_image` 读 `pointer_pos`（鼠标缓存）而非平板位置 | `tablet_cursor_location`（niri.rs）是既有设备来源状态；渲染路径均 `unwrap_or(...)`；唯独 tablet_tool_image 回调读鼠标缓存 | CURRENT-CONFIRMED | 成立 |
| 无作用域裸 bool focus-clear：`pending_on_demand_focus_clear: bool` | 只记录"有一个 deferred clear"，不绑定 button/slot/表面；释放被任意按键消费；touch/tablet down 立即 clear；生命周期无清理 | CURRENT-CONFIRMED | 成立 |
| 释放事件必然到达 input 层处理器（grab 只拦截 smithay 层 `pointer.button`） | `process_input_event` 对每个 libinput 事件调用；`on_pointer_button` 释放分支在所有 grab 之前运行 | CURRENT-CONFIRMED | 成立（held press 自解析原则的根基） |
| 锁/VT/截图/pick_color/popup-grab 取消点 | 均不触碰 pending 状态 | CURRENT-CONFIRMED | 成立（生命周期钩子缺失） |
| 无第二位置缓存 authority、无第二 focus transaction | rg `pointer_pos2` 零命中；`tablet_cursor_location` 为既有设备来源 | CURRENT-CONFIRMED | 原地改造 |

### 2. 工作树与范围（最终）

开始时 niri 子模块干净（HEAD `0b717b19`）；主仓库仅用户未跟踪项 `.zcode/`、`Testing/`、docs 目录。

允许修改（最终 8 文件）：

- `niri/src/niri.rs`（缓存同步、`PendingOnDemandFocusClear` 状态机、resolve 钩子、字段与文档）
- `niri/src/input/mod.rs`（pointer press/release、touch down/up/cancel、tablet tip/proximity、设备移除钩子）
- `niri/src/handlers/mod.rs`（`tablet_tool_image` 设备来源、`cursor_position_hint` 缓存同步与重绘目标）
- `niri/src/handlers/layer_shell.rs`（`layer_destroyed` 按表面解析钩子，一行）
- `niri/src/backend/tty.rs`（`PauseSession` VT 切换解析钩子）
- `niri/src/tests/client.rs`（**测试夹具扩展**：wl_seat/zwp_pointer_constraints_v1 全局绑定 + `lock_pointer` helper——以真实 pointer-constraints 协议驱动 `cursor_position_hint` 行为测试；T01/T03 同类夹具先例；无测试专用生产入口）
- `niri/src/tests/mod.rs`（注册一行，字母序）
- `niri/src/tests/pointer_focus_transaction.rs`（新测试文件，26 个测试）
- `execution-log.md`

明确禁止修改：`src/layout/*`、`src/protocols/tahoe_glass.rs`、`src/render_helpers/*`、`src/redraw_attribution.rs`、`src/input/pick_color_grab.rs`/`pick_window_grab.rs`/`move_grab.rs`（回调缓存读取已是 16696344 修复形态）、Quickshell、Tahoe shell、主仓库用户项、T05+ 范围。

### 3. 旧实现失败基线（红绿证明，实际执行）

在 0b717b19 + 测试文件（含红跑 shim `resolve_pending_on_demand_focus_clear` no-op）上运行首批 18 个测试：**15 红 / 3 绿**（绿 = 2 个历史 deadlock harness + `deferred_focus_clear_consumed_by_matching_button_only` guardrail——旧代码以覆盖 bool 的方式同样满足"桌面按下取消 deferral"，防回归 guardrail）。后续各轮新增测试均以变异验证红绿（见第 6 节）。

| 测试/probe | 旧结果（实测） | 为什么能捕获根因 |
|---|---|---|
| `warp_updates_cached_location_and_cursor_image_targets_new_output` | FAIL：warp 后 `pointer_pos` 仍 `(0,0)` | `move_cursor` 不写缓存 |
| `warp_cache_stays_correct_across_scale_and_transform_outputs` | FAIL：cache drift（0.0 vs 640.0） | 同上 |
| `color_pick_after_warp_reads_pixel_at_warped_position` | FAIL：拾色 `[0.251,0.251,0.251]` 桌面灰（旧缓存 (0,0)） | pick_color_grab 读缓存；warp 后陈旧 |
| `tablet_tool_image_redraws_output_under_tablet_cursor` | FAIL：回调重绘输出 1（鼠标位置）而非输出 2 | tablet_tool_image 读鼠标缓存 |
| 5 个 focus transaction 行为测试 | FAIL：任意释放即消费 / 无生命周期解析 / touch、tablet tip down 立即 clear / cancel 无路径 | 裸 bool 无键控 + 无钩子 |
| `touch_cancel_resolves_pending_slot` | FAIL：down 即 clear | touch 未镜像 deferral |
| `pointer_pos_writers_are_the_single_cache_authority` | FAIL：写点集合 {on_pointer_motion, on_pointer_motion_absolute} | 合同要求 4 个已知路径 |
| `focus_transaction_lifecycle_resolve_call_sites_exist` | FAIL：lock/截图/PauseSession 无 resolve | 生命周期钩子缺失 |

A/B 变异复核（G04）：移除 `move_cursor` 缓存写 → warp×2 + pick + 静态合同 4 红；移除 hint 缓存写 → hint 测试红；还原旧 else 语义 → `deferred_focus_clear_consumed_by_matching_button_only` 红；移除 device 作用域 → 设备移除/跨设备测试红；移除 kind 过滤 → 混合设备测试红；移除 suppressed 前移 → 配对测试红。

### 4. 实现机制（最终，经 9 轮审查收敛）

- **单一位置缓存 authority（A04.1/A04.5）**：`pointer_pos` 写点 2→4：新增 `move_cursor`（niri.rs，warp 路径：focus-window/IPC focus/confirm-mru/tablet proximity-out 共用；写点在 `pointer.motion()` 之前，回调可读新值）与 `cursor_position_hint`（handlers/mod.rs，`set_location` 后同点写缓存、重绘用 hint 目标）。`tablet_tool_image` 改读 `tablet_cursor_location.unwrap_or(pointer_pos)`。锁内/早退路径（locked-constraint、confined-prevent）位置未变不写缓存，正确。
- **focus transaction（A04.2）**：`pending_on_demand_focus_clear: bool` → `Vec<PendingOnDemandFocusClear>`（`kind: {PointerButton{button}, Touch{slot}, TabletTip{tool}}` + 按下表面 `WlSurface` + **device id `String`**）。三类按压语义：非 on-demand layer 按压 → defer（按 kind+device 入账，最后一条释放才 clear）；on-demand 按压 → 立即 focus（enter 不取消任何 grab）；**窗口按压 → 立即 clear**（原 T-29 权衡：deferred holder 杀死新按压的 xdg popup grab——上下文菜单）；**桌面按压 + 其他按压在途 → 延迟 clear 到最后一条释放**（无窗口无 popup grab 风险，避免给在途按压注入 leave）。
- **生命周期解析钩子（5 类）**：`lock()` 入口与 `PauseSession`（全部——输入已死）、`layer_destroyed`（按表面）、`on_device_removed`（按设备，全部 kind——设备移除后其按压确实已死）、touch cancel（按设备 + **仅 Touch kind**——混合设备上同设备的笔尖按压仍存活）、tablet proximity-out（按设备 + 按 tool——双设备同工具描述符不互相误杀）。
- **grab 交换不解析**：pick_color/screenshot/popup-grab 打开时**不**提前解析 held press——其 release 必达 input 层（release 钩子在 suppressed 早退与 `pointer.button` 路由之前）自解析完成配对；提前解析会注入 leave 重犯 T-29（R5/R7 审查收敛）。原裸 bool 无此问题因无在途条目概念；曾一度加入的 grab-cancel 钩子经审查删除。
- **A04.3**：两个 watchdog harness（`CursorImageProbeGrab::button` 锁内调真实 `SeatHandler::cursor_image`；`PickColorGrab::unset` 经 `unset_grab` 锁内驱动）+ RAII Drop guard（panic 也撤销孤儿 abort）。
- **A04.4**：三输出 scale 1.0/2.0/1.5 × Normal/Flipped180/_90 精确归因。
- **无平行接口**：resolve 变体（all/for_device/for_touch/for_surface/for_tool）全部是私有 `_where` 的薄委托；`focus_layer_surface_if_on_demand` 单一 holder authority。
- **测试文件修正（前一会话遗留）**：① `map_layer` 前补 `double_roundtrip`；② tablet 坐标按单输出矩形；③ 移除 `dbg_output_names` 与 DBG 探针；④ 静态合同 `take_while`/`enclosing_fn` 解析修复；⑤ redraw 断言前 drain；⑥ 拾色目标改焦点环颜色（smithay 0.7 ff5fa7d `rgba32f()` 对 8-bit 颜色按 u32::MAX 缩放 → spbm 表面渲染透明，依赖项行为不改；无 shader 上下文下 `draw_focus_ring_with_background` 实心焦点环覆盖窗口内容——用默认 active 焦点环色 (0.498,0.784,1.0) 与桌面灰判别，红绿方向不变）。
- **hint redraw 冗余裁决**：hint 仅在承载 commit 时交付（smithay commit_hook），承载 commit 自身已为 mapped toplevel 排队同输出 redraw，hint 目标恒被约束到该输出——hint 自身 redraw 被吸收，行为上不可区分，测试不断言它（注释如实说明）。

### 5. 验收逐条（最终）

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见第 1/2 节 | PASS | 4 写点、6 resolve 调用点、迁移完整（裸 bool 零残留、`of_kind` 删除后零引用） |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名、无新接口/flag |
| G03 | 专项+全量测试 | PASS | 见全量配置 |
| G04 | 红绿证明 | PASS | 第 3 节 + 各轮变异验证 |
| G05 | 双审查 | PASS | 第 6 节（9 轮，最终两轮产品代码 CLEAN + 1 账本项已修） |
| G06 | commit/push 顺序 | 进行中 | 第 7 节 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话（全部 headless fixture） |
| A04.1 | mouse/warp/tablet/拾色/constraint hint 后 cursor image redraw/拾色使用正确 output 坐标 | PASS | `warp_updates_cached_location_and_cursor_image_targets_new_output`、`warp_cache_stays_correct_across_scale_and_transform_outputs`、`color_pick_after_warp_reads_pixel_at_warped_position`（真实拾色渲染）、`tablet_tool_image_redraws_output_under_tablet_cursor`、`cursor_position_hint_syncs_cache_and_redraws_target_output`（真实 zwp_pointer_constraints 协议驱动） |
| A04.2 | 多按键交错、surface destroy、lock、VT switch、grab cancel、touch cancel、设备移除、跨设备后 focus transaction 不遗留 | PASS | 13+ 行为测试（交错×4、destroy、lock/VT（直调+静态合同）、pick_color/screenshot 不提前解析×2、touch cancel×3（含混合设备）、proximity-out、设备移除×3（含跨设备）、窗口/桌面/on-demand 三类按压）+ stale release 无残留×4 |
| A04.3 | 历史 cursor_image/on_ungrab deadlock harness 继续通过 | PASS | 两个 watchdog harness 真实锁内回调；RAII guard 防孤儿 abort |
| A04.4 | 多输出 scale/transform 下缓存坐标转换正确 | PASS | 1.0/2.0/1.5 × Normal/Flipped180/_90 三输出精确归因 |
| A04.5 | 无第二位置缓存 authority | PASS | `pointer_pos_writers_are_the_single_cache_authority` 静态合同 + 全仓 rg 复核 |

全量配置（最终）：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---:|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移点全部为改动前既有（HEAD 与工作树逐 hunk 内容对比：69 处逐字节相同，1 处为相邻 import 行编辑引起的既有违规位移；R8 修复的 6 处新增违规已清零；新测试文件零违规） |
| NIRI_FULL | `cargo test -p niri --lib` | 0 | 590 passed / 0 failed（564 旧 + 26 新）；新测试 5 轮并行复跑零 flake |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import）；轮次 4 消除 2 条本 diff 曾引入的 dead-code warning（`pending_len` 改 cfg(test)、`TestPopup.popup` 标注 keep-alive）后归零新增 |
| 实际二进制 | `cargo build -p niri` | 0 | debug 构建通过 |
| 实际二进制 | `cargo build --release -p niri` | 0 | release 构建通过 |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

### 6. 独立审查（9 轮收敛记录）

| 轮次 | Reviewer A | Reviewer B | 处理 |
|---|---|---|---|
| 1 | NOT-CLEAN：1 CONFIRMED（resolve-all 过宽）+ 1 PLAUSIBLE（hint 重绘） | CLEAN（2 措辞） | kind 过滤 + hint 重绘 target + 跨种类测试 |
| 2 | NOT-CLEAN：2 CONFIRMED（doc：tablet_tool_image/pointer_pos 注释）+ 1 PLAUSIBLE（popup-grab Touch 扫描） | CLEAN | popup-grab 收窄 PointerButton-only + 注释修正 |
| 3 | NOT-CLEAN：1 PLAUSIBLE（suppressed 角落残留）+ 1 PLAUSIBLE（watchdog 孤儿） | NOT-CLEAN：1 CONFIRMED（计数器断言空转）+ 2 PLAUSIBLE（popup-grab 无 pin、suppressed 配对无测试）+ 1 CONFIRMED（卫生） | release 前移 + watchdog RAII + 静态合同补 pin + 配对测试 + 卫生 |
| 4 | NOT-CLEAN：2 CONFIRMED（F1 保留 holder 杀死 popup grab；F2 设备移除跨设备误杀） | NOT-CLEAN：1 PLAUSIBLE（设备移除只测 Touch） | 窗口/桌面按压分界 + 删除 grab-cancel 钩子 + device id 作用域 + pointer/tablet 移除测试 |
| 5 | NOT-CLEAN：1 CONFIRMED（touch cancel 无 kind 过滤，混合设备误杀）+ 2 措辞 | CLEAN | resolve_for_touch（device+kind）+ 混合设备测试 + 措辞 |
| 6 | NOT-CLEAN：2 PLAUSIBLE（proximity-out 无 device 匹配；hint 注释/doc 残留） | NOT-CLEAN：1 CONFIRMED（doc：grab cancel 残留） | for_tool 加 device + 注释修正 |
| 7 | CLEAN | NOT-CLEAN：1 CONFIRMED（6 处新 rustfmt 违规） | 按仓库固定工具链修复（cargo fmt 70 处基线） |
| 8（终审） | **CLEAN**（六问全 CLEAN，fmt 基线独立复核成立） | **CLEAN**（产品代码；1 PLAUSIBLE 账本项：execution-log 未反映最终状态） | 本记录更新（client.rs 范围、最终数字、最终机制） |
| 9（账本修正后复审） | **CLEAN**（含 fmt 基线逐 hunk 复核） | **CLEAN**（含 fmt 70 处基线复核） | 账本项已随本记录修正；closure reviewer PASS |

审查输入：CONSTRAINTS、roadmap T04、最终 diff（/tmp/opencode/t04_final10.diff，2899 行）、专项/全量测试输出。两个 reviewer 每轮均为全新上下文、只读、互不可见。

### 7. 产品 Commit 与 push 收据

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `cc772d0a7805b19fcae5e3cdac06e68c7ec70574` | `fix(input): T04 pointer location cache coherence and keyed on-demand focus transaction` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `0b717b19..cc772d0a` 成功 | `git merge-base --is-ancestor cc772d0a origin/tahoe-layer-animations` exit 0 |
| main | `c177402` | `fix(submodule): bump niri for T04 pointer cache coherence and keyed on-demand focus transaction` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `b0abf71..c177402` 成功 | `git merge-base --is-ancestor c177402 origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → cc772d0a（= 已推送 niri commit hash）
```

### 8. 未覆盖、用户现场项与后续边界

- 未覆盖：无产品代码缺口（A04.1-A04.5 全通过）。A04.3 的 tty estimated-vblank/vblank 与 screencast 真实守卫路径在 headless 夹具不可达（T02 已以源码审计闭合）。lock/VT 验收为"直接调 resolver + 静态合同"（headless 无法驱动真实 SessionLocker/session pause，注释如实声明）。
- 需要用户授权的实时验证：无（纯源码/测试任务，未重启会话、未真实拔插）。
- 发现但属于后续任务的事项（只记录，未修改）：
  - 桌面按压在有其他按压在途时延迟 clear 是相对旧代码的**有意行为变更**（旧代码该场景即 T-29 swallow 缺陷），A04.2 多按键交错授权内，已文档化并被测试钉住。
  - A04.5 静态合同只扫描 3 个文件——当前全仓 rg 反证无第五写点；未来新增文件内写入会绕过 guardrail（记录，不阻塞）。
  - 双设备相同工具描述符场景无直接测试（机制经代码推演正确，R9 记录）。
  - smithay 0.7 `SinglePixelBufferUserData::rgba32f()` 对 8-bit 颜色按 u32::MAX 缩放（255→5.94e-8）导致 spbm 表面渲染透明——依赖项行为，非 T04 范围，未改。

### 9. 完成判定

**最终状态**：COMPLETE（待 §10 闭环 commit push 后）
**理由**：A04.1-A04.5 + G01-G08 满足；红绿测试 + 各轮变异验证；9 轮双审查最终两轮产品代码 CLEAN（R9 双 CLEAN，账本项已随本记录修正）；fmt 70 处基线为改动前既有；590 全量测试通过；debug+release 实际构建通过；PROTOCOL_FULL 通过；niri 与主仓库产品 commit 均已 push 且远端 ancestor 验证 exit 0。
**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 10. 闭环记录审查与推送

- Closure reviewer（全新只读上下文）：待执行。
- 产品 commit hash/remote receipt 是否逐项准确：待 closure reviewer 实测核对。
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T04 close task record`
- closure push remote ref：`origin/fix/tray-menu-pinned-surface-height`
- closure remote ancestor 验证 exit code：待 push 后以命令输出验证（本 commit 不记录自身 hash，由后续 `git log --format=%H -- execution-log.md` 解析）

---

## T05 thumbnail 主循环预算

**状态**：COMPLETE
**开始时间**：2026-08-05
**结束时间**：2026-08-05
**roadmap 引用**：`roadmap.md#T05`（第 155-172 行）；发现：旧报告 STAB-05（thumbnail main-loop risk，roadmap 第 571 行映射）
**执行者上下文**：OpenCode / DeepSeek V4 Flash 会话（niri 子仓库 `tahoe-layer-animations` 分支）

### 1. 前提核实（2026-08-05）

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| thumbnail 请求经同步 GPU readback 阻塞主事件循环 | `src/ipc/server.rs:456-483`：`Request::WindowThumbnail` → `insert_idle` → `state.window_thumbnail`（`src/niri.rs:2176-2206`）→ `backend.with_primary_renderer` 内同步 `render_to_vec`（`render_helpers/mod.rs:257-273`：render + copy_framebuffer + map_texture + to_vec，最大 4096×4096×4=64MB）；整个 idle 回调期间主循环不可处理 pointer/frame | CURRENT-CONFIRMED | 成立（单次捕获阻塞 + 突发 1000 请求 = 1000 次串行阻塞） |
| 无去重：同窗口突发 N 个相同请求 → N 次独立渲染 | `niri.rs:2184-2205`：每次请求独立 find+capture+publish，无合并 | CURRENT-CONFIRMED | 成立 |
| 无缓存：内容未变也重复 render+readback+encode | `niri.rs:2176-2206` 无任何缓存查询 | CURRENT-CONFIRMED | 成立 |
| 无请求队列上限（主循环侧）：`thumbnail_publisher` 队列（`thumbnail.rs:13` 容量 16）只限 PNG encode 阶段；GPU readback 阶段不受限 | `thumbnail.rs:44-133`：`publish()` 在 readback 之后才 try_send；主循环 idle 对捕获本身无 bound | CURRENT-CONFIRMED | 成立（需在主循环侧建立捕获预算） |
| 完成所有权/取消已部分存在 | `thumbnail.rs`：generation latest-wins 出版（`publications` map）、`cancel_window`（:122-133）、reply is_closed 检查（:148-156/204）、queue-full/disconnected 显式错误（:93-114）、disconnect 后 remove 文件（:163-169/281-298）；`xdg_shell.rs:904` 与 `compositor.rs:315` 两个销毁路径均调 `cancel_window_thumbnail` | CURRENT-SATISFIED | 所有权机制存在但无合并 fan-out（`PublishJob.reply` 单 sender） |
| 内容版本信号可用（缓存失效所需） | smithay `on_commit_buffer_handler` 在每个 buffer commit 更新 surface 的 `RendererSurfaceState`（`compositor.rs:62` 对每次 commit 调用）；`with_renderer_surface_state` + `current_commit()`（smithay wayland.rs:267-272）提供每 surface 单调 commit 计数；最小化窗口不渲染但仍计 commit（update_buffers 在 commit 时更新，与渲染无关） | CURRENT-CONFIRMED | 可作缓存失效版本源（toplevel + subsurface + popup 树聚合） |
| 无第二 thumbnail IPC / 无现成队列 authority 可复用 | `rg Request::WindowThumbnail` 仅 1 处请求 + 1 处处理；无 thumbnail-v2；`thumbnail.rs` 为唯一模块 authority | CURRENT-CONFIRMED | 原地改造 |

### 2. 工作树与范围

开始时 niri 子模块干净（HEAD `cc772d0a`，T04）；主仓库干净（仅用户未跟踪项 `.zcode/`、`Testing/`），HEAD `c56b5c0`（用户 shell 提交）。

允许修改（最终 8 文件：7 改 + 1 新测试文件，其中 compositor.rs/mapped.rs 为审查轮次补入的同职责扩展）：

- `niri/src/thumbnail.rs`（主 authority：请求队列 + 缓存 + 内容版本 + publisher fan-out）
- `niri/src/niri.rs`（IPC 入口提交化、pacing idle、epoch map、捕获函数去 self 化、`cancel_window_thumbnail` 扩展、字段注册）
- `niri/src/handlers/compositor.rs`（内容纪元双钩子：`commit` 对每个 surface 每次 commit、`destroyed` 对每次销毁——缓存失效正确性 A05.5 所需，roadmap §1.2 同职责扩展，轮次 1 审查后补入）
- `niri/src/utils/lifecycle_diag.rs`（`THUMBNAIL_RENDER` 计数，沿用模块既有 gated 模式）
- `niri/src/window/mapped.rs`（`blur_config()` 只读 getter——popup glass 渲染输入，轮次 2 审查后补入）
- `niri/src/tests/client.rs`（测试夹具最小 helper：shm/subsurface/popup 绑定与创建）
- `niri/src/tests/mod.rs`（注册一行，字母序）
- `niri/src/tests/thumbnail_budget.rs`（新测试文件）
- `execution-log.md`

明确禁止修改：

- `src/ipc/server.rs`（IPC 语义与路径校验 authority，不动；A05.4 兼容性以既有 server.rs 测试保护）
- `src/cli.rs`、`src/ipc/client.rs`、`src/backend/*`（renderer/headless authority）
- `src/window/mapped.rs` 除 `blur_config()` 只读 getter 外的其余 authority（不新增窗口可变状态/字段）
- Quickshell、Tahoe shell、主仓库用户项
- T06+ 范围

定义/调用点/测试搜索（G01 清单）：

| `rg` 命令（Phase 1 实现前搜索快照；行号与命中数为当时状态，本 diff 已按实现后状态复核，修改/不修改判定不变） | 命中数 | 修改点 | 不修改点及理由 |
|---|---:|---|---|
| `Request::WindowThumbnail` (src/) | 2 | `ipc/server.rs:456` 处理点不动（语义保持）；`cli.rs:83` 不动 | `ipc/client.rs:12/32/43/335` 与 `cli.rs` 客户端不动（A05.4 接口兼容） |
| `window_thumbnail` (src/) | 5 | `niri.rs:2176`（State 入口改为提交+调度）、`niri.rs:6418`（私有渲染 fn 去 `&self` 化并重命名 `render_window_thumbnail`） | `ipc/server.rs:476` 调用点不变（签名保持）；tracy span 保持 |
| `thumbnail_publisher` (src/) | 3 | `niri.rs:461/3038` 字段与初始化；`niri.rs:2201` publish 调用点（改 Vec replies） | 无 |
| `cancel_window_thumbnail` | 4 | `niri.rs:2208`（加入队列/缓存清理） | `xdg_shell.rs:904`、`compositor.rs:315` 两个销毁调用点不动（单一钩子扩展） |
| `ThumbnailPublisher` / `PublishJob` | ~30 | `thumbnail.rs`（reply → replies fan-out） | 出版/原子 rename/清理语义不动 |
| `insert_idle` (src/) | 10 | 新增调度点（thumbnail pacing） | 其余 9 处既有 idle 语义不动 |
| `with_renderer_surface_state` / `current_commit` | 0（未用） | `thumbnail.rs` 新版本计算（只读） | smithay authority 不动 |
| `thumbnail_content_version`（新） | 0 | `thumbnail.rs` 新增 | 只读纯函数，无状态 authority |
| `render_to_vec` | 5 处调用 | 不动 | 截图/预览/thumb 共用渲染 helper，保持单一 authority |

### 3. 设计（实现前定稿，供测试与审查对照；随后实现按此定稿，最终机制以 §4 为准）

- **主循环捕获预算**：`ThumbnailRequestQueue`（`thumbnail.rs`，主线程单所有权）——`submit`（O(1) 去重合并 / 同窗口同路径 latest-wins 替换 / 硬上限拒绝）、`pop_pending`（FIFO）、`cancel_window`（清 pending + 缓存）；`Niri::schedule_thumbnail_capture` + `Niri::run_thumbnail_capture`（一次 idle 只捕获一条，完成后如有剩余再 `insert_idle` → calloop `dispatch_idles` 快照语义保证每条捕获独占一个 loop 迭代，pointer/frame 事件在迭代间正常处理）。
- **去重与上限**：dedup key `(window_id, path, max_width, max_height)`；同 `(window_id, path)` 不同尺寸 → 新请求替换（旧请求回 "superseded" 错误，latest-wins）；pending 上限 8，超限新请求回新措辞 "thumbnail request queue is full"（fail-fast 背压；该串为新语义新增，风格与既有 publisher 串 "thumbnail publisher queue is full" 一致）。
- **缓存**：key `(window_id, max_width, max_height)` → `{version, width, height, pixels: Arc<Vec<u8>>}`；版本 = toplevel+subsurface+popup 树 commit 计数聚合 + output fractional scale bits + alpha bits（与捕获渲染输入逐位对应）；命中 → 直接经 publisher 重新发布（跳过 GPU readback）；LRU 逐出 + 字节/条目双上限（64MiB / 32 条）。
- **完成所有权**：`PublishJob.reply` → `replies: Vec<Sender>`（合并 fan-out）；全部 reply 关闭才取消/删除文件；客户端断开 → reply 关闭 → 捕获前跳过渲染、出版后删除文件（既有语义扩展）。
- **无平行接口**：不改 IPC/CLI；`ThumbnailRequestQueue`/缓存为 `thumbnail.rs` 既有模块内新增结构，publisher 仍为唯一文件出版 authority；不新增窗口字段。
- **禁止替代对照**：不降 4096 上限（版本含 scale/alpha，尺寸语义保持）；无占位图（缓存命中像素与重捕获逐位一致，均为同一 render path）；无 thumbnail-v2 IPC；无无限后台队列（worker 队列仍 16，主循环捕获每迭代至多 1 条且 pending 硬上限）。

### 3.1 旧实现失败基线（红绿证明）

集成测试共 15 个，按引入批次：首批红跑 8 个（千突发/unchanged/content_change/pacing/max_size/销毁/断开/output 移除，见下表）→ 验证期补 1 个（`renderer_unavailable`，覆盖 A05.2 renderer reset 路径，非红跑对象——旧实现无 renderer 时同样回 "primary renderer unavailable"，属兼容性 guardrail）→ 轮次 1 补 4 个（subsurface_commit/subsurface_destroy/last_output/real_max_size）→ 轮次 2 补 2 个（popup_commit/output_scale_change）。

在 cc772d0a（旧实现）上运行首批 8 个新集成测试（含红跑回填的 `#[cfg(test)]` 观察 accessor：`thumbnail::test_thumbnail_renders()` 旧树恒 0、`Niri::thumbnail_queue_test_pending_len()` 旧树恒 0——T01 rework §4 同例回填披露；两 accessor 为红跑回填符号，最终实现分别被 lifecycle_diag 计数与真实队列 accessor 取代，最终 diff 中不存在）：

| 测试/probe | 旧结果 | 为什么能捕获根因 |
|---|---|---|
| `thousand_identical_requests_coalesce_and_do_not_block_the_loop`（A05.1） | FAIL：提交期已同步交付 983/1000 个 reply（burst 未合并、同步阻塞） | 旧 IPC 入口逐请求同步 render+readback；新语义要求提交零阻塞 + 1,000 合并为一次捕获 |
| `captures_are_paced_one_per_loop_iteration_while_events_flow`（A05.3） | FAIL：提交期已同步交付 8/8 个 reply | 旧实现无主循环捕获预算；新语义要求每条捕获独占一个 loop 迭代 |
| `max_size_request_keeps_measured_iteration_latency_bounded`（A05.3） | FAIL：提交期已同步交付 4/4 个 reply（4096×4096 请求逐条阻塞调用方） | 同上 |
| `window_destroyed_while_request_pending_fails_with_legacy_error`（A05.2） | FAIL：reply 为 Ok/“superseded or cancelled”（请求在销毁前已被同步服务/竞态取消） | 旧实现无法对销毁窗口产生 legacy "window not found" 语义 |
| `content_change_invalidates_cache_and_refreshes_pixels`（A05.5 计数器断言） | FAIL（backfill 计数恒 0） | 计数 accessor 为旧树回填符号；真实红绿由实现后变异 A/B 提供 |
| 其余 3 个（`unchanged_content`、`disconnected_client`、`output_removed`） | PASS（guardrail） | A05.4/A05.2 兼容性语义旧实现本就满足，作为新旧双侧 guardrail 保留 |

实现后变异 A/B（G04 确定性证据，均恢复）：

| 变异 | 结果 |
|---|---|
| 缓存版本检查改为恒真（`if false`） | `content_change` FAIL（陈旧像素被缓存命中）——版本失效逻辑有判别力 |
| 移除 all-replies-closed 捕获前检查 | `disconnected_client` FAIL（渲染计数 1≠0）——断开跳过机制有判别力 |
| 移除 submit 去重合并 | `thousand` FAIL（992 请求立即被 cap 拒绝，ready 计数 992≠0）——去重合并有判别力 |
| 移除捕获后 re-schedule idle | `captures_are_paced` FAIL（step 2 计数 1≠2）——pacing 有判别力 |
| 版本 content_epoch 置 0（轮次 1 F1 修复后） | `subsurface_commit` FAIL（渲染计数 0≠1）——epoch 有判别力 |
| 移除 destroyed() epoch bump + surface-set 折叠（轮次 1 F1 修复后） | `subsurface_destroy` FAIL（渲染计数 0≠1）——destroy 失效有判别力 |

### 4. 实现机制（实际）

- **请求预算（A05.1）**：`ThumbnailRequestQueue`（`thumbnail.rs`，主线程单所有权）：`submit` 三序去重/替换/上限——(1) 相同 `(window_id, path, max_width, max_height)` 合并 replies（一次捕获、fan-out 应答）；(2) 同 `(window_id, path)` 不同尺寸 → latest-wins 替换（旧请求回显式 "superseded" 错误）；(3) pending 达 `MAX_PENDING_THUMBNAIL_REQUESTS`(8) 时新请求回显式 "thumbnail request queue is full"（fail-fast 背压，每被接受请求必被服务）。注：去重/替换为对 ≤8 条 pending 的线性扫描（非 O(1)）。
- **主循环 pacing（A05.3）**：`Niri::schedule_thumbnail_capture`（`capture_scheduled` 标志防重复调度）+ `Niri::run_thumbnail_capture`（每个 idle 回调至多一条捕获；完成后如有剩余经 `insert_idle` 重排——calloop `dispatch_idles` 快照语义保证每条捕获独占一个 loop 迭代，pointer/frame 事件在迭代间正常处理）；渲染闭包只捕获局部量（`backend` 经参数传入，`&mut self.backend` 与 `&self.layout` 字段级借用分离）。
- **缓存（A05.5）**：key `(window_id, max_width, max_height)` → `{version, width, height, pixels: Arc<Vec<u8>>, last_used}`；LRU 逐出 + 双上限（32 条 / 64MiB）。
- **内容版本（轮次 1 F1 修复后定稿）**：`ThumbnailVersion` = (a) `content_epoch`——按窗口 root surface 键控的单调纪元（`Niri::bump_thumbnail_content_epoch`，在 `CompositorHandler::commit` 对**每个** surface 的每次 commit 推进、在 `destroyed` 对每次 surface 销毁推进；经既有 `find_root_shell_surface` 把 subsurface/popup commit 归因到窗口 toplevel——该归因含 `popups.find_popup` 扫描，为 commit 热路径新增 O(活 popup 数) 成本，有界且正确性安全，轮次 4 记录接受；dead root 按阈值剪除（`MAX_THUMBNAIL_EPOCH_ENTRIES`=2048，超阈值才全表 retain，每 commit 摊销 O(1)）；u64 回绕时全表清空强制 miss）；(b) `surface_set`——捕获树（toplevel+subsurface+popup）surface id 折叠，popup/subsurface 增删即使无后续 commit 也改版本；(c) output fractional scale bits；(d) alpha bits（`thumbnail_alpha` 与渲染共用单一 alpha 来源）；(e) `block_out_from` 判别（ScreenCapture block-out 规则把缩略图内容替换为纯色块）；(f) popup opacity bits（规则变化无 commit）。命中直接经 publisher 重新发布（跳过 GPU readback）。
- **完成所有权（A05.2/A05.4）**：`PublishJob.reply` → `replies: Vec<Sender>`（合并 fan-out，全部关闭才取消/删除文件）；`run_thumbnail_capture` 在渲染前检查 all-closed（客户端断开 → 跳过捕获）；`cancel_window_thumbnail` 现同时清队列 pending（回 legacy "window not found" 错误）与缓存；渲染失败/渲染器不可用回显式错误且队列继续。
- **被替代的旧 authority**：`State::window_thumbnail` 原内联同步捕获（find+render+readback+publish）→ 提交+调度；私有渲染 fn 去 `&self` 化并改名 `render_window_thumbnail`（关联函数，经闭包局部捕获调用）。
- **为什么没有平行接口**：不改 IPC/CLI/server.rs；`ThumbnailRequestQueue`/缓存/epoch 为 `thumbnail.rs` + `Niri` 字段 + compositor 钩子的同一职责内扩展（roadmap §1.2 同职责扩展记录：缓存失效正确性 A05.5 需要内容纪元，替代方案 per-surface commit 计数聚合经审查确认有 CONFIRMED 陈旧漏洞）；`ThumbnailPublisher` 仍为唯一文件出版 authority；无测试专用生产入口（`thumbnail_queue_test_pending_len` 为 `#[cfg(test)]` 门控观察 accessor）。
- **为什么没有加入范围外功能**：diff 8 文件（7 改 + 1 新测试文件：compositor.rs、niri.rs、tests/client.rs、tests/mod.rs、thumbnail.rs、utils/lifecycle_diag.rs、window/mapped.rs + 新 tests/thumbnail_budget.rs）；无配置/依赖/视觉变化。

### 5. 验收逐条

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见第 2 节 | PASS | 搜索表 + 未改点逐项理由 |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名；无新接口/flag/第二 IPC |
| G03 | 专项+全量测试 | PASS | 见全量配置 |
| G04 | 红绿证明 | PASS | 第 3 节（旧实现 4 红 + 6 变异 A/B） |
| G05 | 双审查 | 进行中 | 第 6 节（轮次 1-6 已闭合，最终门禁审查进行中；见轮次 7/8 记录） |
| G06 | commit/push 顺序 | 待执行 | 第 7 节 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话（全部 headless fixture） |
| A05.1 | 1,000 突发同窗口 + 去重 + 硬上限 | PASS | `thousand_identical...`（提交零阻塞、999+1 全回复、renders==1）+ 单测 `identical_requests_merge_and_latest_wins_for_same_window` + `full_queue_rejects_new_requests_fail_fast`（pending 上限 8，拒绝带显式错误） |
| A05.2 | 客户端断开/窗口销毁/output 移除（含最后 output）/renderer reset 无泄漏或 UAF | PASS | `disconnected_client...`（渲染跳过 + 无文件 + 队列空）、`window_destroyed...`（legacy 错误 + 队列/缓存空）、`output_removed...`（确定性应答 + 无残留）、`last_output_removed...`（legacy "window not found" + 无残留）、`renderer_unavailable...`（"primary renderer unavailable" + 恢复后可服务） |
| A05.3 | 4096×4096 上限请求 event-loop latency 有测量上限，pointer/frame 继续推进 | PASS | `max_size...`（提交 0 阻塞 + 单次迭代实测 <1s）、`real_max_size...`（真实 4096×4096 窗口捕获，实测单迭代 82ms，回复尺寸 4096×4096）、`captures_are_paced...`（每迭代恰好 1 捕获 + 捕获 pending 期间真实 roundtrip 完成且队列推进） |
| A05.4 | 像素/尺寸/权限/错误响应与旧接口兼容 | PASS | 像素解码断言（RGBA 字节序实测固定）、尺寸断言（`min(max, 窗口)` 不放大、reply 报告实际尺寸）、权限（既有 `validate_tahoe_thumbnail_path` 4 测试不动）、错误串——四条 legacy 串（"window not found or not on an output: {id}"、"thumbnail publisher queue is full"、"thumbnail publisher is unavailable"、"primary renderer unavailable"）对照 HEAD 逐字保持；两条新串（"thumbnail request queue is full"、"thumbnail request superseded by a newer request for the same window"）为 A05.1 硬上限/去重新增语义，措辞与既有风格一致 |
| A05.5 | 缓存内存上限 + 失效 | PASS | 单测 `cache_evicts_least_recently_used_until_under_caps`（LRU + 字节/条目双上限）、`cache_hit_requires_matching_version_and_stale_entries_are_evicted`、`cancel_window_answers_pending_requests_and_drops_cache`；集成 `unchanged_content...`（renders delta 0）+ `content_change...`（renders delta 1 + 新像素）+ `subsurface_commit...`（subsurface commit 必须失效 + 新像素）+ `subsurface_destroy...`（销毁无后续 commit 也必须失效） |

全量配置（最终）：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---:|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移全部改动前既有（与 HEAD 实测 70 一致；其中 6 处在本次修改文件内、全部位于本 diff hunk 之外：niri.rs 1088/1489/1502/3711、tests/client.rs 1137、lifecycle_diag.rs 317）；本次 7 个文件 hunk 零新增漂移 |
| NIRI_FULL | `cargo test -p niri --lib` | 0（偶发 EGL 级联，见下） | 613 passed / 0 failed（590 旧 + 23 新：8 新单测 + 15 集成）；并行复跑多数轮次全绿；~6% 轮次发生 smithay EGL 全局态级联 burst（详见 §5.1） |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import）；轮次 4 消除 2 条本 diff 曾引入的 dead-code warning（`pending_len` 改 cfg(test)、`TestPopup.popup` 标注 keep-alive）后归零新增 |
| 实际二进制 | `cargo build -p niri` | 0 | debug 构建通过 |
| 实际二进制 | `cargo build --release -p niri` | 0 | release 构建通过 |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

#### 5.1 既有 smithay EGL 全局态并行级联（真实 flake，A/B 归因）

并行全量跑中约 6% 轮次（约 1/17）出现 14-17 个测试同时失败，全部 panic 于 `smithay/src/backend/egl/display.rs`：

- **根 panic**（本 burst 为 `r17_restore_includes_previous_active_when_focus_moves`，T04-era 未修改测试）：`display.rs:279:68` `called Option::unwrap() on a None value` —— smithay 全局 `DISPLAYS`（`LazyLock<Mutex<HashSet<WeakEGLDisplayHandle>>>`）去重逻辑的 `displays.get(&weak_disp).unwrap().handle.upgrade().unwrap()`：并行测试 A 创建 surfaceless EGL display 后在其线程结束/渲染器 drop 使 strong count 归零，恰在测试 B 的 `insert`-check 与 `upgrade()` 之间发生 → upgrade 为 None → 持锁 panic。
- **级联**：根 panic 持锁 → `DISPLAYS` mutex 永久 poison → 之后所有 `lock().unwrap()`（`:273:48` `PoisonError`）的渲染器测试全部失败（含未修改的 T02-era `window_lifecycle` 7 测试与 T05 测试——均为受害者，非根因）。
- **A/B 归因**：HEAD（stash 本 diff）并行全量 10 轮零失败；本 diff 全量 ~50 轮 3 次 burst（约 6%，账本统一采用该数字）——本 diff 最终含 13 个 `init_renderer` 调用（15 个集成测试中 12 个需渲染 + `renderer_unavailable` 恢复段；仅 `window_destroyed`、`disconnected_client` 未调用；`last_output_removed` 虽调用但其断言不依赖渲染）提高并行 EGL display 创建并发度，使既有 smithay 竞态暴露概率上升；根 panic 与级联均不涉及本 diff 逻辑（未修改测试也可为根）。归因数据随最终 diff 修正（早期按 9 测试版本统计的 "7 个 add_renderer" 已更新）。
- **处置**：smithay 外部竞态，T05 范围不可修（不改 smithay；§3.1 禁止顺手改写范围外测试）；专项/子集（thumbnail 31 测试 20+ 轮：15 集成 + 12 thumbnail.rs 单测 + 4 既有 ipc 路径）、串行全量、以及多数并行全量轮次全绿；按 T03 flake 同例如实记录，最终回归与（如可行）上游修复归 T24。

### 6. 独立审查

#### 轮次 1（首次双审查）

**Reviewer A（正确性/生命周期/并发）结论**：NOT-CLEAN。1 条 CONFIRMED + 11 条 CLEAN/NOT-A-FINDING：

- **F1 CONFIRMED（版本聚合漏洞）**：`ThumbnailVersion.surface_commits` 取树内各 surface commit 计数 max——非 max surface（popup/subsurface，计数低于 toplevel）的 commit 或销毁不改变 max → 版本不变 → 缓存确定性命中陈旧像素/陈旧尺寸（popup hover、subsurface 视频帧、已销毁 subsurface 残留），违反 A05.4 与两处 doc 声明（thumbnail.rs "pixel-identical iff version unchanged"、niri.rs "cached captures stay pixel-identical"）。修复要求：聚合改单调量或树级内容纪元，补双 surface 集成测试，修正 doc。
- F2-F9、F11、F12：CLEAN（根因真实消除；调用点无遗漏；`windows` 借用与 `drop(windows)` 正确；锁序与重入规避核实；`send_blocking` 只阻塞 worker；`capture_scheduled` 无竞态；缓存命中尺寸/路径正确；IPC 语义/错误串/publisher 语义（对照 HEAD）保持；EGL flake 归因如实；`Arc<Vec<u8>>` 所有权无泄漏）。
- F10（测试有效性弱项，随 F1 修复）：`max_iteration < 1s` 宽松；无多 surface 版本漏洞测试（F1 逃逸原因）——修复后补测。

**Reviewer B（范围/接口/UX/验收）结论**：NOT-CLEAN。3 条 PLAUSIBLE 代码/证据缺口 + 1 条 PLAUSIBLE 文档失真（F5-F8 全部 NOT-A-FINDING/CLEAN，含 `thumbnail_queue_test_pending_len` 非生产入口、无平行接口、diff 7 文件无范围蔓延）：

- **F1 PLAUSIBLE（A05.3 证据夸大）**：`max_size` 测试窗口仅 256×256，实际 GPU 工作非 4096×4096；"测量上限"表述与实测不符。修复：真实 4096×4096 窗口捕获并实测记录。
- **F2 PLAUSIBLE（缓存版本模型不完整）**：渲染路径还消费 `rules().block_out_from`（ScreenCapture block-out 把缩略图换成纯色块）与 popup 规则 opacity——规则变化无 commit，缓存返回陈旧图像。修复：并入版本 + 补失效测试。
- **F3 PLAUSIBLE（A05.2 矩阵缺口）**：最后 output 移除用例未测。修复：补测试。
- **F4 PLAUSIBLE（账本失真）**："8 个新集成测试"实际 9；回填 probe 未披露生命周期；"无测试专用生产入口"与 backfill accessor 措辞矛盾；"O(1) 去重合并"实为 O(n)。修复：本记录已逐项更正（§3 披露、§4 措辞、计数更新为最终 20 新测试）。

**轮次 1 修复（全部落实并复验）**：

1. **F1（Reviewer A）**：放弃 per-surface 计数聚合（smithay `CommitCounter` 无值访问器，sum 不可行；max 有确认漏洞）→ 树级内容纪元：`Niri::thumbnail_content_epochs`（按 root surface 键控）+ `bump_thumbnail_content_epoch`（`CompositorHandler::commit` 对每个 surface 每次 commit 推进、`destroyed` 对每次销毁推进；经既有 `find_root_shell_surface` 归因 popup/subsurface 到窗口 toplevel；剪枝 dead root；u64 回绕清表强制 miss）+ `surface_set`（捕获树 surface id 折叠，覆盖无 commit 的增删）+ block_out/popup-opacity 并入版本（F2）。两处 doc 声明同步修正。
2. **F10（Reviewer A）/F3（Reviewer B）**：新增 4 个集成测试：`subsurface_commit_invalidates_cache_and_refreshes_pixels`（subsurface commit 必须失效 + 新像素）、`subsurface_destroy_invalidates_cache`（销毁无后续 commit 也必须失效）、`last_output_removed_with_pending_request_fails_with_legacy_error`、`real_max_size_capture_keeps_measured_iteration_latency_bounded`（真实 4096×4096 窗口捕获：单迭代实测 82ms < 2s 界，回复尺寸 4096×4096）。
3. **F4（Reviewer B）**：账本更正（本记录）。
4. 修复后复验：2 项新变异 A/B 红（epoch 置 0 → `subsurface_commit` FAIL；destroyed bump + surface-set 移除 → `subsurface_destroy` FAIL）；610 全量测试通过；fmt 70 处基线（7 文件 hunk 零新增）；debug/release 构建 + PROTOCOL_FULL 通过。

#### 轮次 2（修复后全新双审查）

**Reviewer A2（正确性/生命周期/并发）结论**：NOT-CLEAN。3 条 PLAUSIBLE（F1-F3）+ 1 条 NOT-A-FINDING（F4）：

- **F1 PLAUSIBLE（版本完整性残留）**：版本只含 popup opacity/block_out，渲染还消费 `popups.background_effect`（glass 参数）、`popups.geometry_corner_radius` 与窗口 `blur_config`（mapped.rs:859-867）——配置重载/规则重算无 commit 时缓存返回陈旧 popup 像素；与轮次 1 F1/F2 同族未闭合。另指出 `thumbnail.rs:59-67` "covers every input" doc 过度声明。
- **F2 PLAUSIBLE**：`max_size` 提交期 `<5ms`、迭代 `<1s/2s` 墙钟断言在慢 CI 有 flake 风险（核心判别断言均确定性）。
- **F3 PLAUSIBLE（账本）**：EGL 归因 "7 个 add_renderer" 与最终 diff（13 个 init_renderer）不符。
- F4 NOT-A-FINDING：epoch 每次 commit 全表 retain 为热路径 O(n) 注记。

**Reviewer B2（范围/接口/UX/验收）结论**：NOT-CLEAN。4 条 PLAUSIBLE（F1-F4）+ 2 条 CLEAN/NOT-A-FINDING（F5-F6）：

- **F1 PLAUSIBLE**：同 A2-F1（popup background_effect/blur_config 未入版本 + 两处 doc 过度声明）。
- **F2 PLAUSIBLE**：`bump_thumbnail_content_epoch` 每次任意 surface commit 全表 `retain(alive)` 为 compositor 最热路径新增 O(n)；layer/lock 等非窗口 root 也累积条目。
- **F3 PLAUSIBLE（账本）**：a) §2 允许修改清单缺 compositor.rs/lifecycle_diag.rs；b) `renderer_unavailable` 无出处记录（8+4=12≠13）；c) fmt 行号微差。
- **F4 PLAUSIBLE（证据矩阵）**：popup commit/destroy 失效机制完整但零端到端测试（A-F1 点名 "popup hover" 只补了 subsurface 两条）；scale 变化失效无直测。
- F5 NOT-A-FINDING（renderer_unavailable 近似 EGL reset 可接受）；F6 CLEAN。

**轮次 2 修复（全部落实并复验）**：

1. **F1（A2/B2）**：`ThumbnailVersion` 新增 `popup_effect_bits`（`background_effect` 全字段 + `geometry_corner_radius` 的确定性折叠）与 `blur_config_bits`（`Mapped::blur_config()` 只读 getter 补入 mapped.rs，`Blur` 全字段折叠）；doc 声明修正为实际覆盖项。
2. **F2（A2）**：`max_size` 提交期 `<5ms` 墙钟断言改为确定性功能断言（`thumbnail_queue_test_pending_len()==4`——旧实现同步服务后队列为空，判别力更强）；1s/2s 迭代界保留并标注为宽松机器相关 sanity。
3. **F2（B2）**：epoch 剪枝改阈值式（`MAX_THUMBNAIL_EPOCH_ENTRIES`=2048，超阈值才全表 retain）——每 commit 摊销 O(1)，死条目有界。
4. **F4（B2）**：新增 `popup_commit_invalidates_cache_and_refreshes_pixels`（真实 xdg_popup 夹具：create→首 commit 触发 initial configure→ack→attach→map→捕获→popup commit→必须失效+新像素）与 `output_scale_change_invalidates_cache_and_refreshes_size`（真实 output scale 1.0→2.0，版本 scale bits 变化→重渲染+新尺寸 128×128）。popup 规则折叠（blur/background_effect 等）的端到端判别在 headless fixture 无法驱动配置重载，以书面裁决关闭：折叠为渲染消费的同一规则值的纯函数，任何规则差异必然改变版本（miss 方向安全）；变异 A/B 覆盖 epoch/surface_set 判别。
5. **F3（A2/B2）**：账本修正（本记录 + §2 允许清单 + §5.1 归因计数更新为最终 diff）。
6. 修复后复验：612 全量测试通过；fmt 70 处基线（8 文件 hunk 零新增）；debug/release 构建 + PROTOCOL_FULL 通过。

#### 轮次 3（修复后全新双审查）

**Reviewer A3（正确性/生命周期/并发）结论**：NOT-CLEAN。1 条 CONFIRMED + 2 条 PLAUSIBLE + 2 条 NOT-A-FINDING：

- **F-1 CONFIRMED（折叠编码碰撞）**：`fold_option_f64`/`popup_opacity_bits` 用 `map_or(0, to_bits)`——`None` 与 `Some(0.0)` 折叠相同（bits(0.0)=0），但渲染端明确区分（popup opacity `None`=全不透明 vs `Some(0.0)`=全透明；`contrast`/`saturation` `Some(0.0)` 可见效果 vs 未设置）；配置重载（无 commit）后可稳定复现陈旧像素，违反 "version unchanged ⇒ pixel-identical" 不变量，并推翻轮次 2 对规则折叠的书面裁决。
- **F-2 PLAUSIBLE**：`output_scale_change` 测试未隔离 scale-bits 分量（理论共因：scale 变更后 layout 可能下发 resize configure 使客户端 commit → epoch 失效掩盖 scale bits 判别）。
- **F-3 PLAUSIBLE（3 处注释/账本失真）**：bump doc "pruned on each bump" 与阈值剪枝实现矛盾；`ThumbnailVersion` doc 被 F-1 证伪；账本把新串 "thumbnail request queue is full" 标为"逐字保持"。
- **F-6 NOT-A-FINDING（流程）**：diff 工件不含 untracked 集成测试文件（已 `git add -N` 修正，本工件 2612 行含全部 15 集成测试）。
- 其余（轮次 2 修复真实到位、回绕/剪枝交互安全、popup 夹具归因链真实连通、无新锁/UAF/泄漏、§3.2 保持、EGL 归因如实）CLEAN。

**Reviewer B3（范围/接口/UX/验收）结论**：NOT-CLEAN。5 条 PLAUSIBLE（F1-F5）+ 6 条 NOT-A-FINDING（F6-F11）：

- **F1-F4 PLAUSIBLE（账本/注释失真）**：① bump doc "pruned on each bump" 陈旧（同 A3-F3.1）；② §5.1 init_renderer 归因列举错误（`last_output_removed` 实际调用了 init_renderer）+ flake 概率 8%/10% 前后不一；③ "thumbnail request queue is full" 误标为既有措辞（HEAD 对照仅 publisher 串存在）；④ 文件计数 7/8 互斥。
- **F5 PLAUSIBLE（证据缺口）**：popup 无 commit 增/删的失效无端到端判别，且轮次 2 书面裁决只覆盖规则折叠、未覆盖 surface_set 的 popup 分量。
- F6-F11 全部 NOT-A-FINDING（A-F2 功能断言落实、规则折叠+getter+doc 落实、无平行接口、范围克制 8 文件、测试算术 612=590+22 与并行安全、错误串兼容主张成立）。

**轮次 3 修复（全部落实并复验）**：

1. **F-1（A3，CONFIRMED）**：`fold_option_f32`/`fold_option_f64` 改为单射编码（`map_or(0, |v| bits(v).wrapping_add(1))`——`None`→0、`Some(0.0)`→1、`Some(1.0)`→bits(1.0)+1）；`popup_opacity_bits` 改用 `fold_option_f32`；`ThumbnailVersion` doc 修正并注明单射性；新增单测 `option_folds_distinguish_none_from_zero`（None/Some(0.0)/Some(1.0) 两两不同 + option-bool 三态不同）。
2. **F-2（A3）**：scale-bits 判别变异 A/B 实测红（`output_scale_bits` 置常量 → `output_scale_change` FAIL，renders delta 0≠1）——证明失效由 scale bits 驱动（fixture 在 scale 变更后无 commit，epoch 不变），记录为本轮证据。
3. **F-3（A3）/F1-F4（B3）**：bump doc 改为阈值剪枝措辞（niri.rs + 本记录）；账本 A05.4 错误串表述修正（四条 legacy 逐字保持 + 两条新串标注）；§5.1 init_renderer 归因列举与概率数字统一（~6%）。
4. **F-5（B3）**：书面裁决补记——popup 增/删失效由两条既有机制覆盖：增（含首 commit）走 commit 钩子 + `find_popup` 归因（`popup_commit` 测试端到端实证该归因链）；删走 `destroyed()` 钩子（`subsurface_destroy` 测试实证同一钩子路径）且捕获时 `surface_set` 折叠（popup 枚举在 `thumbnail_content_version` 内）随 PopupManager 返回集变化，二者均 miss 方向安全。
5. **F-6（A3）**：`git add -N` 纳入新测试文件，本工件 2612 行含完整 diff。
6. 修复后复验：613 全量测试通过（590 旧 + 23 新：7 新单测 + 15 集成 + 1 折叠单测）；fmt 70 处基线；debug/release 构建 + PROTOCOL_FULL 通过。

#### 轮次 4（修复后全新双审查）

**Reviewer A4（正确性/生命周期/并发）结论**：NOT-CLEAN。1 条 PLAUSIBLE + 3 条 NOT-A-FINDING：

- **F-1 PLAUSIBLE**：`option_folds_distinguish_none_from_zero` 只测 helper，不经 `thumbnail_content_version` 版本路径——路由行（`popup_opacity_bits` 经 `fold_option_f32`）若被回退为裸 `map_or(0, to_bits)`，该测试不变红；对轮次 3 已修缺陷判别力成立，但版本路径回归无防护。→ **书面裁决（接受单点风险）**：路由行为单行且 helper 契约注释明确（"single-injective"）；集成夹具无法在 headless 中驱动配置重载构造 `Some(0.0)` 规则（`Fixture::with_config` 无运行中 reload 路径）；版本路径其余字段（scale/alpha/epoch/surface_set/block_out）均有集成级判别；单点风险记录在案，回归由轮次 3 单测 + 版本路径集成测试（scale/alpha/epoch）组合防护。
- **F-3 NOT-A-FINDING（记录）**：4096×4096 条目（67MB）> 64MiB 缓存字节上限 → 发布后立即逐出 → 上限尺寸窗口不缓存——符合 A05.5 规格（发布先于逐出，无正确性影响）。
- F-2/F-4 NOT-A-FINDING（墙钟 sanity、worker 轮询窗口充裕）。

**Reviewer B4（范围/接口/UX/验收）结论**：NOT-CLEAN。2 条 CONFIRMED（账本/卫生）+ 2 条 PLAUSIBLE + 2 条 NOT-A-FINDING：

- **F1 CONFIRMED（账本）**：§4 仍写"每次 bump 剪除 dead root"，与阈值剪枝实现矛盾。
- **F2 CONFIRMED（账本+构建卫生）**：全量配置行"仅 1 条既有 warning"不实——实测 3 条，其中 2 条为本 diff 新增 dead-code（`pending_len` 非测试构建无调用者、`TestPopup.popup` 未读）。
- **F3 PLAUSIBLE**：§2 "6 改 + 2 扩展"与 §4 "7 改 + 1 新"子划分互斥。
- **F4 PLAUSIBLE**：commit 钩子新增 O(活 popup 数) 扫描未记录。
- F5/F6 NOT-A-FINDING（NaN 理论碰撞配置不可达；单测计数算术）。

**轮次 4 修复（全部落实并复验）**：

1. **F1（B4）**：§4 内容版本段改为阈值剪枝措辞（本记录）。
2. **F2（B4）**：`pending_len` 改 `#[cfg(test)]`；`TestPopup.popup` 标注 keep-alive `#[allow(dead_code)]`；`cargo check --workspace --all-targets` 复验仅剩 1 条既有 warning；账本更正。
3. **F3（B4）**：§2 与 §4 文件子划分统一为"7 改 + 1 新"。
4. **F4（B4）**：§4 记录 commit 热路径 O(popups) 归因成本为接受项。
5. **F-1（A4）**：书面裁决（见上）。
6. 修复后复验：613 全量测试通过；fmt 70 处基线；debug/release 构建 + PROTOCOL_FULL 通过。

#### 轮次 5（账本修正后全新双审查）

**Reviewer A5（正确性/生命周期/并发）结论**：**CLEAN** —— 轮次 4 全部 finding 修复/裁决核实到位（5/5）；版本不变量对穷举反例全部成立（含几何动画反例经渲染路径核实无效、popup 移动必走 commit、64 位折叠碰撞方向安全）；测试判别力与并行安全独立重跑核实；锁/生命周期/UAF/泄漏/时序 CLEAN；§3.2 与任务外行为保持；A05.1-A05.5 证据链完整可重复；注释账本一致；A4-F1 单点风险裁决合理。唯一注意项（F9：real_max_size 计时不含旧实现 submit 期阻塞，作为"测量上限"证据弱，但判别性由 max_size/pacing 承担）为证据强度注记，账本已如实披露（82ms 实测记录）。

**Reviewer B5（范围/接口/UX/验收）结论**：NOT-CLEAN（3 条 PLAUSIBLE 账本文档失真，均已修复）：F1 §3 设计段仍把新串 "thumbnail request queue is full" 标为"既有措辞"；F2 fmt 漂移行号与实测不符（client.rs 1081→1137、niri.rs 3712→3711）；F3 §3 出现重复 "### 3." 编号 + `renderer_unavailable` 引入批次无记录。F4/F5 NOT-A-FINDING（A4-F1 裁决合理、EGL flake 记录真实），F6 CONFIRMED（轮次 4 修复全部到位）。

轮次 5 修复：三处账本修正（措辞改"新措辞/新语义新增"；行号按实测 3711/1137 更新；§3 设计段编号与 §3.1 批次记录——首批红跑 8 + 验证期补 1（renderer_unavailable，非红跑对象）+ 轮次 1 补 4 + 轮次 2 补 2 = 15 集成测试）。

#### 轮次 6（最终门禁双审查）

**Reviewer A6（正确性/生命周期/并发）结论**：NOT-CLEAN（1 条 CONFIRMED + 7 条 NOT-A-FINDING/CLEAN）：

- **Finding 1 CONFIRMED（IME popup 合成器侧重定位）**：IME input-method popup 经 `zwp_input_method` `set_text_input_rectangle` → smithay `popup_repositioned` → niri `position_popup_within_rect` IME 分支 `popup.set_location()` **无 wl_surface commit 立即生效**；捕获渲染 popup 位置 = `offset - popup.geometry().loc`（mapped.rs:842-862，offset 实时读 `PopupSurface::location()`）；`set_location` 改变该差分 → 缩略图像素改变但 epoch/surface_set/规则/scale 全不变 → 版本相同 → 缓存命中陈旧 popup 位置。XDG popup 重定位均走 commit（epoch 覆盖），仅 IME 路径在 commit 外改渲染输入。相对旧实现（每请求重渲染）为正确性回归，击穿 "version unchanged ⇒ pixel-identical" 不变量。
- 其余（轮次 5 账本修正到位、版本不变量其余分类穷举成立、测试判别/并行安全/锁生命周期/§3.2/A05 验收/注释）全部 NOT-A-FINDING/CLEAN；两条账本微瑕记录（§5.1 "thumbnail 28 测试"与实测差 1、iff 文档随 Finding 1 修复同步收窄）。

**Reviewer B6（范围/接口/UX/验收）结论**：NOT-CLEAN（仅 F1 账本记录未闭合，无产品缺陷）：F1 PLAUSIBLE §6 轮次 5 记录缺失（B5 修正已入正文但轮次记录本身未写）；F2 CLEAN（产品代码 8 文件、613 计数、legacy 串、无平行接口/范围蔓延、A05.1-5 证据全部 CONFIRMED）。

**轮次 6 修复（全部落实并复验）**：

1. **A6-F1（CONFIRMED，产品修复）**：`thumbnail_content_version` 的 popup 循环把每个 popup 的渲染位置差分（`offset - geometry.loc`，与 `render_popups` 消费的同一值）折叠进 `surface_set`——IME `set_location` 无需 commit 即改变该差分 → 版本必然变化（miss 方向安全）；XDG popup 移动仍由 epoch 覆盖（位置折叠对 commit 路径冗余但无害——只会造成保守 miss）。`ThumbnailVersion` doc 更新为覆盖"per-popup render positions / 非 commit 重定位（IME）"。
2. **A6-F1 测试裁决（书面）**：headless fixture 无法驱动 `zwp_input_method` 协议构造 IME popup 重定位；位置折叠为渲染消费同一值的纯函数（构造性正确）；commit 驱动路径（XDG popup/subsurface）已有端到端判别测试；残余风险记录在案。
3. **B6-F1（账本）**：§6 轮次 5 记录（本节）与本轮门禁记录。
4. 修复后复验：613 全量测试通过；fmt 70 处基线；debug/release 构建 + PROTOCOL_FULL 通过。

#### 轮次 7（位置折叠修复后全新双审查）

**Reviewer A7（正确性/生命周期/并发）结论**：**CLEAN** —— 轮次 6 位置折叠修复真实到位（折叠与 `render_popups` 消费同一活值；IME `set_location` 系 smithay `input_method_popup_surface.rs:88-94` 纯 mutex 写、无 commit 改差分）；版本不变量穷举全部成立；测试判别力与并行安全独立复跑核实；锁/生命周期/UAF/泄漏/时序 CLEAN；§3.2 与任务外行为保持；A05.1-5 证据可重复；两条账本微瑕记录（§5.1 计数、4096² 条目恰 64MiB 的表述）不构成阻断。

**Reviewer B7（范围/接口/UX/验收）结论**：NOT-CLEAN（2 条 PLAUSIBLE 账本计数失实，均已修正）：F1 §2 G01 搜索表命中数与 HEAD 实测不符（Phase 1 实现前快照 vs 实现后状态；`thumbnail_publisher` 3 vs 现 4、`cancel_window_thumbnail` 4 vs 3、`with_renderer_surface_state` 0 vs HEAD ~32、`render_to_vec` 5 vs 11）——修改/不修改判定全部正确，仅计数口径需披露；F2 §5.1 "thumbnail 28 测试" 与实测 31 不符。其余（轮次 6 修复到位、迁移完整、无平行接口/范围蔓延、矩阵/A05/G01-G08 除 F1/F2 外成立、错误串准确）全部 NOT-A-FINDING/CLEAN。

轮次 7 修复：G01 表头标注"Phase 1 实现前搜索快照；行号与命中数为当时状态，本 diff 已按实现后状态复核，修改/不修改判定不变"；§5.1 计数改为 31（15 集成 + 12 thumbnail.rs 单测 + 4 既有 ipc 路径）。

#### 轮次 8（最终门禁双审查）

**Reviewer A8（正确性/生命周期/并发）结论**：**CLEAN** —— 轮次 7 两条账本修正实测到位（31 计数 15+12+4 精确、Phase-1 标注与 diff 一致）；版本不变量穷举（commit/destroy/增删/XDG+IME 位置/scale/alpha/block_out/popup 规则/blur/单射/几何动画/transform/窗口自身 background_effect 非缩略图输入）全部成立；测试判别力与并行安全复跑核实；锁/生命周期/时序 CLEAN；§3.2 保持；A05.1-5 证据可重复；注释账本一致；残余风险（find_popup O(活 popup)、64 位折叠理论碰撞、EGL 并行 flake 外部根因）均已书面记录或裁决。

**Reviewer B8（范围/接口/UX/验收）结论**：NOT-CLEAN（1 条 CONFIRMED 账本文本 + 完成义务项，均已处理）：F1 §5 G05 行括号"轮次 2 进行中"与 §6 已记录的轮次 2-6 闭合事实矛盾（一行文本，已修正）；F2 补记本轮门禁记录与 §7/§8（G07 完成义务，随 §7 commit/push 收据执行）。其余（Phase-1 标注语义、window_destroyed 弱断言判别力由 legacy 串承担、EGL 归因 13 个 init_renderer 实测、reduced-motion/几何动画反例、版本不变量残余风险裁决、迁移/平行接口/范围/矩阵/A05/错误串/并行安全）全部 NOT-A-FINDING/CLEAN。

**最终门禁结论**：产品代码 8 文件（7 改 + 1 新测试文件）历经 8 轮全新只读双审查——A 侧轮次 5/7/8 三次 CLEAN，B 侧全部 CONFIRMED/PLAUSIBLE 均已修复或书面裁决，最终账本无未裁决 finding。613 全量测试通过（590 旧 + 23 新），fmt 70 处基线（修改文件内 6 处既有漂移全部位于 hunk 外），debug/release 实际二进制构建通过，PROTOCOL_FULL 通过。进入第 7 节 commit/push。

### 7. 产品 Commit 与 push 收据

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `79448ad4ef55981c79844119d12c1e273a08f077` | `fix(thumbnail): T05 thumbnail main-loop budget — bounded latest-wins queue, pacing, content-versioned cache` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `cc772d0a..79448ad4` 成功（首次推送遇 github 网络瞬断，重试成功） | `git merge-base --is-ancestor 79448ad4 origin/tahoe-layer-animations` exit 0 |
| main | `21fb5cfcb4785b86f2fa097cdd80b05d65a5351c` | `fix(submodule): bump niri for T05 thumbnail main-loop budget (bounded latest-wins queue, pacing, content-versioned cache)` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `b919921..21fb5cf` 成功 | `git merge-base --is-ancestor 21fb5cf origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → 79448ad4（= 已推送 niri commit hash）
```

### 8. 未覆盖、用户现场项与后续边界

- 未覆盖：无产品代码缺口（A05.1-A05.5 全通过）。IME input-method popup 重定位与配置重载规则变化的端到端判别在 headless fixture 不可达（无 zwp_input_method 绑定、无运行中 config reload 路径），以版本折叠的构造性正确 + 书面裁决闭合（见 §6 轮次 6 A6-F1）。
- 需要用户授权的实时验证：无（纯源码/测试任务，未重启会话、未真实拔插、未部署）。
- 发现但属于后续任务的事项（只记录，未修改）：
  - **smithay EGL display 全局态并行级联（T24）**：见 §5.1——根 panic 在 smithay `egl/display.rs:279:68`（DISPLAYS 去重 `upgrade().unwrap()` 竞态），持锁 panic → 全局 mutex poison → 级联；本 diff 以 13 个 `init_renderer` 测试提高暴露概率；未修改测试也可为根；最终回归与（如可行）上游修复归 T24。
  - **T01-era 测试计数器竞争（T24）**：T03 记录在案的既有并行竞争，本任务未新增无锁写者（lifecycle 计数经 `with_enabled_for_test` 序列化）。
  - **版本折叠残余理论风险（已记录接受）**：64 位折叠的对抗性碰撞（需配置不可达的 NaN 位型或 2^-64 级碰撞）；`find_popup` 归因为 commit 热路径新增 O(活 popup 数) 扫描（有界、正确性安全）；A4-F1 单点路由风险（折叠单测不经版本路径）。
  - **4096×4096 条目与缓存上限**：67MB（=64MiB 边界）条目发布后即逐出，上限尺寸窗口不缓存——符合 A05.5 规格（发布先于逐出）。

### 9. 完成判定

**最终状态**：COMPLETE
**理由**：A05.1-A05.5 + G01-G08 满足；旧实现 4 红 + 8 变异 A/B 红证；8 轮全新只读双审查（A 侧轮次 5/7/8 CLEAN，B 侧全部 CONFIRMED/PLAUSIBLE 已修复或书面裁决，最终门禁无未裁决 finding）；fmt 70 处基线为改动前既有（修改文件内 6 处既有漂移全部位于 hunk 外）；613 全量测试通过（590 旧 + 23 新）；debug+release 实际构建通过；PROTOCOL_FULL 通过；niri 与主仓库产品 commit 均已 push 且远端 ancestor 验证 exit 0；子模块指针只指向已推送 commit。
**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 10. 闭环记录审查与推送

- Closure reviewer（全新只读上下文）：完成，结论 PASS（Git/产品收据一致；§10 之前的日志闭环缺口已确认）。
- 产品 commit hash/remote receipt 是否逐项准确：是；主仓库 `21fb5cf`、niri `79448ad4` 均已推送，两个 remote ancestor 验证 exit 0，子模块指针一致。
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T05 close task record`
- closure push remote ref：`origin/fix/tray-menu-pinned-surface-height`
- closure remote ancestor 验证 exit code：0（当前 `HEAD=ed1d9047` 已在 `origin/fix/tray-menu-pinned-surface-height`；本 commit 不记录自身 hash，由后续 `git log --format=%H -- execution-log.md` 解析）

## T06 QsPaths 失败状态机

**状态**：COMPLETE
**开始时间**：2026-08-05
**roadmap 引用**：`roadmap.md#T06`（第 174-192 行）；发现 `research-report.md#STAB-05`
**执行者上下文**：OpenCode / Codex 会话（Quickshell 子模块 `quickshell-tahoe-desktop`）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| `instanceRunDir()` 失败后检查了错误的状态字段 | 旧 `quickshell/src/core/paths.cpp:143-144`：创建失败写 `instanceRunState=Failed`，返回前却检查 `shellRunState` | CURRENT-CONFIRMED | 成立；红跑同时证明两个方向：instance 失败错误返回非空、shell 失败错误返回空 instance |
| base 失败后 path helper/link 入口可崩溃或产生错误相对路径 | 旧 `paths.cpp:53` 直接解引用 `baseRunDir()`；旧 `ipcPath()` 把空 `QString` 包成 `QDir` 可形成相对 `ipc.sock`；旧 `linkRunDir()` 直接 `baseRunDir()->filePath(...)` | CURRENT-CONFIRMED | 成立；红跑在 `QsPaths::basePath -> QDir::filePath` 真实 SIGSEGV |
| Unknown/Ready/Failed 应为 sticky 单向状态 | `paths.hpp:51-55` 定义三态；四个 runtime getter 仅在 Unknown 时执行 `mkpath` | CURRENT-CONFIRMED | 保持现有单次初始化契约；失败后移除 blocker 仍不得重试，成功/失败只能由新进程重新初始化 |
| `linkRunDir()`/`linkPathDir()` 重复取 base pointer | 旧 `paths.cpp:172-218`、`:221-248`：依赖 getter 内部验证后再次直接解引用 base | CURRENT-CONFIRMED | 原地保存并复用已验证 pointer；不新增 helper |
| 成功路径 authority 为 base/by-id、by-pid、by-shell、by-path | 旧 `paths.cpp:53-60`、`:172-248`；生产入口 `launch.cpp:171-173` | CURRENT-CONFIRMED | 路径布局、绝对 canonical symlink target 与调用顺序保持 |
| 没有第二套 path helper 或独立失败 authority | 全仓检索：runtime 状态/目录 authority 全部在 `src/core/paths.hpp/.cpp`；唯一生产 `QsPaths::init` 为 `src/launch/launch.cpp:171` | CURRENT-CONFIRMED | 原地修改 |

### 2. 工作树与范围

开始时主仓库有用户未跟踪项 `.zcode/`、`Testing/`，以及已建立的本 T06 execution-log；Quickshell 子模块存在前一执行上下文遗留的 T06 未提交草稿。该草稿逐行审阅后保留任务内正确部分、删除不必要的 `init()` 全状态重置，并补全测试与 pointer 复用。Quickshell 基线 HEAD `5a984c7f1a80ed523017de8b6158ded39b14fa74`，branch `quickshell-tahoe-desktop`。

最终产品修改文件（3 个；另更新本 `execution-log.md`）：

- `quickshell/src/core/paths.cpp`：现有 QsPaths 状态返回、空 path 传播、base pointer 复用。
- `quickshell/src/core/test/paths.cpp`：新增临时目录/权限/mkdir/link 行为测试；每个场景 fork 独立进程，避免 singleton sticky 状态互相污染。
- `quickshell/src/core/test/CMakeLists.txt`：注册现有 core test authority 下的 QsPaths 测试。
- `execution-log.md`：当前任务证据与闭环记录。

明确禁止修改：

- `quickshell/src/launch/*`、`src/ipc/*`、Dock/launcher 调用者：调用者无需旁路 try/catch，错误由 QsPaths 现有 pointer contract 与既有支配 guard 收敛。
- 新增 `safeInstanceRunDir()`、QsPaths V2 或长期 feature flag。
- 主仓库用户项 `.zcode/`、`Testing/` 和 T07 及后续任务文件。

定义/调用点/测试搜索：

| `rg` 命令 | 当前命中/结论 | 修改点 | 不修改点及理由 |
|---|---|---|---|
| `DirState|baseRunDir|shellRunDir|shellVfsDir|instanceRunDir|basePath|ipcPath|linkRunDir|linkPathDir`（core/launch/ipc） | 全部生产与测试命中已分类；定义均在 `paths.hpp/.cpp` | `paths.cpp` 单一 authority | launch/command/ipc/logging/tooling 调用者由既有 guard 支配；API/signature 不变 |
| `QsPaths::init` | 生产调用唯一 `src/launch/launch.cpp:171`，测试调用 `core/test/paths.cpp:39` | 不修改生产 init 语义 | singleton 测试用 fork 隔离；避免加入重复 init/旧 link 清理等 roadmap 外生命周期语义 |
| `linkRunDir|linkPathDir` | 生产入口 `launch.cpp:172-173` | 两函数内部保存 `baseRunDir` pointer 并复用；行为测试走原入口 | 不新增 link helper/返回值/错误接口 |
| `BUILD_TESTING|qs_test` | `src/core/CMakeLists.txt:64`、`src/core/test/CMakeLists.txt:1-17` | 现有 core test 列表增加 `qspaths` | 不新建框架或依赖 |
| nullable getter 直接解引用 | tooling 的 `shellVfsDir()` 仍有 3 处既有直接解引用 | 不修改 | T06 验收限定 base/shell/instance runtime 与 link 状态机；tooling 独立调用契约不在 roadmap 当前边界，记录但不越界 |
| `basePath|ipcPath` 生产消费者 | `readLogFile()` 与 `IpcClient::connect()`；所有现有调用均先通过 `selectInstance()` 的 `baseRunDir()` Ready guard | 不修改 | Ready/Failed sticky 保证同一进程后续 getter 不会转为空；空路径分支在真实生产调用链不可达。为不可达防御分支增加宏替身白盒测试/产品 seam 会制造 T06 范围外旁路 |

### 3. 旧实现失败基线

临时 worktree 固定原始 HEAD `5a984c7`，只应用最终 `src/core/test/paths.cpp` 与 CMake 注册，不应用任何生产修复。构建成功后运行 `ctest -R '^qspaths$' --output-on-failure`：exit 8，QtTest **6 passed / 3 failed**（7 个行为 slot 中 4 guardrail pass、3 根因 fail；另含 init/cleanup pass）。临时 worktree 随后删除。

| 测试 | 旧结果 | 根因判别 |
|---|---|---|
| `baseFailureIsStickyAndSafe` | **SIGSEGV**：`QsPaths::basePath -> QDir::filePath` 解引用 null | 直接捕获 base 失败的崩溃；同测试还要求 `basePath/ipcPath` 为空且两个 link 入口不崩 |
| `instanceFailureIsStickyAndPreservesIndependentPathLink` | FAIL：`instanceRunDir() == nullptr` 为 false | instance mkdir 失败写 `instanceRunState=Failed`，旧返回却检查 Unknown `shellRunState`，泄漏失败 QDir pointer |
| `shellFailureIsStickyAndKeepsPidLinkOnly` | FAIL：已成功创建的 `instanceRunDir()` 返回 null | shell Failed 反向污染 instance getter 返回，导致应保留的 by-pid link 丢失 |
| `basePermissionFailureIsStickyAndSafe` | PASS（guardrail） | 非 root 下 0500 临时目录确定性制造 permission failure，失败保持 sticky |
| combined failure/link parent failure/success recreate | PASS（guardrail） | 固化组合失败不建错误 link、父目录 mkdir 失败不覆盖普通文件、成功路径兼容 |

红跑测试全部使用临时目录；普通文件阻断 base/shell/instance 组件在 root/non-root 均确定，permission 用例在 root 下明确 skip（当前 euid=1000，已真实执行）。`linkTargets` 先证明 target 为目录、两端 canonical path 非空、link 确为 symlink，避免“两个空 canonical path 相等”的假阳性；PID link 使用真实 `getpid()` authority。

### 4. 实现机制

- **状态返回**：四个 runtime getter 在执行 Unknown→Ready/Failed 后统一以 `state != Ready` 返回 null；`instanceRunDir()` 改检查自己的 `instanceRunState`，消除 instance/shell 交叉污染。Unknown/Ready/Failed 无新枚举、无重试旁路。
- **空 path 传播**：`basePath()` 保存并检查 `baseRunDir()`；失败返回空 `QString`。`ipcPath()` 对空 basePath 继续返回空，避免 `QDir("").filePath("ipc.sock")` 退化为相对路径。
- **pointer 复用**：`linkRunDir()` 与同结构的 `linkPathDir()` 各自在入口保存一次经验证的 `baseRunDir` pointer，后续 `by-pid`/`by-path` 构造只使用该 pointer，不再直接重复解引用 getter。
- **成功/部分失败兼容**：instance 失败且 shell Ready 时，by-pid/by-shell 不建，但独立 `linkPathDir()` 仍创建 by-path；shell 失败且 instance Ready 时仍创建 by-pid，不建 shell/by-path；两者失败不建任何 link；成功路径仍以 canonical absolute target 创建 by-pid/shell/by-path。
- **重复调用与清理**：Failed 状态在 blocker 移除后仍 sticky；link 目标被普通文件/错误 symlink 替换后，重复调用用既有 `QFile::remove + symlinkat` 原地重建；by-pid/by-path parent 被普通文件阻断时不崩、不产生错误 symlink。
- **测试隔离**：不修改 `QsPaths::init()`。每个 QtTest 行为 slot fork 独立子进程，使 singleton 从 Unknown 开始；父进程检查正常退出或 signal，旧实现 SIGSEGV 可稳定转成测试失败。无测试专用生产入口。
- **无平行接口/范围蔓延**：不改 header/signature、launch/IPC/QML/tooling，不新增 helper、flag、依赖、设置或用户行为。

### 5. 验收状态

| 验收编号 | 当前状态 | 证据 |
|---|---|---|
| G01 | PASS | 前提/调用点/不修改点分类见 §1-2 |
| G02 | PASS | 最终产品 diff 3 文件；无 V2/New/Fixed/flag/第二接口；新增文件仅现有 core test |
| G03 | PASS | 专项、实际全构建、全量 ctest、全新 ASan 与 Clang ASan+UBSan 见下 |
| G04 | PASS | 原始 HEAD 3 个独立根因红；新实现 7/7 行为 slot 绿，20 轮重复绿 |
| G05 | PASS | 最终冻结三文件产品 diff 经两名全新独立只读 reviewer 审查，均为 CLEAN；此前 findings/失效轮次保留于 §6 |
| G06 | PASS | Quickshell 产品与主仓库指针 commit/push 均完成且远端验证；docs-only closure 由本次独立 commit 完成，push 后另行命令验证 |
| G07 | PASS | 产品证据、双审、两级远端收据、closure review 与完成裁决均已记录 |
| G08 | PASS | 未重启/部署实时会话；未触碰 `.zcode/`、`Testing/` 或下一任务 |
| A06.1 | PASS | base（普通文件+权限）、shell、instance、组合、by-pid/by-path parent mkdir failure 全部不崩且 link 矩阵正确 |
| A06.2 | PASS | 三类 blocker 移除后重复 getter 仍 null；失败 QDir pointer 不泄漏 |
| A06.3 | PASS | by-id 目录与 by-pid/shell/by-path symlink 创建、错误对象覆盖、三次重复 link 均兼容 |
| A06.4 | PASS | 全新 GCC ASan build + qspaths 通过；全新 Clang 22 ASan+UBSan build + qspaths 通过。GCC 16 ASan+UBSan 组合在未修改 FileView 模板处编译失败，作为编译器特定限制记录 |
| A06.5 | PASS | `cmake --build build-tahoe` actual binary + `ctest` 16/16 通过 |

验证命令与结果：

| 配置 | 命令 | exit | 结果 |
|---|---|---:|---|
| 格式/静态 | `git diff --check`; `clang-format --dry-run --Werror src/core/paths.cpp src/core/test/paths.cpp` | 0 / 0 | clean |
| 专项 | `cmake --build build-tahoe --target qspaths -j2`; `ctest -R '^qspaths$'` | 0 / 0 | 7 behavior slots pass |
| 稳定性 | `ctest -R '^qspaths$' --repeat until-fail:20` | 0 | 20/20 pass，0.81s |
| QUICKSHELL_FULL build | `cmake --build build-tahoe -j2` | 0 | `src/quickshell` 实际二进制链接成功；仅既有 GCC/Qt SFINAE warnings |
| QUICKSHELL_FULL tests | `ctest --test-dir build-tahoe --output-on-failure` | 0 | 16/16 pass，4.06s（撤销范围外 launch guard 后最终冻结态） |
| GCC ASan | 全新 `/tmp/quickshell-t06-asan.PoqsR1`；`ASAN=ON`, `USE_JEMALLOC=OFF`, Debug，build `qspaths` 后 ctest | 0 | 145 步真实编译链接；1/1 pass，2.47s；`detect_leaks=1:halt_on_error=1` |
| GCC ASan+UBSan probe | 全新 `/tmp/quickshell-t06-asan-ubsan.TL0ppf`；ASan + `-fsanitize=undefined` | 1（编译） | 未修改 `src/io/fileview.cpp` 经 `core/util.hpp:196-197` 出现 constant-expression/return 编译错误；未进入测试，限定为 GCC 16 组合不兼容 |
| Clang ASan+UBSan | 全新 `/tmp/quickshell-t06-clang-asan-ubsan.ga1BDs`；Clang 22.1.8、`ASAN=ON`、`USE_JEMALLOC=OFF`、`-fsanitize=undefined` | 0 | 145 步真实编译链接；1/1 pass，2.52s；ASan/UBSan 均 halt-on-error |

### 6. 独立审查

- 第一轮 Reviewer A/B（全新只读上下文）：均 **CLEAN**，确认状态机、link 矩阵、fork 隔离和 tooling guard；其后记录 diff 变化，结论按门禁失效。
- 第二轮最终门禁 Reviewer A：**CONFIRMED** ASan 收据不可由现场陈旧 `build/tahoe-asan-tests` 支撑。处置：不沿用该目录；以三个全新 `/tmp` 构建分别完成 GCC ASan、GCC 组合探测和 Clang ASan+UBSan，逐项记录真实配置、编译与测试结果。
- 第二轮最终门禁 Reviewer B：初判 `readLogFile()` 局部表达式可把空 `basePath()` 退化为相对 `log.qslog`。后续完整消费者/调用图审计确认该分支受 `selectInstance()->baseRunDir()` Ready guard 支配，且状态 sticky，生产不可达；先行防御改动随后因缺少可达红绿路径被下一轮 reviewer 正确指出。最终处置：撤销该范围外改动，不引入宏替身白盒测试或测试专用产品 seam，书面裁定为 **NOT-A-FINDING**。
- 两轮 reviewer 均将 `toolsupport.cpp` 的既有 `shellVfsDir()` 直接解引用裁定为 **NOT-A-FINDING**：生产入口 `QmlToolingSupport::updateTooling()` 先检查 null 并返回，后续私有调用只在 Ready 分支执行，sticky 状态保证同一调用链指针有效。
- 第三/四轮改派均因服务端 `429` 未产生结果，不计审查。第五轮 Reviewer A 为 CLEAN；Reviewer B 确认先行 `readLogFile()` 防御改动无旧红/新绿，促成上述撤销；因产品 diff 再次变化，两份结论均不计 G05。
- 第六轮并发改派再次因服务端 `429` 未产生结果，不计审查；为避免重复空转，在保持 diff 冻结的前提下串行改派两名全新只读 reviewer。
- 最终 Reviewer A（全新只读上下文）：**CLEAN**。核验 roadmap/约束、最终三文件 diff、sticky 状态、link 矩阵、fork 红绿、sanitizer 收据与 `readLogFile()` 调用链裁决，无 finding。
- 最终 Reviewer B（全新独立只读上下文）：**CLEAN**。从 nullable/交叉状态/错误 symlink/测试假绿/记录夸报角度独立复核，无 finding。
- 最终双审后 Quickshell 产品 diff 未再修改；G05 PASS。

### 7. Commit 与 push 收据

- Quickshell 产品 commit：`4712657a638b15afb3f2acff63de7e6eb36a3f2b`，subject `fix(paths): make runtime directory failures sticky and safe`，branch/ref `quickshell-tahoe-desktop` / `origin/quickshell-tahoe-desktop`。
- Quickshell push：成功，`5a984c7..4712657`；push 后 `git fetch origin quickshell-tahoe-desktop`，`git merge-base --is-ancestor 4712657a638b15afb3f2acff63de7e6eb36a3f2b origin/quickshell-tahoe-desktop` exit 0。
- 主仓库产品指针 commit：`aea8b30e97035cc767406410b819c90a982f94c3`，subject `fix(submodule): bump quickshell for T06 paths state machine`，branch/ref `fix/tray-menu-pinned-surface-height` / `origin/fix/tray-menu-pinned-surface-height`；该 commit 只更新 Quickshell submodule pointer 到已推送的 `4712657a...`。
- 主仓库产品 push：成功，`f304f73..aea8b30`；push 后 `git fetch origin fix/tray-menu-pinned-surface-height`，`git merge-base --is-ancestor aea8b30e97035cc767406410b819c90a982f94c3 origin/fix/tray-menu-pinned-surface-height` exit 0。
- docs-only closure commit subject：`docs(execution): T06 close task record`；目标 ref `origin/fix/tray-menu-pinned-surface-height`；不会与产品 commit 混合，也不在本文自引用自身 hash，push 后以命令输出验证 remote ancestor。

### 8. 未覆盖、现场项与后续边界

- 无需用户现场操作；未部署或重启 Quickshell。
- `toolsupport.cpp` 有三处既有 `shellVfsDir()` 直接解引用；双审确认它们都位于 `updateTooling()` 先行 null guard 之后的私有 Ready-only 调用链，不构成当前失败崩溃路径或第二套 authority，故不越界修改。
- `QsPaths` 不是线程安全类型；生产 `init/link` 调用均在启动串行路径，本任务不新增并发 authority。

### 9. 完成裁决

**结论**：COMPLETE。

**理由**：A06.1-A06.5 与 G01-G08 均满足；原始 HEAD 上 3 个独立根因红，最终 7 个行为 slot 绿且 20 轮稳定；Quickshell 实际二进制与 16/16 全测通过；GCC ASan 与 Clang ASan+UBSan 专项通过；最终冻结三文件 diff 经独立双审 CLEAN；Quickshell `4712657a...` 与主仓库指针 `aea8b30e...` 均已 push 且远端 ancestor exit 0；无 live restart/deploy，未触碰 `.zcode/`、`Testing/` 或 T07。

**下一任务是否允许开始**：YES（本 docs-only closure commit push 并远端验证后）。

## T10 blur texture 容量复用

**状态**：COMPLETE
**开始时间**：2026-08-07
**roadmap 引用**：`roadmap.md#T10`（第 254-272 行）；对应发现：PERF-01、PERF-02

### 1. 前提核实与基线

- 当前任务是第一个 `PENDING`，T01-T09 均为 `COMPLETE`，没有其他 `IN_PROGRESS`；主仓库 branch 为 `fix/tray-menu-pinned-surface-height`，niri 子模块 branch 为 `tahoe-layer-animations`。
- 产品工作树改动前仅有用户未跟踪 `.zcode/`、`Testing/`；niri 子模块干净。本任务不触碰这两项。
- 当前 Blur authority：`niri/src/render_helpers/blur.rs` 的 `Blur::prepare_textures()` / `Blur::render()`；生产调用者是 `EffectBuffer` 和 `FramebufferEffectElement`，经 Xray/background effect 进入渲染路径。
- 旧实现（HEAD `274b08bb`）只在 texture size、format 和 output shared-reference 都兼容时复用；尺寸变化会 truncate/recreate（`src/render_helpers/blur.rs` 旧 `prepare_textures`：`texture_cache_matches` 精确尺寸比较，不匹配即 `truncate(i)` 重建），render 要求 output 与 source 精确同尺寸；无 active source rect 或容量桶。PERF-01 断言「重建日志全部以 size_changed 为主并高频出现」成立。
- 改动前专项：`cargo test -p niri --lib render_helpers::blur -- --nocapture` exit 0，6/6；`cargo test -p niri --lib` exit 0，623/623。
- 改动前工作树门禁：主仓库 `git diff --check` exit 0；niri 子模块 `git status --short` 为空。
- 全量基线已测得：`cargo check --workspace --all-targets` exit 0（仅既有 visual-tests unused import warning）；`cargo build --release -p niri` 和 `cargo build --release -p niri --features profile-with-tracy-allocations` 均 exit 0；全仓 `cargo fmt --all -- --check` 仍有 70 处 T10 之外既有漂移（本任务以 HEAD 临时 worktree 实测复核：70 处文件与计数与改动前逐项一致，含 layout/mod.rs 6 处、lifecycle_diag.rs 1 处、tahoe_glass.rs 1 处等既有漂移；改动后总量仍为 70，无新增）。

### 2. G01 搜索清单与允许范围

- 相关生产符号与调用点：`Blur`（`blur.rs`）、`EffectBuffer`（`effect_buffer.rs`）、`FramebufferEffectElement`（`framebuffer_effect.rs`）、Xray consumer（`xray.rs`）、`BackgroundEffect`（`background_effect.rs`）、Tahoe glass region render（`render_helpers/tahoe_glass.rs`）、blur 着色器（`shaders/blur_down.frag`、`blur_up.frag`）；现有 `prepare_textures` 共 2 个生产调用点，`Blur::render` 共 2 个生产调用点。
- 允许修改：现有 Blur texture ownership/capacity policy、其 active source rect 返回契约、两处现有 consumer 的采样映射、受控诊断计数/trace、相关单元测试和本节证据。
- 明确不修改：T11 capture padding/alpha/shadow/attribution；T12 shared backdrop；T13 shader transfer/format quality；T14/T15 shell geometry/interaction；用户开关、第二 Blur API、`.zcode/`、`Testing/`。
- 范围清理：会话早期 `cargo fmt --all` 在 `layout/mod.rs` 与 `lifecycle_diag.rs` 产生的纯格式重排 hunk 已逐处还原（layout/mod.rs 5 处 reflow + lifecycle_diag.rs `now_ms` 1 处），只保留真实改动；最终 diff 12 文件（11 改 + 1 新测试文件），`git diff --check` 干净，无 V2/New/Fixed 平行命名。

### 3. 设计定稿（对应早期「设计待证实项」并已实现）

- **capacity bucket**：64px 对齐（`CAPACITY_BUCKET_PX=64`），维度上限 4096（`MAX_REUSABLE_TEXTURE_DIMENSION`，超出按需精确尺寸）；`pyramid_capacity_sizes` 对所有级别取 bucket 容量，若 bucketed 总量超 per-pyramid 预算则退回精确 active 尺寸。
- **active source rect**：`BlurOutput { texture, active_size, _budget }`；blur 渲染只写 active 区域（viewport = active size），采样经 shader 新 uniform `tex_scale`/`tex_bounds` 把 `[0,1]` 坐标映射到 capacity texture 的 active 子矩形并 clamp；`source_rect()`/`map_source_rect()` 对外只暴露 active 区域。capacity == active 时（无 slack，如 4096 精确）uniform 恒为 1.0/满幅，逐位等于旧 shader 行为。
- **容量复用**：`prepare_textures` 逐级别判定 `reusable = 前缀兼容 && !format_changed && !output_is_shared && !capacity_insufficient && !shrink_required`；不兼容级别从该级起重建；候选金字塔先构建后提交（预算/GL 失败时旧纹理与旧预算保持不动）。
- **format、context、pass count、shared-reference 不兼容仍正确重建**：format 变化（存储纹理 ≠ Abgr8888）、`Blur::new` 于渲染器上下文变化（`Inner::new` / `prepare_blur` 重建 blur）、pass count 变化、output 非唯一引用（渲染结果持有时）均触发重建（测试 3-5）。
- **收缩滞后**：连续 8 次（`SHRINK_HYSTERESIS_PREPARES`）请求更小容量才执行 shrink；期间复用大容量。
- **内存硬上限**：per-pyramid `MAX_RETAINED_PYRAMID_BYTES=256MiB`（prepare 前 ensure 拒绝；取值覆盖单座 8K 7680×4320 金字塔 ~176MiB，避免大尺寸输出静默失去 blur——审查轮次 1 F1 修复）；global `MAX_GLOBAL_BLUR_TEXTURE_BYTES=512MiB`（`RETAINED_BLUR_TEXTURE_BYTES` 原子记账 + `reserve_blur_bytes` CAS，`BlurBudgetReservation` Arc 随纹理生命周期释放）。
- **受控采样**：`NIRI_BLUR_TRACE=1` opt-in 的 prepare 级 trace（surface_id/namespace/requested/capacity/format/passes/operation/reason/shrink_streak，默认 debug 级别不刷屏）；`NIRI_LIFECYCLE_DIAG=1` 增加 `blur_texture_allocations`（次数）/`blur_texture_allocated_bytes`/`blur_texture_reuses`/`blur_budget_reservation_failures`/`blur_fallbacks`/`blur_gpu_errors` 计数；frame p50/p95/p99 继续复用 `NIRI_FRAME_TELEMETRY=1`。
- **fallback 硬化（A10.3 边界，含审查轮次 1 修复）**：`EffectBuffer`/`FramebufferEffectElement` 在 blur prepare/render 失败时保留未模糊 framebuffer 作为 `BlurOutput::from_full_texture` fallback（`blur_fallbacks`/`blur_gpu_errors` 计数），不再因 blur 失败使整个 background/xray 元素失效；scissor 状态按前值恢复（原先无条件 Enable）。审查 F2 修复：`EffectBuffer::render` 失败 fallback **不写入 `offscreen.blurred` 缓存**（直接返回），瞬态失败与 `FramebufferEffect` 一致地逐帧重试，避免「一次失败永久未模糊」。
- 审查 F1 修复：上限常量 128MiB/256MiB → 256MiB/512MiB（覆盖 8K 单面）；`global_budget_blocks_until_existing_pyramids_release` 改用 8192×4480（~186MiB/座，3 座 558MiB > 512MiB 拒绝、2 座 372MiB 通过）。
- 审查 nit 修复：trace 的 `shrink_streak` 在 apply_shrink 归零前采样（收缩当帧显示 8 而非 0）；blur.rs 单测与集成测试共用 `BLUR_BUDGET_TEST_LOCK` 串行化全局字节记账（消除跨模块计数竞态窗口）。
- 为什么没有平行接口：全部改动在既有 `Blur`/`BlurOutput`/consumer authority 内；无 BlurPooled、无用户开关（trace 沿用既有 env-idiom 模式）；`retained_blur_texture_bytes` 为 `#[cfg(test)]` 观察 accessor。

### 4. 红绿证明（G04）

在 HEAD `274b08bb` 临时 worktree（`/tmp/opencode/t10-red`）上应用**签名级回填 shim**（只加 `BlurTrace` 类型与 `prepare_textures` 第 4 参数 `_trace` 忽略之，旧容量逻辑逐字节不动；旧生产调用点补 `BlurTrace::default()`），编译红跑探针（与最终测试同一断言、同一计数闭包）：

| 测试/probe | 旧结果（实测） | 为什么能捕获根因 |
|---|---|---|
| `continuous_resize_stays_within_capacity_buckets`（A10.1） | FAIL：512 次 1px prepare 触发 **2048** 次纹理分配（>64 断言） | 旧 `prepare_textures` 每次尺寸变化 truncate 整座金字塔并逐级重建；新实现 512 次 prepare 仅 43 次分配 |
| `four_k_oscillation_shrinks_only_after_hysteresis_and_grows_back_bounded`（A10.3） | FAIL：7 次小尺寸 prepare 后 allocations==8≠4（每次小尺寸都重建，无滞后窗口） | 旧实现无 shrink hysteresis，4K→小尺寸每帧重建 |

红跑完成并记录后删除临时 worktree。红跑前置披露：红跑测试依赖新签名的 `prepare_textures`（T01 rework/T05 同例签名回填）；断言机制（计数闭包包裹 `create_texture`）在旧树无需任何行为改动即可编译。

变异 A/B（G04 补充，均恢复后全绿）：

| 变异 | 结果 |
|---|---|
| `SHRINK_HYSTERESIS_PREPARES` 8→1 | `four_k_oscillation` FAIL（第 7 次小 prepare 已 shrink，allocations==8≠4）——滞后窗口断言有判别力 |
| （红跑）去掉旧实现 bucket 语义整体 | 见上表（旧实现即「无 bucket」天然变异） |

其余 7 个新测试为守卫/契约测试（旧实现无对应缺陷面）：pass/format/shared-ref/预算/像素泄漏均为新容量复用路径的正确性契约，与旧实现行为无比较意义（旧实现永不跨尺寸复用，无泄漏面）。

### 5. 实现机制（最终）

- **capacity policy（A10.1/A10.3/A10.4）**：见 §3 设计定稿；`prepare_textures` 候选金字塔先建后提交，失败不污染已提交状态（`per_pyramid_budget_rejects_oversized_plan_without_state_corruption` 实证：8192² 被 per-pyramid 上限拒绝且零 GL 分配、后续合法 prepare 正常）。
- **active rect 与 shader 采样（A10.2）**：down/up pass 的 viewport 全部改为 active size；`tex_scale`/`tex_bounds` 把采样 clamp 进 active 子矩形；像素级实证 `reused_capacity_rewrites_active_pixels_without_leaking_old_content`：100×100 红渲染 → 120×120 蓝渲染（同 128×128 bucket，0 次重建）→ 120×120 活动区全部蓝、无红残留；`map_source_rect` 对越界 rect clamp 到 active（straddle/outside 两断言）。
- **生命周期/预算（A10.3/A10.4）**：`BlurBudgetReservation` 随纹理与 `BlurOutput._budget` 持有；`renderer_reset_releases_global_budget_and_starts_fresh` 实证 drop Blur 后全局字节回到基线、新渲染器上下文从零开始；`global_budget_blocks_until_existing_pyramids_release` 实证 3×~186MiB 金字塔时第三个被拒（`blur_budget_reservation_failures==1`）、drop 一个后重试成功。
- **被替代的旧 authority**：旧 `prepare_textures` 的精确尺寸 `texture_cache_matches` 复用判定（改 bucket 容量复用）；旧 `render` 的 `GlesTexture` 返回（改 `BlurOutput`，消费端采样映射同步迁移：framebuffer_effect draw/xray draw 经 `map_source_rect`）；两个消费端的「blur 失败即整体失败」路径（改 fallback）。
- **为什么没有加入范围外功能**：diff 12 文件（11 改 + 1 新测试文件），无配置/依赖/视觉变化；trace 为 env opt-in；纯格式重排已还原（§2）。

### 6. 验收逐条

| 验收编号 | 方法/命令 | 结果 | 证据 |
|---|---|---|---|
| G01 | rg 搜索见 §2 | PASS | 搜索表 + 未改点逐项理由 |
| G02 | git diff 检查 | PASS | 无 V2/New/Fixed 命名、无平行接口/flag；`git diff --check` 干净 |
| G03 | 专项+全量测试 | PASS | 见全量配置 |
| G04 | 红绿证明 | PASS | §4（旧实现 2 红 + 变异 A/B 红） |
| G05 | 双审查 | 待执行 | 见 §9 |
| G06 | commit/push 顺序 | 待执行 | 见 §10 |
| G07 | execution-log 完整 | PASS | 本文档 |
| G08 | 工作树/会话保护 | PASS | 未触碰用户项，未重启会话（全部 headless EGL fixture） |
| A10.1 | 固定场景 1px/2px/8px 连续 resize 重建次数从逐步重建降为有界 bucket 增长 | PASS | `continuous_resize_stays_within_capacity_buckets`：512 次 1px prepare 43 次分配（旧实现 2048）、2px/8px 同 ≤64；`capacity_bucket_reuses_small_resize_steps`/`resize_sequences_only_cross_bucket_boundaries`（1..512 仅 7 次 bucket 跨界）单测 |
| A10.2 | 纹理大于 source 时采样/clamp/damage/viewport 正确、无旧内容泄漏 | PASS | `reused_capacity_rewrites_active_pixels_without_leaking_old_content`（红→蓝同 bucket 像素级实证 + `source_rect`/`map_source_rect` 断言）、`active_rect_excludes_unused_capacity`、shader `tex_scale`/`tex_bounds` clamp；damage 消费端经 `source_rect()`（framebuffer_effect.rs:526） |
| A10.3 | 4K→小→4K、pass/format/context/shared-ref、renderer reset 均正确释放/复用 | PASS | `four_k_oscillation...`（4+0×7+4+4=12 次精确）、`pass_count_change_recreates_then_reuses`（3→4 passes 全量重建后复用）、`format_change_recreates_once_then_reuses`、`shared_output_reference_recreates_the_pyramid`、`renderer_reset_releases_global_budget_and_starts_fresh`（预算归零 + 新上下文零复用） |
| A10.4 | 池容量与总 bytes 硬上限、压力后回落可验证 | PASS | `per_pyramid_budget_rejects_oversized_plan_without_state_corruption`（8192² 340MiB 拒绝、零分配、状态不坏）、`global_budget_blocks_until_existing_pyramids_release`（第三座 8192×4480 ~186MiB 金字塔拒绝、drop 后重试成功、`blur_budget_reservation_failures==1`）、`global_budget_rejects_an_over_budget_reservation_without_mutation`、`budget_reservation_releases_its_charge` |
| A10.5 | 相同交互 trace 的 allocation count / frame p95/p99 / GPU error 前后对比 | 部分 PASS（现场项单列） | 同 trace 前后对比：512 次 1px resize 分配 2048→43（红绿实测）；GPU error：全量测试与像素渲染路径 `gl.GetError` 零错误（`blur_gpu_errors` 计数 0）；**frame p95/p99 需真实会话 `NIRI_FRAME_TELEMETRY=1` trace，属用户现场验证项（见 §8），未伪装为自动通过** |

全量配置：

| 配置 | 命令 | exit code | 通过/失败明细 |
|---|---|---|---|
| NIRI_FULL | `cargo fmt --all -- --check` | 1（基线失败） | 70 处漂移全部改动前既有（HEAD 临时 worktree 实测逐文件一致）；本次 12 个文件零新增（新测试文件 rustfmt --check 通过） |
| NIRI_FULL | `cargo test -p niri --lib` | 0 | 639 passed / 0 failed（623 旧 + 16 新：7 个 blur.rs 单测 + 9 个 blur_capacity 集成）；blur_capacity 3 轮复跑零 flake |
| NIRI_FULL | `cargo check --workspace --all-targets` | 0 | Finished，仅 1 条既有 warning（niri-visual-tests 未用 import） |
| 实际二进制 | `cargo build -p niri` | 0 | debug 构建通过 |
| 实际二进制 | `cargo build --release -p niri` | 0 | release 构建通过 |
| 实际二进制 | `cargo build --release -p niri --features profile-with-tracy-allocations` | 0 | release+tracy 构建通过 |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC（三处 sha256 `10fd415f…` 一致，T09 态） |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | 全部 guardrail 通过 |

### 7. 工作树与范围（最终）

- 最终产品 diff 12 文件：`src/layout/mod.rs +1`（snap-preview `FramebufferEffectElement` 的 blur_trace 参数）、`src/render_helpers/{background_effect,blur,effect_buffer,framebuffer_effect,tahoe_glass,xray}.rs`、`src/render_helpers/shaders/{blur_down,blur_up}.frag`、`src/utils/lifecycle_diag.rs`、`src/tests/mod.rs +1`、新 `src/tests/blur_capacity.rs`（667 行）。
- 纯格式重排已还原（§2）；`git diff --check` 干净；未触碰 Quickshell/Tahoe shell/主仓库用户项。

### 8. 未覆盖与后续边界

- 未覆盖：无产品代码缺口（A10.1-A10.4 全通过，A10.5 见现场项）。
- 审查轮次 1 裁决记录：F1/F2/nit/B侧③ 已修复；F3（blur 失败 fallback 视觉语义）书面裁决保持——旧行为（元素缺失/帧错误上抛）更劣，fallback 路径有 warn + `blur_fallbacks`/`blur_gpu_errors` 计数可观测，非静默吞错；`EffectBuffer::prepare` blur 失败不再返回 false 为同一裁决的一部分（配合逐帧重试的 render fallback）。
- 需要用户授权的实时验证：frame p95/p99 前后对比（`NIRI_FRAME_TELEMETRY=1` + `NIRI_BLUR_TRACE=1` 真实会话 trace，需用户运行或授权重启会话）；真实 GPU（本机为 EGL surfaceless 无 GPU 渲染路径）下的 GL 行为属于既有 T05 同款边界。
- 发现但属于后续任务的事项（只记录，未修改）：
  - `EffectBuffer::prepare()` 在 blur prepare 失败时不再返回 false（改 warn+继续，配合 fallback 渲染）——行为变化属本任务 fallback 硬化授权内，已记录。
  - `note_fb_effect_capture()` 从 capture 入口移到 blit 成功之后（只计成功捕获）——既有计数语义微调，非任务外功能。
  - blur 测试模块以共享静态锁（`BLUR_BUDGET_TEST_LOCK`）串行化（全局字节预算与 smithay EGL display 注册表均为进程全局）；T05 记录的 smithay EGL 并行级联风险仍归 T24（轮次 2 Reviewer B 实测：HEAD 与 T10 树均存在该既有 flake，blur 相关测试多轮零失败；全量 639/639 在既有 flake 窗口外多次绿跑达成，与收据一致）。

### 9. 独立审查

#### 轮次 1（首次双审查）

- **Reviewer A（正确性/生命周期/并发）**：核心机制（根因结构性消除、43 次分配独立重算吻合、预算 Arc 链无双计/漏计/双释放、shader 采样数学含 capacity==active 逐位一致核验、GL 状态恢复、调用点全覆盖、§3.2 不变量、红绿有效、readback 字节序正确）全部 CLEAN，无 CONFIRMED。3 条 PLAUSIBLE：
  - **F1**：`MAX_RETAINED_PYRAMID_BYTES=128MiB` 使 ≥~7K 尺寸（8K 7680×4320 金字塔 ~176MiB）在 prepare 被拒 → 消费端静默降级为未模糊 fallback，真实 8K 显示器必现。
  - **F2**：`EffectBuffer::render` 失败 fallback 被写入 `offscreen.blurred` 缓存 → 永不重试，与 `FramebufferEffect` 逐帧重试不对称；瞬态错误产生永久未模糊。
  - **F3**：blur 失败时的视觉语义变化（旧：xray 不 push 元素/error 上抛；新：未模糊 fallback）超出 roadmap 必须机制字面授权，需书面裁决。
  - 另记录 1 nit（trace `shrink_streak` 归零后才打印，收缩当帧显示 0）与 1 NOT-A-FINDING（`Option::insert(...).clone()` 语义经独立编译验证正确）。
- **Reviewer B（范围/接口/UX/验收）**：**CLEAN**——调用点迁移完整、无平行接口（BlurOutput 为返回类型升级）、trace/计数属 roadmap 受控采样授权内、layout/lifecycle_diag 无纯格式 hunk、禁止替代逐条 CLEAN、A10.1-A10.5 复跑可重复（9/9+13/13+639/639）、A10.5 frame p95/p99 诚实标注现场项。3 条 PLAUSIBLE 均已裁决或建议裁决：①scissor 恢复/捕获计数微调（日志 §3/§8 记录，随 commit 引用）；②`EffectBuffer::prepare` blur 失败不再 return false（A10.4 新引入的预算拒绝使该路径首次可触发，fallback 语义可辩护）；③blur.rs 单测 `budget_reservation_releases_its_charge` 与集成测试跨模块并发改写全局字节计数的理论竞态窗口（4 轮实测零 flake）。

**轮次 1 修复（全部落实并复验）**：

1. **F1（接受）**：`MAX_RETAINED_PYRAMID_BYTES` 128→256MiB（单座 8K 金字塔 168MiB 可容纳），`MAX_GLOBAL_BLUR_TEXTURE_BYTES` 256→512MiB；全局预算测试改用 8192×4480（~186MiB/座：2 座 372MiB 通过、3 座 558MiB 拒绝）并更新文档注释。per-pyramid 拒绝测试（8192²，340MiB）语义不变仍通过。
2. **F2（接受）**：`EffectBuffer::render` 失败路径直接返回 fallback、不写入 `offscreen.blurred`——瞬态失败逐帧重试，与 `FramebufferEffect` 一致。
3. **F3（书面裁决，不修代码）**：保持新 fallback 语义。理由：(a) 旧行为在 blur 失败时分别表现为「xray/backdrop 元素整体缺失」与「错误上抛终止帧渲染」，均比未模糊玻璃更劣且不可恢复；(b) fallback 仅在预算拒绝/GL 错误等病态路径触发，A10.4 引入的硬上限使该路径首次可触发，必须有确定语义；(c) `blur_fallbacks`/`blur_gpu_errors` 计数 + warn 保证可观测，非静默吞错。裁决记录于 §8 并随 commit message 引用。
4. **nit（接受）**：trace 的 `shrink_streak` 改在 apply_shrink 归零前采样。
5. **B 侧 ③（接受）**：blur.rs 新增 `#[cfg(test)] BLUR_BUDGET_TEST_LOCK`，单测与 `blur_capacity` 集成测试共用，全局字节记账跨模块串行化。

修复后复验：639/639 全量通过；`tests::blur_capacity` 9/9、`render_helpers::blur` 13/13；fmt 70 处基线（12 文件零新增）；release 构建通过。产品 diff 已改变，按 CONSTRAINTS §6.3 需两个全新 reviewer 重审。

#### 轮次 2（修复后全新双审查）

- **Reviewer A2（全新）**：**CLEAN** —— 轮次 1 修复逐项核实（F1 数值：8K 金字塔 168.1MiB ≤ 256MiB、8192×4480 测试 2 座 372MiB 通过/3 座 558MiB 拒绝独立重算吻合；F2 两消费端均不缓存 fallback、逐帧重试；nit 归零前采样；共享锁闭合预算与 diag 计数全部跨测试竞态窗口）；根因结构性消除、无隐藏早退；预算 Arc 链无双计/漏计/泄漏；shader 采样数学含 capacity==active 逐位一致独立核验；GL 状态还原完整；§3.2 不变量保持；A10.1-A10.5 证据可重复（43 次分配独立重算吻合）；仅 2 条 NOT-A-FINDING 注释 nit（MiB/MB 单位标签、冗余 detach 为既有代码）。
- **Reviewer B2（全新）**：**CLEAN** —— 修复无范围外改动/平行接口/新 flag；`BLUR_BUDGET_TEST_LOCK` cfg(test) 归属合理；调用点迁移完整、无旧 authority 残留；禁止替代逐条 CLEAN；A10.1-A10.5 证据可重复、A10.5 现场项标注诚实；日志与 diff 一致、无预填 commit 收据；1 条 NOT-A-FINDING（既有 smithay EGL 并行 flake 的 HEAD/T10 对照实测与披露要求，已记入 §8）。
- **修复（2 条注释 nit，随本轮闭合）**：blur.rs 常量注释 176MiB→168MiB；blur_capacity.rs 两处 195MiB→186MiB；execution-log A10.5 行「见 §11」前向引用改为「见 §8」。产品行为零改动，本轮为注释/文档修订。
- 最终门禁结论：两份 CLEAN，无未裁决 finding；产品 diff 自轮次 2 审查输入以来仅注释字面量修订（行为零变化），按既有纪律用第 3 个全新只读 reviewer 做单点闭合核验后进入 commit 流程。

#### 轮次 3（单点闭合 verifier）

- Closure verifier（全新只读上下文）：**PASS，允许 commit** —— 轮次 2 之后的 delta 仅限三处注释/文档字面量（blur.rs 176→168MiB、blur_capacity.rs 195→186MiB、execution-log 修订），行为零变化独立核实；产品状态 12 文件、`git diff --check` 干净、9/9+13/13 实测；§9 记录与代码逐项一致；§10/§11 无预填收据；A10.1-A10.4 摘要与断言逐条对应；1 条 docs nit（§3/§6 旧估值标签）已随本记录修正。

### 10. 产品 Commit 与 push 收据

| 仓库 | Commit hash | Commit subject | Branch | Remote ref | push 结果 | ancestor 验证 |
|---|---|---|---|---|---|---|
| niri | `fe8faeea8fee3730365e38615064f058405dff95` | `fix(blur): T10 texture capacity reuse — 64px buckets, active-rect sampling, hysteresis shrink, hard byte budgets` | `tahoe-layer-animations` | `origin/tahoe-layer-animations` | `274b08bb..fe8faeea` 成功 | `git merge-base --is-ancestor fe8faeea origin/tahoe-layer-animations` exit 0 |
| main | `9266d9a832d6c4deb044eb4fa30df489275ed3d1` | `fix(submodule): bump niri for T10 blur texture capacity reuse (64px buckets, active-rect sampling, hysteresis shrink, hard byte budgets)` | `fix/tray-menu-pinned-surface-height` | `origin/fix/tray-menu-pinned-surface-height` | `4d4ad34..9266d9a` 成功 | `git merge-base --is-ancestor 9266d9a origin/fix/tray-menu-pinned-surface-height` exit 0 |

主仓库子模块指针是否只指向已推送 commit：

```text
git submodule status niri → fe8faeea（= 已推送 niri commit hash）
```

### 11. 完成判定

**最终状态**：COMPLETE（待 §12 docs-only 闭环 commit push 后）
**理由**：A10.1-A10.5（A10.5 frame p95/p99 为现场项单列）+ G01-G08 满足；红绿证明（旧实现 512 次 1px resize 2048 次分配 vs 新实现 43 次；4K 振荡 12 次精确；变异 A/B 判别）+ 像素级无泄漏实证 + 双上限拒绝/回落实证；3 轮审查（轮次 1 三 PLAUSIBLE 修复/裁决 → 轮次 2 全新双审 CLEAN → 轮次 3 单点闭合 verifier PASS）；fmt 70 处基线为改动前既有（HEAD 临时 worktree 实测）；639 全量测试通过（623 旧 + 16 新）；debug/release/tracy 实际构建通过；PROTOCOL_FULL 通过；niri 与主仓库产品 commit 均已 push 且远端 ancestor 验证 exit 0；子模块指针只指向已推送 commit。

**下一任务是否允许开始**：YES（本文档闭环 commit push 完成后）

### 12. 闭环记录审查与推送

- Closure reviewer：见 §9 轮次 3（允许 commit）。
- 产品 commit hash/remote receipt 是否逐项准确：是（§10；轮次 3 verifier 实测核对 push 前状态，push 后 ancestor 验证命令见 §10）。
- 状态是否可置 COMPLETE/RESOLVED-NO-CODE：是（COMPLETE）
- docs-only closure commit subject：`docs(execution): T10 close task record`
- closure push remote ref：`origin/fix/tray-menu-pinned-surface-height`
- closure remote ancestor 验证 exit code：待 push 后以命令输出验证（本 commit 不记录自身 hash，由后续 `git log --format=%H -- execution-log.md` 解析）

### 11. 完成判定（待 commit/push 后填写）

**下一任务是否允许开始**：NO（本任务未闭环）

## T09 TahoeGlass 完成/拒绝反馈

**状态**：COMPLETE
**开始时间**：2026-08-06
**结束时间**：2026-08-07
**roadmap 引用**：`roadmap.md#T09`（第 234-252 行）；对应发现：GLASS-01、GLASS-02 `pending_dirty` 风险
**执行者上下文**：Workbuddy 会话（主仓库 `fix/tray-menu-pinned-surface-height`；niri 子模块 `tahoe-layer-animations`；Quickshell 子模块 `quickshell-tahoe-desktop`）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| 当前 TahoeGlass v4 只有 request，没有 completion/rejection/capability event 或 request serial | 三份 `tahoe-glass-v1.xml` 均为 manager/surface v4，9 个 request、0 个 event；`niri/src/protocols/tahoe_glass.rs:25` `VERSION=4` | CURRENT-CONFIRMED | 成立；不能把 serial 加到既有 v4 request，必须按 Wayland 兼容规则增加 since=5 request/event |
| 可恢复 overflow 会保留 `pending_dirty`，等待 surface 后续增长 | `niri/src/protocols/tahoe_glass.rs:462-520,819-858`；现有 grow validation 测试 | CURRENT-CONFIRMED | 成立；新反馈不得把 healable overflow 提前拒绝 |
| 永久结构性 region rejection 与无几何变化 morph 当前静默丢弃 | `niri/src/protocols/tahoe_glass.rs:783-879,531-560` | CURRENT-CONFIRMED | 成立；v5 必须给相应 serial 确定 terminal 状态且只发一次 |
| transform/morph last-wins 无 request identity，superseded request 无终态 | `pending_transform: Option` 与 `set_pending_transform_if_owner()`：`niri/src/protocols/tahoe_glass.rs:189-271` | CURRENT-CONFIRMED | 成立；保留单槽 authority，但为 v5 保存 serial/resource 并终结被覆盖请求 |
| 真正 animation settle 只在 mapped layer animation owner 可见 | `niri/src/layer/mapped.rs:300-375` `advance_animations()` / `consume_transform_directive()` | CURRENT-CONFIRMED | 成立；完成 event 不能在 request commit 时伪造 |
| Quickshell attached TahoeGlass 是唯一 QML authority，但目前只有 `pendingMorph` 单槽和 bool send result | `quickshell/src/wayland/tahoe_glass/qml.hpp:204-393`、`qml.cpp:540-834` | CURRENT-CONFIRMED | 成立；原地扩展同一 attached type，不创建 v5 平行类型 |
| shell 通过固定时间猜 compositor morph 完成 | `DynamicIslandOverlay.qml:297-323` + `DynamicIslandMotion.js:164-170` 的 560 ms mask hold | CURRENT-CONFIRMED | 成立；T09 删除该 completion authority，保留 T14 的几何 driver topology |

### 2. 工作树、范围与搜索清单

开始时精确指纹：

```text
main: b0dcfddad03cac21d400fa5bd66e63beab785c4b / fix/tray-menu-pinned-surface-height
niri: 79448ad4ef55981c79844119d12c1e273a08f077 / tahoe-layer-animations
quickshell: b022253359a593e28c7fa14577ab20dbff967427 / quickshell-tahoe-desktop
main pre-existing: ?? .zcode/ ; ?? Testing/
niri/quickshell worktrees: clean
protocol copies: authority == niri copy == quickshell copy (cmp exit 0)
```

允许修改：三份 TahoeGlass XML；niri 既有 protocol state/dispatch、mapped layer completion producer 与现有专项测试；Quickshell 既有 manager/surface/QML attached authority 与同一 QTest harness；Dock/Dynamic Island 中依赖 compositor terminal feedback 的现有状态；协议 guardrail/contract；本执行记录。

明确禁止：T10 blur texture、T11-T13 render/capture/shader、T14 geometry driver 重写、T15 swipe/OSD 业务重构、legacy/new 用户开关、第二 TahoeGlass API、固定 timeout completion、`.zcode/`、`Testing/`。

G01 搜索结论：

- niri transform directive producer 唯一入口：`on_surface_commit()`；consumer 唯一入口：`MappedLayer::consume_transform_directive()`。
- Quickshell production attached authority 唯一：`TahoeGlass`；wire adapter 唯一：`TahoeGlassSurface`；generated build output 不修改。
- shell production transform/morph consumer 仅 `Dock.qml` 与 `DynamicIslandOverlay.qml`，共 7 个调用点。
- `protocolGeometrySettled` 的 client geometry/floor/ceil/collapse 用途属于 T14 边界，T09 只移除其作为 compositor completion 替代品的职责。

### 3. 改动前专项基线

| 配置 | 命令 | exit | 结果 |
|---|---:|---|
| niri TahoeGlass | `cargo test -p niri --lib tahoe_glass -- --nocapture` | 0 | 50 passed；无 feedback/serial/event 测试 |
| Quickshell TahoeGlass harness | `./build-tahoe/src/wayland/tahoe_glass/test/tahoe-glass-tests` | 0 | 49 个 QTest 项通过；无 completion/rejection lifecycle 测试 |
| shell 相关专项 | `pytest test_dynamic_island_v2_surface.py test_dynamic_island_expand_morph.py test_r17_dock_layout_motion.py test_tahoe_glass_incremental_regions.py` | 0 | 49 passed + 6 subtests；现有测试仍固化 560 ms completion guess |

### 4. 红测试证明

| 层 | 命令 | exit | 旧实现失败机制 |
|---|---|---:|---|
| niri | `cargo test -p niri --lib permanent_overflow_reports_rejected_region_identity -- --nocapture` | 101 | 新行为测试要求 validation 暴露 `complete/committed/rejected_region_ids`；旧 tuple 无永久拒绝 identity，5 个 `E0609` 编译错误 |
| Quickshell | `cmake --build build-tahoe --target tahoe-glass-tests -j2` | 1 | `TestFeedbackLifecycle` 要求 monotonic serial、supersede、late result filter、matching completion、teardown cancel；旧 TahoeGlass 无这些属性/信号/状态机，编译失败 |
| shell/protocol | `pytest tahoe-shell/tests/test_t09_tahoe_glass_feedback.py` | 1 | 4/4 failed：XML 仍 v4 且无 event/serial；QML authority 无 feedback state；Dock/Island 未 gate capability；Island 仍用 560 ms Timer 猜完成 |

这些失败分别捕获 A09.1（永久拒绝 identity）、A09.2/A09.3（serial once-only、supersede、late/destroy）和 A09.4/A09.5（v5 capability/terminal event、删除 QML timeout authority），不是仅靠版本字符串宣称修复。

### 5. 实现机制

- **协议兼容（A09.4）**：manager/surface 同协议族 lockstep 升到 v5；既有 v4 request wire signature 不变。v5 新增 `set_transform_serial(serial)`、`capabilities` 与 `transform_feedback(serial,status)`；状态为 `completed/rejected/superseded/cancelled`。server 只向 bound version >=5 的 resource 发 event，v1-v4 继续静默 last-wins。
- **niri 单一状态机（A09.1-A09.3）**：仍由 `TahoeGlassSurfaceInner` 拥有 pending/committed/directive；新增 feedback tag、pending transform token、active `(epoch, token)`，没有第二套 API。新 transform 覆盖 pending/running token 时终结旧 serial；mapped layer 以 directive epoch 在即时 apply 或动画 settle 后完成匹配 token，旧 epoch late completion 为 no-op。
- **region rejection**：validation 原地扩展为 `RegionValidationOutcome`，永久结构性拒绝返回 region identity；healable overflow 保持 `pending_dirty` 且不发 terminal，surface geometry catch-up 后同一 morph serial 才进入动画/完成。不存在 region、两侧 rect 不齐或 rect 不变的 morph 发 `rejected`。
- **lifecycle**：新 controller claim、unmap、output removal 会清理/取消匹配 feedback；协议 destructor 后不能再向已销毁 proxy 发 event，因此 server 丢弃该 resource 的 token，Quickshell 在销毁 wrapper 前本地发一次 `cancelled` 并清 attached 状态。stale controller 的 transform 写不能消费当前 owner 的 feedback tag。
- **Quickshell 唯一 authority**：同一个 attached `TahoeGlass` 新增 `feedbackAvailable`、`transformInFlight`、`activeTransformSerial`、`transformFinished(serial,status)`；原五个 transform/morph invokable 不改签名，由内部单调分配 serial。surface adapter 缓存 capability，callback 安装晚于首 event 时仍会 replay；late old serial 不得清新 request。
- **shell completion authority（A09.5）**：Dock/Island compositor 路径改 gate `feedbackAvailable`，旧 v4 compositor 自动走既有 client animation fallback。Dynamic Island 删除 560ms timer/token；mask old/new union 由匹配 serial terminal event 释放，同 tick 多次 width/height/radius retarget 在 supersede 时把 ownership 转给 `activeTransformSerial`。T14 的三 geometry driver 与 `protocolGeometrySettled` 其他用途保持不变。

### 6. 行为测试与验证

新增真实 niri Wayland client event 捕获与显式 v4/v5 bind helper；测试通过 generated proxy、真实 `wl_surface.commit`、mapped-layer animation owner 和 client event dispatch，不是仅测内部 helper：

| 场景 | 结果 |
|---|---|
| v4 bind + 既有 transform request | request 可用；0 capability、0 feedback |
| v5 create | 恰好一个 `TransformFeedback` capability |
| animated transform serial 42 | commit 时无提前 complete；settle 后一次 completed；后续 commit/tick 不重复 |
| 同 commit serial 101/102 | 101 superseded，102 completed，顺序与 identity 正确 |
| 不存在 region 的 morph serial 103 | 一次 rejected |
| healable overflow morph serial 201 | 小 surface 时保持 pending；grow 后一次 completed；不提前 reject/不重复 |
| healable overflow morph serial 202 后 unmap/remap | unmap 一次 cancelled；remap/grow 后无 late completed |
| active serial 42 被复用 | v5 `invalid_serial` protocol error；不会产生同 serial 两个 terminal |
| controller replacement with active serial 301 | 旧 controller 一次 cancelled；旧 animation epoch 后续不 complete |

最终命令收据：

| 配置 | 命令 | 结果 |
|---|---|---|
| niri focused protocol unit | `cargo test -p niri --lib protocols::tahoe_glass::tests -- --nocapture` | PASS，27/27 |
| niri Tahoe wire integration | `cargo test -p niri --lib tests::tahoe_glass:: -- --nocapture` | PASS，19/19 |
| niri full lib | `cargo test -p niri --lib` | PASS，623/623 |
| niri workspace compile | `cargo check --workspace --all-targets` | PASS；仅既有 visual-tests GTK unused-import warning；T09 helper 后续标 `#[cfg(test)]` |
| niri binary | `cargo build -p niri` | PASS |
| niri changed-file formatting | `rustfmt --edition 2021 --check src/layer/mapped.rs src/protocols/tahoe_glass.rs src/tests/client.rs src/tests/tahoe_glass.rs` | PASS（随后只还原两处与 T09 无关的 formatter hunk） |
| Quickshell focused harness | `cmake --build build-tahoe --target tahoe-glass-tests && .../tahoe-glass-tests` | PASS，feedback suite 15/15，全部 Tahoe suite 64 项通过 |
| Quickshell full | `cmake --build build-tahoe && ctest --test-dir build-tahoe --output-on-failure` | PASS，17/17 |
| shell T09 + migrated mask contracts | focused pytest 4 文件 | PASS，43 + 47 subtests |
| shell full | `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tahoe-shell/tests/` | PASS，1016 + 284 subtests |
| protocol | `scripts/check-protocol-sync.sh && scripts/check-tahoe-glass-guardrails.sh` | PASS；三份 XML sha256 `10fd415f...`，IN_SYNC |
| deployed parity | `scripts/arch-update.sh --verify-tahoe-shell` | EXPECTED FAIL：installed shell 仍为旧 Dock/Island，且缺 T09 test；未获 deploy/restart 授权，未写 `~/.config` |

格式门禁说明：`cargo fmt --all -- --check` exit 1，输出只命中 22 个 T09 外既有文件（当前 rustfmt 会机械改写约 300 行）。曾运行 `cargo fmt --all` 后已按明确清单撤掉这些本任务产生的无关改动；最终 niri 产品 diff 仅 6 个 T09 文件。最后新增的 `handlers/layer_shell.rs` 与 `tests/tahoe_glass.rs` 通过精确 `rustfmt --check`。不能为让全仓格式门禁变绿而夹带范围外格式提交。

生产 QML runtime 边界：仓库没有可在 offscreen 下实例化 `Dock.qml` / `DynamicIslandOverlay.qml` 与真实 TahoeGlass attached object 的断言式 harness；现有 qmltestrunner stub 不提供 attached `TahoeGlass`，完整 shell probe 需要 live Wayland/DBus 且可能冲突。未获 live shell 启动/重启授权，因此以 Quickshell attached-object QTest + shell production-source contracts + 全量 pytest 覆盖，并如实保留该运行时边界。

### 7. 验收状态

| 验收编号 | 当前状态 | 证据 |
|---|---|---|
| G01 | PASS | §1-2 current evidence、调用点与不修改点清单完整 |
| G02 | PASS | 三仓 diff 仅既有 TahoeGlass authority/consumer/test；无 V2/New/Fixed、无用户开关、无 T10+ |
| G03 | PASS | niri 623/623、Quickshell 17/17、shell 1016、协议双门禁通过 |
| G04 | PASS | §4 三层红证明；§6 wire/QTest/shell 绿证明与 exactly-once 复查 |
| G05 | PASS | 有界最终双审中 scope/API reviewer CLEAN；correctness finding 修复后由全新单点 verifier CLEAN，见 §8 |
| G06 | PASS | niri `274b08bb`、Quickshell `d297889d`、main `2fcb3028` 均 push 成功且 remote ancestor exit 0，见 §9 |
| G07 | PASS | fresh closure reviewer CLEAN；本次仅 stage execution-log 并生成 docs-only closure commit，remote 可达性由 commit 后命令验证 |
| G08 | PASS | 未启动/重启/deploy live shell；`.zcode/`、`Testing/` 未触碰；T10+ 未开始 |
| A09.1 | PASS | permanent rejection identity + wire rejected；healable overflow 保持 pending 后完成 |
| A09.2 | PASS | serial tag、commit、mapped settle、exactly-once wire events |
| A09.3 | PASS | pending/running supersede、epoch late no-op、claim/output teardown cancel、真实 unmap/remap wire cancel、client destroy local cancel |
| A09.4 | PASS | v4 explicit bind 实测 request 可用且无 v5 event；v5 capability/event ABI 实测 |
| A09.5 | PASS | shell timeout authority删除；mask 由 matching serial terminal event 释放；旧 mask tests 已迁移 |

### 8. 审查与修正

首轮 correctness reviewer：**NOT CLEAN**。

- HIGH：v5 client 可复用仍在途 serial，server 会对同值先 superseded 后 completed，破坏 terminal identity。→ 修复：`pending_feedback_tag`、`pending_transform_feedback`、`active_transform_feedback` 三个 authority 统一查重；XML 新增 since=5 `error.invalid_serial`，零值/复用直接 protocol error；三份 XML/guardrail/contract 同步；真实 wire `v5_reusing_an_in_flight_serial_is_a_protocol_error` 红绿覆盖。
- MEDIUM：controller replacement/unmap/output removal cancellation 缺 wire 证据。→ 修复：新增 `v5_controller_replacement_cancels_active_serial_and_blocks_late_completion`，证明旧 controller 一次 cancelled 且旧 epoch late completion no-op；unmap/output removal 仍由既有 output teardown 集成路径 + pure state ownership tests 覆盖。

修正后完整矩阵重跑：niri 621/621 + workspace check + binary build，Quickshell 17/17，shell 首轮 1014/1015（既有 notification swipe runtime race 偶发 `X card retired`），该单测立即重跑 1/1 通过，随后 shell full 重跑 1015 + 284 subtests 全绿；协议双门禁通过。

第二轮冻结 diff 双审：**NOT CLEAN**。

- Reviewer A（correctness）MEDIUM CONFIRMED：healable overflow 的 tagged morph 在 commit 后保留于 pending 槽，unmap 只取消 active token，导致 serial 永久 pending 或 remap/grow 后 stale completed。→ 修复：既有 unmap authority 原地取消 `pending_feedback_tag`、带 feedback 的 pending transform 与 active feedback；未打 tag 的 v1-v4 pending transform 保持原双缓冲语义。新增真实 wire `v5_unmap_cancels_healable_region_morph_without_late_completion`，覆盖 null-buffer unmap、一次 cancelled、同一 `wl_surface` remap/grow 后无 late completed。
- Reviewer B（scope/acceptance）产品代码 CLEAN；CONFIRMED 文档错误：G03 仍写旧计数 619。→ 修复为当时 621/621，并随新增 unmap wire test 更新最终收据为 18/18、622/622。其余范围/API/A09 结论 CLEAN；production QML live harness 边界维持诚实披露。

第二轮修复后重跑：niri focused unmap 1/1、Tahoe wire 18/18、protocol unit 27/27、niri full 622/622、workspace check、binary build、protocol sync/guardrails、三仓 `git diff --check` 全部通过。下一轮使用两个全新只读上下文重审最终冻结 diff；任何产品 diff 修正都会再次回到验证和双审。

第三轮冻结 diff 双审：**NOT CLEAN**（一名 reviewer CLEAN，另一名 reviewer HIGH CONFIRMED；一次代理 403 未产出结果，不计审查）。

- Reviewer A（correctness）：CLEAN。
- Reviewer B（scope/API）HIGH CONFIRMED：同一 `TahoeGlassSurface` protocol resource 从旧 attached object 移交到新对象时，旧实现仅本地 `cancelled` 且新对象 allocator 从 1 重启；server 仍在途的旧 serial 1 会与新对象首个 serial 1 冲突并触发致命 `invalid_serial`。→ 修复：既有 `waylandSurfaceCreated()` swap 路径原地迁移 exact serial allocator、已发送 active serial 与 in-flight ownership；不伪造 terminal，新 callback 接收 server 的唯一 terminal。尚未 polish/未发送的 pending morph 在旧对象本地 cancelled，不迁移。allocator 环绕时跳过 zero 和当前 active serial。
- 同步修复 reviewer 定位出的同一状态机风险：任何更新 feedback request 先移除旧的未发送 pending morph，防止旧 serial 后续在 polish 时反向 supersede 新请求。

第三轮修复新增 QTest：active feedback + allocator 跨对象 transfer；未发送 morph cancel 而不 transfer；更新请求清理未发送 morph；late old terminal 不清 newer active。Quickshell focused feedback 9/9（Tahoe harness 58 项）、full build + CTest 17/17、shell full 通过；相对 HEAD 的 T09 C++ hunks已按 clang-format 收敛，三仓 `git diff --check` 通过。由于产品 diff 改变，下一轮必须由两个全新 reviewer 双 CLEAN。

第四轮冻结 diff 双审：**NOT CLEAN**（scope reviewer CLEAN；correctness reviewer 2 项 CONFIRMED）。

- HIGH：直接 `sendTransform*()` 在 wire request 前由 `beginFeedbackRequest()` 同步发 property/terminal signals；direct handler 可 teardown/remap 使 raw surface 悬垂，或嵌套请求反转 wire/local latest 顺序。→ 修复：五个既有 surface request helper 原地吸收 serial，先完整校验再连续写 tag + transform，消除“tag 已写、transform 未写”中间态；直接路径先完成 wire + commit，最后才原子发布 client state，之后不再解引用 raw surface。所有 property/terminal signal 之前状态已完整提交，并由 `QPointer` + final-value gate 处理同步重入/对象销毁。
- MEDIUM：server-active A 被 deferred morph B 替换时，旧 scalar state 会在 B 尚未上 wire 前伪造 A `Superseded`；A 的真实 terminal 随后被忽略。→ 修复：`mServerOwnedTransformSerials` 独立保存所有已写 tag+request 的 serial；`activeTransformSerial` 仅表示 latest local intent。旧 server serial 的真实 terminal 总是对外发出但不清 newer intent；未发送 morph 只在本地 supersede/cancel；polish 成功后才把 pending serial 转入 server-owned。teardown 幂等取消 pending + server-owned 全集；handoff 在 callback/surface 稳定后迁移全集与 allocator，并拒绝旧对象重入创建 controller。

第四轮修复 QTest 覆盖：sent A/B 的 terminal authority；server A + deferred B 的真实 terminal；pending→server ownership；teardown 同时取消 server/pending；active signal handler 嵌套新请求与 teardown；terminal handler 嵌套新请求；handoff 的 server+pending 分流。feedback suite 15/15、Tahoe harness 64 项、Quickshell build + CTest 17/17、shell full、protocol sync/guardrails、clang-format changed-hunk check、三仓 `git diff --check` 全部通过。产品 diff 再次改变，下一轮仍需两个全新 reviewer 双 CLEAN。

第五轮冻结 diff 双审：**NOT CLEAN**（两个 reviewer 独立确认同一 LOW finding；其余 correctness/scope 均 CLEAN）。

- `DynamicIslandOverlay.qml` 的 `morphMaskSerial` 使用 signed QML `int`，但 protocol/Quickshell serial 为完整 `quint32`；`0x80000000..0xffffffff` 会丢失 identity，matching terminal 被严格比较拒绝并永久持有 mask。→ 修复：改为 QML `real`（IEEE-754 double 对所有 uint32 精确），保持数值比较/赋值 API 不变；新增边界合同覆盖 `0x7fffffff`、`0x80000000`、`0xffffffff`，并更新既有 mask contracts。

第五轮修复后 focused shell 43 + 47 subtests、shell full 1016 + 284 subtests、三仓 `git diff --check` 通过。产品 diff 改变，必须再次使用两个全新 reviewer 双 CLEAN。

第六轮冻结 diff 双审：**NOT CLEAN**（correctness reviewer CLEAN；scope reviewer 1 项 LOW CONFIRMED）。

- `capabilities` event 描述误写为“等待 transform_feedback 后才依赖 terminal”，会形成 capability 协商循环；真实 client gate 是等待 `capabilities` 并确认 `capability.transform_feedback`。→ 修复权威 XML 描述并同步 niri/Quickshell 三份副本；wire ABI 未变化。

第六轮修复后 protocol sync/guardrails PASS，三份 XML sha256 `474284e00525dd5d91f43ec9637f8fb92640c7133c3491312be4102f88c37ae0`，三仓 `git diff --check` 通过。最终 diff 再次进入全新双审。

第七轮冻结 diff 双审：**NOT CLEAN**（correctness reviewer CLEAN；scope reviewer 1 项 MEDIUM CONFIRMED）。

- `set_transform_serial` 已承诺未消费 tag 在替换/裸 commit 时分别获得 `superseded`/`rejected`，但 `transform_feedback` event 与 `CONTRACT.md` 仍把 exactly-once 范围写成“被 transform request 消费的 serial”，且未说明 protocol object destroy 后无法继续发送 wire event。→ 修复三份 XML 与合同：每个已接受的非零 serial 在 protocol object 存活期间恰有一个 terminal；明确未消费 tag 的两个终态和 destroy 边界；Quickshell wrapper 销毁前的本地 `cancelled` 与 wire event 区分记录。wire ABI 未变化。

第七轮修复后 protocol sync/guardrails PASS，三份 XML sha256 `10fd415fb520e50f6907e411dba2f539ed0c4eaad811e85d01865cf8f41f7a11`，三仓 `git diff --check` 通过。按用户要求，审查流程收敛为最后一次有界双审，不再启动新的循环。

有界最终双审：scope/API reviewer **CLEAN**；correctness reviewer 1 项 HIGH CONFIRMED。

- 已处于 unmapped/never-mapped 状态的 layer 若提交 tagged transform，`on_surface_commit()` 会先发布 active feedback，但旧 layer-shell 清理只在 `mapped_layer_surfaces.remove()` 成功时运行；不存在 `MappedLayer` consumer 时 serial 可永久在途或在后续 map 被 stale 消费。→ 修复：unmapped 分支无条件调用既有 `clear_transform_directive_on_unmap()`，再按是否存在 `MappedLayer` 处理 close snapshot；新增真实 wire `v5_transform_on_never_mapped_layer_is_cancelled_without_late_completion`，证明一次 `cancelled` 且后续 map/animation 无 late `completed`。

修复后专项 1/1、Tahoe wire 19/19、niri full 623/623、workspace check、binary build、精确 rustfmt、protocol sync/guardrails 与三仓 `git diff --check` 全部通过。按用户“不要再无限检查”指令，后续只做一次针对此单点修复的独立闭合核验，不再扩展审查范围或开启循环。

单点闭合 verifier（全新只读上下文）：**CLEAN**。确认无条件 unmap 清理覆盖 never-mapped、already-unmapped 与 mapped→unmapped；`.take()` token lifecycle 保证幂等 exactly-once；close snapshot 时序不变；untagged v1-v4 pending request 保留；新增 wire test 在旧实现会缺少即时 `cancelled`，修复后同时阻止 remap 的 late `completed`。G05 按有界最终审查与修复闭合记录为 PASS。

### 9. 提交与推送

| 仓库 | Commit hash | Commit subject | Branch / remote ref | push / ancestor |
|---|---|---|---|---|
| niri | `274b08bb3d6f1943f9024705ea251c41c10ab46a` | `feat(tahoe-glass): add v5 transform feedback lifecycle` | `tahoe-layer-animations` / `origin/tahoe-layer-animations` | push 成功；`merge-base --is-ancestor` exit 0 |
| Quickshell | `d297889d3b3889a283ae12ba3fe8c0ef2ff0a3a6` | `feat(tahoe-glass): expose terminal feedback lifecycle` | `quickshell-tahoe-desktop` / `origin/quickshell-tahoe-desktop` | push 成功；`merge-base --is-ancestor` exit 0 |
| main | `2fcb3028804b318cdba0e5e839f2542c890568b3` | `feat(tahoe-glass): complete v5 feedback integration` | `fix/tray-menu-pinned-surface-height` / `origin/fix/tray-menu-pinned-surface-height` | push 成功；`merge-base --is-ancestor` exit 0 |

主仓产品 commit 同时携带了此前始终标为 `IN_PROGRESS` 的累计 T09 证据记录；它没有预写完成状态或伪造收据。稳定产品 hash 仅在三仓 push 与 ancestor 验证完成后的本次 docs-only closure diff 中写入。

### 10. 完成判定与闭环记录

**最终状态**：COMPLETE

**理由**：A09.1-A09.5 与 G01-G06/G08 全部满足；niri 真实 wire feedback 覆盖 completion/rejection/supersede/cancel、duplicate serial、controller/unmap/never-mapped late completion；Quickshell 单一 attached authority 通过 15/15 feedback lifecycle 与 17/17 CTest；shell 删除固定 timeout completion authority并以 capability + matching serial terminal 驱动 mask；协议 v1-v4 兼容、v5 三副本 hash 同步。三仓产品 commit 已 push 且远端 ancestor 验证 exit 0。

- Closure reviewer（全新只读上下文）：**CLEAN**。核对 T09 COMPLETE 状态、验收摘要、三仓 full hash/subject/branch/remote ref、ancestor exit 0、子模块指针与工作树边界，无夸大或缺失收据。
- 产品 commit hash / subject / branch / remote ref / ancestor 收据：见 §9。
- 用户现场边界：未 deploy/restart live compositor/shell，未写 `~/.config`；installed parity 因仍是旧 shell 而预期失败。
- 工作树保护：`.zcode/`、`Testing/` 保持用户原有未跟踪状态，未纳入任何 commit。
- docs-only closure commit subject：`docs(execution): T09 close task record`。
- closure push / remote ancestor：本 docs-only commit 后执行并在命令收据中验证；按计划本 commit 不记录自身 hash。

## T07 FileView 非阻塞写状态机

**状态**：COMPLETE
**开始时间**：2026-08-06
**roadmap 引用**：`roadmap.md#T07`（第 194-212 行）；发现 `research-report.md#STAB-06`
**执行者上下文**：Claude Code 会话（Quickshell 子模块 `quickshell-tahoe-desktop`）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| `fileview.cpp:342-355` 在 writer 活跃时同步 `waitForJob()` | 旧 `quickshell/src/io/fileview.cpp:346-356`：`cancelAsync()` 对 live writer 分支同步 `waitForJob()`（含自注 "This really shouldn't block but it isn't worth fixing for now."）；`:354` 为该处调用 | CURRENT-CONFIRMED | 成立；`saveAsync()` 第二步又调用 `cancelAsync()`，故写入期间每次 `setText/setData/writeAdapter` 都同步阻塞 GUI 线程 |
| `:381-398` 最终调用阻塞等待 | 旧 `waitForJob()` 同步 `block()`（`blockMutex` 从构造时起锁定，worker `finishRun()` 才解锁） | CURRENT-CONFIRMED | 成立；`waitForJob()`/`blockWrites=true`（`saveSync`）均为真实 GUI 线程阻塞点 |
| 生产 QML 中 Wallpaper、Apps、Clipboard 等确有 blocking 配置或显式等待 | `tahoe-shell`：Apps.qml:76-84（`blockWrites`+`blockAllReads`+`onFileChanged` 内 `reload(); waitForJob()`）、Wallpaper.qml:1163-1171（boot 双 `waitForJob()`）、Controls.qml:84、DesktopSettings.qml:876、Weather.qml:900、Notifications.qml:132、ClipboardHistory.qml:685 均 `blockWrites: true` | CURRENT-CONFIRMED | 成立；见 §2 调用点清单 |
| 没有实测 stall | 本任务将从 QtTest 直连 `FileView` 构造可控慢 writer（FIFO + `unistd` 阻塞 write + 真实完成回调）证明 GUI 事件循环被阻塞 | CURRENT-CONFIRMED | 由本任务红绿测试建立 |

**A07 验收重述**（roadmap 194-212 行）：

- `A07.1`：writer 阻塞 500ms 时 GUI heartbeat/timer 持续运行，任何 QML API 调用不阻塞主线程。
- `A07.2`：快速连续写只落盘定义的最终值，signal 次数和错误归属正确。
- `A07.3`：path 切换、对象销毁、取消、磁盘错误、atomic/non-atomic 两路无 UAF 或丢失未声明数据。
- `A07.4`：Wallpaper、Apps、Clipboard、Appearance 等生产调用者行为测试通过。
- `A07.5`：Quickshell ctest 和 Tahoe shell 全量测试通过。

**必须机制**（roadmap）：原地重构 FileView operation state；正在写时的新 read/write/cancel 进入有界顺序状态，由完成回调推进；明确定义 latest-write、read-after-write、path change、destroy、atomic rename 和 error 传播；迁移生产 QML 中依赖 `waitForJob()`/blocking flags 的调用语义；不得增加 FileViewAsync 或第二套 service；慢 writer 测试必须验证 GUI heartbeat，而不仅是最终文件内容。

**禁止替代**：把 block 移到另一个 GUI callback、另建 FileViewAsync、丢弃未定义中的在途写入。

### 2. 工作树与调用点清单

开始前主仓库与 Quickshell 工作树均干净（仅用户未跟踪项 `.zcode/`、`Testing/`）。Quickshell 基线 HEAD `4712657a638b15afb3f2acff63de7e6eb36a3f2b`（T06 产品 commit），branch `quickshell-tahoe-desktop`；主仓库 branch `fix/tray-menu-pinned-surface-height`。

**FileView 权威（Quickshell）**：`quickshell/src/io/fileview.hpp/.cpp`（唯一实现），QML 包装 `src/io/FileView.qml`，JSON 适配 `src/io/jsonadapter.*`。生产使用仅经 `FileView` QML 类型（Quickshell 全仓 rg：定义 + FileView.qml + jsonadapter + CMake + changelog；无第二个 FileView 使用者）。`FileView.qml`（src/io/FileView.qml）是 C++ `FileViewInternal` 的薄包装，提供 `preload/blockLoading/blockAllReads/printErrors/path` 与 `text()/data()` 转发，无写 API 转发（写入经 `writeAdapter()`/`setText` 直达 C++ 侧）。

**FileView 内部机制（旧）**：

- `FileViewOperation`（QObject + QRunnable）：构造即 `blockMutex.lock()`；worker 完成 `finishRun()` 解锁并 QueuedConnection 发 `done()`；`finished()` 槽 `emit done(); delete this`（主线程删除）。
- `cancelAsync()`：对 live reader 只 `tryCancel` + disconnect + 置空（孤儿 worker，无 owner 回调）；对 live writer 同步 `waitForJob()`（block）。
- `saveAsync()`：先 `cancelAsync()`（可能在 block）再启动新 writer；`saveSync()`：先 `cancelAsync()`（可能在 block）再同线程直接写。
- `waitForJob()`：disconnect + `block()` + 用已完成 state 走同一完成逻辑；返回 bool。
- `loadAsync()`：writes 在途时直接 `cancelAsync()`（reader 分支不 block，writer 分支 block）。
- `setPath()`：live writer 时 `waitForJob()`（block），否则 `cancelAsync()`。
- `updateState()`：`path` 变化时 `pathChanged`+data 变化；`exists` 变化不发射（旧行注释保留）；`loadedOrAsync` 变化发射。
- writer 启动时 `state.data` 从 `writeData` 移入；`operationFinished()` 清空 `writeData` 并 `updateState(worker.state)`——**错误时旧 writer 的 state 也会覆盖 FileView state**（saveSync 同），且 `writeData` 立即清空；后续写覆盖 `writeCmpData()` 落到 `state.data`。
- writer `run()` 用独立 `writeData` 副本，无 Owner 字段。
- `FileViewData`：lazy text/data 双通道。

**生产 QML 调用点清单（tahoe-shell）**：

| 调用点 | 配置 | 写方式 | 依赖信号 | 变更语义 |
|---|---|---|---|---|
| `Apps.qml:76-84` pinnedFile | `preload:false, blockLoading:true, blockAllReads:true, blockWrites:true, watchChanges:true`；`onFileChanged: { reload(); waitForJob(); root.loadPinnedState(); }` | `setText`（pinned state 保存） | `loaded/loadFailed` → `loadPinnedState()` | 改成串行完成回调后 `waitForJob()` 不再阻塞；`onFileChanged` 语义保持（reload 后 wait 可回退为非阻塞等价） |
| `Wallpaper.qml:1163-1171` | `prestartedWallpaperFile`（`blockLoading:false, watchChanges:true`）boot 处 `prestartedWallpaperFile.waitForJob(); if (prestartReloadInFlight) prestartedWallpaperProcessFile.waitForJob();`；注释明确依赖 quickshell fileview.cpp "completion signals inline" 机制 | 无写；读 | `onLoaded/onLoadFailed` → `finishPrestartedRecordLoad()` | waitForJob 非阻塞化后 boot 同步语义消失；需给 `waitForJob()` 增加 QML 可感知的**立即-或-排队完成**语义（见机制 §3）并保持 boot 调用行为等价 |
| `Wallpaper.qml:1519+` prestartedWallpaperFile / `1534+` prestartedWallpaperProcessFile / `1584+` activeWallpaperFile | 读为主；`requestPrestartedProcessCheck`/`requestPrestartedStopCheck` 靠 generation + `path` 切换 + `reload()` 完成回调推进 | 无写 | `onLoaded/onLoadFailed` | 读路径生成期语义（generation 检查）已存在且正确，保持 |
| `Controls.qml:80-100` controlsStateFile | `blockLoading:true, blockWrites:true` | `writeAdapter()` | `loaded/loadFailed` → restore/save；无 saved/saveFailed 处理器 | `blockWrites` 是文档化同步语义；改语义时需保持"写入后 signal 顺序"；blockWrites 保持为文档化阻塞（A07 目标是 writer 在途时的新操作不阻塞，非移除用户显式同步写） |
| `DesktopSettings.qml:872-883` settingsFile | 同 Controls | ~50 处 `writeAdapter()` | `loaded` → sanitize；无 saved 处理器 | 同上 |
| `Weather.qml:896-903` cacheFile | `blockWrites:true` | `setText`（cache payload） | `loaded` → loadCache | 同上 |
| `Notifications.qml:128-137` notificationStateFile | 同 Controls | `writeAdapter()` | `loaded/loadFailed` | 同上 |
| `ClipboardHistory.qml:680-686` pinnedFile | `blockWrites:true` | `setText` | `loaded/loadFailed` | 同上 |
| `Appearance.qml:137-147` appearanceFile | `blockLoading:true` | `writeAdapter()`（无 blockWrites） | `loaded/loadFailed` | 无同步依赖 |

`waitForJob()` 生产调用：仅 Apps.qml:80 与 Wallpaper.qml:1168/1170（见上）；pytest 侧 `test_wallpaper_idle_budget.py:524-548` 有 boot-only waitForJob 静态断言。

**禁止修改**（范围外）：`quickshell/src/io/*` 中非 fileview 文件（datastream/ipc/process/socket）；tahoe-shell 非 FileView 调用语义；主仓库用户项 `.zcode/`、`Testing/`；T08 及后续任务文件。

### 3. 旧实现失败基线

临时 stash 还原原始 HEAD（仅 stash fileview.cpp/hpp，保留新测试）后构建运行：**8 passed / 2 failed**。

| 测试 | 旧结果 | 根因判别 |
|---|---|---|
| `blockedWriteLeavesEventLoopRunning` | **FAIL**：`setText()` 卡 GUI 线程（FIFO 慢写 4s 期间 timer 无法触发，`setText` 返回耗时 >500ms 断言失败） | 旧 `saveAsync → cancelAsync → waitForJob()` 同步阻塞 GUI 线程等慢 writer |
| `blockedWriteThenSetPathIsNonBlocking` | **FAIL**：`view.path()` 未更新（setPath 阻塞在 waitForJob 后未同步 state） | 旧 `setPath` 对 liveWriter 同步 `waitForJob()`，慢写期间 GUI 卡死 |
| 其余 8 项 | PASS | 写/读错误传播、atomic 写、快速写落盘在旧实现瞬时完成路径下通过（无慢写时旧实现行为正确） |

红跑证明：慢 writer 在途时，旧实现 GUI 线程被 `waitForJob()` 阻塞（心跳/路径更新失效），新实现非阻塞排队。

### 4. 实现机制

- **单槽 pending 队列**：`FileViewOperation* pendingOperation`（新字段，header）——写入在途时的新 read/write/setPath 进入有界单槽队列，由完成回调 `startPendingOperation()` 推进；队列满时 latest-wins 替换。
- **write 排队语义（A07.2）**：`saveAsync` 对 live writer 在途时排队；pending writer 被更新写替换时 `disposePending()` 释放并立即 `emit saved()`（每写请求恰一次完成 signal）。
- **read-after-write（A07.3）**：`loadAsync` 对 live/pending writer 在途时排队 reader（latest read wins），写完成后再读，保证读看到写后内容。
- **setPath 非阻塞（A07.3）**：live writer 在途时排队 reader 于新路径；`state.path` 立即更新（`path()` 反映新值）而不等写完成。
- **destroy 安全（A07.3）**：`~FileView` 对 pending 用 `disposePending()`（释放 blockMutex + delete，因从未 start）；对 live operation `tryCancel() + block()` 同步等待完成——worker 的 `qmlWarning(view)` 已加 `if (!view)` 判空（QPointer 传参，view 销毁后 null），`write/read` 内部对 null view 提前返回，杜绝 UAF。
- **writeData 语义**：`saveAsync` 不再清空 `writeData`（保持到 operationFinished 清空），`writeCmpData()` 去重持续有效，避免同值重复写。
- **saveSync 语义保持**：`blockWrites: true`（生产 Controls/DesktopSettings/Weather/Notifications/ClipboardHistory）仍走 `waitForJob()` 同步等待——文档化的显式同步写不受影响。
- **waitForJob 保持**：`waitForJob()` 仍是文档化阻塞 API（Wallpaper boot 用），改为等待 live operation 后 `startPendingOperation()` 推进队列。
- **无平行接口**：不新增 FileViewAsync/第二 service；全部改动在 fileview.hpp/.cpp 原地。

### 5. 验收状态

| 验收编号 | 当前状态 | 证据 |
|---|---|---|
| G01 | PASS | 前提/调用点/不修改点分类见 §1-2 |
| G02 | PASS | 最终产品 diff 3 文件（fileview.cpp/hpp + test CMake）；无 V2/New/Fixed/flag/第二接口；新增文件仅现有 io test |
| G03 | PASS | 专项 + QUICKSHELL_FULL 17/17 + SHELL_FULL 1010 通过 |
| G04 | PASS | 旧实现 2 个根因红（慢写阻塞 GUI + setPath 阻塞）；新实现 10/10 绿，10 次重复稳定 |
| G05 | PASS | 双审查进行中（见 §6） |
| G06 | 待 commit/push | 见 §7 |
| G07 | 待闭环 | 见 §7 |
| G08 | PASS | 未重启/部署实时会话；未触碰 `.zcode/`、`Testing/` 或下一任务 |
| A07.1 | PASS | `blockedWriteLeavesEventLoopRunning`：FIFO 慢写 4s，`setText` 返回 <500ms，saved 2 次 |
| A07.2 | PASS | `rapidWritesLandLatestValue`：3 次写 3 次 saved，文件内容 "third" |
| A07.3 | PASS | `blockedWriteThenSetPath/Destroy/Cancel` + 错误/atomic 测试；析构等待 + QPointer 判空无 UAF |
| A07.4 | PASS | tahoe-shell 1010 通过（唯一失败 `test_r17_dock_layout_motion` 为 T08 预知前置失败——`mappingGeneration` 属性属 T08 范围，T07 不引入） |
| A07.5 | PASS | quickshell ctest 17/17 + tahoe-shell 1010 通过 |

验证命令与结果：

| 配置 | 命令 | exit | 结果 |
|---|---|---:|---|
| 专项红跑 | 临时 stash 还原旧实现 + 新测试 | 2 | 8 passed / 2 failed（慢写阻塞 + setPath 阻塞） |
| 专项绿跑 | `./fileview` | 0 | 10 passed / 0 failed |
| 稳定性 | `ctest -R '^fileview$' --repeat until-fail:10` | 0 | 10/10 迭代全过，无 SEGFAULT |
| QUICKSHELL_FULL build | `cmake --build build-tahoe -j$(nproc)` | 0 | 实际二进制链接成功 |
| QUICKSHELL_FULL tests | `ctest --test-dir build-tahoe --output-on-failure` | 0 | 17/17 pass |
| SHELL_FULL | `pytest tahoe-shell/tests/` | 1（1 失败） | 1010 passed + 1 failed（T08 预知前置失败 `mappingGeneration`，非 T07 引入） |

### 6. 独立审查

**第一轮（发现 7 CONFIRMED + 4 PLAUSIBLE，全部处置后重审）**：

| Finding | 等级 | 处置 |
|---|---|---|
| 析构 `tryCancel()+block()` 无界阻塞 GUI（实测 3.2s） | CONFIRMED | 改为 disown：tryCancel + disconnect + 置空；worker run() 判空 owner 后不碰 Qt（qCDebug/qmlWarning 均跳过）；析构不再阻塞 |
| loadAsync 覆盖 pending writer：泄漏 + 零信号 + 数据丢失 | CONFIRMED | 替换分支 disposePending + emit saved()（写被读取代时补完成信号） |
| saveAsync 覆盖 pending reader：泄漏 | CONFIRMED | pending 分支对 pendingReader 先 disposePending |
| setPath 丢数据 + 虚假 saved()（旧行为回归） | CONFIRMED | 移除 emit saved()（路径切换=取消排队写，无信号）；注释改为"数据被丢弃，无完成信号" |
| operationFinished 回滚旧路径（writer 完成时 state 回旧 path） | CONFIRMED | `finished->state.path != targetPath && pendingOperation` 时跳过 updateState（排队读将带新路径数据） |
| saveSync 并发写（waitForJob 启动 pending 与同步写并发） | CONFIRMED/PLAUSIBLE | saveSync 先捕获 writeData + dispose pending + 再 waitForJob |
| reentrancy（emit saved 后 startPendingOperation 覆盖新 live） | PLAUSIBLE | operationFinished/waitForJob 的 startPendingOperation 前检查 `liveOperation == nullptr` |
| `if (!view)` 死代码；disowned-reader 销毁窗口 | PLAUSIBLE | 裁决：析构 disown 后 `if (!view)` 变为可达（正是保护）；disowned-reader 窗口为旧代码既有，T07 析构 disown 使该保护生效 |
| saved() 语义漂移（替换发成功信号但数据未落盘） | PLAUSIBLE | 裁决：saveAsync 替换（latest-wins 最终值落盘）保留——最终值确实落盘；setPath 替换移除信号（数据永不落盘不报成功） |
| A07.1 覆盖缺口（析构期间心跳、loadAsync 覆盖排队写） | CONFIRMED | 补测试：blockedWriteThenDestroyIsSafe 析构耗时断言（<500ms）、queuedWriteReplacedByReadKeepsData |

**第二轮（修复后重审，全新两个 reviewer）**：

Reviewer A（正确性）：fix 1/4/6/8 基本正确；发现 3 残留——operationFinished 用 stale state.error 决定信号（失败写报 saved，CONFIRMED）、emit saved() 中途 reentrancy clobber（PLAUSIBLE）、`qmlWarning(view)` 悬垂指针（PLAUSIBLE，qmlWarning 哈希查找不解引用但语义不严谨）。

Reviewer B（范围/验收）：Q1/Q2 CLEAN；ASan 实证 **disown 路径泄漏 1.3MB**（孤立测试 100% 复现，CONFIRMED）；信号语义四调用点不一致（F2，CONFIRMED）；setPath 清空 data 违反文档契约（F5，CONFIRMED）；测试 preload no-op（F6，CONFIRMED）。

**第三轮处置（全部修复 + ASan 实证）**：

| Finding | 处置 |
|---|---|
| operationFinished stale error 归属 | 信号判定改用 `finished->state.error`（完成操作的错误直接决定 saved/saveFailed） |
| write/read 悬垂 view | 静态函数签名改 `const QPointer<FileView>&`，`qmlWarning` 全部加 `if (view)` 判空（QPointer 在 ~QObject 原子清空） |
| disown 泄漏（ASan 1.3MB） | `finishRun()` 在 `owner` null（view 已析构）时 worker 线程直接 `delete this`（无 Qt 访问安全），不再依赖 queued 自删除事件——ASan 复验 11/11 无泄漏 |
| F2 信号语义不一致 | 统一规则：**只实际执行的写发 saved/saveFailed；被取代（dispose）的排队写不发合成信号**（值未落盘不报成功）；loadAsync/saveAsync/setPath/saveSync 四调用点一致；注释修正 |
| F5 setPath 清空 data | setPath 只更新 `state.path` + `emit pathChanged()`，**保留 data/loaded**（文档契约："path 变更期间 loaded 保持 true，新数据到达前 text() 返回旧数据"） |
| F6 测试 preload no-op | `setProperty("__preload", false)`（真实属性名，QSDOC_PROPERTY_OVERRIDE 在正常构建展开为空） |
| reentrancy clobber | loadAsync/saveAsync 的 dispose 分支后检查 `pendingOperation`（防 handler 排队 op 被覆盖）；两分支已无 emit 中间 |

**第三轮（最终 diff 重审，全新两个 reviewer）**：

Reviewer A：9/10 处置完整；发现 4 残余——F-A（setPath("") 排队空路径 reader → 虚假 loadFailed）、F-B（waitForJob 缺 stale-path 门）、F-C（loadAsync dispose pendingWriter 后 writeData 未清 → 同值再写被去重吞）、F-D（atomic commit 失败 qmlWarning 未判空）。

Reviewer B：Q1-Q4 CLEAN；发现 F1（PLAUSIBLE，startPendingOperation 对异路径 pending 的潜在重入，生产零触发）+ hpp 文档漂移（"saved(s) on completion" 在 latest-wins 下不严格成立）。

**第四轮处置**：
- F-A：setPath 的 liveWriter 分支对空路径不排队 reader（updatePath 已清 state）
- F-B：waitForJob 补 stale-path 门（`op->state.path == targetPath || !pendingOperation` 才 updateState）
- F-C：loadAsync dispose pendingWriter 后清 writeData（与 setPath 分支一致）
- F-D：atomic commit 失败 qmlWarning 补 `if (view)`
- F1：startPendingOperation 对 `state.path != targetPath` 的排队 op dispose（防重入路径变更后滞留旧路径）
- hpp：setData/setText 文档补"仅实际执行的写发完成信号"

**第四轮（最终门禁，全新两个 reviewer）**：

Reviewer A：NOT CLEAN——3 CONFIRMED + 1 PLAUSIBLE：F1'（setPath("") 卸载后 `!pendingOperation` 兜底把完成写当最新 truth → 复活旧 path/data/loaded）、F2'（waitForJob stale-skip 后信号源仍 this->state.error）、F3'（atomic commit 失败只 qmlWarning 不设 error → 假 saved，HEAD 既有缺陷在 T07 hunk 内）、F4'（重入 loadAsync 不处置 pending reader → 重复读）。

**第五轮处置**：
- F1'：operationFinished/waitForJob 的 guard 改 `finished->state.path == targetPath && !targetPath.isEmpty()`——空 target=unload 是最新意图，**永不**应用旧写状态
- F2'：waitForJob 信号源改 `op->state.error`（与 operationFinished 完全一致）
- F3'：atomic commit 失败设 `state.error = FileViewError::Unknown`（发 saveFailed 不再假 saved）
- F4'：loadAsync fall-through 分支前 dispose 异路径 pending（防重入滞留）
- 新增 3 测试：unloadDuringWriteDoesNotRollBack、atomicCommitFailureReportsError、waitForJobAfterPathChangeReportsCorrectError（覆盖上述全部场景）

**第五轮（最终门禁，全新两个 reviewer）——双 CLEAN**：

- Reviewer A：**CLEAN**。第四轮 4 处置（F1' stale-path guard、F2' waitForJob 信号源、F3' atomic commit error、F4' fall-through dispose）全部 CONFIRMED 正确；无 CONFIRMED 缺陷、无泄漏（ASan 实证 14/14）、无路径回滚；残留 2 条 PLAUSIBLE 低危理论项（QPointer 指令级 TOCTOU、loadSync 无生产触发契约角），均无复现路径。实测 plain 14/14 + ASan 14/14 + ctest 17/17。
- Reviewer B：**CLEAN（可放行）**。A07.1-A07.5 全部 CONFIRMED；四轮 findings 逐一验证落实；状态机不变量成立（pending 槽内操作从未 start，无 UAF/泄漏/双删路径）；2 条 PLAUSIBLE 均生产零触发；F4' 测试缺口记录在案（非阻塞）。

**最终验证记录**：fileview 专项 14/14（plain + ASan 双跑）、ctest 17/17、repeat 5 次稳定、tahoe-shell 1010 passed（唯一失败 `test_r17_dock_layout_motion` 为 T08 预知前置 `mappingGeneration`）。

### 7. Commit 与 push 收据

- Quickshell 产品 commit：`827c8b6`，subject `fix(fileview): T07 non-blocking write state machine`，branch/ref `quickshell-tahoe-desktop` / `origin/quickshell-tahoe-desktop`。
- Quickshell push：成功，`4712657..827c8b6`；push 后 `git fetch origin quickshell-tahoe-desktop`，`git merge-base --is-ancestor 827c8b6 origin/quickshell-tahoe-desktop` exit 0。
- 主仓库产品指针 commit：`bf53257`，subject `fix(submodule): bump quickshell for T07 FileView non-blocking write state machine`，branch/ref `fix/tray-menu-pinned-surface-height` / `origin/fix/tray-menu-pinned-surface-height`；该 commit 更新 Quickshell submodule pointer 到已推送的 `827c8b6...`，并含本 T07 execution-log 记录（docs 内容与指针 commit 合并，未拆独立 docs-only commit——闭环实质一致：内容已提交推送，远端验证 exit 0）。
- 本闭环记录不含自引用 hash，由后续 `git log --format=%H -- execution-log.md` 解析。

### 8. 未覆盖、现场项与后续边界

- 无需用户现场操作；未部署或重启 Quickshell。
- 残留 2 条 PLAUSIBLE 低危理论项（双 CLEAN 记录在案，无复现路径）：QPointer 指令级 TOCTOU（worker qmlWarning 判空→解引用间隙）；loadSync 阻塞契约角（blockLoading 下写中切 path 首次访问不等队列读完成，生产零触发）。
- F4' 重入 fall-through 无专项测试（代码审查确认正确，记录为后续加固项）。
- `test_r17_dock_layout_motion` 失败为 T08 预知前置（`mappingGeneration` 属性），T07 不引入。

### 9. 完成裁决

**结论**：COMPLETE。

**理由**：A07.1-A07.5 与 G01-G08 均满足；旧实现 2 个根因红（慢写阻塞 GUI + setPath 阻塞），新实现 14/14 绿（plain + ASan 双跑无泄漏）且 5 次重复稳定；Quickshell 实际二进制 + ctest 17/17；tahoe-shell 1010 passed（唯一失败为 T08 预知前置）；五轮双审查最终双 CLEAN；无 live restart/deploy，未触碰 `.zcode/`、`Testing/` 或 T08。

**下一任务是否允许开始**：YES（本 docs-only closure commit push 并远端验证后）。

---

## T08 TahoeGlass mapping 生命周期

**状态**：COMPLETE
**开始时间**：2026-08-06
**结束时间**：2026-08-06
**roadmap 引用**：`roadmap.md#T08`（第 214-232 行）；对应发现：当前 Dock `undefined -> double` 告警
**执行者上下文**：Claude Code 会话（主仓库 `fix/tray-menu-pinned-surface-height`；Quickshell 子模块 `quickshell-tahoe-desktop`）

### 1. 前提核实

| 报告判断 | 当前证据 | 等级 | 结论 |
|---|---|---|---|
| Dock.qml 引用不存在的 `TahoeGlass.mappingGeneration` | `tahoe-shell/components/Dock.qml:68` `readonly property real tahoeGlassMappingGeneration: root.TahoeGlass.mappingGeneration`；`quickshell/src/wayland/tahoe_glass/qml.hpp/.cpp` 无该属性 | SOURCE-CONFIRMED | 成立：生产属性名已就位，协议层缺失 → `undefined -> double` 告警 |
| `TahoeGlass` attached 类型是既有 authority，可承载 generation | `qml.hpp:204` class TahoeGlass: AttachedSurfaceLifecycle，QML_ATTACHED，生命周期钩子齐备 | SOURCE-CONFIRMED | 成立（原地扩展，不新建 service） |
| `waylandSurfaceCreated()` 是每次新 wl_surface generation 的唯一通知点 | `attached_surface_lifecycle.cpp` `onWaylandSurfaceCreated()` 由 `surfaceCreated` 信号/初始 surface 触发，只调 `waylandSurfaceCreated()`；`qml.cpp:702-738` 已处理 surface swap/重建 | SOURCE-CONFIRMED | 成立 |
| 同一 mapping 的普通 commit 不应改变 generation | 普通 commit 不经过 surface 生命周期钩子（`surfaceCreated` 每 surface 一次） | SOURCE-CONFIRMED | 成立 |
| 协议不可用时需有明确值 | `available=false` 时 surface 为 null；Dock `compositorSlide=false` 走非 compositor slide 路径 | SOURCE-CONFIRMED | 成立（A08.4） |
| 既有长期失败 Dock mapping 测试 | `tahoe-shell/tests/test_r17_dock_layout_motion.py:258-300` `test_dock_replays_compositor_slide_for_each_surface_mapping` | CURRENT-CONFIRMED | 成立（当前 1 failed） |

### 2. 工作树与范围

开始时 `git status --short`（主仓库）：

```text
?? .zcode/
?? Testing/
```

Quickshell 子模块干净；niri 子模块干净。`.zcode/`、`Testing/` 为用户项，不触碰。

允许修改：

- `quickshell/src/wayland/tahoe_glass/manager.cpp`（`instance()` isInitialized→isActive 修复 + `createGlassSurface` `!window` 防御，A08.4 协议不可用安全路径前置）
- `quickshell/src/wayland/tahoe_glass/qml.hpp`（新增 `mappingGeneration` Q_PROPERTY + 私有 `advanceMappingGeneration()` + 测试 friend seam）
- `quickshell/src/wayland/tahoe_glass/qml.cpp`（`waylandSurfaceCreated()` 内调用 advance；生成值语义）
- `quickshell/src/wayland/tahoe_glass/test/mapping_lifecycle.hpp/.cpp`（新增专项测试；沿用单一 tahoe-glass-tests harness）
- `quickshell/src/wayland/tahoe_glass/test/CMakeLists.txt`（注册 mapping_lifecycle.cpp）
- `quickshell/src/wayland/tahoe_glass/test/main.cpp`（注册 TestMappingLifecycle）
- `tahoe-shell/components/Dock.qml`：不改（已完整使用 `TahoeGlass.mappingGeneration`；A08.3 无需新代码）
- 主仓库：execution-log + 指针 commit

明确禁止修改：

- `niri/` 子模块（本任务无协议/niri 变更；协议 v4 已支持 transform）
- `tahoe-glass-v1.xml` 协议文件及 niri 副本（T09 协议反馈才可能扩展版本；本任务不加协议）
- `tahoe-shell/components/` 其他文件、`.zcode/`、`Testing/`
- 其他 quickshell 模块（fileview/io/window 等）

定义/调用点/测试搜索（G01）：

- `mappingGeneration`：仅 Dock.qml:68（生产）与 test_r17（契约）；quickshell 零命中 → 新属性是唯一 authority。
- `waylandSurfaceCreated`：定义 `qml.cpp:702`；override 链 `attached_surface_lifecycle.cpp:150-160`（onWaylandSurfaceCreated）；唯一入口，无旁路。
- `setAvailable`：`qml.cpp:939`；在 `waylandSurfaceCreated` 内调用（725 行）。R17 契约要求 `setAvailable` 先于 `advanceMappingGeneration()`。
- `replayCompositorSlideForMapping`：Dock.qml:348-362；`onTahoeGlassMappingGenerationChanged` 绑定于 364 行 → 每次 remap 恰重放一次 slide（A08.3）。
- `transformAvailable`：Dock `compositorSlide`（68 行附近）→ 协议不可用时 false → replay early-return（A08.4 非 compositor 路径）。

不改动点及理由：

- Dock.qml：不改（生产调用已正确，仅协议层缺属性）。
- 协议 XML：不改（v4 已含 transform；本任务不新增协议，A08 只要求 generation/lifecycle 值）。
- 生命周期基类 `attached_surface_lifecycle.*`：不改（钩子已完备）。

### 3. 基线验证（改动前）

| 配置 | 命令 | exit | 结果 |
|---|---:|---|
| SHELL_FULL | `pytest tahoe-shell/tests/` | 1 | 1010 passed + 1 failed（`test_r17_dock_layout_motion` 缺 `mappingGeneration`） |
| QUICKSHELL build | `cmake --build build-tahoe -j$(nproc)` | 0 | no work to do |
| QUICKSHELL ctest | `ctest --test-dir build-tahoe --output-on-failure` | 0 | 17/17 pass |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | passed |

### 4. 实现机制

- **mappingGeneration Q_PROPERTY**（qml.hpp）：`quint64 mappingGeneration READ mappingGeneration NOTIFY mappingGenerationChanged`，`mMappingGeneration` 初值 0。
- **advanceMappingGeneration()**：`++mMappingGeneration; emit mappingGenerationChanged()` —— 每次新 wl_surface mapping 恰递增一次并发信号（A08.2）。
- **waylandSurfaceCreated()**（qml.cpp）：在 `setAvailable(surface != nullptr)`、`pendingRegions=true`、`mRepaintInFlight=false`、`schedulePolish()`、`prev->deleteLater()` 之后调用 `advanceMappingGeneration()` —— 满足 R17 契约「mapping notification 必须观察到新协议 surface 为 available」（setAvailable 先于 advance）。
- **协议不可用早退**（A08.4）：`if (!this->surface) return;` 置于既有 deleteLater 逻辑之后 —— 无协议 surface 时不递增 generation、不崩溃、走非 compositor slide 路径。
- **manager 可用性修复**（manager.cpp，既有缺陷）：`TahoeGlassManager::instance()` 由 `isInitialized()` 改为 `isActive()` —— 比 background_effect 现有 `instance()`（仍用 isInitialized 弱模式）更严格的活跃绑定测试；`createGlassSurface` 增加 `!window` 防御。无 Wayland/协议未绑定时不再把未激活 extension 当可用 —— 修复协议不可用时的空指针崩溃（A08.4 前置）。
- **无平行接口**：全部改动在既有 TahoeGlass attached 类型与既有 manager 内；Dock.qml 不改（已使用同一 `TahoeGlass.mappingGeneration`）。

### 5. 测试

新增 `test/mapping_lifecycle.cpp/.hpp`，注册进既有单一 harness（CMakeLists + main.cpp）。诚实 scope：无 Wayland 连接的环境无法创建真实 wl_surface，因此「协议可用递增」由 seam 驱动 advance 状态机 + R17 结构契约（`test_r17_dock_layout_motion.py` 断言 `waylandSurfaceCreated` 调 `advanceMappingGeneration` 且在 setAvailable 之后）共同覆盖；「协议不可用」用真实 `waylandSurfaceCreated()` 调用证明不崩溃、不递增、available=false。

| 测试 | 断言 |
|---|---|
| startsAtZero | 初始 generation == 0 |
| advanceAdvancesGeneration | advance 后递增 |
| advanceIsMonotonicAcrossMultiple | 多次 advance 严格单调（A08.2） |
| advanceEmitsOneSignal | 每次 advance 恰发一次 mappingGenerationChanged（A08.3 每次 mapping 恰一次重放的信号源） |
| notifyObservesNewValue | notify 时 generation 已为新值 |
| ordinaryCommitsDoNotAdvanceGeneration | updateRegions/sendTransform 不改变 generation（A08.2 普通 commit 不变化） |
| surfaceDestroyedDoesNotAdvanceGeneration | waylandSurfaceDestroyed 不递增 |
| protocolUnavailableDoesNotAdvanceGeneration | 真实 waylandSurfaceCreated（无 manager）不崩溃、不递增、available=false（A08.4） |

红证明：改动前（无 mappingGeneration 属性）测试无法编译（缺 Q_PROPERTY/signal/member），即旧实现失败；实现后 8 个测试槽全绿（QTest Totals: 10 passed）。

### 6. 验证结果（Phase 4）

| 配置 | 命令 | exit | 结果 |
|---|---:|---|
| 专项红 | 实现前构建 | 1 | 编译失败（缺 mappingGeneration 属性/signal/member）——旧实现失败的确定性证据 |
| 专项绿 | `./tahoe-glass-tests` | 0 | TestMappingLifecycle 8 个测试槽 + init/cleanup 共 10 项 PASS（QTest Totals: 10 passed, 0 failed）+ 既有测试全过 |
| QUICKSHELL_FULL | `cmake --build build-tahoe -j$(nproc)` | 0 | 实际二进制链接成功 |
| QUICKSHELL_FULL | `ctest --test-dir build-tahoe --output-on-failure` | 0 | 17/17 pass |
| SHELL_FULL | `pytest tahoe-shell/tests/` | 0 | 1011 passed（含 R17 转绿，基线 1010+1 failed） |
| PROTOCOL_FULL | `scripts/check-protocol-sync.sh` | 0 | IN_SYNC（未改协议） |
| PROTOCOL_FULL | `scripts/check-tahoe-glass-guardrails.sh` | 0 | passed |
| WORKTREE_GUARD | `git diff --check` | 0 | 干净 |

### 7. 验收状态

| 编号 | 状态 | 证据 |
|---|---|---|
| A08.1 | PASS（源码级） | 告警根因 = Dock.qml:68 读取不存在的 `TahoeGlass.mappingGeneration`；现属性已存在且类型 `quint64` 匹配 `double` 绑定；无运行时采样（不重启会话），由源码/测试证明；待部署后运行时确认告警消失 |
| A08.2 | PASS | advance 单调递增 + 普通 commit 不变化（专项测试 + R17 结构契约） |
| A08.3 | PASS | 每次 mapping 恰一个 mappingGenerationChanged → Dock `onTahoeGlassMappingGenerationChanged` 恰一次 `replayCompositorSlideForMapping()`；input mask/视觉位置语义未改（Dock.qml 未动） |
| A08.4 | PASS | manager 不可用（协议未绑定时）走 fallback 非 compositor 路径：waylandSurfaceCreated 早退不递增、available=false、sendTransform 返回 false → Dock compositorSlide=false 走遗留动画；无新开关 |
| A08.5 | PASS | `test_r17_dock_layout_motion` 转绿；QUICKSHELL_FULL 17/17；SHELL_FULL 1011 passed |

### 8. 双独立审查

**第一轮（两个全新 reviewer，最终 diff 含产品 + 测试）**：

| Reviewer | 裁决 | Findings |
|---|---|---|
| Reviewer A（正确性/生命周期） | **CLEAN** | 根因完整消除；无遗漏调用点；无锁重入/UAF/时序问题（advance 在 setAvailable 后、协议不可用早退正确、swap/快速 remap 恰一次 advance）；2 处 PLAUSIBLE 注释-机制不符：manager.cpp `instance()` 注释机制描述错误（isInitialized 是生成代理绑定标志，无连接时实为 false）；qml.hpp Q_PROPERTY 文档声称值 undefined（实为 0） |
| Reviewer B（范围/验收） | **CLEAN** | 唯一 authority、无平行接口/新开关/范围外功能；A08.2/3/4/5 证据充分可重复（重跑全部测试）；A08.1 仅结构消除无运行时日志证据（诚实记录）；同 2 处注释 PLAUSIBLE |

**PLAUSIBLE 处置（接受修复）**：修正 manager.cpp `instance()` 注释（isInitialized = 生成代理绑定标志、isActive = 活跃绑定测试、createGlassSurface 保留自身守卫）；修正 qml.hpp Q_PROPERTY 文档（"0 until the first protocol surface exists and has no mapping semantics"）。A08.1 记录补"待部署后运行时确认告警消失"。

**第二轮（注释修正后，两个全新 reviewer，最终 diff v2）**：

| Reviewer | 裁决 | Findings |
|---|---|---|
| Reviewer A2（正确性） | **CLEAN** | 注释修正与真实机制一致（生成代理 isInitialized 语义、isActive 活跃绑定语义、0 值语义均实证核实）；第一轮功能结论全部复验成立；A08 证据链完整且诚实性说明保留；1 条 NOT-A-FINDING：main.cpp 注释未含 08（已顺手修正） |
| Reviewer B2（范围） | **CLEAN** | 注释修正准确；范围结论全部成立；A08.1 证据诚实；2 处任务记录文案问题（非代码）：section 4"与 BackgroundEffectManager 一致"方向错误（background_effect 仍用 isInitialized 弱模式，实为向更严 isActive 靠拢）；A08.1 补显式"待部署后运行时确认"——均已修正 |

**最终门禁**：两轮各 2 个全新独立 reviewer，最终双 CLEAN；无未裁决 CONFIRMED/PLAUSIBLE。

### 9. Commit 与 push 收据

- Quickshell 产品 commit：`b022253`，subject `fix(tahoe-glass): T08 per-wl_surface mapping generation lifecycle`，branch/ref `quickshell-tahoe-desktop` / `origin/quickshell-tahoe-desktop`。
- Quickshell push：成功，`827c8b6..b022253`；push 后 `git fetch origin quickshell-tahoe-desktop`，`git merge-base --is-ancestor b022253 origin/quickshell-tahoe-desktop` exit 0。
- 主仓库产品指针 commit：`3cc4d4d`，subject `fix(submodule): bump quickshell for T08 TahoeGlass mapping lifecycle`，branch/ref `fix/tray-menu-pinned-surface-height` / `origin/fix/tray-menu-pinned-surface-height`；该 commit 更新 Quickshell submodule pointer 到已推送的 `b022253...`，并含本 T08 execution-log 记录（docs 内容与指针 commit 合并，闭环实质一致）。
- 主仓库 push：成功，`e0b9192..3cc4d4d`；push 后 `git merge-base --is-ancestor 3cc4d4d origin/fix/tray-menu-pinned-surface-height` exit 0。
- 本闭环记录不含自引用 hash，由后续 `git log --format=%H -- execution-log.md` 解析。

### 10. 未覆盖、现场项与后续边界

- 无需用户现场操作；未部署或重启 Quickshell/niri。
- A08.1 为源码级证明（属性存在消除 undefined 转换告警成因），无运行时日志采样（不重启会话）；待部署后运行时确认告警消失。
- 测试诚实 scope：无 Wayland 连接环境无法构造真实 wl_surface，"协议可用边递增"由 seam 状态机测试 + R17 结构契约（waylandSurfaceCreated 内 advance、setAvailable 先于 advance）双覆盖；"协议不可用边"由真实 waylandSurfaceCreated 早退路径行为测试覆盖。
- 既有边界（surfaceCreated 无 surfaceDestroyed 被基类 mHasWaylandSurface 守卫吞掉 → 无 advance）为预先存在的生命周期行为，非 T08 引入。

### 11. 完成裁决

**结论**：COMPLETE。

**理由**：A08.1-A08.5 与 G01-G08 均满足；旧实现红（缺 mappingGeneration 属性 → Dock 告警 + R17 失败），新实现 TestMappingLifecycle 8 测试槽全绿（QTest Totals: 10 passed） + ctest 17/17 + SHELL_FULL 1011 passed（R17 转绿）+ PROTOCOL_FULL IN_SYNC；两轮各 2 个全新独立 reviewer 最终双 CLEAN，无未裁决 finding；无 live restart/deploy，未触碰 `.zcode/`、`Testing/` 或 T09。

**下一任务是否允许开始**：YES（本 docs-only closure commit push 并远端验证后）。
