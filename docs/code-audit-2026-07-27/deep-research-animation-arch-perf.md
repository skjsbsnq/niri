# Tahoe Desktop 深挖研究：动画衔接 / 渲染性能 / 架构维护（2026-07-27）

只研究不修改。基线：主仓库 `42039bb`（+工作树 Dock hover 标签改动），niri `0faa78bd`，quickshell `e8c1acb`。
本报告是 `verified-findings.md`（F-01~F-13、P-01~P-04）之上的增量：四路并行源码深读（compositor 动画、shell 动效、渲染性能、架构维护），全部行号经代理直读核实。方案均允许魔改 niri/quickshell。

---

## 第一部分：niri compositor 动画衔接（编号 A-*）

时间源核验结论（健康）：动画时钟 vblank 对齐——`niri.rs:5039-5043` 每次 redraw 将共享 `Clock` 设为 `FrameClock::next_presentation_time()`（`frame_clock.rs:444-485`），动画为纯时间函数，丢帧只跳变不变慢。问题集中在**速度连续性（C1）**层面。

### A-1（高·全局）动画中途重定向一律硬置速度为零

同一缺陷散布 6 处，均真实可达：

| 位置 | 触发 | 表现 |
|---|---|---|
| `niri/src/layout/scrolling.rs:883-891`（上游 FIXME 承认） | 视图动画中再次 focus-column 等 | 连按呈"顿-走-顿-走" |
| `niri/src/layout/monitor.rs:444-483` | workspace 动画中再切换 | 同上，纵向 |
| `niri/src/layout/monitor.rs:1379-1381` | overview 中途开/关 | 切换瞬间速度归零 |
| `niri/src/layout/tile.rs:638-670`（`restarted(1., 0., 0.)`） | 连续移动列/窗口 | 无动量累积 |
| `niri/src/layout/tile.rs:415-426` | 动画 resize 中再次 resize | 进度归零、零初速 |
| `niri/src/ui/mru.rs:281` | MRU 弹层重定向 | 同类 |

根因：`Animation` 无"当前速度"查询接口，调用方只能做位置续接（C0），`restarted(from, to, 0.)` 不保证 C1。

**方案**：
1. `src/animation/spring.rs` 增加解析导数 `Spring::velocity_at(t)`（under/critical/overdamped 均有闭式解，~30 行）；`Animation::velocity()`：Spring 走解析导数，Easing/Deceleration 用 1ms 有限差分。注意返回值乘回 `clock.rate()`（`mod.rs:61,117` 内部会再除，否则慢放调试双重缩放）。
2. 各调用点改 `restarted(from, to, old.velocity())`。tile move 是归一化 1→0 形式，速度按 `v_norm = v_abs / new_from` 换算。
3. 风险：easing 分支目前忽略 `initial_velocity`（可接受，spring 是默认）；overdamped + 大初速需钳制（如 `±10*|to-from|/expected_duration`）防数值爆炸，`mod.rs:283-291` 已有 10 倍范围兜底。
4. 验证：restart 前后 1ms 差分速度差 < 1% 单测；肉眼连按 focus-column 应连续加速。

### A-2（高）swipe 释放的"HACK 二次吸附"吞掉甩动速度

`scrolling.rs:4154-4163`：`view_offset_gesture_end` 正确把 `SwipeTracker` 速度传入 spring（4158），但紧接的 `animate_view_offset_to_column(None, ...)`（"HACK: deal with snapping to the right edge"）在重算目标与刚设目标差 ≥1 物理像素时（864-869），走 883 分支用**零速度**动画整体替换。触发：宽窗口右缘吸附 / center-focused 修正 / strut 存在时的三指横扫释放。表现：高速甩动释放瞬间急停再缓动，同一手势两种手感。
**方案**：A-1 落地后 883 分支携带速度即自动修复；或最小改法把 HACK 的目标重算提前、只创建一次带速度的动画。验证：宽窗口 + 快速 swipe 逐帧 view_pos 无速度突变。

### A-3（中高）客户端连续 commit 期间 resize 动画反复重置

`tile.rs:316-441`：每次带尺寸变化的 commit → 现有 resize 动画被 take、从插值中间尺寸重建、进度归零、零初速；`scrolling.rs:1591-1593`（FIXME）每次 commit 还重 ease 一次视图偏移。触发：慢客户端多步响应 set-column-width、interactive resize 松手后的尾部 commit。表现：几何橡皮式滞后抖动。
**方案**：`Tile::update_window` 中若 resize 动画未过半（或距上次重建 <1 帧），保留相位只更新 `size_from`（目标追踪而非重启）；scrolling.rs:1593 处目标差 < 阈值则跳过重建。大尺寸跳变仍重启（按 delta 分档）。验证：三连 commit 期间动画 start_time 不变断言。

### A-4（中）F-05 genie 反转速度硬置零（引用）

`minimize_window_animation.rs:329-333`。修复同 A-1：`anim.velocity()` 取反传入；direction 翻转时进度镜像（morph = 1-progress）速度取负。

### A-5（中）SwipeTracker 速度系统性高估 + 空闲衰减不可靠

`src/input/swipe_tracker.rs:54-66`：`velocity() = Σ全部delta / (last.ts - first.ts)`——首事件 delta 计入分子但其时间不计入分母，事件稀疏时（快速轻甩 2-4 事件）高估 30-100%。且 gesture end 的空闲补偿 `push(0., clock.now_unadjusted())`（`monitor.rs:1983`、`scrolling.rs:3855`）用本轮事件循环开始的 lazy 时间，早于最后 libinput 事件戳时被 `push` 静默丢弃（swipe_tracker.rs:32-39），空闲衰减随机失效。表现：同样甩动投掷距离不稳定；停顿后松手偶带全速。
**方案**：velocity 排除首事件 delta 或改最小二乘斜率（GNOME Shell 做法）；end 处直取 `get_monotonic_time()`。风险：速度整体变小，需微调 deceleration/spring 手感做 A/B。

### A-6（中）interactive move 松手不携带指针速度

`layout/mod.rs:4584+`（`interactive_move_end` → `animate_move_from`），`move_grab.rs` 无速度跟踪。表现：快速拖窗松手瞬间静止再缓动，无惯性落位。
**方案**：`InteractiveMoveState::Moving` 挂 SwipeTracker（x/y），end 时经新增 `Tile::animate_move_from_with_velocity(from, v)` 传入（归一化 `v/from`，from≈0 跳过）。依赖 A-1 接口。

### A-7（低中）tile 交换清除目标 tile 动画

`scrolling.rs:2552-2560`（FIXME）：swap 时 `stop_move_animations()` 连带清掉目标 tile 合法动画，连续 swap 时上一次动画瞬移终点。
**方案**：`add_tile_to_column` 加 `suppress_move_anim` 参数抑制插入位移动画，保留既有动画。

### A-8（低）关闭动画受 transaction 阻塞最长 300ms

`closing_window.rs:90-112` + `transaction.rs:18`（TIME_LIMIT=300ms）：慢客户端时关窗快照静止悬挂至多 300ms 才起播。
**方案**：降到 ~150ms；或 Waiting 超 1 帧先 alpha-only 起播、几何等 blocker。纯调参低风险。

### A-9（低）overview 缩放坐标非物理像素对齐

`monitor.rs:1156`（代码自认 "doesn't round to output scale properly"）+ 1486-1490 补救性 post-round。fractional scale 下 overview 开合边缘亚像素闪烁。
**方案**：`workspaces_render_geo` 系列统一在最终 loc/size 做 `to_physical_precise_round`，与 hint 宽度（1142-1148）用同一 rounding 函数避免 1px 缝。

已核对无需修改：spring 求解器加固、`restarted` spring 初速语义、列内多窗 resize 的 Transaction 序列化（无首帧撕裂）、open 动画首帧。

---

## 第二部分：tahoe-shell + quickshell 动效质感（编号 S-*）

正面结论：P05 compositor morph 中断反转链路健壮（`mapped.rs:343-380` 从当前视觉位置续接携带速度）；弹层互斥切换无闪断；Dock 磁化波 SmoothedAnimation retarget 合规；令牌覆盖完整，无 restart 复播站点。

### S-H1（高）glass region 显式 commit 与内容 buffer 非原子——region 领先视觉一帧

`quickshell/src/wayland/tahoe_glass/qml.cpp:738-798`（尤其 796-798 `if (changed && !morphSent) commit()`）：polish 阶段重建 region 后立即显式 `wl_surface.commit`，携带旧 buffer + 新 region；帧 N 的 buffer 由 render 线程稍后另行 commit，compositor 在其间 latch 即"region 新、内容旧"一帧。morph 场景已跳过 early commit（注释承认此害），普通 region 更新仍走。**这正是 42039bb compositor 侧 clamp 兜底的上游根因**；另有 GUI/render 线程并发 commit 隐患。
**方案**（魔改 quickshell）：仅当窗口无待处理重绘时才显式 commit——用 `filteredWindowEvent` 的 `QEvent::UpdateRequest` 钩子置 dirty flag；有重绘排队时依赖 render 线程 buffer commit 原子携带 region（region 是 double-buffered pending state）。`sendTransform*` 三处立即 commit（qml.cpp:539-589，即 S-M6）并入同一框架。
**验证**：`WAYLAND_DEBUG=1` 抓 dock grow，每帧仅一次 commit 且 set_region 与 attach 同 commit；临时移除 42039bb clamp 验证 band 消失。**修好后可撤 42039bb 兜底。**

### S-H2（高）minimize genie 目标 = 点击瞬间被放大波扭曲、随后布局坍缩的按钮位置

`tahoe-shell/components/WindowButton.qml:112-121`（mapToItem 含 magnification/lift）+ `:175`；冻结机制 `niri/src/layout/lifecycle_controller.rs:176-211`（创建时一次性读 rect）+ `niri/src/handlers/mod.rs:652-780`（`set_rectangle` 从不 retarget 在飞动画）。开启最小化 shelf 时点击最小化：上报 target 是波峰（scale≈1.62+pushX）位置，minimize 后按钮移除、dock 宽度 Behavior 重排，thumbnail 实际在别处——genie 飞向旧位置，错位可达一个 slot + 波形偏移。
**方案**：①短期纯 QML：shelf 开启时上报预测的 shelf 新 slot rect（`minimizedSectionHost` 场景坐标 + 末尾追加 slot），并剥离 mag/pushX 用 rest 几何。②中期改 niri（无需新协议）：`set_rectangle` 对 active genie 新增 `retarget(rect)` 更新 `target_rect`（shader 每帧读 uniform，平滑可行；同步重算 genie_area）——同时根治"genie 动画期 target 永不更新"（`niri.rs:2246-2303` 单次采样）。

### S-M 中严重度（10 项）

- **S-M1** 岛退场淡出期间内容被改写为时钟/空值：`DynamicIslandOverlay.qml:62-70` + `DynamicIslandContent.qml:353-369` + `services/DynamicIsland.qml:508-526/827-846`。dismiss 通知 → 立即清字段 → 淡出中的卡片文字闪成时钟。媒体场景已有 latch 先例（`Content.qml:136-143`），通知/蓝牙/工作区漏了。方案：同款 latch 或延迟 `clearTransientFields` 到退场 hold 后。
- **S-M2** ControlCenter 模块 morph 时面板底边单帧跳变：`ControlCenter.qml:290-301` sibling `Layout.maximumHeight` 无 Behavior，展开首帧 sibling 直接归 0，玻璃面板底边跳 ~150-250px 再补回。方案：sibling 高度加与 morph 同参动画（仅 morph-in-flight 时 enabled）。
- **S-M3** shelf 缩略图缺场景偏移依赖：`DockMinimizedWindow.qml:187-192` 未监听 dockChrome.x/contentX 变化（pinned 侧 `Dock.qml:152-167` 已有 sceneOffset 正为此坑）；右键菜单/TaskSwitcher/IPC restore 不 force → genie 源矩形过期。方案：透传 `minimizedSectionSceneOffsetX/Y` 并触发重报。
- **S-M4** 波跨 pinned/window 分隔带扫动全塌再重建：`Dock.qml:649-663` 两段各 ±4px 容差、段间 ~17px 间隙返回空 section。方案：间隙归属最近一侧、允许 cursor 越界（cosine 自然衰减）。
- **S-M5** hover 退出/拖拽开始 `contentX = 0` 瞬跳：`Dock.qml:744-747`。拖拽 reorder 起手跳位。方案：去掉归零或动画回滚；拖拽路径绝不重置。
- **S-M6** `sendTransform*` 立即 commit：并入 S-H1 框架。
- **S-M7** 图标 rect 上报无帧同步：`quickshell/src/wayland/toplevel/wlr_toplevel.cpp:125-177` 收到即发；slot Behavior 途中采样；IPC 与 set_rectangle 跨 socket 无序。方案：上报挂 polish + Behavior 结束 force；根治并入 S-H2 retarget。
- **S-M8** restore force 上报夹带 add-transition/press 缩放：`DockMinimizedWindow.qml:123-128`（`lifecycleScale*pressScale`）——快速"最小化→立即恢复"genie 源矩形小 ~6-10%。方案：rest 几何化上报。
- **S-M9** Dock 两套悬停标签令牌不一致：`DockMinimizedWindow.qml:326-332` 用 `Motion.panelExit`(200ms) vs `Dock.qml:1874-1875` `fadeFast`(120ms)。改 fadeFast。
- **S-M10** 天气 BusyStripe 无限循环未接 reduced motion：`LeftSidebarWeather.qml:1407-1415` 硬编码，加 gating + 入令牌。

### S-L 低严重度（12 项摘要）

| # | 位置 | 问题 → 方案 |
|---|---|---|
| L1 | `niri/src/handlers/layer_shell.rs:386-434` + `quickshell/.../wlr_layershell/surface.cpp:180-186` | 直接 destroy 的 layer 无关闭快照瞬消；复用陈旧快照 → quickshell 关窗前先 null commit；niri map 成功清残留 snapshot |
| L2 | `quickshell/src/core/colorquantizer.cpp:265-273` | `cancelAsync` GUI 线程 `waitForDone()` 等全局线程池，壁纸切换全 shell 掉帧 → 改完成信号+弃结果标志 |
| L3 | `quickshell/src/bluetooth/agent.cpp:56,169` | GUI 线程同步 DBus，bluetoothd 无响应卡至 25s → QDBusPendingCallWatcher |
| L4 | `DynamicIslandOverlay.qml:395-399,298-301` | morph 队列失败路径 radius 直跳 + mask hold 提前武装失败时 560ms 吞点击 → 共读队列结果、hold 移到成功后 |
| L5 | `NotificationToast.qml:410,596-608` + kdl:765-787 | 首条 toast 双入场叠加（layer 28px + QML 60px）→ map 帧首卡跳过 QML enter |
| L6 | `shell.qml:795-823` + `PopupDismissLayer.qml:42-76` | 弹层 A→B 后 ~210ms 内点 A 残影误关 B → lastClosedRect 时间窗忽略 |
| L7 | `Spotlight.qml:58-61,462,477-482` | 关闭冻结高度收缩，300ms 内重开首帧偏高 → 打开分支 snap 到目标高度 |
| L8 | `DockMinimizedWindow.qml:357-359,192` | restore 后 bounce 被销毁截断、濒死 delegate 污染 reverse hint → restore 后抑制上报/不 bounce |
| L9 | `Dock.qml:469-482` | 波端部独立 clamp 可致相邻中心重叠 → clamp 后单调性 pass |
| L10 | `Dock.qml:287-311,951-968` | autohide compositor 滑动期间 mask/波按终态瞬时生效 → QML 抑制窗口近似；根治需 tahoe_glass 新 `transform_done` event（唯一需要新协议事件的项） |
| L11 | `Launchpad.qml:834-838` 等 3 处 | 硬编码 120/500ms 不随 profile → 入令牌 |
| L12 | `Motion.js:97-99` vs `DynamicIslandMotion.js:20-22,50-57` | swipe 阈值双源、`v2GeometrySpring` 注释错误、epsilon 未令牌化 → 单源化 |

观察项（不计缺陷）：岛通知连发无文本 crossfade；compositor morph 下 `mediaExpandProgress` 整面仿射（P05 既定代价）；legacy useSpring 路径 retarget 丢速度（仅无 v4 时可达）；遮挡时 dock 若仍跑 QML 动画应主动暂停；minimize 引发 dock 宽度 Behavior 的逐帧 region 提交是 P08 潜在提交风暴源。

---

## 第三部分：渲染性能（编号 R-*，按预期收益排序）

### R-1 queue_redraw_all 收敛（多屏收益最高）

定向基础设施已在（`queue_redraw(output)` niri.rs:3995、`RedrawAttribution` niri.rs:4004、R17 归因测试）。剩余扇出：input/mod.rs 128 处、niri.rs 24、handlers/mod.rs 8 等。成本：queued output 每帧付全部 `update_render_elements` + 元素收集 + `render_frame` 成本后才在 backend/tty.rs:2015 得 NoDamage。

分类改法：
- do_action ~90 处（上游 FIXME granular）→ 新增 `Layout::take_dirty_outputs()`，mutation 按受影响 Monitor 打脏，do_action 尾统一 attribution（避免逐点改 90 处）。
- 指针隐藏/显示（input/mod.rs:641 等）→ `output_under(pointer_pos)` 定向（旧+新）。
- 光标/DnD icon commit（handlers/compositor.rs:449,473，每帧级高频）→ 定向。
- move_grab/touch_overview_grab 每 motion → 被拖 window bbox overlap outputs（move_grab.rs:251 已示范）。
- 真全局（config reload/输出增删/锁屏/screen transition）保留 all，走 `RedrawAttribution::All{reason}` 可审计。

验证：frame telemetry 统计 per-output NoDamage 帧占比前后对比；R17 测试扩展。

### R-2 NoDamage 前固定 CPU 削减

`update_xray_render_elements`（niri.rs:4509）无条件 clear+重建 workspaces、逐 buffer 刷新——无 xray 可见时也全跑。方案：入口加消费者短路（fill_xray_elements niri.rs:4856 知道集合）+ Vec 复用脏标记。估 <0.2ms/帧但 144Hz 动画期纯净利。

### R-3 glass capture 命中率：band 量化 + 快速运动降级（动画期 GPU 高收益）

现状：capture key 含 rounded physical band（resolved_effect_plan.rs:53-73），band 变 1px 即重跑 blit+全金字塔（framebuffer_effect.rs:178）；弹簧动画期≈每帧重捕获×每 region。61138be 教训：rest-anchored 采样因"采样矩形≠捕获矩形"时序失血被回退。
方案（绕开 61138be）：
a) **band 量化 tier**：`geometry_animating` 时 capture_geometry 向外取整到 8px 网格再进 key——capture 仍严格超集覆盖真实 band（无失血），draw 端继续精确映射。重捕获估降 4-8×。改动集中 resolved_effect_plan.rs:215-231 + blit dst 量化。
b) **快速运动 tier2**：band 单帧位移 >24px 时临时 `downsample_shift=2`（MAX=4 有余量，blur.rs:46），走既有 capture-key 失效契约（P06 文档化，安全）。
c) 静止 band 的 damage 短路已正确（P03），不做"band 移动时复用旧纹理"——那就是 61138be。
验证：`note_fb_effect_capture` 计数（lifecycle_diag 已埋）每秒 capture 次数 A/B；同款 env 开关；量化后 blur 边缘走查（超集捕获理论无差异）。

### R-4 glass shader 法线场烘焙（大面积 glass GPU 中-高收益）

postprocess.frag `glass_normal`（:102）每片元 3 次 `glass_height`（各含 rim+detail+2 次 value_noise×4 hash+pow），加 pow(...,42) 高光（:135）——每片元 ~12+ 次 noise。height/normal 场只依赖 coords_geo 与 region size → 预烘焙 128×128 LUT 纹理（法线+rim 打包 RGBA），resize 才重生成；片元变 1 次采样+高光，ALU 估降 5-10×。noise 颗粒保留实时。验证：tracy GPU span（Cargo.toml:142 已启用）+ 像素 diff。

### R-5 Wallpaper.qml 同步 /proc 轮询（零风险）

`Wallpaper.qml:1284`（5s timer）→ `:589,598-599` `reload()+waitForJob()`，`:650,657-658` 再叠一次——UI 线程周期性同步等 IO job。方案：异步状态机（timer 只 reload，解析移 `onLoaded`）；`stopPrestartedWallpaper`（:617）改"先读后杀"回调链。S3 的两次连续 miss 保护（:1297-1300）不受破坏。

### R-6 quickshell glass polish 全量重建

`TahoeGlass::onWindowPolished`（qml.cpp:738）每次 polish 对全部 region 重建 logical+surface 双套（每 region 8 次 mapToScene），单 region 变化也全量。方案：per-region 脏标记 + 未脏复用缓存 state。Ancestor tracking 每层 11 连接（qml.cpp:324-374）→ 7 个几何信号换单个 Geometry change listener，降到 ~5。

### R-7 同步 Loader

`DynamicIslandContent.qml:358,528` `asynchronous: false` 撞展开首帧。安全做法：`active` 预热而非翻 async（morph 编排常立刻解引用 item）。LockScreen 两处非热点可保留。

### R-8 Dock 指针波（观察，暂不改）

`dockMouseX` 每 move 强制逐 icon 重估（Dock.qml:502-571 `_dep` 模式）。若 profiling 证实热，FrameAnimation 节流到每帧一次。

### Profiling 计划（先测后改）

- niri：`--features profile-with-tracy`（GPU+allocations，Cargo.toml:142-146）。场景：A 静置双屏+光标画圈；B Dock 波动 10s；C Island 展开×10；D overview 进出。指标：per-output NoDamage 帧率（frame telemetry）、每秒 fb capture（note_fb_effect_capture）、queue_redraw_all vs 定向计数（已埋）、GPU span（金字塔 vs glass draw 占比）。A/B 沿用 `NIRI_DISABLE_ANIM_BLUR_DOWNSAMPLE` 惯例新增开关。功耗：turbostat PkgWatt / intel_gpu_top，60s×3 取中位。
- QML：qmlprofiler 抓 B/C（binding/JS/create 分布，核 Wallpaper 5s 尖峰、Island create）；`QSG_RENDER_TIMER=1` 验 polish 时长（R-6）；C++ region rebuild 计数。
- 门槛：单项 ≥0.3ms/帧（60Hz）或 ≥3% GPU 帧时间才进实现队列；R-1 与 R-5 因结构正确性可直接做。

---

## 第四部分：架构与维护（编号 M-*）

### M-A（高）niri fork 分叉面大且与 upstream 纠缠

- niri fork 领先本地 main 74 提交，merge-base `948a776e`（2026-06-21，基线冻结 ~5 周）；分叉 85 文件 +23,395/−2,053，其中 62 个是修改 upstream 既有文件（+14k），热点恰是 upstream 演进最快的 layout/render/主循环（mapped.rs 1479 行、animations.rs 1050、scrolling.rs 897、niri.rs 709…）。
- quickshell fork 干净得多：30 提交，+4,528，主体是新增 `src/wayland/tahoe_glass/` 目录。
- **两个 fork 均未配置 upstream remote**——落后量不可见，安全修复无法及时吸收；dependabot 分支堆积。

方案：①立即加 upstream remote + 周报（rev-list count + merge-base 日期）。②分类收敛：(a) 23 个纯新增文件移入 `src/tahoe/`（冲突面归零）；(b) 挂钩点压缩为最小 diff + `// TAHOE:` 标记；(c) 对 upstream 逻辑的行为修改无法 patch 化，建 `FORK.md` 逐条记录意图，rebase 时按意图重实现。全量 feature flag 不现实。③季度 rebase 节奏（quickshell 先演练）；依赖 fork 内 ~5,000 行测试作回归网。

### M-B（高）协议单一事实来源缺失

`tahoe-glass-v1.xml`（v4，版本化设计本身健康）存在两份逐字节拷贝（niri/resources/ 与 quickshell/src/wayland/tahoe_glass/），主仓库无权威副本，`check-submodules.sh` 不校验同步。genie/dock 契约实际分裂三通道：tahoe_glass 协议、`niri msg --json event-stream`（Windows.qml:963）、一次性 `niri msg action`（CommandRunner.qml:711）——无契约文档。
方案：主仓库建 `protocols/tahoe-glass-v1.xml` 权威副本 + sha256 校验进 check-submodules.sh；写 `protocols/CONTRACT.md` 列三通道与字段依赖。

### M-C（中高）QML 巨石与 Motion↔KDL 双源

>1500 行文件 4 个：`services/DynamicIsland.qml` 2487（102 property）、`services/Controls.qml` 2121、`components/Dock.qml` 1963、`ControlCenter.qml` 1694。Reducer 抽取模式已被证明可行（DynamicIslandReducer.js/WindowModel.js/SettingsModel.js 均可 node 单测）但只用了一次。Motion.js（413 行、831 引用）与 `config/niri/tahoe-phase0.kdl` 参数仅靠注释人工同步。
方案：Controls/ControlCenter/Dock 逐个 reducer 化；`motion-tokens.json` 单源生成 Motion.js + KDL 期望值，`test_motion_token_convergence.py` 改全量比对。

### M-D（中）部署无回滚 + 测试合同化

`scripts/arch-update.sh` ~千行单体，就地覆盖 `~/.local/bin`，无版本化/回滚（config 有 backup，二进制没有）——"一行 cp"手工流程的根源。测试 131 文件/~915 test：45 个经 node vm 真执行 reducer（行为测试），94 个是读源码文本的合同检查；QML 绑定层无 qmltestrunner 基建，行为回归只能人工走查。
方案：安装到 `~/.local/lib/tahoe/<sha>/` + symlink 原子切换；脚本拆 build/install/verify 三相；Dock/DynamicIsland 引入 qmltestrunner 冒烟层。

### M-E（中低）依赖健康

smithay pin 在 git rev `ff5fa7df`（6 月，无 crates.io 版本）；`patches/xwayland-satellite-minimize.patch` 是第三条打补丁依赖线（有 compat 检查脚本守护）。双日志框架传闻不成立（shell console.* 仅 7 处），从关注清单移除。smithay 升级绑进季度 rebase。

---

## 总优先级（跨四路合并）

**第一梯队（直接决定日常观感/根治既有兜底）**
1. S-H1 + S-M6：quickshell "有重绘排队则不显式 commit" 框架 → 根治 region/transform 领先一帧，撤 42039bb clamp 兜底。
2. A-1 `Animation::velocity()` 基础设施 → 连锁修复 A-2/A-4(F-05)/A-6，是 compositor 手感的最大单项。
3. S-H2 + S-M7/M8：genie 目标 rest 化 + niri `set_rectangle` retarget（无需新协议事件）。

**第二梯队（小改动高收益的质感项）**
4. S-M1（岛字段 latch）、S-M2（CC sibling 动画）、S-M3（shelf scene offset）——均纯 QML。
5. A-3（resize 目标追踪）、A-5（SwipeTracker，需手感 A/B）。
6. R-5（Wallpaper 异步化，零风险）+ R-1（redraw 收敛，结构正确性直接做）。

**第三梯队（先 profiling 后做）**
7. R-3（band 量化）、R-4（shader LUT）、R-2/R-6/R-7——按 profiling 门槛（≥0.3ms/帧或 ≥3% GPU）准入。

**长期（维护面）**
8. M-A（upstream remote 立即做；分类收敛/季度 rebase 排期）、M-B（权威协议副本 + CONTRACT.md）、M-C/M-D 渐进。

唯一需要新协议事件的项：S-L10 根治（`transform_done`）；其余全部可在现有协议内完成。
