# GOAL-7 验收：open/close 连续性

日期：2026-07-06

范围：验证并加固 niri layer open/close 连续性测试覆盖，重点是 close interrupt open、open interrupt close、快速 toggle 后 snapshot 释放、以及 opacity/transform 起点一致性。不改 QML 外层动画，不延长动画参数，不引入 shader workaround。

## 完成了什么

- 复用现有 `niri/src/tests/layer_shell.rs` fixture，新增快速 toggle 回归测试：
  - `layer_animation_fast_toggle_settles_without_residual_snapshots`
  - 同一个 `animated-layer` 连续执行 10 次 unmap/remap。
  - 每次 close 启动后确认有且只有一个 close snapshot。
  - reopen 后确认旧 close snapshot 被取消，mapped layer 回到 live surface。
  - 最后 open settle 后确认 `mapped.are_animations_ongoing()` 为 false。
  - 最后 close duration + 一帧 margin 后确认 `closing_layers` 清空。
- 新增 snapshot 生命周期测试：
  - `layer_close_snapshot_releases_one_frame_after_duration`
  - 120ms close 动画在 140ms 后释放 close snapshot。
- 保留并重新跑现有连续性测试：
  - `layer_close_animation_interrupted_open_starts_from_current_visual_state`
  - `layer_close_animation_interrupted_open_uses_opacity_delay`
  - `layer_close_animation_interrupted_slide_open_starts_from_current_offset`
  - `layer_close_animation_interrupted_edge_reveal_open_starts_from_current_offset`
  - `layer_close_animation_is_cancelled_on_reopen`
  - `layer_close_animation_uses_snapshot_and_cleans_up`
- 调整 layer-shell test helper：
  - `advance_layer_animations()` 现在通过 `set_layer_animation_time()` 设置 deterministic adjusted clock。
  - 新增 `freeze_layer_animation_clock()`，避免 event-loop `clock.clear()` 让测试中创建的新 open/close animation 采样 wall clock。
  - 这是 test fixture 修正，不改变 runtime。
- GOAL-6 已修正的 `closing_layer.rs` 注释继续保持：`slide` 使用 configured distance，`edge-reveal` 使用 surface extent 完整 retract。

## 没有做什么

- 没有修改 niri open/close runtime 逻辑。
- 没有改变 KDL animation duration、curve、opacity、distance 或 style。
- 没有通过延长动画 duration 掩盖闪烁。
- 没有把 QML 外层动画重新叠回 compositor layer animation 路径。
- 没有新增 shader 或 snapshot render path。
- 没有做 live Quickshell 快速 toggle 截图验收。
- 没有开始 GOAL-8。

## 复用了哪些现有接口

- `opening_layer.rs`
- `closing_layer.rs`
- `mapped.rs`
- Existing `niri/src/tests/layer_shell.rs` fixture。
- Existing `closing_layers` lifecycle and `MappedLayer::are_animations_ongoing()` checks。

## 是否新增接口

没有新增 runtime/config 接口。

新增的是 Rust regression tests 和 test helper：

- `layer_animation_fast_toggle_settles_without_residual_snapshots`
- `layer_close_snapshot_releases_one_frame_after_duration`
- deterministic layer-shell animation clock helper

## 运行命令

```text
cargo test -p niri layer_animation_fast_toggle_settles_without_residual_snapshots
cargo test -p niri layer_close_snapshot_releases_one_frame_after_duration
cargo test -p niri layer_close_animation
cargo test -p niri layer_shell
cargo fmt --check
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
git diff --check
python3 -m unittest discover tahoe-shell/tests
```

结果：

- `layer_animation_fast_toggle_settles_without_residual_snapshots`：passed。
- `layer_close_snapshot_releases_one_frame_after_duration`：passed。
- `cargo test -p niri layer_close_animation`：7 tests passed。
- `cargo test -p niri layer_shell`：18 tests passed。
- `cargo fmt --check`：passed, with existing stable-toolchain warnings for unstable rustfmt options。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- `git diff --check`：passed。
- Full `python3 -m unittest discover tahoe-shell/tests` still fails because `tahoe-shell/docs/tahoe-material-governance.md` is missing in `test_tahoe_material_governance.py`; this is pre-existing/unrelated to GOAL-7 and was not fixed in this gate.

## 剩余风险

- No live Quickshell screenshot/video validation was performed; the 10-toggle check is a deterministic Rust fixture test.
- The test fixture verifies lifecycle and state cleanup, not GPU repaint counters. It uses `closing_layers` and `are_animations_ongoing()` as the automated proxy for residual snapshot/repaint risk.
- Real DRM/TTY visual validation remains useful for GOAL-8/GOAL-10 before changing defaults.

## 回滚方式

- Revert the GOAL-7 additions in `niri/src/tests/layer_shell.rs`.
- Delete this acceptance document.
- Revert the GOAL-7 status row to `in-progress` or `pending` as appropriate.

No user config rollback is required because GOAL-7 did not change runtime config or defaults.
