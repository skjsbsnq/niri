# Left Sidebar LS11 验收记录

日期：2026-06-27

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/LeftSidebarWeather.qml`。
  - 组装 `WeatherBackground`、固定天气头部、主温度区、daily/hourly `WeatherTrendCard` 和 `WeatherCards` 指标网格。
  - 绑定 `Weather` 服务的当前位置、更新时间、当前天气、风速、日夜、daily/hourly 预报、空气质量等数据。
  - 刷新按钮调用 `weather.refresh()`；编辑按钮发 `openWeatherSettingsRequested()`，具体天气设置页注册留给 LS12。
  - 加入 `fresh/stale/error/updating` 状态文案、断网/缓存 banner、无数据占位和底部更新进度条。
- 修改 `tahoe-shell/components/LeftSidebar.qml`。
  - 将天气 tab 的占位页替换为 `LeftSidebarWeather`。
  - 透传 `weatherService/settingsService/sidebarOpen/active/darkMode/monoFontFamily`。
  - 删除不再使用的天气占位组件和 `weatherSummary()`。
- 修改 `tahoe-shell/shell.qml`。
  - 接住 `LeftSidebar.openWeatherSettingsRequested` 并调用 `openSettingsPanel("weather")`；LS12 注册天气页后该入口即可落到真实页面。

## 防腐化核对

- 未引入 QtQuick.Controls / Qt.labs / Qt5Compat / GraphicalEffects / QtQuick.Shapes。
- 未使用 `SpringAnimation`。
- 天气页不声明 `TahoeGlassRegion`，没有新增玻璃几何动画风险。
- 只接入 LS11 需要的容器与 shell 信号；未注册设置页、未改设置侧栏，避免越过 LS12。
- 天气背景 Timer 由 `sidebarOpen && active` 守门，切走天气 tab 或关闭侧边栏会停。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  tahoe-shell/components/LeftSidebarWeather.qml

/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  tahoe-shell/components/LeftSidebar.qml

rg -n "PlaceholderPane|weatherSummary|SpringAnimation|import QtQuick.Controls|import Qt\\.labs|import Qt5Compat|GraphicalEffects|QtQuick.Shapes" \
  tahoe-shell/components/LeftSidebar.qml \
  tahoe-shell/components/LeftSidebarWeather.qml \
  tahoe-shell/shell.qml

git diff --check
```

运行时烟测：

```bash
# 临时新增 tahoe-shell/LS11Preview.qml，实例化 LeftSidebarWeather，
# 用假 weatherService/settingsService 数据 offscreen 加载；验收后已删除临时文件。
timeout 8 /usr/lib/qt6/bin/qmlscene -platform offscreen \
  -I /home/wwt/niri/tahoe-shell/components \
  tahoe-shell/LS11Preview.qml
```

## 验收结果

- `LeftSidebarWeather.qml` 的 `qmllint` 退出 0，无输出。
- `LeftSidebar.qml` 的 `qmllint` 退出 0；仅保留该文件既有的 `PanelWindow`/`TahoeGlassRegion` 类型解析与 unqualified 警告模式。
- 防腐化审计无命中。
- `git diff --check` 退出 0。
- offscreen runtime smoke 退出 0，无输出；天气页能用假数据实例化，雨天背景、主温度、daily/hourly 趋势卡和指标网格能同时加载。
- 临时 `LS11Preview.qml` 已删除。

## DoD 核对（路线图 LS11）

- ✅ 显示位置、更新时间、当前温度、天气文案和主天气图标；无数据时显示占位，更新失败时显示错误/缓存状态。
- ✅ `WeatherBackground` 绑定当前 WMO 码、日夜和风速，并由 `sidebarOpen && active` 控制动画。
- ✅ 16 天趋势卡和逐时趋势卡接入 `WeatherTrendCard`，支持横向滚动。
- ✅ AQI/花粉/湿度/UV/能见度/气压/风/降水/日月指标接入 `WeatherCards`。
- ✅ 刷新按钮调用 `weather.refresh()`，更新中按钮禁用并显示底部进度条。
- ✅ 断网/失败状态通过 `status:"error"` 或 `status:"stale"` 显示「更新失败」/「显示缓存」提示。

## 本机限制

- 本次未在真实 Wayland 桌面会话里做人工目视验收；可重复验证的是 `qmllint`、防腐化审计、`git diff --check` 和 offscreen 假数据运行烟测。
- 天气设置页属于 LS12；LS11 已把编辑入口接到 `openSettingsPanel("weather")`，但真实天气设置页面注册仍待 LS12。

## 偏离与理由

- 主温度和趋势卡在 `weatherTempUnit:"f"` 时做了 Fahrenheit 转换；`WeatherCards` 内部仍按 LS10 既有摄氏文案显示露点等温度，避免在 LS11 扩大 LS10 组件契约。全局单位一致性应在 LS12 设置页联动时统一处理。

## 遗留项

- LS12：注册天气设置页后，验证编辑按钮落到真实天气设置页面。
- LS14：在真实桌面会话做天气页目视验收，包括背景动效、滚动手感、断网缓存和深浅色对比。
