# R08 · 灵动岛几何手感 + OSD 进场（点名④b）验收记录

日期：2026-07-18
覆盖问题：#21 #22 #23 + 用户实测 bug（媒体播放态开/关与来通知时"灵动岛底部白条一闪"）

## 用户白条 bug 根因（本任务修复的核心现象）

旧管线 `quantizeProtocolGeometry(value, 8)` 用 **round-to-nearest**：收起目标高 36px（resting_media，媒体播放态的常驻高度）在动画尾段 h∈[36,40) 全程被抬到 region=40 —— 玻璃 region 比绘制胶囊**底边多出 ≤4px**。岛的绘制 fill 是近不透明深色（#cc10141a），多出的 region 是**裸玻璃材质**（模糊+高光边）＝亮色横条；settle 判定（<0.01）翻真瞬间 region 40→36 跳变，亮条"弹走"＝一闪。高度锚定在顶部，全部量化误差落在底边，故白条只出现在底部。收起到时钟（32，8 的倍数）无此尾段，因此 bug 只在媒体播放态显形——与用户描述完全吻合（打开同理：h 从 36 起步即刻被抬到 40）。通知（60/80→36 收回）同一机制。

**修法（结构性消灭而非调参）**：宽/高量化改 **floor**（region 永不超出绘制面，欠覆盖 ≤2px 藏在深色 fill 下不可见）、半径改 **ceil** 并按提交尺寸再钳（玻璃圆角内缩于绘制圆角）；settled 快照只会把 region 向绘制边内侧补齐，无可见跳变。

## 实施摘要

1. **#21 弹簧驱动+钳制管线**（二选一：**选弹簧**，OutBack 回退未启用——若宿主手感不达预期，改 `IslandMotion.v2GeometrySpring` 一处即可换参/换 OutBack）：
   - 新驱动属性 `islandDriverWidth/Height/Radius`，由 standalone `SpringAnimation`（宽/高，`Motion.springBouncy`——该 token 注释本就写明 "dynamic island morph"）/ `NumberAnimation`（半径恒 eased，避免圆角呼吸）imperative 驱动（对齐 R01 established 双分支模式）。
   - `islandSurface` 几何绑定 `clamp(driver)`：宽 ∈ [2, maxCapsuleWidth]，高 ∈ [2, driverHeightMax]（**新增硬界** `min(maxCapsuleHeight, 窗高-顶缩进)=216`，堵住旧 maxCapsuleHeight=220 + regionY=4 > 窗高 220 的越界口子），半径逐帧 ≤ min(动画宽, 动画高)/2（spring undershoot 下圆角恒有效）。
   - `x` 改为由动画宽**派生**（`(screenWidth-width)/2`）——spring/swipe 下居中零漂移，删除 x/width 双 Behavior 同步问题。
   - 门控：`geometrySpringEnabled(settings, useSpring)` = useSpring && !reduced；swipe 拖拽 1:1 直赋、settle 走 swipeSettle token；eased 回退保留 240/280/240 时长词汇。
   - islandSurface 几何通道上 **零 Behavior 残留**（全部动效在驱动层）；`Behavior on fillColor/opacity` 保留。
2. **#22 量化降级**：8→2px（宽高，floor）、4→2（半径，ceil+钳）；settle 判定 0.01→0.6（> spring epsilon 0.25，锁存稳定）。
3. **#23 OSD 进场**：`v2OsdEnterMs` 0→80；`osdImmediateGeometry` 不再整体 disable Behavior（该机制已删），只作用于时长选择（进场 80ms eased 快展开，**无 spring**——硬件反馈不弹跳）；OSD→OSD 连续 tick 目标不变自然不重动画；退场经 `finishOsdExit`→`clearTransientFields`（**先清 flag 再 recomputePresentation**，读源码核实顺序）走正常 collapse。OSD 数值/进度条首帧即显语义不变（`syncOsdLayerImmediately` 瞬时置 1，未触碰）。
4. **治理文档**：tahoe-material-governance.md DynamicIsland 行改述 R08 管线（"禁止 Spring 直接驱动 region 通道"），对应测试断言同步。

## guardrail 论证（region 永不越界）

- 提交链：`SpringAnimation → islandDriver*（可过冲）→ clamp → islandSurface 几何 → floor/ceil 量化 → region*`。region 通道本身无任何动画对象，值恒 ∈ [2, maxCapsuleWidth]×[2, 216]，regionY=4 固定 → region ⊆ layer surface（220 高、全屏宽）在一切过冲/欠冲/启动（height=0 时 fallback implicitHeight=220）情形下成立。
- 红线条文对齐：GlassPanel x/y/width/height/radius 与 region* 上无 SpringAnimation（弹簧 target 均为 root 驱动属性）；弹簧全部在 useSpring 门控后；02-plan R08 规格明文以"clamp 后提交、region 永不越界"为该红线在本任务的实现形式。
- **加固（采纳 R08 审查可选建议）**：`capsuleTargetHeight` 现也 clamp 到 `driverHeightMax`（原仅 clamp 到 maxCapsuleHeight=220，而 driverHeightMax=min(maxCapsuleHeight,216)）。消除隐患：未来若新增/上调某设计态高度 >216，旧写法会 capsuleTargetHeight>driverHeightMax → painted 被钳在 target 下 → settled 永不 latch → 持久 region 缺口。现 target 与 painted 同界，settled 恒可达。当前设计态最高 176，本加固对现状零行为变化，纯防御。

## 量化预算数据（#22 要求）

模拟（OutCubic，expand 224→418/36→166/18→30 @280ms；collapse 反向 @240ms）区分商数变化次数：

| 刷新率 | expand 旧(8px) | expand 新(2px floor) | collapse 旧 | collapse 新 |
| --- | --- | --- | --- | --- |
| 60Hz | 13 | 14 | 11 | 12 |
| 240Hz | 33 | 49 | 29 | 41 |

60Hz 基本持平；240Hz +~45%（每次 morph 多 ~1x 十几次 commit，仍远低于弹窗面板高度动画的逐帧 commit 既有接受水平——R04 起弹窗高度 Behavior 无量化直喂 region）。**折中开关**：若宿主实测掉帧，`v2ProtocolSizeQuantumPx` 2→4 一处可调（floor 语义不变，白条修复不受影响）。嵌套会话启动 commit 计数 19（R00 基线 17，同量级）。

## 测试

- 全量 `pytest tests/ -q` → **766 passed, 217 subtests passed in 29.30s**（基线 764 + 新增 2：floor 量化不越绘制面/白条回归样例、OSD 80ms 进场）。
- 更新：test_dynamic_island_v2_surface.py（quantize floor/ceil + 2px token、commit 模拟改 OutCubic 减速尾、no-spring 改"驱动弹簧仅 2 处+几何通道零 Behavior+clamp 绑定"、治理行断言）、test_dynamic_island_v2_motion.py（geometryEaseDurationMs/驱动 dispatch/spring 门控、新增 OSD 80ms 测试）、test_dynamic_island_osd_scene.py（v2OsdEnterMs 80 + 更名 fast_eased）、test_motion_token_convergence.py 与 test_dynamic_island_runtime_hardening.py（SpringAnimation 计数 0→2 + 新哨兵注释）。
- `scripts/check-tahoe-glass-guardrails.sh` → passed（24/4/22 + Phase 5 检查全过）。
- 嵌套冒烟：`NIRI_MODE=nested TAHOE_CONFIG_DIR=<worktree> run-tahoe-session.sh`（25s）→ 工作树 shell 加载、19 次 TahoeGlass commit、无 QML TypeError/ReferenceError/binding loop、SIGTERM 干净退出（/tmp/r08-nested-smoke.log）。

## 审查

- R07 遗留独立审查（acceptance 待补项）：本任务开始前补跑，结论见 R07 acceptance 追记（含 FINDING 1 高危：swipeOffsetX 复用不复位，另立 R07 follow-up 修复）。
- R08 独立 agent 审查：**总结论 CLEAN，0 阻断 finding**，a–i 九项全 PASS（region 有界性构造性满足、白条 4px 持久条彻底消除、双驱动零残留、swipe 等价、OSD 进出场时序均核实、全回退/生命周期/范围均 PASS；实跑 island+motion 共 368 passed）。3 条低危/信息级观察处置：
  1. settled 快照 ≤0.6px 瞬态越界——注释措辞已按建议弱化为"sub-pixel against dark fill"（本提交已改）。
  2. settle 振荡穿越阈值 settled 短暂翻转、region 抖动 <1~2px 数 ms——收敛稳定且绘制面本身正回弹，相对不可察，不改。
  3. services/DynamicIsland.qml:875-876 注释过时（提"zero-duration/QML Behavior"，实 80ms 且已无 Behavior）——**范围外**（本任务未改该 service 文件），留待其所属任务顺手更新；其保证的"先 flag 后 forcedState"顺序在新管线下仍正确。
  + 可选加固已采纳：capsuleTargetHeight 也 clamp 到 driverHeightMax（见上 guardrail 论证）。

## 已知余项（不阻塞）

- settled 快照与 spring 静止点最大偏差 0.6px（region 与绘制边亚像素级差，深色 fill 下不可见；旧管线为 4px 亮条）。
- 宿主手测矩阵（弹簧手感二选一终判、240Hz 实测掉帧、useSpring=false VM 路径、reduced profile）：待用户宿主验收；spring 参数/量化 quantum 均为单点 token 可调。
- R07 acceptance 的宿主手测矩阵待补项继续有效（本任务未覆盖）。
