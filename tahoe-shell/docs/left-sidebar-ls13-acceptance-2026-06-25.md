# Left Sidebar LS13 验收记录

日期：2026-06-27

状态：完成

## 修改范围

- `tahoe-shell/components/TopBar.qml` 已完成 LS13 顶栏入口。
  - 增加 `property bool leftSidebarOpen` 和 `signal toggleLeftSidebar()`。
  - 在左侧簇 `niriMenuButton` 后加入 30x24 天气图标按钮。
  - 按钮使用 Material Icons `U+E2BD`（`wb_cloudy`）作为天气字形，打开时使用高亮背景和蓝色图标。
  - 点击按钮发 `root.toggleLeftSidebar()`。
- `tahoe-shell/shell.qml` 已完成 LS13 接线。
  - `TopBar.leftSidebarOpen` 绑定 `navigationOpenFor(leftSidebarOpen, leftSidebarScreenName, modelData)`。
  - `TopBar.onToggleLeftSidebar` 调 `shell.toggleLeftSidebar(modelData)`。
  - `toggleLeftSidebar(screen)` 设置目标屏幕、调用 `closeTopBarPopups("leftSidebar")`，并关闭 launchpad/spotlight。
  - `closeTopBarPopups()` 已把 `leftSidebar` 纳入互斥协调，侧边栏不会进入 top-bar dismiss cutout。

## 防腐化核对

- 未引入 QtQuick.Controls / Qt.labs / Qt5Compat / GraphicalEffects / QtQuick.Shapes。
- 未使用 `SpringAnimation`。
- 顶栏按钮沿用 niri 图标按钮的 `Item + Rectangle + Text + MouseArea` 结构，未重构 TopBar 其它区域。
- 按钮宽度与 niri 按钮一致（30x24），左侧簇仍保留 `clip: true` 与应用名 elide。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  components/TopBar.qml

/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  shell.qml

fc-query --format='%{charset}\n' assets/fonts/MaterialIconsRound.ttf | fold -w 120 | sed -n '1,8p'

rg -n "id: leftSidebarButton|text: \"\\\\ue2bd\"|onClicked: root.toggleLeftSidebar|leftSidebarOpen: shell.navigationOpenFor|onToggleLeftSidebar: shell.toggleLeftSidebar\\(modelData\\)|function toggleLeftSidebar\\(screen\\)" \
  components/TopBar.qml shell.qml

rg -n "SpringAnimation|import QtQuick\\.Controls|import Qt\\.labs|import Qt5Compat|GraphicalEffects|QtQuick\\.Shapes" \
  components/TopBar.qml shell.qml

git diff --check
```

## 验收结果

- `TopBar.qml` 的 `qmllint` 退出 0；仅保留该文件既有 `PanelWindow` / `TahoeGlassRegion` / workspace delegate unqualified 警告模式。
- `shell.qml` 的 `qmllint` 退出 0；仅保留该文件既有 `modelData` unqualified 警告模式。
- `fc-query` 显示字体 charset 包含 `e2bc-e2c4`，覆盖 `U+E2BD`，天气按钮不会落到缺字 fallback。
- LS13 关键接线搜索全部命中。
- 禁用依赖和 `SpringAnimation` 审计无命中。
- `git diff --check` 退出 0。

## DoD 核对（路线图 LS13）

- ✅ 顶栏左侧 niri 图标旁有天气字形按钮。
- ✅ 点击按钮发 `toggleLeftSidebar()` 并由 `shell.toggleLeftSidebar(modelData)` 切换当前屏侧边栏。
- ✅ 按钮打开态通过 `leftSidebarOpen` 高亮。
- ✅ 左侧簇布局沿用 30x24 按钮与应用名 elide，未改变工作区区域结构。
- ✅ 多屏目标通过 `leftSidebarScreenName` 和 `navigationOpenFor()` 约束。

## 本机限制

- 本次未在真实 Wayland 桌面会话里做人工点击/多屏目视验收；可重复验证的是 `qmllint`、字形 charset、静态接线搜索、禁用依赖审计和 `git diff --check`。

## 偏离与理由

- 无。

## 遗留项

- LS14 端到端验收时需要在真实桌面会话里点击顶栏按钮，验证当前屏显示、按钮高亮、多屏切换和左侧簇目视布局。
