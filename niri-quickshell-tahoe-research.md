# niri + Quickshell Tahoe 风格改造研究文档

日期：2026-06-14

## 研究范围

本次研究目标是判断：

- niri 能不能改造成 macOS 26 Tahoe / Liquid Glass 风格。
- niri 能不能变成更接近 Windows/macOS 的浮动窗口体验，而不是以平铺为主。
- Quickshell 应该 fork 核心源码，还是只写 shell 配置/主题。
- 本地 `macOS-26-Tahoe-for-the-Web-main` 能复用到什么程度。

本地目录：

- `niri/`：niri 源码，本地 sparse checkout，排除了 Windows 不兼容的 `docs/wiki/**`。
- `quickshell/`：Quickshell 源码。
- `macOS-26-Tahoe-for-the-Web-main/`：Web 版 macOS 26 Tahoe 桌面模拟器。

## 总结结论

建议架构：

```text
niri fork:
- compositor / layout / input / render / IPC
- 最小化、恢复、snap assist、更强 floating desktop 行为
- 更高级 Liquid Glass shader

Quickshell shell:
- 顶栏
- Dock
- 控制中心
- Launchpad
- 通知中心
- 窗口列表和工作区 UI
```

不建议从零写 Wayland shell，也不建议 fork GNOME/KDE。Quickshell 是更合适的外壳框架。

Quickshell 核心暂时不用 fork。先新建一个独立的 Tahoe shell 配置/主题项目即可。只有需要原生 niri IPC 模块、性能不够、或现有 QML/Process 方案太别扭时，再改 Quickshell 核心。

niri 才是必须 fork 的部分，因为窗口最小化、传统堆叠桌面、snap preview、Liquid Glass compositor shader 都属于 compositor 能力。

## 现有 niri 能做到的部分

niri 不是纯平铺，已经支持浮动窗口：

- `open-floating true` 可以让窗口打开时进入浮动布局。
- `match is-floating=true` 可以给浮动窗口单独套规则。
- 浮动窗口会显示在平铺窗口上方。
- 每个 workspace/monitor 有自己的 floating layout。
- 弹窗、固定尺寸窗口会自动浮动。
- 支持 `toggle-window-floating`、`move-window-to-floating`、`move-window-to-tiling`、`move-floating-window` 等 action。

现有视觉能力：

- 圆角：`geometry-corner-radius`
- 裁剪圆角：`clip-to-geometry`
- 阴影：`shadow`
- 边框/焦点环：`border` / `focus-ring`
- 背景效果：`background-effect`
- blur / xray / saturation / noise
- 自定义动画和 shader 基础设施

配置原型：

```kdl
window-rule {
    open-floating true
    geometry-corner-radius 14
    clip-to-geometry true
}

window-rule {
    match is-floating=true

    shadow {
        on
        softness 45
        spread 4
        offset x=0 y=10
        color "#00000055"
    }

    background-effect {
        blur true
        xray false
        noise 0.025
        saturation 1.35
    }
}
```

这可以做出一个“默认全浮动 + 圆角 + 阴影 + 玻璃模糊”的原型，但它仍然不是完整 Windows/macOS 式堆叠窗口管理器。

## 现有 niri 做不到或不完整的部分

### 真正的最小化/恢复

niri 当前没有完整 minimize 模型。

Quickshell 的 foreign toplevel 模块有 `minimized` 属性和请求能力，但 niri 目前对 foreign-toplevel 的 minimize 请求是空处理：

- `niri/src/protocols/foreign_toplevel.rs`
  - `SetMinimized => ()`
  - `UnsetMinimized => ()`

因此 Dock 点击黄色按钮、Dock 点击恢复窗口，需要改 niri。

### 传统桌面级堆叠模型

niri 当前是“scrollable tiling + floating layer”。即使所有窗口都 `open-floating true`，底层模型仍不是完整的经典 stacking WM。

要更像 Windows/macOS，需要增强：

- 全局/工作区内 z-order
- raise/lower
- 最小化隐藏
- 从 Dock 恢复
- 窗口切换和任务栏状态
- snap/maximize 语义

### Snap preview

niri 有移动/resize 框架，但没有 Windows 式拖到边缘显示半屏/全屏预览的完整体验。

需要在拖拽输入和 layout finalize 阶段新增逻辑。

### 完整 Liquid Glass

现有 blur/noise/saturation 足够做“像玻璃”的基础，但 macOS 26 那种折射、高光、边缘光、动态 tint，需要改 compositor shader。

## 本地 macOS Web 项目结论

目录：`macOS-26-Tahoe-for-the-Web-main/`

它是一个 Web 桌面模拟器，包含：

- `index.html`
- `Css/style.css`
- `javascript/script.js`
- `apps/`
- `background/`
- `icon/`
- `cursor/`
- `audio/`

可复用内容：

- 图标资源：`icon/dock/`、`icon/Launchpad/`
- 壁纸资源：`background/`
- 视觉参数：圆角、透明度、blur 值、Dock 外观、Control Center 外观
- 行为参考：窗口 z-index、拖拽、resize、最大化、左右吸附、Dock magnification

不可直接复用内容：

- DOM/CSS/JS 不能直接塞进 niri。
- niri 是 Rust/Wayland compositor，不运行浏览器 DOM。
- Quickshell 是 Qt/QML/C++，也不能直接运行这套 HTML/CSS/JS。

最佳用途：

```text
Web 项目 CSS/JS/资源
-> 抽取视觉参数和交互行为
-> 用 QML 重写 shell UI
-> 用 niri Rust 实现 compositor 级窗口行为
```

## 动画可行性

结论：可以做到“很像 macOS”，但要分成 shell 层动画和 compositor 层动画。

### Shell 层动画

这些由 Quickshell/QML 实现，不需要改 niri：

- Dock 放大跟随鼠标。
- Dock 图标弹跳。
- Dock hover label。
- 控制中心弹出/收起。
- 菜单栏弹窗。
- Launchpad 缩放、淡入、背景模糊。
- 通知滑入/滑出。
- 窗口列表 UI 的 hover/selection 动画。

Quickshell/QML 可用能力：

- `Behavior`
- `NumberAnimation`
- `PropertyAnimation`
- `SpringAnimation`
- `SequentialAnimation`
- `ParallelAnimation`
- `ShaderEffect`
- Qt easing curves

本地 Web 项目里已有可参考的动画：

- Dock magnification：`javascript/script.js`
- Launchpad open/close：`Css/style.css` 和 `javascript/script.js`
- Control Center transition：`Css/style.css`
- Snap preview fade/resize：`Css/style.css` 和 `javascript/script.js`

这些逻辑应翻译成 QML，不要直接复用 DOM/CSS/JS。

### niri compositor 层动画

niri 已有动画系统，能配置或扩展：

- `workspace-switch`
- `window-open`
- `window-close`
- `window-movement`
- `window-resize`
- `overview-open-close`
- spring
- easing
- cubic-bezier
- open/close/resize custom shader

相关源码：

- `niri-config/src/animations.rs`
- `src/animation/mod.rs`
- `src/animation/spring.rs`
- `src/layout/opening_window.rs`
- `src/layout/closing_window.rs`
- `src/render_helpers/shader_element.rs`
- `src/render_helpers/shaders/`

可实现的 macOS 风格效果：

- 窗口打开：轻微 scale + opacity。
- 窗口关闭：scale down + fade。
- 窗口移动：spring 跟随。
- resize：平滑尺寸变化。
- overview/Mission Control：缩放展开。
- snap：预览框淡入，窗口吸附时 spring 过渡。

### 难点：Genie minimize

macOS 最小化到 Dock 的 Genie effect 不是简单配置能完成，需要 niri fork 深改。

大致流程：

```text
Quickshell Dock 提供目标 icon rect
        ↓
niri IPC 收到 minimize-window --target-rect
        ↓
niri 截取窗口 snapshot
        ↓
compositor 用 shader/mesh 把窗口扭曲收缩到 Dock 图标
        ↓
窗口进入 is_minimized=true
```

需要新增/修改：

- niri IPC action 携带 Dock icon target rectangle。
- layout 最小化状态。
- snapshot 动画路径。
- 变形 shader 或 mesh deformation。
- restore 动画从 Dock icon 反向展开。

建议路线：

```text
先做 80%:
- Quickshell shell 动画
- niri spring/cubic-bezier 窗口动画
- 普通 fade/scale minimize

再做 100%:
- snapshot deformation
- Genie effect
- Dock target rect IPC
```

## niri 源码地图

### 配置

- `niri-config/src/window_rule.rs`
  - `open_floating`
  - `default_floating_position`
  - `geometry_corner_radius`
  - `clip_to_geometry`
  - `background_effect`
  - `is_floating`

- `niri-config/src/layout.rs`
  - layout、border、shadow 等配置。

- `niri-config/src/lib.rs`
  - 顶层配置和 parse 测试。

- `niri-config/src/binds.rs`
  - keybind action enum。
  - 新增 action 时这里和 `niri-ipc/src/lib.rs` 都要同步。

### IPC

- `niri-ipc/src/lib.rs`
  - IPC `Action`
  - `Window`
  - `WindowLayout`
  - `Event`
  - 当前 `Window` 有 `is_floating`，没有 `is_minimized`。

- `src/ipc/server.rs`
  - IPC 请求处理。
  - `make_ipc_window()` 生成窗口状态。
  - `WindowsChanged`、`WindowLayoutsChanged` 事件发送。

### 浮动布局

- `src/layout/floating.rs`
  - 核心 floating stack。
  - `add_tile`
  - `raise_window`
  - `move_window`
  - `center_window`
  - `interactive_resize_begin/update/end`
  - `floating_pos`
  - `floating_window_size`

- `src/layout/workspace.rs`
  - 每个 workspace 里有 `scrolling` 和 `floating` 两套布局。
  - `floating_is_active`
  - `toggle_window_floating`
  - `set_window_floating`
  - `move_floating_window`
  - `render_floating`
  - `is_floating_visible`

- `src/layout/mod.rs`
  - 顶层 Layout。
  - interactive move。
  - 跨 monitor/workspace 移动。
  - `toggle_window_floating`
  - `interactive_move_begin/update/end`

- `src/layout/monitor.rs`
  - monitor/workspace 管理。
  - render 顺序。
  - layer/workspace hit testing。

### 输入拖拽/resize

- `src/input/move_grab.rs`
  - 鼠标拖动窗口。
  - 左/右键拖动期间切换 floating。
  - snap assist 应优先从这里接入。

- `src/input/resize_grab.rs`
  - 鼠标 resize。

- `src/input/mod.rs`
  - action 分发。
  - 新增 minimize/restore action 要在这里处理。

### Wayland 协议

- `src/protocols/foreign_toplevel.rs`
  - 对外暴露窗口列表。
  - activate/close/maximize/fullscreen 请求。
  - minimize 请求当前空处理。

- `src/protocols/ext_workspace.rs`
  - 对外暴露 workspace。
  - Quickshell 的 WindowManager 模块能对接。

- `src/handlers/background_effect.rs`
  - `ext-background-effect` 协议处理。
  - Quickshell 的 BackgroundEffect 可以利用它。

### 渲染

- `src/render_helpers/background_effect.rs`
  - per-surface background effect。
  - blur/xray/noise/saturation。

- `src/render_helpers/blur.rs`
  - dual-kawase blur。

- `src/render_helpers/xray.rs`
  - xray background/backdrop。

- `src/render_helpers/framebuffer_effect.rs`
  - 非 xray background effect。

- `src/render_helpers/shaders/postprocess.frag`
  - noise/saturation 后处理。
  - Liquid Glass tint/highlight/refraction 可从这里或新 shader 开始。

## Quickshell 源码地图

Quickshell 是 C++/Qt/QML shell 工具包，不是现成 macOS 主题。

### Layer shell 面板

- `quickshell/src/wayland/wlr_layershell/wlr_layershell.hpp`
  - `PanelWindow`
  - `WlrLayer`
  - `WlrKeyboardFocus`
  - anchor/margin/exclusive zone

用途：

- 顶栏
- Dock
- 控制中心弹层
- 背景层

### 窗口列表

- `quickshell/src/wayland/toplevel/qml.hpp`
  - `ToplevelManager`
  - `Toplevel`
  - `appId`
  - `title`
  - `activated`
  - `maximized`
  - `minimized`
  - `fullscreen`
  - `activate()`
  - `close()`

前提：

- compositor 需要实现 wlr foreign toplevel management。
- niri 已有实现，但 minimize 需要补。

### Workspace

- `quickshell/src/windowmanager/`
- `quickshell/src/wayland/windowmanager/`

Quickshell 的 WindowManager 当前支持 `ext-workspace-v1`，niri 也实现了该协议。

用途：

- 工作区显示。
- 工作区切换。
- 每个显示器上的 active workspace。

### 背景效果

- `quickshell/src/wayland/background_effect/qml.hpp`

用途：

- 给 Dock、控制中心、顶栏设置 blur region。
- 通过 niri 的 `ext-background-effect` 获得 compositor 级背景模糊。

### 进程和 socket

- `quickshell/src/io/process.hpp`
- `quickshell/src/io/socket.hpp`

用途：

- 初期可以用 `Process` 跑 `niri msg --json`。
- 后期可以用 `Socket` 或新增 C++ 模块直接接 niri IPC socket。

## 改造优先级

### Phase 0: 配置原型

不改源码。

- niri 配置默认浮动。
- 圆角、阴影、背景效果。
- Quickshell 创建基础顶栏/Dock/控制中心。

目标：先看到方向是否对。

### Phase 1: Quickshell Tahoe shell

不改 Quickshell 核心源码。

建议新建单独目录：

```text
tahoe-shell/
- shell.qml
- components/
- assets/
- services/
```

从 Web 项目拷贝/引用图标和壁纸，QML 重写 UI。

### Phase 2: niri fork 最小改造

优先做：

- `is_minimized`
- `minimize-window`
- `restore-window`
- foreign-toplevel minimize/unminimize
- Dock 点击恢复
- snap assist

### Phase 3: 动画拟真

先不做 Genie，优先做：

- Quickshell Dock magnification。
- Quickshell 控制中心 spring open/close。
- Quickshell Launchpad scale/fade/blur。
- niri window open/close scale/fade。
- niri snap preview fade。
- niri snap apply spring movement。

后续再做：

- minimize snapshot。
- Dock target rect IPC。
- Genie-style shader/mesh deformation。
- restore reverse animation。

### Phase 4: Liquid Glass

增强：

- background-effect 参数。
- glass tint。
- highlight。
- edge light。
- refraction/displacement。

### Phase 5: 更深桌面化

可选：

- 服务端窗口装饰。
- 红黄绿按钮。
- 更完整 app menu。
- 更 macOS 的窗口动画。

这一步工程量大，不建议一开始做。

## 风险

- niri 是活跃项目，fork 后长期维护有成本。
- Quickshell 使用 Qt private API，构建环境对 Qt 版本敏感。
- 完整 Liquid Glass 可能有 GPU 性能问题。
- 最小化模型会影响 IPC、foreign-toplevel、layout、render、input、测试。
- Wayland 下全局菜单栏不是 compositor 单独能解决的，需要应用协议/DBus/工具链配合。
