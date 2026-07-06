# Tahoe / niri Layer Animation Motion V2 研究文档与改进路线图

更新时间：2026-06-22

## 目标

在已经完成 Tahoe / niri layer animation 任务 0 到任务 12 的基础上，继续把当前“能动”的 layer open/close 动画升级为更接近 end-4 / illogical-impulse 手感的 motion system。

本阶段不以“继续迁移更多 surface”为目标，而以解决以下真实体验问题为目标：

1. 关闭面板时出现突然透明、闪一下、snapshot 接管感明显。
2. 顶栏 popup 和大面板缺少从触发来源或边缘展开的方向性。
3. 当前 layer 动画大多只是统一 `popin + fade`，和 end-4 的分层 motion language 差距明显。
4. compositor 动画和 QML 内部动画没有统一 token，导致手感碎片化。
5. close snapshot、Tahoe Glass、shadow、background-effect 在快速 toggle 时仍需要更严格的视觉和性能验证。

本路线图采用严格串行策略：完整完成一个任务并通过验收后，才能开始下一个任务。任何没有完成验收的任务都视为未完成，不允许被后续任务“顺手带过”。

## 严格串行规则

1. 每个任务必须先完成实现、验证、记录，再进入下一个任务。
2. 如果任务验收失败，必须在当前任务内修复或更新该任务目标，不得跳到后续任务。
3. 不允许在一个任务里同时重构 Rust 动画机制、QML 结构和 KDL 参数，除非该任务明确允许。
4. 不允许删除回退路径，直到明确通过性能和稳定性验收。
5. 不允许把 Tahoe 专用 namespace 写进 niri Rust 代码。
6. 不允许直接照搬 end-4 配置而不验证 niri 的曲线实现语义。

## 当前状态总结

原路线图任务 0 到任务 12 已经完成以下能力：

- niri 支持 per-layer-rule 的 `layer-open` / `layer-close` 配置。
- 已支持 `fade`、`popin`、`popout`、`slide`。
- 已支持 `origin "center"` / `origin "anchor"`、`edge`、`distance`、命名 cubic-bezier 曲线。
- close 动画通过 unmap snapshot 实现。
- Tahoe Shell 已有 `DesktopSettings.compositorLayerAnimations` 开关。
- Small Popup、Control Center、Notification Center、Spotlight、Toast 已接入 handoff。
- Launchpad 已回退到 QML 外层动画。
- Dock、Task Switcher、Window Overview 保持不迁移。

当前实际运行环境确认：

- `/home/wwt/.local/state/quickshell/by-shell/tahoe/desktop-settings.json` 中 `compositorLayerAnimations` 已为 `true`。
- `/home/wwt/.config/niri/tahoe/config.kdl` 已包含 layer animation rules。
- `/home/wwt/.local/bin/niri` 版本为 `e23bd2d9`，包含 `Fix layer open animation glass transform`。
- `/home/wwt/.config/quickshell/tahoe` 与仓库内 `/home/wwt/niri/tahoe-shell` 内容一致。

因此当前体验差距不是“没有启用”或“没有部署”，而是 motion 机制和参数仍处于 v1 阶段。

## 当前问题分析

### 问题 1：关闭时突然闪透明

当前 close 流程：

1. QML 中 `open` 变为 `false`。
2. compositor animation 模式下，PanelWindow `visible` 直接跟随 `open`。
3. layer surface unmap。
4. niri 在 unmap 前后使用 snapshot 接管视觉。
5. snapshot 执行 `popout` / `slide` / `fade`。

风险点：

- 如果 close 打断 open，snapshot 可能捕获到仍处在 open animation 中的半透明 / 缩放状态。
- close animation 又继续对 snapshot 应用 alpha，造成 double fade。
- 真实 surface 消失和 snapshot 出现之间如果视觉参数不一致，会出现接管闪烁。
- snapshot 是 flattened texture，Tahoe Glass、shadow、content、background-effect 被压成同一层，缺少 live surface 的层次。

结论：关闭闪透明不是单纯参数问题，而是 close snapshot 捕获状态和 close animation 起点不连续的问题。

### 问题 2：`origin "anchor"` 不等于真实触发点

Tahoe 顶栏 popup 的 QML 使用 `popupOriginX`，能根据 Battery / Wi-Fi / Tray 等实际按钮位置确定缩放原点。

compositor layer animation 当前只能根据 layer-shell anchor 推导 origin，例如：

- top + left
- top + right
- center

但它不知道 popup 是由哪个顶栏图标触发的。结果是：

- QML 旧路径可能更贴近真实按钮。
- compositor `origin "anchor"` 只能近似，无法表达动态 X 轴触发点。
- 对横向排列的顶栏 popup，统一 anchor origin 会显得不够“从按钮长出来”。

结论：短期应减少对精确 X origin 的依赖，优先使用 `edge-reveal top` 或轻微 `slide top`，让 motion 语义来自边缘，而不是来自不准确的缩放原点。

### 问题 3：当前 profile 过于单一

当前 Tahoe KDL 主要 profile：

- Small Popup：`popin scale-from 0.96 + opacity-from 0`
- Panel Pop：`popin scale-from 0.93 + opacity-from 0`
- Spotlight：`popin scale-from 0.98 + opacity-from 0`
- Toast：`slide right + opacity-from 0`

这解决了“surface 级动画”，但没有解决“motion language”。

end-4 的策略不是所有 layer 统一 popin。它有：

- 普通 layer surface 使用 compositor layer animation。
- 复杂面板大量 `no_anim`，交给 QML 内部做 edge reveal / StackView / 列表动画。
- sidebar、dock、toast、osk 等按语义使用 slide / fade / no_anim。
- transform 和 fade 的节奏不是完全同一套。

结论：Tahoe v2 必须按 surface 语义重新分类，不应继续把所有 popup 归为统一 popin。

### 问题 4：fade 和 transform 共用同一个 progress

当前 `LayerOpenAnim` / `LayerCloseAnim` 基本只有一个 `Animation` 进度：

- alpha 根据 progress 变化。
- scale 根据 progress 变化。
- slide offset 根据 progress 变化。

这会让动画显得像“透明地缩放一下”。end-4 / Hyprland 中可以看到：

- `layersIn` / `layersOut`
- `fadeLayersIn` / `fadeLayersOut`

也就是说空间运动和透明度可以使用不同节奏。QML 内部也有不同 token：

- element move
- element move enter
- element move exit
- opacity transition
- resize transition

结论：v2 需要把 opacity 和 transform 拆成独立 animation channel。

### 问题 5：end-4 曲线不能直接照搬

end-4 关键曲线：

```text
expressiveFastSpatial    = (0.42, 1.67), (0.21, 0.90)
expressiveDefaultSpatial = (0.38, 1.21), (0.22, 1.00)
emphasizedDecel          = (0.05, 0.7),  (0.1, 1)
emphasizedAccel          = (0.3, 0),     (0.8, 0.15)
menu_decel               = (0.1, 1),     (0, 1)
menu_accel               = (0.52, 0.03), (0.72, 0.08)
stall                    = (1, -0.1),    (0.7, 0.85)
```

niri 当前 cubic-bezier 实现通过二分法反解 `x(t)`。某些 end-4 曲线存在控制点 x 非单调或 y overshoot，例如：

- `menu_decel` 的 x2 小于 x1。
- `expressiveFastSpatial` / `expressiveDefaultSpatial` 有 y overshoot。

这在 QML / Hyprland 中可能有不同处理，在 niri 中必须逐条验证。不能直接认为相同数值会产生相同手感。

结论：v2 可以参考 end-4 曲线语言，但要建立 Tahoe-safe 曲线集。

## end-4 参考结论

参考路径：

- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/hypr/hyprland/general.lua`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/hypr/hyprland/rules.lua`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/common/Appearance.qml`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/waffle/looks/Looks.qml`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/waffle/looks/WBarAttachedPanelContent.qml`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/waffle/bar/BarPopup.qml`

核心结论：

1. end-4 的高级感来自 compositor layer animation 与 QML 内部 motion token 的组合。
2. end-4 不把所有复杂 layer 都交给 compositor 动画。
3. sidebar / dock / notification / osk 等 surface 具有明确方向性。
4. 顶栏相关 popup 常见 edge reveal，不只是 opacity + scale。
5. animation token 集中管理，而不是每个组件随手写 duration / curve。

## v2 设计原则

### 原则 1：先修连续性，再调手感

关闭闪烁、double alpha、snapshot 接管不连续属于基础质量问题。必须先解决，否则任何曲线参数都会被闪烁掩盖。

### 原则 2：减少无意义透明

大多数面板不应该从完全透明出现，尤其是玻璃面板。建议：

- small popup `opacity-from` 从 `0.75` 到 `0.88`。
- large panel `opacity-from` 从 `0.78` 到 `0.9`。
- close 不一定一路淡到 0，可以到 `0.35` 到 `0.6`，最后 unmap 时消失。

这样可以减少“闪透明”的廉价感。

### 原则 3：方向性优先于缩放

顶栏 popup 应更像从 topbar 下方 reveal 出来。

推荐：

- topbar popup：`edge-reveal top`
- notification center：`slide right`
- toast：`slide right`
- spotlight：小幅 center pop
- launchpad：QML 路径

### 原则 4：transform 和 opacity 分离

每个 layer animation 至少应能表达：

- transform duration
- transform curve
- opacity duration
- opacity curve
- opacity delay

### 原则 5：QML 内部 motion token 化

compositor 负责 surface open/close。QML 仍负责：

- toggle knob
- list expand/collapse
- search results fade
- button feedback
- stack/page transition

但这些内部动画需要统一 token，避免和 compositor 动画割裂。

## v2 推荐配置能力

### 新增 KDL 字段草案

保留现有字段：

```kdl
style "popin"
scale-from 0.98
opacity-from 0.8
duration-ms 180
curve "emphasized-decel"
origin "center"
edge "top"
distance 24
```

新增 v2 字段：

```kdl
transform-duration-ms 180
transform-curve "emphasized-decel"
opacity-duration-ms 90
opacity-curve "standard-decel"
opacity-delay-ms 0
```

兼容规则：

- 如果只写 `duration-ms` / `curve`，则同时作用于 transform 和 opacity，保持 v1 行为。
- 如果写了 `transform-*` 或 `opacity-*`，则进入 v2 分离通道。
- `duration-ms` 仍保留，避免破坏旧配置。

### 新增 style：`edge-reveal`

语义：

- open：从 edge 方向外侧或靠近边缘的位置 reveal 到最终位置。
- close：向 edge 方向收回。
- 与 `slide` 的区别：
  - `slide` 表示按配置 `distance` 做固定距离 surface 平移。
  - `edge-reveal` 表示从 bar / edge 处 reveal/retract，当前运行时按 surface 宽/高完成完整收回；`distance` 仅保留解析和兼容语义，不是短滑动距离调参。

当前实现使用 edge offset + 裁剪 reveal；不要用 `distance` 调 edge-reveal 的短位移。

后续增强可以支持 clip reveal：

- 让可见区域随进度增长。
- 更接近 end-4 负 margin edge reveal。
- 但 clip reveal 涉及 damage 和 render element 裁剪，应放到单独任务。

## Tahoe-safe 曲线集

### 直接采用

```text
emphasized-decel = cubic-bezier(0.05, 0.7, 0.1, 1)
emphasized-accel = cubic-bezier(0.3, 0, 0.8, 0.15)
menu-accel       = cubic-bezier(0.52, 0.03, 0.72, 0.08)
standard-decel   = cubic-bezier(0, 0, 0, 1)
expressive-effects = cubic-bezier(0.34, 0.80, 0.34, 1.00)
```

### 需要 Tahoe-safe 近似

end-4 `menu_decel = (0.1, 1), (0, 1)` 在 niri 当前 cubic-bezier 反解中需要谨慎。
它已保留为 `menu-decel` 兼容名称，但来自 end-4 的控制点存在 `x2 < x1`，时间轴可能非单调；不要把它作为 Tahoe compositor surface 的默认曲线。

建议新增：

```text
menu-decel-safe = cubic-bezier(0.12, 0.95, 0.16, 1)
```

### compositor surface 推荐范围

适合 compositor layer surface：

- `standard-decel`
- `expressive-effects`
- `menu-decel-safe`
- `emphasized-decel`
- `emphasized-accel`
- `menu-accel`

仅保留兼容或用于 QML 内部微交互前需单独验证：

- `menu-decel`
- `stall`
- `expressive-fast-spatial`
- `expressive-default-spatial`

### 暂不用于 compositor 大 surface

```text
expressive-fast-spatial    = cubic-bezier(0.42, 1.67, 0.21, 0.90)
expressive-default-spatial = cubic-bezier(0.38, 1.21, 0.22, 1.00)
stall                      = cubic-bezier(1, -0.1, 0.7, 0.85)
```

这些曲线可用于 QML 内部微交互或小元素，但用于 compositor 整个 glass surface 前必须单独测试 overshoot、clamp 和关闭残影。

## v2 推荐 motion profile

### Profile A：Small Popup Edge Reveal

适用：

- `tahoe-battery-popup`
- `tahoe-wifi-popup`
- `tahoe-fan-popup`
- `tahoe-clipboard-popup`
- `tahoe-menu-popup`
- `tahoe-application-menu`
- `tahoe-tray-menu`

建议：

```kdl
layer-open {
    style "edge-reveal"
    edge "top"
    distance 18
    opacity-from 0.82
    transform-duration-ms 180
    transform-curve "emphasized-decel"
    opacity-duration-ms 90
    opacity-curve "standard-decel"
}

layer-close {
    style "edge-reveal"
    edge "top"
    distance 14
    opacity-to 0.55
    transform-duration-ms 120
    transform-curve "emphasized-accel"
    opacity-duration-ms 80
    opacity-curve "menu-accel"
}
```

说明：

- 不从完全透明开始，避免 glass 闪。
- 动作主要来自边缘位移。
- close 先收回，再由 unmap 结束，不依赖全程淡到 0。

### Profile B：Dock Menu

适用：

- `tahoe-dock-app-menu`
- `tahoe-dock-window-menu`

建议先不强行 compositor 化，原因：

- dock menu 的真实 origin 来自 dock item。
- niri 目前无法知道 dock item 动态位置。
- QML 旧路径的 `popupOriginX` 可能更自然。

候选策略：

1. 暂时保留 compositor handoff，但 profile 改为 `slide bottom` / `edge-reveal bottom`。
2. 如果视觉仍不准，Dock menu 回退 QML 外层动画。

### Profile C：Control Center

适用：

- `tahoe-control-center`

建议：

```kdl
layer-open {
    style "edge-reveal"
    edge "top"
    distance 24
    opacity-from 0.84
    transform-duration-ms 210
    transform-curve "emphasized-decel"
    opacity-duration-ms 110
    opacity-curve "standard-decel"
}

layer-close {
    style "edge-reveal"
    edge "top"
    distance 20
    opacity-to 0.55
    transform-duration-ms 140
    transform-curve "emphasized-accel"
    opacity-duration-ms 90
    opacity-curve "menu-accel"
}
```

说明：

- 控制中心从顶栏展开，比 `scale-from 0.93` 更自然。
- 避免大面积 glass 缩放导致软化。

### Profile D：Notification Center Drawer

适用：

- `tahoe-notification-center`

建议：

```kdl
layer-open {
    style "slide"
    edge "right"
    distance 36
    opacity-from 0.86
    transform-duration-ms 210
    transform-curve "emphasized-decel"
    opacity-duration-ms 100
    opacity-curve "standard-decel"
}

layer-close {
    style "slide"
    edge "right"
    distance 28
    opacity-to 0.55
    transform-duration-ms 140
    transform-curve "emphasized-accel"
    opacity-duration-ms 90
    opacity-curve "menu-accel"
}
```

说明：

- Notification Center 语义更像右侧抽屉。
- 不建议继续用大幅 popin。

### Profile E：Spotlight

适用：

- `tahoe-spotlight`

建议：

```kdl
layer-open {
    style "popin"
    scale-from 0.985
    opacity-from 0
    transform-duration-ms 180
    transform-curve "emphasized-decel"
    opacity-duration-ms 120
    opacity-curve "standard-decel"
    origin "center"
}

layer-close {
    style "popout"
    scale-to 0.992
    opacity-to 0
    transform-duration-ms 110
    transform-curve "menu-accel"
    opacity-duration-ms 80
    opacity-curve "menu-accel"
    origin "center"
}
```

说明：

- Spotlight 可以保留 center pop。
- scale 必须非常小，避免文字和搜索结果发软。

### Profile F：Toast

适用：

- `tahoe-notification-toast`

建议：

```kdl
layer-open {
    style "slide"
    edge "right"
    distance 28
    opacity-from 0.75
    transform-duration-ms 180
    transform-curve "emphasized-decel"
    opacity-duration-ms 100
    opacity-curve "standard-decel"
}

layer-close {
    style "slide"
    edge "right"
    distance 22
    opacity-to 0.35
    transform-duration-ms 110
    transform-curve "emphasized-accel"
    opacity-duration-ms 80
    opacity-curve "menu-accel"
}
```

说明：

- Toast 不应抢注意力。
- close 不要突然透明，可以更像被收走。

### 保留 QML / 不迁移

继续保留：

- `tahoe-launchpad`
- `tahoe-dock`
- `tahoe-task-switcher`
- `tahoe-window-overview`

原因：

- Launchpad 大量图标和 glass，compositor 缩放容易软。
- Dock 常驻，不适合 open/close layer animation。
- TaskSwitcher 和 Overview 对响应速度和内部状态要求更高。

## 严格串行任务清单

### 任务 13A：建立 v2 基线与复现记录

目标：在改代码前记录当前 v1 的真实问题。

操作：

1. 确认当前运行的 niri 版本、Quickshell 路径、KDL 路径、`compositorLayerAnimations` 状态。
2. 对以下组件录制或截图序列：
   - Battery Popup
   - Wi-Fi Popup
   - Control Center
   - Notification Center
   - Spotlight
   - Toast
3. 每个组件至少测试：
   - 正常打开。
   - 正常关闭。
   - 打开未完成时快速关闭。
   - 连续 toggle 10 次。
4. 记录是否出现：
   - 关闭闪透明。
   - snapshot 接管跳变。
   - glass/shadow 不同步。
   - 输入区域残留。
   - 关闭后 layer 残留。

验收：

- 形成一份 baseline 记录。
- 至少包含 3 个能复现或明确不能复现的问题说明。
- 未修改功能代码。

完成条件：

- baseline 写入本文档或单独验收文档。
- 可以进入任务 13B。

13A 记录：见 `docs/layer-animation-motion-v2-task13A-baseline-2026-06-22.md`。

未完成不得进入任务 13B。

### 任务 13B：修复 close snapshot 连续性

目标：解决关闭闪透明和 double alpha 的基础机制问题。

操作：

1. 修改 `MappedLayer::store_unmap_snapshot()`，捕获 snapshot 时不要把未完成 open animation 的 alpha/scale 叠进去。
2. 为 close animation 增加起点状态：
   - `start_alpha`
   - `start_scale`
   - `start_offset`
3. 如果 close 打断 open，从当前视觉状态连续进入 close。
4. 如果 open 已完成，从完整状态进入 close。
5. 确保 Tahoe Glass、shadow、background-effect 在 snapshot 捕获和 close render 中一致。

验收：

- 快速 open -> close 不再明显闪透明。
- snapshot 不再 double fade。
- close animation 结束后 snapshot 释放。
- no animation 路径不捕获 snapshot。
- 现有 layer-shell 单元测试通过，并新增 close-interrupt-open 测试。

验收命令：

```bash
cargo fmt --check
cargo check -p niri
cargo test -p niri layer_close_animation
cargo test -p niri layer_rule_animations
cargo test -p niri-config
git diff --check
```

完成条件：

- close 基础连续性通过自动化和手动视觉验证。
- 可以进入任务 13C。

未完成不得进入任务 13C。

### 任务 13C：实现分离式 opacity / transform animation channel

目标：让 layer animation 能分别控制空间运动和透明度。

操作：

1. 在 `niri-config/src/animations.rs` 为 layer open/close 增加：
   - `transform-duration-ms`
   - `transform-curve`
   - `opacity-duration-ms`
   - `opacity-curve`
   - `opacity-delay-ms`
2. 保持 v1 兼容：
   - 未配置 v2 字段时使用 `duration-ms` / `curve`。
3. Rust runtime 中为 open/close 建立两个 animation progress：
   - transform progress
   - opacity progress
4. close snapshot 使用同样模型。
5. 添加配置解析测试和 resolved rule 测试。

验收：

- v1 KDL 配置仍可解析且行为不变。
- v2 KDL 配置可解析。
- transform 和 opacity 可使用不同 duration / curve。
- `opacity-delay-ms` 生效。
- 未配置 animations 的 layer 零成本。

验收命令：

```bash
cargo fmt --check
cargo check -p niri
cargo test -p niri-config parse_layer_rule_animation
cargo test -p niri layer_rule_animations
cargo test -p niri layer_close_animation
git diff --check
```

完成条件：

- 分离 channel 可用，并有测试覆盖。
- 可以进入任务 13D。

13C 记录：

- `LayerOpenAnim` / `LayerCloseAnim` 保留 v1 `duration-ms` / `curve` 作为兼容基准，并新增 `transform-duration-ms`、`transform-curve`、`opacity-duration-ms`、`opacity-curve`、`opacity-delay-ms`。
- open / close runtime 已拆分 transform progress 与 opacity progress；close snapshot 继续使用 13B 的 `start_alpha` / `start_scale` / `start_offset` 起点状态。
- 新增配置解析测试、resolved rule 测试、open opacity delay 打断测试、close opacity delay 生命周期测试。
- 验证通过：`cargo fmt --check`、`cargo check -p niri`、`cargo test -p niri-config parse_layer_rule_animation`、`cargo test -p niri layer_rule_animations`、`cargo test -p niri layer_close_animation`、`git diff --check`。

未完成不得进入任务 13D。

### 任务 13D：引入 Tahoe-safe end-4 inspired 曲线集

目标：参考 end-4 曲线，但避免 niri cubic-bezier 实现中的非单调风险。

操作：

1. 增加命名曲线：
   - `standard-decel`
   - `expressive-effects`
   - `menu-decel-safe`
2. 保留已有：
   - `emphasized-decel`
   - `emphasized-accel`
   - `menu-decel`
   - `menu-accel`
   - `stall`
3. 为 `menu-decel` 写明风险：来自 end-4，但 x 控制点可能非单调。
4. 测试每个命名曲线能解析。
5. 可选：增加 curve sampling debug 单元测试，确认曲线输出不会 NaN，不会严重倒退。

验收：

- 配置解析通过。
- 所有命名曲线有测试。
- 文档记录哪些曲线适合 compositor surface，哪些只适合 QML 内部。

完成条件：

- Tahoe-safe 曲线集固定。
- 可以进入任务 13E。

13D 记录：

- 新增命名曲线：`standard-decel`、`expressive-effects`、`menu-decel-safe`。
- 保留既有 end-4 inspired 曲线：`emphasized-decel`、`emphasized-accel`、`menu-decel`、`menu-accel`、`stall`。
- 在代码中标注 `menu-decel` 的非单调 x 控制点风险，并推荐 compositor surface 使用 `menu-decel-safe`。
- 新增所有命名曲线的 layer animation 配置解析测试。
- 新增 Tahoe-safe cubic-bezier 运行时采样测试，确认输出有限且没有明显倒退。

未完成不得进入任务 13E。

### 任务 13E：实现 `edge-reveal` 最小版本

目标：给顶栏 popup 和 control center 提供比 popin 更自然的方向性。

操作：

1. 在 config 增加 open style：`edge-reveal`。
2. 在 config 增加 close style：`edge-reveal`。
3. 当前 GOAL-6 语义修正后，`edge-reveal` 保持完整 surface reveal/retract；短距离平移应继续使用 `slide`。
4. 支持 edge：
   - top
   - right
   - bottom
   - left
5. 与 `slide` 的区别写入代码注释和文档：
   - `slide` 是较完整的平移进入。
   - `edge-reveal` 从边缘 reveal/retract，运行时按 surface 宽/高移动，透明度可独立调节。

验收：

- `edge-reveal top` 可用于 topbar popup。
- `edge-reveal bottom` 可用于 dock menu 候选。
- 不影响已有 `fade` / `popin` / `slide`。
- 自动测试覆盖 style 解析和 resolved rules。
- 手动视觉确认一个测试 layer surface 能按 edge reveal 方向运动。

完成条件：

- `edge-reveal` 最小版本可用。
- 可以进入任务 13F。

13E 记录：

- `LayerOpenAnimationStyle` / `LayerCloseAnimationStyle` 新增 `EdgeReveal`，KDL 支持 `style "edge-reveal"`。
- open / close runtime 已接入 `edge-reveal`。GOAL-6 语义修正后，edge-reveal 按 surface extent reveal/retract；KDL `distance` 不再作为短位移调参说明。
- 代码注释已标明：`slide` 表示按 configured distance 平移，`edge-reveal` 表示完整 surface edge reveal/retract。
- 自动测试覆盖配置解析、resolved layer rules，以及 `edge-reveal top` 打断 open 时从当前负 Y offset 连续进入 close。
- 验证通过：`cargo fmt --check`、`cargo check -p niri`、`cargo test -p niri-config parse_layer_rule_animation`、`cargo test -p niri layer_rule_animations`、`cargo test -p niri layer_close_animation`、`git diff --check`。

未完成不得进入任务 13F。

### 任务 13F：重写 Tahoe KDL motion profile 为 v2

目标：将 Tahoe layer-rule 从 v1 popin 参数切换到 v2 profile。

操作：

1. 修改 `/home/wwt/niri/config/niri/tahoe-phase0.kdl`。
2. Small Popup 改为 `edge-reveal top` profile。
3. Control Center 改为 `edge-reveal top` profile。
4. Notification Center 改为 `slide right` drawer profile。
5. Spotlight 保持 center pop，但改用 v2 分离 channel。
6. Toast 保持 slide right，但减少完全透明 fade。
7. Dock menu 暂时二选一：
   - 试 `edge-reveal bottom`。
   - 如果手感不准，回退 QML。

验收：

- `niri validate` 通过。
- 所有 v2 KDL 字段可解析。
- 各 namespace 命中对应 profile。
- 没有默认启用 Launchpad / Dock / TaskSwitcher / Overview compositor animation。

验收命令：

```bash
niri/target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo test -p niri-config
cargo test -p niri layer_rule_animations
git diff --check
```

完成条件：

- v2 KDL profile 完成。
- 可以进入任务 13G。

13F 记录：

- `/home/wwt/niri/config/niri/tahoe-phase0.kdl` 已从 v1 popin/fade profile 切到 v2 分离 channel profile。
- Small Popup 组：`tahoe-battery-popup`、`tahoe-wifi-popup`、`tahoe-fan-popup`、`tahoe-clipboard-popup`、`tahoe-menu-popup`、`tahoe-application-menu`、`tahoe-tray-menu` 使用 `edge-reveal top`，open 从 `opacity-from 0.82` 开始，close 到 `opacity-to 0.55`。
- Control Center：`tahoe-control-center` 使用 `edge-reveal top`，避免大 glass surface 继续整体 popin 缩放。
- Notification Center：`tahoe-notification-center` 使用 `slide right` drawer profile。
- Spotlight：`tahoe-spotlight` 保持 center `popin` / `popout`，但改用 `transform-duration-ms` / `opacity-duration-ms` 分离 channel。
- Toast：`tahoe-notification-toast` 保持 `slide right`，open 从 `opacity-from 0.75` 开始，close 到 `opacity-to 0.35`，减少完全透明闪烁。
- Dock menus：`tahoe-dock-app-menu`、`tahoe-dock-window-menu` 暂用 `edge-reveal bottom` 候选 profile，后续 13H 视觉调参决定是否回退 QML 外层动画。
- 未为 `tahoe-launchpad`、`tahoe-dock`、`tahoe-task-switcher`、`tahoe-window-overview` 添加 compositor layer animation rule。
- 验证通过：先重建旧的 debug binary 后执行 `niri/target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`、`cargo test -p niri-config`、`cargo test -p niri layer_rule_animations`、`git diff --check`。

未完成不得进入任务 13G。

### 任务 13G：QML motion token 化

目标：让 QML 内部微交互和 compositor motion 使用同一种语言。

操作：

1. 新增 `/home/wwt/niri/tahoe-shell/components/Motion.js` 或等价 QML singleton。
2. 定义 token：
   - `fadeFastDuration`
   - `menuEnterDuration`
   - `menuExitDuration`
   - `panelEnterDuration`
   - `panelExitDuration`
   - `elementMoveDuration`
   - `elementResizeDuration`
3. 定义 curve 名称和 QML easing：
   - emphasizedDecel
   - emphasizedAccel
   - standardDecel
   - expressiveEffects
4. 只迁移已接入 layer animation 的组件内部微交互，不改变布局结构。
5. 不删除 compositor handoff 开关。

验收：

- QML smoke 能加载。
- Battery/Wi-Fi/Control Center/Notification Center/Spotlight/Toast 内部动画仍工作。
- 没有把外层显隐重新交回 QML。
- 代码中重复 duration 明显减少。

完成条件：

- motion token 可复用。
- 可以进入任务 13H。

13G 记录：

- 新增 `/home/wwt/niri/tahoe-shell/components/Motion.js`，提供 `fadeFastDuration`、`menuEnterDuration`、`menuExitDuration`、`panelEnterDuration`、`panelExitDuration`、`elementMoveDuration`、`elementResizeDuration`，以及 QML easing token：`emphasizedDecel`、`emphasizedAccel`、`standardDecel`、`expressiveEffects`。
- 已迁移已接入 layer animation 的 Tahoe Shell 组件动画 token：Battery Popup、Wi-Fi Popup、Fan Popup、Clipboard Popup、Menu Popup、Application Menu、Tray Menu、Dock App Menu、Dock Window Menu、Control Center、Notification Center、Spotlight、Toast。
- 迁移范围只覆盖外层 QML fallback 动画和组件内部微交互，例如 toggle knob、Control Center 折叠行、Spotlight results fade、Toast height/legacy slide；未改变 `compositorLayerAnimations` handoff 开关、`visible` 分支或 layer namespace。
- 代码中目标组件的 `NumberAnimation { duration: ...; easing.type: Easing.OutCubic }` 重复写法已收敛为 `Motion.*` token。
- 验证通过：`git diff --check`、目标组件硬编码旧 duration 搜索、`QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 -a gui` 最小 Motion token smoke。
- `/usr/lib/qt6/bin/qmllint -I tahoe-shell ...` 以 0 退出；本机缺少 Quickshell/TahoeGlass qmltypes，因此仍输出既有 import/unresolved-type warning，未发现 `Motion.*` 绑定错误。

未完成不得进入任务 13H。

### 任务 13H：逐组件视觉调参

目标：不再凭感觉一次改全局参数，而是逐组件验证。

操作：

按顺序逐个验证：

1. Battery Popup
2. Wi-Fi Popup
3. Fan Popup
4. Clipboard Popup
5. Menu / AppMenu / TrayMenu
6. Dock menus
7. Control Center
8. Notification Center
9. Spotlight
10. Toast

每个组件测试：

- 正常 open。
- 正常 close。
- open 未完成时 close。
- close 未完成时 reopen。
- 连续 toggle 20 次。
- 截图或录屏观察 glass/shadow/blur。

验收：

- 每个组件有独立记录。
- 发现问题必须当前组件修完再测下一个。
- 不允许在第 10 个组件时回头大改第 1 个组件的基础机制。

完成条件：

- 所有迁移组件通过视觉调参。
- 可以进入任务 13I。

未完成不得进入任务 13I。

### 任务 13I：性能与稳定性压力测试

目标：确认 v2 不引入持续重绘、资源泄漏、输入残留。

操作：

1. Small Popup 组每个 toggle 50 次。
2. Control Center toggle 30 次。
3. Notification Center toggle 30 次。
4. Spotlight toggle 30 次，并测试快速输入。
5. Toast 触发至少 30 条。
6. 观察：
   - `niri msg layers`
   - niri log
   - CPU 占用
   - animation list 生命周期
7. 如果可用，记录 `pidstat -p $(pidof niri) 1`。
8. 如果没有 Tracy，说明未使用原因。

验收：

- 动画结束后一帧内不持续重绘。
- close snapshot 结束后释放。
- 快速 toggle 后没有 layer 残留。
- 没有 render/shader/background-effect/snapshot error。
- 关闭 `compositorLayerAnimations` 后旧 QML 路径仍可用。

完成条件：

- v2 性能和稳定性记录完成。
- 可以进入任务 13J。

未完成不得进入任务 13J。

### 任务 13J：决定默认开启范围

目标：明确哪些 surface 可以长期默认使用 compositor animation。

2026-07-06 GOAL-10 decision:

- Default motion profile remains `balanced`.
- New shell state sets `DesktopSettings.compositorLayerAnimations` default `true`; compositor layer animation is default-on.
- QML outer animation fallback remains the user rollback path when the setting is turned off.
- Launchpad、Dock、TaskSwitcher、WindowOverview 继续保持 QML path，不强行 compositor 化。
- Policy source: `tahoe-shell/docs/tahoe-motion-default-policy.md`。

操作：

1. 根据 13H/13I 结果分类：
   - 默认开启 compositor
   - 保留 QML
   - 暂缓
2. 更新 `DesktopSettings.compositorLayerAnimations` 默认值决策。
3. 如果仍默认 false，写明原因。
4. 如果改为 true，必须确认回退路径仍存在。

验收：

- 默认策略明确。
- 用户回退路径明确。
- 不再有“以后再说”的模糊状态。

完成条件：

- 可以进入任务 13K。

未完成不得进入任务 13K。

### 任务 13K：文档定稿与维护说明

目标：让 v2 能被后续维护。

操作：

1. 更新本文档：
   - 最终 profile。
   - 最终曲线。
   - 最终 namespace 矩阵。
   - 性能结果。
2. 更新 Tahoe KDL 注释。
3. 为 Rust 新增结构加模块级注释：
   - open animation lifecycle
   - close snapshot lifecycle
   - opacity / transform channel
   - edge-reveal damage 策略
4. 为 QML handoff 模式加短注释。
5. 记录回滚方式：
   - UI 开关
   - JSON 字段
   - KDL rule 注释方式

验收：

- 文档能指导后续维护。
- 配置注释和实现一致。
- 没有未解释的新字段。
- 没有未记录的 surface 策略。

完成条件：

- Motion V2 完成。

## 最终成功标准

Motion V2 完成时应满足：

1. 关闭面板不再出现明显闪透明。
2. close 打断 open 时视觉连续。
3. Small Popup 具有从 topbar 展开的方向性。
4. Control Center 不再像大 glass surface 硬缩放。
5. Notification Center 更像右侧 drawer。
6. Spotlight 保持轻量 center pop，不明显模糊。
7. Toast slide 不抢注意力。
8. QML 内部动画 token 统一。
9. end-4 曲线被参考但经过 Tahoe-safe 验证。
10. 没有持续重绘、snapshot 残留、layer 残留。
11. `compositorLayerAnimations` 回退路径仍可用。
12. Launchpad、Dock、TaskSwitcher、WindowOverview 不被强行 compositor 化。

## 推荐立即开始的第一步

从任务 13A 开始，先记录 v1 的真实问题。不要直接改参数。当前最大风险不是“参数还没调好”，而是 close snapshot 交接、double alpha 和动态锚点缺失会让任何参数都显得不自然。
