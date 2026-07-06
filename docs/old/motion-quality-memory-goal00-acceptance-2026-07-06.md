# GOAL-0 验收：现状基线

日期：2026-07-06

范围：只记录当前 Tahoe / niri 动画、glass、内存、thumbnail 和触发入口基线。不修改代码、不修改 KDL 参数、不修改 QML 动效。

## 完成了什么

- 记录了当前运行环境、二进制版本和部署配置一致性。
- 记录了 idle 和部分可 IPC 触发 surface 的 `niri msg --json layers` 结果。
- 梳理了要求覆盖 surface 的触发矩阵，并明确哪些场景当前无法自动触发。
- 记录了当前 KDL layer animation profile、QML motion token 和硬编码动画分布。
- 记录了 TahoeGlass region 声明分布、全局 blur/material 配置、frame-time 可观测性缺口。
- 记录了 RSS、thumbnail runtime cache 和 thumbnail provider 行为。

## 运行环境

| 项 | 记录 |
| --- | --- |
| 采样时间 | `2026-07-06T19:05:10+08:00` 到 `2026-07-06T19:10:40+08:00` |
| session | `Type=wayland`, `Desktop=tahoe-niri`, `Service=lightdm`, `State=active` |
| socket | `NIRI_SOCKET=/run/user/1000/niri.wayland-1.1253.sock` |
| compositor | `/home/wwt/.local/bin/niri --session --config /home/wwt/.config/niri/tahoe/config.kdl` |
| version | `/home/wwt/.local/bin/niri msg --json version` -> `cli=f07648af`, `compositor=f07648af` |
| output | `eDP-2`, logical `2048x1280`, scale `1.25`, mode `2560x1600@239.998`, VRR supported but disabled |
| config source | `config/niri/tahoe-phase0.kdl` and `/home/wwt/.config/niri/tahoe/config.kdl` are byte-identical (`cmp` returned `0`) |

注意：`niri` on PATH reports CLI `8ed0da4` and cannot validate Tahoe-specific KDL nodes. Validation for this baseline must use `/home/wwt/.local/bin/niri`; that binary reports the config as valid.

## 动画触发矩阵

Idle live layers:

```text
linux-wallpaperengine Background
tahoe-wallpaper       Background
tahoe-topbar          Top
tahoe-dynamic-island  Top
tahoe-dock            Top
```

| Surface | Namespace | 当前触发入口 | 自动触发状态 | 当前 compositor profile | 采样结果 |
| --- | --- | --- | --- | --- | --- |
| Control Center | `tahoe-control-center` | topbar / Dynamic Island 内部调用 `toggleTopBarPopup("controlCenter", ...)` | 当前 Quickshell IPC 未暴露 open/close/toggle；无法自动触发 | `edge-reveal top`, open `210/110ms`, close transform `210ms`, close opacity `0ms` | 未自动采样 |
| Notification Center | `tahoe-notification-center` | topbar bell 调用 `toggleTopBarPopup("notificationCenter", ...)` | 当前 IPC 未暴露；无法自动触发 | `edge-reveal top`, open `210/100ms`, close transform `210ms`, close opacity `0ms` | 未自动采样 |
| Small Popup | `tahoe-battery-popup`, `tahoe-wifi-popup`, `tahoe-fan-popup`, `tahoe-clipboard-popup`, `tahoe-menu-popup`, `tahoe-application-menu`, `tahoe-tray-menu` | topbar/dock click path | 当前 IPC 未暴露这些 popup 的 anchor-aware open/close；无法自动触发 | `edge-reveal top`, open `180/90ms`, close transform `180ms`, close opacity `0ms` | 未自动采样 |
| Spotlight | `tahoe-spotlight` | topbar search button toggles `spotlightOpen` | 当前 IPC 未暴露；无法自动触发 | `popin/popout center`, open `180/120ms`, close `110/80ms` | 未自动采样 |
| Toast | `tahoe-notification-toast` | desktop notification route (`notify-send`) | `notify-send` 可执行；本次采样后 `layers` 未观察到 toast namespace | `slide right`, open `180/100ms`, close `110/80ms` | 触发返回成功，但 0.25s/1.0s 采样均未见 layer |
| Dock | `tahoe-dock` | 常驻 surface | idle 自动存在 | 无 compositor open/close rule；QML 内部 motion | idle `Top`, `keyboard_interactivity=None` |
| Window Overview | `tahoe-window-overview` | Quickshell IPC `openWindowOverview` / `closeWindowOverview` | 可自动触发 | 无 compositor rule；QML 外层动画 | open 后出现 `Overlay`, `keyboard_interactivity=OnDemand` |
| Task Switcher | `tahoe-task-switcher` | Quickshell IPC `openTaskSwitcher` / `closeTaskSwitcher` | 可自动触发 | 无 compositor rule；QML 外层动画 | open 后出现 `Overlay`, `keyboard_interactivity=OnDemand` |
| Left Sidebar | `tahoe-left-sidebar` | Quickshell IPC `openLeftSidebar` / `closeLeftSidebar` | 可自动触发 | `edge-reveal left`, no opacity fade | open 后出现 `Top`, `keyboard_interactivity=OnDemand` |

## QML 硬编码动画清单

现有统一 token：

- `tahoe-shell/components/Motion.js`: `fadeFastDuration=120`, `menuEnterDuration=150`, `menuExitDuration=120`, `panelEnterDuration=180`, `panelExitDuration=140`, `elementMoveDuration=130`, `elementResizeDuration=180`; easing 为 `emphasizedDecel`, `emphasizedAccel`, `standardDecel`, `expressiveEffects`。
- `tahoe-shell/components/DynamicIslandMotion.js`: Dynamic Island chip、overlay、content、progress、swipe、hover timings。

静态扫描结果：

- `rg "(NumberAnimation|ColorAnimation|PropertyAnimation|SequentialAnimation|ParallelAnimation|SpringAnimation)" tahoe-shell --glob '*.qml' --glob '*.js'` 命中 `89` 行。
- `rg "duration: *[0-9]|easing\\.type: *Easing|ColorAnimation \\{ duration: *[0-9]|NumberAnimation \\{.*duration: *[0-9]" ...` 命中 `42` 行，代表仍有数字 duration/easing 硬编码。
- `Motion.` / `IslandMotion.` 使用已经覆盖 Spotlight、Toast、Control Center、Notification Center、Wi-Fi/Fan popup、Dynamic Island 相关组件的一部分内部动效。

硬编码集中分布：

| 文件 | 动画块命中 | 数字硬编码命中 | 备注 |
| --- | ---: | ---: | --- |
| `tahoe-shell/components/Dock.qml` | 16 | 9 | dock 常驻 surface，仍有 bounce/magnification/opacity/y 数字动效 |
| `tahoe-shell/components/WindowButton.qml` | 8 | 4 | 与 Dock delegate 类似 |
| `tahoe-shell/components/WindowOverview.qml` | 3 | 3 | 外层 opacity/scale 数字动效 |
| `tahoe-shell/components/TaskSwitcher.qml` | 2 | 2 | 外层 opacity/scale 数字动效 |
| `tahoe-shell/components/SettingsPanel.qml` | 3 | 3 | 外层 opacity/scale 数字动效 |
| `tahoe-shell/components/Launchpad.qml` | 2 | 2 | 当前保持 QML path |
| `tahoe-shell/components/TopBar.qml` | 1 | 1 | topbar opacity |
| `tahoe-shell/components/LeftSidebarSystem.qml` | 5 | 5 | system charts/indicators |
| `tahoe-shell/components/LeftSidebarWeather.qml` | 5 | 4 | weather visual effects |
| settings controls | 3 | 3 | `TahoeSwitch`, `TahoeTextField`, `SettingsSidebar` |

## Glass、blur 与 frame-time 基线

KDL 当前全局 blur：

```text
blur on
passes 4
offset 4
noise 0.004
saturation 1.22
```

KDL 当前 TahoeGlass material source of truth:

- materials: `panel`, `pill`, `launcher`, `dock`, `menu`, `toast`, `backdrop`
- all default `chromatic` values are `0.0`
- highest current material `refraction` is `pill=0.013`; menu/toast stay at `0.004/0.005`

QML static TahoeGlass region declarations:

- `TahoeGlass.regions` appears in 22 component files.
- Most surfaces declare one region.
- `Spotlight.qml` declares two regions: `spotlightSurface.region` and `resultsSurface.region`.
- Required surfaces with glass regions: Control Center, Notification Center, Spotlight, Toast, Dock, Window Overview, Task Switcher, and the small popup components all declare TahoeGlass regions.

Compositor guardrails observed in code:

- `niri/src/protocols/tahoe_glass.rs` caps regions at `MAX_REGIONS_PER_SURFACE = 32`.
- Validation drops empty/out-of-surface regions and stops when total region area exceeds the surface area.
- `niri/src/render_helpers/framebuffer_effect.rs` has reusable `subregion_damage` storage.
- Tracy spans exist around `FramebufferEffectElement::capture_framebuffer` and `EffectBuffer::prepare_offscreen`.

Frame-time measurement status:

- Live `journalctl --user` did not contain frame-time, framebuffer capture, blur render, or TahoeGlass timing records for this run.
- No compositor restart or Tracy capture was performed in GOAL-0, to avoid changing the session under measurement.
- Numeric frame-time and blur render timing remain a baseline gap for GOAL-8; available instrumentation should be captured there.

## RSS 与 thumbnail 基线

RSS after sampling at `2026-07-06T19:10:40+08:00`:

| Process | RSS KiB | Notes |
| --- | ---: | --- |
| `quickshell` | 502832 | `/home/wwt/.local/bin/quickshell -p /home/wwt/.config/quickshell/tahoe` |
| `niri` compositor | 178112 | `/home/wwt/.local/bin/niri --session --config ...` |
| `xdg-desktop-portal-gnome` | 71672 | portal process |
| `xdg-desktop-portal-gtk` | 26680 | portal process |
| `xdg-desktop-portal` | 20004 | portal process |
| `niri msg --json event-stream` | 15824 | child owned by Quickshell |
| `xwayland-satellite` | 6736 | started by niri |

Thumbnail runtime cache after Window Overview / Task Switcher sampling:

```text
window-2.png 25562
window-3.png 13540
window-5.png 20074
window-7.png 33721
```

Thumbnail behavior facts:

- `ThumbnailProvider.qml` is the single shell-side thumbnail queue.
- Queue limit is `maxQueueLength: 64`.
- Cache freshness is `maxCacheAgeMs: 30000`.
- Runtime path is `$XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png`.
- It shells out to `niri msg --json window-thumbnail` with an 8s timeout.
- Dock minimized shelf, Task Switcher, and Window Overview use this provider.
- No active `window-thumbnail` child process remained after sampling.

## Nested winit 与 DRM/TTY 差异说明

This run was taken from the active Tahoe Wayland session launched by LightDM on `seat0`, not from a nested winit test instance. The config itself documents the important input-mode difference: `Mod` is Super on TTY and Alt under winit. Visual motion quality from nested winit was not used as final evidence for this gate.

## 没有做什么

- 没有修改 Rust、QML、Python 或 KDL behavior/parameter files。
- 没有新增 motion profile、IPC route、Wayland protocol、thumbnail provider 或 KDL writer。
- 没有重启 niri、没有 reload config、没有开启 debug damage/tint。
- 没有用 nested winit 结果替代 DRM/TTY session 观察。
- 没有做 GOAL-1 及后续任务的实现。

## 复用了哪些现有接口

- `niri msg --json version/outputs/layers/windows/overview-state`
- `/home/wwt/.local/bin/niri validate --config ...`
- Quickshell IPC target `tahoe` 的现有 `openWindowOverview`, `closeWindowOverview`, `openTaskSwitcher`, `closeTaskSwitcher`, `openLeftSidebar`, `closeLeftSidebar`
- `notify-send` desktop notification route
- static source inspection of `config/niri/tahoe-phase0.kdl`, `Motion.js`, `DynamicIslandMotion.js`, `TahoeGlass.js`, `ThumbnailProvider.qml`

## 是否新增接口

没有新增接口。

## 运行命令

关键命令：

```text
/home/wwt/.local/bin/niri msg --json version
/home/wwt/.local/bin/niri msg --json outputs
/home/wwt/.local/bin/niri msg --json layers
/home/wwt/.local/bin/niri msg --json windows
/home/wwt/.local/bin/niri msg --json overview-state
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe show
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe call tahoe openWindowOverview
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe call tahoe closeWindowOverview
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe call tahoe openTaskSwitcher
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe call tahoe closeTaskSwitcher
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe call tahoe openLeftSidebar
/home/wwt/.local/bin/quickshell ipc -p /home/wwt/.config/quickshell/tahoe call tahoe closeLeftSidebar
notify-send -a 'Tahoe GOAL-0' 'Tahoe GOAL-0 baseline' 'Temporary toast trigger for motion baseline.'
ps -eo pid,ppid,rss,vsz,comm,args --sort=-rss
find ${XDG_RUNTIME_DIR}/tahoe/window-thumbnails -maxdepth 1 -type f
rg ...
cmp -s config/niri/tahoe-phase0.kdl /home/wwt/.config/niri/tahoe/config.kdl
```

Known failed command:

```text
niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
```

Reason: PATH `niri` CLI is `8ed0da4` and does not know Tahoe-specific schema. The running Tahoe binary `f07648af` validates the same config successfully.

## 剩余风险

- Control Center、Notification Center、Small Popup、Spotlight 缺少当前 IPC trigger，GOAL-2 必须补齐或正式记录不可触发原因。
- Toast trigger route returned success but no toast layer was observed in this sampling window; GOAL-2 must make toast sampling repeatable.
- GOAL-0 did not produce numerical frame-time or blur render timing; GOAL-8 must capture Tracy/RUST_LOG evidence before material changes.
- RSS is a point-in-time observation, not a leak test.
- `niri msg --json layers` does not expose TahoeGlass committed region counts or areas, so region area baseline is static/source-based.

## 回滚方式

This gate only adds this acceptance document and updates the GOAL-0 status row in the goal document. Rollback is deleting this file and reverting that status row. No runtime behavior or user configuration needs rollback.

