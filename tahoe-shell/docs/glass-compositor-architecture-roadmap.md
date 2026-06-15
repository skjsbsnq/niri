# Tahoe Glass 合成器架构研究与长期路线图

日期：2026-06-15

范围：解释 VMware Arch Linux + niri 环境中反复出现的圆角、模糊、液态玻璃异常，并给出允许魔改 niri / Quickshell 后的长期架构路线。本文不再把问题当作单个 QML 半径或单个 shader 参数来处理，而是把玻璃效果提升为 compositor 统一管理的图元。

## 结论摘要

当前问题是系统性问题，不是某一个 QML `radius` 写错。

项目里现在同时存在三套互不等价的几何系统：

1. QML `Rectangle.radius`
   - 只影响 Quickshell 客户端自己绘制出来的像素。
   - compositor 不会因为 QML 圆角就自动知道这个 surface 是圆角。

2. Quickshell `BackgroundEffect.blurRegion`
   - 最终通过 Wayland `wl_region` 传给 niri。
   - `wl_region` 只能表达矩形集合，不能表达“这是一个半径为 28 的连续圆角矩形”。

3. niri layer surface 几何
   - niri 的 shadow / background-effect 以 layer surface 几何为基础。
   - niri 只能通过 `layer-rule geometry-corner-radius` 得到一个 compositor 侧圆角半径。

这三套系统没有共享同一个“圆角玻璃矩形”图元，所以 niri 经常在一个矩形 layer surface 上渲染 blur / shadow / glass，而 QML 在里面绘制一个更小的圆角面板。截图中的蓝色矩形背板、圆角外 halo、大面积液态透镜感，本质上都来自这个几何所有权错位。

长期正确方向：让 niri 成为玻璃几何的唯一权威。Quickshell 只声明“这里有一个玻璃圆角矩形”，niri 统一用这个矩形渲染 blur、tint、edge highlight、refraction、clip、shadow。

既然允许第五阶段魔改，最终目标应改为：实现一个 Tahoe 私有 Wayland 协议，让 Quickshell 把精确圆角玻璃区域发给 niri。

## 代码证据

### Quickshell 侧

`quickshell/src/core/region.cpp`

- `PendingRegion::build()` 会把 QML item 映射到 scene 坐标，然后构造 `QRegion`。
- 如果设置了 radius，它会用“矩形减去角落外侧椭圆区域”的方式近似圆角。
- 结果仍然是 `QRegion`，也就是一组矩形，不是带 radius 元数据的连续 rounded rect。

`quickshell/src/wayland/background_effect/qml.cpp`

- `BackgroundEffect::onWindowPolished()` 构建 blur region。
- 它还会处理 scale 和 client-side margins。
- 最终把 `QRegion` 传给 background effect surface。

`quickshell/src/wayland/background_effect/surface.cpp`

- `BackgroundEffectSurface::setBlurRegion()` 把 `QRegion` 转成 `wl_region`。
- 然后调用 `set_blur_region()`。
- 这一步之后，圆角语义已经彻底丢失。

`quickshell/src/wayland/wlr_layershell/wlr_layershell.hpp`

- Quickshell layer-shell 默认 namespace 是 `"quickshell"`。
- 当前 Tahoe 除壁纸外，多数面板都没有设置自己的 `WlrLayershell.namespace`。
- 因此 niri 里的 broad rule `namespace="^quickshell"` 会打到几乎所有 shell surface。

### niri 侧

`config/niri/tahoe-phase0.kdl`

- 当前有一个 broad rule：

```kdl
layer-rule {
    match namespace="^quickshell"
    shadow { ... }
    background-effect { ... }
}
```

- 这个规则无差别影响 Spotlight、Dock、TopBar、Control Center、Notification Center、菜单、toast 等所有默认 namespace 的 Quickshell layer。
- 它没有给 layer surface 设置 `geometry-corner-radius`。

`niri/src/handlers/background_effect.rs`

- niri 把 client blur region 缓存为：

```rust
Option<Arc<Vec<Rectangle<i32, Logical>>>>
```

- 也就是说，niri 只拿到矩形列表。
- `region_to_non_overlapping_rects()` 之后，圆角来源已经不可恢复。

`niri/src/layer/mapped.rs`

- layer surface 渲染时调用：

```rust
background_effect::render_for_tile(..., clip_to_geometry=false, ...)
```

- 对 layer surface 来说，background-effect 默认不会按 layer geometry 做圆角裁剪。
- 传入的 radius 来自 `layer-rule geometry-corner-radius`，不是 Quickshell 的 `Region.radius`。

`niri/src/render_helpers/background_effect.rs`

- 如果存在 client blur region，niri 会把它作为 `subregion`。
- 这个 `subregion` 主要用于 damage 过滤和局部绘制，不是连续圆角 mask。
- 真正 smooth 圆角裁剪需要 `clip_geo + CornerRadius`。

`niri/src/render_helpers/shaders/clipped_surface.frag`

- 圆角 alpha 由 `niri_rounding_alpha()` 完成。
- 这个 shader 只接受一个矩形和一组四角半径。
- 它不能从任意 `wl_region` 反推出连续圆角。

## 为什么截图里到处是同类问题

### Control Center / Notification Center

这两个组件接近“容易修”的情况，因为 `PanelWindow` 尺寸基本等于面板尺寸。

但因为 broad `^quickshell` layer rule 给它们加了 compositor shadow / background-effect，而没有匹配 `geometry-corner-radius`，niri 仍然可能按矩形 layer 画出蓝色背板或方形 shadow。

这类组件可以通过独立 namespace + 精确 `geometry-corner-radius` 暂时修好。

### Spotlight

Spotlight 是全屏 `PanelWindow`，因为它要拿焦点、处理 ESC、点击外部关闭。

真正的搜索栏只是里面的一个 item。QML 里视觉上是小圆角 pill，但 niri 看到的是一个全屏 layer surface，以及一组由 blurRegion 离散出来的矩形。

所以搜索栏周围会出现超出 pill 的蓝色 halo 或矩形背板。

### Dock / TopBar

Dock 和 TopBar 也是大透明 layer surface 里放一个内部玻璃条：

- Dock：全宽底部 layer，内部 `dockSurface` 才是玻璃。
- TopBar：全宽顶部 layer，内部 `barSurface` 才是玻璃。

如果 niri 把 layer surface 当玻璃几何，shader 的 rim / refraction / shadow 坐标系就会按全宽或全屏计算，而不是按内部玻璃条计算。

### Launchpad

Launchpad 是全屏 backdrop，问题不同：

- 它本身是全屏 blur / scrim，不需要圆角。
- 但 Dock / TopBar 是同级 layer surface，如果 Launchpad 打开时它们还在，就会继续各自渲染自己的玻璃。
- 结果就是全屏 Launchpad、Dock、TopBar 三套 blur/glass 叠在一起，看起来不像一个统一覆盖层。

## 不能永久解决问题的做法

### 只改 QML radius

无效。niri 不会自动知道 QML 的 radius。

### 只用 Quickshell mask

不够。mask 更偏输入/点击区域，不是 compositor glass shape。

### 给 `namespace="^quickshell"` 加一个全局 `geometry-corner-radius`

只能局部改善 Control Center 这类小面板。

它对 Spotlight、Dock、TopBar 这种“大透明 layer + 小玻璃 item”的结构是错误的，因为 layer surface 几何和玻璃几何不是同一个东西。

### 只降低 tint / refraction / edge highlight

只能掩盖问题。shader 会变淡，但几何仍然是错的。

### 只依赖标准 `ext-background-effect-v1`

不够。这个协议只提供 blur region，不能传 rounded-rect metadata。

## 目标架构

Tahoe glass 应该成为 compositor-owned primitive。

新的架构原则：

1. QML 只声明玻璃意图。
2. Quickshell 把精确 rect + per-corner radius + material 发给 niri。
3. niri 用同一份几何渲染：
   - blur
   - noise
   - saturation
   - tint
   - edge highlight
   - refraction
   - rounded clip
   - shadow
4. QML 继续负责内容、图标、文字、布局和必要的内描边。
5. 玻璃外观参数由 niri config 控制，而不是散落在多个 QML 组件里。

最终不变量：

> 每一个可见玻璃对象，在 niri 里都有一个权威 rounded rect。blur、shadow、refraction、highlight、clip 全部使用这一个 rounded rect。

## 私有协议设计

工作名：`tahoe_glass_v1`

### 协议对象

`tahoe_glass_manager_v1`

- niri 暴露的 Wayland global。
- 客户端用它为某个 `wl_surface` 创建 `tahoe_glass_surface_v1`。

`tahoe_glass_surface_v1`

- 绑定到一个已有 `wl_surface`。
- 存储这个 surface 上的 0 个或多个玻璃区域。
- 状态 double-buffered，随普通 surface commit 一起提交。

### 区域模型

每个 glass region 应包含：

- `id`
  - 稳定整数，用于更新已有 region。

- `x, y, width, height`
  - surface-local 矩形。

- `radius_tl, radius_tr, radius_br, radius_bl`
  - 四角半径。

- `material`
  - 材质角色，建议第一版使用枚举或短字符串：
    - `panel`
    - `pill`
    - `dock`
    - `menu`
    - `toast`
    - `backdrop`

- `flags`
  - `blur`
  - `shadow`
  - `clip`

第一版不建议让客户端传任意 blur 强度。客户端只传 material，具体 blur/tint/shadow 参数由 niri config 映射，避免任意客户端请求超大 blur 或过强 shadow。

### niri 数据结构

新增 per-surface state，类似 background-effect cache：

```text
TahoeGlassSurfaceState
  pending_regions: Vec<TahoeGlassRegion>
  committed_regions: Arc<Vec<TahoeGlassRegion>>
  dirty: bool
```

region 结构：

```text
TahoeGlassRegion
  id
  rect: Rectangle<i32, Logical>
  radius: CornerRadius
  material: TahoeGlassMaterial
  flags: TahoeGlassFlags
```

安全限制：

- 每个 surface 最多 32 个 region。
- region 不允许超过 layer surface 自身边界。
- 单 surface 总 blur 面积不超过当前 output 面积。
- 无效或溢出的 rect 直接丢弃。
- 协议只对 allowlist namespace 生效，例如 `^tahoe-`。

### niri 渲染模型

每个 glass region 都应作为 compositor element 渲染：

1. capture region 背后的 framebuffer。
2. 应用 blur / noise / saturation。
3. 用 Tahoe postprocess shader 做 tint / edge highlight / refraction。
4. 用同一个 `CornerRadius` 做 smooth clip。
5. 用同一个 rounded rect 画 shadow。
6. 最后再画客户端 surface 内容。

关键点：shadow、blur、shader 坐标、clip 必须使用同一个 region rect，而不是 layer surface rect。

### Quickshell QML API 设想

可以做成 attached object：

```qml
TahoeGlass.regions: [
    TahoeGlassRegion {
        item: panel
        material: TahoeGlass.MaterialPanel
        radius: 28
        shadow: true
        blur: true
    }
]
```

Spotlight 这种一个 surface 内多个玻璃块：

```qml
TahoeGlass.regions: [
    TahoeGlassRegion {
        item: searchPill
        material: TahoeGlass.MaterialPill
        radius: 33
    },
    TahoeGlassRegion {
        item: resultsPanel
        material: TahoeGlass.MaterialPanel
        radius: 18
    }
]
```

Quickshell 负责把 item 的 scene geometry 映射成 surface-local 坐标。这里可以复用现有 `BackgroundEffect.blurRegion` 的 item 映射经验，但不能再 collapse 成 `QRegion`。

### fallback

如果 compositor 不支持 `tahoe_glass_v1`：

- Quickshell 回退到 `BackgroundEffect.blurRegion`。
- niri 使用 per-namespace layer rule 做 best-effort。
- 不能重新启用 broad `namespace="^quickshell"` shadow/glass 规则。

## 新路线图

这个路线图把私有协议作为最终主线，而不是可选项。

## 当前进度

| Phase | 状态 | 当前结论 |
| --- | --- | --- |
| Phase 0：固定调试基线 | 已完成 | 三张异常截图、截图 hash / 尺寸、运行时采集脚本已落地。 |
| Phase 1：拆 namespace，移除 broad layer rule | 已完成 | Tahoe `PanelWindow` 已使用独立 namespace，niri broad `^quickshell` layer rule 已拆成精确 Tahoe namespace rules。 |
| Phase 2：niri blurRegion bbox 过渡修复 | 已完成 | niri layer surface 已使用 client blur region 的 surface-clamped bbox 作为 background-effect geometry / clip geometry。 |
| Phase 4/5：`tahoe_glass_v1` 私有协议 | 待做 | 最终主线：Quickshell 发 exact rounded regions，niri 统一渲染 glass。 |
| Phase 6-8：迁移、清理、验证 | 待做 | 逐个组件迁移到 compositor-owned glass，并删除旧 fallback 误用路径。 |

### Phase 0：固定调试基线

目标：后续改动可复现、可对比。

状态：已落地到仓库。视觉基线截图保存在 `tahoe-shell/docs/visual-baselines/2026-06-15-phase0-glass-geometry/`；运行时环境采集脚本为 `scripts/capture-glass-baseline.sh`。

这个阶段的产物不是修复代码，而是验证基线。它解决的是“以后看到截图变化时，能知道到底是哪组代码、配置、分辨率、scale 产生了这个效果”。

任务：

- 保留当前异常截图作为视觉基线：
  - Spotlight 搜索栏 halo。
  - Notification Center 矩形背板。
  - Control Center 矩形背板。
- 记录每次验证时的：
  - root repo commit
  - niri commit
  - Quickshell commit
  - niri config commit
  - 输出分辨率和 scale
- 暂停继续微调 QML 半径，避免把系统问题伪装成局部参数问题。

`scripts/capture-glass-baseline.sh` 的用途：

- 记录 root / niri / Quickshell 的 commit 和 dirty 状态。
- 记录 Tahoe niri config、已部署 config、已部署 `shell.qml` 的 hash。
- 记录三张 Phase 0 基线截图的 SHA-256，确认参考图没有变。
- 记录 session 环境变量，例如 `WAYLAND_DISPLAY`、`NIRI_SOCKET`。
- 在 niri IPC 可用时记录 `niri msg focused-output`、`niri msg outputs` 和 JSON outputs，用来绑定输出分辨率、scale、当前显示器状态。

它不做这些事：

- 不修复圆角或玻璃问题。
- 不部署 QML / niri config。
- 不构建 niri 或 Quickshell。
- 不替代截图对比；它只是给截图补运行环境证据。

使用时机：

- 每个 phase 开始前，在 Arch VM 的 Tahoe niri 会话里跑一次。
- 每个 phase 改完并截图前，再跑一次。
- 如果截图效果和预期不一致，先看 runtime report 里 commit、config hash、输出 scale 是否变了。

验收：

- 每次架构改动前后都能对同一组 surface 截图对比。

### Phase 1：拆 namespace，移除 broad layer rule

目标：先消除“所有 Quickshell surface 都被同一条规则影响”的结构性风险。

状态：已落地。所有 Tahoe `PanelWindow` 已设置独立 `WlrLayershell.namespace`；`config/niri/tahoe-phase0.kdl` 已移除 broad `namespace="^quickshell"` 规则，并只对几何等于小玻璃面板的 Tahoe namespace 保留 layer-level shadow、`geometry-corner-radius` 和 background-effect。

任务：

- 给每个 Tahoe `PanelWindow` 设置独立 `WlrLayershell.namespace`：
  - `tahoe-wallpaper`
  - `tahoe-topbar`
  - `tahoe-dock`
  - `tahoe-spotlight`
  - `tahoe-launchpad`
  - `tahoe-control-center`
  - `tahoe-notification-center`
  - `tahoe-menu-popup`
  - `tahoe-tray-menu`
  - `tahoe-battery-popup`
  - `tahoe-notification-toast`
- 删除或废弃 `layer-rule match namespace="^quickshell"`。
- 改成精确 namespace rules。
- 只有 layer surface 几何本身等于玻璃面板时，才允许设置：
  - compositor shadow
  - `geometry-corner-radius`
  - layer-level background-effect
- 对 Spotlight、Dock、TopBar 这类大透明容器，先禁用 layer-level shadow。

验收：

- 新建 Tahoe layer 不会因为默认 namespace 而继承全局玻璃规则。
- Control Center / Notification Center 不再被 broad rule 画出方形 backing。

### Phase 2：niri 增加 blurRegion bbox 过渡修复

目标：在私有协议完成前，让现有 `BackgroundEffect.blurRegion` 尽量不再用全屏/全宽 surface 当 shader 坐标系。

状态：已落地到 `niri/src/render_helpers/background_effect.rs` 和 `niri/src/layer/mapped.rs`。layer surface 主体渲染使用 `ClientBlurRegionGeometry::BoundingBox`；窗口和 popup 保持旧的 surface 几何行为。bbox 计算会先丢弃 empty / overflow rect，再把每个 blur rect 变换到 surface 全局坐标并逐个 clamp 到 surface geometry，最后从有效交集计算 effect geometry / clip geometry。

任务：

- 在 `niri/src/render_helpers/background_effect.rs` 中，当 client blur region 存在时，计算所有 region rect 的 bounding box。
- 对 layer surface，把这个 bbox 作为 background-effect 的 effect geometry / clip geometry。
- 继续暂时用 `geometry-corner-radius` 作为半径来源。
- 加保护：
  - empty region 不渲染。
  - bbox clamp 到 surface geometry。
  - 溢出 rect 丢弃，不扩展到无限大。

验收：

- Spotlight 搜索栏、Dock、TopBar 的 shader rim/refraction 坐标基于内部玻璃 bbox，而不是全屏/全宽 layer。
- 视觉上不再出现明显全屏级的液态透镜边缘。

限制：

- 这仍然无法从 `wl_region` 恢复真实 per-corner radius。
- 它只是私有协议完成前的桥接方案。

### Phase 3：整理 QML，为 compositor-owned glass 做准备

目标：让所有组件能被迁移到 `TahoeGlassRegion`。

任务：

- 集中定义玻璃常量：
  - panel radius
  - pill radius
  - dock radius
  - menu radius
  - toast radius
  - material 名称
- 任何定义 blur/glass region 的 item，不再用 spring 改几何。
  - x / y / width / height 用 bounded NumberAnimation 或直接跳变。
  - opacity / scale 可以继续动画。
- Spotlight 拆清概念：
  - 全屏 input/scrim surface。
  - 搜索栏 glass region。
  - 结果面板 glass region。
- Launchpad 使用 `backdrop` material，不当作普通圆角 panel。

验收：

- 每个玻璃对象都能描述成一个或多个明确 rounded rect。
- 新增玻璃组件时，只需要声明 region 和 material，不需要重新调 shadow / blur / tint。

### Phase 4：niri 实现 `tahoe_glass_v1`

目标：niri 能接收、缓存、验证、渲染 Quickshell 发来的精确玻璃 region。

任务：

- 添加协议 XML。
- 注册 niri Wayland global。
- 实现请求：
  - create glass surface
  - set/update region
  - remove region
  - clear regions
- 在 `SurfaceData` 中保存 committed regions。
- region 变化时 damage old rect 和 new rect。
- 增加 namespace allowlist，默认只允许 `^tahoe-`。
- 增加 niri config material 映射，例如：

```kdl
tahoe-glass {
    material "panel" {
        blur true
        noise 0.006
        saturation 1.16
        tint-color "#ffffff"
        tint-amount 0.04
        edge-highlight 0.00
        refraction 0.000

        shadow {
            on
            softness 28
            spread 2
            offset x=0 y=8
            color "#0004"
        }
    }
}
```

涉及文件方向：

- `niri/resources/protocols/` 或项目现有 protocol 目录。
- `niri/src/protocols/`
- `niri/src/handlers/`
- `niri/src/layer/mapped.rs`
- `niri/src/render_helpers/`
- `niri/niri-config/src/appearance.rs`
- `niri/niri-config/src/layer_rule.rs`

验收：

- niri debug log 能看到 region create/update/remove。
- 无效 region 不会 crash。
- surface unmap 后 region 自动消失。
- region shadow 和 region blur 使用同一个 rounded rect。

### Phase 5：Quickshell 实现 `TahoeGlass`

目标：QML 能声明 exact glass regions，并通过私有协议发送给 niri。

任务：

- 添加 Quickshell Wayland module。
- 生成/接入 `tahoe_glass_v1` client stub。
- 添加 QML API：
  - `TahoeGlass` attached object，或
  - `TahoeGlassRegion` QML object。
- 实现 item-to-surface 坐标映射。
- 支持多 region。
- 支持协议不可用时 fallback 到 `BackgroundEffect.blurRegion`。

涉及文件方向：

- `quickshell/src/wayland/tahoe_glass/`
- `quickshell/src/wayland/CMakeLists.txt`
- `quickshell/src/wayland/init.cpp`
- `quickshell/src/core/region.*` 可复用部分坐标映射逻辑，但不能输出 `QRegion` 作为最终形状。

验收：

- QML item 的 rect/radius 能准确出现在 niri debug log。
- Spotlight 一个 surface 内可声明 search pill 和 results panel 两个 region。
- Quickshell 不再需要每个组件单独维护 compositor 侧玻璃参数。

### Phase 6：迁移 Tahoe shell 组件

目标：把现有组件从 `BackgroundEffect.blurRegion + QML 玻璃填充` 迁移到 compositor-owned glass。

推荐迁移顺序：

1. Control Center / Notification Center
   - 最简单，surface 几何接近 panel 几何。

2. MenuPopup / TrayMenu / BatteryPopup / NotificationToast
   - 小面板，半径明确。

3. Dock / TopBar
   - 验证大 layer surface 内部小 glass region。

4. Spotlight
   - 验证一个 surface 多 region。

5. Launchpad
   - 验证 fullscreen backdrop material 和 sibling layer 行为。

QML 迁移原则：

- 保留内容布局。
- 移除重复的 QML 外层玻璃 shadow。
- QML fill 可以降到很低，或只保留内描边/高光。
- `BackgroundEffect.blurRegion` 只作为 fallback。

验收：

- Control Center / Notification Center 没有蓝色矩形 backing。
- Spotlight 搜索栏外没有方形 halo。
- Dock / TopBar 的玻璃边缘跟随内部玻璃条，而不是全宽 layer。
- Launchpad 打开时不会和 Dock / TopBar 的独立玻璃互相竞争。

### Phase 7：删除旧的 broad fallback 路径

目标：让架构不容易回退到旧问题。

任务：

- 永久删除 broad `namespace="^quickshell"` glass/shadow 规则。
- 保留 explicit Tahoe namespace rules。
- 文档规定：
  - 新 Tahoe 玻璃组件必须使用 `TahoeGlass`。
  - `BackgroundEffect.blurRegion` 只用于非 Tahoe client 或协议 fallback。
- code review 规则：
  - 新增 `PanelWindow` 必须设置 namespace。
  - 新增玻璃 UI 必须声明 material 和 radius。

验收：

- 新增一个 Tahoe 面板不会因为默认 `"quickshell"` namespace 自动继承错误玻璃效果。

### Phase 8：验证矩阵

目标：覆盖所有已出现问题的路径。

组件：

- TopBar
- Dock
- Spotlight
- Launchpad
- Control Center
- Notification Center
- MenuPopup
- TrayMenu
- BatteryPopup
- NotificationToast
- snap preview / compositor 内置 UI

环境：

- VMware Arch Linux niri，1x scale。
- fractional scale，如果 VM 或真实机器可用。
- 真实 GPU session，如果可用。
- 多显示器，如果可用。

检查项：

- 圆角外没有矩形 backing。
- shadow 和 blur 使用同一个 rounded rect。
- refraction / rim 坐标基于实际 glass rect。
- 打开/关闭动画不会出现一帧巨大 blur。
- region 更新不会触发 `i32` overflow。
- Dock hover 和 Spotlight 打开时性能可接受。

## 推荐实施顺序

当前最佳顺序：

1. Phase 0：已完成，后续只在验证前后运行采集脚本。
2. Phase 1：拆 namespace，删除 broad rule。
3. Phase 2：niri 做 blurRegion bbox 过渡修复。
4. Phase 4：niri 实现 `tahoe_glass_v1`。
5. Phase 5：Quickshell 实现 `TahoeGlass` 客户端。
6. Phase 6：逐个迁移组件。
7. Phase 7：删除旧路径。
8. Phase 8：完整验证。

原因：

- Phase 1 能立即减少误伤。
- Phase 2 能在协议完成前改善大透明 surface 的错误坐标系。
- Phase 4/5 是最终架构核心。
- Phase 6 分批迁移能保持桌面一直可用。

## 最终决策

采用 compositor-owned Tahoe Glass。

不要继续把 QML `Rectangle.radius`、Quickshell `BackgroundEffect.blurRegion`、niri `geometry-corner-radius` 当成三套需要人工同步的旋钮。这个模型就是反复出现圆角和液态玻璃异常的根源。

最终状态应是：

- QML 声明玻璃意图。
- Quickshell 发送精确 rounded regions。
- niri 统一渲染 blur、tint、refraction、clip、shadow。
- niri config 控制 material 外观。
- 标准 `ext-background-effect-v1` 只作为 fallback。
