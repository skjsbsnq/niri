# Dynamic Island T01 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/components/TopBar.qml`
  - 删除顶栏中心裸时间 `Text`。
  - 增加中心 `DynamicIslandChip`，保持 `exclusiveZone: 34` 不变。
  - 左侧内容改为普通 `Row` 紧凑排列，并在中心 chip 前裁剪，避免 1366px 等窄宽度下钻到中心。
- `tahoe-shell/components/DynamicIslandChip.qml`
  - 新增 24px 高常驻时间胶囊。
  - 默认显示 `ddd HH:mm`，使用更实的浅/深色胶囊背景提高可读性。
- `tahoe-shell/components/DynamicIslandMotion.js`
  - 新增 chip-only hover/press/content 动画 token。
- `tahoe-shell/docs/visual-baselines/2026-06-23-dynamic-island-t01/resting-chip.png`
  - T01 顶栏截图基线。

## 验证命令

```bash
git diff --check -- tahoe-shell/components/TopBar.qml tahoe-shell/components/DynamicIslandChip.qml tahoe-shell/components/DynamicIslandMotion.js
timeout 8s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
rsync -a /home/wwt/niri/tahoe-shell/ /home/wwt/.config/quickshell/tahoe/
niri msg --json layers
grim -g '0,0 2048x96' tahoe-shell/docs/visual-baselines/2026-06-23-dynamic-island-t01/resting-chip.png
```

`quickshell` smoke test reached `Configuration Loaded`; the `timeout` command exits after 8s by design.

## 运行时 Layer 列表

`niri msg --json layers`:

```json
[
  {"namespace":"linux-wallpaperengine","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-wallpaper","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-topbar","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dock","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"}
]
```

结论：T01 没有新增 `tahoe-dynamic-island` layer，仍只有原有 `tahoe-topbar`。

## 视觉检查

- 顶栏中心裸时间已替换为 24px 高实体胶囊。
- 胶囊在当前浅色/复杂壁纸上可读，背景比顶栏玻璃更实。
- 左侧 niri 图标、active app、应用菜单、工作区恢复紧凑 spacing；未再出现 `RowLayout` 拉伸导致的大间隙。
- 右侧 tray、通知、状态按钮没有和中心胶囊重叠。
- 截图：`tahoe-shell/docs/visual-baselines/2026-06-23-dynamic-island-t01/resting-chip.png`

## 已知问题

- live 启动日志仍有既有 `shell.qml[322]` font 只读属性警告和 Dock magnification interceptor 警告；本任务未触碰对应代码。
- T01 未引入 overlay、通知、OSD、媒体或服务状态机；这些必须等待 T02+。
