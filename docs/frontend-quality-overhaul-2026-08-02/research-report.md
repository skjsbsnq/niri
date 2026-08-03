# Tahoe Desktop 前端质量、动效与运行时健康度研究报告

**研究日期**：2026-08-02；事实校正于 2026-08-03
**研究性质**：只读源码与日志审计；本报告本身不包含实现改动
**源码基线**：主仓库 `78dc847`，niri `0cf398c4`，Quickshell `5a984c7`
**运行基线**：部署版本与上述源码一致；niri PID 1298，Quickshell PID 1395
**执行入口**：后续实现必须以 `roadmap.md` 为唯一任务清单，以 `CONSTRAINTS.md` 为硬门禁

---

## 0. 结论

项目并不缺动画，也不需要另造一套 shell、控件或 glass API。现有实现已经具备集中 motion profile、reduced-motion、合成器 layer 动画、稳定列表身份、popup 互斥和不可见 surface 停帧等良好基础。

最大的改进空间来自四个系统性缺口：

1. **生命周期没有闭合**：output 移除后 mapped layer 清理不可达；部分历史代码仍依赖可能失效的 output/window 状态。
2. **动画所有权跨层重复**：QML、Wayland surface 和 niri 同时推导几何状态，造成 binding loop、重定向速度丢失以及 blur 纹理频繁重建。
3. **交互原语不完整**：主题、键盘、Accessibility、焦点恢复、异步完成状态没有从共享控件层建立统一契约。
4. **运行时预算缺少硬边界**：日志无限追加、Canvas 跟随 240 Hz 输出全速运行、写任务取消可能阻塞 GUI，内存与纹理也缺少长期遥测。

因此路线图的方向是**原地收敛现有实现**，而不是增加 V2/New/Fixed 旁路。先修稳定性和可观测性，再统一动画与渲染所有权，最后完成视觉和交互系统。

---

## 1. 证据等级

本报告使用以下等级，执行者不得把不同等级混写：

| 等级 | 含义 | 是否允许直接实施 |
|---|---|---|
| `CURRENT-CONFIRMED` | 当前源码与当前会话日志同时支持 | 可以，但任务开始时仍须重查行号和前提 |
| `SOURCE-CONFIRMED` | 当前源码存在确定路径，当前会话未必触发 | 可以，必须先写能捕获该路径的回归测试 |
| `HISTORICAL-CONFIRMED` | 历史 core/日志确认，当前版本状态另有说明 | 仅当当前源码仍保留根因时实施 |
| `RISK` | 存在结构性风险，但没有故障现场或完整因果链 | 必须先复现或建立可判定测试；不得猜修 |
| `PROPOSAL` | 架构研究方向，不是已证实缺陷 | 必须通过路线图中的设计门禁后实施 |

源码是事实权威。日志只能证明其采样窗口内发生或没有发生什么；旧文档中的数字不能冒充当前会话数字。

---

## 2. 当前运行时快照

采样截止 `2026-08-03T08:50:34+08:00`：

| 项目 | 结果 |
|---|---|
| niri / Quickshell 存活时间 | 均约 61 分钟，状态分别为 `Ssl` / `Sl` |
| 当前 boot coredump | 0 |
| 内核严重故障 | 未发现 GPU hang、Xid、OOM、RCU stall、soft/hard lockup |
| 调度状态 | 未发现 D 状态线程；主线程调度计数持续增长 |
| 当前 Quickshell 相关警告 | 1 个 binding loop；1 个 Dock `undefined -> double` |
| 当前 niri 会话日志 | 5,365 行，其中 3,048 次 blur texture 重建 |
| 累计 session.log | 3,547,657,049 bytes；自 2026-06-17 持续追加 |
| Quickshell RSS | 约 659 MiB；线程与 FD 在短采样中稳定 |

这些数据只证明**当前采样窗口没有活跃死锁或崩溃**。它们不能证明长期无泄漏，也不能替代 hot-plug、满盘、慢盘和长时交互压测。

`/boot` 的 FAT 分区另有“未正常卸载”内核警告。这是系统完整性问题，当前没有证据把它归因给 niri 或 Quickshell。

---

## 3. 稳定性与生命周期

### STAB-01 output 移除后 mapped layer 清理不可达

**等级**：`SOURCE-CONFIRMED`，高优先级。

- `niri/src/niri.rs:3290-3300` 的 `Niri::remove_output()` 只向 layer 发送 close，随后先从 layout 移除 output。
- `niri/src/handlers/layer_shell.rs:55-86` 的 `layer_destroyed()` 只扫描 `layout.outputs()`。
- null commit 路径同样先通过现存 output 找 layer，找不到时在 `layer_shell.rs:116-118` 返回。
- `mapped_layer_surfaces.remove()` 只在找到 output 后执行，持有表位于 `niri/src/niri.rs:250-257`。
- 残留条目仍参与动画推进、shader 更新和规则重算。

可以确定的是 map entry、pre-commit hook 与 `MappedLayer` 状态会残留。没有测量 retained GPU bytes，因此不得把它夸写成“已证实永久显存泄漏”。正确修复应在 output 从 layout 消失前完成 layer teardown、Tahoe transform/foreign rect 清理和 map 删除，并覆盖重复热插拔。

### STAB-02 最小化父窗口后打开子对话框可 abort

**等级**：`HISTORICAL-CONFIRMED`，且当前源码需在任务开始时重查。

历史日志在 2026-07-22 记录 Wayland FFI 回调内 panic/abort。既有研究定位到 `niri/src/layout/workspace.rs` 的 `active_window().unwrap()`：活动父窗口被最小化后，dialog 的 `AddWindowTarget::NextTo` 路径可能得到 `None`。该任务必须从真实父子窗口拓扑建立回归测试，不能只把 `unwrap()` 改成返回。

### STAB-03 stale output 与 redraw 生命周期

**等级**：`RISK`。

既有研究指出 `queue_redraw()` 对 `output_state` 的无保护取值，与 grab/动画定时器在 output hot-unplug 时可能交叉。当前没有相应 core。实施前必须先构造“回调已排队 -> output 被移除 -> 回调到达”的测试；若前提不成立，应以证据关闭任务，不做防御式散改。

### STAB-04 layer map MutexGuard 跨越复杂调用

**等级**：`SOURCE-CONFIRMED` 风险。

`layer_map_for_output()` 返回 Smithay `MutexGuard`。现有 commit/destroy 路径让 guard 跨过映射对象构造、foreign rect 清理、pointer 查询和 close snapshot 渲染。当前没有已证实重入，但这使今后一次看似普通的 redraw/working-area 查询可能自锁。方向是缩短 guard 生命周期：锁内只读取或变更 layer map，把渲染、IPC、规则和回调移到锁外。

### STAB-05 Quickshell 运行目录失败路径可返回错误对象

**等级**：`SOURCE-CONFIRMED`，高优先级。

`quickshell/src/core/paths.cpp:116-138` 设置 `instanceRunState`，返回前的 `:141` 却检查 `shellRunState`。实例目录创建失败时可能返回 `&mInstanceRunDir`；`linkRunDir()` 随后又在 `:174` 重新调用并解引用 `baseRunDir()`。应修正现有状态机并复用已验证的指针，不得新增另一套 path helper。

### STAB-06 FileView 写任务取消可阻塞 GUI

**等级**：`SOURCE-CONFIRMED` 风险。

`quickshell/src/io/fileview.cpp:342-355` 在 writer 活跃时同步 `waitForJob()`；`:381-398` 最终调用阻塞等待。生产 QML 中 Wallpaper、Apps、Clipboard 等确有 blocking 配置或显式等待。没有实测 stall，因此任务必须先用可控慢 writer 证明 event loop 仍可响应，再将现有 operation 状态机改成串行排队/完成回调，不得另加一个 FileView2。

### STAB-07 历史 niri 重入死锁已修复

**等级**：`HISTORICAL-CONFIRMED / CURRENT-FIXED`。

历史 core 11605 卡在 `cursor_image` 重入 PointerInternal mutex；core 3020 卡在 `on_ungrab` 同类重入。修复提交 `5a8bf3d8` 与 `16696344` 均在当前 `0cf398c4` 祖先中。后续重构必须保护以下不变量：Smithay pointer/grab 回调内不得重新调用 `pointer.current_location()`，必须使用正确维护的缓存位置。

---

## 4. 崩溃记录的校正

旧草稿曾把 Quickshell 历史 core 与 `QsPaths::linkRunDir()` 直接关联。该归因不成立，必须删除：

- 2026-07-27 PID 126141 的完整 SIGSEGV 栈落在 `WifiDevice::setScannerEnabled -> NMNetwork::visibilityChanged -> NetworkDevice::networkAdded -> QML/V4 Object::insertMember`。
- 2026-08-01 的 18 个 SIGABRT 是 Wi-Fi 测试上游 SIGSEGV 后启动的 crash reporter；reporter 又因 Qt platform 初始化失败而 abort。可见 core 是 reporter 的二次失败，不含原始 SIGSEGV 栈。
- 当前实例创建 runtime directory 成功，也没有崩溃。

因此：`paths.cpp` 是独立的源码缺陷；历史 Network/QML core 是另一事件；8 月 1 日原始 SIGSEGV 根因未知。路线图不得把三者合并成一个“已复现崩溃修复”。

---

## 5. 渲染性能与 Glass

### PERF-01 动画期 blur texture 高频重建

**等级**：`CURRENT-CONFIRMED`。

`niri/src/render_helpers/blur.rs:203-240` 要求 texture pyramid 的尺寸、格式和引用状态兼容；step 0 尺寸变化会截断并重建整座金字塔。当前会话的重建日志全部以 `size_changed=true` 为主，并在交互 burst 中高频出现。

日志证明重建事件很多，源码证明它会创建 GL texture；日志没有单次分配耗时、GPU stall 或带宽数据。因此旧报告中的“不是带宽问题，只是分配开销”是过度排他结论。正确路线是先增加采样归因，再实现容量复用、尺寸量化或稳定 surface envelope，并以 frame trace 证明收益。

### PERF-02 client-driven resize 绕过 capture-band 稳定策略

**等级**：`SOURCE-CONFIRMED`。

现有 capture-band 量化主要识别 niri 自己驱动的 layer transform/open/close。灵动岛、NotificationToast、Control Center 等客户端尺寸变化表现为普通 surface commit，仍可能逐尺寸穿透。固定最大 surface envelope、内部 clip/morph 和 niri 纹理容量复用必须作为同一架构方向协同，不能各自再造一套动画时钟。

### PERF-03 Weather Canvas 跟随 240 Hz 全速运行

**等级**：`SOURCE-CONFIRMED`。

输出配置为 `2560x1600@239.998`。`WeatherBackground.qml:1003-1055` 使用 `FrameAnimation`，每次触发都创建 `nextBands` 和对象、更新全部粒子并全量 `requestPaint()`。`frameBaseDt=33ms` 只是步长基准，不是 30 fps 节流。父级已正确限制为天气页可见且非 reduced-motion；剩余工作是 active 状态内的 30/60 fps accumulator、数据复用和功耗预算。

### PERF-04 Quickshell 内存基线偏高但未证实泄漏

**等级**：`RISK`。

短采样中 RSS 从约 598 MiB 增至约 659 MiB，FD 和线程数稳定。必须记录至少 60 分钟 PSS、Private_Dirty、QObject/texture cache、FD 与场景循环后的 retained delta，之后才能决定是否存在泄漏。禁止只凭 RSS 上涨删除缓存。

### GLASS-01 现有管线的结构事实

Tahoe glass 由 Quickshell 通过 `tahoe_glass_v1` 提交 region，niri 捕获背景、运行 dual-Kawase blur 并在 postprocess 阶段完成 tint、饱和、折射、边缘高光和内阴影。当前协议以 request 为主，客户端很难知道 transform 已完成或 region 被拒；多 region 又可能重复捕获与模糊。

旧报告提出的共享 backdrop、线性光/半浮点链和协议完成事件都是 `PROPOSAL`，不是可以跳过基线直接落地的 bugfix。路线图为它们设置独立任务和 A/B 证据门禁，但对外仍只能保留一套 TahoeGlass API；硬件能力回退属于同一实现的 capability 分支，不得暴露第二套用户接口。

### GLASS-02 待任务前重验的既有发现

以下结论有源码依据，但本轮没有逐项运行时复现，任务开始时必须重新点验：

- capture padding 不应随 interaction/tint 动画改变；否则捕获尺寸会抖动。
- `material_alpha == 0` 时不应继续支付完整捕获与 blur 成本。
- `pending_dirty` 的 healable overflow 可能长期阻塞 region morph；协议目前缺乏拒绝/完成反馈。
- subsurface 传入 redraw attribution 前应解析到 root surface，避免退化为全输出 redraw。
- 重叠 glass 的双重 blur、自阴影进入捕获带、8-bit 非线性 blur 都是质感与成本风险，必须用图像与 GPU 证据判定，不能只凭主观观感改 shader。

---

## 6. 动效衔接

### MOTION-01 灵动岛 binding loop 当前存在，但精确闭环尚未证实

**等级**：`CURRENT-CONFIRMED`。

当前 Quickshell 日志稳定报告 `DynamicIslandOverlay.qml:251` 的 `geometryRevealProgress` binding loop。可以确认该属性读取 morph base、target、animated height，并在退化分支读取 `protocolGeometrySettled`；后者读取 islandSurface 几何。

旧草稿写出的完整闭环和“Qt 截断后会产生任意值”没有足够源码/运行时证据，必须删除。修复任务应使用 QML binding profiler 或可观察求值计数先还原真实依赖图，再把 reveal progress 改为单向 driver/latch，验收标准是日志零 loop、状态连续和无重复时钟。

### MOTION-02 中途重定向与多时钟

**等级**：`SOURCE-CONFIRMED`。

灵动岛当前会停止并 restart 部分 spring/ease，尺寸、圆角、底色又使用不同持续时间。中途反向可能保持位置连续却丢失速度，展开内容 reveal 还可能因重新锁存 base 而回退。方向不是增加第三个 progress，而是指定唯一几何 driver，所有派生值为该 driver 的纯函数，并使用现有 niri/Animation 速度接口完成 retarget。

### MOTION-03 操作提交时机不一致

**等级**：`SOURCE-CONFIRMED`。

通用 ButtonSurface 在 click/release-inside 提交；灵动岛媒体动作在 press 时提交，计时器 release 时又未检查指针是否仍在控件内。拖出取消因此失效。所有业务动作必须统一到 release-inside/TapHandler 语义，pressed 只管理视觉和 interaction lease。

### MOTION-04 需要一并收敛的时序问题

既有研究还发现 OSD 退场被更新时硬跳回满不透明、swipe 只按位移无速度、input mask hold 使用与实际 ease 不同的固定时长、reduced profile 与 dismiss afterimage 不一致、媒体按钮绕过通用 press token。它们共享“时间常量分散、状态完成无 owner”的根因，应在同一 interaction-state 任务中完整收敛，而不是逐个补 magic number。

---

## 7. 视觉质感与用户体验

### UX-01 主题与材质存在孤岛

**等级**：`SOURCE-CONFIRMED`。

`shell.qml:1199-1253` 实例化 NotificationCenter、Battery、Wi-Fi、Fan 和 Clipboard 时没有传递 `darkMode`。这些组件大量使用固定亮材质和深色文字。共享 `ButtonSurface`、`ToggleSwitch` 又硬编码蓝色，忽略用户强调色。

应把现有 `SettingsTheme.js` 收敛成所有生产控件的语义 token authority，覆盖 fill、stroke、primary/secondary text、accent、danger、focus、disabled。不得创建 `ThemeV2.js`，也不得让旧 literal path 长期共存。

### UX-02 共享控件缺少键盘与 Accessibility 契约

**等级**：`SOURCE-CONFIRMED`。

TopBar 已有稳定的键盘遍历，但 ButtonSurface、ToggleSwitch、MenuRow、TahoeSlider、TahoeSegmented、设置侧栏和多数 popup 仍是 `Item + MouseArea`。生产 QML 中 `Accessible.*` 为零命中；Clipboard popup 明确 `focusable: false`，灵动岛含交互内容却整体不可聚焦。

正确路线是原地升级共享控件：role/name/value/action、Tab/Shift-Tab、Enter/Space、方向键、可见 focus ring、Escape 和关闭后焦点恢复。不得为“键盘版”复制一套控件。

### UX-03 popup 几何没有垂直策略

**等级**：`SOURCE-CONFIRMED`。

`PopupGeometry.popupTop()` 只计算 anchor 下方位置，不接收 screenHeight/popupHeight，也不翻转。部分 popup 的 `Math.max(180, availableHeight)` 在可用空间不足 180 时反而保证越界。应让现有 PopupGeometry 返回 placement、top 和 maxHeight，统一下放/上翻/capped scroll。

### UX-04 异步动作把 spawn 当成成功

**等级**：`SOURCE-CONFIRMED`。

`CommandRunner.runDetached()` 在 `execDetached` 没抛异常时立即返回 success。Power、Search 等调用者随即关闭 UI；命令后续非零退出无法反馈。Appearance 先持久化 desired state，并用 `|| true` 吞掉后端失败，又把请求值显示为 applied。

应原地建立 `queued/started/completed/failed/timeout` 状态，区分 desired 与 applied；失败保留可重试上下文并通过现有通知/toast 通路反馈。不得新增“高级模式”或额外设置开关。

### UX-05 字体、滚动与图标系统缺乏统一治理

**等级**：`SOURCE-CONFIRMED`，需要视觉矩阵验收。

正文 UI 没有统一字体 family/weight/size authority，大量 11 px literal；可滚动视图普遍没有 overflow/position 指示；未知 symbol 可能渲染为空，应用 fallback 可能让不同程序共用同一伪装图标。Material 色值、符号字体和 PNG 也造成笔画与色彩语言混杂。

这些问题应通过现有 theme/icon/control 层治理，不得硬编码“macOS 仿制资源包”，也不得加入用户未要求的新主题、皮肤或图标选择功能。

### UX-06 后端失败重试没有预算

**等级**：`SOURCE-CONFIRMED`。

brightness udev monitor 停止后固定 1 秒永久重启，缺少 capability gate、重试上限和退避；fallback poll 又会在状态翻转时交替接管。应使用现有 service authority，加入 capability、degraded 状态和有上限的指数退避，不新增第二个 brightness service。

---

## 8. 运维与可观测性

### OPS-01 niri 会话日志无轮转

**等级**：`CURRENT-CONFIRMED`。

`scripts/tahoe-niri-session.sh:33-35` 对同一文件永久追加，当前已约 3.55 GB。应在 session 启动前使用明确的 size/count policy 轮转，并降低稳定生产路径的 debug 噪声；保留用户可临时启用 debug 的现有入口，不引入常驻日志服务。

### OPS-02 shell 诊断链不直观

niri spawn 子进程 stdio 被定向到 null，但 Quickshell 自带日志环仍可用。路线图不要求把所有 QML stdout 合并进 3.55 GB session.log；应提供受限、可轮转、可定位实例的诊断入口，并保持敏感数据最小化。

### OPS-03 内存与 GPU 预算需要可重复基线

最终验收必须记录：PSS/Private_Dirty、FD/线程、每场景 blur allocation/capture 次数、frame-time 分位数、240 Hz 天气页 CPU、重复 hot-plug 后 mapped layer 数量。没有这些证据，不得用“感觉更流畅”关闭性能任务。

---

## 9. 已经做对、必须保护的实现

- Control Center 使用单一 `morphProgress` 驱动相关几何与交叉淡化。
- Motion profile 集中在 `Motion.js`，并有真实 reduced-motion 策略。
- Settings、Launchpad、popup 等大量 map/unmap 动画已由 niri layer rules 所有。
- ShellPopupState 与 PopupDismissLayer 集中治理 popup 互斥、outside dismiss 和 afterimage。
- Notifications、AppsSettings、Weather、Search 等已有 generation/latest-wins 或稳定 identity 机制。
- 多数 PanelWindow 使用 `updatesEnabled: visible`；天气、发现服务等已有生命周期 gate。
- niri pointer 回调的重入死锁修复必须保留。
- Tahoe glass region 的尺寸 floor、半径 ceil 量化及禁止 overshoot 约束必须保留，除非经过同等严格的协议与图像证明整体替换。

---

## 10. 明确非目标

- 不新增用户没有要求的功能、页面、设置项、主题、动画模式或实验开关。
- 不创建与现有 Motion、Theme、TahoeGlass、FileView、CommandRunner、PopupGeometry 重叠的第二套接口。
- 不以“像 macOS”为理由逐像素照搬第三方资源；目标是内部一致、可读、稳定和响应自然。
- 不把历史 core、单次 RSS 上涨或主观截图观察写成当前已复现缺陷。
- 不在未经用户同意时重启当前桌面会话或执行真实 suspend/reboot/poweroff。

本报告中的实现顺序、任务边界和验收门槛全部落在 `roadmap.md`；执行器不得从本报告自行挑选工作。
