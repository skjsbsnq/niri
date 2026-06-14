# niri + Quickshell Tahoe 改造交接文档

日期：2026-06-14

## 当前本地状态

工作目录：

```text
C:\Users\19180\Documents\999\新建文件夹
```

已有目录：

```text
macOS-26-Tahoe-for-the-Web-main/
niri/
quickshell/
```

仓库状态：

```text
niri       main   6f1a2c5 Use `RUSTFLAGS` instead of `CARGO_BUILD_RUSTFLAGS` in dev shell
quickshell master d99d87d crash: remove logs from crash template
```

两个仓库当前工作区 clean。

注意：niri 在 Windows 上不能普通 checkout 全仓库，因为 `docs/wiki/Configuration:-*.md` 含冒号，Windows 不允许该文件名。当前本地 `niri/` 使用 sparse checkout，只展开源码相关目录。

当前 niri sparse 目录包含：

```text
src/
niri-config/
niri-ipc/
niri-visual-tests/
resources/
```

## 后续建议分支

开始正式修改前建议先建分支：

```powershell
cd .\niri
git switch -c tahoe-desktop

cd ..\quickshell
git switch -c tahoe-shell-support
```

如果只是写 Quickshell shell 配置，不需要改 `quickshell/` 核心仓库；建议在工作目录新建：

```text
tahoe-shell/
```

## 设计分工

### niri 负责

- 窗口真实状态。
- 浮动/平铺/堆叠。
- 最小化/恢复。
- snap assist。
- resize/move 行为。
- compositor 级 blur/glass。
- 对 shell 暴露 IPC 和 Wayland protocol 状态。

### Quickshell 负责

- 顶栏。
- Dock。
- 控制中心。
- Launchpad。
- 通知中心。
- 工作区 UI。
- 窗口列表 UI。
- 壁纸/锁屏外观可以后续接入。

### Web 项目负责

仅作为参考和素材源：

- 图标。
- 壁纸。
- CSS blur/opacity/radius 参数。
- JS 交互逻辑参考。

不要试图把 HTML/CSS/JS 直接塞进 niri 或 Quickshell 核心。

## 第一阶段任务：Quickshell shell 原型

目标：不改 niri，不改 Quickshell 核心，先做视觉原型。

建议新建：

```text
tahoe-shell/
- shell.qml
- components/
  - TopBar.qml
  - Dock.qml
  - ControlCenter.qml
  - Launchpad.qml
  - WindowButton.qml
- services/
  - Niri.qml
  - Apps.qml
- assets/
  - icons/
  - backgrounds/
```

可从 `macOS-26-Tahoe-for-the-Web-main/` 复制/引用：

```text
background/
icon/dock/
icon/Launchpad/
icon/symbols/
```

Quickshell 可用能力：

- `PanelWindow` 做顶栏/Dock。
- `WlrLayershell.layer` 控制 top/overlay/background。
- `BackgroundEffect.blurRegion` 请求 niri 背景模糊。
- `ToplevelManager.toplevels` 获取窗口列表。
- `WindowManager.windowsets` 获取 workspace。
- `Process` 临时执行 `niri msg --json`。

验收标准：

- 有顶部菜单栏。
- 有底部 Dock。
- Dock 能显示固定 app 图标。
- 能显示当前窗口列表。
- 点击窗口项能 activate。
- 控制中心能打开/关闭。
- 面板能有 compositor blur。

## 第二阶段任务：niri 最小化/恢复

目标：让 Dock 能真正最小化和恢复窗口。

需要新增概念：

```text
is_minimized: bool
```

建议改动入口：

- `niri-ipc/src/lib.rs`
  - `Window` 增加 `is_minimized`。
  - `Action` 增加 `MinimizeWindow { id: Option<u64> }`。
  - `Action` 增加 `RestoreWindow { id: u64 }` 或 `ToggleWindowMinimized { id: Option<u64> }`。

- `niri-config/src/binds.rs`
  - 增加对应 config action。
  - 增加 `From<niri_ipc::Action>` 映射。

- `src/input/mod.rs`
  - 在 `do_action()` 里处理新增 action。

- `src/layout/floating.rs`
  - 浮动窗口最小化后从 render/input/hit-test 排除。
  - 需要保留窗口原位置和大小。

- `src/layout/workspace.rs`
  - 提供 minimize/restore 状态切换。
  - 注意 active/focus 窗口被最小化后要切换焦点。

- `src/layout/mod.rs`
  - 顶层 layout API 包装。
  - 根据 window id 找到所在 workspace。

- `src/ipc/server.rs`
  - `make_ipc_window()` 填充 `is_minimized`。
  - `WindowsChanged` 触发状态变化。

- `src/protocols/foreign_toplevel.rs`
  - `SetMinimized` 调用 niri minimize。
  - `UnsetMinimized` 调用 niri restore。
  - 对外 state 里发送 minimized。

验收标准：

- `niri msg windows` 能看到 `is_minimized`。
- `niri msg action minimize-window --id X` 后窗口不可见、不可点中。
- Dock 仍能看到该窗口。
- `restore-window --id X` 后窗口回到原 workspace 和原位置。
- foreign-toplevel 的 `Toplevel.minimized = true/false` 在 Quickshell 里可用。

## 第三阶段任务：snap assist

目标：拖动窗口到屏幕边缘时出现预览，松手后半屏/全屏。

建议新增配置：

```kdl
layout {
    snap-assist {
        on
        threshold 24
        preview-color "#7fb7ff44"
        preview-border-color "#ffffff88"
    }
}
```

实现入口：

- `src/input/move_grab.rs`
  - 监听拖动位置。
  - 判断是否靠近 left/right/top。
  - 更新 layout 中 snap preview 状态。

- `src/layout/mod.rs`
  - `InteractiveMoveData` 增加 snap target。
  - `interactive_move_update()` 计算 target。
  - `interactive_move_end()` 应用 target。

- `src/layout/floating.rs`
  - 对 floating window 设置目标位置/大小。
  - 保留 restore size。

- 渲染 preview：
  - 可以新增 render element。
  - 或参考已有 `insert_hint_element` 思路。

验收标准：

- 拖到左边显示左半屏 preview。
- 拖到右边显示右半屏 preview。
- 拖到顶部显示最大化 preview。
- 松手后窗口尺寸和位置正确。
- 从 snap 状态再次拖动能恢复之前大小。

## 第四阶段任务：动画拟真

目标：让 shell UI 和窗口行为接近 macOS 的动效节奏。

### Quickshell 动画

这些先在 `tahoe-shell/` 的 QML 里做，不改 Quickshell 核心。

建议实现：

- Dock magnification：鼠标靠近图标时 scale + y offset。
- Dock icon bounce：启动 app 或收到 attention 时弹跳。
- Control Center：scale + opacity + blur 淡入。
- Launchpad：背景 blur，app grid scale/fade。
- Menu popup：从顶部轻微位移 + opacity。
- Notification：从右上角滑入 + spring settle。
- Dock hover label：opacity + y offset。

QML 可用：

```text
Behavior
NumberAnimation
PropertyAnimation
SpringAnimation
SequentialAnimation
ParallelAnimation
ShaderEffect
Easing
```

参考来源：

- `macOS-26-Tahoe-for-the-Web-main/javascript/script.js`
  - Dock magnification。
  - Launchpad open/close。
  - Snap preview 行为。

- `macOS-26-Tahoe-for-the-Web-main/Css/style.css`
  - transition。
  - transform scale。
  - cubic-bezier。
  - snap preview opacity/width。

### niri 窗口动画

niri 已有动画系统，先用配置调节：

- `workspace-switch`
- `window-open`
- `window-close`
- `window-movement`
- `window-resize`
- `overview-open-close`

相关源码：

- `niri-config/src/animations.rs`
- `src/animation/mod.rs`
- `src/animation/spring.rs`
- `src/layout/opening_window.rs`
- `src/layout/closing_window.rs`
- `src/render_helpers/shader_element.rs`
- `src/render_helpers/shaders/`

建议第一版：

- 窗口打开：scale 0.96 -> 1.0 + opacity 0 -> 1。
- 窗口关闭：scale 1.0 -> 0.96 + opacity 1 -> 0。
- 移动/resize：spring 参数调到轻微回弹，不要过度弹。
- snap apply：位置和尺寸用 spring 过渡。
- snap preview：半透明矩形 fade in/out。

### Genie minimize

macOS 最小化到 Dock 的 Genie effect 需要 niri 深改，不能只靠配置。

需要的数据流：

```text
Dock icon rect
  -> Quickshell
  -> niri IPC minimize-window --target-rect
  -> niri window snapshot
  -> shader/mesh deformation
  -> is_minimized=true
```

建议新增：

- `MinimizeWindow { id, target_rect }`
- `RestoreWindow { id, source_rect }`
- `Window.is_minimized`
- minimize snapshot animation state
- restore snapshot animation state

可能改动：

- `niri-ipc/src/lib.rs`
- `niri-config/src/binds.rs`
- `src/input/mod.rs`
- `src/layout/floating.rs`
- `src/layout/workspace.rs`
- `src/layout/closing_window.rs`
- `src/layout/opening_window.rs`
- `src/render_helpers/shader_element.rs`
- `src/render_helpers/shaders/`

验收标准：

- Quickshell shell 动画流畅。
- niri 窗口 open/close/move/resize 不突兀。
- snap preview 有淡入淡出。
- 普通 minimize 先有 fade/scale 版本。
- Genie effect 可作为后续增强，不阻塞最小闭环。

## 第五阶段任务：Liquid Glass

目标：让面板和窗口效果更接近 macOS 26 Tahoe。

先用现有能力：

- niri `background-effect`
- Quickshell `BackgroundEffect.blurRegion`
- `noise`
- `saturation`
- 透明 QML 背景

再改 shader：

- `src/render_helpers/background_effect.rs`
- `src/render_helpers/framebuffer_effect.rs`
- `src/render_helpers/xray.rs`
- `src/render_helpers/shaders/postprocess.frag`

建议新增配置项：

```kdl
blur {
    passes 3
    offset 4
    noise 0.025
    saturation 1.35
}

window-rule {
    match is-floating=true
    background-effect {
        blur true
        xray false
        noise 0.025
        saturation 1.35
    }
}
```

更高级再考虑：

- glass tint。
- edge highlight。
- refraction/displacement。
- active/inactive 不同强度。
- layer-shell 和普通窗口不同参数。

验收标准：

- Dock/控制中心有真实背景模糊。
- 窗口背后内容变化时玻璃同步变化。
- FPS 不明显下降。
- 多显示器和 fractional scale 下不破图。

## Quickshell 是否要 fork 核心

短期不需要。

先写 QML shell 配置，理由：

- Quickshell 已有 layer-shell。
- Quickshell 已有 toplevel 管理。
- Quickshell 已有 ext-workspace。
- Quickshell 已有 background-effect。
- Quickshell 已有 Process/Socket 能接 niri IPC。

只有这些情况才改 Quickshell 核心：

- `Process + niri msg --json` 性能/状态同步不够。
- 需要原生 niri IPC singleton。
- 需要把 niri 的窗口 layout 字段直接暴露成 QML model。
- 需要自定义更底层 Wayland 协议。

如果要新增原生 niri IPC 模块，参考：

- `quickshell/src/wayland/hyprland/ipc/`
- `quickshell/src/x11/i3/ipc/`
- `quickshell/src/io/socket.hpp`

建议模块名：

```text
Quickshell.Niri
```

可能暴露：

```text
Niri.windows
Niri.workspaces
Niri.activeWindow
Niri.focusWindow(id)
Niri.minimizeWindow(id)
Niri.restoreWindow(id)
Niri.moveFloatingWindow(id, x, y)
Niri.rawEvent
```

## 不建议优先做的事

- 不要先做服务端标题栏红黄绿按钮。
- 不要先改 Quickshell 核心。
- 不要 fork GNOME/KDE。
- 不要试图直接运行 Web 项目作为真实 shell。
- 不要一开始就追求完整 macOS 全局菜单栏。
- 不要先做锁屏/登录管理器。

这些都容易扩大范围，先把 Dock + floating + minimize + snap 做通。

## 测试建议

niri：

```text
cargo test --all
```

重点补测试：

- `src/tests/floating.rs`
- `src/tests/window_opening.rs`
- layout snapshot tests
- IPC window state tests
- foreign-toplevel minimize/unminimize 行为

Quickshell：

- 先在 Linux Wayland/niri session 下手动跑。
- 检查 `PanelWindow` 是否正确占位。
- 检查 `BackgroundEffect.blurRegion` 是否生效。
- 检查 `ToplevelManager` 是否能读到 niri 窗口。
- 检查 `WindowManager.windowsets` 是否能读到 niri workspace。

## 下一步推荐

最小闭环顺序：

1. 新建 `tahoe-shell/`，做 Quickshell 顶栏 + Dock 静态 UI。
2. 接 `ToplevelManager`，让 Dock 显示真实窗口。
3. 在 niri fork 里实现 minimize/restore。
4. Dock 点击窗口实现 activate/restore/minimize。
5. niri 实现 snap assist。
6. Quickshell 补 Dock/控制中心/Launchpad 动画。
7. niri 补窗口 open/close/move/snap 动画参数。
8. 最后做 Liquid Glass shader 和 Genie minimize。
