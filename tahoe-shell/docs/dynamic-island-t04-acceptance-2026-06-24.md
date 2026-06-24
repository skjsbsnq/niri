# Dynamic Island T04 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/services/DynamicIsland.qml`
  - 监听 `Notifications.activeModel` 增长，真实新通知进入 `transient_notification`。
  - 保留 `NotificationToast` 和 `NotificationCenter`，不改 `Notifications.qml` 核心生命周期。
  - 通知显示时长为 `4200ms`。
  - DND 开启时不显示岛通知；现有 `Notifications.qml` 仍先写入 history 再抑制 visual queue。
  - expanded 或鼠标交互期间不强行打断，使用单槽 pending notification，解除阻塞后显示。
  - 清理通知 summary/body/appName 中的 HTML 标签和常见实体，包括 `&amp;`、`&lt;`、`&gt;`、`&quot;`、`&apos;`、`&nbsp;` 和数字实体。
- `tahoe-shell/components/DynamicIslandContent.qml`
  - 新增岛内容渲染组件。
  - 通知内容独立淡入/淡出：`280ms` in、`140ms` out。
  - 通知胶囊内文本固定单行 elide，避免多通知或长文本导致宽度抖动。
  - 保留 T03 的 resting/detail/progress 内容路径，后续 T05/T06 可复用。
- `tahoe-shell/components/DynamicIslandOverlay.qml`
  - overlay 只保留几何、glass、mask 和输入转发。
  - 接入 `DynamicIslandContent`。
  - 鼠标按下期间向服务标记 `userInteracting`，避免通知打断用户操作。
- `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t04/`
  - `notification-capsule.png`
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T04 完成并链接本验收记录。

`tahoe-shell/services/Notifications.qml` 未修改。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/services/DynamicIsland.qml tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/DynamicIslandContent.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
bash scripts/check-tahoe-glass-guardrails.sh
rsync -a /home/wwt/niri/tahoe-shell/ /home/wwt/.config/quickshell/tahoe/
niri msg --json layers
notify-send 'Island <b>&amp; Real</b>' 'Body &lt;b&gt;bold&lt;/b&gt; &amp; entity'
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetDebugSummary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowExpandedSummary
notify-send 'Queued <b>&amp; Notice</b>' 'Pending &lt;i&gt;body&lt;/i&gt; &amp; text'
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowTime
notify-send 'DND Island Test' 'Should stay hidden'
grim -g '0,0 2048x220' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t04/notification-capsule.png
```

结果：

- `qmllint`：退出 0；仍有 T03 已记录过的 Quickshell `PanelWindow` 不可创建、`TahoeGlassRegion` 类型元数据不完整和 unqualified warning。
- `quickshell` smoke：到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
- `check-tahoe-glass-guardrails.sh`：退出 0，Phase 7 guardrails 通过。
- `notify-send` 非 DND：
  - `state=transient_notification`
  - `displayText=Island & Real`
  - `secondaryText=Body bold & entity`
  - 5 秒后回到 `resting_time`。
- expanded 阻塞：
  - expanded 时发通知保持 `expanded_summary`，`pendingNotification=true`。
  - 收起后进入 `transient_notification`，`displayText=Queued & Notice`，`secondaryText=Pending body & text`。
- DND：
  - 已恢复 live state 为 `"dndEnabled": true`。
  - DND 下 `notify-send` 后岛保持 `resting_time`，`pendingNotification=false`。

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

结论：T04 没有新增 layer；`tahoe-dynamic-island` 仍为 `Top` layer，`keyboard_interactivity` 为 `None`，overlay QML 仍是 `exclusiveZone: 0`。

## 视觉检查

- 通知胶囊居中显示，宽度固定为 T03 定义的 `320px`，连续通知不会改变胶囊宽度。
- 通知内容和图标在 `56px` 高度内没有重叠，长文本单行 elide。
- `NotificationToast` 仍显示在右侧，T04 第一版允许与岛通知共存。
- 截图：`tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t04/notification-capsule.png`

## 已知问题

- T04 只接入通知胶囊；音量/亮度 OSD、媒体展开、左右滑动和工作区胶囊仍按 T05+ 串行实现。
- DND history 更新依赖既有 `Notifications.qml` 顺序：`pushHistory(notification)` 在 DND 分支之前；T04 未改该服务生命周期。
- live 验收期间曾临时将 `/home/wwt/.local/state/quickshell/by-shell/tahoe/notifications.json` 的 `dndEnabled` 改为 `false` 以覆盖非 DND `notify-send` 路径；验收结束后已恢复为 `true` 并重启 live shell。
