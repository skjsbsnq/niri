# Dynamic Island T06 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/services/DynamicIsland.qml`
  - 暴露媒体只读属性：`mediaArtUrl`、`mediaPlaying`、`canPlayPause`、`canNext`、`canPrev`。
  - 暴露媒体控制函数：`mediaTogglePlayPause()`、`mediaNext()`、`mediaPrevious()`。
  - `showExpandedMedia()` 继续只使用 Tahoe `Controls.activePlayer`，没有引入 Tide 后端。
- `tahoe-shell/components/DynamicIslandMediaView.qml`
  - 新增媒体展开视图。
  - 显示封面、标题、艺术家、播放/暂停、上一首、下一首和右侧小型播放状态条。
- `tahoe-shell/components/DynamicIslandContent.qml`
  - 在 `expanded_media` 中渲染 `DynamicIslandMediaView`。
- `tahoe-shell/components/DynamicIslandOverlay.qml`
  - 将媒体属性和媒体控制信号转发到服务。
- `tahoe-shell/shell.qml`
  - 增加媒体控制 IPC smoke 函数。
- `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/`
  - `resting-media.png`
  - `media-expanded.png`
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T06 完成并链接本验收记录。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/DynamicIslandContent.qml tahoe-shell/components/DynamicIslandMediaView.qml tahoe-shell/components/DynamicIslandSummaryView.qml tahoe-shell/shell.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path tahoe-shell
playerctl -l
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetDebugSummary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowExpandedMedia
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandMediaToggle
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandMediaNext
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandMediaPrevious
grim -g '0,0 2048x240' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/resting-media.png
grim -g '0,0 2048x260' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/media-expanded.png
```

结果：

- 临时 MPRIS 测试源注册为 `miniplayer`，只用于验收，不提交到仓库。
- resting media：
  - `state=resting_media`
  - `displayText=Island Test Track`
  - `secondaryText=Tahoe Verification`
- 展开媒体：
  - `dynamicIslandShowExpandedMedia` 返回 `expanded_media`
  - 展开态仍为 `400x165` 目标几何，主 morph 使用 T03 的 `400ms OutQuint`。
- 媒体控制：
  - `dynamicIslandMediaToggle` 后图标从播放态切到暂停态。
  - `dynamicIslandMediaNext` 后测试播放器标题变为 `Island Test Track <`。
  - `dynamicIslandMediaPrevious` 后测试播放器标题变为 `Island Test Track < >`。
- 无播放器路径曾在验收前 smoke：无 MPRIS 时 `dynamicIslandShowExpandedMedia` 回退到 `expanded_summary`，不崩 shell。

## 运行时 Layer 列表

T06 没有新增 layer；运行时仍为：

```json
[
  {"namespace":"linux-wallpaperengine","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-wallpaper","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-topbar","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dynamic-island","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dock","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"}
]
```

## 视觉检查

- 媒体展开态居中，封面、标题、艺术家、三枚控制按钮和播放状态条没有重叠。
- 长标题使用单行 elide，内容不会撑开胶囊。
- 展开态通知/OSD 不强行覆盖，沿用服务的 expanded 阻塞规则。

## 已知问题

- 第一版没有实现进度条/拖动 scrubber；路线图 T06 只要求封面、标题、艺术家和基本控制。
- 验收使用 `/tmp/mpris-mini.py` 临时 MPRIS 测试源，该文件不属于项目产物。
