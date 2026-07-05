# Left Sidebar LS06 验收记录

日期：2026-06-26

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/LeftSidebarSystem.qml`（约 1246 行）。
  - 系统标签页内容视图：CPU/GPU 双弧仪表、Net/RAM/Load 折线图、属性网格、磁盘卡、电池卡、进程列表。
  - 全部 Tahoe 玻璃语言：卡片 `radius 14~18`、内嵌描边（卡片自身 `border`）、深/浅色对、Material Icons 字形、`monoFontFamily` 给数字。
  - 不引入 `QtQuick.Controls`、不引入 MD3 token、不引入 Lottie/SVG。
- 修改 `tahoe-shell/components/LeftSidebar.qml`。
  - 新增 `batteryService` / `monoFontFamily` 属性。
  - 系统占位 `PlaceholderPane` 替换为 `LeftSidebarSystem`，传入 `systemStats` / `batteryService` / `darkMode` / `monoFontFamily`。
  - `PlaceholderPane` 内联组件保留（天气页仍用，待 LS11 替换）。
- 修改 `tahoe-shell/shell.qml`。
  - `LeftSidebar` 实例新增 `batteryService: battery` 与 `monoFontFamily: shell.monoFontFamily`。
  - 纯增量，未改既有 `leftSidebarOpen` / `toggleLeftSidebar` / `closeTopBarPopups` 逻辑。

## 视图结构（对应参考 SystemView.qml，数据逻辑移植、视觉全 Tahoe 重写）

- **Section 0**：主题色 token（`cardFill`/`cardStroke`/`rowHover`/`textPrimary`/`textSecondary`/`textTertiary`/`accentBlue`/`dangerRed` + 折线多色 `colorNetDown`/`colorNetUp`/`colorRam`/`colorLoad1/5/15`/`colorCpu`/`colorGpu`/`colorDisk`/`colorBattery`），照 LeftSidebar/ControlCenter。
- **Section 0.5**：容量/历史魔数提为 `readonly property`（`historyLen=30`、`processRowHeight=38`、`processLimit=50`、`highCpuThreshold=5.0`、`highRamThresholdKB=1048576`）。
- **Section 1**：折线历史数组（视图内 30 采样点）+ `smoothMaxNet`/`smoothMaxLoad`（峰值 ×1.2 + `Behavior` NumberAnimation 600ms 缓动）+ `slideProgress` 滑入动画（`NumberAnimation`，非弹簧）。
- **Section 2**：`Connections{target: systemStats}` 接 `onFastDataChanged`/`onMediumDataChanged`，push 历史、重算 `smoothMax`、按当前标签触发 `slideAnim`、刷新进程过滤列表。
- **Section 3**：`formatBytes`/`formatMemKB`/`numOr`/`fixed`/`gpuAvailable`/`batteryAvailable` helper。
- **Section 4**：主布局 `ColumnLayout`：
  - 4.1 双弧仪表（内联 `component DualArcGauge`，Canvas 移植参考几何，配色改 Tahoe；无 GPU 时第三格用「CPU 频率/负载」占位，CPU 仪表始终占第一格）。
  - 4.2 折线图标签（内联 `component SegTab`，手搓不用参考的 `StyledButtonGroup`）。
  - 4.3 折线图 Canvas + 右上角实时数值（内联 `component ChartStat`）。
  - 4.4 属性网格（内联 `component GridCard`：风扇/频率/任务/运行时间）。
  - 4.5 磁盘卡（`RootCard`）+ 电池卡（`BatteryCard`，无电池时 `visible: batteryAvailable()`）。
  - 4.6 进程列表（`procSection` ColumnLayout：分类标签 + 手搓搜索框 + 表头排序 + `ListView`）。
- **Section 5**：内联组件定义。

## 数据接入

- 只读 `services/SystemStats.qml`（id: `systemStats`）暴露的属性与 `fastDataChanged`/`mediumDataChanged`/`slowDataChanged` 信号。
- 历史折线、`smoothMax`、`slideProgress` 均为表现层关注点，放视图内（与 Canvas 绘制紧耦合），服务只做无状态数据泵（照路线图 §4.4）。
- 电池卡绑 `services/Battery.qml`（`batteryService.percentage`/`stateText`/`timeText`/`healthText`/`charging`）。

## 进程列表

- `getFilteredProcesses()` JS：分类（全部/用户 UID≥1000/系统 UID<1000）+ 搜索（name/pid/cmdline）+ 排序（CPU/内存/PID，升降序），照参考 `SystemView.getFilteredProcesses`。
- `model: procSection.filteredList`（JS 数组）+ `delegate { required property var modelData }`，照 `NotificationCenter` Repeater 模式（避免 int model + `index` 上下文属性触发 "index is not defined"）。
- CPU/内存高亮胶囊：`cpuPercent > 5.0` 或 `memKB > 1GiB` 染 `dangerRed` 半透明。
- 右键 `MouseArea` 预留 `acceptedButtons: Qt.LeftButton | Qt.RightButton`，右键事件已消费但不弹菜单——`ProcessMenu` 接入留待 LS07（照路线图串行纪律，不越界实现）。
- `procSection.procMenuOpen` 预留属性，LS07 打开右键菜单时置位以暂停刷新。

## Material Icons 字形码点核实（路线图风险 9 对策）

- 用 `fontTools` 解析 `assets/fonts/MaterialIconsRound.ttf` 的 GSUB 连字表，得到字形名→码点映射，硬编码实测码点（非猜）。
- 该字体是经典 Material Icons 集（非 Material Symbols），部分参考用名不在字体里，用同义字形替代并注释说明：
  - `download`=``、`upload`=``、`memory`=``、`speed`=``。
  - `mode_fan` 不在字体 → 用 `air`=`` 代风扇。
  - `hard_drive` 不在字体 → 用 `storage`=`` 代磁盘。
  - `memory_alt` 不在字体 → 用 `developer_board`=`` 代 CPU 频率。
  - `account_tree`=``、`schedule`=``、`leaderboard`=``、`search`=``。
  - `battery_full`=``、`battery_charging_full`=``、`arrow_upward`=``、`arrow_downward`=``。
- 风格与项目一致：`\uXXXX` 转义 + 行尾注释字形名（照 TopBar.qml `` // wb_cloudy）。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules components/LeftSidebarSystem.qml components/LeftSidebar.qml shell.qml
timeout 15s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call openLeftSidebar
rg -n "SpringAnimation" components/LeftSidebarSystem.qml components/LeftSidebar.qml
git -C /home/wwt/niri diff --check
```

## 验收结果

- `qmllint`（三文件）退出 0；警告均为项目既有 `[unqualified]` 类型（`root.xxx`/`s()` 访问、`onXChanged` 信号处理器），与 ControlCenter/NotificationCenter 同类，非 LS06 阻断；无 `Error`/`non-existent`/`Type unavailable`。
- `quickshell` smoke 到达 `INFO: Configuration Loaded`；`timeout` 退出 124 为预期（稳定运行，无崩溃）。
- IPC `openLeftSidebar` / `closeLeftSidebar` 退出码 0。
- 打开侧边栏强制实例化系统页 + SystemStats 数据流跑 5s：**无** `LeftSidebarSystem` 相关 warning/error（无 `index is not defined`、无 `non-existent`、无 `Type unavailable`、无 `ReferenceError`）。
- 剩余 7 类唯一 warning 全为既有（Dock WindowButton `magnification`/`bounceOffset` interceptor、portal app id 注册、notification server 已占用、`Qt.application.font` 只读），均已在 LS01/LS05 验收记录里确认，非本次新增。
- 玻璃安全审计：
  - `components/LeftSidebarSystem.qml` 无 `SpringAnimation` 命中。
  - `LeftSidebarSystem` 不声明 `TahoeGlassRegion`、不动画几何；`Behavior` 仅作用于 `smoothMaxNet`/`smoothMaxLoad`/`slideProgress`（数据属性，NumberAnimation）与 `color`（ColorAnimation），均非玻璃几何。
- `git diff --check` 通过（无空白错误）。

## DoD 核对（路线图 LS06）

- ✅ CPU/GPU 仪表随 fast/medium 数据动（`onMValChanged`/`onSValChanged` `requestPaint`）。
- ✅ 折线图 30 采样点历史 + 滑入动画（`slideAnim` NumberAnimation，fast 1s / medium 2s）。
- ✅ Net/RAM/Load 标签切换（`SegTab` → `currentChartTab` → `chartCanvas.requestPaint`）。
- ✅ 进程列表 ≤50 条、分类/排序/搜索可用（`getFilteredProcesses` JS）。
- ✅ 无 GPU 时第三格用「CPU 频率/负载」占位（`gpuAvailable()` 守门）；无电池时电池卡 `visible: batteryAvailable()` 隐藏，磁盘卡仍占满。
- ✅ 配色全 Tahoe、数字用 `monoFontFamily`、无 QtQuick.Controls/MD3/Lottie/SVG。

## 本机限制

- 本机已完成 qmllint、运行时加载、IPC 开关、打开侧边栏强制实例化系统页的 smoke；由于当前流程无法采集屏幕画面，双弧仪表绘制、折线图填满动画、进程列表目视排版仍需在桌面会话中目视确认（与 LS05 同样的运行环境限制）。
- 本机无独显时 `gpuAvailable()` 为假，GPU 仪表自动让位给「CPU 频率/负载」格，需在有 GPU 的机器上目视确认 GPU 仪表正常。

## 偏离与理由

- 进程态属性（`procTabIdx`/`sortCol`/`sortAsc`/`searchText`/`filteredList`）放在 `procSection`（ColumnLayout）上而非 `root`，并把 `onXChanged` 处理器也放在 `procSection` 内。
  - 原因：参考 SystemView 即把进程态挂在进程区对象上；若属性在 `root` 而处理器写在 `procSection` 内，QML 会因 `procSection` 上无该属性而报 `Cannot assign to non-existent property "onXChanged"`（实测首次 smoke 即此错）。同对象属性 + 处理器是正确结构。
- 进程 delegate 用 `model: filteredList`（JS 数组）+ `required property var modelData`，而非参考的 `model: filteredList.length` + `index` 上下文属性。
  - 原因：int model + delegate 内 `index` 上下文属性在数据刷新时触发 `ReferenceError: index is not defined`（实测 smoke 命中）。`NotificationCenter` 已用 JS 数组 model + `modelData` 模式，更稳。功能等价：delegate 仍拿到同一条目。
- `mode_fan`/`hard_drive`/`memory_alt` 三个字形不在 `MaterialIconsRound.ttf`（经典 Material Icons 集），用 `air`/`storage`/`developer_board` 同义字形替代并注释。
  - 原因：路线图 §4.3/风险 9 要求「码点实测后硬编码」；实测确认上述三字不在字体，挑语义最近的同集字形替代，避免出现方块。

## 遗留项

- LS07：`ProcessMenu` 右键菜单（复制 PID/名称/命令、结束/强制结束）。`procMouse` 右键事件已消费并留接入点，`procMenuOpen` 预留属性就绪。
- LS11：天气页真实内容替换 `PlaceholderPane`。
- LS13：顶栏天气按钮细节复核（入口已在 LS05 提前接入）。
- 桌面会话目视确认：双弧仪表绘制、折线图填满动画、进程列表排版、GPU 仪表（需有 GPU 机器）。
