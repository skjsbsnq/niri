# Dynamic Island T07 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/services/DynamicIsland.qml`
  - 新增左右滑动状态：`swipeProgress`、`swipeStartProgress`、`swipeDragging`、`swipeSettling`、`swipePreviewWidth`。
  - 实现 `beginSwipe()`、`advanceSwipe()`、`resolveSwipe()`、`cancelSwipe()`。
  - 支持 resting -> media/summary，也支持 expanded media/summary -> center 回中。
  - 阈值和 settle 时长引用 `DynamicIslandMotion.js`。
- `tahoe-shell/components/DynamicIslandMotion.js`
  - 集中新增 side-swipe token：
    - `swipeSettleDuration = 220`
    - `swipeEnterThreshold = 0.56`
    - `swipeReturnThreshold = 0.44`
    - `swipeVerticalTolerance = 24`
    - `swipeSettleIdleMs = 150`
    - `swipeSuppressClickMs = 180`
- `tahoe-shell/components/DynamicIslandOverlay.qml`
  - 鼠标拖动和 wheel 都进入服务 swipe 状态机。
  - 拖动中胶囊宽度跟随 `swipePreviewWidth`。
  - 松手后使用 `220ms OutCubic` settle。
  - 滑动后短时间抑制 click，避免误触展开。
- `tahoe-shell/components/DynamicIslandSummaryView.qml`
  - 新增摘要页：电池、音量、亮度、工作区。
- `tahoe-shell/components/DynamicIslandContent.qml`
  - 在 `expanded_summary` 中渲染摘要页。
- `tahoe-shell/shell.qml`
  - 增加 swipe IPC smoke 函数。
- `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/`
  - `swipe-right-halfway.png`
  - `swipe-right-settled-media.png`
  - `swipe-left-settled-summary.png`
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T07 完成并链接本验收记录。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/DynamicIslandContent.qml tahoe-shell/components/DynamicIslandMediaView.qml tahoe-shell/components/DynamicIslandSummaryView.qml tahoe-shell/shell.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path tahoe-shell
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSwipeBegin
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSwipeAdvance 180 0
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSwipeResolve
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSwipeAdvance 260 0
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSwipeAdvance -240 0
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandSwipeAdvance 260 80
grim -g '0,0 2048x240' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/swipe-right-halfway.png
grim -g '0,0 2048x260' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/swipe-right-settled-media.png
grim -g '0,0 2048x260' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t05-t08/swipe-left-settled-summary.png
```

结果：

- 快速短滑：
  - `swipeProgress=0.45`
  - `swipePreviewWidth=284.5`
  - 松手后回到 `resting_media`
  - 未误进入 expanded。
- 右滑过阈值：
  - `swipeProgress=0.65`
  - 松手后进入 `expanded_media`。
- 左滑过阈值：
  - `swipeProgress=-0.6666666666666666`
  - 松手后进入 `expanded_summary`。
- 回中阈值：
  - 从 `expanded_media` 拖回到 `0.375 <= 0.44` 后回到 `resting_media`。
  - 从 `expanded_summary` 拖回到 `-0.38888888888888884 >= -0.44` 后回到 `resting_media`。
- 垂直容忍：
  - `dynamicIslandSwipeAdvance 260 80` 被垂直容忍降权，`swipeProgress=0`，未误进入页面。

## 运行时 Layer 列表

T07 没有新增 layer；运行时仍为：

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

- 半滑预览中胶囊宽度跟随变化，没有内容跳变。
- 媒体页和摘要页 settle 后内容没有文字溢出。
- 摘要页四项信息两列排列，电池/音量/亮度/工作区没有重叠。

## 已知问题

- T07 首版没有额外绘制 Tide 的歌词/自定义侧向内容过渡层；右滑目标暂时是媒体页，左滑目标是摘要页。
- T07 对触控板 wheel 做了横向/纵向有效 delta 转换，实际硬件手感仍建议在 T10 基线阶段继续录屏微调。
