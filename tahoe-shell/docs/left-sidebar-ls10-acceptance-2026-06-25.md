# Left Sidebar LS10 验收记录

日期：2026-06-27

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/WeatherCards.qml`。
  - 统一 `MetricCard` 内联组件，覆盖 AQI、花粉、湿度、UV、能见度、气压、风况、降水、太阳、月相 10 张指标卡。
  - 移植参考项目的数据逻辑：`aqiSummary` / `pollutantIndex` / `uvLevel` / `windAccent` / `directionLabel` / `visibilityDescription` / 花粉指数阈值。
  - 只读 `weatherService` 已整理数据，不发网络请求、不写设置、不接页面。
- 新增 `tahoe-shell/components/WeatherTrendCard.qml`。
  - 单组件参数化 `mode: "daily" | "hourly"`。
  - `daily` 显示 16 格，高低温双曲线 + 降水概率；`hourly` 显示 24 格，单温度曲线 + 天气图标。
  - 支持 JS 数组和带 `count/get` 的模型输入，供 LS11 直接绑定 Weather 服务数组。

## 防腐化核对

- 未修改 `LeftSidebar.qml`、`shell.qml` 或其它既有文件；LS10 只新增两个组件，接入留给 LS11。
- 未引入 QtQuick.Controls / Qt.labs / Qt5Compat / QtQuick.Shapes / GraphicalEffects。
- 未声明 `TahoeGlassRegion`，没有玻璃几何动画风险。
- 未使用 `SpringAnimation`。
- 卡片样式使用 Tahoe 玻璃语言：radius 18、半透明 fill、内嵌 1px 描边、Material Icons 字形、深浅色 token。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  tahoe-shell/components/WeatherTrendCard.qml

/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  tahoe-shell/components/WeatherCards.qml

rg -n "SpringAnimation|import QtQuick.Controls|import Qt\\.labs|import Qt5Compat|GraphicalEffects|QtQuick.Shapes" \
  tahoe-shell/components/WeatherCards.qml \
  tahoe-shell/components/WeatherTrendCard.qml

git diff --check
```

运行时烟测：

```bash
# 临时新增 tahoe-shell/LS10Preview.qml，实例化 WeatherCards + daily/hourly WeatherTrendCard，
# 用假 weatherService/daily/hourly 数据 offscreen 加载；验收后已删除临时文件。
timeout 8 /usr/lib/qt6/bin/qmlscene -platform offscreen \
  -I /home/wwt/niri/tahoe-shell/components \
  tahoe-shell/LS10Preview.qml
```

## 验收结果

- `qmllint` 两个新文件均退出 0，无输出。
- 防腐化审计无命中。
- `git diff --check` 退出 0。
- offscreen runtime smoke 退出 0，无输出；`WeatherCards`、daily `WeatherTrendCard`、hourly `WeatherTrendCard` 均能用假数据实例化，无运行时绑定/字体赋值警告。
- 临时 `LS10Preview.qml` 已删除；最终工作树只保留 LS10 两个新组件和本验收文档。

## DoD 核对（路线图 LS10）

- ✅ 各卡片显示对应数值并带 `--` fallback：AQI/花粉走空气质量数据，湿度/UV/能见度/气压/风/降水走当前与今日预报，太阳走 sunrise/sunset/sunshine，月相按日期估算。
- ✅ 趋势卡横向 `Flickable`：daily/hourly 都按 `contentWidth = count * itemWidth` 生成横向内容，超过视口即可滚动。
- ✅ daily 16 格：`mode:"daily"` 时 `maxItems:16`。
- ✅ hourly 24 格：`mode:"hourly"` 时 `maxItems:24`。
- ✅ 不使用参考项目 MD3/Controls/Lottie/SVG/Shapes，视觉层为 Tahoe 自有实现。

## 本机限制

- LS10 按路线图不接入 `LeftSidebar.qml`，真实页面组装在 LS11。因此本任务未做桌面会话内的人工目视滚动验收。
- 本机可重复验证的是 `qmllint`、防腐化审计、offscreen 组件实例化。真实滚动手感和最终页面排版留到 LS11 组装天气页后一起目视确认。

## 偏离与理由

- 月相没有 Open-Meteo 字段来源，`Weather.qml` 当前也未请求 moonrise/moonset。LS10 用日期近似计算月相名和照明比例，避免扩大 LS03 数据契约；若后续需要精确月出/月落，应在天气服务任务之外单独扩展数据源。
- 趋势卡没有移植参考项目的空气质量/风况子标签。路线图 LS10 的 DoD 只要求 daily/hourly 横向趋势卡，保留单一趋势模式更贴合 Tahoe KISS 约束。

## 遗留项

- LS11 接入天气页后，做真实桌面目视确认：卡片数值、横向滚动、深浅色对比、与 WeatherBackground/主温度区域的整体排版。
