# Liquid Glass T10 Menu, Toast, Dynamic Island Route

日期：2026-06-29

## 状态

T10 已完成。菜单、小弹窗、toast 和 Dynamic Island 继续走 `GlassPanel` / `TahoeGlass.regions`，由 niri compositor 拥有真实玻璃材质；QML 只声明 material、radius、region bounds 和进出场 alpha。

## 本轮决策

- 菜单类统一使用 `MaterialMenu` 和 `RadiusMenu`，不新增菜单专用 raw shader 参数。
- 小弹窗类继续使用 `MaterialPanel`，但半径统一为 `RadiusPopup`，避免文字密集 popup 吃更强的 menu/pill profile。
- `NotificationToast.qml` 使用独立 `toastMaterialAlpha` 驱动 card opacity、`interaction`、`materialAlpha` 和 region 生命周期；即使开启 compositor layer animations，toast 关闭时 compositor 材质也会淡出到 0，再释放 region。
- `DynamicIslandOverlay.qml` 继续使用 `MaterialPill`，但将 swipe preview width、target height、left 和 radius clamp 到当前 layer surface 内，避免服务侧异常宽度或快速变形造成 region 越界。

## 本轮改动

- `tahoe-shell/components/NotificationToast.qml`
  - 新增 `toastMaterialAlpha` 和 `toastGlassActive`。
  - `materialAlpha` / `interaction` 不再在 compositor layer animation 模式下固定为 `1`，而是跟随 toast enter/exit。
  - `visible` 和 `regionEnabled` 在 alpha 降到阈值前保持 active，避免关闭瞬间留下满强度 blur snapshot。
- `tahoe-shell/components/DynamicIslandOverlay.qml`
  - 新增 `clampInt()`。
  - `capsuleTargetWidth` clamp 到 `screenWidth`。
  - `capsuleTargetHeight` clamp 到 layer surface 高度预算。
  - `capsuleTargetLeft` clamp 到 `[0, screenWidth - capsuleTargetWidth]`。
  - `capsuleTargetRadius` clamp 到当前 width/height 的半径上限，同时保留 `GlassStyle.RadiusPill` token 起点以满足 guardrail。
- 菜单类和小弹窗类已符合 T10 要求：
  - `MenuPopup.qml`
  - `AppMenuPopup.qml`
  - `TrayMenu.qml`
  - `DockAppMenu.qml`
  - `DockWindowMenu.qml`
  - `ProcessMenu.qml`
  - `BatteryPopup.qml`
  - `WifiPopup.qml`
  - `FanPopup.qml`
  - `ClipboardPopup.qml`

## 保留的不变量

- 不改 TahoeGlass Wayland 协议。
- 不改 shader。
- 不新增 material 名称。
- 不新增 raw shader 参数。
- 不新增直接 `BackgroundEffect` / `blurRegion` 调用。
- `chromatic` 仍为 `0.0`，菜单和 toast 不引入文字彩边。
- 小 popup 不拆分额外 glass region。
- Dynamic Island region bounds 只走 bounded `NumberAnimation`，不使用 spring 驱动几何。

## 验证

已通过：

```sh
bash scripts/check-tahoe-glass-guardrails.sh
./niri/target/debug/niri validate -c config/niri/tahoe-phase0.kdl
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
cargo test -p niri-config tahoe_glass --quiet
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/components/NotificationToast.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/MenuPopup.qml tahoe-shell/components/AppMenuPopup.qml tahoe-shell/components/TrayMenu.qml tahoe-shell/components/DockAppMenu.qml tahoe-shell/components/DockWindowMenu.qml tahoe-shell/components/ProcessMenu.qml tahoe-shell/components/BatteryPopup.qml tahoe-shell/components/WifiPopup.qml tahoe-shell/components/FanPopup.qml tahoe-shell/components/ClipboardPopup.qml
```

`qmllint` 退出码为 `0`；输出仍包含既有 qmltypes 限制导致的 `PanelWindow` / `TahoeGlass` unresolved warnings，以及旧有 unqualified/modelData/property-override/unused-import warnings。

本轮未做 live 截图验收：当前运行的 Tahoe shell / niri live 配置不一定等同于仓库路径，避免覆盖用户当前会话。菜单、toast、Dynamic Island 的实机截图和关闭残影检查应在 T13 视觉基线流程中补采。
