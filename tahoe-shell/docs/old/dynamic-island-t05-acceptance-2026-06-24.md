# Dynamic Island T05 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/services/DynamicIsland.qml`
  - 监听 `Controls.volume`、`Controls.muted`、`Controls.brightness` 和 `Controls.brightnessAvailable`。
  - 音量、静音和亮度变化进入 `transient_osd`。
  - OSD 自动收起时长为 `1250ms`。
  - expanded 或用户交互期间不抢占当前岛内容，保留单槽 pending OSD。
- `tahoe-shell/components/DynamicIslandContent.qml`
  - 为 `transient_osd` 添加专用图标、百分比和环形进度。
  - progress 变化使用 `DynamicIslandMotion.overlayProgressDuration = 180`。
- `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/`
  - `osd-volume.png`
  - `osd-brightness.png`
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T05 完成并链接本验收记录。

`tahoe-shell/services/Controls.qml` 未修改。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/DynamicIslandContent.qml tahoe-shell/components/DynamicIslandMediaView.qml tahoe-shell/components/DynamicIslandSummaryView.qml tahoe-shell/shell.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path tahoe-shell
bash scripts/check-tahoe-glass-guardrails.sh
rsync -a /home/wwt/niri/tahoe-shell/ /home/wwt/.config/quickshell/tahoe/
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowOsd 'volume' 0.45
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.01
brightnessctl set 97%
grim -g '0,0 2048x240' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/osd-volume.png
grim -g '0,0 2048x240' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/osd-brightness.png
niri msg --json layers
```

结果：

- `qmllint`：退出 0；仍有既有 Quickshell `PanelWindow` 不可创建、`TahoeGlassRegion` 类型元数据不完整、`modelData` unqualified warning。
- `quickshell` smoke：到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
- `check-tahoe-glass-guardrails.sh`：退出 0。
- IPC OSD smoke：进入 `state=transient_osd`，`secondaryText=45%`，`progress=0.45`。
- 外部音量变化：
  - `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.01`
  - 触发 `state=transient_osd; displayText=音量; secondaryText=1%; progress=0.0099945068359375`
  - 约 1.25 秒后回到 `resting_media`。
- 外部亮度变化：
  - `brightnessctl set 97%`
  - 等待 `Controls.qml` 轮询刷新后触发 `state=transient_osd; displayText=亮度; secondaryText=97%; progress=0.97`

## 运行时 Layer 列表

`niri msg --json layers`：

```json
[
  {"namespace":"linux-wallpaperengine","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-wallpaper","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-topbar","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dynamic-island","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dock","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"}
]
```

结论：T05 未新增 layer，`tahoe-dynamic-island` 仍为 `Top` layer，`exclusiveZone: 0` 由 T03 保持。

## 视觉检查

- OSD 胶囊宽度约 `220px`，内容居中，图标、百分比和环形进度没有重叠。
- 浅色壁纸背景下 OSD 仍可读。
- 连续状态更新保持在同一胶囊内，不反复创建 layer。

## 已知问题

- 亮度外部变化依赖既有 `Controls.qml` 的 4 秒轮询，所以 `brightnessctl` 触发不是即时事件；T05 未改 `Controls.qml` 生命周期。
- 音量测试结束后已将默认音量恢复到原先的 `0.00`。
