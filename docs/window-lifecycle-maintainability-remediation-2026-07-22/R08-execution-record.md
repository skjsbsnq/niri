# 任务：R08 / 最大化视觉 FSM 与 F02 serial 判定

待审状态：Author verification complete
开始基线：外层 `9c62935` / niri `7c2a7097` / quickshell `bbc267ca`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/maximize_visual_fsm.rs` | **新增** `MaximizeVisualFsm` / `MaximizeVisualPhase` / `MaximizeVisualClear` / `MaximizeTransitionObservation`；超时常量；FSM 单元测试（含 1000/1001 ms 边界） |
| `src/layout/scrolling.rs` | 删除裸 `MaximizeTransition { committed, timed_out }`；字段改为 `Option<MaximizeVisualFsm>`；事件经 `begin` / `on_target_maximized_commit` / `on_clock_tick` / `clear_maximize_transition`；render/hit 经 `exclusivity_active()` |
| `src/layout/mod.rs` | `pub mod maximize_visual_fsm` |
| `src/layout/tests.rs` | 1000 ms unadjusted 边界；既有 timeout/late-commit/tab 回归保留 |
| `src/layout/tests/observe.rs` | observation 变体名对齐 FSM 阶段 |
| `src/tests/lifecycle_observe.rs` | F02 决策门：真实 Mapped configure/ack/commit 五场景 |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R08-execution-record.md` | 本执行记录 |

Owner：

- **`MaximizeVisualFsm`**：scrolling 空间上**唯一**的最大化**视觉** transition owner（阶段、超时、exclusivity 查询）。
- **Column / Mapped**：继续拥有 pending/committed maximized（协议 sizing）；FSM 不复制。
- **`ScrollingSpace` adapter**：window 移除、fullscreen、unmaximize、view/tile settle 谓词 → `Cancelled`/`Finished` clear；目标 commit 路径调用 `on_target_maximized_commit`。
- **Cancelled / Finished**：清除 `Option`（observation = `Idle`），不保留可独立读写的内部 bool 组合。

## 行为契约

适用 1.4 节：

- maximize 目标排他显示（PendingConfigure / CommittedSettling）保持；
- 1s 超时仅解除排他（TimedOutVisibleFallback），迟到有效 maximize commit 可恢复 CommittedSettling；
- 同列其他 tab commit 不推进目标 FSM；
- unmaximize / fullscreen / target remove 取消 visual transition；
- 新 maximize 请求替换旧 transition（显式 Cancel + begin）；
- R01 overlay Draw 策略不受影响（exclusivity 只过滤 live tile）；
- 未改变 Mapped configure/ack/commit serial 语义。

## 目标设计落地

```text
set_maximized(true)
        │
        ▼
MaximizeVisualFsm::begin(window, now_unadjusted, already_committed)
  · already → CommittedSettling
  · else    → PendingConfigure
        │
        ├─ target maximized commit  → on_target_maximized_commit → CommittedSettling
        ├─ clock ≥ 1s pending       → on_clock_tick → TimedOutVisibleFallback
        ├─ late valid commit        → CommittedSettling (from TimedOut)
        ├─ view/tile settled        → clear(Finished)
        └─ unmax / fs / remove / !pending_max → clear(Cancelled)

Render / hit / floating live suppress:
  exclusivity_active() ⇔ PendingConfigure | CommittedSettling
```

Observation（测试/诊断，非平行状态机）：

| 阶段 | Observation |
| --- | --- |
| 无 record | Idle |
| PendingConfigure | PendingConfigure |
| CommittedSettling | CommittedSettling |
| TimedOutVisibleFallback | TimedOutVisibleFallback |

## F02 决策门结论：**不加入 request identity**

| 场景 | 测试 | 结果 |
| --- | --- | --- |
| maximize → timeout → 有效 late commit | `f02_timeout_then_valid_late_maximize_commit_resumes_fsm` | TimedOut → CommittedSettling；排他恢复 |
| max → unmax → max 交错 | `f02_maximize_unmaximize_maximize_replaces_fsm` | unmax → Idle；新 max → PendingConfigure；commit → Settling |
| 同列其他 tab commit | `f02_same_column_other_tab_commit_does_not_advance_target_fsm` | 非目标 commit 不进 CommittedSettling；目标 commit 才进 |
| Activated configure/ack/commit | `f02_activated_configure_after_maximize_is_not_false_epoch_bug` | 累积 Maximized 状态下 commit 合法推进；**非** epoch bug |
| 旧 serial 晚于新 request | `f02_old_maximize_serial_after_new_request_does_not_mis_cancel` | 旧 A commit 在 pending 仍为 maximize 时使 window 合法 maximized，FSM 进 Settling；B（unmax）不 Cancel C；C commit 保持 Settling |

**不加入 identity 的证据：**

1. 窗口层已按 `uncommitted_maximized` serial 应用 committed maximized（R00 fixture + 上表）；FSM 只在 `column.is_pending_maximized() && tile.sizing_mode().is_maximized()` 时推进 — 依赖协议真源，不是裸 commit 计数。
2. 旧 maximize serial A 在请求 C 仍 pending maximize 时被 commit，使窗口**合法**处于 maximized；将当前 transition 标为 CommittedSettling 与“目标已 maximized 且仍请求 max”一致，**未证明**会把无关 epoch 错误当成当前 request 完成。
3. 中间 unmaximize serial B 不会 Cancel 仍 pending maximize 的 C（`!pending` 才 Cancel）。
4. 同列其他窗口/tab 的 commit 因 `transition.targets(window)` 守卫不会推进。
5. Activated 焦点 configure 属于 xdg 累积状态，不是 bug。

因此按路线图：完成 typed FSM，**不**另建 parallel serial 状态机。若未来产品要求“仅匹配本次 maximize configure serial 才进 Settling”，再复用 Mapped 队列 serial 派生 identity。

## 旧路径删除

```text
rg -n 'MaximizeTransition|maximize_transition|maximizing_window_location|maximizing_column_idx|committed: bool|timed_out: bool' niri/src/layout/scrolling.rs
```

作者验证结果：

- **零** `struct MaximizeTransition`、`committed: bool`、`timed_out: bool`。
- `maximize_transition` 字段类型为 `Option<MaximizeVisualFsm<_>>`；phase 仅通过 FSM 方法变更。
- `maximizing_window_location` / `maximizing_column_idx` 仍为 render/hit adapter，读 `exclusivity_active()`，不读内部 bool。

允许保留：

- 字段名 `maximize_transition` 与 helper 名（归属新 FSM）；
- `MaximizeTransitionObservation`（test observation，re-export from fsm 模块）；
- Column/Mapped 的 pending/committed maximized。

```text
rg -n 'committed: bool|timed_out: bool' niri/src/layout
# 零命中于 maximize transition record
```

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化；无关 niri-config/layer fmt 已还原 |
| `(cd niri && cargo test -p niri --lib layout::)` | **172 passed** |
| `(cd niri && cargo test -p niri --lib -- lifecycle coords closing_window maximize)` | **83 passed**（含全部 f02_* 与 real_mapped_serial_*） |
| `layout::maximize_visual_fsm` | **5 passed**（含 999/1000/1001 边界） |
| `maximize_pending_timeout_boundary_1000_ms_unadjusted` | **passed** |
| 既有 `maximize_transition_times_out_*` / `timed_out_maximize_ignores_late_commit_from_other_tab` / cancel priority | **passed** |
| 删除证明（上式） | 旧 bool struct 为零 |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话手测。

### 关键不变量

- PendingConfigure 排他；TimedOut 解除；late target commit 恢复；
- 1000 ms（含）超时，999 ms 仍 Pending（unadjusted）；
- 其他 tab 不能推进目标；
- unmaximize / 新 request 明确替换；
- Activated commit 非 false positive bug；
- 旧 serial 交错下不误 Cancel 当前 pending maximize。

## 性能

可维护性 / 条件修复。未声称帧时间或显存收益。

## 独立审查专属问题（作者自查）

1. FSM 是否排除了旧 bool 可表达的模糊组合？**是**；三相互斥 + Idle=无 record；不存在 `committed && timed_out` 同时为真。
2. 是否错误地把普通 Activated commit 定性为 bug？**否**；`f02_activated_*` 证明合法推进；执行记录写明非 epoch bug。
3. 新 request 如何明确取消/替换旧 transition？**unmaximize** → `clear(Cancelled)`；**maximize** → 直接 `begin` 覆盖 `Option`；fullscreen/remove 同 Cancelled。
4. serial identity 若加入，是否完全复用 production serial 语义？**未加入**；F02 证据见上。若将来加入，必须挂 Mapped `uncommitted_maximized` / commit serial，禁止平行 serial 机。
