# A5 审查记录

日期：2026-08-11
子代理数：2（Poincare APPROVE；Epicurus REJECT 1×CONFIRMED → 已修 → 复跑全量 + 真机复验）

## 各子代理结论

### 子代理 1（Poincare）
- 结论：APPROVE（无 CONFIRMED）
- CONFIRMED：无
- PLAUSIBLE：
  - P1：G-6 裁决事项 —— WidgetPreview 与 WidgetHost.createWidgetInstance 的实例化路径结构平行（服务注入映射被复制）；反证：注册表/尺寸表/添加持久化路径唯一，预览实例不进 widgetInstances/网格/写盘
  - P2：「已添加」标记在宿主重建窗口内可能过期（presentIds 只在 onPresentWidgetsChanged 快照；rebuild 先赋空再 mutation 不触发 notify）
  - P3：「无新增 Timer」字面解读 —— 预览会实例化 CalendarWidget 的停止态 Timer 对象（running 门控 dataRefreshActive）
  - P4：多尺寸 chips 在当前目录（四项均单尺寸）下是死 UI
  - P5：预览组件源文件缺失时仅 console.warn，无 UI 反馈
  - P6：预览实例含 GlassPanel，侧栏 surface region 数 = 1+4 = 5 < 32，无 P-5 风险（观察项）

### 子代理 2（Epicurus）
- 结论：REJECT
- CONFIRMED：
  - C1：presentIds 刷新机制与宿主重建语义错配 —— `rebuildWidgets()` 先 `root.widgetInstances = {}`（触发 notify 时表为空）再逐个 mutation 填充（不触发 notify）→ 库页「已添加」快照停在空表；点击已添加条目会误报「无法添加小部件」横幅
- PLAUSIBLE：
  - P1：WidgetPreview 的 onSourceChanged 与 onCompleted 都调 load()，可能每个预览双实例化（其一立即 destroy；不泄漏但浪费）
  - P2：「无新增进程/Timer」判据无运行时证据（仓库无 A5-review/冒烟日志）
  - P3：「从预览选择尺寸添加」链路当前 catalog 无多尺寸条目，生产不可触发

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| C1/P2 presentIds 在宿主重建时失效 | CONFIRMED | **已修**：rebuildWidgets 改为「填完再整体赋值」——createWidgetInstance(entry, into) 写入临时表 next，`root.widgetInstances = next` 一次赋值；mutation 不再作为 notify 通道 | WidgetHost.qml rebuildWidgets/createWidgetInstance；结构测试 `test_rebuild_assigns_filled_instance_map_once`；真机：侧栏开着时触发 widgetHost.rebuildWidgets()，4 卡「已添加」仍全部正确 |
| P1 WidgetPreview 双触发 | PLAUSIBLE | **已修**：loadedSource 守卫 —— load() 开头 `if (loadedSource === src) return`，初始化时 onSourceChanged 与 onCompleted 只执行一次创建 | WidgetPreview.qml load()；结构测试锁定；真机：探针 a5LoadCount（创建点计数）= 每卡 1 |
| P1（G-6 平行实例化） | PLAUSIBLE | 不修，理由：预览渲染与桌面实例管理是不同职责；widgetCatalog 唯一（WidgetHost）、尺寸→跨度唯一（WidgetGrid.js）、addWidget 仍是唯一添加/持久化路径；预览实例不进 widgetInstances/网格/不写盘。6 行服务注入映射为内部实现细节，不构成第二条功能路径 | 结构测试 test_registry_single_source_with_sizes / test_gallery_sizes_use_widget_grid_single_source |
| P3（无新增 Timer 字面解读） | PLAUSIBLE | 不修，理由：按 A3 既定验收口径「无新增**种类**唤醒源 / 无新增**未门控** Timer」；日历预览 Timer running 恒 false（门控 dataRefreshActive）；真机探针 refreshActive=false | CalendarWidget.qml:34、Widget.qml:48；真机 libProbeState |
| P4 chips 死 UI | PLAUSIBLE | 记录为已知遗留：当前 catalog 四项均单尺寸，chips 不显示属预期；实现已支持多尺寸并真机验证（临时目录给 weather 加 large：chips 渲染、selectedSize 默认 medium、addWidget(weather, large) 成功落盘 size=large），A7 提供档位后自然生效 | 真机 libProbeState + widgets.json |
| P5 缺 source 无 UI 反馈 | PLAUSIBLE | 记录为已知遗留：catalog 是内部固定注册表，四项 source 均存在且测试锁定（test_catalog_ships_first_batch）；桌面宿主 createWidgetInstance 同样仅 console.warn；补 UI 占位属需求外（G-8） | WidgetHost.qml:144-147 |
| P6 预览 glass region | 观察项 | 不修：侧栏 surface region ≤5 << 32，无 P-5 风险；预览玻璃在侧栏内渲染属预期 | Widget.qml GlassPanel；tahoe_glass.rs:26 |

## 完成判据核对

| 判据（引 roadmap.md A5） | 是否满足 | 证据 |
|---|---|---|
| 每个可用小部件在库中显示真实预览 | 是 | 真机（部署后）探针：4 卡各 1 个真实实例（BatteryWidget/WeatherWidget/CalendarWidget/SystemMonitorWidget），previewMode=true、refreshActive=false；weather/calendar 默认 medium（288×144）、battery/system-monitor small（144×144）；截图 /tmp/a5shots/02-library-previews.png |
| 实测：打开库 tab 时无新增进程 spawn、无新增 Timer（预览不得触发数据刷新） | 是 | 真机 60s×200 次子进程采样：稳定 PID 集 = niri/udevadm/wl-paste/sh（既有 4 类），零瞬时 spawn；探针 refreshActive 全 false（数据刷新停摆）；日历预览 Timer 停止态且门控（结构测试锁定）；按 A3 既定「无新增种类/未门控」口径 |
| 从预览选择尺寸后正确添加到桌面 | 是 | 真机生产信号链（leftSidebar.addWidgetRequested(id,size) → shell → widgetHost.addWidget）：calendar/medium 添加成功 → 侧栏关闭 → widgets.json 落盘（col0,row2）；临时目录 weather 双尺寸验证：addWidget(weather,large) 成功 → 侧栏关闭 → widgets.json 记 size=large；空间不足时正确失败（侧栏保持打开 + 横幅） |
| pytest 全绿 | 是 | `python -m pytest tests/ -q`：1116 passed + 318 subtests（修复后复跑） |

## 回归核对（G-7 / A4 清单）

- 「系统」「天气」两 tab：LeftSidebarSystem/Weather.qml 零改动；LeftSidebar.qml diff 仅信号签名 + 三服务注入 + 库页传参；侧栏开合/入场动画未动 —— 通过（git diff 核验）
- A4 库页「已添加」禁用与失败横幅：保留（enabled: !present / 无法添加小部件横幅），且 C1 修复后重建场景下不再过期 —— 真机核验
- 桌面小部件显示与输入策略（A2/A3）：WidgetHost 层契约（WlrLayer.Bottom / ExclusionMode.Ignore / KeyboardFocus.None / focusable:false / namespace）零改动；createWidgetInstance 仅加 into 参数 —— 通过
- 约束速查表：无 SpringAnimation（P-1）、无硬编码 duration（P-3，Timer interval 非动画时长）、无 DragHandler/DropArea/Process/layer.enabled、写盘仅操作完成一次（A-C5）、无 focusable（P-6）—— 结构测试全绿
- qmllint（/usr/lib/qt6/bin/qmllint --bare + 带 import path 复核）：零 [error]，仅既有环境噪音（import path / WidgetHost screen property-override 为 A2 既有）—— 无新增告警

## 最终结论

Epicurus 1×CONFIRMED（C1 presentIds）已修并真机复验；Poincare 无 CONFIRMED。双触发（P1）亦已修并真机复验（loadCount=1）。其余 PLAUSIBLE 已记录理由。全部确认问题已修 → 允许 commit。
