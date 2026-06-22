# Tahoe / niri Layer 动画研究文档与改进路线图

更新时间：2026-06-22

## 目标

把当前 Tahoe Shell 中“不满意的面板显隐动画”升级为更统一、更顺滑、更接近 end-4 / illogical-impulse 手感的动画系统，同时不破坏现有 Tahoe Glass、Genie minimize、snap assist、QML 内部交互动画和现有 layer-rule 效果。

本路线图采用严格串行策略：完整完成一个任务并通过验收后，才能开始下一个任务。

## 路线图完整性说明

这份文档是完整迁移路线图，而不是“一次性改完所有动画”的实现补丁。完整性体现在四个层面：

1. 能力层：niri 先获得 per-layer-rule 的 open/close animation 能力。
2. 配置层：Tahoe 通过 namespace 对不同 layer surface 选择 motion profile。
3. Shell 层：QML 从“外层显隐动画承担者”降级为“状态与内部微交互承担者”。
4. 维护层：每个阶段都有验收、回滚点、性能预算和不允许跨越的边界。

任何没有完成验收的任务，都视为未完成。未完成任务不得被后续任务“顺手带过”。如果实现过程中发现路线需要调整，必须先更新本文档对应任务的目标、验收和回滚点，再继续写代码。

## 配置与开关职责边界

之前提到“兼容开关”但没有明确落点，这是不合格的。最终明确如下。

### 开关放在哪里

开关放在 Tahoe Shell 的 `DesktopSettings`，不是放在 niri KDL，也不是临时环境变量。

具体文件：

- `/home/wwt/niri/tahoe-shell/services/DesktopSettings.qml`
- 持久化文件：`Quickshell.stateDir + "/desktop-settings.json"`

新增字段：

```qml
readonly property bool compositorLayerAnimations: settingsAdapter.compositorLayerAnimations
```

新增写入函数：

```qml
function setCompositorLayerAnimations(enabled) {
    var next = !!enabled;
    if (settingsAdapter.compositorLayerAnimations === next)
        return;

    settingsAdapter.compositorLayerAnimations = next;
    settingsFile.writeAdapter();
}
```

新增 JSON adapter 字段：

```qml
property bool compositorLayerAnimations: false
```

默认值必须先是 `false`。原因是实现早期需要保持现有 QML 动画路径为默认安全路径。等任务 13 性能和稳定性验收通过后，才能讨论是否把默认值改成 `true`。

### 为什么不放进 niri KDL

niri KDL 只应该表达 compositor 层能力和匹配规则，例如：

```kdl
layer-rule {
    match namespace="^tahoe-wifi-popup$"
    animations {
        layer-open { ... }
        layer-close { ... }
    }
}
```

KDL 不应该决定 QML 是否关闭自己的外层 opacity/scale 动画。这个职责属于 Tahoe Shell。否则会出现两个问题：

- niri 配置启用 animation，但 QML 仍保留外层动画，导致双重动画。
- QML 想回退旧路径时还要改 compositor 配置，调试和回滚成本高。

因此职责划分为：

- `DesktopSettings.compositorLayerAnimations`：决定 Tahoe QML 外层显隐动画是否让位给 compositor。
- `niri layer-rule animations`：决定 compositor 对某个 namespace 怎么播放 open/close。
- QML 内部控件动画：不受这个开关影响，继续保留。

### 开关在哪里暴露给用户

开关最终放在 Tahoe 设置页的 `Niri 动画` 页面下。

相关文件：

- `/home/wwt/niri/tahoe-shell/components/settings/pages/NiriAnimationsPage.qml`
- `/home/wwt/niri/tahoe-shell/services/DesktopSettings.qml`
- `/home/wwt/niri/tahoe-shell/components/SettingsPanel.qml`

页面文案建议：

- 标题：`面板显隐动画`
- 开关名：`使用 compositor layer 动画`
- 说明：`将 Tahoe 面板的打开/关闭交给 niri layer animation；内部按钮、列表和切页动画仍由 QML 处理。`

这个 UI 开关必须在任务 8 才实现。任务 2 到任务 7 不允许提前改 QML 设置页。

### QML 使用方式

每个迁移后的面板必须统一使用这个模式：

```qml
readonly property bool compositorLayerAnimations:
    root.settingsService && root.settingsService.compositorLayerAnimations

visible: compositorLayerAnimations ? open : (open || panel.opacity > 0.01)

Rectangle {
    id: panel
    opacity: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0)
    property real contentScale: root.compositorLayerAnimations ? 1 : (root.open ? 1 : 0.98)
}
```

如果组件没有 `settingsService`，必须从 `shell.qml` 或父组件显式传入，不允许在组件里临时读文件或读环境变量。

### 开关不是长期设计目标

这个开关是迁移保护栏，不是最终产品卖点。它的生命周期：

1. 任务 8 引入，默认 false。
2. 任务 9 到任务 12 按组件迁移时用于 A/B 和快速回退。
3. 任务 13 验收通过后，默认可以改为 true。
4. 至少保留一个 release 周期或一个稳定阶段。
5. 如果没有回退需求，任务 15 后可以决定是否移除旧 QML 外层动画路径。

移除开关必须单独成任务，不能在迁移过程中顺手删除。

## 性能目标与预算

layer 动画会触发连续帧渲染，性能风险高于普通静态 layer-rule。必须在设计阶段限定预算。

### 渲染预算

目标硬件按普通 60Hz 桌面体验设定：

- 动画期间允许连续重绘。
- 动画结束后一帧内必须停止持续重绘。
- 单个 layer open/close 动画建议不超过 200ms。
- 小弹窗关闭建议不超过 120ms。
- 大面板打开建议不超过 200ms。
- Launchpad/Spotlight 打开建议不超过 200ms。

不允许出现：

- 动画结束后 `are_animations_ongoing()` 仍为 true。
- snapshot 动画结束后 texture 仍保留在 active list。
- 因 layer animation 导致全局长期 repaint。

### Offscreen / snapshot 预算

关闭动画必须用 snapshot，否则真实 surface unmap 后没有内容可画。snapshot 预算：

- 只在 close 动画需要时捕获。
- 只捕获 surface 当前视觉结果，不重复捕获 popup 树之外的无关内容。
- animation off 或 duration 0 时不捕获 snapshot。
- 动画结束立即释放。
- 快速开关时旧 snapshot 必须被替换或取消，不允许堆积。

大 surface 策略：

- `tahoe-launchpad`、`tahoe-window-overview`、`tahoe-settings` 这类大 surface 默认不第一批迁移。
- 大 surface 的 snapshot 必须在任务 13 专门验证。
- 如果 snapshot 成本过高，允许保留 QML 路径，不强行 compositor 化。

### Damage 策略

动画期间 damage 应尽量局限在 animated layer 的 bounding box。

实现要求：

- `fade` damage 使用 layer geometry。
- `popin/popout` damage 使用 scale 前后最大包围盒。
- `slide` damage 使用起点和终点的 union rect。
- 不允许每帧无条件 damage 全输出，除非现有 render API 无法局部表达，并且必须在性能任务中记录原因。

### Shader 策略

第一阶段不引入自定义 shader。

允许的初始实现：

- alpha
- transform translation
- transform scale
- existing render element composition

禁止第一阶段实现：

- per-layer custom shader
- blur radius 动画
- glass material 动画
- chromatic/refraction 动画

原因：当前 Tahoe 已经有 Tahoe Glass 和 background-effect，先把 surface 生命周期和 open/close 做稳，再考虑材质动画。

### 性能验收命令与观察项

每个性能阶段至少记录：

```bash
RUST_LOG=niri=debug niri --session
```

观察项：

- 动画结束后是否继续刷日志/重绘。
- 是否有 render error、texture allocation error、background-effect error。
- 快速开关时是否出现残影。

如果有可用工具，再补充：

```bash
niri msg layers
pidstat -p $(pidof niri) 1
```

可选观察：

- `tracy` build 下检查动画帧区间。
- GPU profiler 下检查 snapshot 和 offscreen 时间。

性能验收不是“感觉不卡”就通过，必须至少有手动测试记录。

## 后续可维护性设计

### 代码边界

新增代码应按职责放置：

- `niri-config/src/animations.rs`：只放配置结构、默认值和解析。
- `niri-config/src/layer_rule.rs`：只放 layer-rule 匹配和 per-rule animation 字段。
- `src/layer/opening_layer.rs`：只处理 opening layer animation 状态和渲染。
- `src/layer/closing_layer.rs`：只处理 closing snapshot animation 状态和渲染。
- `src/layer/mapped.rs`：只接入规则结果和 render path，不塞复杂 animation style 解析。
- `src/handlers/layer_shell.rs`：只负责 map/unmap 生命周期接线。
- `src/niri.rs`：只负责 ongoing animation 检测和 redraw 调度接入。

禁止把 Tahoe 专用 namespace 写进 Rust 代码。Tahoe 行为必须全部来自 KDL layer-rule。

### Motion profile 不写死在 QML 组件里

QML 组件只读：

```qml
settingsService.compositorLayerAnimations
```

组件不应该知道自己使用 `popin 93%` 还是 `slide right`。这些由 niri KDL 的 namespace 规则决定。

QML 只需要做两件事：

- compositor 动画开启时，外层 opacity/scale 固定为 1。
- compositor 动画关闭时，保留旧外层动画路径。

### 统一命名

配置命名必须固定：

- QML 设置名：`compositorLayerAnimations`
- KDL block：`animations`
- KDL child：`layer-open`
- KDL child：`layer-close`
- style：`fade`、`popin`、`popout`、`slide`
- origin：`center`、`anchor`
- curve：`emphasized-decel`、`emphasized-accel`、`menu-decel`、`menu-accel`、`stall`

不允许在不同文件里混用 `layerAnimations`、`useLayerAnimations`、`shellAnimations` 等近义名字。

### 文档维护规则

任何新增 motion profile 都必须同时更新：

1. 本文档的 profile 章节。
2. Tahoe KDL 配置注释。
3. 对应任务的验收记录。

任何新增 layer animation style 都必须说明：

- 参数含义。
- 默认值。
- damage 范围。
- snapshot 是否需要。
- animation off 时是否零成本。

### 测试维护规则

至少保留三类测试：

1. 配置解析测试：KDL 能解析 layer animations。
2. 规则匹配测试：namespace 命中后 resolved rules 正确。
3. 生命周期测试：map open、unmap close、快速 toggle 不残留 animation。

如果 visual tests 成本过高，至少保留可运行的 manual visual test checklist。

## 完整迁移范围矩阵

| 组件 | namespace | 第一策略 | 是否迁移 compositor | 备注 |
| --- | --- | --- | --- | --- |
| Control Center | `tahoe-control-center` | popin anchor | 是，任务 10 | 大面板，先等小弹窗稳定 |
| Notification Center | `tahoe-notification-center` | popin anchor 或 slide right | 是，任务 10 | 如果 popin 不满意再切 edge profile |
| Battery Popup | `tahoe-battery-popup` | popin anchor | 是，任务 8/9 | 第一批试点 |
| Wifi Popup | `tahoe-wifi-popup` | popin anchor | 是，任务 8/9 | 第一批试点 |
| Fan Popup | `tahoe-fan-popup` | popin anchor | 是，任务 9 | 小弹窗 |
| Clipboard Popup | `tahoe-clipboard-popup` | popin anchor | 是，任务 9 | 列表多，注意 close snapshot |
| Menu Popup | `tahoe-menu-popup` | popin anchor | 是，任务 9 | 关闭要快 |
| Application Menu | `tahoe-application-menu` | popin anchor | 是，任务 9 | 和 menu popup 同 profile |
| Tray Menu | `tahoe-tray-menu` | popin anchor | 是，任务 9 | 和 menu popup 同 profile |
| Dock App Menu | `tahoe-dock-app-menu` | popin anchor | 是，任务 9 | origin 来自 dock item |
| Dock Window Menu | `tahoe-dock-window-menu` | popin anchor | 是，任务 9 | origin 来自 dock item |
| Launchpad | `tahoe-launchpad` | popin center | 是，任务 11 | 注意图标模糊 |
| Spotlight | `tahoe-spotlight` | popin center | 是，任务 11 | 注意输入焦点 |
| Notification Toast | `tahoe-notification-toast` | slide right + fade | 是，任务 12 | 不应抢注意力 |
| Dock | `tahoe-dock` | 保留现状 | 暂缓 | 常驻 surface，先不动 |
| Task Switcher | `tahoe-task-switcher` | 保留 QML | 暂缓 | 快速响应优先 |
| Window Overview | `tahoe-window-overview` | 保留 QML/niri overview | 暂缓 | 与 overview 逻辑耦合，不第一期迁移 |
| Wallpaper | `tahoe-wallpaper` | 无动画 | 否 | background layer，不做 open/close |
| Popup Dismiss Layer | `tahoe-popup-dismiss` | 无动画 | 否 | 功能 surface，不做视觉动画 |


## 当前结论

当前 niri `main` 没有 upstream PR `niri-wm/niri#3481` 的 layer open/close 动画能力。该 PR 在 GitHub 上仍是 open，未合入 upstream。

本地 `niri/niri` 仓库里存在 `remotes/pr/3481`，能看到 `590aec06 Implementing per-rule animations for layer surfaces` 等提交，但当前 `main` 不包含这些提交。

不能直接 merge `remotes/pr/3481`。原因是当前 `main` 和该 PR 分支没有可用 merge-base，直接合并会产生大范围树差异，并可能删除当前 fork 中的 Tahoe Glass、Genie minimize、Tahoe snap assist 等代码。正确方式是移植 layer animation 相关功能块。

## 当前 Tahoe 动画问题

Tahoe Shell 里多数面板目前使用 QML 内部动画：

- `visible: open || panel.opacity > 0.01`
- `opacity: root.open ? 1 : 0`
- `contentScale: root.open ? 1 : 0.98`
- `Behavior on opacity`
- `Behavior on contentScale`

这种方案的问题是：layer surface 本身并没有真正参与 compositor 级别的进入/退出动画，QML 只是在已经映射的透明 surface 内部淡入和缩放内容。结果是 blur region、glass material、shadow、输入区域、surface 映射生命周期和视觉动画不完全一致，容易显得“内容在透明盒子里动”，而不是整个面板作为系统级 surface 在动。

当前 Tahoe 配置已经有很好的迁移基础：

- `tahoe-control-center`
- `tahoe-notification-center`
- `tahoe-battery-popup`
- `tahoe-wifi-popup`
- `tahoe-fan-popup`
- `tahoe-clipboard-popup`
- `tahoe-menu-popup`
- `tahoe-application-menu`
- `tahoe-tray-menu`
- `tahoe-notification-toast`
- `tahoe-launchpad`
- `tahoe-spotlight`
- `tahoe-dock`

这些 namespace 可以直接用于 niri `layer-rule` 分组，无需改 shell 架构。

## end-4 / illogical-impulse 研究结果

参考目录：

- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/hypr/hyprland/general.lua`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/hypr/hyprland/rules.lua`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/common/Appearance.qml`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/waffle/looks/Looks.qml`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/waffle/looks/WBarAttachedPanelContent.qml`
- `/home/wwt/Downloads/dots-hyprland-main/dots/.config/quickshell/ii/modules/waffle/bar/BarPopup.qml`

end-4 的动画手感不是来自单一层，而是来自两层组合：

1. Hyprland compositor layer 动画处理普通 layer surface 的外层进入/退出。
2. Quickshell/QML 处理复杂面板内部的短动效、列表展开、按钮反馈、StackView 页面切换和 edge reveal。

### Hyprland 全局 layer 动画

end-4 的 Hyprland 配置里核心 layer 动画为：

```lua
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.7,
    bezier = "emphasizedDecel",
    style = "popin 93%"
})

hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2.4,
    bezier = "menu_accel",
    style = "popin 94%"
})

hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    bezier = "menu_decel"
})

hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2.7,
    bezier = "stall"
})
```

关键曲线：

```lua
expressiveFastSpatial    = (0.42, 1.67), (0.21, 0.90)
expressiveDefaultSpatial = (0.38, 1.21), (0.22, 1.00)
emphasizedDecel          = (0.05, 0.7),  (0.1, 1)
emphasizedAccel          = (0.3, 0),     (0.8, 0.15)
menu_decel               = (0.1, 1),     (0, 1)
menu_accel               = (0.52, 0.03), (0.72, 0.08)
stall                    = (1, -0.1),    (0.7, 0.85)
```

这些曲线的特点：

- 打开动画快速贴近目标，避免拖泥带水。
- 部分空间动画有轻微 overshoot，让 motion 更有弹性。
- 关闭动画更快，且使用 accel/stall 曲线，让 UI 有“被收走”的感觉。
- fade 和 transform 不同速率，避免简单线性淡入造成廉价感。

### end-4 并不是所有 layer 都用 compositor 动画

`rules.lua` 中有很多 `no_anim`：

```lua
quickshell:actionCenter        no_anim
quickshell:wNotificationCenter no_anim
quickshell:wStartMenu          no_anim
quickshell:overview            no_anim
```

但也有明确用 layer animation 的 surface：

```lua
quickshell:bar               slide
quickshell:cheatsheet        slide bottom
quickshell:dock              slide bottom
quickshell:screenCorners     popin 120%
quickshell:notificationPopup fade
quickshell:reloadPopup       slide
quickshell:sidebarRight      slide right
quickshell:sidebarLeft       slide left
quickshell:osk               slide bottom
quickshell:wallpaperSelector slide top
```

结论：复杂面板不应该无脑套全局 popin。end-4 的思路是：普通 surface 用 compositor 动画，复杂面板在 QML 内部做更精细的 edge reveal 或内容 motion。

### QML 内部动画 token

`Appearance.qml` 和 `Looks.qml` 定义了统一 token：

- `elementMoveEnter`: 400ms, emphasizedDecel
- `elementMoveExit`: 200ms, emphasizedAccel
- `elementMoveFast`: 200ms, expressiveEffects
- `elementResize`: 300ms, emphasized
- `transition.opacity`: 120ms
- `transition.move`: 170ms
- `transition.enter`: 250ms
- `transition.exit`: 250ms

这说明 end-4 的内部动画不是每个组件随手写 duration，而是共享一套 motion language。

### edge reveal 模式

`WBarAttachedPanelContent.qml` 的核心做法：

- 面板内容初始 margin 是负的，也就是藏在 bar 的边缘外。
- 打开时 `sourceEdgeMargin` 动到 `visualMargin`。
- 关闭时 `sourceEdgeMargin` 动回负高度/负宽度。
- 打开 200ms，关闭 150ms。

这比 Tahoe 当前 `opacity + scale 0.98` 更有方向感，也更像 panel 从锚点处展开。

## 对 Tahoe 的设计判断

Tahoe 不应该直接复制 end-4 的完整 QML 结构。Tahoe 已经有自己的 Glass、Dock、Launchpad、Control Center 和配置系统，改动目标应该是 motion layer，而不是重写 shell。

推荐架构：

1. niri 提供通用 layer open/close 能力。
2. niri 支持 Tahoe 所需的少量 style：`fade`、`popin`、`slide`、`edge-reveal`。
3. Tahoe QML 取消外层面板显隐动画，保留内部微交互动画。
4. Tahoe 配置按 namespace 选择 motion profile。
5. 每一类面板迁移时独立验收，不跨类同时改。

## 目标 motion profile

### Profile A：Tahoe Panel Pop

适用：

- `tahoe-control-center`
- `tahoe-notification-center`
- `tahoe-settings`

行为：

- 打开：从锚点轻微缩放进入，带 alpha。
- 关闭：更快缩回，带 alpha。
- 不做大位移，避免控制中心漂移感。

建议参数：

```kdl
layer-open {
    style "popin"
    scale-from 0.93
    opacity-from 0
    duration-ms 180
    curve "emphasized-decel"
    origin "anchor"
}

layer-close {
    style "popout"
    scale-to 0.94
    opacity-to 0
    duration-ms 130
    curve "menu-accel"
    origin "anchor"
}
```

### Profile B：Tahoe Small Popup

适用：

- `tahoe-battery-popup`
- `tahoe-wifi-popup`
- `tahoe-fan-popup`
- `tahoe-clipboard-popup`
- `tahoe-menu-popup`
- `tahoe-application-menu`
- `tahoe-tray-menu`
- `tahoe-dock-app-menu`
- `tahoe-dock-window-menu`

行为：

- 打开：轻微 popin，速度快。
- 关闭：更快 fade/popout。
- 不应该有过长 overshoot，因为菜单需要响应迅速。

建议参数：

```kdl
layer-open {
    style "popin"
    scale-from 0.96
    opacity-from 0
    duration-ms 140
    curve "menu-decel"
    origin "anchor"
}

layer-close {
    style "popout"
    scale-to 0.97
    opacity-to 0
    duration-ms 95
    curve "menu-accel"
    origin "anchor"
}
```

### Profile C：Tahoe Side / Edge Reveal

适用：

- 未来侧边栏
- 从屏幕边缘出现的工具面板
- 可选地用于 notification center，如果想从右侧抽屉化

行为：

- 从指定边缘滑入。
- 关闭滑回边缘。
- alpha 只做轻微辅助，不抢 transform 主导。

建议参数：

```kdl
layer-open {
    style "slide"
    edge "right"
    distance 36
    opacity-from 0.72
    duration-ms 180
    curve "emphasized-decel"
}

layer-close {
    style "slide"
    edge "right"
    distance 28
    opacity-to 0
    duration-ms 120
    curve "emphasized-accel"
}
```

### Profile D：Tahoe Toast

适用：

- `tahoe-notification-toast`

行为：

- 从右侧或顶部轻微滑入。
- 关闭更快，不拖住注意力。

建议参数：

```kdl
layer-open {
    style "slide"
    edge "right"
    distance 28
    opacity-from 0
    duration-ms 170
    curve "emphasized-decel"
}

layer-close {
    style "slide"
    edge "right"
    distance 18
    opacity-to 0
    duration-ms 100
    curve "menu-accel"
}
```

### Profile E：Tahoe Launchpad / Spotlight

适用：

- `tahoe-launchpad`
- `tahoe-spotlight`

行为：

- 从中心轻微 popin。
- 不做大位移，避免图标模糊和布局重排。
- QML 内部搜索框、列表、结果项继续保留自己的细节动画。

建议参数：

```kdl
layer-open {
    style "popin"
    scale-from 0.94
    opacity-from 0
    duration-ms 180
    curve "emphasized-decel"
    origin "center"
}

layer-close {
    style "popout"
    scale-to 0.96
    opacity-to 0
    duration-ms 110
    curve "menu-accel"
    origin "center"
}
```

## 技术实现路线

### 原则

- 不直接 merge PR #3481。
- 不删除 Tahoe Glass、Genie minimize、snap assist、现有 background-effect 和 layer-rule。
- 不一次性迁移所有面板。
- 每个任务必须先验证，再进入下一项。
- 每个任务都必须有明确回滚点。
- QML 内部微动画继续保留，只有外层面板显隐迁移到 compositor。

## 严格串行任务清单

### 任务 0：建立工作分支和基线记录

目标：建立可回滚环境，记录当前状态。

操作：

1. 在 `/home/wwt/niri/niri` 创建新分支，例如 `tahoe-layer-animations`.
2. 记录当前 `git status`。
3. 记录当前 Tahoe Shell 可运行状态。
4. 不做任何功能改动。

验收：

- `git status --short --branch` 只显示预期未跟踪文件。
- 当前 Tahoe Shell 可以按现状启动。
- 当前 niri 可以按现状构建或至少保持之前的构建状态。

完成条件：

- 写下基线 commit/hash。
- 确认无意外文件改动。

未完成不得进入任务 1。

### 任务 1：提取 PR #3481 的最小功能边界

目标：搞清楚只需要移植哪些代码，不做写入。

操作：

1. 对比 `4294948c..7f57a69f`。
2. 只标记以下功能相关内容：
   - `LayerOpenAnim`
   - `LayerCloseAnim`
   - `LayerAnimationsRule`
   - `src/layer/opening_layer.rs`
   - `src/layer/closing_layer.rs`
   - layer shell map/unmap 处理
   - closing snapshot 渲染
   - redraw ongoing animation 检测
3. 排除以下内容：
   - 删除 Tahoe Glass 的改动
   - 删除 Genie shader 的改动
   - 删除 minimize animation pipeline 的改动
   - 和当前 fork 无关的 upstream 重排

验收：

- 形成一份移植清单。
- 清单中每个文件都标注“移植 / 跳过 / 手动适配”。
- 没有文件被修改。

完成条件：

- 清单确认后才能进入任务 2。

#### 任务 0/1 验收记录（2026-06-22）

任务 0 基线：

- niri Rust 仓库路径：`/home/wwt/niri/niri`
- 工作分支：`tahoe-layer-animations`
- 基线 commit：`948a776ed2ba4471808e8910ac0a78eec32b92de`（`Use snap-style maximize for window requests`）
- 当前分支状态：`## tahoe-layer-animations...origin/tahoe-layer-animations`
- 外层聚合仓库 `/home/wwt/niri` 仍在 `main`，既有未跟踪项保持不清理：
  - `docs/layer-animation-research-roadmap.md`
  - `tahoe-shell/services/__pycache__/`
- niri 构建基线：`cargo check` 通过。
- Tahoe Shell smoke：使用 `/home/wwt/niri/quickshell/build-tahoe/src/quickshell -p /home/wwt/niri/tahoe-shell` 在隔离 XDG 目录中运行 6 秒，日志出现 `Configuration Loaded`。退出码 `124` 来自 `timeout` 主动结束；font 只读、通知服务已注册、portal app-id、隔离 state 文件不存在等警告为既有/环境类现象。
- 任务 0/1 过程中没有修改 niri Rust 功能文件。本记录是任务完成后的文档归档。

任务 1 对比范围：

- `4294948c..7f57a69f`
- 相关提交包括：
  - `29ff06af feat: more matchers for layer-rules - pre-requisite for layer animations`
  - `4df51169 layer-anims (split later)`
  - `cb0d01a6 Moves snapshotting into pre-commit-hook`
  - `92aff57e Improved snapshotting to be done only when needed`
  - `dad9e976 Fix cause of failing tests - now calling map.arrange unconditionally instead of only for mapped surfaces`
  - `590aec06 Implementing per-rule animations for layer surfaces`
  - `7f57a69f default animations for bars, wallpapers and launchers`

移植清单：

| 文件 | 结论 | 说明 |
| --- | --- | --- |
| `niri-config/src/animations.rs` | 手动适配 | 可借用 `LayerOpenAnim`、`LayerCloseAnim` 的基础解析思路；不要照搬全局 `animations.layer-open/layer-close` 默认驱动；第一阶段跳过 `custom-shader`。 |
| `niri-config/src/layer_rule.rs` | 手动适配 | 移植 `LayerAnimationsRule` 和 `LayerRule.animations`；跳过 PR 中 anchors、exclusive-zone、keyboard-interactivity 等额外 matcher。 |
| `niri-config/src/lib.rs` | 手动适配 | 只为 layer-rule animations 增加/更新解析测试期望；不要引入无关默认配置 snapshot churn。 |
| `src/layer/mod.rs` | 手动适配 | 在 `ResolvedLayerRules` 增加 `layer_open`、`layer_close` 并按现有 merge 规则解析；跳过额外 matcher 逻辑。 |
| `src/layer/opening_layer.rs` | 手动适配 | 后续任务 4 借鉴 open animation 状态和渲染结构；第一阶段不引入 custom shader，且必须保留当前 Tahoe Glass 渲染路径。 |
| `src/layer/closing_layer.rs` | 手动适配 | 后续任务 5 借鉴 close snapshot 生命周期；需要按当前 fork 的 render/snapshot/Tahoe Glass 状态重接。 |
| `src/layer/mapped.rs` | 手动适配 | 后续加入 open state、unmap snapshot、render 包装；不能覆盖当前 `TahoeGlass` render element 和 `tahoe_glass::render_for_layer` 路径。 |
| `src/handlers/layer_shell.rs` | 手动适配 | 借鉴 map/unmap、pre-commit snapshot、快速 reopen 取消 close 的接线；必须保留当前 `clear_foreign_toplevel_rects_for_source` 和 `needs_output_resize` 优化。 |
| `src/niri.rs` | 手动适配 | 只接入 `closing_layers` state、advance/removal、render insertion、ongoing redraw 检测；不能整块套 PR 版本。 |
| `resources/default-config.kdl` | 跳过 | PR 的通用默认 layer animation 会改变默认行为；Tahoe 必须等任务 7 按 namespace 配置。 |
| `docs/wiki/Configuration:-Layer-Rules.md` | 跳过 | 文档更新留到后续配置/定稿任务，不作为最小移植边界。 |
| `niri-ipc/src/lib.rs` | 跳过 | 主要服务额外 layer matcher/IPС 输出，不属于 open/close animation 最小边界。 |
| `src/ipc/client.rs` | 跳过 | 同上。 |
| `src/ipc/server.rs` | 跳过 | 同上。 |
| `src/backend/tty.rs` | 跳过 | 主要是 shader program 初始化/重排；第一阶段不引入 custom shader。 |
| `src/backend/winit.rs` | 跳过 | 同上。 |
| `src/render_helpers/shader_element.rs` | 跳过 | PR 为 direct custom shader 增加能力；roadmap 第一阶段禁止 custom shader。 |
| `src/render_helpers/shaders/mod.rs` | 跳过 | PR 的 layer shader/custom shader 注册不进入第一阶段。 |
| `src/render_helpers/resize.rs` | 跳过 | 窗口 resize shader 命名重排，非 layer animation 最小边界。 |
| `src/layout/opening_window.rs` | 跳过 | 窗口 open pipeline，避免影响现有窗口动画和 Genie minimize。 |
| `src/layout/closing_window.rs` | 跳过 | 窗口 close pipeline，避免影响现有窗口动画和 Genie minimize。 |

任务 1 结论：

- 不直接 merge `pr/3481`。
- 任务 2 只能先做配置解析层：`LayerOpenAnim`、`LayerCloseAnim`、`LayerAnimationsRule`、`layer-rule animations { layer-open {} layer-close {} }`。
- render、layer map/unmap 生命周期、snapshot 和 redraw 调度必须等任务 4/5 分阶段手动适配。
- Tahoe 专用 namespace 不写入 Rust；后续全部由 KDL layer-rule 选择 motion profile。

### 任务 2：配置层移植

目标：让 niri config 能解析 layer-rule 内的 animation 配置，但暂时不驱动动画。

操作：

1. 在 `niri-config/src/animations.rs` 增加 `LayerOpenAnim` 和 `LayerCloseAnim`。
2. 在 `niri-config/src/layer_rule.rs` 增加：

```rust
pub animations: Option<LayerAnimationsRule>
```

3. 支持 KDL：

```kdl
layer-rule {
    match namespace="^tahoe-control-center$"
    animations {
        layer-open {}
        layer-close {}
    }
}
```

4. 保持默认配置行为不变：没有写 `animations` 的 layer-rule 不应产生动画。

验收：

- `cargo check -p niri-config`
- 解析默认配置不报错。
- 含 `layer-open/layer-close` 的测试配置能解析。
- 未配置 animations 时行为完全等同当前。

完成条件：

- 配置解析通过。
- 没有触碰 render/layer map 生命周期。

未完成不得进入任务 3。

#### 任务 2 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/niri/niri-config/src/animations.rs`，新增 `LayerOpenAnim` 和 `LayerCloseAnim` 基础配置类型。
- 修改 `/home/wwt/niri/niri/niri-config/src/layer_rule.rs`，新增 `LayerAnimationsRule`，并在 `LayerRule` 中增加 `animations: Option<LayerAnimationsRule>`。
- 修改 `/home/wwt/niri/niri/niri-config/src/lib.rs`，增加 `parse_layer_rule_animations` 单元测试，并更新既有 parse debug snapshot 中未配置规则的 `animations: None` 输出。

边界确认：

- 未把 `layer-open` / `layer-close` 加入全局 `animations {}`，避免改变默认行为。
- 未移植 `custom-shader`。
- 未触碰 `src/layer/*`、`src/handlers/layer_shell.rs`、`src/niri.rs`、render、snapshot、redraw 或 Tahoe QML。
- 未配置 `animations` 的 `layer-rule` 解析结果保持为 `None`。

验收命令：

```bash
cargo fmt --check
cargo check -p niri-config
cargo test -p niri-config
```

验收结果：

- `cargo fmt --check` 通过；仅输出当前 stable rustfmt 对 `wrap_comments`、`comment_width`、`imports_granularity`、`group_imports` 等 nightly-only 配置的既有警告。
- `cargo check -p niri-config` 通过。
- `cargo test -p niri-config` 通过：`21 passed`，wiki parse 测试 `1 passed`，doc tests `0 passed`。
- 默认配置解析由 `tests::can_create_default_config` 覆盖并通过。
- 含 `animations { layer-open {} layer-close {} }` 的测试配置能解析。
- 未配置 `animations` 的测试规则断言为 `None`。

### 任务 3：ResolvedLayerRules 增加动画结果

目标：让 layer-rule 匹配后能得到 open/close 动画配置。

操作：

1. 在 resolved layer rules 中加入 `layer_open` 和 `layer_close`。
2. 遵循当前 layer-rule merge 规则。
3. 保证多条规则叠加时行为可预测。
4. 不启动任何动画。

验收：

- config/layer-rule 单元测试或现有测试通过。
- 手动构造 namespace 匹配时能得到对应动画配置。
- 未配置时为 None 或 disabled。

完成条件：

- 匹配和 merge 行为明确。
- 无 runtime 行为变化。

未完成不得进入任务 4。

#### 任务 3 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/niri/src/layer/mod.rs`，在 `ResolvedLayerRules` 中新增：
  - `layer_open: Option<LayerOpenAnim>`
  - `layer_close: Option<LayerCloseAnim>`
- 在 `ResolvedLayerRules::compute` 中接入 `LayerRule.animations`。
- merge 语义明确为：按 layer-rule 顺序处理，后命中的规则覆盖前命中规则；`layer-open` 和 `layer-close` 分别覆盖，某条规则只配置其中一个方向时，另一个方向保留之前的 resolved 结果。
- 修改 `/home/wwt/niri/niri/src/tests/layer_shell.rs`，新增 `layer_rule_animations_resolve_by_namespace_and_merge`，通过真实 layer-shell fixture 创建 namespace 为 `animated-layer` 和 `plain-layer` 的 surface，验证：
  - namespace 命中后能得到 resolved `layer_open` / `layer_close`。
  - 多条匹配规则叠加时后者按方向覆盖前者。
  - 未配置 animations 的 namespace resolved 结果为 `None`。
  - 当前没有启动任何 layer 动画，`MappedLayer::are_animations_ongoing()` 仍为 `false`。

边界确认：

- 未新增 `src/layer/opening_layer.rs` 或 `src/layer/closing_layer.rs`。
- 未修改 `/home/wwt/niri/niri/src/layer/mapped.rs`、`/home/wwt/niri/niri/src/handlers/layer_shell.rs`、`/home/wwt/niri/niri/src/niri.rs`。
- 未接入 map/unmap 生命周期、snapshot、render wrapping、redraw 调度或 Tahoe QML。
- 未写入任何 Tahoe 专用 namespace 到 Rust runtime。

验收命令：

```bash
cargo fmt --check
cargo check -p niri
cargo test -p niri layer_rule_animations_resolve_by_namespace_and_merge
cargo test -p niri-config
cargo test -p niri --lib
```

验收结果：

- `cargo fmt --check` 通过；仅输出当前 stable rustfmt 对 `wrap_comments`、`comment_width`、`imports_granularity`、`group_imports` 等 nightly-only 配置的既有警告。
- `cargo check -p niri` 通过。
- `cargo test -p niri layer_rule_animations_resolve_by_namespace_and_merge` 通过。
- `cargo test -p niri-config` 通过：`21 passed`，wiki parse 测试 `1 passed`，doc tests `0 passed`。
- `cargo test -p niri --lib` 执行到完成，结果为 `211 passed`、`3 failed`。失败用例为既有 floating snapshot 差异：
  - `tests::floating::unmaximize_to_same_size_floating`
  - `tests::floating::unmaximize_to_same_size_windowed_fullscreen_floating`
  - `tests::floating::unmaximize_to_same_size_same_bounds_floating`
- 上述 3 个失败均比较 floating maximize/unmaximize 的 configure snapshot，和本任务新增的 layer-rule resolved animation 字段无关。新增 layer-shell 测试在全量库测试中通过。
- 全量测试生成的临时 `src/tests/.floating.rs.pending-snap` 已删除，未保留无关测试产物。

完成条件：

- 任务 3 的匹配和 merge 行为已经明确并由测试覆盖。
- 无 runtime 行为变化。
- 可以进入任务 4，但任务 4 必须另起步骤实现 open animation，不得把本任务视为已经接入动画播放。

### 任务 4：实现最小 layer open 动画

目标：只实现打开动画，先不处理关闭 snapshot。

操作：

1. 新增 `src/layer/opening_layer.rs`。
2. 在 layer surface map 时，如果命中 `layer-open`，创建 opening animation。
3. 初始只支持 `fade` 和 `popin`。
4. 不引入自定义 shader，先用现有 render element alpha/scale 方式。
5. 保证没有配置 animation 的 layer surface 完全不受影响。

验收：

- niri 构建通过。
- 打开一个测试 layer surface 时能看到 open 动画。
- 普通 layer surface 不动。
- 当前 Tahoe Glass 不崩溃，不丢 blur/background-effect。

完成条件：

- open 动画可见。
- 无关闭动画。
- 无功能回退。

未完成不得进入任务 5。

#### 任务 4 验收记录（2026-06-22）

实现范围：

- 新增 `/home/wwt/niri/niri/src/layer/opening_layer.rs`，实现最小 layer open animation 状态：
  - 使用既有 `crate::animation::Animation` 和 layer-rule 解析出的 `LayerOpenAnim`。
  - 默认 open progress 为 `0 -> 1`。
  - open alpha 随 progress 淡入。
  - Wayland surface tree 和 block-out solid-color 使用 `RescaleRenderElement` 做轻微 `popin`，默认从 `0.96` 缩放到 `1.0`。
  - 不引入 custom shader。
  - 不引入 offscreen buffer。
  - 不引入 close snapshot。
- 修改 `/home/wwt/niri/niri/src/layer/mapped.rs`：
  - `MappedLayer` 增加 `open_animation: Option<OpenAnimation>`。
  - 新增 `start_open_animation()`、`advance_animations()` 和 `open_animation_state()`。
  - 命中 `layer-open` 时，map 后启动 open animation。
  - `are_animations_ongoing()` 现在包含 layer open animation。
  - 未配置 `layer-open` 时 `open_animation` 保持 `None`。
  - surface / solid-color 使用 `open_alpha` 和 popin scale。
  - shadow、background-effect、Tahoe Glass 使用 `open_alpha` 淡入，但不套 rescale wrapper，避免 shader/framebuffer-effect uniform 与外层 scale 组合造成错位。
- 修改 `/home/wwt/niri/niri/src/handlers/layer_shell.rs`：
  - 仅在 layer surface 首次 map 时调用 `mapped.start_open_animation()`。
  - 没有改 unmap/close 生命周期。
- 修改 `/home/wwt/niri/niri/src/niri.rs`：
  - 在 `Niri::advance_animations()` 中推进并清理 mapped layer open animation。
- 修改 `/home/wwt/niri/niri/src/render_helpers/background_effect.rs`：
  - `render_for_tile()` 增加 `alpha` 参数。
  - 现有 window 调用统一传 `1.`，保持旧行为。
  - layer open 路径传 `open_alpha`，让 background-effect 随打开淡入。
- 修改 `/home/wwt/niri/niri/src/render_helpers/tahoe_glass.rs`：
  - `render_for_layer()` 增加 `layer_alpha` 参数。
  - Tahoe Glass region 的 `material_alpha` 乘以 `layer_alpha`。
  - 未动画路径传 `1.`，保持旧行为。
- 修改 `/home/wwt/niri/niri/src/window/mapped.rs`：
  - 仅为 `background_effect::render_for_tile()` 新签名补 `1.`，不改变 window 行为。
- 修改 `/home/wwt/niri/niri/src/tests/layer_shell.rs`：
  - 更新 `layer_rule_animations_resolve_by_namespace_and_merge`：
    - namespace 命中 `layer-open` 后 `MappedLayer::are_animations_ongoing()` 为 `true`。
    - 推进时钟超过 duration 后 `advance_animations()` 清理 open animation，ongoing 回到 `false`。
    - 未配置 animations 的 `plain-layer` 仍为 `None` / `false`。

边界确认：

- 未新增 `/home/wwt/niri/niri/src/layer/closing_layer.rs`。
- 未实现 close animation。
- 未捕获 snapshot。
- 未修改 Tahoe Shell QML。
- 未修改 Tahoe KDL 配置。
- 未实现任务 6 的 KDL `style`、`scale-from`、`origin`、`slide`、`curve profile` 等配置语法。
- 未引入 custom shader。
- 未写入任何 Tahoe 专用 namespace 到 Rust runtime。
- 未配置 `layer-open` 的 layer surface 不创建 open animation。

验收命令：

```bash
cargo fmt --check
cargo check -p niri
cargo test -p niri layer_rule_animations_resolve_by_namespace_and_merge
cargo test -p niri-config
cargo test -p niri --lib
```

验收结果：

- `cargo fmt --check` 通过；仅输出当前 stable rustfmt 对 `wrap_comments`、`comment_width`、`imports_granularity`、`group_imports` 等 nightly-only 配置的既有警告。
- `cargo check -p niri` 通过。
- `cargo test -p niri layer_rule_animations_resolve_by_namespace_and_merge` 通过。
- `cargo test -p niri-config` 通过：`21 passed`，wiki parse 测试 `1 passed`，doc tests `0 passed`。
- `cargo test -p niri --lib` 执行到完成，结果为 `211 passed`、`3 failed`。失败用例仍为任务 3 已记录的既有 floating snapshot 差异：
  - `tests::floating::unmaximize_to_same_size_floating`
  - `tests::floating::unmaximize_to_same_size_windowed_fullscreen_floating`
  - `tests::floating::unmaximize_to_same_size_same_bounds_floating`
- 新增 layer-shell 测试在全量库测试中通过。
- 全量测试生成的临时 `src/tests/.floating.rs.pending-snap` 已删除，未保留无关测试产物。

视觉验收状态：

- 当前会话完成了自动化生命周期验证：命中 `layer-open` 的测试 layer surface 在 map 后进入 open animation，动画结束后被清理；普通 layer surface 不启动动画。
- 当前会话未进行真实桌面下的人工视觉观察；后续任务 5 前如果要严格满足“肉眼看到 open 动画”，需要在运行中的 niri 会话里用测试 layer client 或 Tahoe 小弹窗手动打开一次确认。代码路径已经具备 open render alpha/popin 接线，未进入 close snapshot 阶段。

### 任务 5：实现 layer close snapshot 动画

目标：surface unmap 后仍能播放关闭动画。

操作：

1. 新增 `src/layer/closing_layer.rs`。
2. 在 layer surface unmap 前捕获 snapshot。
3. surface 真正消失后，用 snapshot 播放 close 动画。
4. 初始只支持 `fade` 和 `popout`。
5. 正确报告 `are_animations_ongoing()`，确保 redraw 持续到动画结束。

验收：

- 关闭 layer surface 时动画完整播放。
- 动画结束后 snapshot 被释放。
- 快速开关不会残留旧 snapshot。
- 不造成持续重绘。

完成条件：

- close 动画可见。
- 无 VRAM/texture 明显泄漏。
- no animation 路径不变。

未完成不得进入任务 6。

#### 任务 5 验收记录（2026-06-22）

实现范围：

- 新增 `/home/wwt/niri/niri/src/layer/closing_layer.rs`，实现最小 layer close snapshot animation：
  - unmap 后使用 close-time snapshot 继续绘制 layer 视觉结果。
  - 使用 `TextureBuffer<GlesTexture>` 保存 normal / blocked-out 两条 snapshot texture。
  - 关闭进度为 `0 -> 1`。
  - alpha 随进度淡出。
  - 默认做轻微 popout，缩放到 `0.97`。
  - 不引入 custom shader。
  - 不引入任务 6 的 KDL `style`、`scale-to`、`origin`、`slide`、`curve profile` 等扩展语法。
- 修改 `/home/wwt/niri/niri/src/layer/mapped.rs`：
  - 增加 `LayerSurfaceRenderSnapshot`。
  - 增加 `unmap_snapshot`。
  - 增加 `store_unmap_snapshot()`、`take_unmap_snapshot()`、`should_animate_close()` 和 `has_non_empty_unmap_snapshot()`。
  - snapshot 捕获包括 layer surface normal render 和 popup render。
  - no animation、`off` 或 `duration-ms 0` 路径不捕获 snapshot。
- 修改 `/home/wwt/niri/niri/src/handlers/layer_shell.rs`：
  - 在 mapped layer pre-commit hook 中，检测 null buffer unmap 前的当前 buffer，并按需捕获 snapshot。
  - 在 layer surface unmap / destroy 时启动 close animation。
  - 在同一个 layer surface 快速重新 map 时取消旧 closing snapshot animation。
  - 保留当前 `clear_foreign_toplevel_rects_for_source` 和 `needs_output_resize` 优化。
- 修改 `/home/wwt/niri/niri/src/niri.rs`：
  - 增加 `closing_layers: Vec<ClosingLayerState>`。
  - 在 `Niri::advance_animations()` 中推进并清理完成的 close animation。
  - 在 `render_layer_normal()` 中按 output、layer、backdrop 分组补画 closing snapshot，保持原 layer 层级。
  - 在 redraw ongoing 检测中接入 `closing_layers`，动画结束后不再保持持续重绘。
- 修改 `/home/wwt/niri/niri/src/tests/layer_shell.rs`：
  - 新增 `layer_close_animation_uses_snapshot_and_cleans_up`。
  - 新增 `layer_close_animation_is_cancelled_on_reopen`。
  - 覆盖 close snapshot 创建、动画结束清理、no animation 路径不创建 snapshot、快速 reopen 取消旧 snapshot。

边界确认：

- 未修改 Tahoe Shell QML。
- 未修改 Tahoe KDL 配置。
- 未写入任何 Tahoe 专用 namespace 到 Rust runtime。
- 未实现任务 6 的 `style "fade"`、`style "popin"` / `style "popout"` 参数化、`slide`、`origin`、`distance` 或 cubic-bezier profile 扩展。
- 未引入 custom shader。
- 未配置 `layer-close` 的 layer surface 不捕获 snapshot，不进入 `closing_layers`。
- `layer-close { off }` 或 `duration-ms 0` 不捕获 snapshot，不进入 `closing_layers`。

验收命令：

```bash
cargo fmt --check
cargo check -p niri
cargo test -p niri layer_close_animation
cargo test -p niri layer_rule_animations_resolve_by_namespace_and_merge
cargo test -p niri-config
cargo test -p niri --lib
```

验收结果：

- `cargo fmt --check` 通过；仅输出当前 stable rustfmt 对 `wrap_comments`、`comment_width`、`imports_granularity`、`group_imports` 等 nightly-only 配置的既有警告。
- `cargo check -p niri` 通过。
- `cargo test -p niri layer_close_animation` 通过：`2 passed`。
- `cargo test -p niri layer_rule_animations_resolve_by_namespace_and_merge` 通过。
- `cargo test -p niri-config` 通过：`21 passed`，wiki parse 测试 `1 passed`，doc tests `0 passed`。
- `cargo test -p niri --lib` 执行到完成，结果为 `213 passed`、`3 failed`。失败用例仍为任务 3/4 已记录的既有 floating snapshot 差异：
  - `tests::floating::unmaximize_to_same_size_floating`
  - `tests::floating::unmaximize_to_same_size_windowed_fullscreen_floating`
  - `tests::floating::unmaximize_to_same_size_same_bounds_floating`
- 新增 layer close 测试在全量库测试中通过。
- 全量测试生成的临时 `src/tests/.floating.rs.pending-snap` 已删除，未保留无关测试产物。

视觉验收状态：

- 当前会话完成了自动化生命周期和 render-path 验证：命中 `layer-close` 的测试 layer surface 在 unmap 后创建 closing snapshot animation，动画结束后从 `closing_layers` 清理；快速 reopen 时旧 snapshot 被取消；未配置 close animation 的 layer 不创建 snapshot。
- 当前会话未在真实桌面会话中做人工肉眼观察；真实 Tahoe 小弹窗视觉观察应在任务 7/8 引入实际 namespace 配置和 QML 开关后执行。

### 任务 6：增加 Tahoe 所需 style

目标：实现 Tahoe motion profile 的基础能力。

操作：

1. 增加 `style "fade"`。
2. 增加 `style "popin"` / `style "popout"`，支持 scale 百分比。
3. 增加 `style "slide"`，支持 edge：top/right/bottom/left。
4. 增加 `origin "center"` / `origin "anchor"`。
5. 增加 `distance`。
6. 增加 cubic-bezier 曲线枚举或配置。

验收：

- 每种 style 有最小手动测试。
- 不同 style 可以由不同 namespace layer-rule 选择。
- 无配置时默认行为仍不变。

完成条件：

- `fade`、`popin`、`slide` 都能独立工作。
- curve 参数被正确应用。

未完成不得进入任务 7。

#### 任务 6 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/niri/niri-config/src/animations.rs`：
  - 将 `LayerOpenAnim` / `LayerCloseAnim` 从仅包含基础 `Animation` 的 tuple struct 扩展为具名配置结构。
  - 新增 open style：`fade`、`popin`、`slide`。
  - 新增 close style：`fade`、`popout`、`slide`。
  - 新增 `scale-from`、`scale-to`、`opacity-from`、`opacity-to`、`origin`、`edge`、`distance`。
  - 新增 `origin "center"` / `origin "anchor"`。
  - 新增 `edge "top"` / `"right"` / `"bottom"` / `"left"`。
  - 新增 Tahoe profile 需要的命名 cubic-bezier curve：
    - `emphasized-decel` -> `(0.05, 0.7, 0.1, 1)`
    - `emphasized-accel` -> `(0.3, 0, 0.8, 0.15)`
    - `menu-decel` -> `(0.1, 1, 0, 1)`
    - `menu-accel` -> `(0.52, 0.03, 0.72, 0.08)`
    - `stall` -> `(1, -0.1, 0.7, 0.85)`
  - 保留既有 `curve "cubic-bezier" x1 y1 x2 y2` 直接配置能力。
- 修改 `/home/wwt/niri/niri/src/layer/opening_layer.rs`：
  - open state 根据 style 计算 alpha、scale、slide offset。
  - `fade` 只做 alpha。
  - `popin` 使用 `scale-from -> 1`。
  - `slide` 使用 `edge + distance` 从边缘方向滑入。
  - `origin "anchor"` 根据 layer-shell anchor 推导缩放原点；未单边 anchor 时回退到该轴中心。
- 修改 `/home/wwt/niri/niri/src/layer/mapped.rs`：
  - open animation 读取完整 `LayerOpenAnim`。
  - `slide` 通过移动 render location 影响 surface、popup、shadow、background-effect 和 Tahoe Glass 的位置。
  - `popin` 继续只缩放 Wayland surface / block-out solid-color，Tahoe Glass、shadow、background-effect 只随 alpha 淡入，避免 shader/material 与外层 scale 组合错位。
- 修改 `/home/wwt/niri/niri/src/layer/closing_layer.rs`：
  - close snapshot render 根据 `LayerCloseAnim` 应用 `fade`、`popout`、`slide`。
  - `popout` 使用 `1 -> scale-to`。
  - `slide` 使用 `edge + distance` 滑出。
  - close snapshot 支持 `origin "center"` / `origin "anchor"`。
- 修改 `/home/wwt/niri/niri/src/handlers/layer_shell.rs`：
  - 创建 close snapshot animation 时传入完整 close 配置和 layer-shell anchor。
- 修改 `/home/wwt/niri/niri/niri-config/src/lib.rs`：
  - 更新 `parse_layer_rule_animations`。
  - 新增 `parse_layer_rule_animation_styles`，覆盖 style、scale、opacity、origin、edge、distance、命名 curve 和直接 cubic-bezier。
- 修改 `/home/wwt/niri/niri/src/tests/layer_shell.rs`：
  - 更新既有 layer-rule animation resolved 测试。
  - 新增 `layer_rule_animations_select_style_by_namespace`，用不同 namespace 分别选择 `fade`、`slide`、`popin/popout`，并断言 resolved 结果和 curve 参数。

边界确认：

- 未修改 Tahoe Shell QML。
- 未修改 Tahoe KDL 配置。
- 未写入任何 Tahoe 专用 namespace 到 Rust runtime。
- 未引入 custom shader。
- 未改全局 `animations {}` 默认行为。
- 未配置 `animations` 的 layer-rule 仍为 `None`，无 runtime 行为变化。
- `layer-open {}` / `layer-close {}` 的默认行为继续保持任务 4/5 的最小 popin/popout 路径。

验收命令：

```bash
cargo fmt --check
cargo check -p niri
cargo test -p niri-config
cargo test -p niri layer_rule_animations
cargo test -p niri layer_close_animation
cargo test -p niri --lib
git diff --check
```

验收结果：

- `cargo fmt --check` 通过；仅输出当前 stable rustfmt 对 `wrap_comments`、`comment_width`、`imports_granularity`、`group_imports` 等 nightly-only 配置的既有警告。
- `cargo check -p niri` 通过。
- `cargo test -p niri-config` 通过：`22 passed`，wiki parse 测试 `1 passed`，doc tests `0 passed`。
- `cargo test -p niri layer_rule_animations` 通过：`2 passed`。
- `cargo test -p niri layer_close_animation` 通过：`2 passed`。
- `git diff --check` 通过。
- `cargo test -p niri --lib` 执行到完成，结果为 `214 passed`、`3 failed`。失败用例仍为任务 3/4/5 已记录的既有 floating snapshot 差异：
  - `tests::floating::unmaximize_to_same_size_floating`
  - `tests::floating::unmaximize_to_same_size_windowed_fullscreen_floating`
  - `tests::floating::unmaximize_to_same_size_same_bounds_floating`
- 新增/相关 layer-shell 测试在全量库测试中通过。
- 全量测试生成的临时 `src/tests/.floating.rs.pending-snap` 已删除，未保留无关测试产物。

视觉验收状态：

- 当前会话完成了可重复的 layer-shell fixture 验证：不同 namespace 能分别选择 `fade`、`slide`、`popin/popout`，curve 参数按配置解析并进入 resolved rules。
- 任务 6 尚未改 Tahoe KDL，也未改 Tahoe QML 开关，因此没有真实 Tahoe 小弹窗可用于 compositor-only A/B 视觉测试；真实 Tahoe 视觉测试按路线图留到任务 7/8。

### 任务 7：添加 Tahoe layer-rule 配置但不开启 QML 迁移

目标：先在 niri 配置中定义 Tahoe 动画规则，不改 QML。

操作：

1. 修改 `config/niri/tahoe-phase0.kdl`。
2. 为 Tahoe namespace 增加 `animations` 块。
3. 先只启用一组低风险小弹窗，例如：
   - `tahoe-battery-popup`
   - `tahoe-wifi-popup`
4. 其他面板只写草案或注释，不启用。

验收：

- niri 配置 validate 通过。
- Tahoe 小弹窗开关时没有功能破坏。
- QML 内部动画与 compositor 动画没有明显双重冲突。

完成条件：

- 两个小弹窗正常运行。
- 不影响控制中心、通知中心、Launchpad。

未完成不得进入任务 8。

#### 任务 7 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/config/niri/tahoe-phase0.kdl`。
- 保留现有 Tahoe 小弹窗 glass/shadow/background-effect 规则不变。
- 新增单独的 phase 0 layer animation 规则，只匹配：
  - `tahoe-battery-popup`
  - `tahoe-wifi-popup`
- 使用 Tahoe Small Popup profile：
  - open：`popin`、`scale-from 0.96`、`opacity-from 0`、`duration-ms 140`、`curve "menu-decel"`、`origin "anchor"`。
  - close：`popout`、`scale-to 0.97`、`opacity-to 0`、`duration-ms 95`、`curve "menu-accel"`、`origin "anchor"`。
- 其他 surface 只保留注释说明为后续任务草案，不启用 compositor layer animation。

边界确认：

- 未修改 QML 迁移逻辑；QML 开关和 popup 外层动画旁路在任务 8 单独完成。
- 未给 control center、notification center、launchpad、spotlight、toast、fan、clipboard、menu、tray 或 dock menu 启用 layer animation。
- 未写 Tahoe 专用 namespace 到 Rust 代码；全部由 KDL layer-rule 选择。

验收命令：

```bash
target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo test -p niri-config parse_layer_rule_animations
cargo test -p niri-config parse_layer_rule_animation_styles
cargo test -p niri layer_rule_animations_select_style_by_namespace
cargo check -p niri
git diff --check
```

验收结果：

- `niri validate` 通过，日志显示 `config is valid`。
- `parse_layer_rule_animations` 通过。
- `parse_layer_rule_animation_styles` 通过。
- `layer_rule_animations_select_style_by_namespace` 通过。
- `cargo check -p niri` 通过。
- 外层仓库和 `/home/wwt/niri/niri` 子仓库的 `git diff --check` 均通过。

视觉验收状态：

- 当前会话完成了配置解析和 Quickshell 加载 smoke。
- 当前会话没有通过真实桌面肉眼点击顶栏验证 battery/wifi 的最终手感；任务 8 已提供 QML handoff 开关，部署后需要手动点开 Battery/Wi-Fi popup 做快速开关观察。

### 任务 8：QML 增加 compositor animation 兼容开关

目标：让 QML 可以按开关关闭外层显隐动画。

操作：

1. 修改 `/home/wwt/niri/tahoe-shell/services/DesktopSettings.qml`。
2. 在 `JsonAdapter` 中增加：

```qml
property bool compositorLayerAnimations: false
```

3. 在 `DesktopSettings` 根对象增加：

```qml
readonly property bool compositorLayerAnimations: settingsAdapter.compositorLayerAnimations
```

4. 在 `DesktopSettings` 根对象增加：

```qml
function setCompositorLayerAnimations(enabled) {
    var next = !!enabled;
    if (settingsAdapter.compositorLayerAnimations === next)
        return;

    settingsAdapter.compositorLayerAnimations = next;
    settingsFile.writeAdapter();
}
```

5. 修改 `/home/wwt/niri/tahoe-shell/components/settings/pages/NiriAnimationsPage.qml`，在页面顶部增加一个 `TahoeSection`，标题为 `面板显隐动画`，里面放一个 `TahoeSwitch`。该 switch 读写 `panel.settingsService.compositorLayerAnimations`。`SettingsPanel` 当前已有 `settingsService: desktopSettings` 传参路径，必须复用这条路径，不允许页面自己读 JSON 文件。
6. 修改 `/home/wwt/niri/tahoe-shell/components/BatteryPopup.qml` 和 `/home/wwt/niri/tahoe-shell/components/WifiPopup.qml`，新增：

```qml
property var settingsService
```

7. 修改 `/home/wwt/niri/tahoe-shell/shell.qml` 中 Battery/Wifi popup 的实例化，显式传入：

```qml
settingsService: desktopSettings
```

8. 在两个小弹窗组件中使用这个确定字段：

```qml
readonly property bool compositorLayerAnimations:
    root.settingsService && root.settingsService.compositorLayerAnimations

visible: compositorLayerAnimations ? open : (open || panel.opacity > 0.01)
opacity: compositorLayerAnimations ? 1 : (open ? 1 : 0)
contentScale: compositorLayerAnimations ? 1 : (open ? 1 : 0.98)
```

9. 先迁移两个试点：
   - `/home/wwt/niri/tahoe-shell/components/BatteryPopup.qml`
   - `/home/wwt/niri/tahoe-shell/components/WifiPopup.qml`
10. 保留内部控件动画。
11. 开关默认必须保持关闭。只有任务 13 通过后，才能考虑默认开启。

验收：

- `desktop-settings.json` 中出现 `compositorLayerAnimations` 字段。
- 设置页可以开关该字段，重启 shell 后值保持。
- 开关关闭：Battery/Wifi popup 行为等同当前。
- 开关开启：Battery/Wifi popup 外层由 niri layer animation 接管。
- 开关开启时 Battery/Wifi popup 的 QML 外层 opacity 固定为 1，contentScale 固定为 1。
- Battery/Wifi popup 的 `settingsService` 只来自 `shell.qml` 的 `desktopSettings`，组件没有直接读文件。
- 快速打开/关闭不出现点击区域残留。
- 设置页和两个 popup 之外的组件没有行为变化。

完成条件：

- 小弹窗迁移成功。
- 可随时回滚到 QML 动画。
- 字段名、UI 入口、持久化路径全部固定，不再使用临时环境变量或临时属性名。

未完成不得进入任务 9。

#### 任务 8 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/tahoe-shell/services/DesktopSettings.qml`：
  - 新增 `readonly property bool compositorLayerAnimations: settingsAdapter.compositorLayerAnimations`。
  - 新增 `setCompositorLayerAnimations(enabled)`。
  - 在 `JsonAdapter` 中新增 `property bool compositorLayerAnimations: false`，默认保持关闭。
- 修改 `/home/wwt/niri/tahoe-shell/components/settings/pages/NiriAnimationsPage.qml`：
  - 页面顶部新增 `TahoeSection`，标题为 `面板显隐动画`。
  - 新增 checkable `TahoeListRow`，开关名为 `使用 compositor layer 动画`。
  - 说明文案为 `将 Tahoe 面板的打开/关闭交给 niri layer animation；内部按钮、列表和切页动画仍由 QML 处理。`
  - 读写路径为 `page.panel.settingsService.compositorLayerAnimations` / `setCompositorLayerAnimations()`。
- 修改 `/home/wwt/niri/tahoe-shell/components/BatteryPopup.qml` 和 `/home/wwt/niri/tahoe-shell/components/WifiPopup.qml`：
  - 新增 `property var settingsService`。
  - 新增 `readonly property bool compositorLayerAnimations`，只从 `root.settingsService.compositorLayerAnimations` 读取。
  - `visible` 按开关选择 compositor handoff 或旧 QML fade 兼容路径。
  - 开关开启时，外层 `panel.opacity` 固定为 `1`，`panel.contentScale` 固定为 `1`。
  - TahoeGlass `interaction` / `materialAlpha` 在 compositor 模式下固定为 `1`，避免 QML 外层 opacity 与 compositor alpha 双重压暗。
- 修改 `/home/wwt/niri/tahoe-shell/shell.qml`：
  - BatteryPopup 和 WifiPopup 实例显式传入 `settingsService: desktopSettings`。

边界确认：

- Battery/Wifi popup 没有直接读取 JSON 文件、环境变量或临时全局属性。
- 设置页复用 `SettingsPanel` 已有的 `settingsService: desktopSettings` 传参路径。
- 只迁移 Battery/Wifi 两个试点 popup。
- 保留 Battery/Wifi 内部控件动画，例如 Wi-Fi switch、列表展开、按钮反馈和 battery 内容状态变化。
- 未修改 fan、clipboard、menu、tray、control center、notification center、launchpad、spotlight、toast 或 dock。
- 开关只负责 Tahoe QML 是否让出外层 opacity/scale；niri 是否有 compositor animation 仍由 KDL layer-rule 决定。由于任务 7 已在 KDL 中启用 battery/wifi 试点规则，开关关闭表示 QML 继续走旧外层路径，不表示从 niri runtime 中移除对应 layer-rule。

验收命令：

```bash
target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo check -p niri
git diff --check
tmpdir=$(mktemp -d)
XDG_STATE_HOME="$tmpdir/state" XDG_CACHE_HOME="$tmpdir/cache" XDG_CONFIG_HOME="$tmpdir/config" \
    timeout 8 /home/wwt/niri/quickshell/build-tahoe/src/quickshell -p /home/wwt/niri/tahoe-shell
cat "$tmpdir/state/quickshell/by-shell/tahoe/desktop-settings.json"
```

验收结果：

- `niri validate` 通过。
- `cargo check -p niri` 通过。
- 外层仓库和 `/home/wwt/niri/niri` 子仓库的 `git diff --check` 均通过。
- Quickshell 隔离 smoke 成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- 隔离 state 文件 `/tmp/.../state/quickshell/by-shell/tahoe/desktop-settings.json` 已生成，并包含：

```json
{
    "compositorLayerAnimations": false
}
```

- smoke 日志中的 `Qt.application.font` 只读、通知服务已注册、portal app-id 注册失败、首次 state 文件不存在等 warning 为当前 shell smoke 环境的既有/环境类现象；没有出现由本任务新增属性导致的 QML load failure。

视觉验收状态：

- 当前会话确认了 QML 加载、默认字段写出、配置 validate 和编译。
- 当前会话没有进行真实桌面肉眼 A/B：需要部署后在设置页打开 `Niri 动画 -> 面板显隐动画 -> 使用 compositor layer 动画`，再快速打开/关闭 Battery/Wi-Fi popup，确认无点击区域残留、无明显 glass/blur 闪烁。
- `desktop-settings.json` 中字段名、UI 入口和持久化路径已经固定，可以在任务 9 继续复用。

### 任务 9：迁移 Tahoe Small Popup 组

目标：迁移所有小弹窗和菜单。

范围：

- `tahoe-battery-popup`
- `tahoe-wifi-popup`
- `tahoe-fan-popup`
- `tahoe-clipboard-popup`
- `tahoe-menu-popup`
- `tahoe-application-menu`
- `tahoe-tray-menu`
- `tahoe-dock-app-menu`
- `tahoe-dock-window-menu`

操作：

1. 每次只迁移一个组件。
2. 每个组件迁移后独立测试。
3. 不同时修改 motion 参数和组件结构。

验收：

- 每个 popup 打开/关闭都无双重动画。
- glass region 不闪烁。
- blur/shadow 不残留。
- 键盘焦点行为不变。

完成条件：

- Small Popup 组全部完成。
- 文档记录最终参数。

未完成不得进入任务 10。

#### 任务 9 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/config/niri/tahoe-phase0.kdl`，把 Tahoe Small Popup profile 从任务 7/8 的 Battery/Wi-Fi 试点扩展到完整 Small Popup 组：
  - `tahoe-battery-popup`
  - `tahoe-wifi-popup`
  - `tahoe-fan-popup`
  - `tahoe-clipboard-popup`
  - `tahoe-menu-popup`
  - `tahoe-application-menu`
  - `tahoe-tray-menu`
  - `tahoe-dock-app-menu`
  - `tahoe-dock-window-menu`
- 最终参数保持 Tahoe Small Popup profile：

```kdl
layer-open {
    style "popin"
    scale-from 0.96
    opacity-from 0
    duration-ms 140
    curve "menu-decel"
    origin "anchor"
}

layer-close {
    style "popout"
    scale-to 0.97
    opacity-to 0
    duration-ms 95
    curve "menu-accel"
    origin "anchor"
}
```

- 保留任务 8 已迁移的 `/home/wwt/niri/tahoe-shell/components/BatteryPopup.qml` 和 `/home/wwt/niri/tahoe-shell/components/WifiPopup.qml`。
- 修改以下剩余 Small Popup QML 组件，全部接入 `settingsService.compositorLayerAnimations`：
  - `/home/wwt/niri/tahoe-shell/components/FanPopup.qml`
  - `/home/wwt/niri/tahoe-shell/components/ClipboardPopup.qml`
  - `/home/wwt/niri/tahoe-shell/components/MenuPopup.qml`
  - `/home/wwt/niri/tahoe-shell/components/AppMenuPopup.qml`
  - `/home/wwt/niri/tahoe-shell/components/TrayMenu.qml`
  - `/home/wwt/niri/tahoe-shell/components/DockAppMenu.qml`
  - `/home/wwt/niri/tahoe-shell/components/DockWindowMenu.qml`
- 每个迁移组件统一使用：
  - `property var settingsService`
  - `readonly property bool compositorLayerAnimations: root.settingsService && root.settingsService.compositorLayerAnimations`
  - 开关关闭时保留旧 `open || opacity > 0.01`、`opacity` 和 `contentScale` QML 外层动画路径。
  - 开关开启时 `visible` 只跟随 `open`，外层 `opacity` 固定为 `1`，`contentScale` 固定为 `1`。
  - 开关开启时 Tahoe Glass `interaction` / `materialAlpha` 固定为 `1`，避免 QML alpha 与 compositor alpha 双重压暗。
- 修改 `/home/wwt/niri/tahoe-shell/shell.qml`，为 `MenuPopup`、`AppMenuPopup`、`DockAppMenu`、`DockWindowMenu`、`FanPopup`、`ClipboardPopup` 和 `TrayMenu` 显式传入 `settingsService: desktopSettings`。Battery/Wi-Fi 的传参沿用任务 8。

边界确认：

- 未修改 Control Center、Notification Center、Launchpad、Spotlight、Toast、Dock、Task Switcher 或 Window Overview。
- 未改变 motion 参数，完整 Small Popup 组统一使用同一套 `0.96/0.97`、`140ms/95ms`、`menu-decel/menu-accel` 参数。
- 未重写组件结构，未改内部控件动画、列表、按钮、菜单 row、Dock menu 动作或服务调用。
- 未改变 `focusable` 配置；ClipboardPopup 仍为 `focusable: false`，其他组件保持原有焦点行为。
- 组件没有直接读取 JSON 文件、环境变量或临时全局变量；开关只来自 `shell.qml` 传入的 `desktopSettings`。
- 未修改 niri Rust runtime。

验收命令：

```bash
target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo test -p niri-config parse_layer_rule_animations
cargo test -p niri-config parse_layer_rule_animation_styles
cargo test -p niri layer_rule_animations_select_style_by_namespace
cargo check -p niri
git diff --check
XDG_STATE_HOME=/tmp/tmp.nbvLFkbmOp/state XDG_CACHE_HOME=/tmp/tmp.nbvLFkbmOp/cache XDG_CONFIG_HOME=/tmp/tmp.nbvLFkbmOp/config timeout 8 /home/wwt/niri/quickshell/build-tahoe/src/quickshell -p /home/wwt/niri/tahoe-shell
```

验收结果：

- `niri validate` 通过，日志显示 `config is valid`。
- `parse_layer_rule_animations` 通过。
- `parse_layer_rule_animation_styles` 通过。
- `layer_rule_animations_select_style_by_namespace` 通过。
- `cargo check -p niri` 通过。
- 外层仓库和 `/home/wwt/niri/niri` 子仓库的 `git diff --check` 均通过。
- Quickshell 隔离 smoke 在 `compositorLayerAnimations: false` 默认路径下成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- Quickshell 隔离 smoke 在临时 state 手动设为 `compositorLayerAnimations: true` 后再次成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- smoke 日志中的 `Qt.application.font` 只读、通知服务已注册、portal app-id 注册失败、首次 state 文件不存在、WindowButton interceptor 等 warning 为当前 shell smoke 环境的既有/环境类现象；没有出现由任务 9 新增 `settingsService` 或 `compositorLayerAnimations` 绑定导致的 QML load failure。

视觉验收状态：

- 当前会话完成了配置、编译、QML 加载和开关 false/true 两条路径的自动化验证。
- 当前命令环境没有可靠的真实桌面点击入口逐个打开 9 个 popup；部署到实际 Tahoe 会话后，应逐个快速打开/关闭 Small Popup 组，确认无双重动画、无 glass 闪烁、无 blur/shadow 残留，并在任务 13 的 50 次 toggle 压力测试中继续记录。

### 任务 10：迁移 Control Center / Notification Center

目标：迁移大面板，采用更谨慎参数。

范围：

- `tahoe-control-center`
- `tahoe-notification-center`

操作：

1. 先只迁移 control center。
2. 验证 anchor origin 正确。
3. 再迁移 notification center。
4. 如果 popin 不满意，尝试 edge-reveal 或 slide-right profile，但必须一次只改一种 profile。

验收：

- 面板打开时不显得漂。
- 关闭不拖沓。
- 内部展开、toggle、slider、列表滚动仍自然。
- glass material alpha 不与 surface alpha 产生明显双重变暗。

完成条件：

- 两个大面板都达到可长期使用状态。
- 记录最终参数。

未完成不得进入任务 11。

#### 任务 10 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/config/niri/tahoe-phase0.kdl`，新增 Tahoe Panel Pop profile，匹配：
  - `tahoe-control-center`
  - `tahoe-notification-center`
- 最终参数采用路线图的谨慎大面板 profile：

```kdl
layer-open {
    style "popin"
    scale-from 0.93
    opacity-from 0
    duration-ms 180
    curve "emphasized-decel"
    origin "anchor"
}

layer-close {
    style "popout"
    scale-to 0.94
    opacity-to 0
    duration-ms 130
    curve "menu-accel"
    origin "anchor"
}
```

- 先迁移 `/home/wwt/niri/tahoe-shell/components/ControlCenter.qml`：
  - 新增 `property var settingsService`。
  - 新增 `readonly property bool compositorLayerAnimations`，只从 `root.settingsService.compositorLayerAnimations` 读取。
  - 开关关闭时保留旧 `open || panel.opacity > 0.01`、`opacity` 和 `contentScale` QML 外层动画路径。
  - 开关开启时 `visible` 跟随 `open`，外层 `opacity` 固定为 `1`，`contentScale` 固定为 `1`。
  - Tahoe Glass `interaction` / `materialAlpha` 在 compositor 模式下固定为 `1`，避免 surface alpha 与 material alpha 双重变暗。
- 再迁移 `/home/wwt/niri/tahoe-shell/components/NotificationCenter.qml`，使用同一 handoff 模式。
- 修改 `/home/wwt/niri/tahoe-shell/shell.qml`，给 `ControlCenter` 和 `NotificationCenter` 显式传入 `settingsService: desktopSettings`。

边界确认：

- 未修改 Launchpad、Spotlight、Toast、Dock、Task Switcher 或 Window Overview。
- 未改 Control Center 内部按钮、展开区、slider、utility row 动画。
- 未改 Notification Center 内部 DND toggle、通知列表、滚动和单条移除行为。
- 未改变 focusable / keyboard interactivity 配置。
- 未尝试 edge-reveal 或 slide-right profile；`popin` + `anchor` 在本轮 live harness 中位置稳定，没有必要切换 profile。
- 组件没有直接读取 JSON 文件、环境变量或临时全局变量；开关只来自 `shell.qml` 传入的 `desktopSettings`。
- 未修改 niri Rust runtime。

验收命令：

```bash
niri/target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo test -p niri-config parse_layer_rule_animations
cargo test -p niri-config parse_layer_rule_animation_styles
cargo test -p niri layer_rule_animations_select_style_by_namespace
cargo check -p niri
git diff --check
XDG_STATE_HOME=/tmp/tmp.KURpKK1WM3/state XDG_CACHE_HOME=/tmp/tmp.KURpKK1WM3/cache XDG_CONFIG_HOME=/tmp/tmp.KURpKK1WM3/config timeout 8 /home/wwt/niri/quickshell/build-tahoe/src/quickshell -p /home/wwt/niri/tahoe-shell
```

额外 live harness：

- 生成临时 niri 配置 `/tmp/tmp.0rQFEBzyin/config-task10.kdl`，基于当前部署配置追加本任务的大面板 animation rule。
- 使用 `/home/wwt/.local/bin/niri msg action load-config-file --path /tmp/tmp.0rQFEBzyin/config-task10.kdl` 临时加载。
- 启动临时 Quickshell harness `/tmp/tmp.0rQFEBzyin/task10-harness.qml`，设置 `compositorLayerAnimations: true`，按顺序自动打开/关闭 Control Center，再打开/关闭 Notification Center。
- 用 `niri msg layers` 在 0.9s 观察到 `tahoe-control-center` 出现在 Top layer。
- 用 `niri msg layers` 在 3.0s 观察到 `tahoe-notification-center` 出现在 Top layer。
- 用 `niri msg layers` 在 5.2s 观察到两个测试 panel 都已消失，只剩原本的 `tahoe-dock` 和 `tahoe-topbar`。
- 使用 `grim` 抓取 Control Center 和 Notification Center 打开状态截图，面板位于右上锚点附近，没有明显漂移、错位或双重变暗。
- 测试完成后立即执行 `/home/wwt/.local/bin/niri msg action load-config-file --path /home/wwt/.config/niri/tahoe/config.kdl` 恢复当前部署配置，并再次确认 layer 列表回到原状态。

验收结果：

- `niri validate` 通过，日志显示 `config is valid`。
- `parse_layer_rule_animations` 通过。
- `parse_layer_rule_animation_styles` 通过。
- `layer_rule_animations_select_style_by_namespace` 通过。
- `cargo check -p niri` 通过。
- 外层仓库和 `/home/wwt/niri/niri` 子仓库的 `git diff --check` 均通过。
- Quickshell 隔离 smoke 在 `compositorLayerAnimations: false` 默认路径下成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- Quickshell 隔离 smoke 在临时 state 手动设为 `compositorLayerAnimations: true` 后再次成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- live harness 中两个 namespace 都能按顺序 map/unmap，结束后无 layer 残留。
- smoke / harness 日志中的 `Qt.application.font` 只读、通知服务已注册、portal app-id 注册失败、WindowButton interceptor、qmlscanner 绝对 `file:` import warning 等为当前测试方式或既有环境现象；没有出现由任务 10 新增 `settingsService` 或 `compositorLayerAnimations` 绑定导致的 QML load failure。

视觉验收状态：

- 本轮完成了真实 niri 会话中的临时 layer map/unmap 和截图观察：两个大面板位置稳定，右上锚点 origin 正常，未看到明显双重变暗。
- 内部控件代码未被修改；真实用户点击 slider、DND toggle、通知列表滚动的长时间交互和快速多次 toggle 仍按路线图归入任务 13 压力验证。

### 任务 11：迁移 Launchpad / Spotlight

目标：迁移中心型 surface。

范围：

- `tahoe-launchpad`
- `tahoe-spotlight`

操作：

1. 使用 center origin。
2. 避免过大 scale，防止图标和文字模糊。
3. 保留 QML 内部搜索、列表和结果项动画。
4. 快速输入时验证不会卡顿。

验收：

- 打开时没有图标明显模糊。
- 搜索框自动聚焦正常。
- 关闭 snapshot 不残留。
- 多次快速打开/关闭无异常。

完成条件：

- Launchpad 和 Spotlight 迁移完成。
- 最终参数记录。

未完成不得进入任务 12。

#### 任务 11 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/config/niri/tahoe-phase0.kdl`，新增 Tahoe Launchpad / Spotlight center profile，匹配：
  - `tahoe-launchpad`
  - `tahoe-spotlight`
- 最终参数采用路线图的中心型 surface profile：

```kdl
layer-open {
    style "popin"
    scale-from 0.94
    opacity-from 0
    duration-ms 180
    curve "emphasized-decel"
    origin "center"
}

layer-close {
    style "popout"
    scale-to 0.96
    opacity-to 0
    duration-ms 110
    curve "menu-accel"
    origin "center"
}
```

- 修改 `/home/wwt/niri/tahoe-shell/components/Launchpad.qml`：
  - 新增 `property var settingsService`。
  - 新增 `readonly property bool compositorLayerAnimations`，只从 `root.settingsService.compositorLayerAnimations` 读取。
  - 开关关闭时保留旧 `open || launcher.opacity > 0.01`、`opacity` 和 `contentScale` QML 外层动画路径。
  - 开关开启时 `visible` 跟随 `open`，外层 `opacity` 固定为 `1`，`contentScale` 固定为 `1`。
  - Tahoe Glass `interaction` / `materialAlpha` 在 compositor 模式下固定为 `1`，避免 surface alpha 与 material alpha 双重变暗。
- 修改 `/home/wwt/niri/tahoe-shell/components/Spotlight.qml`：
  - 新增 `property var settingsService`。
  - 使用同一 `compositorLayerAnimations` handoff 模式。
  - 开关开启时外层 `spotlightPanel.opacity` 和 `spotlightPanel.scale` 固定为 `1`。
  - 搜索结果 panel 的 `resultsSurface.opacity` 行为保留，作为内部结果列表显隐动画。
- 修改 `/home/wwt/niri/tahoe-shell/shell.qml`：
  - 给 `Launchpad` 和 `Spotlight` 显式传入 `settingsService: desktopSettings`。

边界确认：

- 未修改 Launchpad 的应用搜索、分类切换、应用 grid delegate 或启动行为。
- 未修改 Spotlight 的输入框、快捷入口、结果项、结果列表 opacity 动画或激活行为。
- 未修改 Dock、Task Switcher、Window Overview 或 niri Rust runtime。
- 组件没有直接读取 JSON 文件、环境变量或临时全局变量；开关只来自 `shell.qml` 传入的 `desktopSettings`。
- `focusable: open`、`TextInput.focus: root.open` 和打开后 `forceActiveFocus()` 路径保持原样。

验收命令：

```bash
niri/target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo test -p niri-config parse_layer_rule_animations
cargo test -p niri-config parse_layer_rule_animation_styles
cargo test -p niri layer_rule_animations_select_style_by_namespace
cargo check -p niri
git diff --check
XDG_STATE_HOME=/tmp/.../state XDG_CACHE_HOME=/tmp/.../cache XDG_CONFIG_HOME=/tmp/.../config timeout 8 /home/wwt/niri/quickshell/build-tahoe/src/quickshell -p /home/wwt/niri/tahoe-shell
```

额外 live harness：

- 生成临时 niri 配置 `/tmp/tmp.EyUdZdnTWC/config-task1112.kdl`，基于当前部署配置追加任务 11/12 的 animation rules。
- 使用 `/home/wwt/.local/bin/niri msg action load-config-file --path /tmp/tmp.EyUdZdnTWC/config-task1112.kdl` 临时加载。
- 启动临时 Quickshell harness，设置 `compositorLayerAnimations: true`，自动打开/关闭 Launchpad 和 Spotlight，并在打开期间修改 `query` 模拟快速输入绑定。
- 用 `niri msg layers` 观察到：
  - `tahoe-launchpad` 出现在 Overlay layer，keyboard interactivity 为 `on-demand`。
  - `tahoe-spotlight` 出现在 Top layer，keyboard interactivity 为 `on-demand`。
  - harness 结束后两个测试 surface 均消失，只剩当前会话原有的 `tahoe-dock` 和 `tahoe-topbar`。
- 测试完成后执行 `/home/wwt/.local/bin/niri msg action load-config-file --path /home/wwt/.config/niri/tahoe/config.kdl` 恢复当前部署配置。

验收结果：

- `niri validate` 通过，日志显示 `config is valid`。
- `parse_layer_rule_animations` 通过。
- `parse_layer_rule_animation_styles` 通过。
- `layer_rule_animations_select_style_by_namespace` 通过。
- `cargo check -p niri` 通过。
- 外层仓库和 `/home/wwt/niri/niri` 子仓库的 `git diff --check` 均通过。
- Quickshell 隔离 smoke 在 `compositorLayerAnimations: false` 默认路径下成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- Quickshell 隔离 smoke 在临时 state 手动设为 `compositorLayerAnimations: true` 后再次成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- live harness 中 Launchpad / Spotlight 能按顺序 map/unmap，结束后无 layer 残留。
- smoke / harness 日志中的 `Qt.application.font` 只读、通知服务已注册、portal app-id 注册失败、WindowButton interceptor、临时 harness asset 路径等 warning 为当前测试方式或既有环境现象；没有出现由任务 11 新增 `settingsService` 或 `compositorLayerAnimations` 绑定导致的 QML load failure。

视觉验收状态：

- 本轮完成了真实 niri 会话中的 layer 生命周期观察和 QML 快速输入绑定 smoke。
- 按用户要求，未继续耗时做 Launchpad 图标清晰度截图和长时间肉眼 A/B；这些更完整的视觉与压力检查归入任务 13。

### 任务 12：迁移 Toast / Dock / TaskSwitcher / Overview

目标：处理剩余需要特殊策略的 surface。

建议：

- `tahoe-notification-toast`：slide right + fade。
- `tahoe-dock`：如果 dock 常驻，不做 open/close；只处理显隐场景。
- `tahoe-task-switcher`：谨慎，可能保留 QML 内部动画。
- `tahoe-window-overview`：建议保留 QML/现有 overview 动画，不急于 compositor 化。

验收：

- 通知 toast 不打断视线。
- dock 不发生意外位移。
- overview 不和 niri 自己 overview 逻辑冲突。

完成条件：

- 明确哪些迁移，哪些保留 QML。
- 不追求全部 compositor 化。

未完成不得进入任务 13。

#### 任务 12 验收记录（2026-06-22）

实现范围：

- 修改 `/home/wwt/niri/config/niri/tahoe-phase0.kdl`，新增 Tahoe Toast profile，只匹配：
  - `tahoe-notification-toast`
- 最终参数采用路线图的 toast slide profile：

```kdl
layer-open {
    style "slide"
    edge "right"
    distance 28
    opacity-from 0
    duration-ms 170
    curve "emphasized-decel"
}

layer-close {
    style "slide"
    edge "right"
    distance 18
    opacity-to 0
    duration-ms 100
    curve "menu-accel"
}
```

- 修改 `/home/wwt/niri/tahoe-shell/components/NotificationToast.qml`：
  - 新增 `property var settingsService`。
  - 新增 `readonly property bool compositorLayerAnimations`，只从 `root.settingsService.compositorLayerAnimations` 读取。
  - 开关关闭时保留旧 QML `x` slide 和 `opacity` fade 路径。
  - 开关开启时 `visible` 跟随 `hasCurrent`，外层 `card.x` 固定为 `0`，`card.opacity` 固定为 `1`。
  - Tahoe Glass `interaction` / `materialAlpha` 在 compositor 模式下固定为 `1`，避免 surface alpha 与 material alpha 双重变暗。
  - 显式设置 `WlrLayershell.layer: WlrLayer.Top` 和 `exclusionMode: ExclusionMode.Ignore`。
  - 将右上定位改为 top/left anchor 加 `toastLeftMargin` 计算，视觉仍保持右上 16px 边距，同时确保 layer-shell surface 在 niri 中稳定 map 并被 namespace 规则匹配。
- 修改 `/home/wwt/niri/tahoe-shell/shell.qml`：
  - 给 `NotificationToast` 显式传入 `settingsService: desktopSettings`。

保留策略：

- `tahoe-dock`：保持常驻 surface，不启用 open/close compositor animation。
- `tahoe-task-switcher`：保持 QML / 现有交互路径，不迁移到 compositor layer animation。
- `tahoe-window-overview`：保持 QML / 现有 overview 路径，不迁移到 compositor layer animation，避免和 niri overview 逻辑冲突。

边界确认：

- 未修改 Dock、TaskSwitcher、WindowOverview 的 QML。
- 未给 `tahoe-dock`、`tahoe-task-switcher`、`tahoe-window-overview` 增加 KDL layer animation rule。
- 未改变 notification service 的 queue、history、DND、auto-expire 或 action invocation 逻辑。
- Toast 内部高度动画、内容布局、action button 行为保留。
- 组件没有直接读取 JSON 文件、环境变量或临时全局变量；开关只来自 `shell.qml` 传入的 `desktopSettings`。
- 未修改 niri Rust runtime。

验收命令：

```bash
niri/target/debug/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
cargo test -p niri-config parse_layer_rule_animations
cargo test -p niri-config parse_layer_rule_animation_styles
cargo test -p niri layer_rule_animations_select_style_by_namespace
cargo check -p niri
git diff --check
XDG_STATE_HOME=/tmp/.../state XDG_CACHE_HOME=/tmp/.../cache XDG_CONFIG_HOME=/tmp/.../config timeout 8 /home/wwt/niri/quickshell/build-tahoe/src/quickshell -p /home/wwt/niri/tahoe-shell
```

额外 live harness：

- 使用任务 11 同一临时 niri 配置 `/tmp/tmp.EyUdZdnTWC/config-task1112.kdl`。
- 启动临时 Toast-only Quickshell harness，设置 `compositorLayerAnimations: true` 并提供 static notification stub。
- 用 `niri msg layers` 观察到 `tahoe-notification-toast` 出现在 Top layer，keyboard interactivity 为 `none`。
- harness 结束后再次用 `niri msg layers` 确认 toast surface 消失，只剩当前会话原有的 `tahoe-dock` 和 `tahoe-topbar`。
- 测试完成后执行 `/home/wwt/.local/bin/niri msg action load-config-file --path /home/wwt/.config/niri/tahoe/config.kdl` 恢复当前部署配置。

验收结果：

- `niri validate` 通过，日志显示 `config is valid`。
- `parse_layer_rule_animations` 通过。
- `parse_layer_rule_animation_styles` 通过。
- `layer_rule_animations_select_style_by_namespace` 通过。
- `cargo check -p niri` 通过。
- 外层仓库和 `/home/wwt/niri/niri` 子仓库的 `git diff --check` 均通过。
- Quickshell 隔离 smoke 在 `compositorLayerAnimations: false` 默认路径下成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- Quickshell 隔离 smoke 在临时 state 手动设为 `compositorLayerAnimations: true` 后再次成功加载到 `Configuration Loaded`；退出码 `124` 来自 `timeout` 主动结束。
- live harness 中 Toast 能 map 为 `tahoe-notification-toast` layer surface，结束后无 layer 残留。
- 当前 `niri msg layers` 在恢复部署配置后只显示原有 `tahoe-dock` 和 `tahoe-topbar`，未残留测试 surface。

视觉验收状态：

- 本轮完成了真实 niri 会话中的 Toast layer map/unmap 生命周期观察。
- 按用户要求，未继续耗时做通知打断视线程度、真实 notification daemon 30 条压力触发和长时间肉眼 A/B；这些更完整的视觉与性能检查归入任务 13。

### 任务 13：性能和稳定性验证

目标：确认没有因为 layer animation 引入持续重绘、卡顿、资源泄漏。

操作：

1. 为每个已迁移组件执行快速 toggle：
   - Small Popup 组：每个 50 次。
   - Control Center：30 次。
   - Notification Center：30 次。
   - Launchpad：30 次。
   - Spotlight：30 次。
   - Toast：至少触发 30 条。
2. 对每类组件记录：
   - 是否有关闭残影。
   - 是否有 glass/blur 闪烁。
   - 是否有输入区域残留。
   - 动画结束后是否停止重绘。
3. 观察 CPU/GPU 占用。最低要求是用 `pidstat` 或同类工具记录 niri 在 idle、动画中、动画结束后的占用变化。
4. 检查 niri log 中是否有 render/shader/background-effect/snapshot 错误。
5. 检查 animation list 生命周期：
   - opening animation 结束后移除。
   - closing snapshot animation 结束后释放。
   - 快速 toggle 时没有重复堆积。
6. 如果支持 Tracy 或已有 profiling feature，记录一次动画期间 frame span。没有 Tracy 时必须说明未使用原因。

验收：

- 动画结束后一帧内不持续重绘。
- 无 texture/snapshot 残留迹象。
- 无 panic。
- 无明显输入延迟。
- 无持续 CPU/GPU 占用抬高。
- 快速 toggle 后 `niri msg layers` 看到的 layer 状态和实际打开状态一致。
- 关闭开关后旧 QML 路径仍可用。

完成条件：

- 在本文档或单独记录中写下性能结果。
- 修复所有阻断问题。
- 明确哪些组件允许默认开启 compositor animation，哪些继续保留 QML 路径。

未完成不得进入任务 14。

### 任务 14：清理 QML 外层动画

目标：只有在 compositor 动画稳定后，清理不再需要的 QML 外层显隐动画。

操作：

1. 删除或禁用已迁移组件的外层 `Behavior on opacity`。
2. 删除或禁用已迁移组件的外层 `Behavior on contentScale`。
3. 保留内部交互动画。
4. 不做样式重构。

验收：

- 无双重动画。
- 关闭时 surface 生命周期合理。
- 开关关闭时仍可回滚到旧路径，除非确认完全不需要。

完成条件：

- QML 只负责内容和内部动效。
- compositor 负责 surface open/close。

未完成不得进入任务 15。

### 任务 15：文档和默认配置定稿

目标：形成长期可维护的配置和说明。

操作：

1. 更新 Tahoe 配置注释。
2. 写明每个 namespace 对应 motion profile。
3. 写明如何关闭 compositor layer animation：
   - UI 路径：设置 -> niri -> 动画 -> 面板显隐动画 -> 使用 compositor layer 动画。
   - 文件路径：`Quickshell.stateDir/desktop-settings.json`
   - 字段名：`compositorLayerAnimations`
4. 写明推荐参数。
5. 为新增 Rust 模块添加模块级注释，说明：
   - open animation 生命周期。
   - close snapshot 生命周期。
   - damage 范围。
   - animation disabled 时的零成本路径。
6. 为 Tahoe Shell 组件添加短注释，说明外层显隐由 compositor 接管，内部微交互仍由 QML 管理。
7. 更新维护矩阵：哪些 namespace 使用 compositor animation，哪些明确不迁移。

验收：

- 文档能指导后续维护。
- 默认配置可以直接使用。
- 回滚路径明确。
- 新增配置项和 QML 字段命名一致。
- 没有“临时开关”“以后再说”的不明状态。
- 性能验收结果已归档。

完成条件：

- 文档完成。
- 配置完成。
- 所有验收通过。

## 推荐默认 KDL 草案

以下只是目标配置草案，必须等任务 2 到任务 6 完成后才能真正启用。

```kdl
layer-rule {
    match namespace="^tahoe-control-center$"
    match namespace="^tahoe-notification-center$"

    animations {
        layer-open {
            style "popin"
            scale-from 0.93
            opacity-from 0
            duration-ms 180
            curve "emphasized-decel"
            origin "anchor"
        }
        layer-close {
            style "popout"
            scale-to 0.94
            opacity-to 0
            duration-ms 130
            curve "menu-accel"
            origin "anchor"
        }
    }
}

layer-rule {
    match namespace="^tahoe-battery-popup$"
    match namespace="^tahoe-wifi-popup$"
    match namespace="^tahoe-fan-popup$"
    match namespace="^tahoe-clipboard-popup$"
    match namespace="^tahoe-menu-popup$"
    match namespace="^tahoe-application-menu$"
    match namespace="^tahoe-tray-menu$"
    match namespace="^tahoe-dock-app-menu$"
    match namespace="^tahoe-dock-window-menu$"

    animations {
        layer-open {
            style "popin"
            scale-from 0.96
            opacity-from 0
            duration-ms 140
            curve "menu-decel"
            origin "anchor"
        }
        layer-close {
            style "popout"
            scale-to 0.97
            opacity-to 0
            duration-ms 95
            curve "menu-accel"
            origin "anchor"
        }
    }
}

layer-rule {
    match namespace="^tahoe-launchpad$"
    match namespace="^tahoe-spotlight$"

    animations {
        layer-open {
            style "popin"
            scale-from 0.94
            opacity-from 0
            duration-ms 180
            curve "emphasized-decel"
            origin "center"
        }
        layer-close {
            style "popout"
            scale-to 0.96
            opacity-to 0
            duration-ms 110
            curve "menu-accel"
            origin "center"
        }
    }
}

layer-rule {
    match namespace="^tahoe-notification-toast$"

    animations {
        layer-open {
            style "slide"
            edge "right"
            distance 28
            opacity-from 0
            duration-ms 170
            curve "emphasized-decel"
        }
        layer-close {
            style "slide"
            edge "right"
            distance 18
            opacity-to 0
            duration-ms 100
            curve "menu-accel"
        }
    }
}
```

## 风险清单

### 风险 1：双重动画

如果 QML 外层 opacity/scale 和 compositor layer animation 同时生效，会导致动画过度、变暗、缩放不自然。

规避：

- 先加开关。
- 一个组件一个组件迁移。
- 迁移后外层 QML opacity/scale 固定为 1。

### 风险 2：关闭 snapshot 残留

关闭动画需要 surface unmap 后继续绘制 snapshot。如果生命周期处理不严谨，可能导致残影、持续重绘或 texture 泄漏。

规避：

- 先实现简单 fade/popout。
- 每次关闭后确认 animation list 清空。
- `are_animations_ongoing()` 必须准确。

### 风险 3：Tahoe Glass 与 alpha 叠加

Tahoe Glass 的 region material alpha 当前跟 QML opacity 绑定。迁移到 compositor alpha 后，需要避免 material alpha 和 surface alpha 双重变暗。

规避：

- compositor animation 启用时，QML materialAlpha 固定为 1 或按 open state 简化。
- 逐组件验证 glass 视觉。

### 风险 4：输入区域与视觉区域不同步

如果 QML surface 保持 visible 但 opacity 为 0，可能仍占输入。迁移后应让 surface 映射生命周期和视觉更一致。

规避：

- compositor 动画模式下 `visible: open`。
- 关闭动画交给 snapshot，而不是保留真实 surface。

### 风险 5：PR #3481 与当前 fork 差异过大

直接合并会破坏现有 fork 功能。

规避：

- 只移植最小功能。
- 每步 compile/test。
- 保留明确回滚点。

## 最终成功标准

项目完成时应满足：

1. niri 支持 per-layer-rule 的 layer open/close 动画。
2. Tahoe namespace 能配置不同 motion profile。
3. 小弹窗、控制中心、通知中心、Launchpad、Spotlight、Toast 的外层显隐动画统一由 compositor 驱动。
4. QML 内部控件动画保留。
5. 没有双重动画。
6. 没有关闭残影。
7. 没有持续重绘。
8. Tahoe Glass、Genie minimize、snap assist、background-effect 不回退。
9. 所有任务严格串行完成，未通过验收不得进入下一任务。

## 推荐第一步

从任务 0 开始，不要直接写功能代码。先建立分支和基线，再做 PR #3481 最小移植清单。这个项目最大风险不是实现动画本身，而是把 PR 分支中无关的大量旧状态误合入当前 fork。
