# P05 审查记录 — 变换动画下沉协议

> 2026-07-26。设计见同目录 `p05-design.md`。commit hash 见 roadmap 状态表。

## 实现落点

- **niri**(分支 tahoe-layer-animations,基于 P03 的 7b2ebd0e):
  - `resources/tahoe-glass-v1.xml`:manager/surface interface 1/3 → **4/4**(锁步,子对象继承 manager bound 版本);新增 `transform_curve` 枚举与 `set_transform` / `set_transform_target` / `set_region_morph` 三个 since=4 请求(双缓冲、每 commit 最后一个生效、仅表现层)。
  - `src/protocols/tahoe_glass.rs`:`VERSION=4`;`PresentationAffine`(clamp:平移 ±16384、scale [0.05,20])、`TahoeTransformCurve`(spring dr/st/eps | eased ms+bezier)、pending→directive 双缓冲(generation 门控、last-wins、epoch 单调);post-commit hook 内 region 提交先行、morph 在此捕获新旧 rect;controller destroy/claim 发布 identity 复位(含"空 region 但变换活跃"时也触发 redraw 的修正);首次 claim 不发布空复位。
  - `src/layer/transform_animation.rs`(新):`PresentationTransformAnimation` 复用 OpenAnimation 骨架——单进度 Animation(spring 不 clamp 允许过冲,lerp 钳 scale ≥0.01)驱动 from→to 仿射插值;重定向速度按最小二乘投影接力。
  - `src/layer/mapped.rs`:`presentation_transform`/`transform_animation`/`seen_transform_epoch`(map 时吸收 epoch 防 remap 重放);`advance_animations` 轮询指令+折叠完成态;`are_animations_ongoing` 计入(vblank 自动续帧,niri.rs 零改动);渲染统一 `WrapSpec`(scale/origin/offset)——纯 open 路径保持逐字节相同三元组,变换单独包裹,并存时 (S,C) 规范形合成一次包裹;`wrap_opening_render_element` 与 `wrap_render_element_with_transform` 合并为一(消重复);快照渲染不注入变换。
  - `src/layer/opening_layer.rs`:`wrap_with_transform` scale 泛化为 `Scale<f64>`(各向异性),删除孤儿 `wrap`。
- **quickshell**(分支 quickshell-tahoe-desktop,基于 1c03b80):
  - XML 字节一致拷贝;manager bind 1→4(Qt 自动 min);`TahoeGlassSurface` 增 5 个 wire 方法 + `supportsTransform()`(`*_SINCE_VERSION` 门,仿 hyprland surface 先例);
  - `TahoeGlass` attached:`transformAvailable` 属性 + `sendTransform*`(wire+立即 commit,无内容变化场景)+ `queueRegionMorph*`(pending,polish 时 setRegions 后发送并**跳过该帧显式 commit**,让 scenegraph 的新 buffer commit 原子携带 [内容+region+morph],避免旧 buffer 吃到变换的闪帧);destroy 路径清 pendingMorph。
- **tahoe-shell**:
  - 岛(DynamicIslandOverlay.qml):`compositorMorph` 门;retarget 三驱动在合成器模式下 snap 到目标 + `queueCompositorMorph()`(spring dr0.85/st160 = v2GeometrySpring 的 niri 等价;OSD/reduced/useSpring=false 走 eased OutCubic 同时长);swipe 拖动/settle 保留遗留管线;量化/settle 管线仅遗留路径使用。
  - Dock(Dock.qml):autohide 在 `compositorSlide` 下 `dockSlideOffset` snap(mask/P02 冻结门/状态即时落位),内容 Translate 与 label 几何改读 `dockContentSlideOffset`(合成器模式恒 0),region 恒 rest;`animateDockSlideTo` 发 `sendTransformTargetSpring(0,slide,1,1,dr1.0/st250)`/eased 190ms,已在目标时用 `sendTransform` 即时断言;`onCompositorSlideChanged` 双向重放恢复。
  - token 全部进 Motion.js(`compositorSpringSmooth`/`compositorEmphasizedDecelBezier`/`dockAutohideSlideEaseMs`)与 DynamicIslandMotion.js(`v2CompositorGeometrySpring`/`v2CompositorGeometryBezier`),换算注释与既有 Qt token 注释对齐。
- **guardrail**:`scripts/check-tahoe-glass-guardrails.sh` 版本钉子 1/3/1 → 4/4/4。

## 范围决策(修正路线图前提)

- **Dock"放大波"不迁移**:波是逐 icon 余弦场(每次 mousemove 重算 N 个 icon scale+pushX,SmoothedAnimation,刻意禁 Spring,玻璃 region rest-only 零参与)。per-surface 变换无法表达逐 icon 场;强迁会毁观感(违反铁律 5)。Dock 上与 P05 病理同构的现场是 **autohide 滑动**(有 ~60Hz glass commits 历史问题记录),已迁移。
- **glass region 随变换 = 冻结跟随**(路线图首选):client 静止期间 committed region 本身静态,无需 Arc 冻结;glass 元素与 surface 元素同包 `Relocate<Rescale<>>`。blur 行为如实记录:live 路径 blit 源随 dst(与现有 open/close 动画同级、小区域);settle 后静止由 P03 缓存接管;动画期残余 blur 是 P06 既定兜底范围。
- 岛 morph 中间帧从"逐帧真布局"变为"目标内容整体缩放"(macOS 容器变换式);端点/时长/弹簧参数不变。大跨度 morph 时圆角随各向异性缩放有透视变形,列为部署后观察项(备选:逐帧重映射模式)。
- 输入/命中不随表现变换(与 niri open/close 动画同语义):岛 mask、Dock mask 即时落到目标位。

## 验证

- niri:`cargo test --lib` 全量 **472 通过 0 失败**;**隔离可编译性实证**(P03 会话规定动作):临时 worktree(HEAD=7b2ebd0e)+ 仅本任务 6 文件 → 472 全过。cargo fmt 已跑。
- quickshell:build-tahoe 增量构建零警告零错误(树内仅本任务 6 文件改动,天然隔离);`tahoe-glass-tests` 全部通过(region diff / transform lifecycle / fallback alpha)。
- tahoe-shell:qmllint 前后诊断数一致(零新增);Motion.js/DynamicIslandMotion.js node --check 语法通过;guardrail 脚本全绿(24 PanelWindow/6 region/22 glass 文件检查)。
- 全局 animations off:经 `clock.set_complete_instantly`(niri.rs:1502/2551)自动直达终值,已核对 Animation::value_at/is_done 的 instant 检查路径。
- 新增单测:协议侧 6 个(陈旧 controller 变换写入拒绝、claim/clear 复位+epoch、双清幂等、affine clamp、rect 映射往返)+ 动画侧 4 个(端点、eased 0ms、过冲 scale 钳、平行重定向速度投影)。

## 对抗性审查(三独立子代理)

三路(协议/状态机、渲染/守护规则、客户端/QML)独立审查,发现按处置分列:

**已修复(审查驱动):**
1. **【高·三路收敛】map commit 携带的变换指令被吞**:smithay post-commit hook 先于 `CompositorHandler::commit` 执行,`MappedLayer::new` 原实现吸收当前 epoch 会把 mapping commit(或 pre-map commit)原子携带的指令当旧指令丢弃——Dock 冷启动/退全屏重建即隐藏的流程直接失效(可见"幽灵 Dock" + mask 已收缩的点击穿透)。修复:new 从 epoch 0 起步不吸收;防重放改由 unmap 时 `clear_transform_directive_on_unmap` 清除已发布指令承担(两处 unmap 路径均接入)。
2. **【中】open 与变换并存时合成顺序**:原 transform inner/open outer 会让协议位移被 open scale 缩放(隐藏 Dock 在 open 动画期露边)。修复:调换为 open inner/transform outer,协议变换在最终呈现中精确成立;附单测。
3. **【中】claim 复位变换但 region 为空时不排 redraw**(自查先行发现,与 destroy 路径修复对称):陈旧变换会留屏至下次任意损伤。修复:claim/clear 双路径都把"变换被复位"纳入 redraw 判定;首次 claim(从未发布过指令)不再发布空复位。
4. **【中】DockMinimizedShelf 漏改一行**:仍传 snap 的 `dockSlideOffset`,最小化恢复矩形在隐藏态上浮 96px(genie 飞向半空)。修复:改传 `dockContentSlideOffset`。
5. **【中】岛 morph 期输入 mask 跳终态**(复辟历史 bug"collapse leave visible chrome unclickable"):修复:morph 窗口内 mask 取 old∪new 并集保持 `v2CompositorMorphMaskHoldMs` 后落到目标;零逐帧流量。〔勘误(P05 收尾会话):原定 420ms 并未"覆盖 spring 全部时长"——dr .85/st 160/eps .003 的包络收敛 = −ln(ε)/(ζ·√k) ≈ 540ms(与 niri spring.rs `duration()` 同式),420ms 到期残余 ~1.1%、最大 collapse 尾段 ~120ms 有 2–4px mask 缺口;已提至 **560ms**(niri spring.rs 对 underdamped 直接返回包络式,540.3ms 即精确收敛时长;560 到期包络残余 0.24%、含 1/√(1−ζ²) 振幅因子 ~0.46% ≈ 0.95px,亚像素),见下文「收尾追记」。〕
6. **【中】swipe 起手不取消在途变换**(拖动内容叠残余仿射畸变):修复:`onSwipeInteractiveChanged` 在 compositor 模式下发 `sendTransform(0,0,1,1)` 即时取消。
7. **【低】morph 随 region 延迟校验被丢**:region 因 surface_geo 未就绪延迟提交时,morph 现随之保留 pending,与 region 在同一 commit 落地。
8. **【低】曲线参数可构造 ~115s 常亮重绘**:下限收紧(dr≥0.2、stiffness≥10、eased≤10s),settle 包络钳到秒级。
9. **【低】XML 承诺 eased 速度接力与实现不符**:措辞修正(spring 接力、eased 从当前值重启)。
10. 卫生:`setAvailable` 两信号先落状态再发射(一致快照);prev-swap 清理 `pendingMorph`;新增 compose 等价单测。

**审查判为不成立/已兜住(有实证):**
- "隐藏 Dock 输入幽灵带":不成立——shell `mask` 即 wl 输入区域,snap 后立即收缩到 reveal 条(渲染审查者仅看 niri 侧,缺 shell mask 语义)。
- 隐藏稳态 glass 常驻 enabled:niri 侧统一包裹后离屏元素走标准 damage 剔除,稳态零重绘零 blur 成本;回落 legacy 后原 `dockGlassActive` 闩恢复,自洽。
- NaN/undefined 参数:wl_fixed wire 上不可能出现 NaN;服务端全参数 clamp,无崩溃路径。
- 纯 open 渲染路径与重构前逐字节等价(`Scale::from` 语义、变体臂、shadow 剥离、moving_surface_rect 数学逐项核对);R16 稳定 identity 由包裹层转发内层 id/commit 保证,稳态零逐帧重绘;advance→redraw 时序保证 morph 首帧带 from 仿射不闪。
- 版本协商:老 client(v1)/新 server、新 client/老 server 双向安全;v1 对象上伪造 since=4 请求由 wayland-backend 以 InvalidMethod 杀 client,不 panic。
- **玻璃 region 禁弹簧守护专项(三路一致)**:spring 仅作用渲染包裹;pending/committed region 与 validate_regions 在变换全路径零写入;过冲越界经 damage 裁剪/离屏剔除/blur blit clamp(framebuffer_effect.rs:207-215)兜底。

**接受并记录(设计内取舍):**
- 单刷新周期两条指令仅最后一条生效(协议 last-wins 层语义);radius-only 状态切换在 compositor 模式瞬跳(现场几乎不存在);Dock 滑动期 mask 即时落位(hide 方向指针已离开、reveal 方向提前可点属收益);展开内容首帧被 from 仿射各向异性压缩、由 170ms 内容 crossfade 遮掩(容器变换固有观感,验收时留意);morph 假设 layer surface 自身位置/尺寸同 commit 不变(固定尺寸 overlay 成立,已注释)。

## 部署

按 P02/P03 先例:commit+push 后待用户窗口期部署(`FORCE_QUICKSHELL_BUILD=true bash scripts/arch-update.sh` + niri 重启),验收数据(岛 morph / Dock autohide 期 client commit 计数与 blur pass 观测,`NIRI_LIFECYCLE_DIAG=1`)部署后补录于本文档附录。

## 收尾追记(2026-07-26 晚,P01–P06 完成度核查会话)

- **测试债清偿**:P05 会话遗留 3 个仍锁旧 mask 契约(逐帧 islandAnimated*)的红测试
  (test_dynamic_island_expand_morph / _public_contracts / _v2_surface),已改写为锁
  新契约:mask 读 maskWidth/maskHeight(hold 期 old∪new 并集、非 hold 期恒等
  islandAnimated* 即 legacy 语义)、禁 capsuleTarget*/screenWidth、holdMorphMask
  捕获先于双驱动 snap 的顺序锁、restart() 布防锁、repeat: false 锁、Timer 块作用域
  锁。经两独立子代理对抗性审查 PASS + token 增量定向复核 PASS(变异注入首轮 7/10
  捕获;按审查建议加固后独立复核 13/14 转红,唯一残余 repeat 变异随 repeat: false
  锁补齐)。
- **hold 时长勘误**:420→560ms(上文 #5 勘误);代价为 mask 超集窗口延长 140ms
  (方向安全:painted ⊆ mask),历史 bug 类缺口(尾段 2–4px)清零。
- **部署已落地(2026-07-26 20:52 会话重启)**:运行栈 = niri 9ce7a720 + quickshell
  e8c1acb + 当批 KDL/QML(逐字节核验)。**例外**:本追记的 560ms token(外层
  846fbce,仅 Motion.js 一文件、无 KDL 耦合)晚于该批部署,线上仍为 420ms——
  权限分类器拦截线上目录写入,待用户执行
  `cp tahoe-shell/components/DynamicIslandMotion.js ~/.config/quickshell/tahoe/components/`
  (quickshell 热重载即生效)或随下批全量 rsync。`NIRI_LIFECYCLE_DIAG` 未随本次
  启动设置,岛 morph / Dock autohide 期 client commit 计数与 blur pass 的定量验收
  顺延 P08(与 P03/P06 的 diag 复测同窗口);大跨度岛 morph 圆角各向异性变形维持
  观察项。
