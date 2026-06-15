# Tahoe 改造差距分析（对标 macOS 26 Tahoe / Liquid Glass）

日期：2026-06-14
基于：`tahoe-shell/`（QML）、`niri/` fork、`config/niri/tahoe-phase0.kdl`、`macOS-26-Tahoe-for-the-Web-main/` 参考源的源码深读。

本文档目的：列出当前项目里**只有 UI 壳子、没有真实功能**的占位符，对照 Web 参考项目指出**动画和玻璃做得不够好的根因**，并给出可复用的 Web 资源清单和修复优先级。

---

## 一、占位符 / 假实现清单（只摆了 UI，点了不发生真实行为）

对照 Web 项目 `index.html` 可以很清楚地看到：macOS 控制中心、菜单栏、Spotlight、Dock 右段、Launchpad 这些核心交互在 Web 版里都有完整 DOM + JS，但在 `tahoe-shell/` 里基本只有 QML 外壳。

### 1. 控制中心 `ControlCenter.qml` —— ✅ 已完成（2026-06-14）

**原占位状态**：只有 3 个显示文字的空 tile（Workspace / Windows / Active），`ControlTile` 里 28×28 彩色圆点纯装饰，没有任何真实控件。

Web 参考（`index.html` 第 92–169 行）包含的控件清单：

```text
cc-wifi-tile      Wi-Fi 状态卡 + 子标题 "Home"
cc-row            蓝牙 / 个人热点 两个圆钮
cc-focus-pill     专注模式
cc-music-widget   正在播放（专辑封面 + 曲目 + 前进/播放/后退）
cc-stack-right    Stage Manager / 隔空投送 两个圆钮
cc-sliders        Display 亮度滑块 + Sound 音量滑块（带白色填充动画）
cc-bottom-row     深色模式 / 计算器 / 计时器 / 相机 四个圆钮
cc-footer         Edit Controls 按钮
```

**已完成的改造**（commit `f2887cc` 重写 + 崩溃修复 `666c3c8` + 位置微调 `01d999a`，VM 已验证）：

```text
新建 services/Controls.qml  → 真服务（Item visible:false 容器），聚合：
  - 音量（Quickshell.Services.Pipewire + PwObjectTracker 绑定 defaultAudioSink）
  - 亮度（brightnessctl via Quickshell.Io.Process + StdioCollector，无 backlight 自动降级）
  - Wi-Fi（Quickshell.Networking）
  - 蓝牙（Quickshell.Bluetooth）
  - 正在播放（Quickshell.Services.Mpris）

重写 ControlCenter.qml：
  - ConnectivityTile（Wi-Fi 标题卡 + 蓝牙圆钮，点击切 Wi-Fi/BT）
  - MusicTile（专辑封面 + 曲目 + 传输按钮，接 MPRIS，无播放器时占位）
  - GlassSlider ×2（亮度 + 音量，白色填充，MouseArea 驱动，无 QtQuick.Controls）
  - 可折叠 utility 行（Edit Controls 按钮控制显隐：深色/计算器/计时器/相机）
  - Material Icons 字体（assets/fonts/MaterialIconsRound.ttf，codepoint 已对官方表核对）

降级策略：所有 Quickshell 单例访问都 null-guard + try/catch，VM 缺硬件不崩。
崩溃教训：服务根必须用 Item 而不是 QtObject（QtObject 无默认 children 槽，
会导致 PwObjectTracker/Process/Timer 等子对象 fatal）。
```

**剩余未做**（留后续）：AirDrop / Stage Manager / 屏幕镜像圆钮（无后端，暂为禁用占位）、深色模式按钮（接 gsettings 是独立任务）、电池电量显示（留给顶栏后续做）。

下面其余条目（2–8）仍是占位符，未完成：

### 2. 菜单栏左侧 "Tahoe" 下拉 `MenuPopup.qml` —— 假菜单

Web 参考（`index.html` 第 38–71 行）有完整的 Apple 菜单 + 应用菜单 + Finder/File/Edit/Go/Help 多级下拉，每个 `<li><button>` 都有内容。

当前 `tahoe-shell/components/MenuPopup.qml` 写死 4 行 `MenuRow`："About Tahoe / {activeApp} / Window / Settings"，点任何一个都只是 `closeRequested()` 关闭。**没有应用菜单接入，没有 DBus appmenu / dbus-menu**（roadmap 列为 Phase 5 不优先）。

### 3. 通知中心 `NotificationToast.qml` —— ✅ 已完成（2026-06-14）

**原占位状态**：写死的 "Tahoe / Session ready"，`shell.qml` 里的 Timer 启动 900ms 后强制弹出，3.6 秒自动消失。**不是真通知系统**，没接 notification daemon。

**已完成的改造**：

```text
新建 services/Notifications.qml → 真服务（Item visible:false 容器），聚合：
  - Quickshell.Services.Notifications.NotificationServer（注册为 org.freedesktop.Notifications 守护进程）
  - incoming 通知 → 设 tracked=true 保留 → 把 live Notification 对象推入 FIFO activeModel 队列
  - activeModel 直接持 live 对象（非快照），所以 replace-id 更新同一对象时 UI 属性自动跟随，无需额外同步
  - 自动过期：只给队首计时（单 Timer），按客户端请求的 expireTimeout（capped 30s，default 5s）；Critical（urgency=2）不过期
  - n.closed 信号统一回收：从队列移除并给新队首重新计时
  - 暴露 activeCount / current 给 UI；提供 dismissCurrent / invokeAction / clearAll

重写 NotificationToast.qml：
  - 完全由 notificationsService.current 驱动，删除假 Timer 和 "Session ready" 文本
  - 渲染 appName / summary / body（多行省略）、app 图标（image://icon/<name> 或 image:// 内联图）、无图标时 Material Icons 通知 glyph 兜底
  - urgency=2 时卡片描边变红（accentColor）
  - 动作按钮行：notify-send -A 的每个 action 渲染成一个 pill，点击 invokeAction → NotificationAction.invoke()
  - 保留原 SpringAnimation x 入场动画

TopBar：加铃铛徽标（activeCount>0 时显示），红色计数 pip，点击 dismissCurrent

shell.qml：删除 notificationOpen 状态和 900ms 假弹 Timer，改为实例化 Notifications 服务并下发给 NotificationToast / TopBar

测试：scripts/test-notification.sh（notify-send 覆盖 basic/icon/urgent/actions/replace/spam/demo）
```

**剩余未做**（留后续）：通知中心历史列表（只弹当前，未做常驻通知列表/通知中心面板）、Do Not Disturb、按 appId 分组堆叠。

### 4. 顶栏 `TopBar.qml` —— 缺核心状态

Web 参考（`index.html` 第 73–174 行）的状态区有：Wi-Fi SVG 图标、电池（文字+进度条+充电图标+popup）、Spotlight 搜索图标、控制中心图标（带动画 gif）、时钟。

当前 `tahoe-shell/components/TopBar.qml` 状态区只有：系统托盘 `Tray` + workspace 数字按钮 + 时钟。**没有**：电池、亮度、音量、输入法、Spotlight 入口、控制中心图标组（Wi-Fi/BT 那组小图标）。

### 5. Launchpad —— 缺搜索/分页

Web 参考（`index.html` 第 211–250 行 + `script.js` `handleLaunchpadSearch` 第 578–585 行）：
- 有搜索框（`<input type="search">`），按 `data-keywords` 实时过滤。
- 打开动画 `@keyframes opacity`（scale 1.2→1 + opacity 0→1，300ms）。
- 关闭动画 `launchpad-closing`（scale 1→1.2 + opacity 1→0，300ms）。

当前 `tahoe-shell/components/Launchpad.qml`：
- ✅ 有 app grid，✅ 打开 scale 0.96→1 + opacity。
- ❌ **没有搜索框**，没有分页，没有文件夹，没有 Spotlight。只是把 `DesktopEntries.applications` 全列出。

### 6. Spotlight —— 完全缺失

Web 参考（`index.html` 第 319–323 行）有 `.spotlight_serach`：圆角搜索框 + 右侧 4 个 Tahoe 圆钮（App Store/Finder/Shortcuts/Copy）。`script.js` `handleopen_spotlight` 第 487–499 行处理打开关闭。

`tahoe-shell/` 完全没有 Spotlight 组件。Dock 也没有触发入口（顶栏那个状态区按钮只开控制中心）。

### 7. Dock —— 缺右段功能区

Web 参考（`index.html` 第 205–207 行）：`<hr class="column">` 分隔线 + Downloads + Trash。`script.js` 第 648–670 行还实现了 Dock 图标拖拽重排（`dragstart`/`dragend`/`drop`），并把 Downloads/Trash 标记为 `static` 不可拖。

当前 `tahoe-shell/components/Dock.qml`：分隔线有，但**分隔线右侧是空的**，没有 Downloads/Trash/最近应用区。也**没有**：拖拽重排、拖入 Dock 固定、App 数角标、Dock 自动隐藏、拖文件到 Dock 图标打开。

### 8. 服务层 `services/` —— 真接的只有 toplevel + workspace

- `Niri.qml`：只读 `ToplevelManager` + `WindowManager.windowsets`，**没接 niri IPC socket**（`niri msg`、`WindowsChanged` 事件流都没用）。拿不到窗口几何、布局、焦点变化的实时流。
- `Apps.qml`：靠 `appHasRunningWindow` 做 appId 模糊匹配判断"是否已启动"，会有误判。

---

## 二、动画：为什么"做得不好"以及根因

> **更新（2026-06-14）：动画 spring 化已完成。** 下表的"现状/问题"列描述的是改造**前**的状态。现已：Dock magnification 用 SpringAnimation 平滑 + 宽度随 magnification 联动（行波，抄 `script.js` 的 margin 联动）；Dock/窗口按钮点击 bounce 改欠阻尼 spring（damping 0.32）；控制中心从 TopRight 锚点 scale 展开（spring）；菜单从 TopLeft 锚点 scale 展开；Launchpad 方向修正为 1.1→1 + spring；opacity 仍用 NumberAnimation（fade 不适合 spring）。Snap preview / 窗口拖拽即时性 属 niri 侧，未在本次改造范围。

### 2.1 Quickshell 侧（普遍是廉价 NumberAnimation + OutCubic，几乎没有 spring）

| 位置 | Web 参考怎么做 | `tahoe-shell/` 现状 | 问题 |
|---|---|---|---|
| Dock magnification | `script.js` 第 358–404 行：`requestAnimationFrame` 每帧 lerp（`smoothness = 0.20`），scale 1→1.7，lift 0→15px，**margin 也跟着放大**（邻居联动），图标和标签一起变形 | `Dock.qml` 第 23–31 行 `proximityScale`：单变量 scale 1→1.38，每个图标独立 `NumberAnimation 120ms OutCubic` | Web 版**整条 Dock 一起呼吸**（margin 联动），`tahoe-shell` 每个图标独立 scale，邻居不联动，没有"波浪"；120ms 离散 tween 鼠标快扫会跳变 |
| Dock icon bounce | （Web 没有，参考真 macOS）多帧阻尼弹跳 | `Dock.qml` 第 224–242 行：`SequentialAnimation` 一次 up 70ms / down 110ms | 一次到位，不弹。macOS 是 1.5~2 次阻尼弹跳（spring） |
| ControlCenter 打开 | `style.css` 第 398–417 行：`transition: opacity 0.2s ease, transform 0.2s ease; transform: translateY(-10px)→0` | `ControlCenter.qml` 第 69–75 行：`y: -12→0` + `opacity 130ms` | Web 版也是平移，但 macOS 26 真实效果是**从顶部状态图标位置 scale 展开 + 模糊从无到有**。两边都只是平移，`tahoe-shell` 更短促 |
| Launchpad 打开 | `style.css` 第 1108–1116 行：`backdrop-filter: blur(25px)` + `@keyframes opacity` scale 1.2→1 | `Launchpad.qml` 第 60–74 行：scale 0.96→1 + opacity 160ms | Web 版**从大缩小到 1**（1.2→1，像从远处飞来），`tahoe-shell` 是**从小放大**（0.96→1，方向相反），而且没有模糊渐变、没有图标错位入场 |
| Launchpad 关闭 | `style.css` 第 1766–1780 行 `close-opacity` keyframe + `script.js` 第 561–568 行 300ms 后 `display:none` | `Launchpad.qml`：依赖 opacity Behavior 反向，**没有独立关闭动画** | 关闭和打开对称，没有 macOS 的"飞回 Dock"感 |
| MenuPopup | （参考 macOS：从菜单栏图标位置展开） | `MenuPopup.qml` 第 51–57 行：`y: -8→0` + opacity 140ms | 平移，没有从锚点展开 |
| 通知 | （Web 没有） | `NotificationToast.qml` 第 52–58 行：`SpringAnimation x` | 相对最接近，但只有一条假通知 |
| 窗口拖拽即时性 | `style.css` 第 2390–2394 行：拖拽时 `.is-dragging { transition: none }`，松手恢复 cubic-bezier(0.16,1,0.3,1) | niri window-movement spring damping 0.86 | niri 这块做得对，但 snap 触发瞬间没有过渡 |
| Snap preview | `style.css` 第 2455–2469 行：`backdrop-filter: blur(12px)` 半透明圆角矩形 + `transition: opacity 0.3s, left 0.3s, width 0.3s` | niri `render_snap_preview_for_output`：`SolidColorRenderElement` 蓝色实心矩形 | Web 版**有圆角 + 真模糊**，niri 版是**直角实心蓝色块**，没有玻璃感、没有圆角、没有内部毛玻璃预览 |

**核心问题（改造前）**：`tahoe-shell/` 动画几乎全用 `NumberAnimation` + `OutCubic`，**只有通知用了 `SpringAnimation`**。macOS 26 的灵魂是 spring/physics。Dock magnification 也是离散 tween 不是连续物理。Web 项目至少用了 `requestAnimationFrame` lerp 做连续平滑，`tahoe-shell` 连这个都没用。

> **改造后（2026-06-14）**：SpringAnimation 现在是 Quickshell 侧所有运动类动画（scale / position / size）的默认驱动；opacity fade 仍用 NumberAnimation（spring 会让 fade 抖动，且 macOS 自身 fade 也是 ease）。Dock magnification 邻居联动通过 delegate `width` 随 magnification 弹簧变化实现，Row 重排时整条 Dock 一起呼吸，等同 Web 的 margin 联动。

### 2.2 niri compositor 侧（参数调了，但 Genie / snap 动画缺失）

> **修复记录（2026-06-14）：region_to_non_overlapping_rects 整数溢出已修。** niri fork 的 `src/utils/region.rs` 在算 blur region 时三处裸 `i32` 加法（`r.loc.y + r.size.h` ×2、`r.loc.x + r.size.w` ×1），当 Quickshell 的 `BackgroundEffect.blurRegion` item 几何被 spring 振荡推动到极端值时，某帧 region 矩形 `loc + size` 溢出 i32::MAX → debug 构建整数溢出 panic（调用栈：`recompute_blur_region` → `region_to_non_overlapping_rects` → `render_layer_normal` → `redraw`）→ niri abort → 回到登录界面。三处改为 `saturating_add`（钳到 i32::MAX，语义等价"无限大矩形"，不产生负数干扰 subtract 分支）。QML 侧同步回退：`ControlCenter.qml` 的 `panel.y` + 可折叠行高度、`MenuPopup.qml` 的 `menuSurface.y` 三处 SpringAnimation 退回 NumberAnimation——**blur-region item 的几何一律禁用 spring，只留给非 blur 子元素**。升级时用 `FORCE_NIRI_BUILD=true bash scripts/arch-update.sh` 重编 niri（release 构建，整数溢出额外 wrapping 不 panic，双重保险）。

来自 `tahoe-phase0.kdl` 和 niri diff：

- ✅ window-open/close 用 custom shader 做 opacity fade。**但注意**：roadmap 声称"scale 0.96→1"，实际 `open_color`/`close_color` shader（config 第 71–104 行）只乘了 `opacity`，**没有 scale**。scale 是 minimize 才有（`animate_alpha_scale`）。
- ✅ minimize/restore 在 `floating.rs` 真的调了 `animate_alpha_scale(1→0, 1→0.96, ...)`，普通 fade+轻微缩小。
- ❌ **snap apply 没有 spring 过渡**：`interactive_move_end` 里直接 `request_size_once` + 设 `floating_pos`，靠 window-resize spring 兜底，没有专门 snap 进场动画。
- ❌ **snap preview 是直角实心蓝色块**（`SolidColorRenderElement`），跟 Web 版的圆角毛玻璃预览差很远。
- ❌ **Genie minimize 完全没做**（roadmap Phase 5）。
- ❌ **没有窗口拖拽时"指哪儿去哪儿"弹性**。

---

## 三、玻璃 / Liquid Glass：为什么"做得不好"

> **更新（2026-06-15）：玻璃参数重做已完成。** `postprocess.frag` 现在用圆顶高度场 + rim falloff + turbulence 计算伪法线，refraction 上限从 `0.05` 放到 `0.12`，edge highlight 改为法线光照 + specular + caustic，`blur` 默认提高到 `passes 5 / offset 7`，QML 面板白色覆盖和描边同步降低。下面列表保留为改造前问题和后续真机复测依据。

代码上**确实做了真 shader**（`postprocess.frag` 加了 tint/edge_highlight/refraction，xray/framebuffer 都传了 uniform），值得肯定。改造前效果不达标的根因：

1. **blur 强度太弱**：`passes 4 / offset 5` 在 1080p 下是"磨砂"不是"液态玻璃"。对比 Web 项目控制中心：`backdrop-filter: blur(20px)` 到 `blur(60px)`（`style.css` 第 249, 605 行），Dock 用 `backdrop-filter: url("#glass-distortion") blur(4px)`（第 723 行，SVG 滤镜位移+高光）。
2. **refraction 被 clamp 到 ≤0.05**（shader 第 47 行 `clamp(refraction, 0.0, 0.05)`），config 只给 `0.014`，几乎看不见折射。
3. **edge_highlight 是固定方向假光照**：shader 第 21–32 行 `glass_edge_strength` 写死 `top_light * 0.28 + left_light * 0.10`，不是真法线/环境光。玻璃边缘死板，不随窗口位置/壁纸变化。
4. **没有真曲面法线折射**：`niri_refraction_offset`（shader 第 34–45 行）用"到中心的归一化向量"当法线，平面假设，不会有曲面玻璃感。
5. **没有 SVG 玻璃扭曲滤镜**：Web 项目用了一个隐藏 SVG `<filter id="glass-distortion">`（`index.html` 第 355 行）做 `feTurbulence` + `feSpecularLighting` + `feDisplacementMap`，Dock 和 Widget 面板都引用它（`style.css` 第 723, 1511 行）。**这是真液态玻璃的关键**——噪声扰动 + 高光 + 位移。`tahoe-shell/` 完全没有等价物。
6. **没有 active/inactive 动态玻璃**：config 是两条静态 window-rule，切换窗口时参数不过渡。
7. **Hyper-V 验收只是"没破图"**，真机 GPU 性能和观感没验过。

简单说：**shader 框架已经从第一版参数试验推进到可见的 turbulence/specular/displacement 等价实现；剩余风险是真机 GPU 上的观感、性能和是否还需要独立 sampled-surface shader。**

---

## 四、Web 项目可复用资源清单

`macOS-26-Tahoe-for-the-Web-main/` **不能直接运行在 niri/Quickshell 里**（DOM/CSS/JS），但以下内容**可直接抽取或翻译成 QML**：

### 4.1 直接可复用的二进制资源

```text
background/iridescence.jpg        → 壁纸（tahoe-shell 已用）
background/albumcover.png         → 控制中心音乐控件封面
background/ccslider.png           → 控制中心滑块背景纹理
background/cchbutton.png          → 控制中心按钮纹理
background/sidebar.png            → Settings 侧栏纹理
background/lock.gif               → 锁屏动画（tahoe-shell 已有）
icon/dock/*.png                   → Dock 图标（已用）
icon/Launchpad/*.png              → Launchpad 图标（已用）
icon/symbols/*.png                → Spotlight 圆钮符号
icon/control_center.gif           → 控制中心入口动画图标（顶栏用）
icon/charging.png                 → 电池充电图标
icon/about/MacBookProM5.png       → About This Mac 图
cursor/normal-select.png          → 鼠标光标
```

### 4.2 视觉参数（CSS → QML 翻译）

```text
控制中心圆钮  backdrop-filter: blur(20px) + inset 双层 box-shadow
              background rgba(255,255,255,0.35~0.5)
              box-shadow: inset 2px 2px 1px rgba(255,255,255,0.2),
                          inset -1px -1px 1px rgba(0,0,0,0.1)
              → QML: Rectangle + BackgroundEffect.blurRegion + 双层 Rectangle 内描边
Dock          backdrop-filter: url(#glass-distortion) blur(4px)
              background rgba(255,255,255,0.15)
              border-radius 1.3rem
              box-shadow 双层 inset
Launchpad     backdrop-filter: blur(25px)
Snap preview  backdrop-filter: blur(12px) + border-radius 15px
              background rgba(255,255,255,0.15)
Spotlight     border-radius 100px, backdrop-filter blur(5px)
              background rgba(200,235,255,0.9)
窗口圆角      .window border-radius 1rem (16px)
              .calculator border-radius 1rem
              .settings-app border-radius 25px
红黄绿按钮    #ff5f56 / #ffbd2e / #27c93f (配 0.5px box-shadow 描边)
```

### 4.3 动画曲线（CSS cubic-bezier → QML Easing/Bezier）

```text
窗口开关      cubic-bezier(0.16, 1, 0.3, 1)  → QML BezierCurve
Widget 面板   cubic-bezier(0.79, 0.14, 0.15, 0.86)
Launchpad 抖动 cubic-bezier(0.42, 0, 1, 0.2)
通用过渡      0.2s ease / 0.3s ease
Dock 抖动动画 @keyframes to-top-bottom（4 帧非线性 translateY）
```

### 4.4 交互逻辑（JS → QML/服务层）

```text
Dock magnification   script.js 358-404  → Dock.qml proximityScale 改 rAF lerp + margin 联动
Launchpad 搜索       script.js 578-585  → Launchpad.qml 加搜索框 + data-keywords 过滤
Dock 拖拽重排        script.js 648-670  → Dock.qml 加 DropArea / drag 拖拽
Snap preview         script.js 676-766  → niri snap_preview 改圆角+模糊元素
电池计算             script.js 823-832  → 新 Battery 服务（UPower DBus）
Spotlight            script.js 487-499  → 新 Spotlight.qml
控制中心开关         index.html 92-169  → ControlCenter.qml 完全重写
```

---

## 五、Web 项目里值得抄但 tahoe-shell 完全没有的东西

按"性价比"排序：

1. **控制中心的 cc-sliders**（亮度/音量白色填充滑块）——`style.css` 第 619–649 行的 `box-shadow: -400px 0 0 400px rgba(255,255,255,0.95)` 技巧做出滑块左侧的白色实心填充，这是 macOS 控制中心的标志视觉。
2. **正在播放音乐控件**（cc-music-widget）——专辑封面 + 曲目 + 前进/播放/后退。接 `playerctl` / MPRIS DBus 即可。
3. **Spotlight 搜索**——圆角搜索框 + 4 个 Tahoe 圆钮。
4. **Apple 菜单 + 应用菜单**——`index.html` 第 40–71 行的完整下拉结构，可翻译成 MenuPopup 的真实菜单项。
5. **电池 popup**——`style.css` 第 243–320 行，显示电量百分比 + 电源来源 + "Battery Preferences"。
6. **Widget 面板**（点击时钟弹出日历）——`index.html` 第 313–316 行，`script.js` 第 616–619 行。
7. **About This Mac 窗口**——`index.html` 第 344–353 行，带 M5 芯片图 + 规格表。
8. **SVG glass-distortion 滤镜**——`index.html` 第 355 行，真液态玻璃的关键，需要翻译成 niri shader 或 Qt ShaderEffect。
9. **Dock 右段（Downloads/Trash）**——分隔线 + 静态图标。
10. **右键上下文菜单**——`index.html` 第 177–184 行，`script.js` 第 814–820 行。

---

## 六、距离"完整可日用桌面"还差什么（对标 macOS 26）

### A. 日用功能性（最致命，目前基本不可日用）

```text
❌ 控制中心无任何真实控件（音量/亮度/键盘亮度/Wi-Fi/蓝牙/勿扰/夜间模式）
✅ 真通知系统（2026-06-14 已接 Quickshell NotificationServer，见 §1.3）
❌ 无电源/注销/重启/关机菜单
❌ 无锁屏 UI（Super+Alt+L 调 swaylock，不是自己的）
❌ 无截屏标注/录屏/Quick Look (空格预览)
❌ 无输入法指示/切换
❌ 无 Spotlight / 全局搜索（Launchpad 也没搜索框）
❌ 无 Stage Manager / Spaces / Mission Control UI
```

### B. 窗口管理（compositor 侧缺）

```text
❌ 没有真 stacking WM 语义（全局 raise/lower、点击 raise、Alt-Tab 切换器 UI）
❌ 没有服务端窗口装饰 / 红黄绿按钮
❌ snap 只有左/右/上三向，无四角、无拖到另一窗口吸附分屏
❌ Genie minimize / Dock target rect IPC（Phase 5）
❌ 多显示器/fractional scale 没真机验过
```

### C. 视觉打磨

```text
❌ Dock 缺右段功能区（最近应用/下载/垃圾桶）
❌ 图标统一性差（混 Tahoe png + 旧 Big Sur + finder/vscode 多种风格）
❌ 字体没做 SF Pro 级别替换（顶栏用默认 Qt 字体；Web 用了 SF Pro Display CDN）
❌ 动画曲线几乎不用 spring
❌ snap preview 是直角蓝色块，不是圆角毛玻璃
❌ 壁纸只有 iridescence.jpg 一张，无动态壁纸/深浅色切换
```

### D. 工程质量风险

```text
⚠️ 从未在真机跑过（所有验收在 Hyper-V，虚拟 GPU 不可信）
⚠️ 测试几乎为零（roadmap "测试清单"整段全 [ ] 未做）
⚠️ niri 是上游活跃项目，6 commit fork 长期 rebase 成本上升
⚠️ Quickshell 无原生 niri IPC 模块，services/Niri.qml 拿不到窗口几何/focus 实时流
```

---

## 七、修复优先级建议（性价比排序）

1. ~~**控制中心做成真的**~~ ✅ 已完成（2026-06-14，commit `f2887cc`+`666c3c8`+`01d999a`）。抄 Web `index.html` 92–169 行的 cc-grid 布局，接 Pipewire/brightnessctl/Networking/Bluetooth/Mpris，加音量/亮度/Wi-Fi/BT toggle + 正在播放。
2. ~~**接真通知系统**~~ ✅ 已完成（2026-06-14）。接 Quickshell `NotificationServer`，注册为 `org.freedesktop.Notifications` 守护进程，替掉假 toast。见 §1.3。
3. ~~**动画 spring 化**~~ ✅ 已完成（2026-06-14）。Dock magnification 改 SpringAnimation 平滑 + 宽度随 magnification 联动（行波效应，抄 `script.js` 358–404 的 margin 联动思路）；Dock/窗口按钮点击 bounce 改欠阻尼 spring（damping 0.32，~1.5 次阻尼弹跳，替代原来的两步 SequentialAnimation）；控制中心从 TopRight 锚点 scale 展开（spring 380/damping 0.78 轻微 overshoot）；菜单从 TopLeft 锚点 scale 展开；Launchpad 修正方向为 1.1→1（原 0.96→1 方向反了，是 zoom-in 不是"从远处飞来"）+ spring。opacity 仍保留 NumberAnimation（fade 不适合 spring，会抖）。详见 §二.1。
4. ~~**玻璃参数重做**~~ ✅ 已完成（2026-06-15）。refraction 上限放开、edge highlight 改为伪法线光照、blur passes 加大；Web 的 SVG glass-distortion 思路已翻译进 niri postprocess shader（turbulence + specular + displacement），后续只保留真机观感/性能调参。
5. **snap preview 重做**——改成圆角 + 模糊元素（抄 `style.css` 2455–2469 行），不是实心蓝色块。
6. **加 Spotlight + Launchpad 搜索框**——抄 `index.html` 211–213 + 319–323。
7. **服务层接 niri IPC socket**——为窗口预览/Stage Manager 做准备。
8. **服务端窗口装饰 + 红黄绿按钮**（Phase 5）。
9. **真机验收 + 性能调优**。

---

## 八、一句话总结

> 当前项目状态：**niri fork 那一层（minimize/snap/glass shader）是真东西且完成度不错；Quickshell shell 那一层原先是"macOS 的皮 + 没有功能的骨头"，现已完成四项改造（控制中心 + 真通知系统 + 动画 spring 化 + 玻璃参数重做），但菜单是假的、Spotlight 没有、snap preview 仍是实心蓝色块**。Web 参考项目是一份现成的"功能清单 + 视觉参数表 + 动画曲线表"，应该当成蓝图继续逐项翻译成 QML。下一项：snap preview 重做。
