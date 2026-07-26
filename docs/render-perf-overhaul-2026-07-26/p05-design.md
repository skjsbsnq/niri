# P05 设计定稿 — 变换动画下沉协议（set_transform_target）

> 2026-07-26。实现前定稿,供实现与对抗性审查对照。基于四路侦察(协议/层动画骨架/quickshell 客户端/tahoe-shell 现场)。

## 侦察对路线图前提的修正

1. **Dock"放大波"不能用 per-surface 变换表达**:波是逐 icon 余弦场(`computeSectionWave`,peak 1.62,每次 mousemove 重算全部 icon 的 scale+pushX,SmoothedAnimation 平滑且刻意禁 Spring——Dock.qml:297 注释)。玻璃 region 在波期间零参与(rest-only 硬规则,Dock.qml:110-112)。把波改成整 surface 变换会毁掉逐 icon 观感,违反铁律 5。**决策:波保持 client 侧;Dock 侧真正迁移的是 autohide 滑动**(每帧 region y/height 脏 + 内容 Translate,有 ~60Hz glass commits 历史问题记录,Dock.qml:281-283)——这是 Dock 上与 P05 病理(动画期每帧 buffer+region+blur)同构的现场。
2. **动态岛形变是各向异性**(compact 112w→expanded 432w,高度独立变化),协议必须携带 scale_x/scale_y;smithay `RescaleRenderElement` 原生接受 `Scale<f64>`。
3. **必须同时支持 spring 与 easing**:岛几何 spring(useSpring 门控)/eased 双分支、OSD 强制 80ms eased、reducedMotion 80ms、Dock autohide springSmooth/190ms eased。只做 spring 会破坏现有降级路径(铁律 5)。
4. **中途重定向问题**:morph 进行中再换态,client 无法得知合成器当前动画位置(无反馈事件)。from 仿射必须由服务端算 → 需要 region 锚定的 `set_region_morph` 请求(旧 rect 当前视觉足迹 → 新 rect 的映射由合成器在应用瞬间计算,天然带速度接力)。
5. **版本协商**:manager interface 与 surface interface 一起升到 4(对齐);`const VERSION: u32 = 4`。tahoe_glass.rs:19-24 注释解释过 global 版本受 manager interface XML 上限约束。guardrail 脚本钉死值(1/3/1)同步更新为 4/4/4。

## 协议扩展(tahoe-glass-v1.xml,双仓字节一致)

`tahoe_glass_surface_v1` v4,新增(全部 since="4",双缓冲、随 wl_surface commit 应用、每 commit 最后一个生效、仅表现层——不影响输入/布局;合成器当前只对 layer-shell surface 生效):

- `set_transform(x, y, scale_x, scale_y)`(fixed×4):commit 时立即设置表现变换(取消进行中的变换动画)。(0,0,1,1) 即清除。
- `set_transform_target(x, y, scale_x, scale_y, curve: uint, p1..p5: fixed)`:从当前表现变换(含速度接力)动画到目标。
- `set_region_morph(region_id: uint, curve: uint, p1..p5: fixed)`:region 锚定容器形变——本次 commit 使 region_id 的 rect 从 R_old 变为 R_new 时,从 [R_new → P_now(R_old) 视觉足迹] 的仿射出发动画回 identity。region 不存在/rect 未变则丢弃(debug log)。
- enum `transform_curve { spring=0, eased=1 }`;spring: p1=damping_ratio, p2=stiffness, p3=epsilon(进度空间), p4/p5 保留;eased: p1=duration_ms, p2..p5=cubic-bezier x1,y1,x2,y2。
- 校验:scale 夹取 [0.05, 20],平移夹取 ±16384;非法丢弃+log(与 set_region 一致,不 post error)。

## niri 侧

- **协议状态**(protocols/tahoe_glass.rs):`TahoeGlassSurfaceInner` 增 `pending_transform`(last-wins,controller generation 门控)+ `transform_directive: Option<(epoch, directive)>`。post-commit hook 解析(morph 在此捕获 old/new region rect)、epoch+1、并入 redraw 触发条件。claim/clear 时发布 Set(identity) 指令复位视觉。
- **动画**(新文件 src/layer/transform_animation.rs,复用 OpenAnimation 骨架):`PresentationTransformAnimation { progress: Animation(0→1 spring|bezier), from: Affine, to: Affine }`,lerp 求当前仿射;重定向时进度速度按最小二乘投影接力(`Animation::restarted` 语义)。全局 animations off 经 `clock.should_complete_instantly()` 自动直达终值。
- **MappedLayer**:`presentation_transform`(稳态)+ `transform_animation` + `seen_transform_epoch`(构造时吸收当前 epoch,防 remap 重放旧指令)。`advance_animations()` 轮询指令(每循环一次 mutex+u64 比较,~26 层可忽略)并折叠已完成动画;`are_animations_ongoing()` 计入 → vblank 自动续帧(niri.rs 零改动)。
- **渲染(冻结跟随模式,路线图首选)**:client 静止期间 committed region 本身就是静态的,无需 Arc 冻结;把 [surface 元素 + glass 元素 + shadow] 统一包 `Relocate<Rescale<>>`(现成 `Opening*` variant,**零新增枚举 variant**)。`opening_layer::wrap_with_transform` 的 scale 参数 f64 → `Scale<f64>`。open 动画与表现变换并存时按 (S,C) 规范形合成一次包裹(纯 open 路径保持今日逐字节相同的三元组,避免 open 回归)。快照渲染(store_unmap_snapshot)不注入表现变换。
- **blur 行为(如实记录)**:live 路径 blit 源随 dst 走(mapped.rs:982-996 draw_clip 契约)——动画期 blur 与现有 open/close 动画同级(每帧、小区域);settle 后静止 → P03 缓存接管;xray 路径 xray_pos 不随变换调整 = 冻结源采样。"blur 不随变换每帧重算"的完整兑现由 P03(静止缓存)+ 本任务(client 不再逐帧改 region 几何触发全量重算)共同构成;动画期残余 blur 是 P06 的既定兜底范围。
- **R16**:包裹层转发内层稳定 Id/CommitCounter;每帧仅栈上包裹结构,零堆分配。
- 已知边角(注释记录):close 发生在变换动画中途时快照从 rest 状态出发(常驻 overlay 实际不 unmap);输入命中不随表现变换(与 open/close 动画同语义)。

## quickshell 侧

- XML 字节一致拷贝;manager bind 1→4(Qt 自动 min(server, 4))。
- `TahoeGlassSurface` 增 wire 方法(`version() >= *_SINCE_VERSION` 门控,仿 hyprland/surface/surface.cpp:33-37)。
- QML attached `TahoeGlass` 增:`transformAvailable`;`sendTransform/sendTransformTargetSpring/sendTransformTargetEased`(wire+立即 commit,Dock autohide 用,无内容变化);`queueRegionMorphSpring/Eased`(记 pending,onWindowPolished 里 setRegions 后发 wire 并**跳过该帧显式 commit**,让 scenegraph 的新 buffer commit 原子携带 [新内容+新 region+morph]——避免旧 buffer 提前吃到变换的闪帧)。
- 协议 <4 时全部方法 no-op 返回 false,`transformAvailable=false` → shell 走遗留管线(版本协商,非平行接口)。

## tahoe-shell 侧

- **岛**(DynamicIslandOverlay.qml):`transformAvailable` 时 retarget 直接把 driver snap 到目标(内容一次 relayout、region 一次精确提交)+ `queueRegionMorph`(曲线选择完整镜像现有门:geometrySpringEnabled→spring(dr .85/st 160);否则 eased(240/280ms OutCubic);OSD 80ms;reduced 80ms——参数放 DynamicIslandMotion.js,遵守 token 红线)。mediaExpandProgress 从 snap 后高度自然跳到终值(内容中间态由合成器 scale 替代,端点/时长/曲线不变)。swipe 拖动与 settle 保留遗留管线(交互逐帧跟指针,不适合 fire-and-forget 目标)。量化/settle 管线(protocolCapsule*)仅遗留路径使用。
- **Dock**(Dock.qml):autohide 在 `transformAvailable` 时 slide offset 恒 0(内容/region 保持 rest),隐藏/显示改发 `sendTransformTargetSpring(0, slidePx, 1, 1, dr 1.0/st 250)` 或 eased 190ms(useSpring/reducedMotion 门保留);启动即隐藏用 `sendTransform` 免动画。放大波不动。
- Motion.js 换算注释已给:v2GeometrySpring(2.5/0.28)=springPanel=niri dr 0.85/st 160;springSmooth=dr 1.0/st 250。

## 验收口径

- 岛 morph / Dock autohide 动画期:client 零 buffer 重提交、零 region wire 流量(岛内容 crossfade 的 ≤170ms 小面积重绘除外,属内容动画,协议不覆盖)。
- 弹簧手感:合成器 spring 参数 = Motion.js 注释给出的等价 dr/st;eased 路径逐 site 时长曲线一致。
- 玻璃 region 禁弹簧守护:弹簧作用于表现变换,协议 region 几何全程静态,不经过 validate_regions 超界路径;审查专项确认。
