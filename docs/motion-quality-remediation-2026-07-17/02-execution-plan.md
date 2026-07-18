# 02 · 修复执行计划：R00–R19 串行驱动器

日期：2026-07-17
性质：本轮整治的**执行驱动文件**。任何实施会话必须按 [README.md](README.md) 的铁律与执行循环推进：**严格串行 → 实施 → 审查（/code-review 或等效独立审查）→ 验收 → commit → push → 下一任务**。问题编号 `#n` 均指 [01-research-report.md](01-research-report.md) §4 清单。

任务排序原则：先快赢 bug（建立节奏）→ 用户四个点名问题（R04–R08）→ 同族推广（列表/控件/面板）→ 参数与外围收尾。每个任务 = 恰好一个提交 = 可单独 revert。

---

## 0. 状态表（执行时就地更新，勾选进该任务的提交）

| 任务 | 名称 | 覆盖问题 | 规模 | 状态 | 审查/验收记录 |
| --- | --- | --- | --- | --- | --- |
| R00 | 基线锁定 | — | S | DONE | [R00](acceptance/R00-baseline-2026-07-17.md)：747 tests 全绿、validate 过、嵌套冒烟过、grep 基数 124/10/0/27 |
| R01 | 弹跳物理统一（死 bounce + 点击上行） | #74 #75 | S | DONE | [R01](acceptance/R01-bounce-physics-2026-07-17.md)：双 agent 审查 3 问题已修，749 tests 全绿 |
| R02 | Spotlight 打字闪烁修复 | #86 | S | DONE | [R02](acceptance/R02-spotlight-stable-rows-2026-07-17.md)：双独立复审 PASS，752 tests 全绿，宿主/嵌套验收通过 |
| R03 | Launchpad 打字脉冲修复 + 图标异步 | #83 #84 #85 | S | DONE | [R03](acceptance/R03-launchpad-filter-icons-2026-07-17.md)：最终独立复审 PASS，754 tests 全绿，宿主/嵌套验收通过 |
| R04 | WiFi 弹窗稳定列表（点名②） | #7 #8 #9 #10 | M | DONE | [R04](acceptance/R04-wifi-stable-list-2026-07-17.md)：终审 FINAL PASS，758 tests 全绿，宿主 30s+/嵌套验收通过 |
| R05 | 剪贴板弹窗稳定列表与动画（点名①） | #1 #2 #3 #4 #5(部分) | M | DONE | [R05](acceptance/R05-clipboard-stable-list-2026-07-18.md)：终审 FINAL PASS，762 tests 全绿，宿主/嵌套验收通过 |
| R06 | 菜单时序重排（点名③） | #13 #14 #15 #16 #17 #19 | M | DONE | [R06](acceptance/R06-menu-timing-2026-07-18.md)：终审 FINAL PASS，764 tests 全绿，flashHold 门控幽灵点击/陈旧 close，宿主部署 parity OK |
| R07 | 灵动岛换场重构（点名④a） | #20 #24 #25 #26 #27 #28 #29 | L | DONE | [R07](acceptance/R07-island-crossfade-2026-07-18.md)：764 tests 全绿，crossfade 架构落地，独立审查与手测矩阵待补（见 acceptance） |
| R08 | 灵动岛几何手感 + OSD 进场（点名④b） | #21 #22 #23 | M | DONE | [R08](acceptance/R08-island-geometry-osd-2026-07-18.md)：独立审查 CLEAN（a–i 全 PASS），766 tests 全绿，白条 bug（媒体态收起底部亮条）随 #22 floor 量化根治，嵌套冒烟过；R07 补审出 1 高危另立 follow-up |
| R09 | Toast 栈重构与退出统一 | #31 #32 #33 #34 | M–L | DONE | [R09](acceptance/R09-toast-stack-2026-07-18.md)：稳定 id 栈与三路统一退出，770 tests 全绿，guardrail/validate/嵌套冒烟/部署 parity 通过 |
| R10 | 通知中心稳定列表与入场 | #35 #36 | M | DONE | [R10](acceptance/R10-notification-center-stable-history-2026-07-18.md)：entry/group 双层稳定 identity，新增行入场与单删两阶段退出，776 tests 全绿，三路终审 CLEAN |
| R11 | 侧栏系统页（进程表/活动环/morph） | #55 #56 #57 #58 #59 | M | DONE | [R11](acceptance/R11-left-sidebar-system-motion-2026-07-18.md)：pid+starttime 稳定 identity，780 tests 全绿，三路终审 CLEAN，宿主 32s 观测/嵌套/部署 parity 通过 |
| R12 | 控制中心收尾（滑块插值/模块列表） | #47 #48 #49 #50 | S–M | PENDING | |
| R13 | 弹窗控件合并统一（防腐化） | #5(余) #11 #12 #18 #40 #66 #67 #68 #69 + S4/S5 | M–L | PENDING | |
| R14 | 锁屏动效包 | #38 #39 #40(余) | S–M | PENDING | |
| R15 | KDL 参数修正包 | #6 #89 #95 #96 #97 #100 | S | PENDING | |
| R16 | Overview / 切换器收尾 | #42 #43 #44 #45 #46 | S | PENDING | |
| R17 | Dock 布局动画 | #72 #73 #76 #77 #78 #79 #80 #81 #82 #90 | M | PENDING | |
| R18 | 外围收尾（顶栏/设置/侧栏细节/壁纸/托盘） | #51 #52 #60–#65 #70 #71 #87 #88 #91–#94 | M | PENDING | |
| R19 | 治理收尾与总验收 | 复测全量 | S | PENDING | |

**范围外（本轮不做，另立任务）**：#41（有意设计）、#53 设置页懒加载（性能专项）、#98 快照跳过（运行期复现后再修）、#99（既有权衡）、#101/#102 图标体系（视觉基因专项，改动面大需单独立项）。

---

## 1. 通用审查清单（每个任务的审查者都必须过一遍）

1. **范围**：改动是否严格落在该任务"改动清单"内？范围外发现只记 acceptance 不顺手修。
2. **红线**：玻璃 region 几何（GlassPanel x/y/width/height/radius/region\*、Behavior 喂 region 的一切路径）没有 SpringAnimation；弹簧全部在 `useSpring` 门控之后。
3. **无平行接口**：没有新 token 文件、没有新旧控件/机制并存、合并类任务旧实现零残留（grep 证据进 acceptance）。
4. **全状态**：深色/浅色、reduced profile（动画归零或降级路径存在）、`useSpring=false` 回退、服务不可用占位态都被处理。
5. **无藏匿**：无 TODO/FIXME/注释掉的半成品；没有用开关把没做完的部分默认关闭。
6. **绑定安全**：新 Behavior 不与既有 SpringAnimation/States 双驱动同一属性；`Behavior on height` 类改动确认没有喂进 spring 或造成布局循环。
7. **测试**：受影响的 `tahoe-shell/tests/tst_*` 已更新且通过；涉 KDL 的任务 `niri validate` 通过。

## 2. 通用验收矩阵（涉弹窗/列表的任务必测）

开/关 ×3 快速连点、Esc、点外关闭、开着时数据刷新（rescan/新通知/进程 tick）、深浅色切换、reduced profile、`useSpring=false`、嵌套会话（TAHOE_NESTED_SESSION）冒烟。列表类另测：滚动位置在刷新后保持、hover 不丢失、增删有过渡、无整表闪烁。

---

## R00 基线锁定（S）

**目标**：为全轮建立回归锚点。
**改动清单**：不改产品代码。跑通并记录：现有 tst_* 全量结果；`niri validate -c ~/.config/niri/tahoe/config.kdl`；嵌套会话启动冒烟；对四个点名现象录基线描述（复现步骤）；记录 §量化 grep 四项基数（Behavior 计数 / press 覆盖 / transitions=0 / 零 Behavior 文件数=27）。
**验收**：acceptance/R00 记录齐全。无提交内容时允许仅提交 acceptance + 状态表。

## R01 弹跳物理统一（S）

**目标**：#74 死 bounce、#75 点击 bounce 上行瞬跳——三处弹跳统一为"上行有动画、下行弹簧/缓动"同一套物理。
**文件**：components/DockMinimizedWindow.qml、components/Dock.qml、components/WindowButton.qml、components/Motion.js（如需新增时长 token，只加在 Motion.js）。
**改动清单**：
1. DockMinimizedWindow：废除"16ms Timer 归零 vs 170ms Behavior"结构（:101-104,248-259），改为显式上/下两段动画（上 ~90ms InQuad/OutQuad 对齐启动循环、下 spring/ease 双分支），肉眼可见完整弹跳。
2. Dock 固定图标 bounce（:1253-1260）与 WindowButton bounce（:321-358）：上行 14px 改为动画（对齐启动循环 InQuad 上行），下行维持 springBouncy/ease 双分支。
3. 三处时长/高度常量收敛到 Motion.js 既有 dockLaunchBounce\* 族或新增单一 token，不留三份魔法数。
**明确不做**：不合并三处代码结构（结构合并属重构，本任务只统一物理与 token）。
**审查加查**：bounceOffset 无双驱动（Behavior 与显式动画不并存于同一属性）。
**验收**：点击 dock 图标/窗口按钮/还原最小化窗口，三处弹跳肉眼一致且上行可见；reduced profile 下降级为单跳或无动画。

## R02 Spotlight 打字闪烁修复（S）

**目标**：#86——打字不再整片重排。
**文件**：components/Spotlight.qml、services/Search.qml（仅当稳定 key 需服务侧提供时）。
**改动清单**：flatRows 行对象提供稳定 key（provider+resultId+kind），ScriptModel 配 `objectProp`（对齐 Dock.qml:1393 范例）；buildSections/flattenRows 对未变化条目**复用同一对象**（按 key 缓存），只有真正新增/移除的行发生 delegate 创建/销毁。
**明确不做**：不改结果渲染样式、不加 hover 过渡（归 R18）。
**验收**：连续键入/删除时，既有结果行的 delegate 不重建（Component.onCompleted 计数或 objectName 日志证据进 acceptance）；选中高亮弹簧行为不回归；图标不再逐字重载。

## R03 Launchpad 打字脉冲修复 + 图标异步（S）

**目标**：#83 #84 #85。
**文件**：components/Launchpad.qml。
**改动清单**：
1. `onQueryChanged`(:361-373) 不再调用 playGridEnter()；整场入场只在 open 时播。
2. 筛选变化改轻量过渡：图标格 opacity 短淡入（≤fadeFast）或无动画直换，二选一（手测定，结论进 acceptance）；`contentX=0` 复位保留但不叠加整场缩放。
3. appIcon `asynchronous: false→true`(:770)，并确认无首帧空白回归（占位底保留）。
**验收**：Launchpad 内打字网格不再脉冲缩放；开场入场动画不回归；应用多时首帧无卡顿恶化。

## R04 WiFi 弹窗稳定列表（M，点名②）

**目标**：#7 #8 #9 #10——rescan 不闪卡。**本任务建立 S2 家族的标准修法，后续 R05/R10/R11/R12 复用同一模式。**
**文件**：services/Controls.qml、components/WifiPopup.qml。
**改动清单**：
1. 服务层：`wifiNetworks` 改为**按 SSID 稳定复用条目对象**（内部缓存 map，字段就地更新、排序稳定）；扫描进行中**保留上一份非空列表**（scanner toggle 期间不发布空数组），扫描完成后增量合并。服务对外接口（属性名/字段）不变——禁止另起炉灶。
2. 视图层：netList 配稳定 key（ScriptModel objectProp:"name" 或等效）；add/remove/displaced Transition（fadeFast + elementMove）；列表高度与面板高度 `Behavior on`（**eased NumberAnimation only**——面板高度喂玻璃 region）。
3. "未发现网络"占位仅在"扫描完成且确无结果"时出现，不在扫描瞬间闪现。
4. PSK 展开（:377-385）：高度 0↔42 加 elementResize 动画（visible 用 opacity 守卫）。
5. 30s 定时 rescan 保留——增量化后自然不闪；验收必须覆盖"面板开着等 30s"。
**审查加查**：面板高度动画路径确认无 spring；服务字段消费方（ControlCenter WiFi 模块也读 wifiNetworks）无回归。
**验收**：点"重新扫描"卡片不闪不塌缩；行内信号强度数字就地更新；开着 30s+ 无周期性闪烁；连接/断开行有过渡。

## R05 剪贴板弹窗稳定列表与动画（M，点名①）

**目标**：#1 #2 #3 #4 + #5 中的行 hover。
**文件**：services/ClipboardHistory.qml、components/ClipboardPopup.qml。
**改动清单**：
1. 服务层：refresh 按 cliphist 条目 id 增量合并（复用 R04 模式），打开弹窗时已有数据不清不闪；`entries`/`pinnedEntries` 稳定 identity。
2. 两个 ListView：稳定 key + add/remove/displaced Transition；删除=滑出+折叠、固定=移动过渡。
3. 面板高度 `Behavior on`（eased only）。
4. ClipboardRow hover 色 ColorAnimation（fadeFast）；行按压用 Motion press token（行是本地组件，不在 R13 合并范围）。
5. 打开时 refresh 保留但不再引起视觉重建。
**明确不做**：IconButton/TextButton 的 hover/press（归 R13 统一控件）。
**验收**：开弹窗无开场重建闪烁；删除/固定/复制置顶全部有过渡且滚动位置保持；高度变化平滑。

## R06 菜单时序重排（M，点名③）

**目标**：#13 #14 #15 #16 #17 #19——点菜单项的响应链路对齐 macOS。
**文件**：components/MenuRow.qml、components/Motion.js、components/MenuPopup.qml、components/AppMenuPopup.qml、services/AppMenu.qml（仅稳定 key 需要时）。
**改动清单**：
1. 闪烁时序：menuFlashInterval 70→~55ms、保持 2 次；**activated() 在点击时立即发出**（动作不等闪烁），闪烁变纯视觉，闪完由父级 close。总"点击→动作"延迟 ≤ 1 帧，"点击→菜单消失"≈ 110ms 闪 + 合成器 pop-slide 180ms。Motion.js token 同步改（menuFlash\*），reduced 路径保持跳过闪烁。
2. 删除 MenuRow 行级按压缩放（:77-84 scale 部分），保留高亮反馈。
3. MenuPopup：`implicitHeight` 二值切换(:37) 改为确认卡展开动画——确认卡 opacity+height 进出（elementResize/panelExit），窗口高度随 Behavior 平滑（eased only，喂 layer surface 尺寸）。
4. "窗口"行(:113-119) 接 `shell.toggleWindowOverview()`；当前应用行(:105-111) 接 `appMenuService.activateFocusedWindow()` 或移除——二选一，结论进 acceptance。信号经既有 shell 链路，不新增平行通道。
5. AppMenuPopup(#19)：nativeMenuItems 稳定 key（Repeater/ScriptModel objectProp），refresh 不整列表重建。
**审查加查**：flash Timer 生命周期（菜单关闭中断闪烁不悬挂）；MenuRow 全部 6+ 使用现场（MenuPopup/AppMenuPopup/TrayMenu/ProcessMenu/Dock 菜单）行为一致。
**验收**：点"设置/关于"动作立即发生、菜单快闪后利落淡出；点"重启"确认卡平滑展开；全部菜单现场回归手测。

## R07 灵动岛换场重构（L，点名④a）

**目标**：#20 #24 #25 #26 #27 #28 #29——换场从"全隐-换-全现"改为连续形变。
**文件**：components/DynamicIslandOverlay.qml、components/DynamicIslandContent.qml、components/DynamicIslandNotificationView.qml、components/DynamicIslandCompactMediaView.qml、components/DynamicIslandMotion.js；tests/tst_dynamic_island_\*。
**改动清单**：
1. **交叉淡化架构**：Overlay 的 contentSwap（:444-467）改为双层——outgoing 场景保持渲染淡出（110ms）+ incoming 同时淡入（170ms）+ ≤6px 方向位移；几何与内容**同一时刻起步**。空胶囊帧消失。scene 持有/释放机制替代现有 latch/hold Timer 群（Content.qml:100-311 中因此多余的补丁一并删除——删除清单进 acceptance）。
2. 输入死区（:585）：enabled 门槛改 `opacity>0.5` 或移除（incoming 可即时交互）。
3. 通知 compact↔expanded（NotifView:52,179,191）：从整层眨眼改为视图内过渡——两布局 crossfade + 内容元素位置过渡，配合几何高度 morph；forceSwap 路径不再全隐。
4. 滑动关闭跟手（NotifView:360-403）：内容 x 跟手指位移，过阈值飞出、未过弹回（springSnappy，useSpring 门控）。
5. 媒体收起硬切（Content.qml:583）：改淡出（contentExitMs）。
6. 封面/图标淡入（CompactMediaView:96-104；播放/暂停字形切换加短 crossfade）（#28）。
**审查加查**：глass region 路径零变化（本任务只动内容层）；多屏 owner/非 owner 角色渲染不回归（screenRole 分支）；tst_dynamic_island 系列全绿（必要时更新断言）。
**验收**：时钟↔媒体↔OSD↔通知↔展开 全部两两切换无空帧、无眨眼；换场中可点击；滑动关闭跟手回弹；reduced profile 退化为纯 opacity。

## R08 灵动岛几何手感 + OSD 进场（M，点名④b）

**目标**：#21 #22 #23。
**文件**：components/DynamicIslandOverlay.qml、components/DynamicIslandMotion.js、components/GlassPanel.qml（仅当量化参数在此调整）。
**改动清单**：
1. **弹簧驱动+钳制管线**：新增驱动属性（spring 驱动，useSpring 门控），islandSurface 几何绑定 `clamp(驱动值, min, max)`，region 提交值继续量化+有界——**满足 guardrail：region 永不越界**。过冲幅度用 clamp 上限压到安全范围（≤ mask/maxCapsule 余量）。若手测弹簧不达预期，回退方案=OutBack 系曲线（仍是 eased），二选一结论进 acceptance。
2. 量化降级：protocolCapsule 宽高 8→2px、半径 4→2（:170-178,269-272）；用嵌套会话实测 morph 期间 TahoeGlass commit 频率与掉帧，对比 R00 基线；超预算则折中（动画期 4px、settle 精确）。数据进 acceptance。
3. OSD 进场：v2OsdEnterMs 0→~80ms（几何快速展开），数值/进度条首帧即显（内容不等几何）；osdImmediateGeometry 分支只保留"OSD→OSD 连续 tick 不重动画"语义。
**审查加查**：mask Region 与 clamp 上限一致；`useSpring=false` 全路径回退 eased；无 Binding loop。
**验收**：展开/收起有弹性且玻璃边缘无阶梯感；音量键连按 OSD 即时跟手、首次出现有 ~80ms 展开而非跳变；VM 模拟（useSpring=false）正常。

## R09 Toast 栈重构与退出统一（M–L）

**目标**：#31 #32 #33 #34。
**文件**：components/NotificationToast.qml、config/niri/tahoe-phase0.kdl（toast 规则）。
**改动清单**：
1. **栈位动画**：废除"数据流过固定槽"的静态绑定（:172-183,196-200）——按通知 id 绑定卡片、槽位变化时 stackY/scale 动画过渡（既有 `Behavior on stackY`(:251-256) 激活为真实路径）；顶卡关闭→下卡动画上移放大；新卡→旧卡动画下移缩小。glass region 仍 eased only（现有约束保持）。
2. 退出词汇统一：点 X（:700）与超时路径也走"滑出+淡出"（与 swipe :399-424 同语言、同时长 panelExit）。
3. 删除 swipeAnim 死代码（:450-456）。
4. KDL：toast layer-close `opacity-to 0.35→0`（:646，完全淡尽）；`niri validate` + 重部署。注意 QML 内部滑出与合成器 slide 的叠加——QML 滑出完成后再 unmap（守卫式 visible）或削减合成器 close 位移，二选一手测定，结论进 acceptance。
**审查加查**：三卡满栈 + 快速连发通知的槽位竞争（同 id 复入、清空 stagger 与新栈位动画不打架）；tst_notification_swipe_stable_identity 更新通过。
**验收**：关顶卡下卡平滑上移放大；连发 5 条无跳位；swipe/X/超时三种退出观感一致；toast 消失完全淡尽。

## R10 通知中心稳定列表与入场（M）

**目标**：#35 #36。
**文件**：services/Notifications.qml、components/NotificationCenter.qml。
**改动清单**：historyModel/groupedHistory 按通知 id 稳定复用（R04 模式，分组对象含稳定 key）；新行入场动画（右滑淡入，对齐 toast 语言）；单条删除走既有"飞出+折叠"路径（复用清空全部的 NotificationRow 动画，:422-445），删除瞬灭路径清零。
**验收**：新通知入历史无整树闪烁；单删与清空同语言；分组折叠不回归。

## R11 侧栏系统页（M）

**目标**：#55 #56 #57 #58 #59。
**文件**：components/LeftSidebarSystem.qml、services/SystemStats.qml（仅稳定 key 需要时）。
**改动清单**：
1. 进程列表：按 pid 稳定复用（R04 模式），tick 更新就地改字段；排序变化位移过渡（displaced/move 或 y Behavior）；hover 不丢失。
2. 活动环：progress 加插值（SmoothedAnimation/Behavior ~500ms，Canvas 重绘由动画驱动），CPU/内存/GPU 弧长扫动而非跳变。
3. "展开全部"morph：procCard 高度 + tabs/搜索/排序头 opacity 用 ccMorph token（复用，不新增 token）。
4. 磁盘/电池条宽度 Behavior；SegTab/SortHeader/进程行 hover 与激活色 ColorAnimation。
**验收**：盯 30s：列表不闪、环平滑扫动；展开/收起 morph；hover 稳定。

## R12 控制中心收尾（S–M）

**目标**：#47 #48 #49 #50。
**文件**：components/ControlCenter.qml。
**改动清单**：GlassSlider 填充宽/旋钮 x 加 `Behavior { enabled: !dragArea.pressed }`（拖拽仍 1:1 跟手，外部值变更 ~150ms 滑动）；WiFi/蓝牙 moduleList 稳定 key + 增删动画（R04 模式，服务侧已在 R04 稳定则仅视图接线）；PSK 高度动画（复用 R04 第 4 项模式）；模块行 hover ColorAnimation。
**验收**：面板开着按音量/亮度键滑块滑动过去；拖拽无迟滞；模块列表 rescan 不跳。

## R13 弹窗控件合并统一（M–L，防腐化核心任务）

**目标**：S4/S5 主力 + #5(余) #11 #12 #18 #40(按钮部分) #66 #67 #68 #69——**消灭 4+ 份平行内联控件**。
**文件**：新建 components/controls/（或经评估复用 components/settings/controls/ 扩展变体——评估结论进 acceptance，二选一）；改 ClipboardPopup、WifiPopup、BatteryPopup、FanPopup、MenuPopup(ConfirmButton)、NotificationCenter（内联按钮/开关若有）。
**改动清单**：
1. 盘点全部内联 IconButton/PillButton/TextButton/ToggleSwitch/ConfirmButton 定义（含样式差异表），合并为一套共享控件：hover ColorAnimation(fadeFast) + press token(scale 0.96/120ms) + disabled opacity 过渡 + danger/active 变体。
2. **全现场替换，旧内联定义全删**——`grep -n "component IconButton\|component PillButton\|component TextButton\|component ToggleSwitch\|component ConfirmButton" components/*.qml` 结果为零，证据进 acceptance。
3. ToggleSwitch：轨道色 ColorAnimation 与旋钮 x 同步（#11、FanPopup #68 轨道）。
4. BatteryPopup 电量条宽/色 Behavior（#66）、FanPopup 滑块填充 Behavior（#68）、两弹窗按钮 hover/press（#67 #69）。
**审查加查**：这是本轮"禁平行接口"的正面战场——审查者必须确认没有第五份实现残留、共享控件 API 没有为个别现场开洞（变体用 property 不用复制文件）。
**验收**：五个弹窗全部按钮/开关手感一致；深浅色/禁用态过渡正常。

## R14 锁屏动效包（S–M）

**目标**：#38 #39 #40(余)。
**文件**：components/LockScreen.qml。
**改动清单**：锁屏内容进入淡入（session-lock surface 内 QML opacity/轻位移，panelEnter）；解锁成功淡出后释放；认证失败：密码框 x shake（3 摆 ~300ms，位移动画非 spring 亦可）+ 边框 ColorAnimation + 清空输入；statusText 出现/消失淡入；提交按钮 hover/press（用 R13 共享控件或接 token）。reduced profile 全部降级为即时。
**审查加查**：解锁释放时序——淡出动画不得延迟 `locked=false` 的安全语义（先解锁后播剩余淡出，或守卫式且不超过 ~200ms）；认证流程 PAM 逻辑零改动。
**验收**：锁/解锁有过渡；输错密码 shake + 红边过渡；连续输错不叠加动画。

## R15 KDL 参数修正包（S）

**目标**：#6 #89 #95 #96 #97 #100。
**文件**：config/niri/tahoe-phase0.kdl（+部署脚本既有流程）。
**改动清单**：
1. Spotlight close 对称：scale-to 0.992→0.96、transform/opacity 时长按手测微调（#89）。
2. 状态弹窗组（battery/wifi/fan/clipboard/tray-menu）close 加淡出：opacity-duration-ms 0→~120、opacity-to→0；open 淡入感知增强评估：opacity-from 0.84→0.6 区间手测定值（#6 #95）。
3. tray-menu 归组决策：试迁入 pop-slide origin pointer 组，手测 anchor 拉伸问题；不成立则维持现组并在 KDL 注释记录原因（#96）。
4. edge-reveal 各 rule 的 `distance 24` 死参数删除或改注释明确无效（#97）。
5. #100 窗口开合评估：scale-from/to 0.97→0.94 与时长微调的 A/B 手测（**不引入 spring**——既有性能注释禁止；不碰 motion-profile 管理面四节点）；允许"维持现状"结论。
6. `niri validate` + 重部署 + 全弹窗开关回归。
**审查加查**：diff 仅触及 layer-rule 与 window-open/close 节点；MOTION_PROFILE_SPRINGS 管理面零改动。
**验收**：每条弹窗开/关手测记录（对比 R00 基线描述）；validate 通过。

## R16 Overview / 切换器收尾（S）

**目标**：#42 #43 #44 #45 #46（#41 有意设计不动）。
**文件**：components/WindowOverview.qml、components/TaskSwitcher.qml。
**改动清单**：Overview ensureVisible 的 contentY 改平滑滚动（NumberAnimation elementMove）；选中卡底色/边框 ColorAnimation + 宽度 Behavior；Flow 增减 move/displaced 过渡。TaskSwitcher：确认释放选中卡短 pop（scale 1→1.06→1 ~150ms）后关闭；卡 hover 色过渡、焦点点宽度 Behavior；滚动与高亮 spring 同步（positionViewAtIndex 配动画或高亮以视口为准）。
**验收**：键盘连续导航视口平滑、选中态过渡；切换器确认有反馈；面板本身仍瞬时（不回归 #41 设计）。

## R17 Dock 布局动画（M）

**目标**：#72 #73 #76 #77 #78 #79 #80 #81 #82 #90。
**文件**：components/Dock.qml、components/WindowButton.qml、components/DockMinimizedShelf.qml、components/DockMinimizedWindow.qml、components/TopBar.qml、（若选 layer-rule 方案则 +kdl）。
**改动清单**：
1. dockChrome 宽度 Behavior（elementResize，**eased only**——glass region 跟随此宽度）；section/viewport 宽度同步过渡。
2. 固定区 Repeater 补 objectProp（对齐窗口区 :1393 范例）；pin/unpin/重排图标 x 位移动画，放大态不丢。
3. WindowButton 槽位 x/width Behavior、运行指示点宽/色过渡、悬停名牌 x/y 过渡。
4. DockMinimizedShelf：进出场（scale 0.9+fade in / fade out）、Row 位移过渡；缩略图 hover 边框过渡。
5. 全屏过渡（#76 #90）：dock 与 topbar 由 `visible` 瞬切改**范式 B**——QML 滑出/淡出（守卫式 visible: open || opacity>0.01），或给两 namespace 加 layer-rule；二选一（倾向 QML，理由：常驻 surface 反复 map/unmap 代价高），结论进 acceptance。
6. #82 评估项：dock 右键菜单已有合成器 pop-slide origin pointer——手测确认原点感是否达标；达标则关闭该项，不达标补 QML transformOrigin 缩放。
**审查加查**：放大波/autohide/启动弹跳零回归（Dock 最精华部分）；dock 宽度动画与 autohide 滑动不打架。
**验收**：开关窗口 dock 宽度平滑伸缩、图标滑移让位；pin/unpin 不闪；最小化缩略图优雅进出；进出全屏 dock/顶栏有过渡。

## R18 外围收尾（M）

**目标**：#51 #52 #60 #61 #62 #63 #64 #65 #70 #71 #87 #88 #91 #92 #93 #94。
**文件**：TopBar.qml、SettingsPanel.qml、LeftSidebar.qml、LeftSidebarWeather.qml、WeatherBackground.qml、MeteoIcon.qml、Tray.qml、Spotlight.qml、Wallpaper.qml。
**改动清单**：顶栏角标缩放+淡入进出（#91）、全部按钮 hover ColorAnimation（#92）、电池填充 Behavior（#93）；设置换页标题与正文同步过渡+返回/刷新键淡入（#51 #52）；侧栏切标签子页 crossfade+标签色过渡（#60）；天气刷新按钮旋转动画+按钮反馈（#61）、温度条过渡（#62）、空态/横幅过渡（#63）；天空渐变 ColorAnimation（#64）、MeteoIcon crossfade（#65）；托盘增减进出场（#70 #71）；Spotlight 关闭对称 QML 侧评估——关闭走高度收缩+淡出再 unmap（范式 B 化）或维持 R15 合成器参数，二选一（#87，与 R15 结论衔接）+ 结果行 hover 过渡（#88）；壁纸 zoom/dim 扩展到动态壁纸层（#94）。
**验收**：逐项手测勾选表进 acceptance。

## R19 治理收尾与总验收（S）

**目标**：全轮闭环。
**改动清单**：复跑 R00 的四项量化 grep 记录前后对比（目标：transitions>0 覆盖全部动态列表、零 Behavior 文件仅剩基建类、press/hover 覆盖全部交互现场）；四个点名现象逐一对照 R00 基线复测并录结论；全量 tst_* 通过；更新治理测试与相关 policy 文档索引；扫描 TODO/FIXME 零残留；memory 索引更新。
**验收**：acceptance/R19 含前后对比表；状态表全 DONE。

---

## 3. 执行提醒（从上一轮踩坑继承）

- niri 子模块改动（本轮仅 R09/R15 可能涉 config，不涉子模块源码；若意外需要）：先推子仓 tahoe-layer-animations 再推父仓。
- KDL 的 layer 测试有 3 个 pre-existing "独立跑过、全量并行挂"的 flaky（closing layer clock 顺序），验收时独立跑，不误判为回归。
- 改 `Behavior on height` 喂玻璃面板时，先确认该高度没有同时被 States/其它动画驱动。
- 每任务 acceptance 必含：审查方式与结论、验收命令输出摘要、手测矩阵勾选、二选一决策记录、范围外发现待办。
