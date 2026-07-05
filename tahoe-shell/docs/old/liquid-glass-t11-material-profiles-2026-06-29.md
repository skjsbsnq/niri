# Liquid Glass T11 Material Profiles

日期：2026-06-29

## 状态

T11 已完成。shell 场景玻璃 profile 现在集中在 niri material 和设置读写默认值中，业务 QML 仍只选择 material token，不承载 raw shader 参数。

## 本轮决策

- material vocabulary 收敛为 7 个 shell 场景：`panel`、`pill`、`launcher`、`dock`、`menu`、`toast`、`backdrop`。
- 移除 `tahoe-glass` 配置中的旧 `clear` / `tinted` profile；它们不是业务 QML 使用的 scene material。
- `chromatic` 默认保持 `0.0`，避免菜单、面板、toast 文本出现彩边。
- `backdrop` 显式关闭 shadow，降低 noise/refraction/lens，继续依赖 shader 的大面衰减。
- 不新增 `clarity`、`refraction_a/b/c/d`、`power_factor` 等 raw knob；继续复用已有 `BackgroundEffect` / `GlassOptions` 字段。

## Profile 分层

| material | 目标 |
| --- | --- |
| `panel` | 默认面板，可读性优先，低折射、无 lens。 |
| `pill` | Spotlight 输入框和 Dynamic Island，边缘光更强，保留轻 lens。 |
| `launcher` | Launchpad 居中大卡片，比 `panel` 更克制，比 `backdrop` 更有边缘。 |
| `dock` | 图标密集且面积中等，降低 refraction/lens，保留轻交互感。 |
| `menu` | 文字密集，增强 edge/contrast，压低 refraction/lens。 |
| `toast` | 短生命周期卡片，接近 menu 但稍柔和，继续由 `materialAlpha` 控制进出。 |
| `backdrop` | 大面积/全屏背景，shadow off，最低 refraction/lens。 |

## 本轮改动

- `config/niri/tahoe-phase0.kdl`
  - 删除 `clear` / `tinted` material blocks。
  - 为 7 个 scene material 显式设置 `noise`、`saturation`、`tint-color`、`tint-amount`、`contrast`、`edge-highlight`、`refraction`、`inner-shadow`、`chromatic`、`lens-depth`。
  - 同步 panel/menu fallback `background-effect` blocks，使协议不可用时视觉仍接近主路径。
- `niri/niri-config/src/tahoe_glass.rs`
  - 默认 material map 改为同一套 7 个 scene token。
  - 新增 `launcher` 默认 material，删除默认 `clear` / `tinted`。
  - 新增测试锁住默认 material vocabulary、`launcher` refraction、`backdrop` shadow-off。
- `niri/niri-config/src/lib.rs`
  - 更新默认配置 inline snapshot。
- `tahoe-shell/services/NiriSettings.qml`
  - 同步设置页首次加载前的 material slider 默认值。
- `tahoe-shell/services/niri_settings_tool.py`
  - 缺失 material block 或字段时，按 scene material 默认值回退，而不是统一回退到 `0.0`。

## 保留的不变量

- 未改 TahoeGlass Wayland 协议。
- 未改 shader。
- 未改业务 QML material 选择。
- 未新增 direct `BackgroundEffect.blurRegion` 调用。
- `TahoeGlass.js`、`niri_settings_tool.py`、`config/niri/tahoe-phase0.kdl` 与 niri 默认 material map 的 scene token 一致。

## 验证

已通过：

```sh
bash scripts/check-tahoe-glass-guardrails.sh
./niri/target/debug/niri validate -c config/niri/tahoe-phase0.kdl
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
python3 -m py_compile tahoe-shell/services/niri_settings_tool.py
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/NiriSettings.qml tahoe-shell/components/settings/pages/NiriGlassPage.qml
cargo test -p niri-config --quiet
git diff --check
(cd niri && git diff --check)
```

本轮未做 live 截图验收；T11 只调 material profile 与默认值，实机浅色/深色/高对比背景下的视觉基线仍进入 T13。
