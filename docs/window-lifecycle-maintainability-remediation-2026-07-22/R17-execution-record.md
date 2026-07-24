# 任务：R17 / lifecycle/foreign/glass 定向 redraw

待审状态：Author verification complete
开始基线：外层 `36f5dee` / niri `cafde04f` / quickshell `8b71640`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/redraw_attribution.rs` | 统一 `RedrawAttribution` / `RedrawReason` / `RedrawFallbackReason`；reason note |
| `src/lifecycle_command.rs` | `LifecycleCommandResult` 携带 `redraw: RedrawAttribution` |
| `src/niri.rs` | `execute_lifecycle_command` 返回 home+related outputs；`Niri::apply_redraw_attribution` |
| `src/handlers/mod.rs` | Foreign activate/maximize/minimize 与 glass handler 走 attribution |
| `src/handlers/xdg_shell.rs` | xdg `minimize_request` 走 command redraw |
| `src/input/mod.rs` | IPC Minimize/Restore 走 command redraw |
| `src/utils/lifecycle_diag.rs` | targeted / fallback reason counters |
| `src/tests/r17_redraw_attribution.rs` | 双输出 waste、跨 focus restore、源码删除、fallback reason |
| `src/tests/r15_perf_baseline.rs` | 历史 R15 样本改为 post-R17 targeted 断言 |
| `src/tests/mod.rs` | 注册 r17 模块 |
| `src/lib.rs` | 导出 `redraw_attribution` |

### 外层

| 路径 | 作用 |
| --- | --- |
| `docs/.../R17-execution-record.md` | 本记录 |
| `docs/.../acceptance/R17-redraw-attribution-2026-07-24.md` | 前后对照与删除证明 |

未改 quickshell；未动 R18/R19；未清理 182 处全量 `queue_redraw_all` 外围调用。

Owner：

- **Redraw attribution 结果类型**：`RedrawAttribution`（command/controller 返回；adapter 禁止自建 output 列表）。
- **Apply 唯一入口**：`Niri::apply_redraw_attribution`。
- **Lifecycle 输出集**：`State::execute_lifecycle_command`（window home + restore 时 prev active）。
- **Activate 输出集**：`State::activate_window_attributed`（home + prev active）。
- **Maximize 输出集**：`State::set_maximized_attributed` / `unset_maximized_attributed`（workspace home）。
- **Glass**：R14 `queue_redraw_for_tahoe_glass_surface` 现经 attribution（targeted / Unlocatable fallback）；handler 只解析 root→output 再 apply。

## 目标设计落地

```text
foreign / xdg / IPC  adapter
        │ parse only
        ▼
LifecycleCommand / set_maximized / activate / glass surface
        │ owner returns RedrawAttribution
        ▼
Niri::apply_redraw_attribution
  · Outputs {..} → note_targeted_reason + queue_redraw(each)
  · All {Unlocatable|OutputTeardown|GlobalConfig}
        → note_fallback_reason + queue_redraw_all
  · None → no-op (cache write / NoOp command)
```

## 旧路径删除

```text
# ForeignToplevelHandler 块内零 queue_redraw_all：
cargo test -p niri --lib r17_foreign_handler_source_has_zero_queue_redraw_all

# xdg minimize_request / IPC Minimize|Restore 臂：
cargo test -p niri --lib r17_lifecycle_adapters_use_attribution_not_redraw_all

# 生产路径关键字：
rg -n 'apply_redraw_attribution' niri/src/handlers niri/src/input niri/src/niri.rs
# foreign minimize/restore/maximize/activate + glass + xdg minimize + IPC lifecycle

# Foreign 块内不得出现：
rg -n 'queue_redraw_all' niri/src/handlers/mod.rs
# 剩余命中：cursor/dnd/ext_workspace/xdg_activation/glass 以外的非 foreign 路径
# （ForeignToplevelHandler 区间由自动化源码测试锁定为零）
```

作者验证：

1. 双输出 foreign minimize（command 直调 + apply）：`queued=1`，other Idle，`targeted_lifecycle≥1`。
2. restore 跨 focus：attribution 含 home + prev active（2 outputs）。
3. set_rectangle 纯缓存：无 lifecycle/maximize/activate attribution。
4. glass unlocatable：`RedrawFallbackReason::Unlocatable` + 全输出 Queued。
5. 未引入第二套 parallel redraw API；未把 `queue_redraw_all` 改名伪装。

## 行为契约

适用 1.4 节：minimize/restore/reverse、maximize、activate、glass locatable/unlocatable、anchor 缓存、多输出/热插拔路径未删真实跨输出依赖（restore 跨 focus 显式返回两个输出）。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all -- --check)` | 通过 |
| `(cd niri && cargo test -p niri --lib r17_redraw -- --nocapture)` | **12 passed** |
| `(cd niri && cargo test -p niri --lib lifecycle -- --nocapture)` | **45 passed** |
| `(cd niri && cargo test -p niri --lib foreign_toplevel -- --nocapture)` | **12 passed** |
| `(cd niri && cargo test -p niri --lib tahoe_glass -- --nocapture)` | **33 passed** |
| `(cd niri && cargo test -p niri --lib)` | **455 passed** |

未运行：

- 完整 `cargo test -p niri`（含 bin/doctest）：lib 为矩阵自动化主体；
- 真机双屏 KMS direct-scanout 命中率；
- quickshell ctest：未改。

### 关键不变量

- attribution 来自唯一 owner（command / foreign maximize-activate 查找 / glass output_for_root）；
- 跨输出 restore 完整包含 home + prev active；
- fallback 可观测（reason counter）且仅 Unlocatable/OutputTeardown/GlobalConfig；
- 双输出 minimize 不受影响 output 保持 Idle（fixture-local Queued 证明）。

## 性能

对照 R15（`acceptance/R15-baseline-2026-07-24.md` §5.1）：

| 指标 | R15 前测 | R17 后 |
| --- | --- | --- |
| foreign minimize dual-output Queued | 2/2 via redraw-all | **1/2** home only（command+apply） |
| waste_ratio (home=1, total=2) | 0.50 | **0** on attribution path |
| foreign maximize adapter | queue_redraw_all≥1 | targeted_maximize≥1，adapter 零 redraw-all |
| glass mapped | targeted（R14） | 仍 targeted；经统一 apply |

硬件：同 R15（Linux WWT / Ryzen 7 7745HX）。Headless debug 集成测试。

说明：`double_roundtrip` 后偶发仍见全局 `queue_redraw_all` 计数来自 `refresh_pointer_contents`（指针离开 minimized 表面），该路径不在 R17 cluster，已在记录与测试注释中标明；cluster 删除证明 + fixture Queued 状态为正式证据。

## 独立审查专属问题（作者自查）

1. attribution 来自唯一 owner，还是 adapter 各自维护 output 列表？**唯一 owner：`execute_lifecycle_command` / `activate_window_attributed` / `set_maximized_attributed` / glass handler 经 `output_for_root` 建 attribution；adapter 只 apply。**
2. 跨输出事件是否完整包含所有受影响输出？**是；restore 跨 focus 返回 home+prev active（测试 `r17_restore_includes_previous_active_when_focus_moves`）。**
3. fallback 是否可观测且仅用于无法定位/真正全局事件？**是；`RedrawFallbackReason` + diag counters；glass unlocatable 使用 Unlocatable。**
4. 是否出现漏帧、动画停止调度或 direct scanout 回归？**lifecycle/foreign/glass/minimize 动画测试通过；未跑 KMS scanout。**
