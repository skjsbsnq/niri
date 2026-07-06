# GOAL-8 验收：glass 性能预算与质感治理

日期：2026-07-06

范围：建立 TahoeGlass 性能预算、治理文档和测量入口。默认材质强度不变；没有 DRM/TTY Tracy capture 前，不提高 `chromatic`、`refraction` 或全局 blur。

## 完成了什么

- 新增 `tahoe-shell/docs/tahoe-material-governance.md`。
  - 记录七个 material token：`panel`、`pill`、`launcher`、`dock`、`menu`、`toast`、`backdrop`。
  - 记录 surface recipes：TopBar、Dock、ControlCenter、NotificationToast、Launchpad、Spotlight、MenuPopup、SettingsPanel。
  - 明确 source-of-truth 文件：`TahoeGlass.js`、`config/niri/tahoe-phase0.kdl`、`niri/niri-config/src/tahoe_glass.rs`、`NiriSettings.qml`、`niri_settings_tool.py`。
  - 明确不做 GPU/渲染能力自适应。
- 在 `niri/src/render_helpers/tahoe_glass.rs` 复用现有 render path 加测量入口：
  - `TahoeGlass::render_regions_for_layer` Tracy span。
  - `TahoeGlass::render_region` Tracy span。
  - `trace` fields：namespace、region_count、total_area、material、region area、sample_padding、blur、clip、material_alpha。
- 记录现有成本观察点：
  - `FramebufferEffectElement::capture_framebuffer`
  - `Blur::prepare_textures`
  - `Blur::render`
  - `EffectBuffer::prepare_offscreen`
- GOAL-8 调整决策：不改默认 material 数值。原因是没有 live DRM/TTY capture；本 gate 先建立 budget 和 measurement hooks。

## Baseline

Source-level baseline：

- Material token set unchanged。
- 所有 material 的 `chromatic` 仍为 `0.0`。
- `refraction` 未提高。
- Spotlight 以外的常见 surface 目标为 1 region；Spotlight 为 2 regions。
- Protocol hard limits 已记录：
  - max 32 TahoeGlass regions per surface。
  - committed region 总面积不能超过 surface area。
  - region 必须在 surface geometry 内。

Sample padding formula 已记录：

```text
max(2, blur.offset * blur.passes, (abs(refraction) + abs(lens-depth)) * short_edge * 2 + 4)
clamped to [2, 64]
```

调整后对比：

- 默认 material 参数不变，所以 visual/perf risk from material strength is unchanged。
- 新增的 measurement hooks 让后续 live capture 能比较 region_count、total_area、sample_padding、framebuffer capture span 和 blur render span。
- Governance test 现在覆盖 material drift 和治理文档，之前缺失的 `tahoe-material-governance.md` 测试失败已修复。

## 没有做什么

- 没有提高 `chromatic`。
- 没有提高 `refraction`。
- 没有提高 blur pass、blur offset、sample padding 或材质全局强度。
- 没有新增 material token。
- 没有新增 static blur path。
- 没有按 GPU/渲染能力自动切换策略。
- 没有做 live DRM/TTY Tracy capture；本环境只完成 source-level baseline 和 instrumentation。
- 没有开始 GOAL-9。

## 复用了哪些现有接口

- `FramebufferEffect`
- `EffectBuffer`
- `TahoeGlass.js`
- `tahoe-material-governance.md`
- Existing Tracy spans and render helper structure。
- Existing `test_tahoe_material_governance.py` governance test。

## 是否新增接口

没有新增 runtime/config/user-facing 接口。

新增的是 observability：

- Two Tracy span names in the existing TahoeGlass render path。
- Existing `trace` logging fields for region budget data。
- Governance documentation consumed by existing tests。

## 运行命令

```text
python3 tahoe-shell/tests/test_tahoe_material_governance.py
python3 -m unittest discover tahoe-shell/tests
cargo test -p niri tahoe_glass
cargo test -p niri-config tahoe_glass
cargo fmt --check
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
git diff --check
```

结果：

- `test_tahoe_material_governance.py`：3 tests passed。
- Full `python3 -m unittest discover tahoe-shell/tests`：53 tests passed。
- `cargo test -p niri tahoe_glass`：3 tests passed。
- `cargo test -p niri-config tahoe_glass`：2 tests passed。
- `cargo fmt --check`：passed, with existing stable-toolchain warnings for unstable rustfmt options。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- `git diff --check`：passed。

## 剩余风险

- No real DRM/TTY frame-time capture was performed, so no material value was raised.
- The new trace fields require running with trace logging or Tracy capture to collect live numbers.
- Future visual tuning still needs before/after capture for TopBar、ControlCenter、Launchpad、Spotlight、Dock before changing defaults。

## 回滚方式

- Revert `tahoe-shell/docs/tahoe-material-governance.md`。
- Revert the GOAL-8 instrumentation in `niri/src/render_helpers/tahoe_glass.rs`。
- Delete this acceptance document and revert the GOAL-8 status row。

No user config rollback is required because default material values did not change.
