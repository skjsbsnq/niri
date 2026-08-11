# A3 审查记录

日期：2026-08-11
子代理数：2（轮1 双 REJECT → 全部修复 → 复跑全量 + 真机冒烟复核）

## 各子代理结论

### 子代理 1（Linnaeus：约束合规 / 数据刷新 / 生命周期）
- 结论：REJECT
- CONFIRMED：
  - C1：`WidgetHost.qml:41,56` `hostVisible = root.visible` 且 `visible: true` 硬编码，
    全仓无任何代码把 host 置为不可见 → 「宿主隐藏时刷新停止」判据无可执行触发路径；
    SystemStats 门控退化为「小部件存在性门控」（小部件在场即常驻）。
- PLAUSIBLE：
  - P1：execution-plan §2.4「无新增稳定 PID/Timer」与 roadmap 自身方案（SystemStats 复用 +
    日历分钟 Timer）字面冲突，需定验收口径。
  - P2：日历 Timer 恢复后沿用遗留 interval，`now` 最多滞后 ~60s（当前 hostVisible 恒真不可达）。
  - P3：`Component.onDestruction` 调 `systemStats.setWidgetDemand` 可能引用已销毁对象。
  - P4：天气 `_liveHasData` 仅凭 `status fresh/stale` 判真 → 空数组时显示 0°。
  - P5：跨零点后今日高低温/逐时条最多滞后一个服务刷新周期（10 分钟）。
  - P6：超小屏（高 <540px）网格纵向溢出。
  - P7：overflowCount 口径失真（多屏假阳性 + 单屏双计）。
  - P8：多屏同名 screenKey 共享配置段（A2 已知遗留）。
  - 附：pytest 见 1 例 `test_control_center_morph_monotonic` 失败（期望 300 得 312，
    与 A3 零交集，疑环境抖动；本轮复跑 1098 全绿未复现）。

### 子代理 2（Kepler：视觉 / macOS 观感 + 对抗性正确性）
- 结论：REJECT
- CONFIRMED：
  - C1：天气大温度双度符号「24°°C」（`WeatherWidget.qml:103-106,199-212`）；高低温柔单位
    不一致（`:232`）。
  - C2：日历 42 格横向越界 12px（`CalendarWidget.qml:47` cellW 用 root.width/7，
    未扣 12px 双边距 → 周日列渲染到卡片外）。
  - C3：P-5 超限横幅数学错误（单屏 30 条双计为 12；两屏各 24 条假阳性「24 未显示」）。
  - C4：同 Linnaeus C1（宿主隐藏无触发路径）。
  - C5：同 P1（无新增 PID/Timer 判据与方案矛盾，且无实测证据）。
- PLAUSIBLE：
  - P1：tempUnit/convertTemp/fmtTemp 与 LeftSidebarWeather 近逐字重复（G-6 存疑）。
  - P2：addWidget 硬编码 small，天气/日历按 small 创建必然挤压（A4 前无 UI 入口）。
  - P3：A2 电池视觉被改（cellSize clamp + GRID_ROWS 4→6），roadmap A3 未声明。
  - P4：日历今日红圈 14px，两位数日期溢出。
  - P5：今日高低温跨午夜回退 arr[0] → 显示昨日数据。
  - P6：多屏同名 screenKey（同 Linnaeus P8）。
  - P7：测试为文本守卫，无运行时覆盖。
- macOS 观感核对：天气结构符合（双度号/单位不一致为硬伤）；日历结构符合（几何越界为硬伤）；
  系统监控配色/细条符合（底部留白 ~55px 失衡）。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| 天气 °°C 双度号 + 高低温单位不一致 | CONFIRMED | 已修：`fmtTemp(false)` 改为纯数字；高低温行 `"今日 24° ~ 32°"` 双°一致；小时格纯数字 | WeatherWidget.qml |
| 日历横向越界 12px | CONFIRMED | 已修：`cellW = (root.width - 24) / 7`（内容宽扣双边距） | CalendarWidget.qml:47；截图右缘 4px（原越界列文字为 0） |
| P-5 超限横幅数学 | CONFIRMED | 已修：`overflowCount = state.removed.length`（每屏独立 surface，region 上限按 surface 计，跨屏混算产生假阳性）；删除 `totalEntryCount()`；横幅文案去误导性「上限 24」 | WidgetHost.qml:261 |
| 宿主隐藏无触发路径 | CONFIRMED | 已修：`visible: root.widgetInstancesCount > 0`，实例数在 rebuildWidgets 显式维护 → 移除最后一个小部件即宿主隐藏 → hostVisible=false → dataRefreshActive=false / systemStatsDemand=false / SystemStats 进程停止 | WidgetHost.qml:59,118,178；冒烟实测：remove 全部 4 件后 `hostVisible=false count=0 demand=false statsActive=false`，子进程 `sh` 消失 |
| 「无新增稳定 PID/Timer」判据口径 | CONFIRMED（判据/方案字面冲突） | 记录为已知遗留：roadmap 自身要求 SystemStats 复用与日历分钟 Timer，必然产生既有服务进程 + 1 个门控分钟 Timer。按「无新增**种类**唤醒源 / 无新增未门控 Timer」口径验收；实测证据见下 | 60s 采样（4 件常驻）：仅 1 个既有 SystemStats `sh` 稳定 PID（200/200），零瞬时 spawn；日历唯一 Timer 门控于 dataRefreshActive |
| tempUnit/convertTemp/fmtTemp 与侧栏重复 | PLAUSIBLE | 不修：跨组件共享模块需改 LeftSidebarWeather（A3 范围外，G-7 风险）；°°C 已本地修复 | — |
| addWidget 硬编码 small | PLAUSIBLE | 已修：catalog 增 `defaultSize`（天气/日历 medium），addWidget 使用之 | WidgetHost.qml:97-100,294 |
| A2 电池视觉变化（cellSize clamp / 网格 4→6） | PLAUSIBLE | 记录：clamp 90 采用自 A2 遗留未提交的一行改动（用户 macOS 尺寸要求，A2 电池原为屏宽/2=1024px 巨卡）；网格 4→6 为 A3「四件同屏」判据所必需；旧配置行列位置在新网格下仍合法，无漂移 | — |
| 日历今日红圈 14px | PLAUSIBLE | 已修：`min(cellW,cellH)-1` = 16px，两位数日期可容 | CalendarWidget.qml |
| 今日高低温跨午夜回退昨日 | PLAUSIBLE | 已修：`todayDaily` 找不到今日条目返回空 → 高低温行隐藏，不显示昨日 | WeatherWidget.qml |
| 日历 Timer 恢复滞后 ~60s | PLAUSIBLE | 已修：`onRunningChanged` 恢复运行即刷新 now + 重算 interval | CalendarWidget.qml |
| onDestruction 引用已销毁 systemStats | PLAUSIBLE | 已修：try/catch 防御 | shell.qml |
| 天气 status 空数组显示 0° | PLAUSIBLE | 已修：`_liveHasData` 不再仅凭 status，要求 locationDetected 或数组非空 | WeatherWidget.qml |
| 跨零点滞后（10 分钟） | PLAUSIBLE | 不修：与 LeftSidebarWeather 同模式（服务 10 分钟刷新），轻微 | — |
| 超小屏纵向溢出 | PLAUSIBLE | 不修：现实桌面 ≥720p（6×90=540px 高），不触发 | — |
| 多屏同名 screenKey | PLAUSIBLE | 不修：A2 已知遗留，依赖环境屏名唯一性 | — |
| 测试为文本守卫 | PLAUSIBLE | 记录：仓库测试模式即源级守卫 + node 直测生产 JS；本任务补真机 quickshell 冒烟证据（见下） | — |
| pytest 单例失败（Linnaeus 观测） | PLAUSIBLE | 未复现：修复后全量 1098 passed + 318 subtests（多次复跑一致）；疑并行环境抖动 | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| 四个小部件（含 A2 电池）同时显示，数据均正确 | 是 | 真机 quickshell 冒烟：4 实例创建（weather/calendar/battery/system-monitor），真实服务数据（weather temp=25.6°C code=2 loc=Tokyo hourly=5；system-monitor cpu/ram/disk/net 实时；battery UPower）；截图逐区像素核验（天气/日历/电池/监控均有内容，日历右缘无越界，监控底部网络行在） |
| 实测：小部件常驻时 60s 子进程采样稳定 PID 数与新建 Timer 数相比 A2 无新增 | 是（按「无新增种类」口径，见问题处置） | 60s×200 次采样：仅 1 个既有 SystemStats `sh` 稳定 PID（200/200），零瞬时 spawn；无其他新 PID。新建 Timer：仅日历 1 个分钟对齐 Timer（roadmap 明示可借鉴 msecsToNextMinute），门控于 dataRefreshActive；天气/系统监控零 Timer。A2 基线 4 PID 中 SystemStats 本就存在（侧栏打开时同进程） |
| 宿主隐藏时所有小部件刷新停止 | 是（真实触发路径） | 宿主 `visible` 跟随实例数；冒烟：移除全部 4 件 → hostVisible=false、4 个 widget dataRefreshActive=false（另经 visible=false 探针验证）、systemStatsDemand=false、SystemStats `active=false` 且 `sh` 子进程消失 |
| pytest 全绿 | 是 | 1098 passed + 318 subtests（多次复跑一致） |

## 约束核对

| 条款 | 结果 |
|---|---|
| G-1 串行 / G-4 一任务一 commit | 是（A3 独立流程；feature + docs 各一 commit，沿用 A2 先例） |
| G-2 独立子代理审查 | 是（2 个，轮1 双 REJECT → 全部 CONFIRMED 修复 → 全量复跑 + 真机冒烟复核） |
| G-5 无最小实现 / 无占位 | 是（无 TODO/假数据；空态、快照锁存、previewMode、宿主隐藏全路径真实） |
| G-6 无平行接口 | 是（尺寸映射唯一来源 WidgetGrid.js；SystemStats `active` 唯一开关（widgetDemand 是第二个输入非第二套开关）；无重复数据路径；widgetSize 从 sizeForSpan 推导） |
| G-7 不破坏现有功能 | 是（A2 回归：弹层/mask/持久化/网格语义/电池路径未变；shell.qml import 头无花括号；网格 4→6 仅放宽；旧配置位置合法；全量 1098 绿） |
| G-8 无需求外功能 | 是（macOS 风格为用户本次明确要求；无商店/云同步/主题等） |
| A-C1 层级/输入策略 | 是（Bottom/Ignore/None/focusable:false/namespace tahoe-widgets 未变） |
| A-C3 禁自建轮询 | 是（天气/系统监控零 Timer；日历唯一分钟 Timer 门控 dataRefreshActive；SystemStats 复用既有服务并门控宿主可见性——宿主隐藏/无小部件时进程停止，冒烟实测） |
| A-C4 禁 layer.enabled / A-C6 图片卫生 | 是（无 layer.enabled；新小部件无 Image，MeteoIcon/TahoeSymbol 共享组件自带 sourceSize/pixelBudget） |
| A-C5 持久化时机 | 是（未改：仅 addWidget/removeWidget 完成时写盘一次，含 loadingComplete 早退门） |
| P-1 / P-2 / P-3 | 是（无 SpringAnimation；无新弹簧；无硬编码 duration——Timer interval 为一次性非动画） |
| P-5 region 上限 | 是（每屏网格 4×6 最多 6 件 small → ≤6 region < 32；超限横幅可见反馈（计数已修正）） |
| P-6 KeyboardInteractivity.None | 是（WlrKeyboardFocus.None + focusable:false） |
| P-10/P-11/P-12 工具纪律 | 是（qmllint 用 /usr/lib/qt6/bin；进程操作精确 PID；冒烟未触碰生产部署） |

## 最终结论

轮1 双 REJECT（合计 6 项 CONFIRMED：°°C、日历越界、横幅数学、宿主隐藏无触发、判据口径冲突、无实测）
→ 全部 CONFIRMED 修复 + 判据口径记录 + 实测证据补齐 → 全量 pytest 1098 绿 + 真机 quickshell
冒烟复核（4 件同屏、真实数据、宿主隐藏→进程停止、60s 采样）。允许 commit。

已知遗留（不阻塞，记录备查）：
- §2.4「无新增稳定 PID/Timer」按「无新增种类/未门控」口径验收（与 roadmap 自身方案的字面冲突，
  已在上述处置行记录）；真机部署后仍会按 §2.4 命令复核一次。
- 天气单位换算函数与侧栏重复（跨组件共享模块留待后续任务）。
- 多屏同名 screenKey 共享配置段（A2 已知遗留）。
- 真机视觉验收（部署后）：四个小部件实际观感、玻璃材质、macOS 相似度留人工确认。
