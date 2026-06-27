# Left Sidebar LS12 验收记录

日期：2026-06-27

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/settings/pages/WeatherPage.qml`。
  - 提供自动定位开关（`TahoeListRow` 内置 `TahoeSwitch`）、纬度/经度/城市三个 `TahoeTextField`、立即检测按钮、保存按钮和 °C/°F `TahoeSegmented`。
  - 自动定位开启时禁用手动输入；关闭自动定位时优先使用当前 Weather 服务位置初始化手动覆盖。
  - 手动保存通过 `weather.setLocation()` 更新天气服务并落到 `DesktopSettings.setWeatherLocation()`；无 Weather 服务时回退到 settings setter。
  - “立即检测”调用 `weather.detectLocation()`；手动模式下检测成功后把 Weather 服务返回的位置写入 `DesktopSettings.setWeatherLocation()`。
- 修改 `tahoe-shell/components/SettingsPanel.qml`。
  - 新增 `weatherService` 属性。
  - 注册 `selectedPage === "weather"` 的标题、副标题和 `pageIndex`。
  - 在 `StackLayout` 末尾加入 `Pages.WeatherPage`，避免重排既有页面索引。
- 修改 `tahoe-shell/components/settings/SettingsSidebar.qml`。
  - 新增“天气”入口，使用 Material Icons `U+E2BD` 和 `categoryColor("weather")`。
- 修改 `tahoe-shell/components/settings/SettingsTheme.js`。
  - 新增 `weather` 类别色。
- 修改 `tahoe-shell/shell.qml`。
  - `SettingsPanel` 透传 `weatherService: weather`。
  - 新增 IPC `openWeatherSettings()` → `openSettingsPanel("weather")`。
- 修改 `WeatherTrendCard.qml`、`WeatherCards.qml`、`LeftSidebarWeather.qml`。
  - 透传 `settingsService`，让天气页主温度、趋势卡温度标签和露点等指标随 `weatherTempUnit` 切换。

## 防腐化核对

- 未引入 QtQuick.Controls / Qt.labs / Qt5Compat / GraphicalEffects / QtQuick.Shapes。
- 未使用 `SpringAnimation`。
- 设置持久化只通过 `DesktopSettings` setter；天气刷新只通过 `Weather` 服务 API。
- 对既有设置系统只做页面注册、侧栏按钮和主题色增量；未重排既有页面索引。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  components/settings/pages/WeatherPage.qml

/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  components/settings/SettingsSidebar.qml

/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  components/SettingsPanel.qml

/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  components/settings/pages/WeatherPage.qml components/WeatherTrendCard.qml components/WeatherCards.qml

timeout 8 /usr/lib/qt6/bin/qmlscene -platform offscreen \
  -I /home/wwt/niri/tahoe-shell/components/settings/pages \
  LS12Preview.qml

rg -n "SpringAnimation|import QtQuick\\.Controls|import Qt\\.labs|import Qt5Compat|GraphicalEffects|QtQuick\\.Shapes" \
  components/settings/pages/WeatherPage.qml components/SettingsPanel.qml \
  components/settings/SettingsSidebar.qml components/settings/SettingsTheme.js \
  components/WeatherTrendCard.qml components/WeatherCards.qml components/LeftSidebarWeather.qml shell.qml

git diff --check
```

## 验收结果

- `WeatherPage.qml`、`SettingsSidebar.qml`、`WeatherTrendCard.qml`、`WeatherCards.qml` 的 `qmllint` 退出 0，无输出。
- `SettingsPanel.qml` 的 `qmllint` 退出 0；仅保留该文件既有 `PanelWindow` / `TahoeGlassRegion` / unqualified 解析警告模式。
- 临时 `LS12Preview.qml` offscreen smoke 退出 0，无输出；页面能用假 settings/weather 服务实例化，并跑过单位切换和定位刷新路径。临时文件已删除。
- 禁用依赖和 `SpringAnimation` 审计无命中。
- `git diff --check` 退出 0。

## DoD 核对（路线图 LS12）

- ✅ 设置侧栏出现“天气”入口。
- ✅ `openSettingsPanel("weather")` 和 IPC `openWeatherSettings()` 能路由到天气页。
- ✅ 自动/手动定位切换可用；自动定位开启时手动输入禁用。
- ✅ 手动经纬度/城市保存后调用 `weather.setLocation()`，天气服务立即切换并持久化。
- ✅ 切回自动定位调用 `weather.clearManualOverride()`，随后重新刷新定位。
- ✅ 温度单位写入 `DesktopSettings.setWeatherTempUnit()`，天气页主温度、趋势卡和指标卡跟随单位变化。

## 本机限制

- 本次未在真实 Wayland 桌面会话里做人工目视验收；可重复验证的是 `qmllint`、offscreen 假服务烟测、禁用依赖审计和 `git diff --check`。

## 偏离与理由

- 天气页在 `StackLayout` 末尾注册为 index 16，而侧栏按钮放在 Dock 后面。这样可以避免重排既有页面索引，属于最小增量接入。
- 除路线图要求的“立即检测”按钮外，额外提供了“保存”按钮；原因是手动坐标有三个输入框，显式保存能避免只靠焦点离开触发造成的操作不确定。

## 遗留项

- LS14 端到端验收时需要在真实桌面会话里验证：设置页目视布局、手动坐标切换真实天气数据、断网缓存提示和多屏打开行为。
