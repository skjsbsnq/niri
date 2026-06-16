# Tahoe Glass Guardrails

Phase 7 的目的不是继续调玻璃参数，而是防止 Tahoe shell 回到旧的 broad fallback 架构。

## 永久规则

- niri 配置不得重新添加 broad `namespace="^quickshell"` glass/shadow layer rule。
- niri 配置只允许使用明确的 Tahoe namespace rule，例如 `^tahoe-control-center$`。
- Tahoe `PanelWindow` 必须显式设置 `WlrLayershell.namespace: "tahoe-*"`。
- Tahoe 玻璃 UI 必须使用 `TahoeGlass.regions` 和 `TahoeGlassRegion`。
- 每个玻璃 region 的 item 必须声明 `tahoeGlassMaterial` 和 `tahoeGlassRadius`，并从 `components/TahoeGlass.js` 取共享 material/radius。
- Tahoe QML 组件不得直接调用 `BackgroundEffect` 或 `BackgroundEffect.blurRegion`。
- `BackgroundEffect.blurRegion` 只允许用于非 Tahoe client，或 Quickshell `TahoeGlass` 客户端内部的协议不可用 fallback。

## Review Checklist

- 新增 `PanelWindow` 时，确认 namespace 是唯一的 `tahoe-*` 名称，不是默认 `quickshell`。
- 新增可见玻璃区域时，确认存在 `TahoeGlass.regions`、`TahoeGlassRegion`、`material`、`radius`。
- 新增玻璃 item 时，确认 item 暴露 `tahoeGlassMaterial` 和 `tahoeGlassRadius`。
- 修改 niri layer rules 时，确认没有对 `^quickshell` 添加 shadow、background-effect 或 geometry-corner-radius。
- 修改 Dock、TopBar、Spotlight、Launchpad 时，确认大透明 `PanelWindow` 本身没有重新获得 layer-level glass/shadow。

## Automated Check

Run this before review or deployment:

```sh
bash scripts/check-tahoe-glass-guardrails.sh
```

`scripts/arch-update.sh` runs the same check by default before deployment. To skip it for a local emergency debug pass only:

```sh
RUN_TAHOE_GLASS_GUARDRAILS=false bash scripts/arch-update.sh
```
