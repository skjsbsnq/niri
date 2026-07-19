# R16 · Overview / 切换器收尾 · 2026-07-19

覆盖问题：#42 #43 #44 #45 #46；#41 “TaskSwitcher 面板瞬时出现”的有意设计保持不变。

## 实施摘要

- TaskSwitcher 确认改为选中卡片局部 `1 → 1.06 → 1` pop，两段共享 `Motion.elementMove` 档位时长；动画结束后才 activate/restore 并关闭。`SequentialAnimation + ScriptAction` 复用原有确认路径，未新增第二个 confirm Timer。
- confirm 期间禁止重复选择；取消、外部关闭和新 session 都会 stop pop 并清空捕获窗口；reduced profile 不等待动画、同帧确认。
- 切换器去掉 `positionViewAtIndex()` 的瞬时视口跳转；选择框 `contentX` 成为唯一动画驱动，ListView 视口每帧按选择框位置有界跟随，spring/eased 互斥，不再有两条时间轴。
- TaskSwitcher 窗口模型补 `objectProp: "modelKey"`；卡片 hover 和焦点点颜色加 `ColorAnimation`，焦点点宽度加 eased `Behavior`。
- WindowOverview `ensureVisible()` 改为可重定向的 `NumberAnimation` + `Motion.elementMove`，用户手势开始时会停止程序滚动；reduced/0ms 路径直达目标。
- workspace/window 两层 ScriptModel 分别用 `key` / `modelKey` 稳定 identity；Flow 采用 Positioner 合法的 `move: Transition` 为增减后存量卡片让位，不引入 ListView-only 的平行机制。
- Overview 选中卡填充色、边框色与 `border.width` 分别接 Color/NumberAnimation；卡片销毁时清理 `selectedCardItem`，避免陈旧 item 被 `mapToItem()`。

## 方案决策

- #41 保持：外层 `visible: open` / `visible: root.open` 与二值 opacity 不变，没有给面板增加入场 scale。pop 只是 delegate 内容 transform。
- 滚动/高亮选“高亮为唯一驱动，视口跟随”：比同时动 ListView `contentX` 和 highlight `contentX` 更直接，且视口始终 clamp 在合法范围。
- Flow 只用 Positioner `move` 过渡实现“增减导致的 displaced 位移”；不将 ListView `remove/displaced` API 硬套到 Flow，也不与已有窗口 flight opacity/transform 双驱动。

## 审查

独立子代理逐 diff 审查结论 **CLEAN**：

- confirm pop 无第二 Timer，取消/外部 close/reduced 生命周期收口；重复 confirm 不会二次激活。
- highlight spring / eased 每次都先互停后择一；视口未新增独立 Behavior/Animation，无双时间轴。
- Overview 变更均在内容层；`TahoeGlass.regions` 与两个 GlassPanel region 几何零 diff，无 spring 进入 glass 路径。
- `ScriptModel.objectProp` 对应的 `key/modelKey` 均由生产模型提供；`Flow.move` 通过 qmllint 语法核验。

## 自动验收

- `git diff --check` → 通过。
- `qmllint components/TaskSwitcher.qml components/WindowOverview.qml` → 退出码 0；仅有独立 qmllint 环境无 Quickshell import path 的既有 unresolved-import warning。
- R16 及相关治理回归：`test_task_overview_motion`、`test_task_switcher_release_confirm_lifecycle`、thumbnail contract/budget、material governance、motion token convergence → **59 tests 全绿**。
- TaskSwitcher 真实 `qmltestrunner` 覆盖：30ms pop 期间不激活、pop 后单次激活/关闭、pop 期间 cancel、重复 confirm、reduced 同帧确认，以及既有 40ms modifier-release session race。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tahoe-shell/tests/` → **795 passed, 234 subtests passed in 40.93s**。

## 运行期/手测矩阵

- 用当前源码启动隔离 nested niri，通过 PID 定向 Quickshell IPC 打开 WindowOverview；同一 workspace 生成 10 个真实 Alacritty 窗口，Flow 两行以上布局、选中边框、空 workspace 占位均正常。
- nested 会话运行至 timeout，无 TaskSwitcher/WindowOverview `ReferenceError`、`TypeError`、binding loop 或 QML 动画警告；仅既有 EGL 噪声与 timeout SIGTERM。
- 面板本体仍瞬时出现；选中卡颜色/边框过渡与局部 pop 不修改 layer surface 或 glass region。
- fast/balanced/liquid 时长由 `Motion.elementMove/elementResize/fadeFast` 继承；reduced 路径在真实 QML 测试中验证为即时；`useSpring=false` 走单一 eased 分支。

## 范围外

- 未修改 TaskSwitcher/Overview 外层开合范式、缩略图服务、窗口 flight 物理或 KDL layer-rule。
- Overview 新增/删除卡本体的延迟销毁淡出未新建机制；R16 按计划只处理 Flow 增减引起的存量卡位移。
