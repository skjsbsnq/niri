# Dynamic Island T03 验收记录

日期：2026-06-24

状态：完成

## 修改文件

- `tahoe-shell/components/DynamicIslandOverlay.qml`
  - 新增 per-screen `PanelWindow` overlay。
  - `WlrLayershell.namespace: "tahoe-dynamic-island"`。
  - `WlrLayershell.layer: WlrLayer.Top`，未使用 Overlay layer。
  - `exclusiveZone: 0`，`visible: true` 默认保持 mapped。
  - 输入 `mask` 只覆盖当前胶囊矩形，透明全宽 layer 不接收其他顶部输入。
  - overlay 使用黑色高对比胶囊，不随 light mode 变成白色。
  - 去掉 resting/expanded 胶囊底部的装饰性 1px 线。
  - 修正 `progress < 0` 的隐藏逻辑，避免无 OSD progress 时仍显示 0% 空进度条。
  - resting 起步尺寸为 `140x38`；expanded summary 为 `360x132`；OSD/workspace/notification 基础尺寸按状态 morph。
  - 主胶囊 `x/y/width/height/radius` 使用 `400ms` `Easing.OutQuint`。
  - 使用 `TahoeGlass.regions` 声明胶囊玻璃区域。
- `tahoe-shell/components/DynamicIslandMotion.js`
  - 增加 overlay morph/color/content/progress 动画 token。
  - T03 对任务范围做最小扩展，原因是 roadmap 要求动画参数集中，不能散写在 overlay 子层。
- `tahoe-shell/shell.qml`
  - 在每个 screen 的 `Variants` 中实例化 `DynamicIslandOverlay`。
  - 传入 T02 的 `dynamicIsland` 服务和 `darkMode`。
- `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/`
  - `resting-overlay.png`
  - `expanded-summary-overlay.png`
  - `transient-osd-overlay.png`
- `tahoe-shell/docs/dynamic-island-research-roadmap-2026-06-23.md`
  - 标记 T03 完成并链接本验收记录。

`config/niri/tahoe-phase0.kdl` 未修改；T03 没有添加任何 `tahoe-dynamic-island` layer-open/layer-close 动画规则。

## 验证命令

```bash
git diff --check -- tahoe-shell/components/DynamicIslandOverlay.qml tahoe-shell/components/DynamicIslandMotion.js tahoe-shell/shell.qml
bash scripts/check-tahoe-glass-guardrails.sh
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/components/DynamicIslandOverlay.qml
timeout 10s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
rsync -a /home/wwt/niri/tahoe-shell/ /home/wwt/.config/quickshell/tahoe/
niri msg --json outputs
niri msg --json layers
pid=$(pgrep -n -x quickshell)
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandGetDebugSummary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowExpandedSummary
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandShowOsd Volume 0.42
/home/wwt/.local/bin/qs ipc --pid "$pid" call tahoe dynamicIslandReset
grim -g '0,0 2048x220' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/resting-overlay.png
grim -g '0,0 2048x220' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/expanded-summary-overlay.png
grim -g '0,0 2048x220' tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/transient-osd-overlay.png
```

结果：

- `git diff --check`：退出 0。
- `check-tahoe-glass-guardrails.sh`：退出 0，22 个 `PanelWindow` namespace、21 个 `TahoeGlassRegion` 检查通过。
- `qmllint`：退出 0；仍有 Quickshell 类型不可创建、`TahoeGlassRegion` 类型不完整和既有 unqualified warning。
- `quickshell` smoke：到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
- IPC：
  - `dynamicIslandGetDebugSummary`：`state=resting_time ... targetScreenName=eDP-2; expanded=false`
  - `dynamicIslandShowExpandedSummary`：返回 `expanded_summary`
  - `dynamicIslandShowOsd Volume 0.42`：返回 `transient_osd`
  - `dynamicIslandReset`：返回 `resting_time`

## 运行时 Layer 列表

`niri msg --json layers` 稳定结果：

```json
[
  {"namespace":"linux-wallpaperengine","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-wallpaper","output":"eDP-2","layer":"Background","keyboard_interactivity":"None"},
  {"namespace":"tahoe-topbar","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dynamic-island","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"},
  {"namespace":"tahoe-dock","output":"eDP-2","layer":"Top","keyboard_interactivity":"None"}
]
```

结论：`tahoe-dynamic-island` 已出现；layer 为 `Top`；`keyboard_interactivity` 为 `None`；overlay QML 中 `exclusiveZone: 0`，没有新增窗口预留区。

## 视觉检查

- Resting overlay 居中，显示黑色 `140x38` 胶囊，视觉上覆盖并接管 T01 topbar chip。
- Expanded summary 通过 IPC 触发后 morph 到 `360x132`，下伸覆盖窗口内容但不挤压窗口布局。
- OSD smoke 状态 morph 到短胶囊并显示进度条；短 OSD 状态隐藏 secondary 文本，避免 44px 高度内文字和 progress 重叠。
- 胶囊在当前浅色/复杂壁纸上可读，边框和阴影没有明显方角；resting/expanded 状态没有装饰性底部细线或空 progress 条。
- 顶部其他透明区域没有可见表面；输入 mask 源码只开放胶囊区域。
- 截图：
  - `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/resting-overlay.png`
  - `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/expanded-summary-overlay.png`
  - `tahoe-shell/docs/visual-baselines/2026-06-24-dynamic-island-t03/transient-osd-overlay.png`

## 已知问题

- T03 只实现基础层和 morph；通知内容、完整 OSD 语义、媒体展开 UI、左右滑动页面仍按 T04+ 串行实现。
- `qmllint` 仍报告 Quickshell 自定义类型和 `TahoeGlassRegion` 元数据相关 warning；退出码为 0，项目现有组件同类 warning 已存在。
- `rsync` 触发 live Quickshell 热重载的瞬间曾短暂出现默认 `quickshell` layer，1 秒后稳定 layer 列表只剩显式 `tahoe-*` namespace；源码 guardrail 确认没有 PanelWindow 缺失 namespace。
- live 启动日志仍有既有 `shell.qml[322]` font 只读属性警告、Dock magnification interceptor 警告和 portal app-id 警告；T03 未触碰对应代码。
