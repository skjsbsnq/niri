# Liquid Glass T4 Visual Baseline

日期：2026-06-29

## 范围

本目录记录 T4 shader 调参与可读性工作的当前会话视觉基线。T4 代码改动落在仓库
`niri/` submodule 中；当前运行中的 compositor 是已安装的
`/home/wwt/.local/bin/niri 26.04 (c205293c)`，不会热加载本工作区刚修改的 shader。
因此这些截图是当前会话的可见基线和触发能力记录，不作为新 shader 的最终视觉验收。

## 环境

- Wayland：`WAYLAND_DISPLAY=wayland-1`
- 桌面：`XDG_CURRENT_DESKTOP=niri`
- niri：`26.04 (c205293c)`
- Quickshell：`0.3.0 (revision 8b3b864db99e78e70e247af4ff2f99e7706924e5, distributed by Tahoe fork)`
- 输出：`eDP-2`，物理截图 `2560x1600`，逻辑 `2048x1280`，scale `1.25`
- 截图工具：`grim`
- 裁剪工具：`magick`

运行中的配置和仓库当前文件不一致：

- `/home/wwt/.config/niri/tahoe/config.kdl` 与 `config/niri/tahoe-phase0.kdl` 不一致。
- `/home/wwt/.config/quickshell/tahoe/components/TahoeGlass.js` 与 `tahoe-shell/components/TahoeGlass.js` 不一致。

## 资产

| 文件 | 尺寸 | sha256 | 说明 |
| --- | --- | --- | --- |
| `00-idle-full.png` | `2560x1600` | `1f1edc255c05f732f54fee10b14cceec5a6f1dfef34627578225f780d54f73b4` | 当前 idle 全屏，包含 TopBar、Dynamic Island、当前窗口。 |
| `topbar.png` | `2560x120` | `1177285b656812ebf8dba3fa434e5924bea16c400b5ae5fc0a4e7319e15150ae` | 从 idle 截图裁出的 TopBar 区域。 |
| `dock.png` | `2560x220` | `2fb48768cfd8bf8e88bafadcc3510c97f418dd6d6f3709faac996f343f1aae3c` | 从底部裁剪；当前 dock 未可见或被窗口/自动隐藏状态遮挡。 |
| `00-idle-layers.json` | n/a | `fe7945a1d3f3478219200b75b0fa19535876f0007d09b3601b1654551230c2e8` | idle layer 列表。 |
| `01-notification-toast-attempt-full.png` | `2560x1600` | `0fd35be6dfced20f9799ca673ab66d4b3d621eb803c0f12a1f3e3030d6687676` | `notify-send` 后截图；DND 抑制 toast。 |
| `01-notification-toast-attempt-layers.json` | n/a | `fe7945a1d3f3478219200b75b0fa19535876f0007d09b3601b1654551230c2e8` | toast 尝试后的 layer 列表。 |

## Layer 记录

idle 与通知尝试后 layer 一致：

- `linux-wallpaperengine`
- `tahoe-wallpaper`
- `tahoe-topbar`
- `tahoe-dynamic-island`
- `tahoe-dock`

没有出现 `tahoe-notification-toast`。当前
`/home/wwt/.local/state/quickshell/by-shell/tahoe/notifications.json` 中
`dndEnabled` 为 `true`。

## T4 截图状态

| 场景 | 状态 | 记录 |
| --- | --- | --- |
| TopBar | 已截图 | `topbar.png`。 |
| Dock | layer 存在，未形成可见验收图 | `dock.png` 显示当前底部状态，不足以验收 dock 玻璃。 |
| ControlCenter | 未自动触发 | 当前 Quickshell IPC 未暴露 open/close，且无 `wtype`、`ydotool`、`dotool`、`wlrctl`。 |
| Spotlight | 未自动触发 | 当前 Quickshell IPC 未暴露 open/close。 |
| NotificationToast | 已尝试，未出现 | DND 为 true，`notify-send` 被写入历史/抑制视觉 toast。 |
| Launchpad/backdrop | 未自动触发 | 当前 Quickshell IPC 未暴露 open/close。 |

## 新 shader 验收要求

重启到本工作区构建的 niri 后，应重新采集以下场景，才能完成视觉验收：

- Dock 可见状态。
- TopBar。
- ControlCenter。
- Spotlight。
- NotificationToast，需先关闭 DND。
- Launchpad/backdrop。

检查重点：

- 无方形 halo。
- 文本不被折射明显扭曲。
- TopBar/Dock 只对内部 region 做玻璃，不把整个 layer surface 当玻璃。
- 大面积 Launchpad/backdrop 没有整屏水波、巨大 rim 或明显 stutter。
