# Niri + Quickshell Tahoe 性能、动画、用户体验与可维护性研究报告及修复路线图

| 字段 | 值 |
|---|---|
| 状态 | 审计基线与执行规范 |
| 版本 | 1.0 |
| 日期 | 2026-07-16 |
| 适用仓库 | /home/wwt/niri |
| 目标分支 | main |

## 0. 文档定位

本文件是本轮性能、GPU、动画、用户体验、架构和可维护性治理的唯一执行基线。

它同时承担以下职责：

1. 记录已经由源码或现场运行证据确认的问题。
2. 记录高置信但仍需度量验证的设计风险。
3. 定义修复顺序、任务边界、验收指标和回滚条件。
4. 定义反腐化约束，禁止为修复问题创造第二套接口、协议、provider、配置写入器或动画控制链。
5. 定义严格串行的审查、提交和推送流程。

本文件不是实现本身。任何任务只有在实现、验证、审查、commit、push 全部完成后，才允许开始下一任务。

仓库根目录中既有的 niri-quickshell-tahoe-research.md、niri-quickshell-tahoe-roadmap.md 和 handoff 文件视为历史材料，不作为本治理计划的并行状态表，也不得在后续任务中同时维护。当前计划的状态、门禁和任务顺序只在本文件中维护。

## 1. 强制执行原则

以下规则使用“必须”表述时，不得在实现中绕过。

### 1.1 严格串行

1. 同一时间只能有一个路线图任务处于进行中。
2. 当前任务未完成验证和审查时，不得开始下一任务。
3. 当前任务未 commit 和 push 成功时，不得开始下一任务。
4. 不允许为了等待当前任务而顺手实现其它问题。
5. 发现新问题时只记录，不在当前任务范围外顺带修改。

### 1.2 反腐化

1. 必须扩展或修正当前权威实现，不得创建同功能的 V2、New、Legacy2、FastPath2 等平行实现。
2. 不得为了降低迁移风险而长期保留新旧两条生产路径。
3. 如果修改协议或数据结构，必须在同一任务中更新所有生产调用者并删除旧语义。
4. 临时诊断接口只能用于观测，不能成为第二套业务接口；诊断完成后应保留为低成本可观测能力或在同一任务中移除。
5. 不得新建第二个缩略图 provider、第二个配置写入器、第二个亮度服务、第二套玻璃协议或第二套 layer 动画开关。
6. 不得复制材质和动画 token 到新文件。需要新增字段时，应扩展现有权威 token 来源。
7. 不得用 Shell 侧补丁掩盖 compositor 状态错误，也不得用 compositor 特例掩盖 QML 生命周期错误。
8. 每个状态必须有唯一 owner；其它层只能读取或发送明确命令。
9. 修复必须删除导致问题的旧路径，而不是在其前后再增加补偿逻辑。
10. 不得用更高轮询频率掩盖事件缺失。

### 1.3 唯一所有者

| 领域 | 当前应保留的权威所有者 | 禁止出现的平行路径 |
|---|---|---|
| 输出帧调度、VRR、vblank | niri frame clock 和 backend | QML 自建全局帧调度 |
| 窗口与 layer 外层动画 | niri animation/layout/layer | 同一 surface 同时由 QML 再做一套外层进出场 |
| 组件内部微动画 | QML 组件 | compositor 为按钮、列表行等内部元素增加特例 |
| Tahoe 玻璃协议 | 现有 TahoeGlass 协议与 renderer | 第二套 blur/glass Wayland 协议 |
| Shell 缩略图入口 | Tahoe ThumbnailProvider | 各组件独立调用 niri、screencopy 或新 daemon |
| niri 配置写入 | NiriSettings + niri_settings_tool.py | 新 JSON 配置、第二个 KDL writer |
| 亮度和蓝牙状态 | Controls | BrightnessServiceV2、BluetoothControllerV2 |
| Desktop 设置 | DesktopSettings | 每个页面维护独立设置文件 |
| 通知生命周期 | Notifications | Toast 和 NotificationCenter 各自维护另一套过期状态 |
| 动画与材质 token | 现有 Motion、IslandMotion、KDL/Rust 配置结构 | 局部硬编码复制 |

## 2. 审计范围与方法

### 2.1 范围

本轮扫描约 630 个 Rust、QML、JS、C++ 和头文件，约 21 万行源码。重点覆盖：

- niri 主事件循环、TTY backend、frame clock、damage、render helpers。
- blur、framebuffer effect、Tahoe glass、shader。
- window、layer、close、minimize、spring 和 gesture 动画。
- Quickshell TahoeGlass C++ 接入和 window mask。
- Tahoe Shell 的 TopBar、Dock、Dynamic Island、Overview、通知、设置、搜索、锁屏和系统服务。
- 配置生成、运行脚本、外部 Process 和 Timer。

未使用旧研究文档作为问题依据。结论来自源码、运行状态、运行日志和测试结果。

### 2.2 证据等级

| 等级 | 含义 |
|---|---|
| 现场确认 | 已在当前桌面会话测得或日志中复现 |
| 源码确定 | 控制流和状态关系可直接证明 |
| 高置信风险 | 设计上很可能导致问题，但修复前仍应增加度量 |

### 2.3 限制

1. 当前未重启桌面会话。
2. 当前未部署带 redraw-source 标识的 niri 构建。
3. 因此能够确认存在 240Hz 持续重绘，但尚不能唯一确认是哪一个 unfinished animation 来源长期为真。
4. Quickshell 的高 rchar 已确认，但现有环境没有 strace/perf/bpftrace，尚不能把全部读取量精确归因到单一 fd。

## 3. 执行摘要

去重后共记录 38 个独立问题：

- P0：10 个，直接影响 GPU、帧时间或动画可靠性。
- P1：19 个，影响动画衔接、手感、功能一致性和交互延迟。
- P2：9 个，影响架构、资源治理、测试和维护成本。

GPU 高占用的主因不是单个进程，而是以下链路叠加：

    239.998Hz 固定刷新且 VRR 关闭
        -> 任一未结束动画使 niri 每个 vblank 继续排队
        -> 常驻 TopBar、Dock、动态岛阻止直接扫描输出
        -> Tahoe 材质普遍使用非 xray 真实 framebuffer 采样
        -> 每个区域执行 framebuffer blit、4 pass blur 和复杂 shader
        -> 动态岛几何与 mask 动画扩大 damage 和 Wayland commit
        -> 壁纸和部分 QML Canvas/MultiEffect 继续提供背景更新

## 4. 现场基线

### 4.1 显示与 GPU

| 指标 | 当前值 |
|---|---|
| 输出 | eDP-2 |
| 模式 | 2560×1600@239.998Hz |
| scale | 1.25 |
| VRR 支持 | 是 |
| VRR 启用 | 否 |
| GPU | RTX 4070 Laptop |
| GPU 总占用 | 约 30% 至 40% |
| niri GPU | 常见 28% 至 32% SM |
| niri 显存 | 约 206 至 295 MiB |
| linux-wallpaperengine 显存 | 约 1011 MiB |
| Quickshell 显存 | 约 105 MiB |

### 4.2 CPU、内存和 IO

| 指标 | 当前值 |
|---|---|
| Quickshell RSS | 约 537 MiB |
| Quickshell CPU | 常见约 9% |
| Quickshell rchar | 约 0.6 至 5 MB/s 周期性波动，个别窗口更高 |
| niri CPU | 常见约 8% |
| wallpaper engine CPU | 常见约 10% 至 15% |
| niri voluntary context switches | 约 266 至 314 次/秒 |

niri 上下文切换频率与 240Hz 持续 frame loop 高度吻合。

### 4.3 运行时错误

当前 Quickshell 日志确认：

1. shell.qml:472 向 Qt.application.font 只读属性赋值。
2. LockScreen.qml:16 报 lockClock is not defined。
3. StartupPage.qml:358 重复报 addCandidateRow is not defined。
4. WindowOverview 曾解码到未完成或损坏的 PNG，报 Unsupported image format。

### 4.4 测试基线

| 测试 | 结果 |
|---|---|
| Shell 测试 | 708 passed，185 subtests passed |
| niri-config | 35 passed |
| niri-ipc | 3 passed |
| niri 单线程 | 289/289 passed |
| niri 默认并行，连续 5 次 | 每次 4 至 5 个 layer-close 测试失败 |
| Quickshell Tahoe CTest | 12/12 passed |
| cargo fmt --check | 失败 |
| Clippy | 未安装 |
| qmllint | 148 个运行时 QML/JS 中 126 个无法形成可靠检查 |

## 5. P0 问题

### P0-01：240Hz 持续重绘与 VRR 关闭

证据：

- config/niri/tahoe-phase0.kdl:21-27 固定 239.998Hz，variable-refresh-rate 被注释。
- niri/src/niri.rs:4851-4875 汇总 unfinished_animations_remain。
- niri/src/backend/tty.rs:1789 附近在 redraw_needed 或 unfinished animation 为真时再次 queue_redraw。

影响：

- 静止桌面也可能按 240Hz 运行完整 compositor loop。
- 所有玻璃、shadow、damage 和覆盖层成本被放大。
- 增加功耗、风扇噪声和输入抖动。

修复方向：

1. 先增加每个 unfinished animation 来源的命名计数。
2. 明确空闲时是否仍持续 queue_redraw。
3. 启用 on-demand VRR 或适合当前显示器的 VRR 策略。
4. 不允许仅通过降低刷新率掩盖永久动画状态。

### P0-02：真实 framebuffer 采样成本必须在不破坏视觉语义下治理

证据：

- config/niri/tahoe-phase0.kdl:98-192 的 Tahoe material 均使用 xray false。
- config/niri/tahoe-phase0.kdl:322-331 的普通窗口 background-effect 也使用 xray false。
- niri/src/render_helpers/background_effect.rs:263-285 明确选择 xray 或 nonxray framebuffer path。
- 2026-07-16 的 R04 回归复核确认：xray buffer 只包含 workspace backdrop 和 background layer；将 panel/dock/backdrop 改为 xray true 会跳过普通窗口，使白色窗口上方的玻璃仍显示壁纸颜色。

影响：

- 每个玻璃区域需要抓取真实 framebuffer。
- 窗口移动、动态岛变形和背景更新都会重新采样。
- 直接改用 xray backdrop 虽然降低成本，但会把液态玻璃变成只看壁纸的不同视觉语义。

修复方向：

1. 所有 Tahoe 液态玻璃 material 保持 xray false，实时采样后方已经合成的窗口内容。
2. 在现有 nonxray 路径内复用 FBO、跳过关闭的 shader feature，并收紧 damage/commit。
3. 如果未来共享 composed framebuffer，结果必须包含普通窗口并随其 damage 正确失效；不得用 wallpaper-only xray buffer 冒充实时玻璃。
4. 不新增第二套玻璃组件、第二个 blur API 或第二套采样协议。

### P0-03：Framebuffer 与 blur FBO 高频创建删除

证据：

- niri/src/render_helpers/framebuffer_effect.rs:279-308 每次 blit 创建并删除 FBO。
- niri/src/render_helpers/blur.rs:202 附近每次 blur render 创建两个 FBO。
- config/niri/tahoe-phase0.kdl:62-68 使用 4 passes。

影响：

- 240Hz 下产生大量 OpenGL driver 调用。
- 增加 GPU 状态切换和 CPU driver overhead。
- 多个 glass region 会重复支付同类成本。

修复方向：

1. 在现有 FramebufferEffect 和 Blur 对象中缓存 FBO。
2. 在 size、format 或 renderer context 变化时失效。
3. 不建立 ParallelBlur 或 BlurV2。

### P0-04：玻璃 shader 存在无条件昂贵计算

证据：

- niri/src/render_helpers/shaders/postprocess.frag:85 起包含 SDF、normal、value noise、pow、refraction 和 caustic。
- postprocess.frag:234 和 240 在乘以 edge_highlight 或 inner_shadow 前已经执行昂贵函数。

影响：

- 即使某项材质参数为零，像素仍支付大部分成本。
- 大区域玻璃和 240Hz 会显著放大 shader ALU 压力。

修复方向：

1. 对零值或近零值 uniform 先分支。
2. 在现有 shader 构建链中提供有限的材质 feature mask。
3. feature mask 必须由现有 BackgroundEffect/Tahoe material 驱动，不新增第二套 shader 接口。

### P0-05：TahoeGlass 更新扩大 damage

证据：

- niri/src/render_helpers/tahoe_glass.rs:59-68 的 damage 会 damage_all 并更新所有 region effect/shadow。
- niri/src/protocols/tahoe_glass.rs:231 附近 region commit 后再次 damage surface。
- tahoe-shell/components/DynamicIslandOverlay.qml:477-540 同时动画 mask、x、y、width、height、radius。
- quickshell/src/wayland/tahoe_glass/qml.cpp:623-650 每次 region 变化 schedulePolish 并提交。
- quickshell/src/window/proxywindow.cpp:655-665 重建 QRegion 和 window mask。

影响：

- 动态岛的小变形可能扩大为整个 surface 的 damage。
- 同一帧产生 QML polish、Wayland commit、glass commit 和 mask commit。
- 视觉上可能出现节奏不稳、边缘抖动或偶发掉帧。

修复方向：

1. 区分视觉几何、采样几何和输入几何。
2. 动画期间尽量保持 input mask 稳定。
3. region damage 精确覆盖 old/new union，不 damage 全部无关 region。
4. 修改现有 TahoeGlass region 提交语义，不新增第二协议。

### P0-06：窗口缩略图同步阻塞 compositor 主循环

证据：

- niri/src/ipc/server.rs:473 附近将请求插入 niri event loop。
- niri/src/render_helpers/mod.rs:255-270 同步 render、map texture 和 CPU copy。
- niri/src/niri.rs:5961-5970 随后同步保存 PNG。
- tahoe-shell/components/WindowOverview.qml:54-68 打开 Overview 时请求缩略图并启动进入动画。

影响：

- GPU readback、CPU copy、PNG 编码和文件 IO 与动画共用主线程时段。
- 多窗口 Overview 会形成突发任务。
- 输入和呈现延迟可能在打开 Overview 时明显上升。

修复方向：

1. 保留现有 window-thumbnail IPC 作为唯一入口。
2. compositor 只负责产生像素或可异步处理的结果。
3. PNG 编码和磁盘写入移出关键事件循环。
4. ThumbnailProvider 继续作为 Shell 唯一队列，不允许组件自行抓图。

### P0-07：缩略图文件不是原子发布

证据：

- niri/src/niri.rs:6009 使用 File::create 直接截断目标文件。
- 现场 WindowOverview 日志出现 Unsupported image format。

影响：

- QML Image 可能读取到半写入 PNG。
- cache:false 和 revision 更新会增加并发读取概率。

修复方向：

1. 同目录临时文件写入。
2. flush、必要时 fsync。
3. atomic rename。
4. rename 成功后才更新 generation/revision。

### P0-08：Layer close 动画在 snapshot 完成前开始计时

证据：

- niri/src/layer/mapped.rs:317 在 snapshot 渲染前记录 close_start。
- niri/src/layer/closing_layer.rs:112-143 可能同步渲染多份纹理。
- niri/src/handlers/layer_shell.rs:328-344 之后才创建动画并加入 closing list。
- 并行测试连续出现 layer-close 失败。

影响：

- 负载高时短动画可能尚未可见就已经过期。
- 表现为偶尔没有关闭动画、突然跳过或不一致。

修复方向：

1. snapshot 和纹理准备完成后再建立动画起点。
2. 保留必要的视觉起始状态，但不要把 GPU 准备时间计入动画。
3. 增加确定性测试，不依赖墙钟和并行调度偶然性。

### P0-09：常驻 shell surface 破坏直接扫描输出机会

证据：

- tahoe-shell/components/TopBar.qml:144 常驻 visible。
- tahoe-shell/components/Dock.qml:133 常驻 visible。
- niri/src/backend/tty.rs:1904-1918 默认关闭 overlay planes。

影响：

- 全屏应用仍需要 compositor 合成 Top layer。
- 视频、游戏和全屏应用无法稳定获得 direct scanout。

修复方向：

1. 全屏时真正 unmap 或提交空 surface，而不是只把视觉内容透明化。
2. 评估 overlay plane 的设备兼容策略。
3. 不能通过新建另一个 fullscreen shell 实现绕过当前 TopBar/Dock。

### P0-10：设置滑杆会触发逐 sample 配置验证和 reload

证据：

- tahoe-shell/components/settings/controls/TahoeSlider.qml:160-166 每个 pointer sample 发出 userSet。
- tahoe-shell/services/NiriSettings.qml:361-400 每字段启动 Python writer。
- NiriSettings.qml:546-560 写入后调用 niri load-config-file。
- tahoe-shell/services/niri_settings_tool.py:1581-1597 每次 fsync、niri validate、atomic replace。
- niri_settings_tool.py:1621-1637 再全量解析并返回所有配置块。

影响：

- 拖动 blur、动画、scale 等设置会形成进程、磁盘、验证和 compositor reload 风暴。
- 交互期间最需要稳定帧时间，却同时触发最重配置路径。

修复方向：

1. TahoeSlider 增加预览值与提交值语义。
2. 拖动时只更新 UI；松手或短 debounce 后提交最终值。
3. 继续使用现有 NiriSettings writer，不得创建快速 writer 或第二个配置文件。

## 6. P1 问题

### P1-01：动画光标未按帧 delay 调度

cursor.rs 能计算每帧 delay，但 is_current_cursor_animated 只返回布尔值。niri 因此可能每个 vblank 重绘，而不是在下一 cursor frame 到期时重绘。

修复应扩展当前 CursorManager，返回下一帧 deadline，不得创建独立 cursor animation timer 服务。

### P1-02：baba_is_float 永久报告动画进行中

niri/src/layer/mapped.rs:190 和 niri/src/layout/tile.rs:486 把 baba_is_float 直接视为 ongoing animation。

该功能一旦启用会永久维持 redraw，应改成明确的周期 deadline 或独立低频 animation source。

### P1-03：Spring 重启和求解失败会破坏速度连续性

- niri/src/animation/mod.rs:111 的 restarted spring 分支没有正确使用调用者传入的 initial_velocity。
- niri/src/animation/spring.rs:84-88 超过迭代上限返回 Duration::ZERO。

影响是快速反向、手势中断和极端参数可能瞬移。修复必须保持当前 Animation API，不创建另一套 spring engine。

### P1-04：Compositor 与 QML 动画所有权不一致

DesktopSettings 的 compositorLayerAnimations 只写 Shell 设置，不会同步修改 KDL layer rules。LeftSidebar、Spotlight、Toast 等可能同时存在 compositor 外层动画和 QML fallback。

应确定唯一外层动画 owner，并在同一任务中删除另一条外层路径。

### P1-05：NotificationToast 具有多段退出链

NotificationToast 同时有 material fade、card spring、Behavior on x、延迟 dismiss 和 niri layer-close。退出可能先 QML 移动/淡出，再 unmap 触发 compositor close，形成拖尾或两段式手感。

### P1-06：TopBar 和动态岛 sibling stacking 影响手势

TopBar.qml:938 起的 input proxy 只能补偿点击和 hover，不能完整转发 overlay 的 swipe、wheel 和复杂 pointer 生命周期。Wayland sibling Top layer 不保证顺序。

应让一个 surface 成为动态岛交互唯一 owner，不能再增加第三个代理层。

### P1-07：夜览色温逐 sample 启动外部进程

DisplaysPage.qml:96-108 每次滑动调用 setColorTemperature；Appearance.qml:43-50 写 JSON，83-104 启动 shell、gammastep -x 和 gammastep -O。

应在现有 Appearance 中合并写入并只应用最终值。

### P1-08：亮度逐 sample 启动 brightnessctl

ControlCenter.qml:1427-1449 把每个 pointer sample 传给 Controls.setBrightness。Controls 虽然有单进程串行合并，但没有 16/33ms 节流，也没有明确的 release final commit。

### P1-09：MenuRow 固定增加约 280ms 动作延迟

MenuRow.qml:93-130 使用 70ms 间隔和四个 half-cycle，完成后才 activated。关机、菜单、托盘等动作因此感觉迟钝。

建议动作立即执行或在 80ms 内执行，视觉 flash 与动作并行。

### P1-10：通知过期和 DND 与用户交互不一致

- 通知 deadline 不感知 hover、按压、阅读和 action 操作。
- 开启 DND 只抑制新通知，不隐藏已经显示的 toast。
- 文案却声明横幅已静音。

通知生命周期必须继续由 Notifications 统一管理，Toast 只能上报 interaction state。

### P1-11：NotificationCenter 隐藏时保留全部 delegate

NotificationCenter 使用 Repeater 构造分组和行。关闭 surface 只改变 visible，没有卸载最多 60 条历史内容和 Image。

应使用 Loader、可回收模型或在关闭时卸载内容，但不能创建第二份通知历史模型。

### P1-12：LockScreen 输入框状态与认证状态分离

LockScreen 清 root.password，但 TextInput.text 是独立状态。认证失败、解锁后再次锁定时可能保留旧圆点，并可能丢失焦点。

应以 TextInput 或单一受控属性作为唯一密码状态，并在 lock、unlock、completed、error 四条路径统一清理。

### P1-13：启动时存在确定的 QML 错误

1. shell.qml:472 修改只读 font。
2. LockScreen.qml:16 在可见绑定中引用尚未解析的 lockClock。
3. StartupPage.qml:358 引用另一个 delegate id。

这些错误应作为独立正确性任务修复，并加入启动日志零错误验收。

### P1-14：Spotlight 慢 provider 无法取消旧查询

Search.qml 仅 90ms debounce；TaskIndexProvider 会解析 recent、运行 tracker3 并扫描用户目录。新 query 到来时旧进程继续运行，最新查询只能等待旧任务结束。

应在现有单 Process/provider 中实现 generation 和 terminate，不新增第二 provider。

### P1-15：Bluetooth discovery 关闭面板后继续

ControlCenter 打开 Bluetooth 模块时自动 start discovery，但 closeModule 和 onOpenChanged 不 stop。Controls 中也没有自动超时。

### P1-16：AppsSettings 常驻并周期性执行重探测

shell.qml 常驻实例化 AppsSettings。CommandRunner 每 30 秒刷新 dependencies，revisionChanged 又触发 refreshDefaults。默认应用 probe 会递归扫描 desktop entries，并对多类 MIME 执行 xdg-mime。

应对输入 fingerprint 做缓存，并只在依赖或 desktop entry 真正变化时刷新。

### P1-17：应用权限 probe 最坏串行等待很长

apps_settings_probe.py 为 8 类权限逐个 busctl Lookup，每个 timeout 可达 2 秒；存储统计每个候选目录可遍历 2 万文件。选择新 app 时旧 probe 不立即取消。

### P1-18：Dock 缩略图依赖全局 revision

DockMinimizedWindow.qml:21-29 绑定 ThumbnailProvider 全局 revision，Image 又使用 cache:false。任意窗口缩略图状态变化可能让全部 minimized delegate 重新检查 source。

应扩展现有 per-window state 的细粒度通知，不创建 Dock 专用 provider。

### P1-19：额外背景视觉持续占用资源

1. linux-wallpaperengine 当前约占 1011 MiB 显存并持续运行。
2. WeatherBackground 使用 FrameAnimation、Canvas 2D 和 MultiEffect。
3. 启动脚本接电时默认倾向 performance profile。

这些功能应服从统一的 active、idle、fullscreen、battery budget，而不是各自维护资源策略。

## 7. P2 问题

### P2-01：Timer 和 Process 分散

Tahoe Shell 中约有 73 个 Timer、44 个 Process、24 个 PanelWindow 和 22 处 TahoeGlass 注册。多个常驻轮询分别管理亮度、输入法、网络、声音、电源、风扇和依赖检测。

### P2-02：Quickshell 内存和读取量缺少预算

现场 RSS 约 537 MiB，rchar 周期性处于 MB/s 级。当前没有服务级 IO 计数、对象数量或长期稳定性测试。

### P2-03：核心文件过大

- niri/src/niri.rs：6906 行。
- niri/src/layout/scrolling.rs：6063 行。
- niri/src/layout/mod.rs：5648 行。
- niri/src/input/mod.rs：5580 行。
- tahoe-shell/services/DynamicIsland.qml：2442 行。
- tahoe-shell/services/Controls.qml：1673 行。
- tahoe-shell/components/Dock.qml：1650 行。

拆分必须沿现有职责边界移动代码，不能留下 facade 和新旧实现同时存在。

### P2-04：动画和材质 token 没有单一来源

KDL、Rust、QML、JS 和 Python 都存在默认值、限制或映射。修改一个视觉参数可能遗漏其它层。

### P2-05：QML lint gate 不可靠

当前 qmllint 对大部分运行时 QML/JS 无法形成有效检查，启动时的明显 ReferenceError 因此进入生产会话。

### P2-06：Rust 静态质量门禁不完整

cargo fmt --check 失败，Clippy 未安装。定制代码缺少统一格式和 lint 基线。

### P2-07：并行测试暴露时序脆弱性

niri 单线程 289/289 通过，但默认并行连续失败，集中在 layer-close。测试和实现对共享 clock、GPU snapshot 或全局状态存在耦合。

### P2-08：缺少性能回归测试和可观测性

目前没有自动验证：

- 空闲 redraw rate。
- 每个 redraw source。
- glass damage 面积。
- P95/P99 frame time。
- GPU readback 耗时。
- 输入到呈现延迟。
- Quickshell 2 小时 RSS 稳定性。

### P2-09：运行策略会放大性能问题

高刷新率、VRR 关闭、接电 performance profile、常驻 wallpaper 和 Top layer 叠加，使代码中的小型无效工作变成持续高功耗。

## 8. 已排除或修正的旧判断

窗口 ClosingWindow 的 transaction blocker 不是“确定没有超时”。

niri/src/handlers/xdg_shell.rs 和 niri/src/handlers/compositor.rs 的当前调用路径会在 transaction 仍有实例时注册 300ms deadline。该问题不列入确认缺陷。

以后报告问题时必须检查完整调用链，不能只根据局部类型判断资源是否会永久等待。

## 9. 目标架构

### 9.1 帧与动画

1. niri 是输出帧调度唯一 owner。
2. 每个 animation source 暴露 next deadline，而不是只有 bool。
3. 空闲时无持续 redraw。
4. layer/window 外层动画由 compositor 统一负责。
5. QML 只负责 surface 内部微动画。

### 9.2 玻璃

1. TahoeGlass 协议保持唯一。
2. QML 提交稳定、最小化的 region。
3. Tahoe 液态玻璃统一使用 nonxray composed framebuffer；xray 只保留给明确要求跳过普通窗口的非默认效果。
4. blur 资源复用。
5. damage 精确覆盖变化区域。

### 9.3 缩略图

1. ThumbnailProvider 是 Shell 唯一入口。
2. niri window-thumbnail IPC 保持唯一 compositor 入口。
3. capture、readback、encode、publish 具有清晰阶段。
4. 文件只在完整后原子发布。
5. per-window state 只唤醒相关消费者。

### 9.4 设置写入

1. 控件维护预览值。
2. Service 维护提交值。
3. NiriSettings 是唯一 KDL writer。
4. 一次交互最多一次最终配置 reload。

### 9.5 外部进程

1. 事件优先。
2. 轮询必须有 owner、活动条件、最低周期和退出条件。
3. 同类命令合并。
4. 新请求能取消旧请求。
5. 关闭 UI 后不允许无界扫描或 discovery 继续。

## 10. 严格串行修复路线图

任务依赖关系：

    R01 -> R02 -> R03 -> R04 -> R05 -> R06 -> R07 -> R08
        -> R09 -> R10 -> R11 -> R12 -> R13 -> R14 -> R15

任何任务未完成审查、commit 和 push 时，后续任务保持 pending。

### R01：增加 redraw、frame time 和 damage 诊断

目标：

- 唯一定位 240Hz 持续重绘来源。
- 建立后续任务共同使用的基线。

允许修改：

- niri/src/niri.rs
- niri/src/backend/tty.rs
- niri/src/frame_clock.rs
- 现有 debug/telemetry 结构

禁止：

- 新建第二个 frame scheduler。
- 用高频日志替代计数器。

验收：

- 能按来源看到 layout、cursor、layer、UI、screen transition 等 ongoing 状态。
- 能测量提交帧率、P95/P99 frame time 和 damage area。
- 默认关闭时开销接近零。

审查重点：

- 诊断是否改变 frame scheduling。
- 是否会在 240Hz 产生日志风暴。

建议 commit：

    perf(niri): add redraw-source and frame-budget telemetry

### R02：修复 VRR 与空闲帧调度

前置：R01 已 push。

目标：

- 空闲桌面不持续按 240Hz 提交。
- 建立明确 VRR 策略。

范围：

- 当前 frame clock、output config 和 on-demand VRR 路径。

禁止：

- 通过强制降到 60Hz 掩盖 ongoing flag。
- 新建 QML 刷新率服务。

验收：

- 静止 30 秒没有持续 240Hz redraw。
- VRR supported 输出按策略启用。
- cursor、输入和动画启动无额外首帧延迟。

建议 commit：

    fix(render): stop idle vblank redraw and enable vrr policy

### R03：修复 cursor deadline 和永久 animation flag

前置：R02 已 push。

目标：

- CursorManager 暴露下一帧 deadline。
- baba_is_float 不再永久报告 ongoing。

禁止：

- 新建独立 cursor animation service。

验收：

- 动画光标只在 frame delay 到期时重绘。
- baba_is_float 使用明确低频 deadline。
- 空闲 GPU 不因光标主题多帧而升高。

### R04：建立玻璃采样策略

前置：R03 已 push。

目标：

- 明确 xray/nonxray 的视觉语义，所有液态玻璃保留实时 composed framebuffer 采样。
- 在现有实时路径内控制 framebuffer capture 成本，不用 wallpaper-only backdrop 换取性能。

范围：

- 现有 Tahoe material 配置。
- BackgroundEffect/TahoeGlass 现有 xray 选择。

禁止：

- TahoeGlassV2。
- 第二套 QML GlassPanel。

验收：

- 22 个生产 GlassPanel 调用点和 7 个 fallback 均随后方普通窗口变化。
- Dock、panel、Launchpad backdrop、pill、menu 和 toast 视觉正确。
- FBO、shader、damage 与 commit 优化后，静止和交互 GPU 仍在预算内。

### R05：缓存 blur/framebuffer 资源

前置：R04 已 push。

目标：

- 缓存 FBO 和可复用资源。
- 明确失效条件。

验收：

- steady-state render 不再每帧 Gen/Delete framebuffer。
- resize、scale、output hotplug 正确失效。
- blur 单元和渲染测试通过。

### R06：优化玻璃 shader

前置：R05 已 push。

目标：

- 零 feature 不执行昂贵函数。
- 大面积材质使用合理复杂度。

禁止：

- 复制一份独立 postprocess shader 接口。

验收：

- feature 为零时编译或运行路径明显简化。
- 视觉基线无非预期变化。
- shader 编译失败有测试覆盖。

### R07：收紧 TahoeGlass damage 与动态岛 commit

前置：R06 已 push。

目标：

- region 更新只 damage old/new union。
- 动态岛动画期间减少 mask 和协议 commit。

验收：

- 动态岛 damage 面积低于输出面积 15%。
- swipe、hover、click 命中正确。
- sibling stacking 不再决定手势是否工作。

### R08：异步化缩略图并原子发布

前置：R07 已 push。

目标：

- 主事件循环不承担 PNG 编码和文件写入。
- 文件原子发布。
- Overview 批量请求受预算控制。

禁止：

- 第二个 provider。
- 组件直接 screencopy。

验收：

- 1000 次缩略图请求无解码失败。
- 打开 Overview 时 frame P99 不因 PNG 编码产生长尾。
- 取消或窗口关闭时无陈旧文件覆盖新 generation。

### R09：修复 layer close 和 spring 连续性

前置：R08 已 push。

目标：

- snapshot 完成后启动动画 clock。
- spring restart 使用新 initial velocity。
- solver 失败不返回零时长瞬移。

验收：

- niri 单线程和默认并行连续 10 次通过。
- close 动画在压力下不跳过。
- 手势中断和反向速度连续。

### R10：统一 compositor/QML 动画所有权

前置：R09 已 push。

目标：

- 每类 surface 的外层进出场只有一个 owner。
- 删除 Toast、Sidebar、Spotlight 的重复外层路径。

禁止：

- 保留新旧外层动画并用开关长期切换。

验收：

- 开关语义真实生效。
- Toast 不再出现两段退出。
- reduced motion 在两层语义一致。

### R11：修复设置滑杆和高频写入

前置：R10 已 push。

目标：

- Niri、色温和亮度滑杆使用 preview/commit。
- 合并外部进程调用。

验收：

- 一次连续拖动最多一次最终 niri reload。
- 色温无进程风暴和闪烁。
- 亮度反馈即时，硬件写入不超过 30Hz，并在 release 提交最终值。

### R12：治理搜索、Apps、Bluetooth 和轮询

前置：R11 已 push。

目标：

- 旧查询可取消。
- Apps 默认 probe 使用 fingerprint 缓存。
- 权限和目录扫描可取消并有预算。
- Bluetooth discovery 有生命周期和超时。
- 常驻轮询统一活动条件。

禁止：

- 新建第二个 CommandRunner。
- 为每个页面新建守护进程。

验收：

- 关闭 UI 后无相关扫描或 discovery。
- 连续输入只应用最新查询。
- 空闲 Quickshell rchar 显著下降。

### R13：通知、锁屏和启动正确性

前置：R12 已 push。

目标：

- hover/按压暂停 toast deadline。
- DND 行为与文案一致。
- NotificationCenter 关闭后卸载重内容。
- LockScreen 单一密码状态。
- 启动日志无本报告列出的 QML 错误。

### R14：Direct scanout、壁纸和背景预算

前置：R13 已 push。

目标：

- 全屏应用恢复 direct scanout 条件。
- TopBar/Dock 真正退出合成路径。
- wallpaper、Weather Canvas 和 power profile 服从统一预算。

验收：

- 合适全屏应用能够进入 direct scanout。
- 全屏时 wallpaper 暂停或降到明确低预算。
- 电池和接电策略不会默认掩盖高功耗。

### R15：可维护性和质量门禁

前置：R14 已 push。

目标：

- cargo fmt 通过。
- 安装并建立 Clippy 基线。
- QML lint 能实际解析运行模块。
- 增加性能回归测试。
- 按职责拆分超大文件。

禁止：

- 只增加 facade 而不删除旧代码。
- 为了减少单文件行数机械搬运但保留双向耦合。

验收：

- CI 中格式、lint、单线程和并行测试全部通过。
- 性能基线自动记录。
- 拆分后依赖方向单向且 owner 清晰。

## 11. 每个任务的固定执行流程

每个 Rxx 任务必须严格执行以下步骤。

### 阶段 A：进入任务

1. 确认上一任务已经 push。
2. git status 必须干净。
3. HEAD 与 upstream 必须没有意外分叉。
4. 在本文件状态表中把唯一当前任务标为 in_progress。
5. 记录任务前性能和测试基线。

### 阶段 B：实现

1. 只修改任务允许范围。
2. 不做顺手重构。
3. 不创建平行接口。
4. 如果必须修改接口，在同一任务更新全部调用者并删除旧接口。
5. 增加能证明修复的测试或度量。

### 阶段 C：验证

按风险执行：

1. 目标单元测试。
2. 相关集成测试。
3. niri 单线程测试。
4. niri 默认并行测试。
5. Quickshell Tahoe CTest。
6. Shell 测试。
7. cargo fmt 和 Clippy。
8. QML 启动与运行日志检查。
9. GPU、frame time、damage 或 IO 对比。

任何必要检查失败，任务不得进入 commit。

### 阶段 D：审查

必须完成三层审查：

#### 正确性审查

- 是否解决根因。
- 是否覆盖取消、错误、重启、output hotplug、scale 和关闭生命周期。
- 是否有竞态、陈旧 generation 或半写入状态。

#### 性能审查

- 是否减少工作，而不是把工作移到另一线程后继续无限执行。
- 是否减少 redraw、damage、GPU readback、process spawn 或 IO。
- 是否引入长期缓存且缺少失效。

#### 反腐化审查

- 是否出现第二 provider、第二 writer、第二协议或第二 owner。
- 是否保留旧路径。
- 是否复制 token。
- 是否出现临时兼容层且没有在同一任务删除。

### 阶段 E：提交和推送

只有审查全部通过后：

1. 本文件中的任务状态和验收指标更新为 reviewed 或 verified。
2. 查看完整 git diff。
3. 确认只有当前任务范围内的文件。
4. 创建一个原子 commit，不创建 WIP commit。
5. push 当前 commit。
6. 确认本地 HEAD 与 upstream 一致。
7. commit id 以 Git 历史为唯一证据，不在该 commit 内写入自身哈希；push 后在任务交付结果中报告 commit id。
8. 工作树重新干净后，才允许开始下一任务。

禁止：

- force push。
- 审查前 commit。
- push 后 amend 并强推。
- 将多个路线图任务塞入同一 commit。

## 12. 审查清单

每个任务在审查和交付阶段必须逐项回答“是”。其中“提交前”项目必须在 commit 前完成，“推送后”项目用于决定任务能否正式结束。

### 范围

- [ ] 只处理一个 Rxx 任务。
- [ ] 没有修改无关文件。
- [ ] 没有把发现的新问题顺带修复。

### 反腐化

- [ ] 没有新增平行生产接口。
- [ ] 状态 owner 仍然唯一。
- [ ] 旧路径已在同一任务删除。
- [ ] 没有复制配置、材质或动画 token。
- [ ] 没有新增无退出条件的 Timer 或 Process。

### 正确性

- [ ] 新测试先能证明旧问题，再证明修复。
- [ ] 错误、取消和关闭路径已覆盖。
- [ ] 没有陈旧异步结果覆盖新状态。
- [ ] 运行日志没有新增 warning/error。

### 性能

- [ ] 有任务前后数据。
- [ ] P95/P99 没有回退。
- [ ] 空闲资源没有回退。
- [ ] damage、redraw 或进程数量符合目标。

### Git：提交前

- [ ] git diff 已逐文件审查。
- [ ] commit 是单一原子任务。
- [ ] commit message 描述根因和结果。

### Git：推送后

- [ ] push 成功。
- [ ] HEAD 与 upstream 一致。

## 13. 总体验收指标

### 13.1 空闲桌面

| 指标 | 目标 |
|---|---|
| niri GPU | 低于 5% 至 8% SM |
| compositor redraw | 无持续 240Hz redraw |
| Quickshell RSS | 2 小时内趋于稳定，建议低于 250 至 300 MiB |
| Quickshell 空闲 rchar | 降至约 100 KiB/s 级或给出可解释来源 |
| wallpaper | idle/fullscreen 时暂停或进入明确低预算 |

### 13.2 动画

| 指标 | 目标 |
|---|---|
| 240Hz P95 frame time | 小于 4.17ms |
| 240Hz P99 frame time | 小于 6ms |
| 普通动画掉帧 | 小于 1% |
| layer close | 压力和并行测试下不跳过 |
| 动画中断 | 速度连续，无瞬移 |
| reduced motion | compositor 与 QML 行为一致 |

### 13.3 玻璃和 damage

| 指标 | 目标 |
|---|---|
| 动态岛 damage | 小于输出面积 15% |
| steady-state FBO 创建 | 每帧为零 |
| disabled shader feature | 不执行对应昂贵路径 |
| region commit | 与真实几何变化次数一致，不跟随无关 property |

### 13.4 缩略图

| 指标 | 目标 |
|---|---|
| 连续请求 | 1000 次无损坏 PNG |
| 主事件循环 | 不执行 PNG 编码和磁盘写入 |
| Overview 打开 | 无 readback/encode 长尾抢占进入动画 |
| consumer 更新 | 仅相关 window delegate 更新 |

### 13.5 输入和设置

| 指标 | 目标 |
|---|---|
| Niri 设置拖动 | 最多一次最终 reload |
| 亮度写入 | 不超过 30Hz，release 提交最终值 |
| 色温 | 无连续 gammastep 进程风暴 |
| MenuRow 动作 | 立即或 80ms 内执行 |
| 输入到呈现 P95 | 建议小于 20ms |

## 14. 风险与回滚

### 高风险区域

1. frame scheduling 和 VRR。
2. renderer context/FBO 生命周期。
3. TahoeGlass damage 和协议 commit。
4. GPU readback 与线程迁移。
5. layer close clock。
6. direct scanout 和 overlay planes。

### 回滚原则

1. 每个任务一个原子 commit，便于普通 git revert。
2. 不使用 reset --hard 或 force push。
3. 回滚后必须重新运行该任务验证集。
4. 回滚不能恢复已经证明会损坏数据的非原子写路径；如遇紧急情况，应禁用功能而不是恢复数据竞争。

## 15. 状态表

| 任务 | 状态 | 核心验收记录 |
|---|---|---|
| 报告基线 | reviewed | 38 个独立问题，10/19/9 分级；结构、源码引用和执行门禁审查通过 |
| R01 诊断 | verified | `NIRI_FRAME_TELEMETRY=1` 显式启用、默认关闭；每 5 秒按输出汇总 layout/cursor/layer/UI/screen-transition/closing-layer 来源、submitted/presented FPS、render 与 frame-time P95/P99、damage pixels/percent；目标测试 2/2、niri 单线程 291/291、niri-config 35/35、niri-ipc 3/3、release check 通过；默认并行复现既有 4 个 layer-close 时序失败；全仓 fmt 与 Clippy 仍为既有基线门禁问题 |
| R02 帧调度与 VRR | verified | Tahoe 输出采用唯一 always-on VRR 策略并已部署，eDP-2 保持 2560×1600@239.998Hz 且 VRR supported/enabled；on-demand 状态切换改为显式目标值并在 KMS pending 状态变化后补一帧，避免静态窗口首帧后未应用；新二进制隔离 30 秒稳定窗口为 0.1 redraw/s、所有 ongoing 来源为 0；Shell 708/708（185 subtests）、niri 单线程 291/291、niri-config 35/35、niri-ipc 3/3、release build/check 与 guardrails 通过；默认并行仍复现既有 3 个 layer-close 时序失败；当前旧桌面进程未破坏性重启，R03 将继续处理 cursor/permanent animation deadline |
| R03 Cursor 与永久 animation | verified | `CursorManager`/`XCursor` 暴露按主题 frame delay 计算的绝对下一帧 deadline；niri 复用每输出唯一 one-shot calloop timer 调度 cursor 与 `baba_is_float` 的最早 deadline，并在替换、显示器停用和 output 移除时取消；`baba_is_float` 固定 30Hz，已从 `Tile`/`MappedLayer` continuous ongoing 语义删除，集成测试同时确认 timer 已注册且 `unfinished_animations_remain=false`；新增回归 5/5、niri 单线程 297/297、niri-config 35/35（wiki 1/1）、niri-ipc 3/3（doctest 1/1）、release build/check、Shell 708/708（185 subtests）、Quickshell Tahoe CTest 12/12、guardrails 与 changed-code rustfmt/diff check 通过；默认并行仅复现既有 5 个 layer-close 时序失败，全仓 fmt 与未安装 Clippy 仍为既有 R15 门禁；当前桌面会话未破坏性重启，调度频率由 deadline 和状态回归确定性验收 |
| R04 玻璃采样策略 | verified | 后续现场回归复核否决原先把 `xray=true` 当作无损共享采样的结论：xray buffer 只含 workspace backdrop/background layer，会跳过普通窗口。七种 Tahoe material、未知 material 默认值、普通窗口和 7 个 layer-rule fallback 现统一 `xray=false`，并删除 Rust `live_material_profile` 分叉；治理测试锁定 22 个生产 GlassPanel 调用点（panel 11、pill 1、dock 1、menu 7、toast 1、backdrop 1，launcher 当前 0）及其唯一实时采样语义。配置已部署并热加载；同一 Control Center 内的像素从壁纸区 `srgb(197,213,225)` 随白窗边界变为 `srgb(247,249,252)`，Dock 白窗截图、Launchpad composed backdrop、Dynamic Island pill 与 TaskSwitcher menu 均通过。12 秒静止桌面 `nvidia-smi pmon` 的 niri 全样本均值约 8% SM（5 个零/低于阈值样本，数值 4% 至 26%；动态壁纸同期 6% 至 31%），无 240Hz 常驻重绘回退。目标治理 4/4、Shell 699/699、niri 单线程 313/313、niri-config 35/35（wiki 1/1）、Quickshell Tahoe CTest 12/12、release check、配置 validate、guardrails 与 diff check 通过；默认并行仅复现 R09 已记录的 4 个 layer-close 时序失败；全仓 fmt 仍为既有 R15 门禁 |
| R05 Blur/FBO 缓存 | verified | `FramebufferEffect` 与 `Blur` 复用 EGL renderer context 唯一 scratch FBO，热路径从每次 render 合计 3 次 Gen/Delete 收敛为每 context 1 次 Gen、每帧 0 次 Delete；attachment 用后 detach，FramebufferEffect 按 renderer context/size/format、Blur pyramid 按 size/format/pass 明确失效；真实嵌套 winit + Quickshell background-effect 连续渲染只创建 1 个 FBO，scale 1.0↔1.5 与 output off/on 均成功并触发预期 texture 重建，日志无渲染错误；新增缓存/失效/blur 单元 5/5、render helpers 23/23、niri 单线程 302/302、niri-config 35/35（wiki 1/1）、niri-ipc 3/3（doctest 1/1）、Shell 709/709、Quickshell Tahoe CTest 12/12、release build/check、guardrails 与 diff check 通过；`d17059b0` release 二进制已部署，当前桌面进程未破坏性重启；默认并行仅复现既有 5 个 layer-close 时序失败，全仓 fmt 与未安装 Clippy 仍为既有 R15 门禁 |
| R06 Shader 优化 | verified | 沿用唯一 `postprocess_and_clip` 与现有材质 uniform：`edge_highlight`、`inner_shadow`、`refraction`/`lens_depth` 在昂贵函数前短路，feature 为零时对应 SDF normal、value noise、caustic 与 `pow` 调用均为 0；长边/大面积材质保留方向性 rim 的低复杂度路径，高光由每像素 7 次 `value_noise` + 1 次 `pow` 降为 0，折射由 8 次 `value_noise` 降为 0；真实 surfaceless EGL 同时验证生产 shader 编译成功和非法源码明确失败，新增目标回归 3/3、TahoeGlass 28/28、niri 单线程 305/305、niri-config 35/35（wiki 1/1）、niri-ipc 3/3（doctest 1/1）、Shell 709/709（192 subtests）、Quickshell Tahoe CTest 12/12、release build/check、guardrails 与 diff check 通过；隔离 winit 截图确认 TopBar、动态岛和控制中心视觉无非预期变化，日志无 shader/QML 新错误；默认并行仅复现既有 4 个 layer-close 时序失败，全仓 fmt/Clippy 仍保留 R15 基线门禁 |
| R07 Damage 与动态岛 commit | verified | niri 按 region id 仅选择真实新增/删除/字段变化的 old/new rect，并在单次及 render 前多次 commit 间维持非重叠 union；删除协议 commit 后再次 damage 全部 BackgroundEffect/Shadow 的旧路径，材质-only 同 rect 只计一次；最大 440×220 动态岛 union 为 96,800 px，占 2560×1600 输出 2.36%，低于 15% 门禁。动态岛视觉几何保持平滑，唯一 TahoeGlass region 采用 8/8/4px 过渡量化并在 settle 发布精确目标，代表性 240Hz morph 从 54 次降到 40 次以内；nested OSD morph 实测 11 次 region commit，8 次 swipe advance 仅产生 4 次 commit，resolve 后 dragging/settling 均归零。Overlay input mask 绑定未动画的目标几何；TopBar 真正挖空中心并删除 sibling 点击/hover 代理，click/swipe/wheel 由 Overlay 原生 MouseArea 唯一拥有；目标 damage/TahoeGlass 回归 32/32、动态岛目标 85 passed（52 subtests）、niri 单线程 309/309、niri-config 35/35（wiki 1/1）、niri-ipc 3/3（doctest 1/1）、Shell 710/710（192 subtests）、Quickshell Tahoe CTest 12/12、release build/check、guardrails 与 diff check 通过；隔离 winit 截图及 IPC swipe/OSD 验收无视觉、协议或 QML 新错误；默认并行仅复现既有 5 个 layer-close 时序失败 |
| R08 缩略图异步与原子发布 | verified | 保留唯一 `window-thumbnail` IPC 与唯一 `ThumbnailProvider`：compositor 主线程只做 GL render/readback，容量 16 的单 worker 承担 PNG 编码、同目录 `create_new` 临时文件、flush、文件/目录 `sync_all` 和 atomic rename；每路径 generation、IPC receiver 与 window-id 取消门控发布，刷新失败恢复上一 token。真实同 socket 1000 次 64px 请求逐次 PIL 解码 0 失败，并发读取 54,700 次 0 失败、P99 7.847ms、max 38.843ms、临时文件 0；首张已发布后关闭窗口的 12 并发请求最终目标/临时文件均 0。Overview 入场 settle 后才请求，provider 限 8 张/会话并以 48ms 节流、关闭按 requester 精确取消；nested 10 窗口只发布 8 张，实测约 48–55ms 间隔，稳定/Overview+缩略图 render P99 9.40/10.63ms，无编码长尾。新增原子/陈旧 generation/失败恢复目标 4/4、Shell 目标 18/18，niri 单线程 313/313、niri-config 35/35（wiki 1/1）、niri-ipc 3/3（doctest 1/1）、Shell 712/712（192 subtests）、Quickshell Tahoe CTest 12/12、release build/check、guardrails 与 changed-code rustfmt/diff check 通过；默认并行仅复现既有 4 个 layer-close 时序失败 |
| R09 Layer close 与 spring | verified | `ClosingLayer` 完成普通/blocked-out snapshot texture 渲染后刷新唯一 niri clock 并创建 transform/opacity 动画，纹理准备时间不再消耗 close 时长；12 个 layer 动画回归统一使用各 fixture 的冻结 clock。`Animation::restarted` 的 spring 分支使用调用者的新 initial velocity；过阻尼 Newton 斜率、非有限值、负时间和迭代失败惰性退回稳定双指数上界求解，不再返回零时长。修复前默认并行为 309/313，稳定失败 4 个 layer-close；修复后默认并行连续 10 次 316/316、单线程连续 10 次 316/316。spring/animation 目标 12/12、layer-close 目标 10/10、niri-config 35/35（wiki 1/1）、niri-ipc 3/3（doctest 1/1）、release check、Shell 712/712（214 subtests）、Quickshell Tahoe CTest 12/12、guardrails、changed-code rustfmt 与 diff check 通过；全仓 fmt 和未安装 Clippy 保留既有 R15 门禁 |
| R10 动画所有权 | verified | niri 现为 Toast、LeftSidebar、Spotlight surface 外层进出场的唯一 owner；三者已删除 QML 位移、缩放、surface 淡出 fallback，Launchpad 继续明确由 QML 拥有。旧 `DesktopSettings.compositorLayerAnimations` JSON 镜像已删除，现有 `NiriSettings`/`niri_settings_tool.py` 唯一 KDL writer 在 7 个受管 layer-rule 的 14 个 open/close phase 中可逆增删 `off`；真实关闭/恢复往返保留 profile 且恢复后 SHA-256 字节一致，缺失 rule 时拒绝写入。nested winit 实测 Sidebar/Spotlight 均单次 map/unmap；禁用 Dynamic Island 后 Toast 仅 1 个 surface，关闭后 58ms 撤销且未再次映射；`reduced` 同时同步到 niri profile 与 QML `motionProfile`，切换 profile 不会重开已关闭的 layer channel。Shell 717/717（217 subtests）、Quickshell Tahoe CTest 12/12、guardrails、生产配置 validate、diff check 和隔离运行日志零新增 warning/error 均通过 |
| R11 设置高频写入 | verified | 共享 `TahoeSlider` 现以控件本地 `displayValue` 提供逐 sample preview，并只在 release/cancel 发出一次 commit；全部 35 个 Niri 设置滑杆调用点只在 commit 进入现有 `NiriSettings` 单 writer，因此一次连续拖动最多一次 KDL validate/write/reload。色温同样只在 commit 持久化，`Appearance` 将 detached gammastep 调用收敛为单一 Process，按 enabled/temperature key 去重并在运行中只保留最新请求，夜览关闭时调整色温不启动进程。Control Center 与 Power 亮度滑杆逐 sample 乐观反馈，现有 `Controls` latest-wins 队列以 34ms 最小启动间隔限制 `brightnessctl` 低于 30Hz，并在 release 重新入队最终值；Process 退出后的续写通过 `Qt.callLater` 避免 running 清零竞态。目标回归 36/36（真实 QML 6 subtests）、Shell 724/724（217 subtests）、Quickshell Tahoe CTest 12/12、qmllint、guardrails、diff check 与 12 秒隔离 nested 启动日志零新增 QML warning/error 均通过 |
| R12 服务、搜索和轮询 | verified | Spotlight 慢 provider 保留单一 Process，以 query/generation 冻结请求身份；新输入或 UI 关闭会立即 terminate 旧任务，stdout/exit 只有同时匹配最新 generation 与 query 时才发布。Apps 默认应用先运行 desktop entry/mimeapps metadata fingerprint，缓存命中不再执行完整扫描；实机 102 个 desktop entry 的 fingerprint 为 30.7ms/253B，完整 probe 为 769.8ms/64174B。权限、Flatpak/Snap 和目录统计共享 1600ms deadline，目录上限降为 4000 文件，选择 A→B→C 会立即终止旧 Python probe 并只发布 C；实机权限 probe 为 57.2ms，预算未超限。Bluetooth discovery 由 Controls 唯一 owner map 管理，Control Center/Settings 各自 acquire/release，关闭、切页、禁用适配器或 15 秒 timeout 均 stop；隔离会话关闭 UI 后 `bluetoothctl show` 为 `Discovering: no`。CommandRunner、亮度/Wi-Fi、VPN、系统能力、声音、电源模式、风扇和输入法的周期 Process 统一绑定 `servicePollingActive`，关闭 UI 同时取消 in-flight probe 且取消退出不会触发 fallback 或错误覆盖；InputMethod 仅保留一次启动探测。旧部署实例同期 10 秒 `rchar` 为 48,073,937B（4,807,393B/s）；新 nested 会话 warm-up 后覆盖完整 30 秒旧轮询边界的 35 秒窗口仅 2,448B（69B/s，下降超过 99.99%），子进程中无 Search/Apps scan 或 Bluetooth discovery。Shell 735/735（217 subtests）、Quickshell Tahoe CTest 12/12、qmllint、Python compile、guardrails 和 diff check 通过；nested 日志无新增 R12 warning/error，报告列出的 R13 启动警告按顺序保留 |
| R13 通知、锁屏与启动错误 | verified | `Notifications` 继续作为唯一生命周期 owner，按通知 id 保存 hover/按压暂停时的剩余 deadline，Toast 只上报交互状态；恢复后按剩余时长过期，Timer 触发前再次检查交互门控。开启 DND 会撤下当前 active banner、保留历史并继续抑制新横幅，使“横幅和提示音已静音”文案与行为一致。NotificationCenter 以 `Loader.active=open` 管理唯一内容树，关闭后销毁分组 Repeater、最多 60 行及 Image。LockScreen 删除独立 `root.password`，PAM 只消费 `TextInput.text`，lock/unlock/response/completed/error 统一清空并恢复焦点；`SystemClock` 在消费 binding 前声明。删除 `Qt.application.font` 只读写入并修正 StartupPage delegate id。新增 R13 目标回归 6/6（真实通知 deadline/DND 2 subtests），锁屏真实 QML 回归含密码生命周期；Shell 741/741（217 subtests）、Quickshell Tahoe CTest 12/12、qmllint 解析、Python compile、guardrails、niri config validate 与 diff check 通过；15 秒 repo nested 启动日志无报告所列 QML error，只有既有 EGL warning 与 timeout 结束时的 xwayland SIGTERM；`shellcheck` 未安装，保留为 R15 工具链门禁。 |
| R14 Direct scanout 与背景预算 | pending |  |
| R15 质量门禁与拆分 | pending |  |

## 16. 当前任务完成条件

本报告基线任务只有满足以下条件才算完成：

1. 文件已创建。
2. 问题数量、优先级和源码引用已审查。
3. 反腐化和禁止平行接口规则明确。
4. 路线图严格串行。
5. 每个任务都有验证和审查门禁。
6. git diff 只包含本文件。
7. 审查通过后才 commit。
8. push 成功并确认 upstream 一致。
