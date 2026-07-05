# Left Sidebar LS07 验收记录

日期：2026-06-26

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/ProcessMenu.qml`（316 行）。
  - 进程列表右键菜单：`PanelWindow` + 玻璃面板 + `ColumnLayout` 的 `MenuRow` 列，照 `DockWindowMenu.qml` 模式。
  - 五项：复制进程 ID / 复制名称 / 复制完整命令 / 结束进程 / 强制结束 (SIGKILL)。
  - 配色改 Tahoe 深浅色对（DockWindowMenu 只有浅色硬编码），数字用 `monoFontFamily`。
  - 不引入 `QtQuick.Controls`。
- 修改 `tahoe-shell/components/LeftSidebarSystem.qml`。
  - 新增 `sidebarPanel` 属性（LeftSidebar PanelWindow 引用，用于 `itemRect` 取进程行屏幕坐标）。
  - 新增 `openProcessMenu(proc, anchorRect)` 信号、`processMenuOpen` 属性（shell 驱动，暂停进程刷新）。
  - 新增 `requestProcessMenu(delegateItem)`：经 `sidebarPanel.itemRect(delegateItem)` 算屏幕坐标 anchorRect，发信号给 shell。
  - 进程 delegate 右键 `procMouse.onClicked` 在 `Qt.RightButton` 时调 `requestProcessMenu(procDelegate)`。
  - `Connections.onFastDataChanged`/`onMediumDataChanged` 的暂停刷新判断从 `procSection.procMenuOpen` 改读 `root.processMenuOpen`，并移除 `procSection` 上的预留 `procMenuOpen` 属性（生命周期统一由 shell 掌控）。
- 修改 `tahoe-shell/components/LeftSidebar.qml`。
  - 新增 `openProcessMenuRequested(proc, anchorRect)` 信号、`processMenuOpen` 属性。
  - `LeftSidebarSystem` 实例传 `sidebarPanel: root`、`processMenuOpen: root.processMenuOpen`，`onOpenProcessMenu` 透传给 `root.openProcessMenuRequested`。
- 修改 `tahoe-shell/shell.qml`（纯增量）。
  - 新增状态四件套：`processMenuOpen` / `processMenuScreenName` / `processMenuAnchorRect` / `processMenuProc`（照 dockWindowMenu 模式）。
  - 新增 `prepareProcessMenu(screen, proc, anchorRect)` / `processMenuOpenFor(screen)` / `closeProcessMenu()`。
  - `closeTopBarPopups(except)` 加 `if (except !== "processMenu") closeProcessMenu()` 分支。
  - `closeLeftSidebar()` 顺带 `closeProcessMenu()`（关侧边栏时菜单不悬空）。
  - `LeftSidebar` 实例绑 `processMenuOpen: shell.processMenuOpenFor(modelData)` + `onOpenProcessMenuRequested` 处理器（`prepareProcessMenu` + `closeTopBarPopups("processMenu")` + 置 `processMenuOpen=true`）。
  - 每屏实例化 `ProcessMenu` + 配对 `PopupDismissLayer`（点外部关闭，照 dockWindowMenu 配对）。

## 菜单行为

- **位置**：anchorRect = 进程行屏幕坐标（经 `sidebarPanel.itemRect(delegateItem)`，照 Tray.qml/Dock.qml 的 `anchorRectFor`）。`popupLeft` 对齐进程行左缘（右缘不越屏幕），`popupTop` 出现在进程行下方 + gap（贴底不越界）。经 `PopupGeometry.js`。
- **关闭**：点外部（`PopupDismissLayer` 全屏遮罩 + 挖空菜单区，`onCloseRequested` → `closeProcessMenu`）/ Esc（`focusCatcher.Keys.onEscapePressed`）/ 点菜单面板空白处（菜单自带背景 `MouseArea`）三路并存，照 DoD。
- **层级**：`WlrLayershell.layer: WlrLayer.Overlay`，盖在 `Top` 层的 LeftSidebar 之上（照 Launchpad/TaskSwitcher/SettingsPanel/PopupDismissLayer）。
- **键盘焦点**：`focusable: open` + `onOpenChanged` 里 `Qt.callLater` 给 `focusCatcher.forceActiveFocus()`，承 Esc。

## 命令路径（DoD 实测验证）

| 菜单项 | 命令 | 实测 |
|---|---|---|
| 复制进程 ID | `Quickshell.execDetached(["sh","-c","printf %s \"$1\" | wl-copy","sh",String(pid)])`（照 Search.qml） | `printf %s TEST_PID_12345 \| wl-copy` → `wl-paste` 返回 `TEST_PID_12345` ✓ |
| 复制名称 | 同上，内容 `proc.name` | （同机制） |
| 复制完整命令 | 同上，内容 `proc.cmdline` | （同机制） |
| 结束进程 | `Quickshell.execDetached(["kill", String(pid)])` | `kill <sleep_pid>` 实杀测试 `sleep` 进程，下一拍消失 ✓ |
| 强制结束 (SIGKILL) | `Quickshell.execDetached(["kill","-9", String(pid)])`，守 `uid>=1000` | `kill -9 <sleep_pid>` 实杀 ✓；uid<1000 时菜单行 `enabledRow=false` 禁用（系统进程不可强杀）✓ |

> uid 守卫：`enabledRow: proc.pid > 0 && proc.uid !== undefined && proc.uid !== null && proc.uid >= 1000`。SystemStats 服务把无 uid 的进程 sanitize 为 -1，故无 uid 进程的强制结束行也被禁用（安全）。

## Material Icons 字形码点核实（路线图风险 9 对策）

- 用 `fontTools` 解析 `MaterialIconsRound.ttf` GSUB 连字表，硬编码实测码点：
  - 头部 `terminal`=``；`tag`=``（复制 PID）；`content_copy`=``（复制名称）；`code`=``（复制命令）；`close`=``（结束）；`cancel`=``（强制结束）。
- 风格与项目一致：`\uXXXX` 转义 + 行尾注释字形名（照 TopBar.qml / LeftSidebarSystem.qml）。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules components/ProcessMenu.qml components/LeftSidebarSystem.qml components/LeftSidebar.qml shell.qml
timeout 12s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call openLeftSidebar
# 临时 IPC __ls07PreviewProcessMenu（验收用，已撤除）强制实例化 ProcessMenu 验证加载
rg -n "SpringAnimation" components/ProcessMenu.qml components/LeftSidebarSystem.qml components/LeftSidebar.qml shell.qml
git -C /home/wwt/niri diff --check
# 实杀 + 复制路径：
kill <sleep_pid>; kill -9 <sleep_pid>; printf %s X | wl-copy; wl-paste
```

## 验收结果

- `qmllint`（四文件）退出 0；警告均为项目既有 `[unqualified]` 类型，无 `Error`/`non-existent`/`Type unavailable`/`Cannot assign`。
- `quickshell` smoke 到达 `INFO: Configuration Loaded`；`timeout` 退出 124 为预期（稳定运行，无崩溃）。
- IPC `openLeftSidebar` / `closeLeftSidebar` 退出 0。
- **临时 IPC `__ls07PreviewProcessMenu`**：用合成 proc（`{pid:99999,name:"sleep",uid:1000,cmdline:"sleep 3600"}`）+ 屏幕左上 anchorRect 强制 `processMenuOpen=true`，实例化 ProcessMenu PanelWindow + 玻璃面板 + MenuRow 列，跑 3s：**无** ProcessMenu/process-menu 相关 warning/error（无 `non-existent`、无 `Type unavailable`、无 `ReferenceError`、无 `Cannot assign`）。验收后已撤除该临时 IPC。
- 打开侧边栏实例化 LeftSidebarSystem：无 LS06 回归 warning（LS06 验收基线保持）。
- 剩余唯一 warning 仍为既有 `Qt.application.font` 只读（行号因插入偏移）、Dock WindowButton interceptor、portal app id、notification server 已占用——均已在 LS01/LS05/LS06 验收记录里确认，非本次新增。
- **命令路径实测**（见上表）：`kill` / `kill -9` 实杀测试 `sleep` 进程成功；`wl-copy` → `wl-paste` 内容正确。
- 玻璃安全审计：
  - `components/ProcessMenu.qml` 等四文件无 `SpringAnimation` 命中。
  - ProcessMenu 玻璃面板几何（`panel.x/y/width/height`、`implicitHeight`）无 `Behavior`/弹簧；定位走 `PanelWindow.margins`（由 shell 状态驱动，非动画），照 DockWindowMenu。
- `git diff --check` 通过（无空白错误）。

## DoD 核对（路线图 LS07）

- ✅ 右键进程行弹出菜单于光标附近（进程行屏幕坐标 anchorRect，经 `itemRect` + `PopupGeometry`）。
- ✅ 点「结束」进程下一拍消失（`kill PID`，实测实杀 `sleep` 成功）。
- ✅ 「复制 PID」经 `wl-copy` 可用（实测 `wl-paste` 返回正确内容）。
- ✅ 点外部 / Esc 关闭（`PopupDismissLayer` + `focusCatcher` Esc + 菜单背景 MouseArea 三路）。
- ✅ 强制结束对系统进程（uid<1000）禁用（`enabledRow` 守 uid>=1000；无 uid 进程 sanitize 为 -1 也禁用）。
- ✅ 打开菜单时暂停进程刷新（`processMenuOpen` 回灌 LeftSidebarSystem，`Connections` 跳过 `getFilteredProcesses`）。

## 本机限制

- 本机已完成 qmllint、运行时加载、IPC 开关、临时 IPC 强制实例化 ProcessMenu、命令路径（kill/kill-9/wl-copy）实杀实测；由于当前流程无法采集屏幕画面与无法驱动真实鼠标右键，菜单的实际弹出位置/玻璃模糊/深浅色渲染仍需在桌面会话中目视确认（与 LS05/LS06 同样的运行环境限制）。
- 真实右键进程行 → 弹菜单的端到端目视确认留给桌面会话；本机已用合成 proc + anchorRect 强制实例化验证菜单 QML 加载/绑定无误。

## 偏离与理由

- `procMenuOpen` 从 `procSection`（ColumnLayout）迁移到 `LeftSidebarSystem` 根，并由 shell 驱动。
  - 原因：LS06 把 `procMenuOpen` 作为 `procSection` 预留属性「LS07 会置位」。实现后发现开关生命周期应由 shell 的 `processMenuOpen` 状态掌控（shell 关菜单时才能可靠复位），若留在 `procSection` 需要额外跨对象回写路径。提到根 + shell 驱动后，`Connections` 直接读 `root.processMenuOpen`，结构更单一、无悬空状态。功能等价：菜单开 → 暂停刷新，菜单关 → 恢复刷新。
- ProcessMenu 用 `WlrLayer.Overlay`（而非 DockWindowMenu 的默认 Top）。
  - 原因：DockWindowMenu 弹在 `Top` 层的 Dock 上，默认 Top 即可；ProcessMenu 要盖在 `Top` 层的 LeftSidebar 之上，必须 Overlay，照 Launchpad/TaskSwitcher/SettingsPanel/PopupDismissLayer 同样盖侧边栏面板的约定。
- ProcessMenu 支持 darkMode（DockWindowMenu 没有）。
  - 原因：菜单弹在支持深浅色的侧边栏之上，硬编码浅色会在深色下违和；用 LS06 的 Tahoe 色 token（`textPrimary`/`textSecondary`/`dangerRed`/`rowHover`）做深浅色对，与系统页视觉一致。玻璃材质仍用 `MaterialMenu`/`FillPanelBright`（照 DockWindowMenu，合成器侧统一）。

## 遗留项

- 桌面会话目视确认：右键进程行的实际弹出位置、玻璃模糊、深浅色渲染、点外部/Esc 关闭手感。
- LS08 起进入天气页链路（MeteoIcon / WeatherBackground / WeatherCards / LeftSidebarWeather）。
- 后续增强池（路线图 §10）：若 ProcessMenu 与 DockWindowMenu 的 MenuRow/Separator 模式重复到值得抽取，可抽共享组件——本计划内不做。
