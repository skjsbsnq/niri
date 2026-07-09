# 02 · 规则文件：升级期间的红线、许可、防腐化与性能预算

日期：2026-07-09
效力：本轮升级（T00–T23）期间对所有改动生效。与 `tahoe-shell/docs/tahoe-motion-default-policy.md`、`tahoe-shell/docs/tahoe-material-governance.md` 冲突时，**以旧治理文档为准**——本文件是其扩展，不推翻其中任何条款。

---

## 0. 一页速查

| 类别 | 一句话 |
| --- | --- |
| 流程 | 严格串行：一任务 → 全部代码完成 → 验收 → 一提交 → **push 成功**，然后才准开下一个（执行协议见 04-goals.md） |
| 弹簧 | 内容 transform 可弹簧；**玻璃 region 几何绝对禁止弹簧/过冲** |
| 接口 | 只复用、只收敛；发现重复实现先合并，禁止再造平行接口 |
| 配置 | KDL 只经 `niri_settings_tool.py` 写；motion/theme token 只扩展既有文件 |
| 性能 | 动画属性优先 transform/opacity；克隆层用完即毁；RSS 涨幅 >5% 必须解释 |
| 幅度 | 表现层可以推倒重做；服务层/数据流/接口边界不许另起炉灶 |

---

## 1. 流程门禁（怎么做事）

1. **严格串行**：路线图任务按编号执行，上一任务未达到 DONE（全部代码完成 + 验收通过 + commit + push 成功，判定标准与 push 细则见 04-goals.md §3/§5）前，不得开始下一任务的任何代码改动。研究/阅读下一任务的代码不受限。
2. **一任务一提交一推送**：每个任务恰好一个 git 提交（允许任务内多次 WIP，最终 squash 成一个），提交信息以 `Txx:` 开头，验收通过后必须 push 成功（父仓 origin/main；niri 子模块先推 `tahoe-layer-animations`，见 04-goals.md §5.2）。必须可用 `git revert` 单独回滚。
3. **验收记录**：每任务完成后在 `docs/motion-visual-overhaul-2026-07-09/acceptance/Txx-<slug>-<日期>.md` 写验收记录（跑了哪些命令、手测矩阵结果、性能数据、已知残留）。
4. **失败处理**：验收不过 → 修复后重验；无法当场修复 → revert 该任务提交，任务标记 blocked，**不得带病进入下一任务**。
5. **禁止顺手改**：任务范围外的文件即使看到问题也不改，记入 `acceptance/` 记录的"发现待办"段，由后续任务或路线图修订承接。
6. 治理测试同步：改 `Motion.js`、材质常量、edge-reveal 语义时，`tahoe-shell/tests/` 里对应的治理测试（`test_motion_token_convergence.py`、`test_motion_default_policy.py`、`test_tahoe_material_governance.py`、`test_edge_reveal_semantics.py`、`test_memory_allocation_governance.py`）必须在**同一提交**内更新并通过——测试是规则的机器化形态，不允许"先改代码后补测试"跨任务。

---

## 2. 红线：绝对不能做

每条附依据。违反任何一条 = 验收直接不通过。

1. **玻璃 region 几何禁弹簧/过冲**：`GlassPanel` 的 x/y/width/height/region* 以及任何喂给 `TahoeGlassRegion` 的几何，禁止 SpringAnimation、禁止会过冲的曲线。过冲会把 region 推出 surface，niri 拒绝该 region 且伴随纹理损坏（guardrail 0704ea4；`ControlCenter.qml:194-199`、`NotificationToast.qml:104-141` 注释均有记载）。面板高度/位置动画只准用无过冲 easing（emphasized-decel 等）。弹簧只准用于：① 玻璃面板**内部**的内容 transform/opacity；② compositor 侧动画（niri 自己裁剪）；③ 非玻璃元素。
2. **不得绕过 `useSpring` 门控**（`shell.qml:66-70`）：QML 里新增的每一处 SpringAnimation Behavior 必须写成 spring/NumberAnimation 双分支（参照 `Dock.qml:669-697` 既有模式），VMware/软渲染路径必须始终可用。
3. **QML 不直写 KDL**：niri 配置写入只准经 `tahoe-shell/services/niri_settings_tool.py`（经 NiriSettings 服务）。源头文件是 `config/niri/tahoe-phase0.kdl` 的 `tahoe-managed` 区块，靠 `scripts/arch-update.sh` 部署（policy doc "Maintenance Rules"）。
4. **不新建第二套 token 文件**：motion token 只准扩展 `Motion.js`；玻璃/圆角常量只准扩展 `TahoeGlass.js`；颜色 token 收编进共享主题库时必须是**收编**（各组件逐步迁入），不是并存第二套（policy doc："Do not introduce a profile JSON file or component-private motion token file"）。
5. **profile 三方同步**：动 motion profile（名称/数值/新增 profile）时，`Motion.js`、`niri_settings_tool.py`、`DesktopSettings.qml` 源默认值三处 + policy 文档必须同一提交更新（policy doc "Maintenance Rules"）；`balanced` 必须保持字节级回滚基线地位。
6. **不删 fallback**：QML outer open/close 动画 fallback、`BackgroundEffect.blurRegion` 玻璃 fallback、`WindowPreviewFallback`、`reduced` profile、genie 的无矩形/跨输出/shader 失败三级 fallback——全部保留（policy doc "Fallback Retention Plan"；genie acceptance doc :21-26）。移除任何 fallback 需要单独立项 + 实机证据 + 回滚方案，不在本轮范围。
7. **不引入新 UI 依赖**：不引入 QtQuick.Controls（项目从未使用，`ControlCenter.qml:653-654` 注释明示）、不引入 MD3 token、不引入 Lottie/运行时 SVG 渲染依赖（`LeftSidebarSystem.qml:16-18` 既有约定）。图标用预渲染 PNG 资产。
8. **compositor 曲线单调性**：新增命名曲线必须加入 `niri/src/animation/mod.rs:398-426` 的单调性/有限性测试；x 控制点非单调的曲线（`menu-decel`、`stall` 一类）禁止用于 compositor 通道。
9. **不动 quickshell C++**（`quickshell/` 子仓）——本轮所有任务在 tahoe-shell QML、KDL、niri fork Rust 内完成；若确需 quickshell 改动，先修订路线图立项。
10. **不破坏现有功能与用户入口**（沿用 2026-07-03 反腐化路线图总约束）：所有既有 IPC 函数（`shell.qml:514-605`）、快捷键、设置项、弹窗行为在每个任务验收时必须仍然可用。
11. **Launchpad 保持 QML 动画路径**：不迁移到 compositor layer 动画（compositor 缩放使图标发虚，`Launchpad.qml:36-38` 记载的既有决策）。

---

## 3. 防腐化条例：禁止平行接口，优先复用

### 3.1 必须复用的既有接口清单

新代码遇到下列需求时，**必须**使用对应既有接口；发现接口能力不足时，扩展该接口本身，不得旁路：

| 需求 | 唯一入口 | 位置 |
| --- | --- | --- |
| 弹窗开关/互斥协调 | `ShellPopupState` + `shell.closeTopBarPopups()`/`toggleTopBarPopup()` | `components/ShellPopupState.qml`、`shell.qml:114-452` |
| 弹窗定位 | `PopupGeometry.js`（popupLeft/popupTop/originX） | `components/PopupGeometry.js` |
| 点外关闭 | `PopupDismissLayer` | `components/PopupDismissLayer.qml` |
| 锚点矩形 | `anchorRectFor(item)` 模式 | `TopBar.qml:84-95`、`Dock.qml:207-221` |
| 玻璃面板 | `GlassPanel` + `TahoeGlass.js` 材质常量 | `components/GlassPanel.qml` |
| 动效时长/曲线/弹簧参数 | `Motion.js`（本轮扩展它） | `components/Motion.js` |
| 图标资产路径 | `appsService.iconPath(dir, name)` / `iconForApp` | `services/Apps.qml` |
| 窗口操作/事件流 | `Windows.qml`（activate/minimize/restore/setRectangle） | `services/Windows.qml` |
| 窗口缩略图 | `ThumbnailProvider`（队列/缓存/失败态） | `services/ThumbnailProvider.qml` |
| 外部命令 | `CommandRunner` | `services/CommandRunner.qml` |
| shell 持久状态 | `DesktopSettings` 的 JsonAdapter 加字段 | `services/DesktopSettings.qml` |
| 设置页面注册 | `SettingsModel.js` 注册表 | `components/settings/SettingsModel.js` |
| genie 目标矩形 | foreign-toplevel `setRectangle` 链路 | `Windows.qml` → niri fork |
| niri 动画配置节点 | 既有 `Animation` 节点解码模式（spring/duration-ms/curve） | `niri-config/src/animations.rs:1150-1272` |

### 3.2 平行实现判例（见到就合并，不得新增）

- 6 个菜单组件各自内联一份 MenuRow（MenuPopup/AppMenuPopup/TrayMenu/DockAppMenu/DockWindowMenu/ProcessMenu）→ T06 合并为一个共享组件后，**此后任何菜单必须用它**。
- hover 标签胶囊在 `Dock.qml` 内出现 3 份近似实现（:535、:832、:908）→ Dock 任务内合并。
- 颜色 token 在各组件重复定义（textPrimary/cardFill 等在 LeftSidebar/ControlCenter/TopBar/Settings 各写一套）→ T14 收编为共享库后逐组件迁入。
- 新组件 API 必须沿用既有命名约定：`open/anchorRect/settingsService/darkMode/closeRequested()`，不得发明同义新名。

### 3.3 "大刀阔斧"的边界

- **可以推倒重做**：组件内部结构、视觉参数、动画实现、布局（如 Launchpad 全屏化、侧边栏 widget 化、设置页面重排）。
- **不可以另起炉灶**：服务层数据流、IPC 面、弹窗协调机制、配置写入链路、玻璃 region 协议。这些只许复用与收敛。
- 重构与重写的判据：对外接口（signal/property 名、IPC 函数、KDL 节点语义）不变或纯增量 = 允许；需要调用方跟着改名/换协议 = 先在路线图立项说明。

---

## 4. 性能与内存预算

1. **动画属性优先级**：优先动 transform（translate/scale/rotation）与 opacity；驱动 width/height/anchors 的动画仅限面板级少数场景（CC morph、Spotlight 高度），且用无过冲 easing。
2. **禁止每帧 JS 轮询**：动画一律走 Behavior/Animation/SpringAnimation 框架；不得用 <100ms 间隔 Timer 驱动动画帧。现有各服务 Timer 频率（SystemStats fast 1s / medium 2s 等）不得加密。
3. **Image 纪律**：所有新增 Image 必须设 `sourceSize`（图标 ≤128）+ `asynchronous: true`；缩略图保持 `cache: false`；不加载超过显示尺寸 2× 的位图。
4. **克隆层生命周期**：genie-lite/概览飞行/最小化过渡等克隆 Item，动画结束帧必须 `destroy()`，禁止常驻；同屏克隆层 ≤3。
5. **stagger 预算**：单次编排总时长 ≤450ms；同帧活动动画元素 ≤40（Launchpad 全网格 stagger 需按此上限截断延迟梯度）。
6. **弹簧 epsilon 下限**：位移类 ≥0.0005、小元素/不透明度类 ≥0.001，防止亚像素长尾帧。
7. **模糊与材质**：compositor blur `passes 4` 不上调；QML 内禁止叠加 FastBlur/GaussianBlur 等二次模糊；tahoe-glass 材质参数改动需在验收记录里附改前/改后主观帧感受与 `niri msg` 正常性确认。
8. **纹理/快照**：close/genie/最小化快照沿用"动画结束即释放"路径（GOAL-7 pytest 覆盖），涉及改动必须重跑 `test_memory_allocation_governance.py` 与相关 cargo tests；genie 绘制区域保持"窗口∪目标+24px"，禁止扩为整屏（`minimize_window_animation.rs:416-430` 测试保护）。
9. **RSS 基线**：T00 记录 quickshell 与 niri 进程 RSS 基线；此后每阶段末（T04/T12/T14/T20/T23）验收记录必须附当前 RSS，相对基线涨幅 >5% 必须写明原因与处置。
10. **常驻面数**：不新增常驻 layer surface（新功能复用既有 PanelWindow 或按需创建/销毁）。

---

## 5. 许可清单：明确可以做

1. KDL layer-rule 主通道写 `spring damping-ratio=… stiffness=… epsilon=…`（`animations.rs:1179-1196` 已支持）；`popin + origin "anchor"`；自定义 `cubic-bezier`。
2. 重写 window-open/close 的 custom-shader（scale+fade），用 spring 主通道驱动 shader 进度。
3. 新增 KDL 动画节点 `window-minimize {}` / `window-restore {}`（镜像 WindowOpenAnim 节点形态，默认值=现行为）；新增命名曲线（附单调性测试）。
4. 新增 motion profile（如 `macos`），按红线 5 三方同步；`Motion.js` 增加弹簧 token 导出。
5. `Wallpaper.qml` 由 shell 状态驱动变焦/暗化（Launchpad 开场）。
6. `DesktopSettings` JsonAdapter 新增字段（accent 色、通知堆叠数等）。
7. `tahoe-shell/assets/` 新增预渲染图标资产；新建 `TahoeSymbol.qml` 统一图标出口。
8. 合并重复组件（MenuRow、hover 标签、颜色 token）。
9. niri fork Rust 扩展（仅限路线图 T21/T22 立项范围：layer per-channel spring、pop-slide style、origin pointer、genie 节点与 frag 调优）。
10. genie.frag 形变曲线重修（两段式吸入、末端淡出比例、edge lead 差）——保持 fallback 链与绘制区域护栏。

---

## 6. 每任务验收命令模板

按任务涉及面选取，验收记录必须贴命令与结果：

```sh
# KDL 改动
/home/wwt/.local/bin/niri validate --config config/niri/tahoe-phase0.kdl

# niri fork Rust 改动
cd niri && cargo test -p niri animation
cd niri && cargo test -p niri genie_area minimize_restore_with_rect
scripts/check-genie-minimize-phase7-8.sh          # genie 专项
scripts/check-tahoe-glass-guardrails.sh           # 材质/玻璃改动

# shell 治理测试（motion/材质/内存相关任务必跑）
cd tahoe-shell && python -m pytest tests/ -x

# shell 加载冒烟（配置能起、无 QML 错误日志）
quickshell -p tahoe-shell -n --log-rules '*.debug=false' &  # 或按 scripts/start-quickshell.sh 环境

# 手测入口（按任务附最小矩阵）
qs ipc -p <cfg> call tahoe toggleControlCenter / toggleLeftSidebar / openSpotlight / …（全集见 shell.qml:514-605）
```

手测矩阵基线（涉及弹窗/dock/genie 的任务必测）：打开/关闭/快速连点/Esc/点外关闭/深浅色/reduced profile/`compositorLayerAnimations=false` 回退路径。
