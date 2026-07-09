# 01 · 研究报告：Tahoe 桌面视觉/手感/动效现状审计与升级方向

日期：2026-07-09
性质：源码静态审计（以源码为第一依据，文档仅作辅助）。本报告不代表已实施。
范围：tahoe-shell 全部核心组件、niri fork 动画引擎与 layer/genie 实现、`config/niri/tahoe-phase0.kdl`、玻璃材质体系、网页参考实现。

---

## 1. 总诊断：三大根因

### 根因 1：动效词汇是"短促补间"，不是 Apple 的"弹簧"

- `tahoe-shell/components/Motion.js:8-19` 全库只有 7 个时长 token（菜单 150/120ms、面板 180/140ms、元素移动 130ms）加 4 个通用 Qt 缓动（OutCubic/InCubic/OutQuad/OutQuart）。没有弹簧词汇、没有过冲、没有速度延续。
- niri 侧 layer 动画曲线用的是 **Material Design 3 原版曲线**：`emphasized-decel(0.05,0.7,0.1,1)`、`emphasized-accel(0.3,0,0.8,0.15)`、`standard-decel(0,0,0,1)` 等（`niri/niri-config/src/animations.rs:1051-1060`）。真 macOS 的运动语言是弹簧（SwiftUI `response/dampingFraction`、CASpringAnimation）：感知时长更长（300–550ms）、带轻微过冲、可被打断并自然接力。
- 结果：每个动画都是一次性的"减速刹车"，快但死。

### 根因 2：视觉基因是"工程师仪表盘"，不是 Apple

- 全局用 Material Icons 字体做图标（TopBar/ControlCenter/LeftSidebar/Settings/Launchpad/Spotlight 共约 40+ 处字形引用）。
- 所有卡片是"低透明白填充 + 1px 白描边"三件套（例：`LeftSidebarWeather.qml:37-39` 的 cardFill/cardHover/cardStroke；`SettingsTheme.js:66-99` 全套半透明白）。
- 信息组件带工具窗 chrome：左侧边栏有标题"左侧边栏"+ 关闭圆钮 + 双 Tab（`LeftSidebar.qml:132-214`）；控制中心有标题行 + X 钮（`ControlCenter.qml:94-128`）。真 macOS 对应物没有这些。
- 数据用等宽字体 + catppuccin 系折线配色（`LeftSidebarSystem.qml:46-57`）。

### 根因 3：macOS 的"招牌戏剧性动画"缺席或走样

- Dock：线性衰减放大、峰值仅 1.34、格子定宽不推挤、点击只有 14px 微跳、无启动等待循环弹跳（详见 §4.1）。
- Launchpad 是 760×560 居中小窗，非全屏，无壁纸变焦、无 stagger、无翻页（§4.2）。
- 菜单没有"选中项闪两下再整体淡出"，hover 是白色填充而非 accent 蓝（§4.6）。
- 通知只有单卡，不堆叠（§4.8）。
- 设置页面切换零动画（§4.5）。
- **全桌面没有按下态（press state）**——所有控件只有 hover。
- Genie 已有合成器级实现但时序耦合窗口动画且未做 macOS 化调优（§5）。

### 基建现状（好消息）

niri fork 的动画引擎完整支持弹簧（damping-ratio/stiffness/epsilon，mass=1，含初速度接力，`niri/src/animation/spring.rs`）和任意 cubic-bezier（`niri/src/animation/bezier.rs`）；layer 动画有 fade/popin/slide/edge-reveal 四种样式、center/anchor 变换原点、transform/opacity 双通道 + opacity 延迟（`animations.rs:203-308`）；tahoe-glass 材质协议（refraction/edge-highlight/inner-shadow/chromatic/lens-depth）已经是液态玻璃级别。**大部分升级是"把参数和词汇换成 Apple 的"，少部分要写新代码。**

---

## 2. 动效基建现状细目

| 位置 | 现状 | 问题 |
| --- | --- | --- |
| `Motion.js:8-19` | 时长 token + 4 缓动，4 个 profile（fast/balanced/liquid/reduced） | 无弹簧词汇；时长普遍比 macOS 短 40–60% |
| `shell.qml:70` | `useSpring: true`（真机默认开） | 全 shell 只有 Dock 弹跳/放大真的用了 SpringAnimation，弹簧词汇没有铺开 |
| `config/niri/tahoe-phase0.kdl:405-675` | 所有 layer-rule 用 `transform-duration-ms + 命名曲线` | **主通道其实支持 `spring`**（`animations.rs:1179-1196` 的 decode 对 layer 同样生效）；只有 `transform-*`/`opacity-*` 覆写通道被强制转 Easing（`animations.rs:1010-1034`）。不写 transform-duration-ms、让 transform 继承主通道弹簧即可解锁 |
| `animations.rs:1046-1112` | 命名曲线表 + 任意 `cubic-bezier x1 y1 x2 y2` | 曲线命名是 MD3 词汇；`menu-decel`/`stall` 是非单调 x 的兼容曲线（注释明示勿用于 compositor 通道） |
| `opening_layer.rs:100-117` | `origin "anchor"` 以 layer surface 锚定边为缩放原点 | 顶栏弹窗全部 top+left 锚定 → anchor origin ≈ 从按钮附近长出，**现在没用**（全用 edge-reveal） |
| 全部控件 | 只有 hover 色变 | macOS 每个可点元素都有按压变暗/缩放 |

### 窗口/工作区动画（`tahoe-phase0.kdl:255-309`）

| 项 | 现状 | 差距 |
| --- | --- | --- |
| window-open | 120ms ease-out-cubic + 自定义 shader 纯透明度淡入（:260-277） | 真 macOS 新窗口 ≈ scale 0.97→1 + 淡入 ~250ms，现在扁平无生气 |
| window-close | 100ms ease-out-quad 纯淡出（:279-296） | 缺收缩感 |
| workspace-switch | spring dr=1.0 st=780（:257） | 过硬；macOS Spaces 是较慢滑行 + 柔和停靠 |
| window-movement | spring dr=0.86 st=620（:299） | 可更活：dr≈0.80 st≈480 |
| window-resize | spring dr=0.96 st=700（:303） | 基本合理 |
| 阴影 | softness 36 spread 4 y=10 `#0006`（:43-50） | 真 macOS 聚焦窗阴影大得多：≈ softness 60 y=18 alpha 0.45 + 非激活明显更弱 |
| 窗口圆角 | 18（:314） | Tahoe 窗口更圆，建议 22 |

### 玻璃材质（`tahoe-phase0.kdl:71-197`）

7 种材质（panel/pill/launcher/dock/menu/toast/backdrop），参数已细腻。`GlassPanel.interaction` 属性已接 hover（`Dock.qml:374`），compositor 侧会提升边缘光——**把它同时接到按压事件上**即可获得 Tahoe 液态玻璃的"按压聚光"，零合成器改动。

---

## 3. 目标动效规范：Tahoe Motion 2.0

Apple `response/bounce` 换算 niri spring（mass=1）：`stiffness = (2π/response)²`，`damping-ratio = 1 − bounce`。

| Token | Apple 手感 | niri spring | QML SpringAnimation 近似 | 用途 |
| --- | --- | --- | --- | --- |
| `springSnappy` | snappy（response .28 / bounce .12） | dr=0.88 st=500 | spring 4.2 damping 0.30 | 菜单/小弹窗入场、开关 |
| `springSmooth` | smooth（response .40 / bounce 0） | dr=1.0 st=250 | spring 3.0 damping 0.40 | 面板位移、高度变化 |
| `springPanel` | 默认 spring（response .50 / bounce .15） | dr=0.85 st=160 | spring 2.5 damping 0.28 | 控制中心/通知中心/侧边栏 |
| `springBouncy` | bouncy（response .50 / bounce .30） | dr=0.70 st=160 | spring 2.5 damping 0.22 | Dock 弹跳、灵动岛 morph |
| `pressIn` | 按下 | 120ms ease-out-quad + scale 0.96 | — | 所有可点元素按下态 |
| `fadeContent` | 内容交叉淡化 | 180–220ms standard-decel | — | 透明度通道 |

分层规则（macOS 手感的隐性公式）：

1. **位移/尺寸/缩放走弹簧；透明度永远走短 ease 淡化，且先于变换完成**（现有 KDL 的 opacity 90–110ms / transform 210ms 分层思路正确，保留结构，换弹簧）。
2. 入场比出场慢约 1.6 倍；出场用 accel 曲线。
3. 被打断的动画从当前值+当前速度接力（niri `Animation::restarted` 已支持初速度，`animation/mod.rs:111-151`）。

---

## 4. 逐组件审计与差距

### 4.1 Dock（差距最大）

现状（`tahoe-shell/components/Dock.qml`）：

- 放大：`proximityScale()` 线性三角衰减 `1 − d/135`，峰值 1.34（:128-136）；图标格子定宽 62px 不推挤（:454-460 注释明示为避免 `width→magnification→width` 绑定循环而放弃宽度联动）；平滑用临界阻尼 spring 260/damping 1.0（:690-697）。
- 点击弹跳：kick 14px + spring 380/0.32 单次微跳（:652-681），与应用启动状态无关。
- autohide：dockSlideOffset 88px，190ms OutCubic（:335-337）；hover 标签 24px 高 11px 字带 y 滑移（:535-576）。
- 收纳架缩略图 hover 仅换填充色（`DockMinimizedWindow.qml:102-110`）。

差距 → 方向：

1. 余弦钟形衰减 `scale(d)=1+(peak−1)·cos²(πd/2R)`，peak 1.7–2.0，R≈2.5 图标宽。
2. **推挤**：放弃读 delegate 几何，改为按索引解析计算每图标目标中心 `x_i = Σ_{j<i} w_j(cursorX) + w_i/2`（w 由衰减函数直接算），图标显式 `x` 定位替代 Row 自动布局——从根源消除绑定循环，波形随光标连续滑动。
3. 启动循环弹跳：`launching` 状态 + 抛物线跳（高 ≈0.7×图标高，周期 ≈550ms，InQuad 上/OutQuad 下），循环至 `appHasRunningWindow`（:446-449）为真或 10s 超时。
4. 图标基准 46→56px；按下变暗 25%；标签即时出现、13px、去 y 滑移；autohide 换 springSmooth + reveal 消抖。

### 4.2 Launchpad（需推倒重做）

现状（`Launchpad.qml`）：760×560 居中窗（:32-35）、无翻页、无 stagger、无键盘导航（仅 Enter 首项 :195-200）、类别 chips（:204-251）、开场 140ms 淡入 + 0.98→1（:100-106）。故意留在 QML 动画路径（compositor 缩放会让图标发虚，:36-38）。

方向：全屏化（surface 已全屏）+ **壁纸变焦**（`Wallpaper.qml` 归 shell 管，打开时驱动壁纸 scale 1→1.06 + 暗化 25%）+ 图标按"距中心距离×6ms"stagger 弹入（springSnappy）+ 横向分页（snap + OvershootBounds 橡皮筋 + 页点）+ 方向键导航 + 删类别 chips。

### 4.3 Spotlight

现状（`Spotlight.qml`）：搜索 pill 与结果面板是两块分离玻璃（:120-258，10px 缝）；结果高度瞬变；无 ↑↓ 键盘选中；输入框里塞 4 个快捷按钮（:185-234）。

方向：合并为单面板；高度变化用 250ms emphasized（玻璃 region 禁弹簧，无过冲曲线正合规）；↑↓ 选中 + 蓝色高亮胶囊 y 弹簧平移；分组标题；右侧预览栏（220px，内容交叉淡化 150ms）；删快捷按钮。

### 4.4 云朵左侧边栏

现状：工具窗结构（标题 + 关闭钮 + 双 Tab，`LeftSidebar.qml:132-214`）；天气页大温度用等宽字体 + 8 个描边小卡 + "未来几小时 12 项"式工程师标题（`LeftSidebarWeather.qml:141-333`）；系统页 iStat 风双弧仪表 + Canvas 折线 + 进程表（`LeftSidebarSystem.qml`）。KDL 侧 edge-reveal 无透明度淡入（`tahoe-phase0.kdl:466-487`）。

方向（widget 栈化）：去 chrome（删标题/关闭钮，Tab 改分段胶囊或取消）；天气改 macOS 中号小组件（**按天气状态渐变彩底**，WeatherCodes.js 已有状态映射；白色大字非等宽；逐时条内嵌）；日预报温度条渐变色去描边；系统改活动圆环风 + top3 进程默认收起；卡片去 1px 描边改"填充差+阴影"；面板落位后卡片 30ms 间隔 stagger（y+14→0 + opacity，springSmooth）；KDL 主通道换弹簧。

### 4.5 设置界面

现状：900×540 玻璃浮层（`SettingsPanel.qml:47-50`）；**页面切换 StackLayout 直切零动画**（:331-527）；侧栏 210px 无彩色分类图标（`SettingsSidebar.qml:229-241`，但色表已备好未用：`SettingsTheme.js:190-227`）；全表面半透明白导致灰蒙蒙（`SettingsTheme.js:66-99`）；开关 42×24 无按压形变无投影（`TahoeSwitch.qml`）。

方向：内容区提高到 ~0.92 不透明度（真 System Settings 基本不透明，玻璃感留给边缘与阴影）；侧栏彩色圆角方块图标 + 选中实心 accent 蓝胶囊白字；页面切换 = 新页右侧 24px 滑入+淡入（280ms emphasized）+ 旧页 12px 视差淡出 + 子页返回箭头（SettingsModel 已有 parentId 层级）；控件精修（开关按压拉宽 knob 20→24 + 投影、滑块白色圆 knob、行高 40、分割线内缩、主按钮实心 accent）。

### 4.6 菜单与小弹窗

现状：`MenuPopup.qml` 行高 30、12px、hover 白色填充（:244-248）；关闭即消失；6 个菜单组件各自内联一份 MenuRow 实现（MenuPopup/AppMenuPopup/TrayMenu/DockAppMenu/DockWindowMenu/ProcessMenu）。KDL 全用 edge-reveal（:553-617）。

方向（macOS 菜单三签名）：① 即时出现（popin scale-from 0.98 高刚度或 60ms 淡入），关闭 180ms 纯淡出；② **选中项闪两下**（~70ms 间隔）再整菜单淡出再执行动作；③ hover 改 accent 蓝实心+白字，行高 26、13px、radius 6。防腐化：6 份 MenuRow 合并为一个共享组件。popover 类（电池/WiFi/风扇/剪贴板）KDL 改 `popin origin "anchor" scale-from 0.94 + 弹簧`。

### 4.7 控制中心

现状（`ControlCenter.qml`）：标题行 + X 钮（:94-128，真 CC 没有）；Wi-Fi 磁贴整贴点击即切换（:380-388）；滑块无 knob（:696-751）；磁贴无 hover/按下反馈；展开行 180ms 高度动画（:194-204）。

方向：删标题/X；**模块原位 morph 展开**（点 Wi-Fi → 面板高度 280ms emphasized 扩展、磁贴长成整宽网络列表、其余磁贴淡出下移 8px、逆向 morph 返回；玻璃 region 禁弹簧 → 用无过冲曲线）；滑块加白色圆 knob + 拖动 scale 1.15；磁贴 hover 提亮 6% / 按下暗 10% + scale 0.97；ToggleCircle 状态切换加 1→0.9→1 弹性 + ColorAnimation 200ms。

### 4.8 通知系统

现状：单卡 toast（`NotificationToast.qml:19-23` 注释明示单卡复用），x 平移 180ms 入场（:136-138）；NotificationCenter 只有一处 130ms x 位移动画（:185-186）。

方向：堆叠化（最多 3 张：新卡 x+60→0 springPanel 弹入，旧卡 y+8 / scale 0.96/0.92 下压）；hover 浮起 + 左上 X 钮；横滑 dismiss（速度判定阈值可复用 `DynamicIslandMotion.js:26-32` 的 swipe 范式）；通知中心按 app 分组堆叠、展开弹簧散开、清除全部逐卡 stagger 飞出。

### 4.9 灵动岛与顶栏

灵动岛是现存动效最好的部分（morph 400ms OutQuint，`DynamicIslandMotion.js:13-23`）。方向：width/height/radius 换 springBouncy（带过冲的尺寸 morph 是灵动岛本体），radius 恒等 height/2 连续插值，内容切换 scale 0.9→1 伴随淡入。
顶栏（`TopBar.qml`）：状态按钮 hover 的 1px 描边全部去掉（:361-363 等 7 处），改纯填充胶囊即时高亮 + 按下变暗；图标随 §6 迁移；时钟/数据用 tabular 数字。

### 4.10 任务切换器 / 窗口概览

TaskSwitcher：opacity 130ms + scale 150ms（:307-312）——真 cmd+tab 无入场动画（即时出现），选中框在图标间平移。WindowOverview：纯淡入淡出 + scale 160ms（:321-371）——Mission Control 是窗口从实际位置飞向网格位的弹簧飞行（可用 ThumbnailProvider 缩略图 + 显式 x/y 弹簧实现"飞行"）。

---

## 5. Genie（神灯）动画：现状与优化方向

### 现状（已实现，合成器级）

- 实现：`niri/src/layout/minimize_window_animation.rs` + `niri/src/render_helpers/shaders/genie.frag`（另有 genie_prelude/epilogue 可组合段）。
- 数据链：Dock 通过 foreign-toplevel `setRectangle` 提供目标矩形（`DockMinimizedWindow.qml:62-75` 恢复前回写矩形；`Windows.qml` setRectangle）。
- 时序：最小化沿用 `window-close` 配置、恢复沿用 `window-open` 配置；**有效目标矩形时强制"更平滑曲线 + ≥320ms"下限**（`genie-minimize-phase7-8-acceptance-2026-06-21.md:19`，测试 `genie_animation_config_slows_valid_target_rect`）。
- 形变特征（phase7 记录）：底边先行、顶边滞后但克制、**末 12% 才淡出**、目标侧轻微压扁。
- 可中断反转：`reverse_to_restore/reverse_to_minimize` 带进度接力（:243-267）。
- 性能护栏：绘制区域 = 窗口∪目标 + 24px padding（:416-430），有单元测试保护；动画期间持有最多 3 张全窗纹理（contents / blocked-out / blocked-out-bg，:187-218），结束即随对象释放（快照生命周期有 GOAL-7 pytest 覆盖）。
- fallback 链完整：无矩形→普通淡出；跨输出矩形→过滤；shader 编译失败→纹理淡出（acceptance doc :21-26）。

### 优化方向（对标真 macOS Genie ≈500ms 的"吸入"感）

1. **时序解耦**：新增 `window-minimize {}` / `window-restore {}` KDL 动画节点（镜像 WindowOpenAnim 的既有节点形态，属于复用既有 Animation 解码模式，非平行接口），默认值 = 当前行为；Tahoe 配置建议 minimize 420ms `cubic-bezier(0.32,0,0.18,1)`、restore 360ms emphasized-decel。这样 T02 改 window-close/open 时不会误伤 genie。
2. **frag 形变重修**：第一阶段（0–40%）先"拉出尾巴"（目标端收束提前、窗口主体基本原位），后段（40–100%）整体流入——目前的形变偏"整体位移+弯曲"，缺两段式"吸入"；顶/底边 lead 差增强 10–15%；末端淡出 12%→6–8%（真 genie 几乎不靠透明度，靠形变收束）。
3. restore 方向（direction=-1 分支已有）做反向两段式：先鼓出再展开。
4. 中断反转、绘制区域护栏、纹理释放路径全部保持，改动后必须重跑既有 cargo tests + `scripts/check-genie-minimize-phase7-8.sh` + 相关 pytest。
5. 进度 uniform 已同时传 `niri_progress`（未钳制）与 `niri_clamped_progress`（:375-384）——若尝试弹簧驱动，形变用 clamped、只让位移通道吃过冲；首选仍是 easing（形变类动画过冲易破相）。

---

## 6. 视觉体系（跨组件）

1. **图标撤换（最大的"一眼假"修复）**：全局撤 Material Icons 字体。用预渲染 PNG 符号集（`macOS-26-Tahoe-for-the-Web-main/icon/symbols/` 已有部分资产；补齐用 SF 风格开源集 Phosphor/Lucide 预渲染 @2x PNG 入 `tahoe-shell/assets/`），新建 `TahoeSymbol.qml`（name→source + 着色），走既有 `appsService.iconPath()` 接口（`Spotlight.qml:220` 已有先例）。不引入运行时 SVG/Lottie 依赖（与 `LeftSidebarSystem.qml:18` 既有约定一致）。
2. **颜色语义化**：建共享 token 库（扩展/收编现有 `SettingsTheme.js`，非新平行文件）：label/secondaryLabel(50%)/tertiaryLabel(25%)、separator(8–12%)、systemBlue `#007AFF/#0A84FF`、用户可选 accent（macOS 8 色）。收编全 shell 几十处一次性 hex。
3. **描边减法**：1px 白描边只保留玻璃面板最外圈；卡片/按钮/行内元素改"填充差 + 阴影"。
4. **字体**：CJK 保持 Noto Sans CJK；拉丁/数字叠 Inter；数据处开 `font.features {"tnum": 1}`；字阶 11/13/15/17/20/28；正文 12→13px。
5. **材质微调**：菜单 `tint-amount 0.11→0.16`（更可读）；`GlassPanel.interaction` 接按压事件（按压聚光）。

---

## 7. 性能与内存观察

已经做对的（保持，不许退步）：

- Image 普遍设 `sourceSize` + `asynchronous`（如 `Dock.qml:516-522`）；缩略图 `cache: false`（`DockMinimizedWindow.qml:125`）。
- 快照生命周期有自动化测试（fast 切换、中断、一帧释放，policy doc GOAL-7）；内存分配治理有 pytest（`tests/test_memory_allocation_governance.py`）。
- Genie 绘制区域有界 + 测试保护；ThumbnailProvider 带队列/缓存/失败态。
- 玻璃 blur 由 compositor 单次完成（passes 4），QML 不叠加模糊。

本轮升级引入的新风险（规则文件设预算约束）：

- stagger 编排（Launchpad/侧边栏/通知中心）→ 同帧活动动画元素数量上限、总编排时长上限。
- Dock 波形逐帧更新 → 必须继续走 Behavior/SpringAnimation 框架（现状如此），禁止 per-frame JS Timer 轮询。
- genie-lite/概览"飞行"类克隆层 → 动画结束必须 destroy，禁止常驻。
- LeftSidebarSystem 的 Canvas `requestPaint` 已按数据到达节流（fast 1s/medium 2s，:126-176）——重构后刷新频率不得加密。
- 弹簧 epsilon 下限（位移 ≥0.0005、小元素 ≥0.001）防长尾帧。

---

## 8. 参考实现评价

`macOS-26-Tahoe-for-the-Web-main` 的动效本身很粗糙（清一色 0.2s/0.3s 通用 ease，Css/style.css 采样确认），**只当视觉素材库用（图标/布局比例），不要抄它的时序**。动效标准以 §3 的 Apple 弹簧参数表为准。
