# GOAL-2 验收：可重复触发入口

日期：2026-07-06

范围：补齐常用 surface 的 repeatable trigger path，并记录 layers / screenshot 采样命令。不新增 Wayland protocol，不新增平行控制服务。

## 完成了什么

- 在现有 Quickshell IPC target `tahoe` 上新增 open/close/toggle wrappers。
- wrappers 复用现有 shell state 和 helper：`toggleTopBarPopup`, `closeTopBarPopups`, `prepareTopBarPopup`, `setTopBarPopupOpen`, `spotlightOpen`。
- 为 Control Center、Notification Center、Small Popup、Spotlight 提供 repeatable IPC trigger。
- 为 Toast 明确 repeatable route：真实 desktop notification route；当前 Dynamic Island 开启时 toast layer 会被设计性 suppressed，采样时需要用既有 Dynamic Island IPC 临时关闭并恢复。
- 记录 layers 采样命令和 screenshot 时间点。

## 修改范围

代码修改：

- `tahoe-shell/shell.qml`

新增 helper：

- `ipcScreen()`
- `topBarIpcAnchorRect(screen, slot)`
- `openTopBarPopupForIpc(popupName, slot)`
- `toggleTopBarPopupForIpc(popupName, slot)`
- `closeMotionSamplingSurfaces()`

新增 IPC function：

- Control Center: `openControlCenter`, `toggleControlCenter`, `closeControlCenter`
- Notification Center: `openNotificationCenter`, `toggleNotificationCenter`, `closeNotificationCenter`
- Small Popup: `openBatteryPopup`, `toggleBatteryPopup`, `closeBatteryPopup`, `openWifiPopup`, `toggleWifiPopup`, `closeWifiPopup`, `openFanPopup`, `toggleFanPopup`, `closeFanPopup`, `openClipboardPopup`, `toggleClipboardPopup`, `closeClipboardPopup`
- Spotlight: `openSpotlight`, `toggleSpotlight`, `closeSpotlight`
- Cleanup: `closeMotionSamplingSurfaces`

已有 IPC retained:

- `openTaskSwitcher`, `closeTaskSwitcher`
- `openWindowOverview`, `toggleWindowOverview`, `closeWindowOverview`
- `openLeftSidebar`, `closeLeftSidebar`
- `dynamicIslandSetEnabled`, `dynamicIslandGetSettingsSummary`

## 触发命令矩阵

Assume:

```text
QS=/home/wwt/.local/bin/quickshell
CFG=/home/wwt/.config/quickshell/tahoe
NIRI=/home/wwt/.local/bin/niri
```

The source and deployed Quickshell trees are separate copies. These new commands are available after deploying/reloading Tahoe shell from `tahoe-shell/`.

| Surface | Open | Close | Expected namespace |
| --- | --- | --- | --- |
| Control Center | `$QS ipc -p "$CFG" call tahoe openControlCenter` | `$QS ipc -p "$CFG" call tahoe closeControlCenter` | `tahoe-control-center` |
| Notification Center | `$QS ipc -p "$CFG" call tahoe openNotificationCenter` | `$QS ipc -p "$CFG" call tahoe closeNotificationCenter` | `tahoe-notification-center` |
| Battery Popup | `$QS ipc -p "$CFG" call tahoe openBatteryPopup` | `$QS ipc -p "$CFG" call tahoe closeBatteryPopup` | `tahoe-battery-popup` |
| Wi-Fi Popup | `$QS ipc -p "$CFG" call tahoe openWifiPopup` | `$QS ipc -p "$CFG" call tahoe closeWifiPopup` | `tahoe-wifi-popup` |
| Fan Popup | `$QS ipc -p "$CFG" call tahoe openFanPopup` | `$QS ipc -p "$CFG" call tahoe closeFanPopup` | `tahoe-fan-popup` |
| Clipboard Popup | `$QS ipc -p "$CFG" call tahoe openClipboardPopup` | `$QS ipc -p "$CFG" call tahoe closeClipboardPopup` | `tahoe-clipboard-popup` |
| Spotlight | `$QS ipc -p "$CFG" call tahoe openSpotlight` | `$QS ipc -p "$CFG" call tahoe closeSpotlight` | `tahoe-spotlight` |
| Task Switcher | `$QS ipc -p "$CFG" call tahoe openTaskSwitcher` | `$QS ipc -p "$CFG" call tahoe closeTaskSwitcher` | `tahoe-task-switcher` |
| Window Overview | `$QS ipc -p "$CFG" call tahoe openWindowOverview` | `$QS ipc -p "$CFG" call tahoe closeWindowOverview` | `tahoe-window-overview` |
| Left Sidebar | `$QS ipc -p "$CFG" call tahoe openLeftSidebar` | `$QS ipc -p "$CFG" call tahoe closeLeftSidebar` | `tahoe-left-sidebar` |
| Cleanup | `$QS ipc -p "$CFG" call tahoe closeMotionSamplingSurfaces` | same | idle layer set |

Toast route:

```text
$QS ipc -p "$CFG" call tahoe dynamicIslandGetSettingsSummary
$QS ipc -p "$CFG" call tahoe dynamicIslandSetEnabled false
notify-send -a 'Tahoe motion probe' -t 2500 'Toast probe' 'GOAL-2 toast trigger'
sleep 0.12
$NIRI msg --json layers
# Restore to the value reported by dynamicIslandGetSettingsSummary.
$QS ipc -p "$CFG" call tahoe dynamicIslandSetEnabled true
```

Reason: `NotificationToast.qml` intentionally suppresses `tahoe-notification-toast` while Dynamic Island is enabled. `notify-send` is still the real notification route; disabling Dynamic Island only selects the existing toast presentation path.

## Layers 采样命令清单

For each surface:

```text
$QS ipc -p "$CFG" call tahoe closeMotionSamplingSurfaces
sleep 0.10
$NIRI msg --json layers

$QS ipc -p "$CFG" call tahoe openControlCenter
sleep 0.05
$NIRI msg --json layers
sleep 0.12
$NIRI msg --json layers
sleep 0.25
$NIRI msg --json layers

$QS ipc -p "$CFG" call tahoe closeControlCenter
sleep 0.05
$NIRI msg --json layers
sleep 0.25
$NIRI msg --json layers
```

Replace `openControlCenter` / `closeControlCenter` with the open/close pair from the trigger matrix. For `liquid` or future longer profiles, add a final sample at `max(transform-duration-ms, opacity-duration-ms) + 100ms`.

## Screenshot 采样时间点

For visual acceptance, capture both `layers` and screenshot at:

| Phase | Time |
| --- | --- |
| idle before open | `t=-100ms` |
| first visible frame | `open + 50ms` |
| mid motion | `open + 120ms` |
| settled open | `open + 250ms` for current `balanced`; longer profile uses max duration + 100ms |
| first close frame | `close + 50ms` |
| mid close | `close + 120ms` |
| settled close | `close + 250ms` for current `balanced`; longer profile uses max duration + 100ms |

Suggested capture shape:

```text
grim "$OUT_DIR/<surface>-open-050ms.png"
$NIRI msg --json layers > "$OUT_DIR/<surface>-open-050ms-layers.json"
```

If `grim` is not available, use the existing screenshot command path and record the substitute in that goal's acceptance document.

## 没有做什么

- 没有新增 Wayland protocol。
- 没有新增 IPC daemon 或第二套 shell control service。
- 没有修改 KDL animation parameters。
- 没有修改 motion token values。
- 没有 deploy/reload the running Quickshell process from this repo during this gate。
- 没有做 visual screenshot acceptance；这里只建立 repeatable triggers and sampling commands。

## 复用了哪些现有接口

- Existing Quickshell `IpcHandler { target: "tahoe" }`
- Existing shell popup state: `ShellPopupState.qml`
- Existing shell functions: `toggleTopBarPopup`, `closeTopBarPopups`, `prepareTopBarPopup`, `setTopBarPopupOpen`
- Existing notification route: `notify-send` -> `Notifications.qml` -> `NotificationToast.qml`
- Existing Dynamic Island settings IPC for toast presentation selection
- Existing niri IPC: `niri msg --json layers`

## 是否新增接口

Added functions to the existing `tahoe` IPC target. This is an extension of the existing shell IPC route, not a new protocol or service.

Reason: GOAL-0 proved Control Center, Notification Center, Small Popup, and Spotlight had internal QML click paths but no repeatable automation entry. Reusing the existing `tahoe` target is the narrowest existing interface that can exercise those state paths.

## 运行命令

```text
sed -n '1,460p' tahoe-shell/shell.qml
sed -n '1,230p' tahoe-shell/components/ShellPopupState.qml
sed -n '1,340p' tahoe-shell/components/NotificationToast.qml
sed -n '1,420p' tahoe-shell/services/Notifications.qml
rg -n "ipcScreen|topBarIpcAnchorRect|openControlCenter|openNotificationCenter|openBatteryPopup|openWifiPopup|openFanPopup|openClipboardPopup|openSpotlight|closeMotionSamplingSurfaces" tahoe-shell/shell.qml
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
git diff --check
```

Tooling note: `qmllint` / `qmlformat` were not available on PATH in this environment.

## 剩余风险

- Live verification of the new IPC functions requires deploying/reloading Quickshell from `tahoe-shell/`.
- The synthetic IPC anchor rects are stable sampling anchors, not the exact visual anchor of every physical topbar button.
- Toast sampling changes Dynamic Island enabled state temporarily; testers must restore the previous value reported by `dynamicIslandGetSettingsSummary`.
- Screenshot capture tooling may vary by host; commands above specify timing, not a mandatory image backend.

## 回滚方式

Rollback is removing the IPC helper/functions from `tahoe-shell/shell.qml`, deleting this acceptance document, and reverting the GOAL-2 status row. No KDL or persistent user setting change is required by the source change itself.

