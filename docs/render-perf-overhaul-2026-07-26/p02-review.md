# P02 对抗性审查记录

日期：2026-07-26

## 改动摘要

- `RenderActivity.js`：统一渲染活跃策略（`forResidentSurface` + 48ms paint pulse / 360ms transition pulse 常量），作为既有 `visible`/`servicePollingActive` 门控在渲染帧路径上的延伸。
- 弹出类 21 个 PanelWindow + Wallpaper 内嵌 live overlay：`updatesEnabled: visible` 严格镜像（各自 visible 已含退场保持，构造上不可能截断动画）。
- 常驻三窗接 `forResidentSurface(visible, motionActive, paintPulse)`：
  - **DynamicIslandOverlay**：判据 = 几何驱动器 running / protocolGeometrySettled / swipe / userInteracting / 非 resting 态 / 播放中媒体 / 运行中计时器 / 异步专辑封面解码 / 胶囊透明度过渡带；内容/主题/屏宽事件 360ms pulse，暂停态 seek/accent 48ms pulse。
  - **Dock**：仅 autohide 完全隐藏且静止才冻结（`!dockVisualHidden` 保持显示态恒热）；隐藏态 launch bounce 每 offset tick 自续 pulse（弹跳/回缩/10s 超时回缩全路径保留 pre-P02 露头视觉）。
  - **Wallpaper**：launchpad zoom/dim、cover 淡出、静态图加载中保持热；缓存命中换壁纸走 `staticImage.onSourceChanged/onStatusChanged` pulse。
- settle 不变式：motion→rest 翻转必发 360ms pulse（同事件可能触发判据看不见的 Behavior，如暂停 → 110ms 字形交换）。
- pulse extend-only：新请求取 `max(请求时长, 在途 interval)`，只延不缩。
- 三窗均把首帧 pulse 并入**既有唯一** root `Component.onCompleted`（重复 root handler 是 QML 加载错误，曾在前置工作区状态中实际存在，测试现已锁死单一性）。
- quickshell `proxywindow.cpp`：`setUpdatesEnabled(true)` 补 `window->update()`（Qt 冻结期丢弃 update/expose 请求，解冻必须主动调度否则脏内容滞留）。
- 测试：`test_updates_enabled_gate.py` 10 项契约；qmltestrunner 改写脚手架把 `updatesEnabled` 列入 quickshell 窗口属性 drop 清单；测试桩 PanelWindow 补同名属性。

## 审查方式

三个独立子代理并行对抗审查（互补视角），另有本地静态验证（root handler 查重、qmllint、全量 pytest）。

### 审查一：冻结判据正确性（专攻"动画冻在半路"）

- 裁决：FAIL → 修复后达标。
- **[MAJOR-B] Dock 隐藏冻结 × launch bounce**：判据不含 bounceOffset，弹跳尖端（振幅 33.6px，>21px 即露出屏幕）約 40% 概率定格在可见区；应用启动失败的 10s 超时回缩路径完全无 pulse，残影无限期存留。→ 修复：delegate `onBounceOffsetChanged: if (root.dockVisualHidden) root.requestPaintPulse()` 自续 pulse。
- [MINOR] 暂停态专辑封面异步解码可晚于 360ms pulse → 修复：`artLoading`（MediaView）→ `asyncArtLoading`（Content 聚合）→ 判据项。
- [MINOR] 暂停态外部 seek 2px 进度条陈旧 → 修复：`onMediaProgressChanged` pulse。
- 通过项：pulse extend-only 实现正确；唤醒链路（hover/swipe/状态）全部属性级同步触发无一帧延迟；0.45px 滑出阈值尾巴完全在屏外；island 全树无 loops:Infinite/marquee 残留未覆盖项；Wallpaper dim 与 zoom 同步收敛。

### 审查二：回归与语义保持（铁律 5）

- 裁决：PASS-with-minors（minors 已全部修复）。
- 弹出类镜像逐一核对 visible 表达式（含 NotificationToast displayItems 退场保持、MenuPopup flashHold、Launchpad compositorLayerAnimations 分支）：updatesEnabled=false ⇔ unmapped，数学上不可能截断动画。
- quickshell C++ 三风险排除（读 Qt 6.11 qsgthreadedrenderloop.cpp 源码）：null 守卫、未 expose 时 update() 为 no-op、等值早退无 update 风暴；completeWindow() 重建时重放 mUpdatesEnabled。补帧必要性确认：Qt 冻结期 handleUpdateRequest/handleExposure 双双早退丢请求。
- 冻结无死锁：多窗口 exposed 场景动画走 GUI 线程 m_animation_timer，冻结窗口内 Behavior 照常推进并驱动谓词解冻。
- onCompleted 合并顺序无语义变化；测试脚手架 drop 正则不误删注释行；`property bool updatesEnabled: true` 与 proxywindow.hpp 默认一致。
- [MINOR] 暂停媒体外部 seek / island 居中 x 屏宽变化陈旧 ≤60s → 已修复（onMediaProgressChanged / onScreenWidthChanged pulse）。

### 审查三：守护规则与架构

- 裁决：FAIL → 修复后达标。
- **[MAJOR-A] settle pulse 48ms 截断同事件 110ms 字形交换**（暂停媒体 → 播放/暂停图标冻在 ~10% 透明度，最长 60s 后分钟 tick 自愈）→ 修复：三处 settle pulse 统一改传 `transitionPulseMs`。
- **平行接口判定：不构成**。`updatesEnabled` 是 quickshell 上游既有属性（windowinterface.hpp:151，本项目首次启用）；判据全部复用既有真值源（dockVisualHidden/protocolGeometrySettled/驱动器 .running/capsuleShown/launchpadOpen 等），无第二套可漂移状态；与 servicePollingActive 是同策略双通道（服务探针 vs 渲染帧）职责不重叠。
- **玻璃 region × 冻结互斥由构造保证**：island region 通道变化瞬间令 protocolGeometrySettled 翻 false 即解冻；Dock 冻结期 regionHeight=0 且 glassEnabled=false，恒空 region 无 mismatch。
- **弹簧守护无冲突**：P02 零新增动画于 region 几何通道，判据只读取 R08 驱动器 running；Motion.js:269-272 守护注释仍然为真。无 QSG_ 环境开关引入。
- TopBar mirror-visible 是有原则的保守选择：无常驻无限动画、静止场景图本来零帧、每个静止期变化都必须立即绘制，resident-freeze 净收益为零。
- [MINOR] `forMappedSurface` 死代码 → 已删除（弹出类策略即内联 mirror）；`expanded_timer` 不可达分支 → 已删除；requestPaintPulse 三份复制 → 接受（QML Timer 无法进 JS library，形状被 test_paint_pulse_is_extend_only 三处锁定）。

## 修复后验证

- `test_updates_enabled_gate.py` 10/10；全量 pytest **906 passed（含 272 subtests）无失败**，两轮均未出现挂起。
- 曾有 2 个失败并已根修：qmltestrunner 改写型测试不识别新窗口属性（drop_props 补齐）；island root 重复 `Component.onCompleted`（生产加载会炸的真雷，合并 + 测试锁单一性；Dock/Wallpaper 同类雷一并排除）。
- qmllint：无 syntax / duplicate-property 错误。
- quickshell 增量编译（build-tahoe, Release）通过。

## 残余非阻断项（接受并记录）

- 冻结期极端罕见输入（如封面加载 Error 态个别路径）兜底依赖分钟 tick 全局 pulse（≤60s 自愈），与审查共识一致。
- components/ 子目录未来若出现 PanelWindow 根会漏出 glob 检查（当前穷尽）。
- 验收实测（空闲渲染线程唤醒对比）见部署后数据附录。

## 结论

**PASS** — 两个 MAJOR 与全部可修 MINOR 均已修复并复测，允许 commit + push。

## 部署后实测（附录）

- 待部署后补充：空闲 10s 采样对比（pre-P02：主线程 29 jiffies / 334 次自愿切换，WaylandEventThr 657+355 次）。
