# Tahoe Glass 研究文档与改进路线图

日期：2026-06-16

本文最初记录对 Tahoe 玻璃效果链路的只读研究结论，并给出后续改进路线。原始研究期间未修改实现代码，未运行脚本，未读取 baseline 文件；后续阶段完成情况在对应章节追加记录。

## 目标

- 提升 Tahoe shell 的液态玻璃质感，让它更接近“折射、透镜、高光、柔和阴影随交互变化”的效果，而不是单纯的静态半透明白色层。
- 保留现有 compositor-owned glass 架构：QML 只声明玻璃区域，niri 负责采样、模糊、阴影、裁剪和材质。
- 避免重回已知风险：玻璃 region 几何不使用无界 spring，防止 niri 区域计算溢出；虚拟机或软件 GPU 下不让 Image 几何 spring 导致贴图消失。

## 研究摘要

### AndroidLiquidGlass-kmp 的关键思路

AndroidLiquidGlass 的“液态”主要不是来自普通 blur，而是来自运行时 shader 材质：

- 用 rounded-rect SDF 表达玻璃边界。
- 背景采样带有透镜式偏移和折射。
- 高光、内阴影、边缘光和模糊强度参与统一材质。
- 交互、速度、按压或 hover 会改变 scale、blur、lens、highlight 等参数。

这说明 Tahoe 当前最缺的不是更多 QML Rectangle，而是 compositor 侧材质参数和 shader 表现力。

### Tahoe 当前架构

当前 Tahoe 路径大致为：

- QML 组件通过 `TahoeGlass.regions` 声明玻璃区域。
- `TahoeGlassRegion { item: ... }` 多数绑定到实际可见的 Rectangle，例如 Dock 的 `dockSurface`、TopBar 的 `barSurface`、Spotlight 的 `spotlightSurface` 和 `resultsSurface`。
- Quickshell fork 通过私有 `tahoe_glass_v1` 协议提交 per-surface regions。
- niri 在 compositor 侧按 region 渲染 background-effect、shadow、clip 和 material。
- Phase 3 前，QML 仍然在玻璃 item 上绘制 tint、border、inner stroke、hairline，这些覆盖层会影响最终玻璃观感。

整体方向是对的：玻璃应由 compositor 拥有。问题集中在坐标契约、材质默认值和 QML 覆盖层过重。

## 关键发现

### 1. TahoeGlass 坐标契约冲突（已在 Phase 1 解决）

这是最高优先级问题，现已修复。修复方式见下方“Phase 1”。以下保留原始分析作为背景。

协议 XML 明确写着：

- region 坐标是 `surface-local logical coordinates`。

niri 的处理也符合 surface-local 语义：

- `make_region()` 把客户端传入的 `x/y/width/height` 原样保存为 `region.rect`。
- `validate_regions()` 用 `surface_geo(states)` 校验 region 是否在 surface 内。
- `render_region()` 渲染时使用 `surface_location + rect.loc`，也就是 compositor 自己再加 surface 的屏幕位置。

但 Quickshell 当前 TahoeGlass 路径中：

- `buildRegion()` 用 `item->mapToScene()` 得到 scene/window 内坐标。
- `buildSurfaceRegion()` 又执行 `state->rect.translate(window->position())`。
- 注释写的是把 window-relative 转成 screen-absolute。

这和协议、niri 实现、旧 `BackgroundEffect.blurRegion` 经验都冲突。旧 blur 路径只做 item region、DPR 和 `clientSideMargins()`，没有加 `window->position()`。

实际影响：

- 如果 layer-shell 下 `QWindow::position()` 始终是 `(0, 0)`，问题会被掩盖。
- 如果它在多显示器、非主输出、带 margins 的 anchored panel 或某些 Qt/niri 组合下非零，region 可能被 niri 校验丢弃。
- 即使未被丢弃，也可能出现 double offset：Quickshell 已经加过窗口位置，niri 渲染时又加一次 surface location。
- Dock、TopBar、Spotlight 这类“大透明 PanelWindow 里的局部玻璃 item”尤其容易暴露这个问题。

同一处还需要复核 DPR 和 margins：

- Tahoe 协议写的是 logical coordinates。
- QML `mapToScene()` 得到的是 Qt scene logical 坐标。
- 当前 `buildSurfaceRegion()` 会用 `QHighDpiScaling::factor(window)` 缩放 region，再加 `clientSideMargins()`。
- 如果 niri 端按 logical 消费，这个 DPR 缩放在 fractional/high-DPI 下也可能不正确。

结论：第二点不是误判。更准确地说，坐标链路存在确定的契约冲突，但当前是否可见取决于 `QWindow::position()`、DPR 和 compositor 输出布局。

### 2. 真实液态参数可能没有启用

niri config 的 Tahoe material 默认值里，`edge_highlight` 和 `refraction` 曾观察到是 `Some(0.)`。如果当前运行配置没有覆盖这些值，那么 compositor-owned glass 即使工作，也更像普通 blur/tint，而不是液态玻璃。

这会导致：

- QML 里看得到白色填充和描边。
- 背景有 blur。
- 但没有明显折射、边缘光、透镜形变和材质深度。

优先级仅次于坐标问题。坐标不准时，材质调得再好也可能作用在错误区域；坐标修正后，材质参数才是主要观感来源。

### 3. QML 静态覆盖层偏重（已在 Phase 3 降权）

多数组件在 glass item 上继续绘制：

- 半透明 fill。
- 1px border。
- inset border。
- top hairline。
- bottom shadow line。

这些能补偿当前 compositor material 不足，但也会带来副作用：

- 边缘像“白色卡片”而不是“折射玻璃”。
- 多层 border 会压住 shader 高光。
- 不同组件各自调色，导致 Dock、TopBar、ControlCenter、Launchpad 之间玻璃一致性弱。

Phase 3 已对主玻璃 surface 降权：QML 保留轻量 tint/fallback stroke，重复 shadow、hairline 和 inner stroke 交给 compositor material 方向继续承接。

### 4. 动画限制是合理的，不应简单恢复 spring

当前项目大量注释提到：

- 玻璃 region 的 `x/y/width/height` 不使用 spring。
- Image geometry 在 VMware/software GPU 下 spring 会导致贴图透明或丢失。
- 曾有 niri region 计算溢出导致会话回到登录界面。

这些约束应保留。改进动画的方向不是让玻璃 region 几何无界弹动，而是：

- region 几何继续使用 bounded `NumberAnimation`。
- 内容层可以做 opacity、scale、translate，但不要影响 glass region bounds。
- 更理想的是在 compositor 侧做材质参数动画，例如 refraction、highlight、shadow alpha、blur strength 的 eased transition。

## 改进路线图

### Phase 1：统一 TahoeGlass 坐标契约（已完成）

目标：让 Quickshell 发送的 TahoeGlass region 与协议和 niri 消费方式一致。

状态：已完成。Quickshell fork（`quickshell-tahoe-desktop` 分支）的 `src/wayland/tahoe_glass/qml.cpp` 与 `qml.hpp` 已落地以下修改：

- `buildSurfaceRegion()` 不再加 `QWindow::position()`，移除了 window-relative 到 screen-absolute 的平移。
- 移除了 `QHighDpiScaling::factor(window)` 的 DPR 缩放和 `scaleInt()` 辅助函数；region 保持 QML scene logical 坐标。
- `buildSurfaceRegion()` 签名从 `(QWindow*, QWaylandWindow*, state)` 简化为 `(QWaylandWindow*, state)`，调用方 `onWindowPolished()` 同步更新。
- 仅保留 `clientSideMargins()` 平移，并加注释说明：region 是 surface-local logical，compositor 负责加 surface 输出位置。对 Tahoe layer-shell 窗口 margins 预期为零，保留平移是为 decorated/带 margins 的普通 Wayland surface 保持正确。
- 删除了不再需要的 `#include <private/qhighdpiscaling_p.h>`。

协议与 compositor 侧已与该契约一致，本次未改动：

- `niri/resources/tahoe-glass-v1.xml` 已声明 region 为 surface-local logical coordinates。
- `niri/src/render_helpers/tahoe_glass.rs` 的 `render_region()` 用 `surface_location + rect.loc` 仅加一次 surface 位置。
- `niri/src/protocols/tahoe_glass.rs` 的 `validate_regions()` 用 `surface_geo(states)` 校验 region 落在 surface 内。

文档：`tahoe-shell/docs/phase5-quickshell-client-notes.md` 已包含“TahoeGlass Coordinate Contract”一节记录该契约。全仓库已无 `screen-absolute` / `window->position` / `QHighDpiScaling` 残留引用。

原始建议方向（已逐条落实）：

- 把 TahoeGlass 协议 region 定义为唯一事实来源：surface-local logical。
- Quickshell `buildSurfaceRegion()` 不应把 `window->position()` 加入 region。
- 复核是否应该保留 DPR 缩放。若协议坚持 logical，QML scene logical 坐标不应再乘 DPR。
- 复核 `clientSideMargins()` 对 layer-shell surface 是否必要。若只为普通 decorated window 准备，应限定适用范围或加注释。
- 更新注释和文档，删除“screen-absolute coordinates”这一说法。
- niri 侧继续由 `render_for_layer()` 传入 surface location，并在 `render_region()` 中加 `surface_location + rect.loc`。

验收建议：

- Dock 的 `dockSurface` region 位于透明 PanelWindow 内底部居中，niri committed rect 应仍是 surface-local。
- TopBar 的 `barSurface` 带左右 8px、上下 5px inset，committed rect 应反映这些 inset，而不是全局屏幕位置。
- ControlCenter、NotificationCenter、BatteryPopup、MenuPopup 带 layer-shell margins，region 坐标仍应从 surface 左上角开始计算。
- Spotlight 和 Launchpad 是全屏 surface 内局部或全屏 region，应在多输出和 fractional scale 下稳定。

### Phase 2：启用真正的液态材质参数

目标：先用现有 niri material 能力把玻璃从“白色模糊卡片”推进到“有折射和边缘光的玻璃”。

建议方向：

- 为 `panel`、`dock`、`menu`、`pill`、`toast`、`backdrop` 分别设置非零 `edge_highlight`。
- 为 `panel`、`dock`、`pill` 设置保守非零 `refraction`。
- `backdrop` 可以低 refraction 或无 shadow，避免 fullscreen overlay 过度扭曲。
- `toast` 和 `menu` 可以更清晰，减少 blur 半径但增强边缘光。
- 先调 compositor material，再决定是否删减 QML border。

建议初始区间：

- `edge_highlight`: 0.20 到 0.45。
- `refraction`: 0.02 到 0.08。
- `backdrop refraction`: 0.00 到 0.03。
- `shadow alpha`: Dock 和 panel 可强一些，fullscreen backdrop 应弱或关闭。

这些数值只是起点，最终以截图和交互观感为准。

### Phase 3：降低 QML 覆盖层权重（已完成）

目标：让 QML 只负责内容、tint 和必要的 fallback，而不是用多层 Rectangle 模拟玻璃。

状态：已完成。`tahoe-shell` 的 QML 主玻璃 surface 已落地以下修改：

- `components/TahoeGlass.js` 降低共享 fill/stroke alpha，并把 panel、dock、topbar、pill、backdrop、toast 统一到同一套轻量 fallback material 词汇。
- `Dock.qml` 移除主 `dockSurface` 上的重复 bottom shadow edge、inner stroke、top hairline 和 bottom shadow line，只保留一层低 alpha inset stroke。
- `TopBar.qml` 移除主 `barSurface` 的 bottom shadow edge，只保留一层低 alpha inset stroke。
- `ControlCenter.qml` 移除主 `panel` 的 bottom shadow edge、top hairline 和 bottom shadow line，只保留一层低 alpha inset stroke。
- `MenuPopup.qml`、`BatteryPopup.qml`、`NotificationCenter.qml` 和 `TrayMenu.qml` 移除主 popup surface 的额外 QML shadow stroke，只保留轻量 fallback stroke。
- `NotificationToast.qml` 移除 toast 主 surface 的 QML shadow stroke；普通 toast 使用共享轻描边，critical toast 继续保留红色 urgency accent。
- `Spotlight.qml` 移除 search pill 的额外 inner stroke，并让 results surface 使用共享 panel fill/stroke。

落地原则：

- 先保留 fill，但降低 alpha，避免压住折射。
- 再减少重复 border，只保留必要的内侧细线。
- 将 top hairline 和 bottom shadow line 迁移为 compositor material 的 edge highlight 和 inner shadow。
- Dock、TopBar、Panel、Popup 使用同一套 material 词汇，避免每个组件单独堆叠视觉补丁。

后续风险：

- 如果 Phase 2 材质还不够强，过早删 QML stroke 会让玻璃变淡。
- 这次已保留轻量 fallback stroke，后续应继续优先调 compositor material，再考虑进一步削弱 QML fallback。

### Phase 4：引入更接近 AndroidLiquidGlass 的 shader 表现

目标：把 niri Tahoe material 从普通 blur/shadow 扩展为真正的 liquid glass。

建议能力：

- rounded-rect SDF mask，统一处理 radius 和边缘过渡。
- 基于 SDF normal 的背景采样偏移，形成边缘折射。
- 中心区域轻微 lens distortion，边缘区域更强。
- top-left highlight 和 bottom-right inner shadow 由 shader 生成。
- 支持 per-material 的 refraction、highlight、inner shadow、tint、noise 或 chromatic fringe 参数。

可选协议扩展：

- region 支持 `intensity`、`interaction` 或 `state` 参数。
- QML 可为 Dock hover、toast enter、popup open 传递轻量交互值。
- 如果暂不扩协议，也可以 compositor 内部根据 region 生命周期做 open/close material easing。

### Phase 5：动画模型重构

目标：动画更活，但不牺牲稳定性。

保留：

- 玻璃 region 的位置和尺寸继续使用 bounded `NumberAnimation`。
- `useSpring` 默认 false，虚拟机和软件渲染优先稳定。
- Image geometry 不在默认路径上 spring。

改进：

- popup open/close：region bounds 稳定，内容层做轻微 scale/opacity。
- Dock hover：icon scale 和 lift 继续在内容层做，glass material 可以额外提高 highlight/refraction。
- Toast enter：card 的 region x 仍 bounded，material alpha/highlight 可以 eased。
- Launchpad：fullscreen backdrop 的 blur/refraction/tint 过渡由 compositor material 承担，减少 QML 上叠的静态色层。

### Phase 6：验证矩阵

坐标验证：

- 单显示器 1x。
- fractional scale。
- 多显示器，主输出和非主输出。
- TopBar、Dock、ControlCenter、NotificationCenter、BatteryPopup、MenuPopup、Spotlight、Launchpad。
- 带 layer-shell margins 的右上弹窗。
- 全屏 anchored surface。

视觉验证：

- 静态壁纸下看边缘高光。
- 有窗口移动到玻璃背后时看折射和 blur 是否跟随。
- Launchpad 打开时 Dock/TopBar 是否真正消失并停止采样。
- Spotlight 两个 region 是否独立且位置正确。
- Toast 滑入滑出时 region 是否无残影。

稳定性验证：

- 快速连续开关 ControlCenter、Spotlight、Launchpad。
- 快速产生多条通知。
- 切换输出布局或 scale。
- VMware/software GPU。
- 真机 GPU。

性能验证：

- region 数量接近上限时的 damage 范围。
- blur/refraction 开启后的 frame time。
- fullscreen backdrop 对低端 GPU 的成本。

## 建议修改顺序

1. ~~先修 TahoeGlass 坐标契约，尤其是 `window->position()` 和 DPR 语义。~~（已完成，见 Phase 1）
2. 再启用或调高 compositor material 的 refraction 和 edge highlight。（下一步）
3. ~~然后逐步降低 QML 静态 stroke/hairline 的存在感。~~（已完成，见 Phase 3）
4. 最后考虑扩展 shader 和协议，让交互状态驱动液态参数。

不要优先做：

- 不要先给玻璃 region 几何恢复 spring。
- 不要用 broad namespace 规则绕过 TahoeGlass region。
- 不要靠继续叠 QML Rectangle 来模拟折射。
- 不要把 niri 改成消费 screen-absolute region，协议和旧路径都更支持 surface-local。

## 需要后续确认的问题

- layer-shell 下 `QWindow::position()` 在不同输出和不同 Qt/niri 组合中是否总为 `(0, 0)`。
- `clientSideMargins()` 对 Tahoe 的 layer-shell windows 是否始终为零。
- Tahoe 私有协议最终是否坚持 logical coordinates。如果坚持，Quickshell DPR 缩放应重新审计。
- niri 当前 material 默认值和实际运行配置是否把 `edge_highlight`、`refraction` 置零。
- 是否需要在协议中加入 per-region interaction 参数，还是先用 compositor 内部 transition 即可。

## 参考文件

- `quickshell/src/wayland/tahoe_glass/qml.cpp`
- `quickshell/src/wayland/tahoe_glass/surface.cpp`
- `quickshell/src/wayland/background_effect/qml.cpp`
- `quickshell/src/core/region.cpp`
- `quickshell/src/wayland/wlr_layershell/surface.cpp`
- `quickshell/src/window/proxywindow.cpp`
- `niri/resources/tahoe-glass-v1.xml`
- `niri/src/protocols/tahoe_glass.rs`
- `niri/src/render_helpers/tahoe_glass.rs`
- `niri/src/render_helpers/background_effect.rs`
- `niri/src/layer/mapped.rs`
- `niri/src/utils/mod.rs`
- `niri/niri-config/src/tahoe_glass.rs`
- `config/niri/tahoe-phase0.kdl`
- `tahoe-shell/components/Dock.qml`
- `tahoe-shell/components/TopBar.qml`
- `tahoe-shell/components/ControlCenter.qml`
- `tahoe-shell/components/Spotlight.qml`
- `tahoe-shell/components/Launchpad.qml`
- `tahoe-shell/components/NotificationToast.qml`
- `tahoe-shell/components/TahoeGlass.js`
