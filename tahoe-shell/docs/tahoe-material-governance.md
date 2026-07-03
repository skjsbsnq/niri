# Tahoe Material Governance

日期：2026-07-03

本文是 Tahoe shell 视觉材质的治理规则。目标是让 QML token、niri KDL material profile、niri-config 默认值和 fallback fill/stroke 长期同步；本文不做 GPU/渲染能力自适应，不新增自动探测或按 renderer 切换的视觉策略。

## Source Of Truth

- `tahoe-shell/components/TahoeGlass.js` 是 shell 侧 material token、radius、QML fallback fill/stroke 的来源。
- `config/niri/tahoe-phase0.kdl` 是部署用 material profile 调参来源。
- `niri/niri-config/src/tahoe_glass.rs` 是 compositor 配置解析缺省值来源，必须镜像 KDL 的 scene material profile。
- `tahoe-shell/services/NiriSettings.qml` 和 `tahoe-shell/services/niri_settings_tool.py` 只镜像可写的五个 visual fields：`edge-highlight`、`refraction`、`inner-shadow`、`chromatic`、`lens-depth`。

修改任一 material profile 时，必须同步上述来源并运行 `python3 -m pytest tahoe-shell/tests/test_tahoe_material_governance.py`。fallback layer-rule 只服务协议不可用路径，不得成为第二套调参来源。

## Permanent Rules

- material vocabulary 固定为七个 scene token：`panel`、`pill`、`launcher`、`dock`、`menu`、`toast`、`backdrop`。
- 业务 QML 只选择 material token、radius、interaction 和 materialAlpha，不直接写 shader/raw glass 参数。
- `chromatic` 默认保持 `0.0`。除非另有实机视觉验收，不通过默认 chromatic 制造彩边。
- `refraction` 默认保持克制：文字密集 surface 使用低 refraction，不能为了视觉刺激整体抬高。
- 不做 GPU/渲染能力自适应：不加入自动 GPU 探测，不按 renderer 自动改 `useSpring`，不按 GPU 自动降级 material profile。
- 不删除现有 fallback。fallback 的目标是接近主路径，而不是追求完全等价。

## Material Defaults

| material | 用途 | 默认 radius | fallback fill | fallback stroke | interaction range |
| --- | --- | ---: | --- | --- | --- |
| `panel` | 常驻面板、控制中心、设置面板、结果列表、侧栏 | 28 | `#14ffffff` | `#24ffffff` | `0.0` for persistent panels; `0.0..1.0` when tied to transient opacity |
| `pill` | 顶栏胶囊、Spotlight 输入框、Dynamic Island | 33 | `#80f7fbff` | `#48ffffff` | `0.0..1.0`; hover/active should intensify edge, not resize the region |
| `launcher` | Launchpad 主卡片、大型中心启动面板 | 28 | `#1cf7f8fb` | `#32ffffff` | `0.0..1.0` during enter/exit, otherwise stable |
| `dock` | Dock 背板和窗口架 | 24 | `#2af7fbff` | `#44ffffff` | `0.0..1.0`, driven by visible amount and hover state |
| `menu` | 右键菜单、AppMenu、TrayMenu、Dock menu、process menu | 18 | `#18f7f8fb` | `#34ffffff` | usually `0.0`; use row-local hover instead of region-wide pulsing |
| `toast` | 通知 toast 和短暂反馈卡片 | 18 | `#14ffffff` | `#34ffffff` | `0.0..1.0`, tied to toast materialAlpha |
| `backdrop` | 全屏 dim/scrim/overview background | 0 | `#12eef2f7` | `#24ffffff` | `0.0..0.25`; avoid whole-screen warp |

`TopBar` is a recipe override on top of `panel`: radius is `18`, fill is `#22f7fbff`, stroke is `#34ffffff`. `SettingsPanel` and `Spotlight` result lists may use compact panel radius `18` where density matters.

## Material Profiles

The deployed KDL and Rust defaults must match these scene profiles:

| material | noise | saturation | contrast | tint-amount | edge-highlight | refraction | inner-shadow | chromatic | lens-depth |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `panel` | 0.005 | 1.10 | 1.10 | 0.105 | 0.14 | 0.004 | 0.06 | 0.0 | 0.0 |
| `pill` | 0.005 | 1.12 | 1.05 | 0.052 | 0.32 | 0.013 | 0.07 | 0.0 | 0.010 |
| `launcher` | 0.005 | 1.08 | 1.08 | 0.085 | 0.15 | 0.004 | 0.055 | 0.0 | 0.003 |
| `dock` | 0.005 | 1.10 | 1.06 | 0.060 | 0.18 | 0.007 | 0.07 | 0.0 | 0.006 |
| `menu` | 0.004 | 1.08 | 1.11 | 0.110 | 0.26 | 0.004 | 0.10 | 0.0 | 0.0 |
| `toast` | 0.005 | 1.09 | 1.10 | 0.100 | 0.24 | 0.005 | 0.09 | 0.0 | 0.0 |
| `backdrop` | 0.003 | 1.04 | 1.03 | 0.070 | 0.05 | 0.002 | 0.0 | 0.0 | 0.0 |

Fallback `background-effect` blocks in `config/niri/tahoe-phase0.kdl` must match the material profile they name in their comment. Today that applies to `panel`, `menu`, and `toast` fallback layer rules.

## Surface Recipes

| surface | namespace | material | radius | fallback | interaction/materialAlpha |
| --- | --- | --- | ---: | --- | --- |
| TopBar | `tahoe-topbar` | `panel` | 18 | `FillTopBar` / `StrokeTopBar` | interaction `0.0`, materialAlpha follows bar opacity |
| Dock | `tahoe-dock` | `dock` | 24 | `FillDock` / `StrokeDock` | interaction `dockGlassInteraction`, materialAlpha `1.0`, region clipped to visible height |
| ControlCenter | `tahoe-control-center` | `panel` | 28 | panel fill/stroke via local dark-mode colors | interaction `0.0`; niri owns outer layer motion |
| NotificationToast | `tahoe-notification-toast` | `toast` | 18 | bright panel fill plus inset edge rectangles | interaction and materialAlpha follow `toastMaterialAlpha` |
| Launchpad | `tahoe-launchpad` | `launcher` | 28 | `FillLauncher` / `StrokeLauncher` | interaction/materialAlpha follow opener opacity, or `1.0` under compositor layer animations |
| Spotlight | `tahoe-spotlight` | `pill` for input, `panel` for results | 33 / 18 | pill and bright panel fallbacks | input can use full interaction during open; results follow opacity |
| MenuPopup | `tahoe-menu-popup` | `menu` | 18 | `FillPanelBright` / `StrokePanelBright` | region interaction stays `0.0`; hover belongs to menu rows |
| SettingsPanel | `tahoe-settings-panel` | `panel` | 28 | panel fill/stroke via theme colors | interaction `0.0`; materialAlpha follows panel opacity |

When adding a new visible surface, pick one existing material first. Add a new material only if the surface cannot be expressed by an existing semantic token and the KDL/Rust/settings/fallback/test updates are included in the same change.

## Review Checklist

- Does the QML surface use `TahoeGlass.regions` through `GlassPanel` or `TahoeGlassRegion`?
- Is the material selected from `TahoeGlass.js`, not typed as a raw string in the component?
- Is the radius selected from `TahoeGlass.js` or a documented recipe override?
- If a fallback `background-effect` changed, does it still match the named material profile?
- Did `TahoeGlass.js`, `config/niri/tahoe-phase0.kdl`, `niri/niri-config/src/tahoe_glass.rs`, `NiriSettings.qml`, and `niri_settings_tool.py` stay synchronized?
- Did the change avoid GPU probing, renderer-based behavior switches, and higher default chromatic/refraction values?

## Verification

Run the Phase 9 guardrail:

```sh
python3 -m pytest tahoe-shell/tests/test_tahoe_material_governance.py
```

Run the broader Tahoe glass guardrail before deployment:

```sh
bash scripts/check-tahoe-glass-guardrails.sh
```
