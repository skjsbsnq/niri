# LS05 LeftSidebar 容器验收

## 做了什么

- 新增 `components/LeftSidebar.qml`：
  - 左侧三边锚定 `PanelWindow`，`WlrLayershell.namespace: "tahoe-left-sidebar"`。
  - `ExclusionMode.Ignore` + `exclusiveZone: 0`，不挤压工作区。
  - Tahoe 玻璃面板：`TahoeGlassRegion` + 内嵌 1px 描边，未在玻璃面板本体使用 `border`。
  - 纯 QML `Translate.x` 滑入/滑出，`NumberAnimation` 使用 `Motion.panelEnterDuration`/`Motion.panelExitDuration`。
  - `mask: Region` 跟随 `Translate.x`，关闭动画期间不保留全宽透明点击层。
  - 两个标签页：系统 / 天气；当前为 LS05 占位内容，后续 LS06/LS11 替换。
  - `Esc` 和关闭按钮触发 `closeRequested()`。
- 增量修改 `shell.qml`：
  - 新增 `leftSidebarOpen` / `leftSidebarScreenName`。
  - 新增 `toggleLeftSidebar(screen)` / `closeLeftSidebar()`。
  - `closeTopBarPopups(except)` 接入 `leftSidebar` 分支。
  - 新增 IPC：`toggleLeftSidebar` / `openLeftSidebar` / `closeLeftSidebar`。
  - 在每个屏幕 Scope 中实例化 `LeftSidebar`，用 `navigationOpenFor()` 保证只显示在目标屏幕。
- 增量修改 `components/TopBar.qml`：
  - 在左侧簇 niri 图标和当前应用名之间插入天气图标按钮。
  - 按钮绑定 `leftSidebarOpen` 激活态，点击发 `toggleLeftSidebar()`。

## 验收结果

- `git diff --check`：通过。
- `/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules components/LeftSidebar.qml shell.qml`：退出码 0。
  - 输出包含项目既有类型/`modelData` unqualified 静态警告；未出现 LS05 阻断错误。
- `timeout 12s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell`：到达 `Configuration Loaded`。
  - `timeout` 退出 124 为预期；日志里有既有 Dock 动画 interceptor、通知服务已占用、portal app id 警告。
- IPC smoke：
  - `/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell --newest show` 能看到 `toggleLeftSidebar` / `openLeftSidebar` / `closeLeftSidebar`。
  - `openLeftSidebar` 和 `closeLeftSidebar` 调用退出码 0。
- 玻璃安全审计：
  - `components/LeftSidebar.qml` 无 `SpringAnimation`。
  - 滑入动画只作用于内部 `Translate.x`；面板宽高、`PanelWindow` 几何和玻璃安全区未使用弹簧动画。
- 多屏逻辑审计：
  - `toggleLeftSidebar(screen)` 写入 `leftSidebarScreenName`。
  - 每屏实例用 `navigationOpenFor(leftSidebarOpen, leftSidebarScreenName, modelData)` 判断显示。
- 关闭协调审计：
  - 打开其它顶栏弹层会关闭侧边栏。
  - 侧边栏打开时会关闭顶栏弹层、窗口导航面板、Launchpad 和 Spotlight。
- 顶栏入口审计：
  - `TopBar.leftSidebarOpen` 绑定当前屏幕的侧边栏状态。
  - `TopBar.onToggleLeftSidebar` 调用 `shell.toggleLeftSidebar(modelData)`，因此多屏点击只打开当前屏幕侧边栏。

## 本机限制

- 本机已完成运行时加载与 IPC 打开/关闭 smoke；由于当前流程无法采集屏幕画面，玻璃模糊、内嵌描边和 180ms 滑入效果仍需在桌面会话中目视确认。

## 偏离与理由

- LS05 文档原要求“暂用临时按钮或 IPC 触发”，但用户明确指出侧边栏应该由顶栏 niri 图标旁按钮打开。本次提前接入顶栏按钮，范围仍限定为入口信号和按钮本身，不实现 LS06/LS11 的真实内容。

## 遗留项

- LS06 接入系统页真实内容。
- LS11 接入天气页真实内容。
- LS13 后续可转为只做按钮细节复核/清理，不再需要新增主入口。
