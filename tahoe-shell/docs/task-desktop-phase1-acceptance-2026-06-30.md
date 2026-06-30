# Tahoe 任务桌面反腐化路线图阶段 1 验收记录

日期：2026-06-30

状态：完成

范围：`task-desktop-research-roadmap-2026-06-30.md` 阶段 1：`shell.qml` 弹层状态反腐化。本阶段只做低风险结构收敛，不做锁屏、缩略图 provider、命令 provider、搜索、设置写入或 XWayland 兼容性改造。

## 修改范围

- 修改 `tahoe-shell/shell.qml`。
- 新增 `closeLaunchpadAndSpotlight()`，集中处理同时关闭 Launchpad 和 Spotlight 的重复逻辑。
- 新增 top bar popup helper：
  - `topBarPopupOpenValue(popupName)`
  - `setTopBarPopupOpen(popupName, open)`
  - `topBarPopupOpenForName(popupName, screen)`
  - `toggleTopBarPopup(popupName, screen, anchorRect)`
  - `openTopBarTrayMenu(item, screen, anchorRect)`
- 迁移 TopBar 的重复 toggle 逻辑：
  - app menu
  - application menu
  - control center
  - notification center
  - battery popup
  - Wi-Fi popup
  - fan popup
  - clipboard popup
  - tray menu open path
- Dynamic Island 打开 control center / notification center 的路径改为复用 `toggleTopBarPopup()`。
- task switcher、window overview、settings panel、left sidebar、screenshot、Dock app menu、Dock window menu 中重复的 `launchpadOpen=false` + `spotlightOpen=false` 改为调用 `closeLaunchpadAndSpotlight()`。

## 保留的行为边界

- 未拆除或替换任何 popup 组件。
- 未移除任何 property、signal、component binding 或 IPC 方法。
- 未改变 TopBar、Dock、LeftSidebar、ProcessMenu 的信号名。
- 未重新设计多屏逻辑；仍使用既有 `screenName()`、`topBarPopupScreenName`、`topBarPopupAnchorRect`、`navigationOpenFor()` 和各自的 `*OpenFor(screen)` 判断。
- Dock app menu、Dock window menu 的 same-app / same-window toggle 判断保留在原调用点。
- ProcessMenu 的 open、dismiss layer 和侧边栏关闭联动保持原路径。
- Launchpad / Spotlight 自身的互斥 toggle 保持原语义，没有改成通用 top bar popup。

## 验证命令

```bash
git diff --check -- tahoe-shell/shell.qml
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules tahoe-shell/shell.qml
timeout 12s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell show
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call tahoe dynamicIslandGetState
rg -n "var wasOpenHere = shell\\.topBarPopupOpenFor|shell\\.prepareTopBarPopup\\(modelData|shell\\.closeTopBarPopups\\(\\\"(appMenu|applicationMenu|controlCenter|notificationCenter|battery|wifi|fan|clipboard)\\\"" tahoe-shell/shell.qml
```

## 验证结果

- `git diff --check -- tahoe-shell/shell.qml` 退出 0。
- `qmllint` 退出 0。
  - 输出仍包含既有 `modelData` unqualified warnings；本阶段不做全文件 lint 整理。
- repo-path Quickshell smoke 到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
  - 运行时仍有既有 interceptor warning、`Qt.application.font` 只读 warning、notification server 已被当前会话占用 warning、portal app id warning。
  - 未出现 QML load failure 或新增 helper 运行时报错。
- repo-path IPC `show` 仍暴露：
  - `openSettings`
  - `openAbout`
  - `openSystemHealth`
  - `openWeatherSettings`
  - `openDynamicIslandSettings`
- repo-path IPC `dynamicIslandGetState` 返回 `resting_time`，确认临时实例 IPC 可调用。
- 源码核对中，指定的 TopBar popup toggle 重复模式已无剩余匹配；`rg` 对旧模式返回无匹配。
- 临时 repo-path Quickshell 实例已停止，未留下额外 `/home/wwt/niri/tahoe-shell` 实例。

## 验收清单

- TopBar app menu / application menu / control center / notification center / battery / Wi-Fi / fan / clipboard 的 toggle 调用都进入 `toggleTopBarPopup()`。
- 打开任一上述 top bar popup 时仍调用 `closeLaunchpadAndSpotlight()`。
- Tray menu 打开时仍保存当前 item 和 anchor；关闭路径仍清空 item。
- Dock app menu、Dock window menu、ProcessMenu 的 dismiss 组件和关闭方法未改。
- IPC 打开 settings、health、about、weather、dynamic-island 的方法名和目标页未改。

## 未覆盖项

- 本轮没有真实鼠标点击逐个打开/关闭 TopBar 弹窗；自动验收覆盖 QML 加载、源码路径和 IPC 暴露。真实桌面点击回归应在下一次人工 UI 验收时补做。
- 本轮没有改 niri 配置，因此未运行 `niri validate`。

结论：阶段 1 已完成。下一阶段应进入阶段 2：锁屏入口统一。
