# GOAL-6 验收：修正 edge-reveal 调参语义

日期：2026-07-06

范围：选择路径 A，保留现有 `edge-reveal` 完整 surface reveal/retract 行为，只修正设置页、KDL 注释和文档里的调参语义。不新增 style，不改变 runtime，不迁移 KDL profile。

## 选择路径

选择路径 A：保留当前 `edge-reveal` 语义。

原因：

- 当前 niri runtime 已有 `layer_close_edge_reveal_moves_full_surface_extent` 测试，明确要求 close edge-reveal 按 surface 高/宽完整收回。
- 新增 `edge-slide` / `short-reveal` 会进入 parser、runtime、状态测试和视觉验收的更大范围，不是消除误导所必需。
- 设置页没有独立的 distance 编辑入口；真正误导来自 `distance` KDL 字段和旧文档里“短距离 edge reveal”的描述。

## 完成了什么

- 在 `NiriAnimationsPage.qml` 的 `Motion profile` 区域新增只读说明：
  - `edge-reveal` 按 surface 宽/高完成 reveal/retract。
  - KDL `distance` 仅为兼容保留，不是短滑动距离调参。
- 在 `config/niri/tahoe-phase0.kdl` 的所有 `edge-reveal` + explicit `distance` 位置旁增加注释：
  - `edge-reveal uses the layer surface extent; this is not a short-travel knob.`
- 修正 active config 中 Small Popup 的注释，不再说 `short top-edge reveal motion`。
- 修正 `docs/layer-animation-motion-v2-roadmap.md` 里仍把 `edge-reveal` 描述为短距离 slide 的旧文字。
- 修正 `niri/src/layer/closing_layer.rs` 中过期的 code comment；runtime 仍保持原逻辑。
- 新增 `tahoe-shell/tests/test_edge_reveal_semantics.py`，source-level 约束：
  - settings page 必须说明 `KDL distance` 不是短滑动距离调参。
  - active KDL 不再出现 `short top-edge`。
  - niri full-surface edge-reveal regression test 必须保留。

## 没有做什么

- 没有新增 `edge-slide`、`short-reveal` 或任何新 animation style。
- 没有修改 `LayerOpenAnimationStyle` / `LayerCloseAnimationStyle` enum。
- 没有修改 KDL parser 行为；`distance` 仍可解析。
- 没有修改 open/close runtime offset、crop、snapshot 或 animation state 逻辑。
- 没有改变 `config/niri/tahoe-phase0.kdl` 的实际 animation values。
- 没有开始 GOAL-7。

## 复用了哪些现有接口

- Existing `NiriAnimationsPage.qml` section/control structure。
- Existing `config/niri/tahoe-phase0.kdl` layer-rule animation fields。
- Existing niri parser/runtime/tests for `edge-reveal`。
- Existing GOAL-5 motion profile writer; comments do not affect profile detection or writes.

## 是否新增接口

没有新增 runtime/config 接口。

新增了 source-level test `tahoe-shell/tests/test_edge_reveal_semantics.py`。原因：GOAL-6 是语义/文档风险，测试应防止设置页和 active config 重新把 `edge-reveal distance` 描述成短滑动距离。

## 运行命令

```text
python3 tahoe-shell/tests/test_edge_reveal_semantics.py
python3 tahoe-shell/tests/test_niri_settings_tool.py
git diff --check
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/settings/pages/NiriAnimationsPage.qml
cargo fmt --check
cargo test -p niri layer_close_edge_reveal_moves_full_surface_extent
cargo test -p niri-config parse_layer_rule_animation_edge_reveal_style
python3 -m unittest discover tahoe-shell/tests
```

结果：

- `test_edge_reveal_semantics.py`：3 tests passed。
- `test_niri_settings_tool.py`：15 tests passed；KDL comments did not break profile parsing/writing tests。
- `git diff --check`：passed。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- Bounded `NiriAnimationsPage.qml` load exited with expected `124` timeout and no stderr。
- `cargo fmt --check`：passed, with existing stable-toolchain warnings for unstable rustfmt options。
- `cargo test -p niri layer_close_edge_reveal_moves_full_surface_extent`：1 targeted test passed。
- `cargo test -p niri-config parse_layer_rule_animation_edge_reveal_style`：1 targeted test passed。
- Full `python3 -m unittest discover tahoe-shell/tests` still fails because `tahoe-shell/docs/tahoe-material-governance.md` is missing in `test_tahoe_material_governance.py`; this is pre-existing/unrelated to GOAL-6 and was not fixed in this gate.

## 剩余风险

- No live Quickshell reload or screenshot validation was performed.
- `distance` remains in KDL because the parser supports it and profile writes preserve existing schema compatibility; users manually editing KDL can still see the field, but active comments now explain that it is not a short-travel knob for `edge-reveal`.
- Historical docs may still contain raw `distance` examples, but the active motion-v2 wording that described `edge-reveal` as short-distance was corrected.

## 回滚方式

- Revert the GOAL-6 edits in `NiriAnimationsPage.qml`, `config/niri/tahoe-phase0.kdl`, `docs/layer-animation-motion-v2-roadmap.md`, and `niri/src/layer/closing_layer.rs`.
- Delete `tahoe-shell/tests/test_edge_reveal_semantics.py`.
- Delete this acceptance document and revert the GOAL-6 status row.

Runtime rollback is not needed because this gate did not change runtime behavior.
