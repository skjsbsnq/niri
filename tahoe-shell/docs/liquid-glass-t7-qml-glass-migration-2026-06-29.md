# Liquid Glass T7 QML Glass Migration

日期：2026-06-29

## 状态

T7 已完成代码迁移。业务组件不再直接声明 `TahoeGlassRegion`，统一通过 `GlassPanel.region` 暴露给 `TahoeGlass.regions`。

## 本轮改动

- 扩展 `tahoe-shell/components/GlassPanel.qml`：
  - 保留 `material`、`radius`、`blur`、`shadow`、`interaction`、`materialAlpha`。
  - 增加 `regionClip`、`regionEnabled`、`regionItem`，同时兼容已有 `glassClip`、`glassEnabled`。
  - 继续支持 item region 和显式 rect region。
- 迁移仍手写 `TahoeGlassRegion + Rectangle` 的组件：
  - `AppMenuPopup.qml`
  - `BatteryPopup.qml`
  - `ClipboardPopup.qml`
  - `DockAppMenu.qml`
  - `DockWindowMenu.qml`
  - `DynamicIslandOverlay.qml`
  - `FanPopup.qml`
  - `LeftSidebar.qml`
  - `NotificationCenter.qml`
  - `NotificationToast.qml`
  - `ProcessMenu.qml`
  - `SettingsPanel.qml`
  - `TaskSwitcher.qml`
  - `TrayMenu.qml`
  - `WifiPopup.qml`
  - `WindowOverview.qml`
- 已经使用 `GlassPanel` 的组件保持该路径：
  - `ControlCenter.qml`
  - `Dock.qml`
  - `Launchpad.qml`
  - `MenuPopup.qml`
  - `Spotlight.qml`
  - `TopBar.qml`

## 保留的不变量

- `TahoeGlass.regions` 覆盖仍为 22 个组件、23 个 compositor-owned region。
- `Spotlight.qml` 保留两个 region：search pill 和 results panel。
- `Dock.qml` 保留 visible-height 显式裁剪逻辑。
- `LeftSidebar.qml`、`SettingsPanel.qml`、`TaskSwitcher.qml`、`WindowOverview.qml` 保留显式 rect 模式，继续让 region 跟随原 opacity/transform 语义。
- `NotificationToast.qml` 保留原紧急状态 accent 描边。
- `DynamicIslandOverlay.qml` 保留动态 radius 和 bounded geometry animation。
- 没有新增 `BackgroundEffect` import 或 `blurRegion` 调用。
- 没有新增协议、KDL raw shader 参数或 niri 行为。

## 验证

已通过：

```sh
scripts/check-tahoe-glass-guardrails.sh
rg -n "TahoeGlassRegion|BackgroundEffect|blurRegion|tahoeGlassMaterial|tahoeGlassRadius" tahoe-shell/components tahoe-shell/shell.qml
rg -o "TahoeGlass\\.regions" tahoe-shell/components/*.qml | cut -d: -f1 | sort | uniq -c
```

验证结果：

- guardrail 通过。
- `TahoeGlassRegion` 只剩 `GlassPanel.qml` 内部声明。
- `BackgroundEffect`、`blurRegion`、旧 `tahoeGlassMaterial/tahoeGlassRadius` 业务组件引用均为 0。
- `TahoeGlass.regions` 文件数保持 22。

未完成本机截图验证：当前执行环境没有 `quickshell` 和 `qmllint` 可执行文件，且没有可复用的 Tahoe shell 图形会话上下文。视觉截图应在有 Quickshell/niri Tahoe 会话的环境中继续按 T13 基线流程补采。
