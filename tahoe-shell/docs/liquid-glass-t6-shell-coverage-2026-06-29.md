# Liquid Glass T6 Tahoe Shell Coverage

日期：2026-06-29

## 状态

T6 已完成。本文只记录覆盖清单和缺口，不新增代码行为、协议、KDL material 或 QML region。

本轮已完整读取 `tahoe-shell/docs/liquid-glass-niri-glass-forceblur-roadmap-2026-06-28.md`，并按 T6 要求从当前 QML/KDL 实际状态生成清单。

## 扫描命令

覆盖清单以这些命令为准：

```sh
rg -l "TahoeGlass\\.regions" tahoe-shell/components | sort
rg -n "^PanelWindow\\s*\\{" tahoe-shell/components
rg -n "^\\s*material \"|^\\s*match namespace|background-effect \\{" config/niri/tahoe-phase0.kdl
bash scripts/check-tahoe-glass-guardrails.sh
```

`rg -l "TahoeGlass\\.regions" tahoe-shell/components | sort` 当前输出 22 个组件：

```text
tahoe-shell/components/AppMenuPopup.qml
tahoe-shell/components/BatteryPopup.qml
tahoe-shell/components/ClipboardPopup.qml
tahoe-shell/components/ControlCenter.qml
tahoe-shell/components/Dock.qml
tahoe-shell/components/DockAppMenu.qml
tahoe-shell/components/DockWindowMenu.qml
tahoe-shell/components/DynamicIslandOverlay.qml
tahoe-shell/components/FanPopup.qml
tahoe-shell/components/Launchpad.qml
tahoe-shell/components/LeftSidebar.qml
tahoe-shell/components/MenuPopup.qml
tahoe-shell/components/NotificationCenter.qml
tahoe-shell/components/NotificationToast.qml
tahoe-shell/components/ProcessMenu.qml
tahoe-shell/components/SettingsPanel.qml
tahoe-shell/components/Spotlight.qml
tahoe-shell/components/TaskSwitcher.qml
tahoe-shell/components/TopBar.qml
tahoe-shell/components/TrayMenu.qml
tahoe-shell/components/WifiPopup.qml
tahoe-shell/components/WindowOverview.qml
```

实际 `PanelWindow` 中只有 `Wallpaper.qml` 和 `PopupDismissLayer.qml` 没有 `TahoeGlass.regions`；二者都是明确非目标。`Screenshot.qml` 不是 `PanelWindow`，是隐藏 service/action 入口，也不是玻璃目标。

## 覆盖清单

| 组件 | namespace | regions | material | 大面积/全屏 | fallback layer-rule | 结论 |
| --- | --- | ---: | --- | --- | --- | --- |
| `TopBar.qml` | `tahoe-topbar` | 1 | `panel` | full-width layer，内部浮动 bar region | 否 | 目标内；继续保持只给 `barSurface` 建 region。 |
| `Dock.qml` | `tahoe-dock` | 1 | `dock` | bottom layer，内部 dock region | 否 | 目标内；保留 visible-height 裁剪，避免 auto-hide 越界。 |
| `ControlCenter.qml` | `tahoe-control-center` | 1 | `panel` | 中型面板 | 是，panel 组 | 目标内。 |
| `NotificationCenter.qml` | `tahoe-notification-center` | 1 | `panel` | 中型面板 | 是，panel 组 | 目标内。 |
| `LeftSidebar.qml` | `tahoe-left-sidebar` | 1 | `panel` | full-height side panel | 是，panel 组 | 目标内；注意可读性。 |
| `Spotlight.qml` | `tahoe-spotlight` | 2 | `pill` + `panel` | fullscreen overlay，内部 search/results regions | 否 | 目标内；两 region 模型正确。 |
| `Launchpad.qml` | `tahoe-launchpad` | 1 | `launcher` | fullscreen overlay，内部 launcher panel | 否 | 目标内，高风险；T8 已改为 `launcher` material。 |
| `SettingsPanel.qml` | `tahoe-settings` | 1 | `panel` | fullscreen overlay，内部 settings panel | 否 | 目标内，高风险；文本和控件密度最高。 |
| `TaskSwitcher.qml` | `tahoe-task-switcher` | 1 | `menu` | fullscreen overlay，内部 switcher panel | 否 | 目标内；窗口列表变化时注意 region 稳定。 |
| `WindowOverview.qml` | `tahoe-window-overview` | 1 | `panel` | fullscreen overlay，内部 overview panel | 否 | 目标内，高风险；不要把每个窗口缩略图做成 region。 |
| `DynamicIslandOverlay.qml` | `tahoe-dynamic-island` | 1 | `pill` | full-width top layer，动态 capsule region | 否 | 目标内，高风险；尺寸变化频繁。 |
| `MenuPopup.qml` | `tahoe-menu-popup` | 1 | `menu` | 小菜单 | 是，menu/toast 组 | 目标内。 |
| `AppMenuPopup.qml` | `tahoe-application-menu` | 1 | `menu` | 小菜单 | 是，menu/toast 组 | 目标内。 |
| `TrayMenu.qml` | `tahoe-tray-menu` | 1 | `menu` | 小菜单 | 是，menu/toast 组 | 目标内。 |
| `DockAppMenu.qml` | `tahoe-dock-app-menu` | 1 | `menu` | 小菜单 | 是，menu/toast 组 | 目标内。 |
| `DockWindowMenu.qml` | `tahoe-dock-window-menu` | 1 | `menu` | 小菜单 | 是，menu/toast 组 | 目标内。 |
| `ProcessMenu.qml` | `tahoe-process-menu` | 1 | `menu` | 小菜单 | 是，menu/toast 组 | 目标内。 |
| `BatteryPopup.qml` | `tahoe-battery-popup` | 1 | `panel` | 小 popup | 是，小 popup 组 | 目标内。 |
| `WifiPopup.qml` | `tahoe-wifi-popup` | 1 | `panel` | 小 popup | 是，小 popup 组 | 目标内。 |
| `FanPopup.qml` | `tahoe-fan-popup` | 1 | `panel` | 小 popup | 是，小 popup 组 | 目标内。 |
| `ClipboardPopup.qml` | `tahoe-clipboard-popup` | 1 | `panel` | 小 popup | 是，小 popup 组 | 目标内。 |
| `NotificationToast.qml` | `tahoe-notification-toast` | 1 | `toast` | toast card | 是，menu/toast 组 | 目标内。 |

合计：22 个组件声明 `TahoeGlass.regions`，共 23 个 compositor-owned region；`Spotlight.qml` 是唯一的双 region 组件。

## 非目标 surface

| 组件 | 类型 | 原因 |
| --- | --- | --- |
| `Wallpaper.qml` | `PanelWindow` / `tahoe-wallpaper` | 背景层，不是玻璃；不能声明 TahoeGlass region。 |
| `PopupDismissLayer.qml` | `PanelWindow` / `tahoe-popup-dismiss` | 透明点击/遮罩层，不是可见玻璃；mask 只用于点击穿透区域。 |
| `Screenshot.qml` | hidden `Item` service/action | 截图动作入口，不是 layer surface，也没有可见面板。 |

`LockScreen.qml` 走 `WlSessionLockSurface`，不是 T6 的 `PanelWindow` 覆盖范围。它应继续单独评估：安全界面优先保证认证语义、输入稳定和文字可读性，不在本轮纳入 TahoeGlass。

## 高风险 surface

| 组件 | 风险 | 当前记录 |
| --- | --- | --- |
| `Launchpad.qml` | fullscreen overlay + 大 launcher panel；容易出现大 halo、整屏水波或巨大 rim。 | T8 后当前 material 是 `GlassStyle.MaterialLauncher`。如果后续视觉转向 fullscreen/backdrop，应改 `backdrop`。 |
| `WindowOverview.qml` | fullscreen overlay 内含大量窗口缩略图；性能和可读性敏感。 | 只有 overview 主 panel 是 region；缩略图不是 region，保持此边界。 |
| `SettingsPanel.qml` | 文本和控件密度最高，是可读性下限。 | 当前 `panel` material；后续先降 refraction/提高 tint，不加 chromatic。 |
| `DynamicIslandOverlay.qml` | capsule 尺寸和内容状态频繁变化。 | 当前 `pill` material；region 跟随 `islandSurface`，后续继续优先动画内容和 `materialAlpha`，避免无界 geometry。 |

## fallback layer-rule 缺口

当前有 fallback `background-effect` 的 namespace：

- panel 组：`tahoe-control-center`、`tahoe-notification-center`、`tahoe-left-sidebar`。
- 小 popup 组：`tahoe-battery-popup`、`tahoe-wifi-popup`、`tahoe-fan-popup`、`tahoe-clipboard-popup`。
- menu/toast 组：`tahoe-menu-popup`、`tahoe-application-menu`、`tahoe-tray-menu`、`tahoe-dock-app-menu`、`tahoe-dock-window-menu`、`tahoe-process-menu`、`tahoe-notification-toast`。

当前没有 layer-level fallback 的目标组件：

- `TopBar.qml`
- `Dock.qml`
- `Spotlight.qml`
- `Launchpad.qml`
- `SettingsPanel.qml`
- `TaskSwitcher.qml`
- `WindowOverview.qml`
- `DynamicIslandOverlay.qml`

其中 `topbar`、`dock`、`spotlight`、`launchpad` 在 KDL 注释中明确不加 layer-level shadow/glass，避免把大透明容器整块玻璃化。`settings`、`task-switcher`、`window-overview`、`dynamic-island` 也应保持谨慎：若未来需要 fallback，应按真实 region geometry 增加精确规则，不能回到 broad `^quickshell` 或整个 fullscreen surface 玻璃。

## 验收

- `rg -l "TahoeGlass\\.regions" tahoe-shell/components | sort` 的 22 个组件已全部列入覆盖清单。
- 每个可见 launcher/panel/menu/toast/popup 都有明确 material。
- `Wallpaper.qml`、`PopupDismissLayer.qml`、`Screenshot.qml` 已列为非目标并说明原因。
- `Launchpad.qml` 的 `MaterialPanel` 待验证项已由 T8 关闭，当前使用 `MaterialLauncher`。
- `scripts/check-tahoe-glass-guardrails.sh` 通过。
- 本轮没有新增代码行为。
