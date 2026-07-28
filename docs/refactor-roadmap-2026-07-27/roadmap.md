# Tahoe Desktop 重构修复改进路线图（2026-07-27）

配套研究报告：本目录 `research-report.md`（编号 A-*/S-*/R-*/M-*）。
已并入 `docs/code-audit-2026-07-27/verified-findings.md` 的全部确认项（编号 F-01~F-13）与其第九节优先级建议。

## 执行纪律（对每个任务生效，不可省略）

1. **串行**：每次只做一个任务，完成（含审查、commit、push）之前不得开始下一个。
2. **不要最小实现**：允许并鼓励局部重构，把问题在其结构根因处修掉；但——
3. **不得创建平行接口**：不允许为兼容旧路径而新增第二套 API/属性/协议通道并行存在。重构时直接改造现有接口及其全部调用点；如接口签名需扩展，一次性迁移所有消费者。
4. **不得破坏原有功能与实现语义**：改动前明确现有行为契约（含既有测试、guardrail 脚本、`// TAHOE:`/FIXME 注释记录的意图）；重构后行为等价或按任务验收标准明确改善，不引入回归。
5. **完成定义**：代码 + 配套测试更新 + 任务自带验收方法通过。
6. **审查门**：每个任务完成后，必须派**独立子代理做对抗性审查**（多角度：正确性/回归面/与既有兜底机制的交互），审查通过后才允许 `git commit` + `git push`。审查发现问题则修复后重审。
7. 涉及 niri/quickshell 子模块的任务：先在子模块 commit/push，再在主仓库前移指针（吸取 P05 map-commit 教训，见记忆 render-perf-p05）。
8. R 系列性能任务受 profiling 门槛约束（≥0.3ms/帧@60Hz 或 ≥3% GPU 帧时间才准入实现），T-30 是它们的前置。

---

## 阶段 0：护栏与地基（低风险，先行）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-01 | 为 niri/quickshell 两个子模块添加 upstream remote，新增分叉周报脚本（rev-list count + merge-base 日期），并入 check 脚本体系 | M-A① | 脚本输出两 fork 的落后量报告 |
| T-02 | 主仓库建 `protocols/tahoe-glass-v1.xml` 权威副本；`check-submodules.sh` 增加对两个子模块拷贝的 sha256 一致性校验；撰写 `protocols/CONTRACT.md`（tahoe_glass 协议 / event-stream JSON / `niri msg action` 三通道契约与字段依赖清单） | M-B | 校验脚本对当前树通过；人为改动一份拷贝时 fail |
| T-03 | 移除 `scripts/diagnose-quickshell-crash.sh` 自动 push：内容脱敏（hostname/用户名/路径最小化）+ 明确交互确认；同时修 `scripts/diagnose-tray-launcher.sh` 与 `tools/mrid6_dump_wmi_acpi.sh` 的固定 `/tmp` 路径为 `mktemp` 安全机制 | F-02、F-03 | 无确认不外发；symlink 预置攻击不再可截断目标文件 |
| T-04 | `scripts/check-tahoe-glass-guardrails.sh` 去硬编码机器路径（`$HOME`/XDG 推导） | F-09 | 任意用户名环境下脚本可运行 |

## 阶段 1：内存安全与稳定性（quickshell/niri C++/Rust）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-05 | 修复 Quickshell Color IPC 存储类型错误：`ColorIpcType` 的 `createStorage`/`destroyStorage`/`copyStorage` 与 `sizeof(QColor)` 一致化（`quickshell/src/io/ipc.cpp`、`ipchandler.cpp`）。允许重构 IpcType 存储层为类型统一的模板/工厂，消除 bool/QColor 手写分支这类错配的结构土壤；不新增平行注册通道 | F-01 | 新增 color 参数/返回值/属性三向 IPC 测试；ASan 下无越界/错误 delete |
| T-06 | 修复 crash handler partial-write 循环（`quickshell/src/crash/handler.cpp:73-84`）：从 `wptr` 写剩余长度，循环边界正确 | F-04 | 构造 partial write 的单测（或注入小 pipe buffer）验证帧无重复、无越界 |
| T-07 | niri 多键 repeat 状态模型重构（`niri/src/input/mod.rs:404-415`）：单 timer 改为跟踪当前应重复的键（按最后按下者），释放非当前键不取消 repeat。允许把 repeat 状态收敛为独立小结构体 | F-06 | 双键按住/交替释放的输入测试 |
| T-08 | 混合缩放 tablet clamp 用平板映射输出的 scale（`input/mod.rs:335-344`）；pointer constraint 改用实时 surface 全局原点（`input/mod.rs:2484-2505,2613-2625`），必要时重构约束检查取坐标的路径 | F-07、F-08 | 混合 scale 双屏回归测试；约束期间移动窗口的场景测试 |

## 阶段 2：compositor 动画速度连续性（niri）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-09 | `Animation::velocity()` 基础设施：`Spring::velocity_at(t)` 解析导数（三分支闭式解）+ Easing/Deceleration 有限差分；返回值乘回 `clock.rate()`；初速钳制防 overdamped 爆炸。这是接口扩展而非平行接口——`restarted` 调用点后续任务全部迁移 | A-1① | 导数正确性单测（数值 vs 解析 <1e-6）；rate≠1 下无双重缩放 |
| T-10 | 六处重定向站点全部改为速度续接（scrolling.rs:883、monitor.rs:444/1379、tile.rs:638/415、mru.rs:281），tile 归一化速度换算 | A-1② | restart 前后 1ms 差分速度差 <1% 单测；连按 focus-column 手感走查 |
| T-11 | swipe 释放二次吸附重构：把右缘吸附目标重算提前到 `view_offset_gesture_end` 内、只创建一次带速度动画，删除 HACK 双动画路径（scrolling.rs:4154-4163） | A-2 | 宽窗口快速 swipe 逐帧 view_pos 无速度突变 |
| T-12 | genie 反转速度续接（minimize_window_animation.rs:274-333）：`restart_progress` 携带取向修正后的当前速度 | F-05 / A-4 | 反转瞬间 morph 进度导数连续单测；录帧走查 |
| T-13 | interactive move 惯性：`InteractiveMoveState::Moving` 挂 SwipeTracker，`interactive_move_end` 经速度参数进入 `animate_move_from`（扩展现有函数签名并迁移全部调用点，不建平行函数） | A-6 | 拖拽释放首帧 render_offset 速度 ≈ 指针速度 |
| T-14 | SwipeTracker 重构：velocity 改最小二乘斜率（或排除首事件 delta）；gesture end 空闲补偿直取 `get_monotonic_time()`（monitor.rs:1983、scrolling.rs:3855） | A-5 | 2 事件序列速度单测；手感 A/B 后微调 deceleration/spring |
| T-15 | resize 动画目标追踪：`Tile::update_window` 保留动画相位只更新 `size_from`（按 delta 分档，大跳变仍重启）；scrolling.rs:1593 目标差 < 阈值跳过重建 | A-3 | 三连 commit 期间动画 start_time 不变断言 |
| T-16 | 收尾三小项：swap 保留目标 tile 动画（`add_tile_to_column` 加抑制参数并迁移调用点）；transaction TIME_LIMIT 300→150ms（或 alpha 先行）；overview 几何统一物理像素 round | A-7、A-8、A-9 | 连续 swap 动画连续；关窗起播延迟测量；fractional scale 逐帧 diff |

## 阶段 3：glass/genie 跨进程时序（quickshell + niri + shell）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-17 | quickshell commit 原子化重构：tahoe_glass 的 region 与 `sendTransform*` 显式 commit 统一为"窗口有待重绘则不显式 commit、依赖 render 线程 buffer commit 原子携带"（qml.cpp:539-589、738-798）；用 `UpdateRequest` 钩子置 dirty flag。这是对现有 commit 路径的改造，不新增通道 | S-H1、S-M6 | `WAYLAND_DEBUG=1` 抓 dock grow：每帧一次 commit、set_region 与 attach 同 commit |
| T-18 | 撤 42039bb clamp 兜底（T-17 根因已除后），回归验证 mid-animation band | S-H1 后续 | 撤除后 grow 动画无超前带；guardrail 走查 |
| T-19 | genie 目标 rest 化（纯 QML）：WindowButton/DockMinimizedWindow 上报剥离 magnification/pushX/lifecycleScale/pressScale，用 rest 几何；shelf 开启时上报预测 slot rect；shelf 补 sceneOffset 依赖 | S-H2①、S-M3、S-M8 | 波峰点击最小化录屏比对 genie 终点 vs thumbnail；shelf 版 rectangle-tracking 测试 |
| T-20 | niri genie retarget：`set_rectangle` 对 active 动画更新 `target_rect`（shader uniform 平滑；同步重算 genie_area）——改造现有 handler，非新协议事件 | S-H2②、S-M7 | r16_genie_identity 基建补 retarget 用例；动画中拖动 dock 布局 genie 跟随 |
| T-21 | rect 上报帧同步：上报挂 polish/布局稳定后，slot Behavior 结束再 force 一次 | S-M7 | Behavior 途中触发 minimize 的错位消除走查 |

## 阶段 4：shell 质感修复（纯 QML 为主）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-22 | 岛退场字段 latch：通知/蓝牙/工作区场景仿 `latchedCompactMediaTitle` 冻结内容至 loader 卸载（或延迟 `clearTransientFields`） | S-M1 | 退场调长至 800ms 观察文字不闪成时钟 |
| T-23 | ControlCenter 展开重构：sibling 高度与 morph 同参动画（仅 in-flight enabled），或面板高度显式双状态单 Behavior | S-M2 | `content.implicitHeight` 单调性断言 + 录屏 |
| T-24 | Dock 波连续性：分隔带间隙归属最近段 + cursor 越界衰减；波端部 clamp 后单调性 pass；`resetDockHover` 不再瞬时 `contentX=0`（拖拽路径绝不重置） | S-M4、S-L9、S-M5 | 慢速扫过分隔线 scale 单调；20 图标溢出场景走查 |
| T-25 | 令牌治理：Dock 悬停标签统一 fadeFast；BusyStripe 接 reducedMotion 并入令牌；Launchpad/LeftSidebarSystem/LockScreen 硬编码时长入令牌；swipe 阈值/epsilon 单源化（消除 Motion.js 与 DynamicIslandMotion.js 双源） | S-M9、S-M10、S-L11、S-L12 | test_motion_token_convergence 扩展断言 |
| T-26 | 弹层边缘 case 包：morph 队列失败路径 radius/mask hold 共读结果；首条 toast 双入场去叠加；A→B 残影误关时间窗；Spotlight 重开高度 snap；restore 后 bounce/上报抑制 | S-L4~L8 | 各自条目所附走查/测试 |
| T-27 | layer 关闭动画补洞：quickshell 关窗前先 null commit；niri map 成功清残留 `unmap_snapshot` | S-L1 | 直接 destroy 的 layer 有关闭动画；快速重映射无陈旧快照 |
| T-28 | quickshell UI 线程阻塞点：colorquantizer `cancelAsync` 改完成信号+弃结果；bluetooth agent 同步 DBus 改 PendingCallWatcher | S-L2、S-L3 | 壁纸切换无掉帧尖峰；bluetoothd 挂起不冻结 UI |
| T-29 | UX/无障碍补齐：TopBar 键盘焦点模型（Keys/焦点指示器）；ControlCenter 面板级 Escape；亮度错误文本绑定 `brightnessErrorText`；PopupDismissLayer 滚轮/右键处理策略 | F-10~F-13 | 键盘可遍历 TopBar 入口；Esc 关面板；VM 下亮度不可用有解释 |

## 阶段 5：性能（先测后做）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-30 | **Profiling 基线采集**（研究报告第三部分计划）：tracy 四场景 + qmlprofiler + `QSG_RENDER_TIMER` + turbostat/intel_gpu_top，产出基线数据文档，确定 T-32~T-35 准入 | R 计划 | 基线数据入 docs；各候选项标注 通过/不通过门槛 |
| T-31 | queue_redraw_all 收敛（结构正确性，免门槛）：`Layout::take_dirty_outputs()` + do_action 尾统一 attribution；指针/光标 commit/DnD/grab 定向；真全局保留 `All{reason}` 可审计。Wallpaper `/proc` 轮询异步状态机化（免门槛零风险） | R-1、R-5 | per-output NoDamage 帧占比前后对比；R17 归因测试扩展；qmlprofiler 5s 尖峰消失 |
| T-32 | glass capture band 8px 量化 + 快速运动 downsample tier2（须过 T-30 门槛；严格超集捕获，禁止 rest-anchored 采样复辟——61138be 教训） | R-3 | `note_fb_effect_capture` 每秒次数 A/B；blur 边缘走查无差异 |
| T-33 | glass shader 法线场 LUT 烘焙（须过门槛） | R-4 | GPU span 前后对比；像素 diff 视觉等价 |
| T-34 | xray 元素更新短路 + quickshell per-region 脏标记 + ancestor 连接收敛（须过门槛） | R-2、R-6 | tracy 细分 span；region rebuild 计数 |
| T-35 | Island Loader 预热（active 提前，不翻 async）；Dock 指针波 FrameAnimation 节流（仅 profiling 证实热才做） | R-7、R-8 | 展开首帧时间；波动场景 JS 总量 |

## 阶段 6：架构收敛（长期，穿插进行但仍串行占位）

| 任务 | 内容 | 来源 | 验收 |
|---|---|---|---|
| T-36 | niri fork 分类收敛：23 个纯新增文件移入 `src/tahoe/`；挂钩点压缩 + `// TAHOE:` 标记；`FORK.md` 记录 (c) 类行为改动意图。移动是重构不是平行结构——路径迁移一次到位 | M-A② | 构建/测试全绿；`grep '// TAHOE:'` 可枚举全部挂钩点 |
| T-37 | quickshell rebase 演练（30 提交、低纠缠）验证季度 rebase 流程；随后排期 niri rebase + smithay bump + dependabot 清理 | M-A③、M-E | rebase 后测试全绿、部署走查 |
| T-38 | QML 巨石 reducer 化（逐个任务：Controls → ControlCenter → Dock），复制 DynamicIslandReducer 模式，QML 只留视图绑定 | M-C① | 每个迁移配 node vm 行为测试 + 对抗审查 |
| T-39 | Motion 令牌单源：`motion-tokens.json` 生成 Motion.js 与 KDL 期望值，convergence 测试改全量比对 | M-C② | 生成物 diff 逐行核对为零差异后切换 |
| T-40 | 部署原子化：`~/.local/lib/tahoe/<sha>/` + symlink 切换 + 回滚；arch-update.sh 拆 build/install/verify 三相 | M-D① | 模拟失败回滚演练；消灭"一行 cp"手工步骤 |
| T-41 | qmltestrunner 冒烟层（Dock/DynamicIsland 先行），文本合同测试降级为守护规则 | M-D② | 冒烟测试在 CI/本地脚本可跑 |

## 顺序说明

- 总顺序 T-01 → T-41 串行；阶段 6 的 T-36~T-41 可按窗口期插入到阶段 4/5 之间，但任一时刻仍只有一个任务在进行。
- 依赖关系：T-10~T-13 依赖 T-09；T-18 依赖 T-17；T-20 建议在 T-19 验证错位仍有残量后再做；T-32~T-35 依赖 T-30 门槛判定。
- verified-findings 第九节第 7 条（热拔/残留 grab/vblank 回归场景）并入 T-08 与 T-37 的回归网扩展，不单列。
