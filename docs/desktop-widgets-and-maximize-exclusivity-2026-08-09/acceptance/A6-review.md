# A6 审查记录

日期：2026-08-11
子代理数：5（第 1 轮 3 个 + 第 2 轮 2 个；其中 Mencius 超时无结果，按子代理协议停止）

## 各子代理结论

### 子代理 1（Linnaeus，第 1 轮）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  1. begin/update 拖动逻辑可被掏空而不被测试发现（结构测试风格固有上限）
  2. 「短按不触发」未被定点守护（需人工运行时验证）
  3. suppressNextClick 接线只被字符串存在性守护
  4. onCanceled 是否被 quickshell 真实派发无法静态证实（需人工）
  5. grid 测试边界盲区（canPlace 负值 / snapPosition cols>GRID_COLS / 屏下沿）
  6. 「拖动期抑制 hover、阻止宿主尺寸变化」无显式实现（widgets 无 hover、宿主尺寸只随实例数变化，实为空条款）

### 子代理 2（Ramanujan，第 1 轮）
- 结论：REJECT
- CONFIRMED：
  - C1：编辑模式退出不清拖动状态 —— `exitEditMode()`（WidgetHost.qml）只置
    `editMode=false`，不清 `dragActive/dragWidgetId/dragStart`；拖动可越过编辑
    模式存活，release 仍 commit 写盘；cancel 不达则 `dragActive` 永久残留，
    后续 begin 全部早退（拖动永久失效）。
- PLAUSIBLE：
  - P1 onCanceled 派发无保障；P2 预览实例创建 2 个 Timer 对象（不启动）；
    P3 提交动画期间实例被销毁可能悬挂动画 target；P4 完成按钮可能被窗口覆盖
    （可恢复）；P5 拖动状态双份维护（与 Dock 同构，非 G-6 违规）。

### 子代理 3（Anscombe，第 1 轮）
- 结论：REJECT
- CONFIRMED：
  - C1：落位动画被下一次 begin 截断 —— `beginWidgetDrag` 无条件
    `dragXAnim.stop()/dragYAnim.stop()`，而 `dragStart` 快照取 `inst.x/inst.y`
    当前值（动画中间帧）；130ms 内再次按住任意小部件 → 已提交实例冻结在非
    网格坐标，与已写盘 config 长期不一致；cancel 回滚到中间帧快照而非网格位。
- PLAUSIBLE：
  - P1 popup 打开是否触发 MouseArea.onCanceled 无法静态证实；
    P2 exitEditMode 中途不清 dragActive（与 Ramanujan C1 同根因，标 PLAUSIBLE）；
    P3 rebuild 不 stop 动画；P4 动画时长忽略 motion profile（`elementMove(null)`
    恒 balanced，P-3 合规但 reduced 下仍 130ms）；P5 窄屏/矮屏 y 轴网格语义。

### 子代理 4（Laplace，第 2 轮，复核修复）
- 结论：APPROVE
- CONFIRMED：无（两条首轮 CONFIRMED 均已闭合）
- PLAUSIBLE：
  - P1（已修）：`test_widget_edit_mode.py` exit_block 切片方向错误，
    `root.clearDrag()` 断言空转（`enterEditMode` 先于 `exitEditMode` 出现，
    split 不命中）。
  - P2（已修）：settle/begin/cancel/commit 未做 `Math.max(0,…)` y 钳制，
    与 createWidgetInstance 不一致（屏高 <540px 顶部行像素为负）。
  - P3（已修）：退出时仅 `dragPressed=true`（未过阈值）不被 reset，之后移动
    可把 widget 侧 dragActive 置真（host 门挡住写盘，仅防御不对称）。

### 子代理 5（Mencius，第 2 轮）
- 结论：无结果（运行超 10 分钟，按子代理协议停止；无可用 MESSAGE）

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| 编辑模式退出不清拖动状态（Ramanujan C1） | CONFIRMED | 已修 | `exitEditMode()` 拖动中回滚（停动画、恢复 inst.x/y=start.x/y、clearDrag）；Widget.qml `onEditModeChanged` 退出时 resetGesture（dragActive‖dragPressed） |
| 落位动画截断 → 实例与 config 不一致（Anscombe C1） | CONFIRMED | 已修 | `settleWidgets()` 停动画并把全部实例对齐 config 网格位；`beginWidgetDrag` 先 settle 再从 `Grid.xPxForCell/yPxForCell` 快照（不再用 inst.x/inst.y）；rebuild 停动画 |
| 测试 exit_block 切片空转（Laplace P1） | PLAUSIBLE | 已修 | 切片终点改为 exitEditMode 之后的注释行，断言紧贴函数体 |
| 短屏 y 钳制不一致（Laplace P2） | PLAUSIBLE | 已修 | settle/begin/animateWidgetTo 统一 `Math.max(0,…)`，与 createWidgetInstance 一致 |
| 退出时 dragPressed 残留（Laplace P3） | PLAUSIBLE | 已修 | `onEditModeChanged` 条件改为 `(gesture.dragActive \|\| gesture.dragPressed)` |
| onCanceled 派发无法静态证实 | PLAUSIBLE | 不修，理由：代码路径完备（Widget.qml onCanceled → cancelWidgetDrag 回滚）；派发本身属运行时行为，roadmap 已列为人工验证判据（执行计划 A6 判据 3） |
| 预览实例创建 2 个 Timer 对象 | PLAUSIBLE | 不修，理由：两个 Timer 均为一次性手势计时（repeat:false），预览实例 gesture 禁用（interactive=false 且无 widgetHost）→ Timer 永不 start；与 Dock 每图标一个 suppressClickReset Timer 同模式；A5「无新增 Timer」判据语义为「不触发数据刷新」，运行时实测基线以稳定 PID/运行中 Timer 为准 |
| 提交动画期间实例被销毁 | PLAUSIBLE | 不修，理由：rebuild 已补 stop；Qt QQuickAnimation target 为 QPointer，销毁自动停；仅 130ms 窗口且需删除按钮在动画中点击 |
| 完成按钮可能被窗口覆盖 | PLAUSIBLE | 不修，理由：Bottom 层小部件系统固有（窗口之上即覆盖）；空白点击退出 + 移开窗口可恢复，非卡死；roadmap 未要求键盘退路 |
| 拖动状态双份维护（widget/host） | PLAUSIBLE | 不修，理由：与 Dock 既有模式（per-button + root.pointerDragActive）同构，A-C2 要求的模式；host 门保证写盘唯一入口 |
| 动画时长忽略 motion profile | PLAUSIBLE | 不修，理由：`elementMove(null)` 恒 balanced 不违反 P-3（令牌来源正确）；widgets 无 settingsService 注入，注入属范围外改动 |
| 短屏 6 行网格超屏高 | PLAUSIBLE | 不修，理由：A2 既有网格语义，非 A6 引入；A6 已保证所有像素路径钳制一致 |
| 结构测试盲区（掏空 begin/update、短按、suppressNextClick 因果） | PLAUSIBLE | 不修，理由：仓库「源码结构守护」测试风格固有上限，commit/cancel/回滚等关键路径已钉牢；运行时判据列入人工验证 |

## 完成判据核对

| 判据（引 roadmap.md A6） | 是否满足 | 证据 |
|---|---|---|
| 长按进入编辑模式；短按不触发；拖动不误触发点击 | 结构是 | 长按：Widget.qml longPressTimer（500ms one-shot）→ enterEditMode；短按：onReleased/onPositionChanged stop；不误触：dragActive 激活置 suppressNextClick + onClicked 消费 + 180ms 复位。短按/不误触的最终判定需人工（部署后） |
| 拖动改变位置并持久化；重启后位置正确 | 结构是 | commitWidgetDrag：snapPosition+canPlace → updateConfigPosition → animateWidgetTo → persistConfig（恰一次）；loadConfig 重建。重启需人工 |
| onCanceled 路径完整回滚，不卡死 | 结构是 | Widget.qml onCanceled → cancelWidgetDrag 恢复 inst.x/y=start.x/y + clearDrag + resetGesture；所有退出路径状态归零（exitEditMode/rebuild）。派发需人工 |
| 拖动期间无写盘 | 是 | begin/update/cancel/exitEditMode 均无 persistConfig（测试断言 + 逐行确认）；commit 恰一次 |
| 退出编辑模式后抖动动画停止 | 是 | wobble `running: root.editMode && root.interactive` + onRunningChanged 归零 rotation |
| 通过 A4 库 tab 新添加的小部件同样可被拖动 | 是 | createWidgetInstance 注入 widgetId/widgetHost + editMode Qt.binding（与预置实例同一路径） |
| pytest 全绿 | 是 | `python -m pytest tests/ -q` → 1136 passed, 318 subtests passed（70.6s） |

## 最终结论

第 1 轮 3 个子代理（1 APPROVE / 2 REJECT，共 2 个 CONFIRMED）→ 已修复 →
第 2 轮 2 个子代理（1 APPROVE，1 超时无结果）复核确认两条 CONFIRMED 已闭合，
并把 3 个 PLAUSIBLE 修复。全部 CONFIRMED 已修、测试全绿 → 允许 commit。
剩余 PLAUSIBLE 均为运行时人工验证项或仓库测试风格固有盲区，已逐条记录处置。

## 部署修复记录（2026-08-11）

**运行时缺陷（部署后实测复现）**：拖动不生效，小部件位置固定。
- 现象：长按进入编辑模式正常（抖动/完成按钮/编辑 mask 均出现），但拖动时
  小部件不跟随指针，release 后位置不变。
- 根因：`WidgetHost.qml` 的 `beginWidgetDrag` / `updateWidgetDrag` 调用
  `inst.mapToItem(root, ...)`，其中 `root` 是 `PanelWindow`。quickshell 的
  `PanelWindowInterface` 继承自 `WindowInterface`（QObject），**不是 QQuickItem**，
  运行时抛 `TypeError: Could not convert argument 0 from WidgetHost_QMLTYPE_102
  to const QQuickItem*`（qslog 实测）。异常发生在 `dragStart`/`dragActive`
  赋值之前 → 后续 update/commit 全部被宿主守卫早退 → 位置固定。
- 修复：mapToItem 目标改为 `widgetLayer`（普通 QQuickItem，`anchors.fill`
  宿主，坐标等价）。结构测试同步把断言改为 `inst.mapToItem(widgetLayer, ...)`
  并加注释锁定该坑。
- 教训：qmllint 对 quickshell PanelWindow 类型不报（它把 PanelWindow 标为
  uncreatable 后不再深查），此类「把窗口类型当 Item」的调用必须经部署实测
  才能暴露 —— 与 A2/A5 部署修复同属「结构测试 + 静态 lint 覆盖不到的层」。

## 部署反馈修复记录（2026-08-11，第二次）

**运行时问题（用户反馈）**：所有小部件只能集中在左下角一小块区域，无法自由
拖动到桌面其他位置。
- 根因：网格固定 4×6 单元格且 cellSize 封顶 90px → 2048×1280 屏上只覆盖
  360×540 左下角；拖动落点 snapPosition 一律钳回该块（设计缺陷，A2 网格
  语义在 A6 拖动暴露）。
- 修复：网格按屏铺满 —— gridCols/gridRows = floor(屏宽/高 ÷ cellSize)
  （cellSize 固定 ≤90px，小部件尺寸语义不变）；WidgetGrid.js 各边界函数
  参数化 gridCols/gridRows（默认 4×6 保留给库预览/单测/窄屏）；每屏条目
  上限 widgetLimit = min(32, 网格容量) 守住 P-5 region 上限，加载/添加时
  截断并计入超限横幅。
- 验证：全量 pytest 1140 passed；node 实测全屏网格的
  gridStateFromConfig/findSlot/snapPosition/canPlace；部署后运行探针确认
  拖到右上角可落位到 (20,10) 附近而非钳回左下角。

## 部署反馈修复记录（2026-08-11，第三次）

**运行时问题（用户反馈）**：往左上角放小部件很容易超过顶栏，没法刚好贴着顶栏。
- 根因：网格垂直方向固定 cellSize=90px 从屏底铺满到屏顶，最顶行像素上缘
  会进入顶栏（TopBar 高 40px，exclusiveZone 40）；且 1240px 可用高度无法
  被 90px 整除，最顶行要么进顶栏、要么留 ~70px 空隙。
- 修复：新增 topReserved=40；cellSize 垂直方向自适应为
  (screenHeight-topReserved)/rows，使网格恰好铺满 [topReserved, 屏底] ——
  最高行像素上缘恒等于 40（贴着顶栏）；拖动时 y 钳制在
  [topReserved, screenHeight-height]；加载时把进入顶栏区的旧条目钳到
  最高行（只重定位、不计超限）。
- 验证：全量 pytest 1140 passed；部署后运行探针确认拖到最顶时
  y = topReserved（40）且不进入顶栏。

## 部署反馈修复记录（2026-08-11，第四次）

**运行时问题（用户反馈，三项）**：① 多个小部件排在一起时完全贴死、无视觉
缝隙；② 天气小部件「今日 x° ~ y°」行容易与逐时条/其他内容贴在一起；
③ 设置里已把天气位置设为「肇庆市 · 广东 · 中国」，仍经常按 IP 查询天气。

**本记录：小部件视觉缝隙（gap）**
- 根因：实例按整格铺放（x=col*cell、width=cols*cell），相邻小部件像素级贴死。
- 修复：WidgetGrid.js 新增 GAP_PX=12，xPxForCell/yPxForCell/snapPosition
  增加可选 gap 参数（默认 0 保持纯网格语义）；WidgetHost 以 widgetGap 注入，
  实例矩形四周内缩 gap/2（相邻留 12px、屏边留 6px）；拖动钳制与静止位同一
  内缩并锚网格右边界（gridCols*cellSize），消除拖到边缘松手回弹。
- 审查：Socrates（第 1 轮 APPROVE；PLAUSIBLE：拖动边缘 6px 回弹 → 已修）→
  Hooke（第 2 轮 REJECT：右缘整格回弹 ≤1 cell → maxX 锚网格右边界已修）→
  Hilbert（第 3 轮 APPROVE；残差 ≤0.78px 亚像素级，非回弹）。
- 验收：gap round-trip 纯函数测试 + 结构测试更新；全量 pytest 全绿
  （1150 passed / 1204 subtests）。

**本记录：天气小部件顶部布局（「今日 x° ~ y°」不再贴/叠逐时条）**
- 根因：44px 当前温度 + 52px 逐时条在 medium（2 行）高度内放不下，顶部
  Column 溢出把「今日 x° ~ y°」行压进/贴上逐时条（2048×1280 下溢出约
  9-13px）。
- 修复：内容自适应 —— contentMargin=10、hourlyH=50、topAreaH 随实例高
  计算、tempRowH=clamp(topAreaH-47,26,38)，温度字号跟随行高
  （min(34,max(24,tempRowH-4))）；各行显式高度；topArea clip 兜底。
- 审查：Fermat（REJECT：768p 下「今日」行被 clip 裁没 + 测试不锁承重值）
  → Sagan（REJECT：761/762 边界 1px + 测试未取整/只枚举 5 屏）→ Lagrange
  （APPROVE；两条 PLAUSIBLE 需真机目检：温度字形行高溢出、今日字形墨迹
  ~1px 裁切，均非本轮引入且不阻断）。
- 验收：几何测试按宿主同款公式扫描逻辑高 720–1600 全绿（886 subtests）；
  全量 pytest 全绿。

**本记录：天气手动位置持久化（设置了肇庆不再按 IP 查询）**
- 根因：Weather 服务 Component.onCompleted 立刻 refresh()，而 DesktopSettings
  的 desktop-settings.json 由 FileView 异步加载，此时 weatherManualOverride
  还是默认 false → 每次启动先按 IP 定位（live 状态实测：desktop-settings.json
  为肇庆 23.04893/112.46091，weather-cache.json 却是 Beijing 39.90/116.41）；
  设置加载完成后没有任何路径重发刷新，10 分钟内一直显示 IP 天气。
- 修复：refresh()/loadCache() 增加 settingsService.loaded 早退门
  （pendingSettingsRefresh 挂起），Connections.onLoadedChanged 在设置加载
  完成后重驱 loadCache+refresh（P-7 双门）；loadCache 增加
  cacheMatchesLocation —— 手动覆盖且缓存坐标与手动坐标不一致（容差 0.05°）
  时丢弃缓存，不闪现旧 IP 位置。
- 审查：Lovelace（REJECT：结构测试只锁字符串、不锁控制流位置 → 已强化为
  函数体内相对位置断言：gate<manual<detect、mismatch<apply、refresh 在
  pendingSettingsRefresh 条件块内）→ Hooke（第 2 轮复核：运行时代码核验
  通过、测试强化有效，APPROVE）。
- 验收：门控顺序断言 + 全量 pytest 全绿（1150 passed / 1204 subtests）。

**本记录：电池小部件图标与百分比卡在一起**
- 根因：BatteryWidget 旧布局用 cellSize 绝对偏移（bolt topMargin 0.45*cell、
  半透明轮廓居中、百分比 bottomMargin 0.22*cell）；上一轮 gap 修复让实例
  宽高各内缩 12px 后，bolt 与轮廓互相挤压、百分比压上轮廓下沿（截图实测
  bolt 与轮廓贴合、百分比距轮廓下沿仅 ~19px）。
- 修复：改为锚链顺序排布 —— 半透明电池轮廓贴顶（size=min(52, W*0.58)）、
  bolt 叠加其中心（size=min(40, W*0.46)）、百分比锚在轮廓下沿
  （topMargin=max(2, H*0.04)，font=min(26, W*0.26)）、状态文本贴底；
  任意实例高度（120–180）下三者互不重叠，低电量变红语义与充电/放电字形
  不变。
- 审查：Aquinas（APPROVE；指出测试切片使 0.15/0.22/0.36 等旧偏移断言
  空转 → 已补强为全视觉块切片 + 补 0.42/0.62）→ Hume（APPROVE；四屏
  几何一致、手势/删除命中不受遮挡、无平行网格逻辑；极短屏 <640×480
  边界微叠 3px 不在本轮范围）。
- 验收：全量 pytest 1152 passed / 1204 subtests。
