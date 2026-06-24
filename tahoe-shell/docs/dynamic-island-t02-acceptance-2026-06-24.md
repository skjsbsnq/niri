# Dynamic Island T02 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/services/DynamicIsland.qml`
  - 新增 Tahoe 本地灵动岛状态机服务。
  - 暴露 `state`、`displayText`、`secondaryText`、`progress`、`iconCode`、`targetScreenName`、`expanded`。
  - 第一版状态包含 `resting_time`、`resting_media`、`transient_osd`、`transient_notification`、`transient_workspace`、`expanded_media`、`expanded_summary`。
  - 接入 `Controls` 的 MPRIS 只读字段、`Windows` 的屏幕/工作区字段，未新增后端。
- `tahoe-shell/shell.qml`
  - 实例化 `DynamicIsland` 服务并传入 `controls`、`notifications`、`niri`。
  - 将服务传给每个 screen 的 `TopBar`。
  - 在既有 `target tahoe` IPC handler 上增加 `dynamicIsland*` smoke 函数。
- `tahoe-shell/components/TopBar.qml`
  - 移除 topbar 本地时间计时器。
  - `DynamicIslandChip.displayText` 改为读取 `dynamicIslandService.displayText`。
  - chip 点击转发给服务状态机；T02 不打开 overlay。
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T02 完成并链接本验收记录。

## 验证命令

```bash
git diff --check -- tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/TopBar.qml tahoe-shell/shell.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
rsync -a /home/wwt/niri/tahoe-shell/ /home/wwt/.config/quickshell/tahoe/

log=$(mktemp)
/home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell >"$log" 2>&1 &
pid=$!
/home/wwt/.local/bin/qs ipc --pid "$pid" show
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetDebugSummary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowOsd Volume 0.42
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetState
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandReset
kill "$pid"

command -v playerctl >/dev/null 2>&1 && playerctl -l || true
niri msg --json layers
```

`quickshell` smoke test reached `Configuration Loaded`; `timeout` exits with code 124 by design.

IPC smoke result:

```text
state=resting_time; displayText=Wed 00:29; secondaryText=2026-06-24; progress=-1; iconCode=...; targetScreenName=eDP-2; expanded=false
dynamicIslandShowOsd Volume 0.42 -> transient_osd
dynamicIslandGetState -> transient_osd
dynamicIslandReset -> resting_time
```

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

结论：T02 没有新增 `tahoe-dynamic-island` layer，也没有新增 exclusive zone。

## 视觉检查

- 顶栏中心仍是 T01 的 24px chip，T02 只把文本来源切到服务。
- 无媒体时 chip 显示服务提供的时间。
- IPC 触发 `transient_osd` 只改变服务状态；因为 T02 不渲染 overlay，屏幕上不会出现 OSD 胶囊。
- 左右状态区、顶栏高度和 `tahoe-topbar` layer 保持 T01 结果。

## 已知问题

- 当前会话 `playerctl -l` 返回 `No players found`，因此本机未能实测真实 MPRIS player 下的 `resting_media` 视觉显示；代码路径读取 `Controls.hasMedia`、`trackTitle`、`trackArtist`，无媒体时正确回退到 `resting_time`。
- `qs ipc -p /home/wwt/niri/tahoe-shell` 会命中同配置的旧实例；smoke 测试必须用 `qs ipc --pid "$pid"` 指向本次启动的临时进程。
- live 启动日志仍有既有 `shell.qml[322]` font 只读属性警告、Dock magnification interceptor 警告和通知服务占用警告；T02 未触碰对应代码。
