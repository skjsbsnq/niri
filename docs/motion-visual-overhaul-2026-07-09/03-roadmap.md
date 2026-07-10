# 03 · 执行路线图：T00–T23 严格串行任务

日期：2026-07-09
前提：先读 [02-rules.md](02-rules.md)。**上一任务未达到 DONE（全部代码完成 + 验收通过 + commit + push 成功），不得开始下一任务**（研究性阅读不受限）。每任务 = 一个提交（`Txx:` 前缀）+ push 成功 + 一份 `acceptance/Txx-*.md` 验收记录；执行循环协议、"全部代码完成"判定标准与子模块 push 细则见 [04-goals.md](04-goals.md)。规模标注：S（≤半天）/ M（约一天）/ L（多日）。

任务默认验收底线（每个任务都隐含，不再重复写）：
- `niri validate` 通过（涉 KDL）；`cargo test -p niri` 相关子集通过（涉 Rust）；`python -m pytest tahoe-shell/tests/ -x` 通过（涉 shell/治理面）；quickshell 冒烟加载无 QML 错误。
- 规则 §2 红线逐条自查；规则 §6 手测矩阵基线跑一遍。
- 回滚方式一律为 `git revert <该任务提交>`，特殊回滚步骤才单独写。

---

## 阶段 A：参数换血（纯配置 + token，收益最大）

### T00 · 基线锁定（S）

- **目标**：为整轮升级建立可对照、可回滚的基线。
- **改动**：不改代码。创建 `acceptance/` 目录；记录当前 commit hash；跑通并记录：`niri validate`、`cargo test -p niri`（animation/genie/layout 子集）、全量 pytest、quickshell 冒烟；记录 quickshell 与 niri 进程 RSS 基线（规则 §4.9）；用 `scripts/capture-glass-baseline.sh` 留玻璃基线截图（可行则截 dock/CC/侧边栏/设置四景）。
- **验收**：`acceptance/T00-baseline-*.md` 齐全，含全部命令输出摘要与 RSS 数字。
- **回滚**：无（只产出记录）。

### T01 · Motion.js 2.0：弹簧 token 与治理测试同步（M）

- **目标**：建立 §3（研究报告）的 Tahoe Motion 2.0 词汇表，作为后续所有任务的唯一动效出口。
- **改动**：`Motion.js` 新增弹簧 token 导出（springSnappy/springSmooth/springPanel/springBouncy 的 QML SpringAnimation 参数组 + 对应 niri spring 参数注释）、`pressDuration=120`、`pressScale=0.96`；时长重调：menuEnter 150→180、menuExit 120→160、panelEnter 180→320、panelExit 140→200（四 profile 等比联动，reduced 保持极短）；新增 `macos` profile 或直接以 balanced 承载新值（**二选一，选定后写入验收记录**；若新增 profile：`niri_settings_tool.py` + `DesktopSettings.qml` 源默认 + policy 文档同一提交更新）。同步更新 `test_motion_token_convergence.py`、`test_motion_default_policy.py`。**本任务不改任何组件**。
- **验收**：pytest 全绿；quickshell 冒烟后现有组件动画仍正常（数值变化生效）；设置页 motion profile 切换仍工作。
- **依赖**：T00。

### T02 · 窗口/工作区动画 + 阴影/圆角 KDL 重写（M）

- **目标**：窗口层手感 macOS 化。
- **改动**（`config/niri/tahoe-phase0.kdl` tahoe-managed 区块）：window-open 改 spring 主通道（dr≈0.85 st≈300）+ 新 shader（scale 0.965→1 + 淡入，读 `niri_clamped_progress`）；window-close 140ms + shader 加 scale→0.97；workspace-switch → dr=0.92 st=420；window-movement → dr=0.80 st=480；window-resize 保持近临界；layout.shadow → softness 60 spread 6 y=18 `#0007` / inactive `#0004` softness 40；window-rule geometry-corner-radius 18→22（popups 14→16）。
- **验收**：`niri validate`；实机开/关/拖动/换工作区目测对照 T00 截图；genie 行为不回归（此时 genie 仍耦合 window-close/open——若观感受损，允许在本任务临时保持 window-close 旧值，把解耦留给 T04，写入验收记录）。
- **依赖**：T01。

### T03 · layer-rule 全面弹簧化 + anchor popin（M）

- **目标**：所有 shell 弹层的出入场换 Apple 手感。
- **改动**（同文件 layer-rule 区块）：菜单类七 namespace（menu-popup/application-menu/tray-menu/dock-app-menu/dock-window-menu/process-menu）→ `popin origin "anchor" scale-from 0.94` + 主通道 spring（dr≈0.88 st≈500，**不写 transform-duration-ms 以继承弹簧**）+ `opacity-from 0 / opacity-duration-ms 90`；关闭 → 180ms 纯淡出（scale-to 0.98，menu-accel 换 emphasized-accel）。控制中心/通知中心/左侧边栏 edge-reveal 主通道换 spring（dr≈0.85 st≈380）。toast slide 主通道 spring（dr≈0.80 st≈320）。spotlight popin 换 spring + scale-from 0.96。同步更新 `test_edge_reveal_semantics.py`（若语义断言涉及时长/曲线）。
- **验收**：`niri validate`；逐 namespace 用 IPC 开关目测（含快速连点中断反转）；`compositorLayerAnimations=false` 时 QML fallback 路径完好。
- **依赖**：T02。

### T04 · Genie（神灯）动画专项优化（M–L，涉 Rust）

- **目标**：genie 达到"两段式吸入"的 macOS 观感，并与窗口动画时序解耦。
- **改动**：
  1. `niri-config/src/animations.rs` 新增 `window-minimize {}` / `window-restore {}` 节点（镜像 WindowOpenAnim 形态，默认=现行为即沿用 close/open + 320ms 下限），layout 侧接线替换耦合点；
  2. Tahoe KDL 配 minimize 420ms `cubic-bezier(0.32,0,0.18,1)`、restore 360ms emphasized-decel；
  3. `genie.frag` 形变重修：0–40% 先收束目标端"拉尾巴"、40–100% 整体流入；顶/底边 lead 差 +10–15%；末端淡出 12%→8%；restore 分支反向两段式；
  4. 保持：绘制区域 union+24、三级 fallback、`reverse_to_*` 中断反转、快照释放路径。
- **验收**：`cargo test -p niri genie_area minimize_restore_with_rect` + 新增节点解码测试；`scripts/check-genie-minimize-phase7-8.sh` 全绿；手测矩阵（floating/scrolling/多输出/分数缩放/快速连点/Dock 重启）；pytest 内存治理测试通过；RSS 对照（阶段 A 末检查点）。
- **依赖**：T03。

> **2026-07-10 二次修正：** 第一次 T04-fix 的自动化通过但实机逐帧验收失败。最终修正改用真实 Dock 图标矩形与线性 restore 驱动，窗口开关改为有界原生 scale+fade，顶栏七类弹层统一为控制中心同款 top edge-reveal，并补 layer close→reopen 状态续接。详见 `acceptance/T04-fix2-animations-2026-07-10.md`；该修正取代本节和第一次 fix 记录中冲突的实现参数。

---

## 阶段 B：交互手感（QML 微交互）

### T05 · 全局按下态铺开（M）

- **目标**：补上 macOS 的"按压反馈"这层缺失的手感。
- **改动**：以 Motion.js 的 pressIn token 为唯一出口，给以下元素统一加按下变暗/缩放（0.96）：TopBar 状态按钮与菜单钮、Dock 图标（按下变暗 25%）与工具钮、CC 磁贴/圆钮、设置控件（TahoeButton/TahoeListRow/TahoeSidebarButton/TahoeSegmented）、Spotlight/Launchpad 行与格、菜单行。同时把 `GlassPanel.interaction` 接到按压（按压聚光，零合成器改动）。TopBar hover 的 1px 描边全部移除（改纯填充胶囊）。
- **验收**：逐面板手测按下态；reduced profile 下按下态退化为即时色变（无缩放）；pytest 治理测试。
- **依赖**：T04。

### T06 · 菜单 macOS 化 + MenuRow 合并（M）

- **目标**：菜单三签名（即时出现/选中闪烁/蓝色高亮）+ 防腐化合并。
- **改动**：新建共享菜单行组件（命名沿用现约定），**替换掉 6 处内联 MenuRow**（MenuPopup/AppMenuPopup/TrayMenu/DockAppMenu/DockWindowMenu/ProcessMenu）；行高 26、字 13px、radius 6、hover=accent 蓝实心+白字（含图标）；点击后闪两下（~70ms 间隔）→ 整菜单淡出 → 执行动作；分割线 `#1a000000` 内缩。
- **验收**：6 个菜单全部行为一致；键盘 Esc/点外关闭不回归；闪烁期间快速再点无重入 bug。
- **依赖**：T05。

### T07 · Dock 放大与推挤重写（L）

- **目标**：真 Dock 波形。
- **改动**（`Dock.qml` + `WindowButton.qml`）：余弦钟形衰减（peak 1.7、R≈2.5 图标宽，参数进 Motion.js 或 Dock 顶部常量区）；**解析式推挤**——按索引计算目标中心 x（规则：不读 delegate 几何，杜绝绑定循环），pinned 行改显式 x 定位；图标基准 46→56、dock 面板高度/exclusiveZone 相应重算；磁贴间距弹簧联动；3 份 hover 标签实现合并为一，13px、即时出现、去 y 滑移。保持 useSpring 双分支与 Flickable 溢出行为。
- **验收**：光标扫过波形连续、无跳变、无绑定循环告警（quickshell 日志）；拖拽重排/右键菜单/最小化收纳架全部不回归；帧感受与 CPU 占用记录入验收（对照 T00）。
- **依赖**：T06。

### T08 · Dock 启动弹跳 + autohide 手感（M）

- **目标**：补启动等待循环弹跳与 autohide 弹性。
- **改动**：`launching` 状态机（点击启动 → 抛物线循环跳：高≈0.7×图标高、周期≈550ms、InQuad 上/OutQuad 下；`appHasRunningWindow` 为真或 10s 超时停止）；autohide slide 换 springSmooth + reveal 消抖 150ms；运行指示点微调（加 2px 辉光）。
- **验收**：启动慢应用（如首启浏览器）弹跳循环正确终止；连点不叠加动画；autohide 快速进出边缘无抖动。
- **依赖**：T07。

### T09 · 通知堆叠与滑出（M）

- **目标**：toast 栈化 + 手势。
- **改动**：`NotificationToast.qml` 支持最多 3 张堆叠（新卡 springPanel 弹入，旧卡 y+8 / scale 0.96/0.92 下压）；hover 浮起 + 左上 X；横滑 dismiss（复用 DynamicIslandMotion 的 swipe 阈值范式）；`NotificationCenter.qml` 按 app 分组、清除全部 stagger 飞出（预算：≤450ms、≤40 元素）。堆叠数入 DesktopSettings 字段。
- **验收**：`scripts/test-notification.sh` 连发 5 条行为正确；DND/灵动岛抑制路径不回归；克隆/多卡在队列清空后无残留对象（Qt 对象树检查或日志）。
- **依赖**：T08。

### T10 · 控制中心去 chrome + 控件手感（M）

- **改动**：删标题行与 X 钮，宽 360→330；滑块加白色圆 knob + 投影 + 拖动 scale 1.15；磁贴 hover 提亮/按下暗 + scale 0.97；ToggleCircle 切换 1→0.9→1 弹性 + ColorAnimation 200ms。
- **验收**：亮度/音量拖动跟手无迟滞；Esc/点外关闭；深浅色。
- **依赖**：T09。

### T11 · 控制中心模块 morph 展开（L）

- **改动**：点 Wi-Fi/蓝牙磁贴 → 面板高度 280ms emphasized 扩展（玻璃 region 禁弹簧），磁贴 morph 成整宽设备列表 + 返回箭头，其余磁贴淡出下移 8px；逆向 morph 返回。复用 Controls 服务现有 wifi/bluetooth 列表能力，不新建数据通道。
- **验收**：morph 往返 10 次无布局残留；列表为空/服务不可用时的占位态；高度动画期间玻璃 region 始终在 surface 内（无 niri 拒绝日志）。
- **依赖**：T10。

### T12 · 灵动岛 morph 弹簧化（S）

- **改动**：`DynamicIslandMotion.js` overlay morph 由 400ms OutQuint 改 springBouncy 参数组（width/height/radius 三通道），radius 恒等 height/2；内容切换 scale 0.9→1 + 淡入；chip 参数微调。灵动岛不是玻璃 region 项（自绘黑底）——确认后方可用弹簧，若发现接了 region 则高度通道保持 easing（写入验收记录）。
- **验收**：媒体出现/展开/收起/横滑全路径；`dynamicIslandSwipe*` IPC 调试路径不回归；RSS 阶段检查点。
- **依赖**：T11。

---

## 阶段 C：视觉体系

### T13 · 图标体系迁移（L）

- **改动**：`assets/` 引入预渲染 PNG 符号集（先用 `macOS-26-Tahoe-for-the-Web-main/icon/symbols/` 现有资产，缺口用 SF 风格开源集预渲染 @2x）；新建 `TahoeSymbol.qml`（name→source + 着色 + sourceSize 纪律），走 `iconPath()`；按面迁移全部 Material Icons 字形（TopBar→菜单→CC→侧边栏→设置→Launchpad/Spotlight）。Material Icons FontLoader 保留至全部迁完再移除（本任务末尾）。
- **验收**：全 shell 无 Material Icons 残留引用（grep 验证）；深浅色两套着色正确；图标内存（sourceSize ≤128）抽查。
- **依赖**：T12。

### T14 · 颜色语义化 + accent 系统（M）

- **改动**：把 `SettingsTheme.js` 扩展为全 shell 共享 token 库（或在其内新增 shell 域导出——收编而非并存，规则 §3.2）；语义色：label/secondaryLabel/tertiaryLabel/separator/systemBlue/danger…；accent 可选（macOS 8 色）入 DesktopSettings 字段 + 设置外观页选择器；逐组件迁移一次性 hex（本任务先迁 TopBar/菜单/CC/侧边栏四面，设置面留给 T15/T16）。
- **验收**：accent 切换全 shell 即时生效；深浅色对比抽查（文字可读性）；pytest。
- **依赖**：T13。

---

## 阶段 D：大部件重构

### T15 · 设置外壳重设计（L）

- **改动**：内容区不透明化（panelFill ≈0.92 不透明）；侧栏 210→230 + 彩色圆角方块图标（用 `SettingsTheme.categoryColor` 现成色表 + TahoeCategoryIcon）+ 选中实心 accent 胶囊白字；页面切换动画（新页右 24px 滑入+淡入 280ms emphasized，旧页 12px 视差淡出；StackLayout 换双页容器）；子页返回箭头（用 SettingsModel.parentId）。
- **验收**：34 个页面全部可达且切换动画正常；搜索过滤不回归；页面切换连点无竞态。
- **依赖**：T14。

### T16 · 设置控件精修（M）

- **改动**：TahoeSwitch（按压 knob 20→24 拉宽 + 投影 + 色变 150ms）、TahoeSlider（白色圆 knob + 投影）、TahoeButton（主按钮实心 accent、普通浅灰实心）、TahoeListRow（行高 40、分割线内缩）、TahoeSegmented/TextField 对齐 macOS 质感；字阶统一（正文 13px）。
- **验收**：NiriAnimationsPage 的曲线/弹簧编辑器仍工作（它是后续调参工具）；各页抽查 8 个。
- **依赖**：T15。

### T17 · Spotlight 重构（M）

- **改动**：单面板化（搜索行+结果同一玻璃）；高度 250ms emphasized；↑↓ 键盘选中 + 高亮胶囊 y 弹簧平移 + Enter 激活选中项；分组标题；右侧预览栏 220px（内容交叉淡化 150ms）；删输入框内快捷按钮。
- **验收**：键盘全流程（输入→上下→回车）；空结果/单结果边界；玻璃 region 随高度变化无越界日志。
- **依赖**：T16。

### T18 · Launchpad 全屏重构（L）

- **改动**：全屏网格（自适应 7×5）+ backdrop 材质；壁纸变焦（Wallpaper.qml scale 1→1.06 + 暗化 25%，400ms springSmooth，关闭反向）；图标"距中心×6ms"stagger 弹入（预算截断：总时长 ≤450ms）；横向分页（snap + OvershootBounds + 页点）；方向键导航；删类别 chips；保持 QML 动画路径（规则 §2.11）。
- **验收**：200+ 应用时首开帧感受与滚动流畅（记录）；搜索过滤重排；Esc/点外关闭；壁纸变焦与 blur 无冲突（xray false 场景）。
- **依赖**：T17。

### T19 · 左侧边栏 widget 化重构（L）

- **改动**：去 chrome（删标题行/关闭钮，Tab 改顶部小分段或合并为单列滚动）；天气 → 状态渐变彩底中号小组件（白字大号非等宽、逐时条内嵌、日预报渐变温度条去描边）；系统 → 活动圆环 + top3 进程默认收起（展开保留完整列表与右键菜单链路）；卡片全面去 1px 描边改阴影；入场卡片 stagger（30ms 间隔，springSmooth）。ProcessMenu 链路（shell.qml:869-905）不动。
- **验收**：天气各状态（晴/雨/夜/错误/缓存）视觉抽查；系统页数据刷新频率未加密（规则 §4.2）；进程右键菜单不回归。
- **依赖**：T18。

### T20 · 任务切换器 / 窗口概览手感（M）

- **改动**：TaskSwitcher 改即时出现（去入场缩放），选中框在图标间弹簧平移；WindowOverview 改"飞行"：缩略图从近似窗口位置向网格位弹簧飞行（克隆层用完即毁，规则 §4.4），关闭反向。
- **验收**：Mod+Ctrl+Tab 连击稳定；概览开关 10 次无残留克隆；RSS 阶段检查点。
- **依赖**：T19。

---

## 阶段 E：合成器扩展与收尾

### T21 · niri fork：layer per-channel spring + pop-slide（M，Rust）

- **改动**：`animations.rs` 的 transform/opacity 覆写通道支持 spring（`transform-spring damping-ratio=…`）；新增 `pop-slide` style（scale-from 与 edge/distance 复合，`opening_layer.rs` 两个 match 各加一臂）+ 解码测试；KDL 择面启用（菜单 pop-slide 下移 4px）。
- **验收**：cargo test 新增用例；`niri validate` 新旧语法皆过（向后兼容）；逐弹层目测。
- **依赖**：T20。

### T22 · niri fork：origin "pointer" + shader preset（M，Rust，可选项）

- **改动**：layer 动画新增按点原点（shell 经既有 tahoe-glass/foreign-toplevel 通道传锚点，**不新建协议**——若评估需新协议则本任务降级为跳过并记录）；window open/close 常用 shader 收为命名 preset 减少 KDL 内嵌 GLSL。
- **验收**：菜单从点击点长出；preset 与内嵌 GLSL 等效性对比。
- **依赖**：T21。

### T23 · 收尾：回归、校准、文档（M）

- **改动**：全量回归（规则 §6 全套命令 + 手测矩阵全集）；四 profile（fast/balanced/liquid/reduced + 若有 macos）复核校准；RSS 终值对照 T00；更新 `tahoe-motion-default-policy.md`（若默认 profile/开关变化）与本文件夹 README 状态；把 T05–T22 验收记录里的"发现待办"整理成下一轮 backlog。
- **验收**：`acceptance/T23-final-*.md` 汇总表（每任务一行：提交 hash / 验收结论 / 性能数据）。
- **依赖**：T22。

---

## 任务依赖总览

```
T00 → T01 → T02 → T03 → T04   (阶段A：参数换血，含神灯专项)
        ↓
T05 → T06 → T07 → T08 → T09 → T10 → T11 → T12   (阶段B：交互手感)
        ↓
T13 → T14   (阶段C：视觉体系)
        ↓
T15 → T16 → T17 → T18 → T19 → T20   (阶段D：大部件重构)
        ↓
T21 → T22 → T23   (阶段E：合成器扩展与收尾)
```

严格线性：即使某任务与后续任务表面无耦合，也不并行——串行是本轮的流程红线（规则 §1.1）。若执行中发现顺序必须调整（如 T04 需要前置到 T02），修订本文件并在验收记录中注明，属于允许的路线图维护。
