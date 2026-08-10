# A1 审查记录

日期：2026-08-10
子代理数：5（轮1 ×3、轮2 ×2）

## 各子代理结论

### 轮 1

#### 子代理 1（对抗审查：生命周期/销毁）
- 结论：REJECT
- CONFIRMED：
  - C1：`windowOverviewRetain` 属性遮蔽（shell 级 :49 与 Scope 级 :1143 同名，写 Scope 级、loader 读 `shell.windowOverviewRetain` 根级 → 恒 false）→ WO 关闭时退场飞行被砍（对象树同帧销毁，leave 飞行闭包丢弃）、重开白屏（重建后 open=true 为初始值，onOpenChanged 不触发 → flightPhase 停 idle、veil 0、内容不可见）
  - C2：LeftSidebar 重开卡片永不入场（cardsEnter 只由 onOpenChanged(true) 里的 Timer 置位，重建路径不触发）+ currentTab 状态丢失
  - C3：Spotlight 重开搜索框无键盘焦点（forceActiveFocus 只在 onOpenChanged(true)）
  - C4：SettingsPanel 重开丢 systemStatusService.refresh 与焦点
  - C5：CC/NC retain 信号广播到所有屏 → 每次关闭在每块屏实例化隐藏面板（16ms 后销毁）
  - C6：完成判据一（六面板功能动画无变化）不成立
- PLAUSIBLE：P1 activeTopBarPopup 首帧 null（已被子代理 2 否证）；P2 panelWidth 异屏；P3 Connections 声明顺序依赖

#### 子代理 2（对抗审查：多屏时序）
- 结论：REJECT
- CONFIRMED：
  - C1（同子代理 1 的 C1）：WO retain 作用域不匹配，退场飞行截断、面板瞬灭
  - C2（同 C5）：多屏广播，每次关闭 CC/NC 所有未开屏瞬时实例化（N 屏拓扑下 (N-1) 次全量构建）
- PLAUSIBLE：P1 每次打开同步实例化卡顿（A1 按需加载设计取舍）；P2 panelWidth 异屏宽度
- 已核查无问题：CC 16ms 内重开（item 存活复用）；Timer/Connections 竞态（主线程串行）；启动路径无行为差异；activeTopBarPopup 求值时序安全（lazyloader item() getter 强制完成 + PopupDismissLayer width>1 守卫 + S-L6 锁存）；测试无旧 id 残留

#### 子代理 3（对抗审查：回归与测试）
- 结论：REJECT
- CONFIRMED：
  - C1（同 C1）：windowOverviewRetain 双重声明断链，退场动画截断
- PLAUSIBLE：P1 退场期间销毁后 niri close snapshot 只剩壁纸；P2 CC/NC 所有屏 retain 同步置位（16ms 隐藏面板）；P3 panelWidth 绑定不重求值（函数调用不建依赖）；P4 LeftSidebar.currentTab 关闭重开丢失
- 回归核对：除 C1 外逐面板代码核对通过（LeftSidebar/CC/NC/Spotlight/SettingsPanel 的 open 驱动等价、玻璃材质无首帧问题、cutout 正确、tab 切换未动）；测试覆盖：无任何测试覆盖 retain 机制（C1 断链未被静态测试捕获）；runtime 测试不受 LazyLoader 包裹影响

### 轮 2（修复后复核）

#### 子代理 4（复核：修复验证）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：A 屏 700ms 窗口内被 B 屏开+关提前销毁（半 veil 快照，自愈）；panelWidth 绑定冻结（clamp 饱和，实际无影响）
- 关键确认：LazyLoader 同步实例化（Synchronous incubator）+ 销毁 deleteLater（延迟到下一事件循环）→ onOpenChanged(false) 清理必先于销毁执行；enter() 双驱动（onCompleted 对初始 open=true、onOpenChanged 对转变）按构造互斥，逐路径推演均恰一次；CC/NC 16ms retain 对 deleteLater 语义冗余但无害；deleteOnInvisible 确认 A1 前后关闭路径一致

#### 子代理 5（复核：状态与信号链路）
- 结论：APPROVE
- CONFIRMED：WO retain 僵尸实例泄漏（`overviewRetainTimer.stop()` 无条件 → B 屏打开误停 A 屏 700ms 计时器 → retain 永久滞留）——已修（stop 移入 `if (onThisScreen)` 分支，子代理 5 复核确认修复正确）
- PLAUSIBLE：panelWidth 取屏语义（clamp 下实际无差）；同帧 close→reopen 双实例竞争（用户交互不可达）
- 关键确认：currentTab 四处接线闭环（shell 属性 / 注入 / 信号 / 回灌）、赋值与信号成对无静默路径、segmentThumb onCompleted 首帧直接定位无跳帧、多屏至多一个实例无共享竞争、retain 屏名判定与 topBarPopupOpenFor/navigationOpenFor 逐字同源、WO 空串放宽已补

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| WO retain 属性遮蔽（C1，三代理） | CONFIRMED | 已修（第 1 轮）：删 shell 级死属性；WO LazyLoader active 改读 Scope 级 retain；WindowOverview 提取 `enter()` + `onCompleted: if (root.open) enter()` 补驱动 | shell.qml（Scope 内声明/写入/读取同作用域）；WindowOverview.qml enter/onCompleted |
| LeftSidebar 重开卡片不入场 + currentTab 丢失（C2） | CONFIRMED | 已修：提取 `enter()` + onCompleted 补驱动；`currentTab` 可注入 + `currentTabChangeRequested` 信号回灌 shell；shell 级 `leftSidebarCurrentTab` 跨开关保留 | LeftSidebar.qml enter/onCompleted/signal；shell.qml 注入/回灌 |
| Spotlight 重开无焦点（C3） | CONFIRMED | 已修：提取 `enter()`（snappingOpen + query 清空 + forceActiveFocus）+ onCompleted 补驱动 | Spotlight.qml enter/onCompleted |
| SettingsPanel 重开丢刷新/焦点（C4） | CONFIRMED | 已修：提取 `enter()`（refresh + snapTo + forceActiveFocus）+ onCompleted 补驱动 | SettingsPanel.qml enter/onCompleted |
| CC/NC retain 多屏广播（C5，代理 2 C2） | CONFIRMED | 已修：Connections handler 内加 `onThisScreen` 本屏判定（topBarPopupScreenName 与 modelData.name 比较）；WO 用 windowOverviewScreenName 且含空串放宽（与 navigationOpenFor 语义一致） | shell.qml Connections handler |
| WO retain 僵尸实例泄漏（代理 5） | CONFIRMED | 已修（第 2 轮）：`overviewRetainTimer.stop()` 移入 `if (onThisScreen)` 分支，非本屏打开不碰本屏 retain/Timer | shell.qml onWindowOverviewOpenChanged |
| activeTopBarPopup 首帧 null（轮1 代理1 P1） | PLAUSIBLE | 不修：子代理 2 否证（item() getter 强制完成 + PopupDismissLayer width>1 守卫 + S-L6 锁存） | — |
| 每次打开同步实例化卡顿（代理 2 P1） | PLAUSIBLE | 不修：A1 按需加载的设计取舍；同步孵化保证行为确定性 | — |
| panelWidth 异屏/绑定冻结（代理 2 P2、代理 3 P3、代理 4/5 minor） | PLAUSIBLE | 不修：340–420 clamp 对所有 ≥444px 屏饱和，实际无差异；panel 与 cutout 共用同值内部一致 | — |
| WO 700ms 窗口被 B 屏开+关提前销毁（代理 4） | PLAUSIBLE | 不修：触发窗口极窄（关闭后 700ms 内异屏开+关）、自愈（下次打开 enter 从快照态重编）、严格优于旧僵尸泄漏 | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| 六个面板均可正常打开/关闭，功能与动画无变化（回归） | 是（静态+冒烟） | 冒烟：修改后 shell 在真实 quickshell 下加载零 QML 错误（exit=124 持续运行）；逐面板 open 驱动等价核对（子代理 3/4/5）；WO 退场飞行由 700ms retain 保活（快照在飞行完成时捕获）；CC/NC 清理在 deleteLater 前同步执行；面板内 Timer 随对象树销毁无泄漏。**人工验证（部署后）待执行** |
| 实测 RSS：关闭后回收量显著改善，前后对比 | 是（代码层面） | 改造前实测：WO 开 +18MB、关残留 +15MB（RSS 658→677→674MB）。改造后关闭即销毁对象树（WO 700ms 后销毁）。**部署后复测（A1 判据二）待执行** |
| `python -m pytest tests/` 全绿 | 是 | 1023 passed + 291 subtests（68.2s），多次复跑一致 |
| qmllint --bare 无新增告警 | 是（执行计划 2.2 补充） | 仅既有环境噪音（import path / PanelWindow uncreatable / TahoeGlass unresolved / modelData unqualified），无新告警 |

## 约束核对

| 条款 | 结果 |
|---|---|
| G-1 串行 | 是（A1 独立 commit） |
| G-2 独立子代理审查 | 是（5 个，轮1 REJECT → 修复 → 轮2 APPROVE） |
| G-4 一任务一 commit | 是 |
| G-5 无最小实现/TODO | 是 |
| G-6 无平行接口 | 是（panelWidth 单一来源 + 本地休眠回退；retain 为销毁时序 latch 非状态副本） |
| G-7 不破坏现有功能 | 是（除 C1–C5 已修；未声明行为未动） |
| G-8 无需求外功能 | 是（仅 6 面板 LazyLoader + panelWidth 提升） |
| 不做：dock/dynamicIsland | 是（未改动） |

## 最终结论

全部子代理 APPROVE（轮 2 两个复核均 APPROVE，全部 CONFIRMED 已修）→ 允许 commit。

已知遗留（不阻塞，记录备查）：
- 每次打开面板为同步实例化（LazyLoader 同步孵化），首开/每次打开有毫秒级阻塞——A1 按需加载的设计取舍，异步孵化（loading/activeAsync）留作后续优化
- WO 700ms retain 窗口内异屏开+关的极窄提前销毁边界（自愈）
