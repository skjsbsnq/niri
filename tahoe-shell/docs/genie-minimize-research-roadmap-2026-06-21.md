# Genie 最小化/恢复研究文档与顺序路线图

日期：2026-06-21

范围：Tahoe Quickshell Dock + niri fork 的窗口最小化、Dock 点击恢复、以及后续正统 Genie/神灯动画。本文只记录研究结论和路线，不代表已经实现。

## 目标

最终目标是实现 compositor 级的 Genie 最小化/恢复：

```text
窗口当前视觉内容
  -> compositor snapshot
  -> 根据 Dock 图标目标矩形做曲面/网格形变
  -> 收束到 Dock 图标
  -> 窗口进入 is_minimized=true

Dock 点击已最小化窗口
  -> 使用同一个 Dock 图标矩形作为 source rect
  -> 从图标反向展开
  -> 窗口恢复并激活
```

关键要求：

- 动画必须指向实际 Dock 图标位置，而不是屏幕底部的固定点。
- 最小化和恢复必须是同一套几何模型的正反向，避免视觉风格不一致。
- 动画不能破坏现有 `is_minimized`、IPC、foreign-toplevel 状态。
- 动画不能破坏 screencast/screencopy 的 block-out 隐私逻辑。
- 每个阶段必须完成验收后才能进入下一阶段。

## 当前源码状态

### Dock 侧已经有目标矩形雏形

`WindowButton.qml` 在点击最小化/恢复前会调用 `updateDockRectangle()`：

- `tahoe-shell/components/WindowButton.qml`
  - `updateDockRectangle()`
  - `restoreOrActivate()`
  - `minimize()`

`Windows.qml` 继续调用 Quickshell foreign-toplevel 的 `setRectangle()`：

- `tahoe-shell/services/Windows.qml`
  - `setRectangle(idOrWindow, sourceWindow, x, y, width, height)`

Quickshell 最终会发出 wlr foreign-toplevel `set_rectangle(surface, x, y, width, height)`：

- `quickshell/src/wayland/toplevel/wlr_toplevel.cpp`
  - `ToplevelHandle::setRectangle(QWindow* window, QRect rect)`

结论：Dock 到 Quickshell 的数据流已经基本具备。后续重点在 niri 侧接住并使用这个矩形。

### niri 当前忽略 Dock 目标矩形

`niri/src/protocols/foreign_toplevel.rs` 当前处理：

```rust
zwlr_foreign_toplevel_handle_v1::Request::SetRectangle { .. } => (),
```

这意味着 Dock 传来的图标矩形目前完全没有进入 compositor 状态。现有最小化动画无法知道要收束到哪里。

### 当前最小化/恢复不是 snapshot 动画

当前最小化：

- `niri/src/layout/floating.rs`
  - `set_minimized(..., true)`
  - `animate_alpha_scale(1., 0., 1., 1., window_close, true)`

- `niri/src/layout/scrolling.rs`
  - `set_minimized(..., true)`
  - `animate_alpha_scale(1., 0., 1., 1., window_close, true)`

当前恢复：

- `niri/src/layout/floating.rs`
  - `set_minimized(..., false)`
  - `animate_alpha_scale(0., 1., 1., 1., window_open, false)`

- `niri/src/layout/scrolling.rs`
  - `set_minimized(..., false)`
  - `animate_alpha_scale(0., 1., 1., 1., window_open, false)`

`Tile::render()` 遇到 `alpha_animation` 时，会把 tile 渲染进 offscreen，再整体设置 alpha 或 scale。这个路径适合淡入淡出，但不适合 Genie：

- 没有 Dock target rect。
- 没有独立 minimize snapshot 状态。
- 没有曲面/网格形变 shader。
- 没有 restore 反向 source rect。

### 关闭动画是最接近的参考实现

`niri/src/layout/closing_window.rs` 已经具备正统 compositor 动画所需的大部分技术模式：

- 保存窗口 snapshot。
- 把 snapshot 渲染成 texture。
- 处理 normal / blocked-out / blocked-out-background 多种内容。
- 使用 `ShaderRenderElement` 和 `ProgramType::Close`。
- 由 layout 的 `advance_animations()` / `are_animations_ongoing()` 驱动持续重绘。

Genie 应该参考 `ClosingWindow` 的架构，而不是继续扩展 `AlphaAnimation`。

## 当前位置抖动问题

用户已观察到：点击最小化、或者点击 Dock 恢复已最小化窗口时，窗口有一点点位置变动，看起来不舒服。

初步源码判断，抖动可能来自以下组合：

1. `alpha_animation` 期间走 offscreen 渲染路径，而非正常直接渲染路径。
2. `Tile::render()` 在 alpha path 中先 `render_inner(..., Point::new(0., 0.))`，再通过 offscreen element 的 `offset` 重新定位。
3. offscreen texture 的 encompassing geometry 会做物理像素取整，和正常 window render path 的逐元素取整不完全一致。
4. 恢复动画结束时，从 offscreen path 切回 normal render path，可能出现 1px 或亚像素级跳变。
5. scrolling 布局恢复时会 `activate_window()` / `activate_column()`，如果恢复窗口不在当前活动列，还可能伴随 view position 调整。
6. Dock 点击前会更新 `setRectangle()`，虽然 niri 目前忽略 `SetRectangle`，但 Dock 自身点击 bounce / magnification 和窗口恢复同时发生时，也会让视觉对比更明显。

在正统 Genie 之前，必须先把这个抖动压下去。否则后续曲面收束会放大同类坐标误差。

## 正统方案设计

### 1. 持久化 Dock target rect

需要让 niri 处理 foreign-toplevel `SetRectangle`：

```rust
SetRectangle {
    surface,
    x,
    y,
    width,
    height,
}
```

注意：协议中的 `x/y/width/height` 是相对 `surface` 的局部坐标，不是全局 output 坐标。

Dock 传入的是 Dock layer surface，因此 niri 侧需要：

1. 通过 `surface` 找到 root shell surface。
2. 判断它是否是 layer-shell surface。
3. 找到该 layer surface 所在 output。
4. 读取 layer surface 在 output 中的 `layer_geometry`.
5. 把 `rect` 转为 output logical 坐标：

```text
target_rect_output = layer_geometry.loc + rect.loc
```

如果 source surface 不存在、已销毁、width/height 为 0，清除 target rect。

建议保存位置：

- `ForeignToplevelManagerState` 只负责协议实例和临时请求，不适合保存长期窗口动画状态。
- 更合理的是将 target rect 写入 niri 的窗口/布局侧状态，例如：
  - `Mapped` 增加 `foreign_toplevel_rect: Option<ForeignToplevelRect>`，或
  - `Layout` 增加以窗口 id 为 key 的 `minimize_target_rects`。

推荐：先放在 `Mapped` 或与窗口生命周期绑定的结构里，避免窗口销毁后额外清理 map。

### 2. 扩展 minimize/restore 调用链

当前 API：

```rust
layout.minimize_window(&window)
layout.restore_window(&window)
```

正统方案需要变成：

```rust
layout.minimize_window(&window, target_rect)
layout.restore_window(&window, source_rect)
```

其中 `target_rect/source_rect` 可以是 `None`，用于 fallback：

- 没有 Dock rect：降级到稳定 fade，不做 Genie。
- target rect 不在同 output：降级，或先激活目标 output 后再播。
- 目标 rect 太小或无效：降级。

IPC 可选扩展：

```text
niri msg action minimize-window --id X --target-rect x,y,w,h --target-output NAME
niri msg action restore-window --id X --source-rect x,y,w,h --source-output NAME
```

但 Quickshell Dock 的主路径优先用 `foreign-toplevel.set_rectangle()`，这样符合 Wayland taskbar/dock 语义。

### 3. 新增 GenieAnimation 状态

不要继续使用 `AlphaAnimation` 做 Genie。建议新增独立结构：

```rust
struct GenieAnimation {
    anim: Animation,
    direction: GenieDirection,
    source_rect: Rectangle<f64, Logical>,
    target_rect: Rectangle<f64, Logical>,
    window_rect: Rectangle<f64, Logical>,
    snapshot: TileRenderSnapshot 或 texture buffers,
    random_seed: f32,
}

enum GenieDirection {
    Minimize,
    Restore,
}
```

放置位置有两种：

方案 A：挂在 `Tile` 上。

- 优点：窗口没有被移出 layout，restore/minimize 状态和 tile 位置容易对应。
- 缺点：最小化完成后 tile 不再渲染，但动画对象仍需要最后一帧清理；渲染顺序要额外处理，避免被 Dock 遮挡。

方案 B：像 `ClosingWindow` 一样挂在 workspace/floating/scrolling 的独立动画列表。

- 优点：更接近关闭动画，snapshot 和真实窗口状态解耦，最小化完成后不依赖 tile 是否渲染。
- 缺点：restore 反向动画需要在窗口真实 tile 恢复可见前后协调。

推荐先采用方案 B：新增 `GenieWindow` 或 `MinimizedWindowAnimation`，逻辑更接近 `ClosingWindow`，对现有 tile render path 侵入更小。

### 4. 新增 shader program

当前 shader 系统：

- `render_helpers/shaders/mod.rs`
- `render_helpers/shader_element.rs`
- `layout/opening_window.rs`
- `layout/closing_window.rs`

建议新增：

```rust
ProgramType::Genie
```

新增 shader 文件：

```text
niri/src/render_helpers/shaders/genie_prelude.frag
niri/src/render_helpers/shaders/genie.frag
niri/src/render_helpers/shaders/genie_epilogue.frag
```

最低 uniform：

```glsl
uniform sampler2D niri_tex;
uniform mat3 niri_geo_to_tex;
uniform vec4 niri_window_rect;
uniform vec4 niri_target_rect;
uniform float niri_progress;
uniform float niri_clamped_progress;
uniform float niri_direction;
uniform float niri_alpha;
uniform float niri_scale;
```

几何模型建议先做 fragment shader inverse mapping：

```text
输出区域：window_rect 和 target_rect 的 union 扩展区域
每个像素 -> 计算当前 progress 下的变形空间坐标
        -> 反算到原窗口 texture 坐标
        -> 采样 niri_tex
        -> 超出形变边界则透明
```

第一版变形可以使用“上下边缘分别插值到 target rect 上边/下边”的模型：

```text
left(y, p)  = mix(window_left,  target_left + curve_left(y),  p)
right(y, p) = mix(window_right, target_right + curve_right(y), p)
top/bottom  = mix(window_top/bottom, target_top/bottom, p)
```

为了接近神灯效果，需要：

- 下边缘更快向 Dock 收束。
- 上边缘滞后，形成“被吸进去”的感觉。
- 横向中心向 target center 偏移。
- alpha 在最后 15% 快速衰减到 0，避免 target rect 处糊成一团。

### 5. 渲染层级

Dock 是 layer-shell surface。当前窗口/层级渲染顺序受 `render_above_top_layer()` 影响。

Genie 动画为了看起来像进入 Dock 图标，建议动画元素在最小化期间渲染在 Top/Overlay layer 之上、pointer 之下，或者至少在 Dock layer 之上。

原因：

- 如果动画在 Dock 后面，窗口会被 Dock 遮挡，看起来像“消失到 Dock 背后”，不像被图标吸收。
- macOS/GNOME 类似效果一般会短暂覆盖 Dock 上方。

这可能需要在 `Niri::render_inner()` 中新增一处专用 render hook：

```text
render Genie animations
  after layer top/overlay normal
  before pointer
```

也可以先放在 workspace render 内验证几何，再移动到更高层级。

### 6. 状态切换时机

最小化时有两种选择：

方案 A：动画开始立刻 `is_minimized=true`。

- 优点：输入/hit-test 立即不可用，状态及时同步。
- 缺点：动画期间真实窗口已被 layout 排除，需要独立 snapshot 渲染。

方案 B：动画完成后才 `is_minimized=true`。

- 优点：真实窗口仍在 layout 里。
- 缺点：动画期间窗口仍可能被命中，foreign-toplevel 状态延迟，Dock 状态不一致。

推荐方案 A。正统 snapshot 动画本来就应与真实窗口状态解耦。

恢复时建议：

1. 收到 restore。
2. 先让窗口回到 layout，设置不可交互或动画遮罩。
3. 播放 source rect -> window rect 的反向 Genie。
4. 动画完成后恢复正常渲染和输入。

如果短期内不加“不可交互”状态，至少要保证恢复开始时窗口不会闪一下正常大小再开始动画。

## 顺序路线图

规则：必须完成当前阶段的所有验收项，才能进入下一阶段。不得跳阶段并行推进。

### Phase 0：修复当前 minimize/restore 位置抖动

目标：在现有 fade 动画下，点击最小化/恢复不再出现可见位置跳动。

研究点：

- 对比 normal render path 和 `alpha_animation` offscreen path 的最终物理像素位置。
- 检查 `OffscreenBuffer::render()` 返回的 `elem.offset()` 是否导致 1px/fractional 偏移。
- 检查 restore 动画结束后从 offscreen path 切回 normal path 是否有跳变。
- 分别测试 floating、scrolling、fractional scale、CSD shadow 窗口、SSD/无边框窗口。

建议修法：

- 当 `alpha_scale == 1` 且只做透明度时，优先避免 offscreen rescale path，尽量直接复用正常 render path 的位置。
- 或者让 offscreen path 的 location/offset 计算严格匹配 normal path。
- 对 restore 动画完成帧和 normal 第一帧做同一坐标取整。

验收：

- 点击原生最小化按钮，窗口淡出期间无可见位移。
- 点击 Dock 恢复，窗口淡入期间和淡入结束瞬间无可见位移。
- 100%、125%、150% scale 下均无 1px 跳动。
- floating 窗口位置和大小不变。
- scrolling 窗口恢复不产生额外横向滑动，除非恢复目标本来不在当前视图。
- 通过现有 layout minimize/restore 测试。

完成条件：用户肉眼确认抖动消失，且最小化/恢复基础功能无回归。

### Phase 1：接入并保存 Dock target rect

目标：niri 能接收并保存 foreign-toplevel `SetRectangle`，但暂不改变动画。

任务：

- 修改 `ForeignToplevelHandler`，增加 rectangle 请求入口。
- 在 `foreign_toplevel.rs` 处理 `SetRectangle { surface, x, y, width, height }`。
- 将 source surface-local rect 转换为 output logical rect。
- 保存到目标窗口关联状态。
- source surface 销毁、rect 为 0、窗口销毁时清理。
- 增加 debug log，方便确认 Dock rect 是否正确。

验收：

- Dock hover/click 前设置的 rect 能在 niri 日志中看到。
- rect 坐标与 Dock 图标位置一致。
- 多输出下 rect 归属 output 正确。
- Dock 重启或 surface 销毁后不会留下旧 rect。
- 不改变现有 minimize/restore 行为。

完成条件：target rect 数据可靠可用，并有测试或手动验证记录。

### Phase 2：扩展 minimize/restore 内部 API

目标：layout 层能接受 `target_rect/source_rect`，但仍使用稳定 fade fallback。

任务：

- `layout.minimize_window()` 增加可选 target rect 参数。
- `layout.restore_window()` 增加可选 source rect 参数。
- `workspace/floating/scrolling` 透传 rect。
- foreign-toplevel minimize/restore 从保存状态读取 rect。
- IPC action 暂可不扩展；如扩展，必须保持旧 CLI 兼容。

验收：

- 没有 rect 时行为与当前一致。
- 有 rect 时不会改变窗口最终位置/大小。
- IPC `minimize-window --id` 和 `restore-window --id` 继续可用。
- Quickshell Dock 点击路径能把 rect 传到 layout 层。

完成条件：rect 已进入 minimize/restore 决策路径，但还不做形变。

### Phase 3：新增 snapshot 型 minimize 动画框架

目标：最小化不再依赖 `AlphaAnimation`，而是创建独立 snapshot animation，但视觉仍可先用 fade/scale fallback。

任务：

- 新增 `MinimizeWindowAnimation` 或 `GenieWindow`。
- 复用 `TileRenderSnapshot` / `RenderSnapshot` 的 block-out 逻辑。
- 在 minimize 开始时保存 snapshot。
- 真实窗口立即进入 `is_minimized=true`，输入和 hit-test 排除。
- snapshot 动画独立渲染到完成。
- 加入 `advance_animations()` 和 `are_animations_ongoing()`。

验收：

- 最小化期间窗口不可点击。
- 最小化状态立即同步到 IPC/foreign-toplevel。
- 动画完成后 snapshot 清理。
- screencast/screencopy block-out 不回归。
- 没有 Dock rect 时 fallback 仍稳定。
- 当前 Phase 0 修复的位置抖动不复发。

完成条件：snapshot minimize 框架稳定，虽然还不是神灯形变。

### Phase 4：新增 snapshot 型 restore 动画框架

目标：恢复也使用 source rect -> window rect 的独立 snapshot/遮罩路径，避免先闪现正常窗口。

任务：

- restore 开始时读取 source rect。
- 恢复真实窗口到 layout，但动画期间用 snapshot/遮罩控制视觉。
- 动画完成后切回正常 tile render。
- 处理 restore 时目标 workspace/output 不可见的策略：
  - 推荐第一版：先激活目标 workspace/output，再播放 restore。
  - 如果无法获得 source rect，则 fallback fade。

验收：

- Dock 点击已最小化窗口，不出现正常大小窗口先闪一下。
- restore 后焦点、workspace、output 正确。
- restore 期间窗口不产生 1px 位移。
- 快速重复点击不会叠加多个 restore 动画。

完成条件：restore snapshot 框架稳定，仍可先使用非 Genie 视觉。

### Phase 5：实现第一版 Genie shader

目标：实现从窗口到 Dock rect 的可见收束形变，以及反向展开。

任务：

- 新增 `ProgramType::Genie`。
- 新增 genie shader 编译入口。
- 新增 uniforms：window rect、target rect、progress、direction、texture matrix。
- 第一版 fragment shader inverse mapping。
- 对无 shader / 编译失败做 fallback。
- 调整动画曲线和时长，避免过慢或眩晕。

验收：

- 最小化明显收束到 Dock 图标。
- 恢复明显从 Dock 图标展开。
- floating 和 scrolling 都可用。
- 不同窗口尺寸下无明显拉裂、黑边、残影。
- 100%、125%、150% scale 下可用。
- shader 编译失败时不影响基本最小化/恢复。

完成条件：视觉上已经是可接受的 Genie 第一版。

### Phase 6：处理动画中断与反向接续

目标：快速点击、连续 minimize/restore、窗口关闭等边界稳定。

任务：

- minimize 动画中收到 restore：从当前 progress 反向播放。
- restore 动画中收到 minimize：从当前 progress 反向播放。
- 动画中窗口关闭：取消 Genie，转 close 或直接清理。
- Dock rect 更新时决定是否重定向目标。
- 输出断开或 Dock surface 消失时 fallback。

验收：

- 快速双击 Dock 不会卡住窗口。
- minimize/restore 反复切换不会留下不可见但未最小化的窗口。
- 窗口关闭不会遗留动画元素。
- 输出变化不会 panic。

完成条件：边界行为稳定，能日常使用。

### Phase 7：视觉调优与性能优化

目标：让 Genie 效果接近 GNOME/macOS 插件的手感，同时保持性能。

任务：

- 调整曲线：下边缘快、上边缘滞后、末端 alpha 衰减。
- Dock 图标附近增加轻微 squash，避免最后变成硬矩形。
- 限制 shader area 为 window rect 与 target rect 的 union + padding，避免全屏过度绘制。
- 检查 damage 区域。
- 检查低端 GPU / VMware / Hyper-V 表现。

验收：

- 常见窗口大小下动画稳定 60fps 或接近显示刷新率。
- 没有明显过绘导致的卡顿。
- Dock 上方收束自然。
- 用户确认观感达到预期。

完成条件：视觉和性能都可接受。

### Phase 8：测试、文档、回归护栏

目标：把实现固化为可维护能力。

任务：

- 增加 layout 状态测试。
- 增加 foreign-toplevel `SetRectangle` 行为测试。
- 增加 minimize/restore snapshot 生命周期测试。
- 增加手动测试脚本或 visual-test 场景。
- 更新用户配置文档和 Tahoe roadmap。

验收：

- `cargo test` 相关测试通过。
- 手动测试矩阵完成：
  - floating
  - scrolling
  - 多输出
  - fractional scale
  - CSD shadow
  - SSD/无边框
  - minimized restore
  - 快速反复点击
  - Dock 重启
- 文档记录 fallback 行为和已知限制。

完成条件：实现可维护，可作为默认 Tahoe 行为继续迭代。

## 不允许跳过的门槛

1. Phase 0 未完成，不进入 Genie。当前位置抖动必须先解决。
2. Phase 1 未完成，不写 shader。没有可靠 target rect，shader 只能是假效果。
3. Phase 3/4 未完成，不做曲面形变。没有 snapshot 框架，状态会混乱。
4. Phase 5 未完成，不做视觉调优。先保证几何正确，再调手感。
5. 任一阶段出现 minimize/restore 基础功能回归，立即停止推进并修复。

## 当前最推荐的下一步

先做 Phase 0：修复现有最小化/恢复的位置抖动。

理由：

- 用户已经能感知到这个问题。
- 它和后续 Genie 共享同一类坐标/rounding/offscreen 问题。
- 如果不先解决，Genie 实现后定位误差会更明显。
- Phase 0 完成后，即使暂时不做 Genie，现有体验也会立刻变好。

Phase 0 的第一项代码研究建议：

1. 在 `Tile::render()` 的 alpha path 中记录：
   - `location`
   - `elem.offset()`
   - `location + offset`
   - normal path 下窗口首个 render element geometry
2. 分别对 floating 和 scrolling 做最小化/恢复。
3. 在 fractional scale 下复测。
4. 如果差异来自 offscreen offset，优先让 alpha-only 动画不走 offscreen path。

