# Liquid Glass T9 Persistent Panel Glass Route

日期：2026-06-29

## 状态

T9 已完成。常驻和高密度面板保持 compositor-owned region 模型，但默认材质交互态从“长期增强”收敛为 at-rest；Dock hover 只驱动 `interaction`，不改变 region 几何。

## 本轮决策

- `GlassPanel.qml` 的默认 `interaction` 改为 `0`，与 TahoeGlass 协议语义一致：`0` 是静止态，`1` 才是 hover/active 增强态。
- `TopBar.qml` 继续只给内部 `barSurface` 建 region，不把 full-width layer surface 变成玻璃。
- `Dock.qml` 保留 visible-height 裁剪：auto-hide 滑入时 region height 只覆盖屏幕内可见部分，避免 niri reject 越界 region。
- Dock hover/reveal 通过 `dockGlassInteraction` 驱动材质强度，region `x/y/width/height` 仍由已有 bounded `NumberAnimation` 和 visible-height 计算控制。
- `ControlCenter.qml`、`NotificationCenter.qml`、`LeftSidebar.qml`、`SettingsPanel.qml`、`WindowOverview.qml` 使用 `panel` material 的 at-rest interaction，优先保证文字与缩略图可读。
- `SettingsPanel.qml` 和 `WindowOverview.qml` 不再把淡入 opacity 当作 `interaction`；opacity 只继续驱动 `materialAlpha`。

## 本轮改动

- `tahoe-shell/components/GlassPanel.qml`
  - 默认 `interaction` 从 `1` 改为 `0`。
- `tahoe-shell/components/TopBar.qml`
  - `barSurface` 显式 `interaction: 0.0`，保持 `RadiusTopBar` 和内部 region。
- `tahoe-shell/components/Dock.qml`
  - 新增 `dockGlassInteraction: dockHovered ? dockVisibleAmount : 0.0`。
  - `dockSurface.region` 仍使用 `regionY = root.height - root.dockVisibleHeight`、`regionHeight = root.dockVisibleHeight`。
- `tahoe-shell/components/ControlCenter.qml`
- `tahoe-shell/components/NotificationCenter.qml`
- `tahoe-shell/components/LeftSidebar.qml`
  - 面板 region 显式保持 `interaction: 0.0`。
- `tahoe-shell/components/SettingsPanel.qml`
- `tahoe-shell/components/WindowOverview.qml`
  - `interaction` 固定为 `0.0`，`materialAlpha` 仍跟随 panel/overview opacity。
- `config/niri/tahoe-phase0.kdl`
  - `panel` material 增加 tint/contrast，降低 edge/refraction/inner-shadow，并关闭 lens-depth。
  - 同步 `tahoe-control-center` / `tahoe-notification-center` / `tahoe-left-sidebar` fallback block。
  - 同步小 popup fallback block，保持 fallback 和 `panel` material 接近。

## 保留的不变量

- 不改 TahoeGlass Wayland 协议。
- 不新增 material 名称。
- 不新增 raw shader 参数。
- 不新增直接 `BackgroundEffect.blurRegion` 调用。
- TopBar 和 Dock 仍只声明内部可见玻璃 region。
- WindowOverview 仍只有一个 outer panel glass region；窗口缩略图没有拆成 per-window glass region。
- `chromatic` 仍为 `0.0`，文字密集面板不引入彩边。

## 验证

已通过：

```sh
bash scripts/check-tahoe-glass-guardrails.sh
./niri/target/debug/niri validate -c config/niri/tahoe-phase0.kdl
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
cargo test -p niri-config tahoe_glass --quiet
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules tahoe-shell/components/GlassPanel.qml tahoe-shell/components/TopBar.qml tahoe-shell/components/Dock.qml tahoe-shell/components/ControlCenter.qml tahoe-shell/components/NotificationCenter.qml tahoe-shell/components/LeftSidebar.qml tahoe-shell/components/SettingsPanel.qml tahoe-shell/components/WindowOverview.qml
```

`qmllint` 退出码为 `0`；输出仍包含既有 qmltypes 限制导致的 `PanelWindow` / `TahoeGlass` unresolved warnings，以及旧有 unqualified/modelData warnings。

本轮未做 live 截图验收：当前运行的 Tahoe shell 使用 `/home/wwt/.config/quickshell/tahoe`，当前运行的 niri 配置为 `/home/wwt/.config/niri/tahoe/config.kdl`；两者都不是仓库路径，并且部署端 niri config 明显旧于仓库配置。为避免覆盖用户当前会话配置，未把仓库状态同步到 live session。TopBar/Dock/ControlCenter/Settings/Overview 的截图和帧率观察应在 T13 视觉基线流程中补采。
