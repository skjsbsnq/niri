# Tahoe 左侧边栏（系统栏 + 天气栏）研究结论与串行执行路线图

> 研究对象：参考项目 `/home/wwt/Downloads/quickshell-main` 的左侧边栏（`Modules/Sidebars/Left/`）。
> 目标项目：本仓库 Tahoe shell `/home/wwt/niri/tahoe-shell`（基于 Quickshell/QML 的 niri Wayland 桌面 shell）。
> 立场：参考项目**仅供学习，不修改、不照搬代码**。功能移植，视觉与代码全部用 Tahoe 自身风格重写。
> 范围：只移植 **System（系统栏）** 和 **Weather（天气栏）** 两个标签页；明确**不移植 Info（信息栏）**。
> 工程纪律：**KISS、防腐化、局部重构、可维护性优先**；**严格串行，完成一个任务才能开始下一个**。

---

## 0. 文档定位与阅读对象

本文是「研究文档 + 改进路线图」二合一：前半部分把参考项目与 Tahoe 的架构差异讲透，作为实现期的判定依据；后半部分把工作切成**可独立验收的串行任务**，每个任务都有明确的「完成定义（Definition of Done）」与验收方式。

与 `/home/wwt/.claude/plans/foamy-bubbling-finch.md`（已批准的实现计划）的关系：那份是面向执行的精简蓝图，本文是它的**研究底座与防腐化护栏**——任何实现偏离本文的纪律条款时，以本文为准。

阅读对象：未来接手维护的人（包括未来的自己）。所以写作目标是「看完本文就能独立判断每一步该不该做、做完对不对」。

---

## 1. 目标

- 新增一个贴左边缘、全高度的 `tahoe-left-sidebar` 面板，从左滑入，仅在触发它的那个屏幕显示。
- 两个标签页：**系统**（CPU/GPU 双弧仪表、折线图、进程列表、磁盘、电池）、**天气**（动画背景、当前天气、16 天预报、逐时预报、AQI、花粉、日月等指标卡片）。
- 数据层**自己写**：系统统计用 shell 脚本读 `/proc`/`/sys`；天气用 `curl` 调 Open-Meteo + ipwho.is。不引入参考项目的 C++ 插件。
- 视觉**完全沿用 Tahoe 玻璃语言**：`TahoeGlassRegion` + 双矩形内嵌描边、Material Icons 字体、深/浅色对、`Motion.js` 动效 token。**不用任何 MD3 token、不用 QtQuick.Controls、不依赖 Lottie/SVG 素材**。
- 顶栏入口：在**左侧簇 niri 图标旁边**加一个**天气图标**按钮切换。
- 天气定位：自动 IP 定位 + 设置里的手动覆盖（持久化）。

**非目标**：Info 标签页、参考项目的 MD3 主题生成（matugen）、参考项目的 Lottie 天气动画、参考项目的 gooey 模糊边缘效果、C++ 插件体系。

---

## 2. 研究对象与结论总览

### 2.1 参考项目左侧边栏结构

参考项目是 Quickshell/QML 桌面 shell，左侧边栏由以下文件构成（`Modules/Sidebars/Left/`）：

- `LeftSidebarWindow.qml` —— `PanelWindow` 容器，贴左+上+下，`WlrLayershell.layer: Top`，`ExclusionMode.Ignore`，宽 540，专属键盘焦点，用 `slideOffset` + `Easing.OutBack`（600ms，过冲 0.3）滑入；带 gooey 模糊边缘（`GaussianBlur` + `ThresholdMask`）。
- `LeftSidebarContent.qml` —— 3 标签页（info/sys/weather）+ 内容区切换。
- `SystemView.qml` —— 系统页：双弧仪表（Canvas）、Net/RAM/Load 折线图（Canvas sparkline + 平滑滑入）、属性网格、磁盘/电池卡片、进程列表（过滤/排序/搜索/右键 kill）。
- `WeatherView.qml` —— 天气页：动画背景 + 主温度 + 16 天/逐时趋势卡 + AQI/花粉/湿度/UV/能见度/气压/风/日月 卡片。
- 一组 `Weather*Card.qml`（约 10 个）+ `WeatherBackground.qml`（Canvas 粒子场景，~1250 行）+ `MeteoIcon.qml`（Lottie/SVG）+ `notifications/` 子目录。
- 全局状态在 `Common/WidgetState.qml`（`leftSidebarOpen`/`leftSidebarView`）。

### 2.2 参考项目数据层（C++ 插件，我们不移植）

- `Clavis.Sysmon`（`core/src/sysmon_*.cpp`）读 `/proc`/`/sys`，按 fast(1s)/medium(2s)/slow(5s)/glacial(30s) 四档轮询，发对应信号。
- `Clavis.Weather`（`core/src/openmeteo_client.cpp`/`weather_backend.cpp`/`weather_calculator.cpp`）调 Open-Meteo forecast + air-quality + ipwho.is，30/60 分钟刷新，缓存到 `~/.cache/clavis_weather_cache.json`。
- 这些插件 Tahoe **不存在**，且本仓库 Quickshell 子模块未必注册了它们 → 必须用 Tahoe 已有的 `Process`+`StdioCollector` 模式在 QML+shell 层重写数据层。

### 2.3 Tahoe 现状（与移植相关的部分）

- 入口：`shell.qml` ShellRoot → `Variants { model: Quickshell.screens }` → `Scope { required property var modelData }`，每个面板按屏幕实例化。
- 面板均为 `PanelWindow`（`Quickshell.Wayland`），`WlrLayershell.namespace: "tahoe-*"`。三边锚定范例：Dock `anchors{left,right,bottom}` + `exclusiveZone:98`；TopBar `anchors{left,right,top}` + `exclusiveZone:34`。左侧边栏 → `anchors{left,top,bottom}`。
- 玻璃系统：`import "TahoeGlass.js" as GlassStyle`，声明 `TahoeGlass.regions: [TahoeGlassRegion{...}]`。合成器侧 material 在 `config/niri/tahoe-phase0.kdl` 的 `tahoe-glass { material "panel" {...} }` 已定义，**玻璃侧边栏自动获得 panel 材质，无需新增 material**。QML 侧只提供 tint/fallback 权重（`FillPanel`/`StrokePanel` 等）。
- 双矩形描边约定：玻璃表面 `Rectangle` **自身不加 `border`**（居中 1px 描边会因大圆角逐化露出近直角瑕疵），改用一个内嵌 `Rectangle { anchors.margins:1; radius: parent.radius-1; border.color: glassStroke; border.width:1 }`。Dock/TopBar/ControlCenter 一致。
- 颜色：`darkMode ? "#d01d1f24" : GlassStyle.FillPanel` 等；文字 `textPrimary` 深 `#f5f7fb`/浅 `#1d1d1f`、`textSecondary` 深 `#c8d0d8`/浅 `#991d1d1f`、`textTertiary` 深 `#9da7b1`/浅 `#731d1d1f`；强调蓝 `#2c9cf2`/`#0b6bd3`；危险红 `#ff453a`/`#e54857` 一类。Material Icons 字体 `font.family: "Material Icons"`（`shell.qml` 已 `FontLoader` 注册）。
- 动效：`Motion.js` token（`panelEnterDuration=180`、`panelExitDuration=140`、`emphasizedDecel=OutCubic`、`elementResizeDuration=180`）。`shell.useSpring` 控制弹簧。
- **关键安全约束**：凡喂给 `TahoeGlassRegion` 几何的属性（`panel.x/y/width/height`、`implicitHeight`）**必须 `NumberAnimation`，禁止 `SpringAnimation`**——弹簧过冲会把玻璃区域顶出安全区崩溃（`ControlCenter.qml` 224-230 注释）。
- 状态上提：`shell.qml` 持有各 `bool <panel>Open` + 屏幕名追踪 + `closeTopBarPopups(except)` 协调器。顶栏弹层用 `topBarPopupOpenFor(open, screen)` + `prepareTopBarPopup`；导航式（SettingsPanel/WindowOverview/TaskSwitcher）用 `navigationScreenName()`/`navigationOpenFor(open, targetScreenName, screen)`。
- 数据取法模式：
  - **A. FileView+JsonAdapter**（持久化设置）：`DesktopSettings.qml`、`Appearance.qml`。
  - **B. Quickshell 内建服务**：UPower（`Battery.qml`）、Pipewire、MPRIS、Networking、Bluetooth。
  - **C. Process+StdioCollector**（shell 脚本/IPC）：`SystemStatus.qml`（一次性探针）、`Windows.qml`（niri 事件流）、`Controls.qml`（brightnessctl）。
  - **D. `Quickshell.execDetached`**（fire-and-forget）。
- 滚动模式：无可复用滚动组件；`NotificationCenter` 用 `Flickable{clip;StopAtBounds;Column{Repeater}}`，`ClipboardPopup` 用 `ListView{model;delegate;clip;spacing;StopAtBounds}`。delegate：`Rectangle` radius 14、hover `#54ffffff`/rest `#34ffffff`、描边 `#44ffffff`、`MouseArea hoverEnabled`。
- 右键菜单模式：无 QtQuick.Controls；`DockWindowMenu.qml` 用 `PanelWindow` + 背景 `MouseArea` 消失层 + 玻璃 `Rectangle` + `ColumnLayout` 的 `MenuRow` 内联组件，每个 `onActivated` 调 `closeRequested()`，位置经 `PopupGeometry.js`。
- 设置系统：页面在 `components/settings/pages/*.qml`，`SettingsPanel.qml` 用 `StackLayout`（`currentIndex: pageIndex(selectedPage)`）装载，`SettingsSidebar.qml` 用 `Controls.TahoeSidebarButton` 列出，类别色在 `SettingsTheme.js` 的 `categoryColor()`。控件：`TahoeSwitch`/`TahoeTextField`/`TahoeSegmented`/`TahoeButton`/`TahoeSection` 等。
- 现有相关服务：`Battery.qml`（UPower，可复用）、`FanControl.qml`、`SystemStatus.qml`（健康探针，**不含** CPU/内存/网络用量统计）。**无任何天气或系统用量组件**。

### 2.4 总结结论

1. 数据层必须自建（QML+shell），不能依赖参考的 C++ 插件。
2. 视觉层完全用 Tahoe 玻璃语言重写，不用 MD3 token、不用 QtQuick.Controls、不用 Lottie/SVG。
3. 滑入动画用**纯 QML `transform: Translate` + `NumberAnimation`**（照搬 Dock 显隐），不改 kdl、不依赖合成器 layer-rule、不依赖 `compositorLayerAnimations` 设置——最低风险、最易调试。
4. 文件粒度比参考更粗：参考的 ~22 个天气文件在 Tahoe 里收成 ~7 个（MD3 token 驱动的细粒度拆分对 Tahoe 无意义；Tahoe 卡片共享同一种玻璃卡片样式，适合内联 `component`）。
5. 天气图标用 Material Icons 字形，避免 Lottie/SVG 素材依赖。
6. 顶栏入口放左侧簇 niri 图标旁、用天气字形——已与用户确认。

---

## 3. Tahoe 集成架构

### 3.1 新增组件（`components/`）

| 文件 | 职责 | 复用参考 |
|---|---|---|
| `LeftSidebar.qml` | `PanelWindow` 容器：三边锚定、玻璃区域、纯 QML `Translate` 滑入 + `mask: Region`、2 标签页栏、装载两个视图（始终构造、`visible:` 切换）。 | 合并 `LeftSidebarWindow`+`LeftSidebarContent` |
| `LeftSidebarSystem.qml` | 系统页：内联 `component DualArcGauge`（Canvas 弧）、折线图 Canvas + 火花线历史、属性网格、`RootCard`+`BatteryCard`、进程 `ListView` + JS 过滤/排序。 | `SystemView.qml` |
| `LeftSidebarWeather.qml` | 天气页：`WeatherBackground` + 固定头部 + `Flickable` + 主温度 + 趋势卡 + 指标卡网格。 | `WeatherView.qml` |
| `WeatherBackground.qml` | 移植 Canvas 粒子场景，darkMode 调色板，可见性守门 Timer，内联落叶 delegate。 | `WeatherBackground.qml` |
| `WeatherCards.qml` | 内联 `component MetricCard` 覆盖 AQI/花粉/湿度/UV/能见度/气压/风/降水/日月，移植各卡片数据逻辑。 | 合并 ~10 个 `Weather*Card.qml` |
| `WeatherTrendCard.qml` | 参数化横向 `Flickable` 趋势卡，`mode:"daily"|"hourly"`。 | 合并 `Daily/HourlyForecastTrendCard` |
| `MeteoIcon.qml` | Material Icons 字形渲染（`Text`+`WeatherCodes.materialIcon`），区分日夜。 | `MeteoIcon.qml` |
| `ProcessMenu.qml` | 进程右键菜单（复制 PID/名称/命令、结束/强制结束），照 `DockWindowMenu.qml`。 | `SystemView.qml` 的 `Menu` |
| `WeatherCodes.js` | WMO code → 文字/slug/Material-Icons-字形 三张表（`.pragma library`）。 | `weather_calculator.cpp` 映射 |

### 3.2 新增服务（`services/`）

| 文件 | 职责 |
|---|---|
| `SystemStats.qml` | 流式 `Process` + 内联循环 shell 脚本输出带标签 JSON；暴露 cpu/温度/gpu/内存/网络/负载/频率/风扇/uptime/磁盘/进程 属性 + fast/medium/slow 信号。 |
| `Weather.qml` | `curl` `Process` 请求 ipwho.is + Open-Meteo forecast/air-quality；解析→缓存→属性；10 分钟刷新；手动覆盖接 `settingsService`。 |

### 3.3 现有组件修改（最小侵入）

- `shell.qml`：加 `leftSidebarOpen`/`leftSidebarScreenName` 属性；`closeTopBarPopups(except)` 加 `leftSidebar` 分支；声明两个新服务；`Variants` 的 `Scope` 里按屏幕实例化 `LeftSidebar`；接 `onToggleLeftSidebar`。
- `components/TopBar.qml`：加 `signal toggleLeftSidebar()` + `property bool leftSidebarOpen`；左侧簇 niri 图标后加天气字形按钮。
- `services/DesktopSettings.qml`：`JsonAdapter` 加 5 个天气属性 + setter + sanitize 校验。
- `components/SettingsPanel.qml`：`pageIndex()`/`pageTitle()`/`pageSubtitle()` + `StackLayout` 加天气页。
- `components/settings/SettingsSidebar.qml`：加天气 `TahoeSidebarButton`。
- `components/settings/SettingsTheme.js`：`categoryColor()` 加 `weather` 色。

### 3.4 不修改的边界（防腐化护栏）

- **不动** `TahoeGlass.js`/`Motion.js`/`PopupGeometry.js`（复用，不改）。
- **不动** `Battery.qml`（原样复用）。
- **不动** `Dock.qml`/`ControlCenter.qml`/`NotificationCenter.qml` 等既有面板（只参照其模式）。
- **不动** `config/niri/tahoe-phase0.kdl`（核心计划用纯 QML 动画，不需要 layer-rule；合成器 `material "panel"` 已存在）。
- **不引入** QtQuick.Controls、`Qt5Compat.GraphicalEffects`（除非天气背景确需，且仅限该文件）、Lottie 模块、matugen/MD3 主题。

---

## 4. 数据源映射

### 4.1 系统统计（`SystemStats` shell 脚本，Tahoe 自有）

| 指标 | 来源 | 解析 | 节奏 |
|---|---|---|---|
| CPU % | `/proc/stat` 首行 | `(user+nice+system+irq+softirq+iowait+steal)` 增量 / 总增量 ×100 | fast 1s |
| 内存 % / 已用 / 总量 | `/proc/meminfo` | `(MemTotal-MemAvailable)/MemTotal×100`；GB = kB/1048576 | fast 1s |
| 网络下行/上行 Bps | `/proc/net/dev` | 非 `lo` 接口 rx/tx 字节增量求和 / 经过秒数 | fast 1s |
| 负载 1/5/15、运行/总任务 | `/proc/loadavg` | 字段 0/1/2；字段 3 按 `/` 拆 | medium 2s |
| 核心温度 | `/sys/class/hwmon/*/temp*_input` | 匹配 `coretemp`/`k10temp`/`x86_pkg_temp`，/1000 | medium 2s |
| CPU 频率 GHz | `/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` | /1e6 | medium 2s |
| GPU 温度/占用 | `nvidia-smi` 或 sysfs | 启动检测：`nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits`；否则 `/sys/class/drm/card*/device/gpu_busy_percent` + amdgpu/i915/radeon/nouveau hwmon 温度；都没有→0/0 | medium 2s |
| 风扇 RPM | `/sys/class/hwmon/*/fan1_input` | 第一个命中 | slow 5s |
| 进程 top50 | `ps -eo pid,user,uid,pcpu,rss,comm,args --sort=-pcpu \| head -51` | → `{pid,name,cpuPercent,memKB,cmdline,uid}` | medium 2s |
| 磁盘 % / 已用 / 总量 | `df /` | 用量 %、GB | slow 10s |
| uptime | `/proc/uptime` | → `"Xd Yh"`/`"Xh Ym"`/`"Xm"` | slow 10s |

> 用 `ps` 而非遍历 `/proc`：可移植、更省、规避参考项目注释里警告的 `QQuickItem::polish()` loop 风险。全部用 `command -v`/`[ -r ]` 守卫（照 `SystemStatus.have()`）。

**输出协议**：脚本循环输出带标签 JSON 行：`{"c":"fast","cpu":..,"ram":..,"netD":..,"netU":..}\n`、`{"c":"medium","load1":..,"procs":[..]}\n`、`{"c":"slow","disk":..,"up":".."}\n`。QML 用流式按行解析（保留半行缓冲），逐行 `JSON.parse` → 赋属性 → 发对应信号。

> ⚠️ `StdioCollector.onStreamFinished` 只在进程退出时触发，循环脚本永不退出。必须用按行增量解析，不能依赖 `onStreamFinished`。

### 4.2 天气（`Weather` 服务，Open-Meteo 契约）

端点（已对照 `core/src/openmeteo_client.cpp` 核实）：

- **预报**：`https://api.open-meteo.com/v1/forecast`
  `timezone=auto`、`timeformat=unixtime`、`latitude`/`longitude`（6 位小数）、`models=best_match`、`forecast_days=16`、`past_days=1`、`windspeed_unit=ms`、`daily=temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,sunshine_duration,uv_index_max,relative_humidity_2m_mean,dew_point_2m_mean,pressure_msl_mean,cloud_cover_mean,visibility_mean`（按需裁剪）、`hourly=temperature_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,is_day,relative_humidity_2m,dew_point_2m,pressure_msl,cloud_cover,visibility`、`current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,relative_humidity_2m,dew_point_2m,pressure_msl,cloud_cover,visibility`、`minutely_15=precipitation`。
- **空气质量**：`https://air-quality-api.open-meteo.com/v1/air-quality`
  `timezone=auto`、`timeformat=unixtime`、`latitude`/`longitude`、`forecast_days=7`、`past_days=1`、`hourly=pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen`。
- **定位**：`https://ipwho.is/?fields=success,latitude,longitude,city,region,country`。

调用：`curl -fsS --max-time 8 '<url>'`，`JSON.parse` 解析，把 Open-Meteo 并行数组 zip 成对象数组，缓存到 `stateDir/weather-cache.json`，失败回退缓存（`status:"stale"`）或 `status:"error"`。刷新 10 分钟一次。

### 4.3 WMO 天气码映射（`WeatherCodes.js`）

- **文字**（移植 `weather_calculator.cpp::weatherText`）：0→晴、1→大致晴朗、2→局部多云、3→阴、45→雾、48→冻雾、51/53/55→毛毛雨、56/57→冻毛毛雨、61/63/65→雨、66/67→冻雨、71/73/75→雪、77→雪粒、80/81/82→阵雨、85/86→阵雪、95→雷暴、96/99→雷暴伴冰雹。
- **slug**（移植 `MeteoIcon.slugForCode`，区分日夜）：`clear-day`/`clear-night`/`partly-cloudy-day`/.../`thunderstorms-night-hail`，供 `WeatherBackground` 场景分类用。
- **Material Icons 字形**（Tahoe 新增）：按 WMO 码 + 日夜映射到 Material Icons 码点（如晴日 `light_mode`、晴夜 `clear_night`/`bedtime`、云 `cloud`、雨 `rainy`、雪 `ac_unit`/`weather_snowy`、雷暴 `thunderstorm`、雾 `foggy`）。码点在实现时对照 `assets/fonts/MaterialIconsRound.ttf` 核实后硬编码。

### 4.4 火花线历史归属

历史数组（30 采样点）+ `smoothMax` EMA + `slideProgress` 滑入动画**放在系统视图**，不放服务（表现层关注点，与 Canvas 绘制紧耦合；服务只做无状态数据泵）。视图 `Connections{target: systemStats; onFastDataChanged: pushHistory(...)}`。

---

## 5. 明确不迁移

- **Info 标签页**（系统摘要 + 通知列表）——用户明确不要。
- **MD3 主题**（`Appearance.qml` 的 `m3*` token、matugen 生成、`colLayer0..4` 层级色、`colWeatherCardSurface` 等）——Tahoe 用自己的玻玻璃色。
- **gooey 模糊边缘**（`GaussianBlur`+`ThresholdMask`）——Tahoe 玻璃由合成器材质处理，不需要。
- **Lottie/SVG 天气图标**——用 Material Icons 字形替代。
- **C++ 插件**（Sysmon/Weather）——QML+shell 重写。
- **`Easing.OutBack` 过冲滑入**——Tahoe 用 `OutCubic` 180ms，与 Dock 一致，更克制。
- **`QtQuick.Controls`**（`Menu`/`MenuItem`/`TextField`/`ToolButton` 等）——Tahoe 全程不用，右键菜单和输入都手搓。
- **参考的 `StyledListView`/`StyledFlickable`/`StyledButtonGroup`**——带 MD3 依赖，Tahoe 用原生 `ListView`/`Flickable` + 内联组件。

---

## 6. 工程纪律（KISS / 防腐化 / 局部重构 / 可维护性）

这是本文的**硬性约束**，实现期任何偏离都需在此处增补理由。

### 6.1 KISS

- 每个新文件**只做一件事**，能在三句话内说清职责。
- 能复用就**不新建**：玻璃常量、动效 token、`Battery.qml`、`PopupGeometry.js`、设置控件、滚动/菜单/按钮模式一律复用。
- 数据层用最朴素的方式：shell 脚本 + JSON 行 + `JSON.parse`。不引入解析库、不搞协议缓冲。
- 文件粒度服从「同一种样式 → 内联 `component`，独立大单元 → 独立文件」。天气背景因 ~1250 行 Canvas 而独立；指标卡片因共享同一种卡片样式而内联到一个 `WeatherCards.qml`。
- 默认值要「无网络/无 GPU/无电池也能优雅退化」，不为罕见路径堆复杂度。

### 6.2 防腐化

- **不污染既有文件**：对 `shell.qml`/`TopBar.qml`/`DesktopSettings.qml`/`SettingsPanel.qml`/`SettingsSidebar.qml`/`SettingsTheme.js` 的改动**只做增量**（加属性、加 case、加按钮、加 setter），不重排既有逻辑。
- **不引入新依赖**：不引 QtQuick.Controls、不引 Lottie、不引 matugen、不引第三方 QML 库。`Qt5Compat.GraphicalEffects` 仅在 `WeatherBackground` 确需时用，且局限在该文件并注释说明。
- **不复制粘贴既有代码**：参照模式时写「参照 XXX.qml 的 Y 模式」注释，不整段抄；数据脚本自己写。
- **玻璃安全**：喂给 `TahoeGlassRegion` 几何的属性一律 `NumberAnimation`，禁 `SpringAnimation`；微交互若用弹簧，必须守在 `shell.useSpring` 后且只作用于非几何属性。
- **命名**：新文件用 `LeftSidebar*`/`Weather*` 前缀，服务用 `SystemStats`/`Weather`，与既有 `tahoe-*` namespace、`Settings*` 风格一致。中英文混用规则：**用户可见文案与代码注释用中文**（与项目既有中文一致），**标识符/路径/token 用英文**。
- **不绕过设置持久化**：天气定位只通过 `DesktopSettings` 的 setter 落盘，不自己写文件。

### 6.3 局部重构

- 本路线图**只新增 + 最小增量改动**，不重构既有面板。若实现中发现某个既有模式（如右键菜单）值得抽取成共享组件，**不在本计划内做**——记入「后续增强池」，避免范围蔓延。
- 例外：若 `SettingsPanel.qml`/`SettingsSidebar.qml` 的页面注册机制需要小幅调整才能接入天气页，仅做**接入所需的最小改动**，不动其他页面。

### 6.4 可维护性

- 每个新文件顶部写**职责注释**（参照 `Battery.qml`/`SystemStatus.qml` 的头部注释风格）。
- 数据脚本里每个指标**注明来源文件与解析公式**（参照 `SystemStatus.probeScript()` 的逐行注释密度）。
- 复杂视图（系统页/天气背景）写**结构分节注释**（`// --- Section N: ... ---`，参照 `ControlCenter.qml`/`SystemView.qml`）。
- 魔数（宽度 540、历史 30 点、刷新 10 分钟、超时 8s 等）提为 `readonly property`，不散落字面量。
- 每个任务有**完成定义 + 验收**，做完即记入 acceptance 文档（沿用项目 `*-acceptance-<日期>.md` 惯例）。

### 6.5 串行规则（硬性）

- **完成一个任务才能开始下一个**。每个任务的「完成定义」未达成前，禁止动下一任务的文件。
- 每个任务结束**必须**：(1) 跑通该任务的验收；(2) 无新增 QML 警告；(3) 玻璃安全审计通过（`grep SpringAnimation` 无违规）；(4) 既有面板回归未坏。
- 任务之间的依赖见 §8 各任务「前置」字段。
- 若某任务验收失败，**修复该任务**，不跳到下一个。

---

## 7. 风险清单

### 风险 1：玻璃区域几何动画崩溃
- **表现**：侧边栏滑入时 niri 崩溃或玻璃错位。
- **原因**：用 `SpringAnimation` 或直接动画 `panel.x/y` 喂给 `TahoeGlassRegion`。
- **对策**：滑入用 `transform: Translate`（不喂几何）+ `NumberAnimation`；玻璃 `interaction/materialAlpha` 绑 `opacity`（`NumberAnimation`），照 Dock。

### 风险 2：流式 JSON 解析丢行/粘包
- **表现**：`SystemStats` 数据偶发错乱或解析报错。
- **对策**：按 `\n` 切行 + 保留半行缓冲；`JSON.parse` 失败的行静默丢弃并计数，不中断。

### 风险 3：进程列表性能
- **表现**：2s 一次 50 进程重建 delegate 卡顿。
- **对策**：`ps --sort` 服务端排序、`head -51` 限量；右键菜单打开时暂停刷新（`procMenuOpen`）；`ListView` model 用长度 int，重建 50 行可接受。

### 风险 4：天气网络失败/无缓存
- **表现**：首次无网时天气页空白。
- **对策**：`status:"error"` + 错误占位文案；有缓存先显示缓存标 `stale`；所有数值绑定带 `--` fallback。

### 风险 5：无 GPU / 无电池
- **表现**：仪表/卡片显示 0 或空白。
- **对策**：`gpuTemp<=0 && gpuUsage<=0` 时隐藏 GPU 仪表，CPU 仪表占满；`batteryService.available` 为假时隐藏电池卡，磁盘卡占满。

### 风险 6：60fps Canvas 耗电
- **表现**：天气页开着时 CPU/GPU 占用高。
- **对策**：`WeatherBackground` 的 `Timer.running` 守门于 `sidebarOpen && currentTab==="weather" && animate`；切走或关闭即停。

### 风险 7：顶栏左侧簇拥挤
- **表现**：左侧簇加了天气按钮后，应用名/工作区被挤压。
- **对策**：天气按钮宽度与 niri 图标一致（30×24），左侧簇 `clip:true` 已有；若仍挤，应用名 `elide` 已有保底。验收时目视确认。

### 风险 8：多屏侧边栏错位
- **表现**：A 屏触发后 B 屏也出现。
- **对策**：`open: navigationOpenFor(leftSidebarOpen, leftSidebarScreenName, modelData)`，切换处理器设 `leftSidebarScreenName`。照 TaskSwitcher/SettingsPanel。

### 风险 9：Material Icons 字形码点不符
- **表现**：天气图标显示成方块或错误字形。
- **对策**：`WeatherCodes.materialIcon` 实现时对照 `MaterialIconsRound.ttf` 实测码点；设 unknown fallback 为 `cloud`。

### 风险 10：范围蔓延
- **表现**：顺手重构既有面板、抽共享组件、加 Info 页。
- **对策**：§6.3 约束；偏离即记「后续增强池」不做。

---

## 8. 串行执行路线图

每个任务格式：**目标 / 前置 / 涉及文件 / 实现要点 / 完成定义（DoD）/ 验收**。
任务编号 `LSxx`（Left Sidebar）。完成一个写一份 `docs/left-sidebar-lsxx-acceptance-2026-06-25.md`。

### LS01 SystemStats 数据服务
- **目标**：新建 `services/SystemStats.qml`，流式输出系统统计。
- **前置**：无。
- **涉及**：`services/SystemStats.qml`（新）；`shell.qml`（仅声明 `SystemStats { id: systemStats }`，先不接视图）。
- **实现要点**：内联循环 shell 脚本（JS 数组 join `\n`，照 `SystemStatus.probeScript()`）；`Process`+流式按行解析；暴露 §4.1 全部属性 + `fastDataChanged`/`mediumDataChanged`/`slowDataChanged` 信号；`command -v`/`[ -r ]` 守卫；进程死亡 2s 重启 Timer；GPU 启动检测一次。
- **DoD**：shell 启动后日志无警告；`fastDataChanged` 每 1s 触发；`cpuUsage`/`ramUsage`/`netDownBps` 数值合理（CPU 0-100、网络非负）；`processes` 含 ~50 条且每条有 pid/name/cpuPercent/memKB。
- **验收**：临时在 `shell.qml` 加一行 `console.log` 打印 `systemStats.cpuUsage`，跑 10s 看日志；或临时绑定到一个 Text 看 1s 刷新。验收后撤掉临时代码。

### LS02 WeatherCodes 映射表
- **目标**：新建 `components/WeatherCodes.js`，三张表 + 三个查询函数。
- **前置**：无（可与 LS01 并行，但为串行纪律，排在 LS01 后）。
- **涉及**：`components/WeatherCodes.js`（新）。
- **实现要点**：`.pragma library`；`text(code)`、`slug(code,isNight)`、`materialIcon(code,isNight)`；unknown fallback。
- **DoD**：三函数对全部 WMO 码（0/1/2/3/45/48/51-57/61-67/71-77/80-82/85/86/95/96/99）有覆盖；`materialIcon(0,false)` 返回的字形能在 Material Icons 字体里渲染（实测码点）。
- **验收**：临时 `Text{font.family:"Material Icons"; text: WeatherCodes.materialIcon(0,false)}` 渲染出太阳图标。

### LS03 Weather 数据服务
- **目标**：新建 `services/Weather.qml`，Open-Meteo 取数 + 缓存 + 定位。
- **前置**：LS02（用 `WeatherCodes.text/slug`）。
- **涉及**：`services/Weather.qml`（新）；`shell.qml`（声明 `Weather { id: weather; settingsService: desktopSettings }`，先不接视图）。
- **实现要点**：`curl` 三端点；`JSON.parse` + zip 并行数组；缓存 `stateDir/weather-cache.json`；10 分钟刷新 Timer；`refresh()`/`detectLocation()`/`setLocation()`/`clearManualOverride()`；`status` 状态机（idle/fresh/stale/error）；`manualOverride` 读 `settingsService`。
- **DoD**：有网时一次 `refresh()` 填充 `currentWeatherCode`/`currentTemperatureC`/`dailyForecast`(16) /`hourlyForecast`/`currentAirQuality`；断网时回退缓存或 `status:"error"`；`locationName` 非空。
- **验收**：临时 console.log 打印 `weather.currentTemperatureC`/`weather.locationName`/`weather.dailyForecast.length`，确认 16。

### LS04 DesktopSettings 天气持久化
- **目标**：`services/DesktopSettings.qml` 加天气属性 + setter + sanitize。
- **前置**：无。
- **涉及**：`services/DesktopSettings.qml`。
- **实现要点**：`JsonAdapter` 加 `weatherLatitude`/`weatherLongitude`/`weatherLocationName`/`weatherManualOverride`/`weatherTempUnit`；`setWeatherLocation(lat,lon,name)`、`clearWeatherLocation()`、`setWeatherTempUnit(u)` 照 `setDynamicIslandEnabled` 模式；`sanitizeState()` 加纬度 [-90,90]、经度 [-180,180] 钳制 + 覆盖项合理性。
- **DoD**：设置文件 `desktop-settings.json` 能落盘并重读；非法值被 sanitize 修正；setter 无变化即返回。
- **验收**：手动调 `desktopSettings.setWeatherLocation(31.23,121.47,"上海")`，读文件确认；重启 shell 确认值保留。

### LS05 LeftSidebar 容器
- **目标**：新建 `components/LeftSidebar.qml`，面板 + 玻璃 + 滑入 + 2 标签页栏（先放占位内容）。
- **前置**：LS01、LS03（服务已就绪，容器先占位引用）。
- **涉及**：`components/LeftSidebar.qml`（新）；`shell.qml`（加属性 + `closeTopBarPopups` 分支 + 按屏幕实例化 + `onToggleLeftSidebar`；暂用临时按钮或 IPC 触发，因 TopBar 改动在 LS13）。
- **实现要点**：`PanelWindow` anchors{left,top,bottom}；`WlrLayershell.namespace:"tahoe-left-sidebar"`；`ExclusionMode.Ignore` + `exclusiveZone:0`；玻璃 `TahoeGlassRegion`（`MaterialPanel`/`RadiusPanel`）+ 双矩形描边；`transform: Translate{x: open?0:-(width+24); Behavior on x{NumberAnimation{duration:Motion.panelEnterDuration; easing:Motion.emphasizedDecel}}}` + `mask: Region`（照 Dock 253-268/316-326）；`Behavior on opacity{NumberAnimation}`；2 标签页栏（系统/天气），切换 `currentTab`；`signal closeRequested()`；Esc 关闭。
- **DoD**：触发 `leftSidebarOpen=true` 后侧边栏从左滑入（180ms OutCubic）、玻璃模糊壁纸、内嵌描边可见；再触发滑出；多屏只在目标屏显示；玻璃安全审计通过。
- **验收**：临时 IPC `toggleLeftSidebar` 触发；目视滑入/滑出；`grep SpringAnimation` 新文件无违规；既有面板开关回归正常。

### LS06 LeftSidebarSystem 系统页
- **目标**：新建 `components/LeftSidebarSystem.qml`，仪表+折线图+网格+磁盘/电池卡+进程列表。
- **前置**：LS05（容器就绪）、LS01（数据）。
- **涉及**：`components/LeftSidebarSystem.qml`（新）；`LeftSidebar.qml`（接入，替换占位）。
- **实现要点**：内联 `component DualArcGauge`（Canvas 弧，移植参考 96-227，配色改 Tahoe）；折线图 Canvas + 视图内历史数组 + `smoothMax` EMA + `slideProgress` 滑入（移植参考 27-94）；Net/RAM/Load 标签切换（用内联 `component SegTab`，不用参考的 `StyledButtonGroup`）；属性网格 `GridCard`；`RootCard`（磁盘）；`BatteryCard`（绑 `batteryService`，无电池隐藏）；进程 `ListView` + `getFilteredProcesses()` JS 过滤/排序/搜索。配色全部 Tahoe，字体 `monoFontFamily` 给数字。
- **DoD**：CPU/GPU 仪表 1s 内动；折线图 30s 填满；标签切换正常；进程列表 ~50 条、排序/搜索/过滤可用；无 GPU/电池时对应项隐藏且其余占满。
- **验收**：目视各项；切换标签；排序点表头；搜索过滤；无电池机器确认电池卡隐藏。

### LS07 ProcessMenu 右键菜单
- **目标**：新建 `components/ProcessMenu.qml` + 接进程 delegate 右键。
- **前置**：LS06。
- **涉及**：`components/ProcessMenu.qml`（新）；`LeftSidebarSystem.qml`（接右键）；`shell.qml`（按 `DockWindowMenu` 模式加 `processMenuOpen`/`processMenuAnchorRect`/`processMenuProc` 状态 + 实例化 `ProcessMenu` + `closeTopBarPopups` 分支）。
- **实现要点**：`PanelWindow` + 背景 `MouseArea` 消失层 + 玻璃 `Rectangle` + `ColumnLayout` 的 `MenuRow`（照 `DockWindowMenu.qml`）；行：复制 PID/名称/完整命令（`Quickshell.execDetached(["wl-copy",...])`）、结束（`kill`）、强制结束（`kill -9`，守 `uid>=1000`）；位置经 `PopupGeometry.js`；打开时置 `procMenuOpen=true` 暂停进程刷新。
- **DoD**：右键进程行弹出菜单于光标处；点「结束」进程下一拍消失；「复制 PID」经 `wl-copy` 可用；点外部/Esc 关闭；强制结束对系统进程（uid<1000）禁用。
- **验收**：实杀一个可重启进程（如 `sleep`）；复制 PID 粘贴验证。

### LS08 MeteoIcon
- **目标**：新建 `components/MeteoIcon.qml`，Material Icons 字形渲染。
- **前置**：LS02。
- **涉及**：`components/MeteoIcon.qml`（新）。
- **实现要点**：`Text { font.family:"Material Icons"; text: WeatherCodes.materialIcon(weatherCode, night); ... }`；接受 `weatherCode`/`night`/`pixelSize` 属性。
- **DoD**：各 WMO 码渲染出合理图标；日夜区分；unknown fallback `cloud`。
- **验收**：用 Repeater 遍历几个码目视。

### LS09 WeatherBackground 动画背景
- **目标**：新建 `components/WeatherBackground.qml`，移植 Canvas 粒子场景。
- **前置**：LS02、LS03、LS08。
- **涉及**：`components/WeatherBackground.qml`（新）。
- **实现要点**：移植参考的 `classifyWeatherType`/粒子系统（云/雨/雪/闪电/流星/落叶/星星/日月）/16ms Timer；`palette()` 加 darkMode 分支（深色下 top/mid/bottom 压暗 ~60%、glow/accent/cloud 去饱和）；Timer `running: visible && animate`；内联落叶 delegate；输入 `weatherCode`/`night`/`windSpeedMs`/`animate`。
- **DoD**：code 61 显示雨粒子；晴夜显示星+流星；雷暴显示闪电；切深色模式配色合理；切走/关闭 Timer 停（CPU 回落）。
- **验收**：切几个天气码目视；切深色模式；关闭侧边栏确认 Timer 停（`top`/日志）。

### LS10 WeatherCards + WeatherTrendCard
- **目标**：新建 `WeatherCards.qml`（内联 MetricCard 覆盖 AQI/花粉/湿度/UV/能见度/气压/风/降水/日月）+ `WeatherTrendCard.qml`（参数化 daily/hourly）。
- **前置**：LS03、LS08。
- **涉及**：`components/WeatherCards.qml`（新）、`components/WeatherTrendCard.qml`（新）。
- **实现要点**：移植参考各卡片的**数据逻辑**（`aqiSummary`/`pollutantIndex`/`uvLevel`/`windAccent`/`directionLabel`/`visibilityDescription` 等，参考 WeatherView.qml 71-211）到卡片内；卡片用 Tahoe 玻璃卡样式（`Rectangle` radius 18、`darkMode?"#28ffffff":"#60ffffff"`、内嵌描边）；趋势卡横向 `Flickable` + Repeater，`mode` 参数化。
- **DoD**：各卡片显示对应数值（带 `--` fallback）；趋势卡横向滚动；daily 16 格、hourly 24 格。
- **验收**：目视各卡数值；横向滚动趋势卡。

### LS11 LeftSidebarWeather 天气页组装
- **目标**：新建 `components/LeftSidebarWeather.qml`，组装背景+头部+Flickable+主温度+趋势+卡片。
- **前置**：LS09、LS10、LS03。
- **涉及**：`components/LeftSidebarWeather.qml`（新）；`LeftSidebar.qml`（接入，替换占位）。
- **实现要点**：`WeatherBackground` + 固定头部（位置名/更新时间/刷新按钮/编辑按钮，Tahoe 样式，编辑按钮开设置页）+ `Flickable`（NotificationCenter 模式）+ 主温度（大字号）+ `WeatherTrendCard`×2 + `WeatherCards` 网格；移植 `fmtTemp`/`currentIsNight`/`updatedText` helper；刷新按钮调 `weather.refresh()`；编辑按钮调 `openWeatherSettings`（LS12 提供）。
- **DoD**：约 2s 后显示位置+温度+图标；背景匹配天气；趋势卡滚动；指标卡有值；刷新按钮工作；断网显示「更新失败」+缓存。
- **验收**：目视全页；点刷新；断网测试。

### LS12 天气设置页
- **目标**：新建 `settings/pages/WeatherPage.qml` + 注册到设置系统。
- **前置**：LS04。
- **涉及**：`components/settings/pages/WeatherPage.qml`（新）；`components/SettingsPanel.qml`（`pageIndex`/`pageTitle`/`pageSubtitle` + `StackLayout`）；`components/settings/SettingsSidebar.qml`（加按钮）；`components/settings/SettingsTheme.js`（`categoryColor` 加 `weather`）；`shell.qml`（IPC `openWeatherSettings`→`openSettingsPanel("weather")`，供 LS11 编辑按钮调用）。
- **实现要点**：`TahoeSection` 包 `TahoeSwitch`（自动定位）+ `TahoeTextField`×3（纬度/经度/城市）+ `TahoeButton`（立即检测）+ `TahoeSegmented`（°C/°F）；自动定位开时禁用输入框；「立即检测」调 `weather.detectLocation()` 后 `setWeatherLocation`。
- **DoD**：设置侧栏出现「天气」入口；进页可切自动/手动；手动输入经纬度后侧边栏天气切换；切回自动重新定位；温度单位生效。
- **验收**：改位置→侧边栏天气变；切回自动→重新定位。

### LS13 顶栏天气按钮
- **目标**：`TopBar.qml` 左侧簇 niri 图标旁加天气字形按钮。
- **前置**：LS05（容器已能用）。
- **涉及**：`components/TopBar.qml`；`shell.qml`（TopBar 实例绑 `leftSidebarOpen` + `onToggleLeftSidebar`；撤掉 LS05 的临时触发）。
- **实现要点**：`signal toggleLeftSidebar()` + `property bool leftSidebarOpen`；左侧簇 `niriMenuButton` 后加按钮（结构照 `niriMenuButton` 的 Item+Rectangle 背景，字形用 `spotlightButton` 那种 Material Icons `Text`，**天气字形**如 `wb_cloudy`/`cloud`，码点实测）；点击 `root.toggleLeftSidebar()`；`shell.qml` 的 `onToggleLeftSidebar`：切换 + 设 `leftSidebarScreenName` + `closeTopBarPopups("leftSidebar")` + 关 launchpad/spotlight。
- **DoD**：顶栏左侧 niri 旁出现天气图标按钮；点击开关侧边栏；按钮激活态高亮；左侧簇不挤掉应用名/工作区。
- **验收**：点按钮开关；多屏切换；目视左侧簇布局未坏。

### LS14 全链路验收与文档
- **目标**：端到端验收 + 写总验收文档。
- **前置**：LS01-LS13 全部完成。
- **涉及**：`docs/left-sidebar-acceptance-2026-06-25.md`（新）。
- **实现要点**：跑 §9 全部冒烟检查；玻璃安全审计；既有面板回归；记已知限制与后续增强池。
- **DoD**：§9 全部通过；无 QML 警告；`grep SpringAnimation` 新文件无违规；既有面板回归正常。
- **验收**：本文 §9 清单逐条 ✓。

---

## 9. 端到端验收清单

1. shell 启动无新增 import / 字形缺失的 QML 警告。
2. 点顶栏左侧 niri 旁的天气按钮 → 侧边栏从左滑入（180ms OutCubic），仅当前屏，玻璃模糊壁纸，内嵌描边可见。
3. 系统页：CPU/GPU 仪表 ~1s 动；折线图 ~30s 填满；Net/RAM/Load 切换；进程 ~50 条、排序/搜索/过滤、右键结束/复制可用；无 GPU/电池时对应项隐藏且其余占满。
4. 天气页：~2s 后位置+温度+图标；背景匹配天气；16 天/逐时趋势滚动；AQI/花粉/湿度/UV/能见度/气压/风/日月 卡片有值。
5. 关闭（按钮/Esc/开别的弹层）→ 滑出；60fps Timer 停（CPU% 回落）。
6. 多屏：A 屏触发仅 A 有；焦点到 B 再触发 → 跑到 B。
7. 手动覆盖：设置→天气→输入经纬度→天气切换；切回自动→重新定位。
8. 断网：点刷新→「更新失败」+缓存留存；恢复→刷新恢复。
9. 玻璃安全：`grep SpringAnimation` 新文件无违规命中。
10. 回归：控制中心/通知中心/Spotlight/Dock 正常开关；侧边栏不在 `topBarDismissOpenFor`。

---

## 10. 后续增强池（不在本计划内）

- 合成器 `slide` layer-rule（`tahoe-left-sidebar`，`style "slide"; edge "left"`）+ `leftSidebarCompositorAnimations` 设置守门，更精致动画（纯增量，niri 原生语法无需重编）。
- 抽共享右键菜单组件（若 `ProcessMenu`/`DockWindowMenu` 模式重复到值得抽取）。
- 天气逐时降水分钟级趋势卡（参考的 `minutelyForecast`）。
- 系统页 GPU 历史折线、进程的 CPU/内存历史迷你图。
- 天气页 cities 多位置切换。
- Info 标签页（若将来需要）。

---

## 11. 当前推荐起点

**从 LS01（SystemStats 数据服务）开始**。它是整条链的数据底座，无前置、可独立验收、风险可控，且能在不碰任何 UI 的前提下先用日志验证数据正确性——符合「完成一个再下一个」与「先验证底层再往上搭」的可维护性原则。

每完成一个 LSxx 任务，写一份 `docs/left-sidebar-lsxx-acceptance-2026-06-25.md`（沿用项目 `*-acceptance-<日期>.md` 惯例），记入「做了什么 / 验收结果 / 偏离与理由 / 遗留项」，再开始下一个。
