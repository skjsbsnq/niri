# Liquid Glass 源码研究与顺序改进路线图

日期：2026-06-28

范围：本文件记录对本仓库 Tahoe/niri/Quickshell 玻璃链路的只读研究，以及对两个外部开源实现的源码级参考结论。本文是研究文档兼后续路线图，不包含实现代码变更。

核心约束：

- 外部源码只能参考，不能照搬。
- 不新增第二套玻璃协议，不虚增接口。
- 优先复用现有 `tahoe_glass_v1`、`BackgroundEffect` fallback、niri KDL config、现有 shader/uniform 管线。
- 按任务顺序推进：一个任务验收通过后，才能开始下一个任务。
- 保持 KISS：先稳定已有通道和参数映射，再考虑更复杂的视觉模型。

## 外部源码位置

本轮参考源码均拉取到项目目录外，避免污染 `/home/wwt/niri` 工作区。

### Niri-glass

- 本地路径：`/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass`
- 远程：`https://github.com/zaroutt/Niri-glass`
- 当前本地提交：`e018a31`
- 重点文件：
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/src/render_helpers/liquid_glass.rs`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/src/render_helpers/shaders/clipped_surface.frag`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/src/render_helpers/background_effect.rs`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/src/render_helpers/framebuffer_effect.rs`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/src/render_helpers/xray.rs`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/niri-config/src/appearance.rs`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass/config.kdl`

说明：`Niri-glass` README 明确说 shader 基于 `kwin-effects-glass`。本轮不把 `kwin-effects-glass` 作为第三个重点输入，以避免扩大范围；只记录 `Niri-glass` 对该思路的 niri 移植方式。

### kwin-effects-forceblur

- 本地路径：`/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur`
- 远程：`https://github.com/taj-ny/kwin-effects-forceblur`
- 当前本地提交：`51a1d49`
- 重点文件：
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/blur.cpp`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/blur.h`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/settings.h`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/settings.cpp`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/blur.kcfg`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/shaders/downsample.frag`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/shaders/upsample.glsl`
  - `/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur/src/shaders/roundedcorners.glsl`

说明：用户提到的 `kwin-effects-foreblur` 应按现有开源项目名理解为 `kwin-effects-forceblur` / Better Blur。

### Apple 官方设计参考

这些不是源码参考，只用于校准视觉目标和术语：

- `https://www.apple.com/os/macos/`
  - Apple 在 macOS 27 页面中说明 Liquid Glass 更新重点是可读性、更统一的折射、更好的对比度，以及从 ultraclear 到 fully tinted 的外观滑杆。
- `https://developer.apple.com/news/?id=e2lxw9l1`
  - Apple Developer 2026-06-23 发布 macOS 27 design kits，明确包含 Liquid Glass 更新。
- `https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/`
  - macOS Tahoe 26 新闻稿说明 Liquid Glass 是会反射和折射周围环境的 translucent material，并重点用于 Dock、sidebars、toolbars、menu bar。

## 本仓库当前架构判断

本仓库已经具备正确的架构骨架：真正的玻璃效果由 niri 合成器拥有，Quickshell 只声明区域。

当前关键路径：

- 协议：`niri/resources/tahoe-glass-v1.xml`
  - 明确约定 client 只描述 `wl_surface` 上的 rounded glass regions。
  - compositor 拥有 blur、tint、refraction、clip、shadow。
- niri server：`niri/src/protocols/tahoe_glass.rs`
  - region 结构已包含 `rect`、四角 `radius`、`material`、`blur/shadow/clip`、`interaction`、`material_alpha`。
  - `MAX_REGIONS_PER_SURFACE` 为 32。
  - region double-buffered，随 `wl_surface` commit 提交。
- niri renderer：`niri/src/render_helpers/tahoe_glass.rs`
  - 按 layer surface namespace 过滤。
  - 根据 material 解析 compositor-owned background effect 和 shadow。
  - 用 region geometry 计算 sample padding、clip、shadow 和 material fade/interaction。
- niri shader：`niri/src/render_helpers/shaders/postprocess.frag` 与 `clipped_surface.frag`
  - 已有 rounded SDF、rim、高光、inner shadow、refraction、chromatic、lens-depth。
- Quickshell client：`quickshell/src/wayland/tahoe_glass/qml.cpp`
  - `TahoeGlassRegion` 把 QML item 或显式 rect 转为 surface-local logical region。
  - fallback 到 `BackgroundEffect.blurRegion`。
- Tahoe QML：`tahoe-shell/components/*.qml`
  - Dock、Control Center、Spotlight、Settings、TaskSwitcher、WindowOverview 等已声明 `TahoeGlass.regions`。

结论：不要新增第三套玻璃渲染组件。后续重点应是增强 niri 的材质/采样/性能，并把 Quickshell 侧 region 声明封装得更稳。

## 到底改 niri 还是 Quickshell

本路线图的目标范围已经收敛：只把自己写的 launcher、panel、menu、toast、overview、dynamic island 等 Tahoe shell UI 做成液态玻璃。不计划把普通第三方应用窗口玻璃化。

结论：

1. Quickshell 负责声明玻璃几何。
   - 每个可见玻璃块必须是 `TahoeGlassRegion`。
   - QML 只提供 item/rect、material、radius、blur/shadow/clip、interaction、materialAlpha。
   - QML 不做真 blur/refraction shader。

2. niri 负责真正液态玻璃。
   - `niri/src/render_helpers/tahoe_glass.rs` 渲染 region 级 shadow、clip、background-effect。
   - `niri/src/render_helpers/background_effect.rs` 和 `framebuffer_effect.rs` 负责 framebuffer capture、blur、xray/non-xray、uniform。
   - `niri/src/render_helpers/shaders/postprocess.frag` 和 `clipped_surface.frag` 负责 SDF edge、highlight、inner shadow、refraction、chromatic、lens-depth。
   - `config/niri/tahoe-phase0.kdl` 的 `tahoe-glass { material ... }` 是主要调参入口。

3. 不增加独立组件。
   - 独立 overlay 进程无法稳定拿到 compositor 的背景采样、damage、clip、workspace animation 时机。
   - 它会重复 niri 已有权限和状态，增加同步问题。
   - 只有截图基线、性能采样、配置检查这类离线工具适合独立存在。

4. 普通应用窗口是非目标。
   - 不改普通 `window-rule` 来强行把 app window 玻璃化。
   - 不把 TahoeGlass 协议扩给任意 app。
   - 保留现有普通窗口规则只是因为配置里已有历史设置；它不是本路线图主线。

## 自己 UI 的本地源码落点

Quickshell 侧：

- `tahoe-shell/components/TahoeGlass.js`
  - 统一 material 名称、radius、QML fallback fill/stroke。
  - 当前 material：`panel`、`pill`、`launcher`、`dock`、`menu`、`toast`、`backdrop`。
- `tahoe-shell/components/*.qml`
  - 具体 `PanelWindow` 和 `TahoeGlass.regions` 声明。
  - 目标是让所有 launcher/panel/menu 的玻璃声明都走同一套小封装或同一套约定。
- `quickshell/src/wayland/tahoe_glass/qml.cpp`
  - `TahoeGlassRegion` 把 QML item/rect 转为 surface-local logical region。
  - 协议不可用时 fallback 到 `BackgroundEffect.blurRegion`。
- `quickshell/src/wayland/background_effect/qml.cpp`
  - 仅作为 fallback 生命周期参考，不让业务 QML 直接散落调用。

niri 侧：

- `niri/resources/tahoe-glass-v1.xml`
  - 当前私有协议，client 只描述 rounded glass regions。
- `niri/src/protocols/tahoe_glass.rs`
  - 存储 double-buffered committed regions，限制每 surface 最多 32 个 region。
- `niri/src/render_helpers/tahoe_glass.rs`
  - 按 namespace allowlist 渲染 TahoeGlass region。
  - 处理 region material、shadow、clip、interaction、materialAlpha、sample padding。
- `niri/niri-config/src/tahoe_glass.rs`
  - 解析 `tahoe-glass` 配置、material fallback、namespace allowlist。
- `config/niri/tahoe-phase0.kdl`
  - 当前 `tahoe-glass` material 的主配置文件。
  - `layer-rule` 中的 `background-effect` 只应作为 BackgroundEffect fallback，不是主路径。

## 当前 Tahoe UI 覆盖清单

已接入 `TahoeGlass.regions` 的主要 shell UI：

- 启动器/搜索：`Spotlight.qml`、`Launchpad.qml`。
- 面板：`TopBar.qml`、`Dock.qml`、`ControlCenter.qml`、`NotificationCenter.qml`、`LeftSidebar.qml`、`SettingsPanel.qml`。
- 切换/概览：`TaskSwitcher.qml`、`WindowOverview.qml`。
- 菜单：`MenuPopup.qml`、`AppMenuPopup.qml`、`TrayMenu.qml`、`DockAppMenu.qml`、`DockWindowMenu.qml`、`ProcessMenu.qml`。
- 小弹窗：`BatteryPopup.qml`、`WifiPopup.qml`、`FanPopup.qml`、`ClipboardPopup.qml`。
- 状态浮层：`NotificationToast.qml`、`DynamicIslandOverlay.qml`。

明确不应做成玻璃 region 的 surface：

- `Wallpaper.qml`：背景，不是玻璃。
- `PopupDismissLayer.qml`：透明点击层，不是可见玻璃。
- `Screenshot.qml`：服务/动作入口，不是面板 surface。

需要单独评估但不作为第一阶段目标：

- `LockScreen.qml`：走 `WlSessionLockSurface`，不是 layer-shell `PanelWindow`。它可以有玻璃视觉，但安全界面应先保证可读性、输入稳定和锁屏语义，再决定是否接 TahoeGlass 或另做锁屏内 QML 视觉。

当前发现的具体改进点：

- `Launchpad.qml` 的主面板曾使用 `MaterialPanel`；T8 已新增 `launcher` material，避免大 launcher card 吃全局 panel profile 后出现过强 lens/rim。
- 多数组件重复写 `TahoeGlassRegion` + `Rectangle` fill/stroke + `tahoeGlassMaterial/tahoeGlassRadius`。这适合抽一个很薄的 `GlassPanel`/`GlassSurface` QML 封装，但不能把 shader 参数暴露到 QML。
- `TopBar.qml`、`Dock.qml` 已经避免把整个 layer surface 当玻璃，只给内部 surface 建 region；这个方向必须保持。

## 非目标边界

本路线图不做：

- 不把普通 app window 改成液态玻璃。
- 不用 `window-rule opacity` 强行把第三方应用半透明。
- 不让任意客户端请求 TahoeGlass。
- 不新增独立 glass overlay 进程。
- 不复制 `Niri-glass` 或 `forceblur` 的源码。
- 不在每个 QML 组件里直接调用 `BackgroundEffect.blurRegion`。

## Niri-glass 源码观察

### 可参考点

1. `Niri-glass` 走的是 niri `background-effect` 既有路径。
   - 它没有设计新的 Wayland 协议。
   - 它在 `BackgroundEffect` 内增加 `liquid_glass: Option<LiquidGlassOptions>`。
   - 对 Tahoe 来说，这说明现有 background-effect/framebuffer/xray 管线足够承载更多 shader 参数。

2. 它把 config 参数一路传到 `framebuffer_effect.rs` 和 `xray.rs`。
   - 这与本仓库当前 `GlassOptions` 已做的事情一致。
   - 可取的是路径简单：config -> options -> uniforms -> shader。

3. 它特别处理了两个坐标空间：
   - `uv_tex`：用于采样 framebuffer texture。
   - `uv_geo`：用于在窗口/region 内计算 SDF、边缘和裁剪。
   - 这个点非常重要。本仓库 TahoeGlass 也应继续保持“采样坐标”和“region 内几何坐标”分离，避免非原点窗口/面板的边缘计算错位。

4. 它使用 rounded-rect SDF 做边缘折射/轮廓。
   - 这和本仓库 `rounded_rect_sdf.frag` 思路一致。
   - 后续可以参考它对 KWin SDF corner order 的注释，但不能复制 shader。

### 不应照搬点

1. 参数面过大。
   - `refraction_strength`、`power_factor`、`refraction_a/b/c/d`、`refraction_power`、`glow_weight`、`glow_bias`、`glow_edge0/1` 等暴露过多。
   - 多数参数在 README 或 shader 中并未形成清晰用户语义。
   - Tahoe 不应新增这么多 KDL knob。

2. README 明确提示实验性强。
   - 文档写有 “Vibe coded project so expect weirdly behavior.”。
   - 因此它适合作为探索参考，不适合作为稳定设计基准。

3. shader 注释中多处写 “EXACT copy from kwin”。
   - 本项目不能照搬外部 shader 代码。
   - 应只吸收原则：SDF、UV 分离、最后阶段折射、色散可选、强度 clamp。

4. 它作用于 window/layer rule 的 background-effect。
   - 本项目已经有 TahoeGlass region 协议，能表达内部 panel/dock/pill 的精确 rounded rect。
   - 如果退回 window-rule/layer-rule 级别，会重新出现“大透明 surface 与内部玻璃 item 几何错位”的老问题。

## kwin-effects-forceblur 源码观察

### 可参考点

1. blur slider 不直接等于 pass 数。
   - `BlurEffect::initBlurStrengthValues()` 把用户 blur strength 映射为 dual Kawase 的 `iteration` 和 `offset`。
   - 注释解释了 offset 过低会块状、过高会产生 diagonal artifacts。
   - Tahoe 后续如果做 macOS 27 clarity/blur slider，也应映射到受控 token，而不是暴露 raw passes/offset。

2. 色彩调节是独立的一等能力。
   - `GeneralSettings` 有 `brightness`、`saturation`、`contrast`。
   - `settings.cpp` 直接读取这些值并构造 color matrix。
   - 这与 macOS 27 “透明/着色可调但保持可读性”的方向一致。
   - Tahoe 当前已有 `saturation`、`tint_amount`，但缺少清晰的 `contrast` / `clarity` 抽象。

3. static blur 是性能阀门。
   - README 说明 static blur 缓存纹理、降低 GPU 用量。
   - `blur.cpp` 用 `m_staticBlurTextures` 按 output 缓存。
   - 它还提供 “有窗口在后面时切回 real blur” 的选项。
   - Tahoe 不必立即做 static blur，但应把“低功耗/静态背景模式”作为后续任务，而不是把所有玻璃都做实时高强度 refraction。

4. refraction 只在最后 upsample pass 应用。
   - `blur.cpp` 注释写明 refraction 只在最后 pass 应用，否则会出现 weird stacking。
   - Tahoe 当前是在 postprocess sampling 时做一次 refraction，这个方向是合理的。

5. 小纹理和资源重建有防护。
   - 它把非常小的 framebuffer texture 尺寸 clamp 到至少 1。
   - 只有尺寸、format、iteration 不匹配时才重建 offscreen targets。
   - TahoeGlass 应继续避免 region 动画造成反复 realloc。

6. Wayland 性能风险被明确写入 README。
   - 高 GPU 负载会导致 cursor latency/stutter。
   - Tahoe 后续调强 refraction、chromatic、blur passes 时必须以帧时长和交互延迟为验收项。

### 不应照搬点

1. KWin 的 window class matching 不适合 TahoeGlass。
   - `forceBlur.windowClasses`、blacklist/whitelist、blur menus/docks 是 KWin effect 的使用模型。
   - 本项目已有 explicit `tahoe-*` namespace 和 `TahoeGlass.regions`。
   - 不应新增按 app class 强行套玻璃的规则系统。

2. KWin 的 decoration/window 圆角模型不适合 Quickshell shell UI。
   - Tahoe 的核心问题是内部 rounded region，不是整个 layer surface。
   - 继续复用 TahoeGlass region，不新增 per-window glass protocol。

3. 其 shader 是 KWin/Qt/OpenGL effect 环境下的实现。
   - 不能直接迁移 VBO、QRegion、KWin render target 逻辑。
   - 只参考算法和性能边界。

## 反腐化原则

后续任何改动都必须先通过这些问题：

1. 能否复用 `TahoeGlass.regions`？
   - 能：不要新协议。
   - 不能：先写明为什么现有 region/material/flags/interaction/materialAlpha 不够。

2. 能否复用 `BackgroundEffect` 作为 fallback？
   - 能：不要在 QML 中散落新的 blurRegion。
   - 不能：先补 TahoeGlass attached object 的 fallback，不让业务组件知道 fallback 细节。

3. 能否复用现有 `GlassOptions`？
   - 能：只新增少量语义明确字段。
   - 不能：先考虑把多个 raw shader 参数压缩成一个用户语义 token。

4. 能否通过 KDL material 配置表达？
   - 能：不要新增 IPC 或 Wayland request。
   - 不能：证明它必须是动态 per-region 状态，再考虑扩展 TahoeGlass。

5. 是否影响 glass region 几何？
   - 如果影响 `x/y/width/height/radius`，必须 bounded，不能用 spring。
   - 首选动画 `materialAlpha`、`interaction`、opacity、content transform，而不是动画 region bounds。

6. 是否会增加接口面？
   - 新增接口必须有两个以上调用点或明确长期使用场景。
   - 一次性调参不新增接口。

## KISS 设计方向

推荐保留三层模型：

1. QML shell：
   - 负责布局、内容、输入、轻量 fallback fill/stroke。
   - 只声明 `TahoeGlassRegion`。

2. Quickshell TahoeGlass client：
   - 负责 QML item -> surface-local logical rect。
   - 负责 Wayland lifecycle 和 fallback。
   - 不做真玻璃 shader。

3. niri compositor：
   - 负责 background capture、blur、refraction、chromatic、SDF edge、shadow、clip、damage。
   - 负责 material preset 和性能阀门。

不推荐：

- 独立 glass overlay 进程。
- 第二个私有 glass protocol。
- 在每个 QML 组件里堆 `BackgroundEffect.blurRegion`。
- 把 KWin 的 class matching/window rules 搬进 Tahoe。
- 暴露大量 raw shader knobs 给用户。

## 顺序改进路线图

每个任务必须完成验收后才能进入下一个任务。

### T0：固定参考与护栏

目标：让后续研究不漂移，避免协议和参考源码来源不清。

改动范围：

- 新增或更新 guardrail 脚本。
- 不改渲染行为。

任务：

1. 在 `scripts/check-tahoe-glass-guardrails.sh` 增加 XML drift 检查：
   - `niri/resources/tahoe-glass-v1.xml`
   - `quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml`
2. 检查版本不变量：
   - manager XML version 为 `1`。
   - surface XML version 为 `3`。
   - `niri/src/protocols/tahoe_glass.rs` 中 manager global `VERSION` 为 `1`。
3. 检查 region limit 不变量：
   - niri `MAX_REGIONS_PER_SURFACE` 为 32。
   - Quickshell TahoeGlass client 没有散落裸 `32`，或集中成常量。
4. 记录外部参考仓库的 URL、commit 和本地路径。

验收：

- guardrail 脚本退出 0。
- 文档中源码路径和 commit 与本地一致。
- 不修改 TahoeGlass 协议语义。

### T1：Quickshell TahoeGlass lifecycle 去重

目标：减少维护风险，不改变协议和视觉。

背景：

- `quickshell/src/wayland/tahoe_glass/qml.cpp`
- `quickshell/src/wayland/background_effect/qml.cpp`

这两处都处理 `ProxyWindowBase`、`QWindow`、`QWaylandWindow`、surface created/destroyed、reload object stealing、polish 调度。

任务：

1. 抽一个很薄的 Wayland attached lifecycle helper。
2. TahoeGlass 和 BackgroundEffect 共享 lifecycle 骨架。
3. TahoeGlass region 逻辑仍留在 TahoeGlass。
4. BackgroundEffect blurRegion 逻辑仍留在 BackgroundEffect。

验收：

- TahoeGlass 行为不变。
- BackgroundEffect fallback 行为不变。
- Quickshell reload 时不重复 attach，不丢 surface。
- 不新增 Wayland protocol。

### T2：QML 玻璃声明封装

目标：降低组件重复，避免新组件绕过 TahoeGlass。

改动范围：

- 新增 `tahoe-shell/components/GlassPanel.qml` 或同等小封装。
- 不改变 niri。

设计：

- 封装 `TahoeGlassRegion` + 轻量 QML fill/stroke。
- 暴露少量属性：
  - `material`
  - `radius`
  - `blur`
  - `shadow`
  - `clip`
  - `interaction`
  - `materialAlpha`
  - `enabled`
- 不暴露 raw shader 参数。

迁移顺序：

1. 先迁移一个低风险弹窗，例如 `MenuPopup.qml`。
2. 再迁移 Control Center。
3. 再迁移 Dock/TopBar。
4. 最后迁移 Spotlight/Launchpad 这类多 region 或全屏组件。

验收：

- `scripts/check-tahoe-glass-guardrails.sh` 通过。
- 每个迁移组件仍使用 explicit `tahoe-*` namespace。
- 不新增直接 `BackgroundEffect.blurRegion`。
- region geometry 仍使用 bounded NumberAnimation 或静态绑定。

### T3：niri material token 初步收敛

目标：把 macOS 27 风格的透明度/着色/可读性做成少量语义参数，而不是一堆 shader knob。

参考：

- `forceblur` 的 `brightness/saturation/contrast`。
- Apple macOS 27 官方页面的方向：Liquid Glass 更新重点是可读性、更统一的折射、更好的对比度，并提供从更透明到更着色的外观调节。
- 本仓库已有 `tint_amount`、`saturation`、`edge_highlight`、`refraction`、`inner_shadow`、`chromatic`、`lens_depth`。

建议新增最少字段：

- `clarity`：统一影响 contrast、tint、refraction 强度。
- 或者只新增 `contrast`，把 `clarity` 留在 GUI/settings 层映射到现有 material 字段。

优先方案：

1. 先不扩协议。
2. 先不扩 TahoeGlass region request。
3. 只在 KDL material 层增加或复用字段。
4. 先通过 `config/niri/tahoe-phase0.kdl` 调出两套 profile：
   - `clear`：低 tint、低 contrast、轻 refraction。
   - `tinted`：高 tint、较高 contrast、低 refraction，偏可读。

验收：

- `niri validate -c config/niri/tahoe-phase0.kdl` 通过。
- 不破坏 fallback background-effect。
- 大面积 surface 不出现巨大 lens/rim。

### T4：shader 性能与可读性调参

目标：提升“像玻璃”的程度，同时不牺牲可读性和交互延迟。

参考：

- `Niri-glass` 的 UV 分离。
- `forceblur` 的 “refraction only on last pass”。
- 本仓库当前 `postprocess.frag` 已有 SDF 和 `glass_surface_detail()` 大面淡出。

任务：

1. 审计 `clipped_surface.frag` 与 `postprocess.frag` 中采样坐标与 region geometry 坐标。
2. 保持 chromatic 默认 0。
3. 对小面板允许更强 edge/refraction，对 fullscreen/backdrop 自动衰减。
4. 增加视觉基线截图：
   - Dock
   - TopBar
   - ControlCenter
   - Spotlight
   - NotificationToast
   - Launchpad/launcher

验收：

- 截图无方形 halo。
- 文本可读，不被 refraction 明显扭曲。
- Dock/TopBar 大透明 surface 不按全宽做玻璃。
- real GPU 与 VM 下均无明显 stutter。

### T5：低功耗/静态玻璃模式研究

目标：只研究，不急于实现。

参考：

- `forceblur` static blur cache。

Tahoe 可行方向：

- 对 fullscreen backdrop 或 idle 状态的大面积 panel，缓存 blurred background。
- 有窗口移动、workspace 动画、overview、视频窗口在后面时切回 real blur。

暂不做：

- 不新增 screencopy-based 独立服务。
- 不做每个 region 一张长期缓存纹理，除非有明确 perf 数据证明需要。

验收：

- 先有性能测量和风险文档。
- 没有测量前不实现。

完成记录：

- 2026-06-29 已完成 T5 研究，见 `tahoe-shell/docs/liquid-glass-t5-static-glass-research-2026-06-29.md`。
- 当前结论是不实现 static blur；已有测量被动态壁纸和当前窗口负载污染，只作为起始数据。
- static blur 仅保留为 T14 的有条件研究方向，必须先通过干净场景性能测量。

### T6：Tahoe shell 覆盖清单与缺口确认

目标：先确认自己的 UI 哪些应该是玻璃，哪些不应该是玻璃，避免后续边做边改范围。

任务：

1. 生成并维护覆盖清单：
   - 已有 `PanelWindow`。
   - 已有 `TahoeGlass.regions`。
   - material 类型。
   - region 数量。
   - 是否是大面积/全屏。
   - 是否需要 fallback layer-rule。
2. 标出非目标 surface：
   - `Wallpaper.qml`
   - `PopupDismissLayer.qml`
   - `Screenshot.qml`
3. 单独标出高风险 surface：
   - `Launchpad.qml`：大面积 launcher。
   - `WindowOverview.qml`：可能包含大量窗口缩略图。
   - `SettingsPanel.qml`：文本和控件密度高。
   - `DynamicIslandOverlay.qml`：尺寸变化频繁。
4. 把 `Launchpad.qml` 当前 `MaterialPanel` 的使用记录为待验证项：
   - 如果视觉是居中 launcher panel，可继续用 `panel`。
   - 如果视觉趋向 fullscreen/backdrop，应改为 `backdrop` 或新增 `launcher` material。

验收：

- 文档列出的组件与 `rg -l "TahoeGlass\\.regions" tahoe-shell/components` 一致。
- 每个可见 launcher/panel/menu/toast 都有明确 material。
- 每个非目标 surface 都有原因。
- 不新增代码行为。

完成记录：

- 2026-06-29 已完成 T6 覆盖清单与缺口确认，见 `tahoe-shell/docs/liquid-glass-t6-shell-coverage-2026-06-29.md`。
- 当前 `TahoeGlass.regions` 覆盖 22 个组件、23 个 compositor-owned region；`Spotlight.qml` 是唯一双 region 组件。
- `Wallpaper.qml`、`PopupDismissLayer.qml`、`Screenshot.qml` 已明确为非目标；`LockScreen.qml` 仍按安全界面单独评估。
- `Launchpad.qml` 的 `MaterialPanel` 待验证项已由 T8 关闭：当前使用 `launcher` material；若后续视觉转向 fullscreen/backdrop，再改为 `backdrop`。

### T7：QML 玻璃封装落地与组件迁移

目标：在 T2 的封装设计完成后，把它按风险顺序落到真实组件，减少重复，防止后续新增面板绕过 TahoeGlass。

建议新增一个很薄的 QML 封装，例如 `GlassSurface.qml` 或 `GlassPanel.qml`。

封装职责：

- 包一层 visual `Item`/`Rectangle`。
- 暴露 `material`、`radius`、`blur`、`shadow`、`clip`、`interaction`、`materialAlpha`、`enabled`。
- 内部声明 `TahoeGlassRegion`。
- 内部使用 `TahoeGlass.js` 的 fill/stroke token。
- 支持 `item` 模式和显式 rect 模式。

不允许封装做的事：

- 不暴露 raw shader 参数。
- 不直接调用 `BackgroundEffect.blurRegion`。
- 不读取 niri config。
- 不把动画 spring 绑到 glass region 几何。

迁移顺序：

1. `MenuPopup.qml` 或 `BatteryPopup.qml`，单 region、风险低。
2. `ControlCenter.qml` / `NotificationCenter.qml` / `LeftSidebar.qml`。
3. `TopBar.qml`。
4. `Dock.qml`，保留当前“只暴露可见部分”的裁剪逻辑。
5. `Spotlight.qml`，保留输入 pill 和结果 panel 两个 region。
6. `Launchpad.qml`，在 material 决策后迁移。
7. `TaskSwitcher.qml`、`WindowOverview.qml`、`SettingsPanel.qml`。

验收：

- 每迁移一个组件，截图验证对应 surface。
- 迁移后 `TahoeGlass.regions` 数量和原来一致，除非任务明确说明要拆分 region。
- `scripts/check-tahoe-glass-guardrails.sh` 通过。
- 业务组件不出现新的 `BackgroundEffect` import。

完成记录：

- 2026-06-29 已完成 T7 QML 玻璃封装落地与组件迁移，见 `tahoe-shell/docs/liquid-glass-t7-qml-glass-migration-2026-06-29.md`。
- 业务组件不再直接声明 `TahoeGlassRegion`；该声明只保留在 `GlassPanel.qml` 内部。
- `TahoeGlass.regions` 覆盖仍为 22 个组件、23 个 compositor-owned region；`Spotlight.qml` 仍是唯一双 region 组件。
- `scripts/check-tahoe-glass-guardrails.sh` 已通过；当前环境缺少 `quickshell`/`qmllint` 和可用图形会话，截图验证留给 T13 视觉基线流程补采。

### T8：启动器玻璃路线

目标：让 `Spotlight.qml` 和 `Launchpad.qml` 成为最像液态玻璃的主体验证对象。

`Spotlight.qml` 当前状态：

- 已有两个 TahoeGlass region：
  - search pill 使用 `MaterialPill`。
  - results panel 使用 `MaterialPanel`。
- 已经避免把 scale animation 直接套到 glass region bounds。

`Spotlight` 任务：

1. 保持 search pill 和 results panel 两 region 模型。
2. search pill 使用更强的 `pill` material：
   - 更明显 edge highlight。
   - 很轻的 lens-depth。
   - chromatic 仍为 0。
3. results panel 使用更可读的 `panel` material：
   - tint 稍高。
   - refraction 更低。
   - inner shadow 保留但不压文字。
4. `interaction` 只影响材质强度，不改 region geometry。
5. 搜索结果列表滚动时不重新创建 region。

`Launchpad.qml` 当前状态：

- 已有一个 TahoeGlass region。
- T8 完成后，当前主 surface 使用 `MaterialLauncher`。

`Launchpad` 任务：

1. 先确定视觉目标：
   - 居中 launcher card：继续 `panel`，但要调低 refraction。
   - 大面积 backdrop：改 `MaterialBackdrop`。
   - 介于两者之间：新增 `launcher` material，比 `panel` 更克制，比 `backdrop` 更有边缘。
2. 如果新增 `launcher` material，只改：
   - `TahoeGlass.js` material 常量。
   - `niri/niri-config/src/tahoe_glass.rs` 默认 material map。
   - `config/niri/tahoe-phase0.kdl` material block。
   - 不改协议。
3. 验证大面积 surface 的 `glass_surface_detail()` 衰减足够。
4. Launchpad 打开/关闭只动画 `materialAlpha`、opacity、content transform，不动画 region bounds。

验收：

- Spotlight 输入框文字不被折射。
- Spotlight results panel 滚动时无 shader artifact。
- Launchpad 不出现整屏水波、大 halo 或巨大 rim。
- 启动器关闭后没有残留 damage/blur。

完成记录：

- 2026-06-29 已完成 T8 启动器玻璃路线，见 `tahoe-shell/docs/liquid-glass-t8-launcher-glass-2026-06-29.md`。
- `Spotlight.qml` 保持 search pill + results panel 两 region；`pill` material edge highlight 更明显、lens-depth 更轻，`panel` material 更偏可读。
- `Launchpad.qml` 判定为居中大 launcher card，新增并使用 `launcher` material：比 `panel` 更克制，比 fullscreen `backdrop` 更有边缘。
- 未改协议、未改 shader、未新增 raw shader 参数；`interaction` / `materialAlpha` 仍只影响材质强度，不改 region geometry。
- `scripts/check-tahoe-glass-guardrails.sh`、`niri validate -c config/niri/tahoe-phase0.kdl`、`cargo test -p niri-config tahoe_glass --quiet` 已通过；当前环境缺少 `quickshell`/`qmllint` 和可用图形会话，视觉截图留给 T13。

### T9：常驻面板玻璃路线

目标：让 `TopBar.qml`、`Dock.qml`、`ControlCenter.qml` 等面板稳定、统一、可读。

任务：

1. `TopBar.qml`
   - 继续只给内部 `barSurface` 建 region。
   - 不把整个 full-width layer surface 变成玻璃。
   - 保持小半径 `RadiusTopBar`，避免像一整条毛玻璃墙。
2. `Dock.qml`
   - 保留当前 visible-height 裁剪逻辑，避免 auto-hide 从屏幕外滑入时 region 越界。
   - Dock hover 可以驱动 `interaction`，但不要改 region 几何。
3. `ControlCenter.qml`、`NotificationCenter.qml`、`LeftSidebar.qml`
   - 保持 `MaterialPanel`。
   - 视觉重点是可读性，refraction 低于 Spotlight pill。
4. `SettingsPanel.qml`
   - 文本密度最高，应作为可读性下限。
   - 如果文字发虚，先提高 tint/降低 refraction，不加 chromatic。
5. `WindowOverview.qml`
   - 缩略图密集，优先降低 lens-depth 和 refraction。
   - 不让每个窗口缩略图单独成为 glass region，除非有明确视觉收益和性能预算。

验收：

- TopBar 不是全宽玻璃条。
- Dock auto-hide 过程中 blur 连续，无 region reject。
- Control Center 和 Settings 文字可读。
- Overview 帧率可接受，无持续 texture realloc。

完成记录：

- 2026-06-29 已完成 T9 常驻面板玻璃路线，见 `tahoe-shell/docs/liquid-glass-t9-persistent-panels-2026-06-29.md`。
- `GlassPanel.qml` 默认 `interaction` 从 `1` 收敛为 at-rest `0`；TopBar、Control Center、Notification Center、LeftSidebar、Settings、WindowOverview 显式保持 `interaction: 0.0`。
- `Dock.qml` 保留 visible-height 裁剪逻辑；hover/reveal 只驱动 `dockGlassInteraction`，不改 region 几何。
- `panel` material 进一步偏向可读性：提高 tint/contrast，降低 refraction/lens/inner-shadow，并同步 panel fallback blocks。
- 已通过 guardrail、`niri validate`、`niri_settings_tool.py read`、`cargo test -p niri-config tahoe_glass --quiet` 和本轮 QML lint；live 截图未覆盖，因为当前部署目录与仓库不同且 niri live config 旧于仓库配置，避免覆盖用户会话，截图留给 T13。

### T10：菜单、toast、dynamic island 路线

目标：把小面积 shell UI 做得更“液态”，但不牺牲文字清晰度。

任务：

1. 菜单类：
   - `MenuPopup.qml`
   - `AppMenuPopup.qml`
   - `TrayMenu.qml`
   - `DockAppMenu.qml`
   - `DockWindowMenu.qml`
   - `ProcessMenu.qml`
   - 统一 `MaterialMenu` 和 `RadiusMenu`。
2. 小弹窗类：
   - `BatteryPopup.qml`
   - `WifiPopup.qml`
   - `FanPopup.qml`
   - `ClipboardPopup.qml`
   - 可继续使用 `MaterialPanel`，但 radius 使用 `RadiusPopup`。
3. Toast：
   - `NotificationToast.qml` 使用 `MaterialToast`。
   - materialAlpha 跟随 enter/exit，避免关闭后残影。
4. Dynamic Island：
   - `DynamicIslandOverlay.qml` 使用 `MaterialPill`。
   - 尺寸频繁变化时，优先动画 content 和 materialAlpha；region bounds 必须 bounded。

验收：

- 菜单文字无彩边。
- Toast 进出时无残留 blur。
- Dynamic Island 变形时 region 不越界、不产生大面积 damage。
- 小 popup 不需要单独 raw shader 参数。

### T11：shell 场景 material profile 细化

目标：把 macOS 风格“透明、折射、边缘光、可读性”的调节集中在 niri material，而不是散落在 QML。

材料分层：

- `panel`：默认面板，平衡可读性和玻璃感。
- `pill`：Spotlight 输入框、Dynamic Island，可略强 edge/lens。
- `dock`：Dock，面积中等且内容图标多，refraction 保守。
- `menu`：菜单，文字密集，edge 可强，lens/refraction 要低。
- `toast`：短生命周期卡片，materialAlpha 驱动进入/退出。
- `backdrop`：大面积/全屏，shadow off，lens/refraction 最低。
- 可选 `launcher`：仅当 `Launchpad` 的视觉无法用 `panel` 或 `backdrop` 表达时再新增。

参考原则：

- 从 `Niri-glass` 只参考 UV 分离、rounded SDF、最后采样阶段做折射。
- 从 `forceblur` 只参考受控 blur strength、亮度/饱和度/对比度思路、static blur 性能阀门。
- 不复制 shader，不复制 KWin/KDecoration/window class 代码。

任务：

1. 先用现有字段调 material：
   - `noise`
   - `saturation`
   - `tint-color`
   - `tint-amount`
   - `edge-highlight`
   - `refraction`
   - `inner-shadow`
   - `chromatic`
   - `lens-depth`
2. `chromatic` 默认继续 0。
3. 对大面积 material 自动保守：
   - `backdrop` 的 refraction/lens-depth 低。
   - `glass_surface_detail()` 继续对大面衰减。
4. 如果可读性仍不足，再考虑新增一个 `contrast` 字段。
5. 不新增 `clarity/refraction_a/b/c/d/power_factor` 这类 raw knob。

验收：

- `config/niri/tahoe-phase0.kdl` material 数量少且语义明确。
- `TahoeGlass.js` material 名称与 niri material 一一对应。
- material 调参不需要改 QML 业务组件。
- `niri validate -c config/niri/tahoe-phase0.kdl` 通过。

### T12：TahoeGlass fallback 与生命周期收敛

目标：协议可用时走 TahoeGlass，协议不可用时 fallback 一致，但业务 QML 不知道 fallback 细节。

任务：

1. 对齐 `quickshell/src/wayland/tahoe_glass/qml.cpp` 与 `background_effect/qml.cpp` 的 surface lifecycle。
2. reload、surface destroy/recreate、QWindow 替换时不丢 region。
3. fallback 的 `BackgroundEffect.blurRegion` 只在 TahoeGlass client 内部使用。
4. `config/niri/tahoe-phase0.kdl` 的 layer-rule fallback 参数继续与 `tahoe-glass` material 保持近似。

验收：

- 重启/热加载 Quickshell 后玻璃仍恢复。
- 没有重复 attach。
- guardrail 阻止业务 QML 直接 import/use BackgroundEffect。
- niri log 没有 protocol/render error。

### T13：视觉基线与性能验收

目标：每次调 shader/material 都能判断变好还是变坏。

必须截图：

- `TopBar.qml`
- `Dock.qml`
- `Spotlight.qml`
- `Launchpad.qml`
- `ControlCenter.qml`
- `SettingsPanel.qml`
- `WindowOverview.qml`
- `TaskSwitcher.qml`
- `MenuPopup.qml`
- `NotificationToast.qml`
- `DynamicIslandOverlay.qml`

必须场景：

- 浅色壁纸。
- 深色壁纸。
- 背后有高对比窗口。
- 背后窗口移动。
- fractional scale。
- 打开/关闭动画中间帧。

性能验收：

- 真机和 VM 下无明显输入延迟。
- Dock/Spotlight/Launchpad 动画无明显 stutter。
- niri log 无 shader/render/texture allocation error。
- 大面积 Launchpad/Overview 不触发持续重建昂贵 texture。

### T14：是否需要 static blur 的判定

目标：只在有测量数据证明必要时，才借鉴 `forceblur` 的 static blur。

默认不做。

进入条件：

- T13 显示大面积 glass 在真实硬件上持续超预算。
- 降低 refraction/lens/blur 后仍不可接受。
- 问题集中在大面积、低动态 surface，例如 Launchpad launcher card 或后续 fullscreen backdrop。

如果进入研究：

- 只缓存大面积、低动态背景。
- 有窗口移动、workspace 动画、overview、视频动态背景时回到实时 blur。
- 不做每个小 region 的长期缓存纹理。

验收：

- 有测量数据前不实现。
- 实现前先写单独设计文档。

## 近期最推荐执行顺序

1. T0 guardrails。
2. T1 Quickshell TahoeGlass lifecycle 去重。
3. T6 Tahoe shell 覆盖清单与缺口确认。
4. T2 QML `GlassPanel`/`GlassSurface` 封装设计。
5. T7 QML 玻璃封装落地与低风险组件迁移。
6. T8 启动器玻璃路线，先 Spotlight，再 Launchpad。
7. T9 常驻面板玻璃路线，先 TopBar/Dock，再 ControlCenter/Settings/Overview。
8. T10 菜单、toast、dynamic island 路线。
9. T3 niri material token 初步收敛。
10. T11 shell 场景 material profile 细化。
11. T4 shader 性能与可读性调参。
12. T12 fallback 与生命周期收敛验收。
13. T13 视觉基线与性能验收。
14. T5/T14 static blur 研究；只有 T13 证明需要才进入。

执行约束：

- 一个任务验收通过后才能开始下一个任务。
- 先整理 QML region 声明，再调 niri material。
- 先用现有 `BackgroundEffect` / `GlassOptions` / shader 管线，不扩协议。
- 普通应用窗口不在本路线内。

## 明确禁止方向

- 把 `Niri-glass` 文件复制进本仓库。
- 直接移植 `forceblur` 的 KWin effect 代码。
- 新增 `tahoe_glass_v2` 只为调一个 shader 参数。
- 在 Tahoe QML 中直接新增 `BackgroundEffect.blurRegion`。
- 新增第二套按 app class/window title 匹配的玻璃系统。
- 用 spring 直接驱动 glass region 几何。
- 把每个视觉微调都暴露成 KDL 用户配置。
- 为普通应用窗口接入 TahoeGlass client 协议。
- 为了玻璃效果改普通应用窗口的 `window-rule opacity`。

## 本轮结论

`Niri-glass` 证明 niri 的 background-effect/shader 管线能承载更强折射，并提醒必须分离 texture UV 与 geometry UV。`kwin-effects-forceblur` 证明桌面级 blur/glass 的关键不是“更多 pass”，而是受控的 blur strength 映射、最后阶段折射、色彩可读性参数、缓存策略和性能边界。

本仓库 TahoeGlass 架构比 `Niri-glass` 更适合你的 launcher 和 panel，因为它能表达内部 rounded region，而不是只作用于整个 window/layer。后续应坚持：Quickshell 声明 region，niri 拥有玻璃，KDL 管 material，fallback 留给 TahoeGlass client 内部处理。

所以最终判断是：

- 要让 Tahoe shell 真正像液态玻璃：Quickshell 继续声明 region，niri 继续渲染 TahoeGlass。
- 不把普通第三方应用窗口作为目标。
- 不增加独立组件。
- 不照搬 `Niri-glass` 或 `forceblur` 代码，只吸收 UV 分离、受控 blur 映射、最后阶段折射、可读性和性能阀门这些原则。
