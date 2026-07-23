# 任务：R00 / 回归与观测地基

待审状态：Author verification complete
开始基线：外层 `51a275eb` / niri `a7b88a0c` / quickshell `bbc267ca`

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/layout/scrolling.rs` | production overlay 可见性谓词 + test-only `render_observation` |
| `src/layout/minimize_window_animation.rs` | test morph progress；Genie create 时 opt-in 字节计数 |
| `src/window/mapped.rs` | test-only maximize serial 观测 |
| `src/backend/headless.rs` | scale/transform 感知 add_output |
| `src/tests/fixture.rs` | 多输出/scale/transform、layer map/unmap/remap helpers |
| `src/tests/lifecycle_observe.rs` | 真实 Mapped serial、F01 观测、fixture 自测 |
| `src/layout/tests/observe.rs` | layout 级 maximize FSM / overlay decision 自测 |
| `src/utils/lifecycle_diag.rs` | opt-in 计数（默认关） |
| `src/utils/mod.rs` | 导出 lifecycle_diag |
| `src/niri.rs` | queue_redraw(_all) 钩子 |
| `src/frame_clock.rs` | frame_p50 上报 |
| `src/protocols/tahoe_glass.rs` | region request/commit 计数 |
| `src/render_helpers/tahoe_glass.rs` | region capture 计数 |
| `src/tests/mod.rs` / `src/layout/tests.rs` | 注册测试模块 |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../acceptance/R00-baseline-2026-07-23.md` | 基线记录 |
| `docs/.../R00-execution-record.md` | 本执行记录 |

Owner：观测/fixture 基础设施；**无** lifecycle/render ownership 迁移。

## 行为契约

适用 1.4 节保持项：全部 lifecycle/maximize/多输出/协议路径行为不变；仅增加 test/opt-in 观测。
明确**不**修复 F01（仅观测当前“抑制但仍推进”）。

## 旧路径删除

不适用（R00 不替换 production owner）。
静态检索：无新增平行 lifecycle API；观测读取 production 容器与 `lifecycle_overlays_are_rendered()`。

```text
rg -n 'lifecycle_overlays_are_rendered|render_observation' niri/src
# 仅 scrolling render + observation；无第二决策表
```

## 测试

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all` | 已格式化 |
| `cargo test -p niri --lib layout::tests` | 126 passed |
| `cargo test -p niri --lib frame_clock` | 2 passed |
| `cargo test -p niri --lib lifecycle_diag` | 3 passed |
| `cargo test -p niri --lib foreign_toplevel` | 3 passed |
| `cargo test -p niri --lib lifecycle_observe` | 5 passed |
| `cargo test -p niri --lib observe` | 8 passed |

未运行：完整 `cargo test -p niri`（时间）；嵌套会话 frame 分位（见基线文档，仪器已就绪）。

## 性能

硬件/场景/未测项见 `acceptance/R00-baseline-2026-07-23.md`。
本任务目标是建立可复测仪器，不是改善数值。

## Follow-up：M1–M3 修复（同任务闭环补强）

| Finding | 修复 |
| --- | --- |
| M1 旧/最新 serial | 新增 `real_mapped_serial_old_configure_vs_latest_commit`：maximize(A)→unmaximize(B)→commit A→仍 maximized 且 B 在队列→commit B→false；`test_maximize_commit_state` 返回完整 `(Serial, bool)` 队列 |
| M2 并行 diag 竞态 | `with_test_lock` / `with_enabled_for_test` 串行化 enable/disable；fixture 与 unit 测试均走此路径 |
| M3 默认关闭成本 | `note_genie_create(FnOnce)` 仅在 enabled 时求值字节；单测断言闭包不在 disabled 路径执行 |

验证：`cargo test -p niri --lib observe`（9 passed）、`lifecycle_diag`（4 passed）、`layout::tests`（126 passed）。
