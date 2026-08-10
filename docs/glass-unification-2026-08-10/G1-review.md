# G1 审查记录 —— 玻璃令牌统一

日期：2026-08-10
子代理数：2（另 G0 阶段 2 个，共 4 个）

## 背景

用户诉求：「将模糊透明之类的统一成 niri 菜单那一种效果」，并明确
「我能接受这个性能开销」。

G1 范围：仅 QML 令牌统一（零性能代价部分）。着色器尺寸门改动属 G2，
配置与回退块同步属 G3。

## 改动

10 个玻璃表面 material → `MaterialMenu`，radius → `RadiusMenu`
（Launchpad 保持 `RadiusBackdrop`=0，因其为全屏面）：

| 表面 | 原 material | 原 radius | 原 fill |
|---|---|---|---|
| ControlCenter | panel | 28 | FillPanel(0.200) |
| WifiPopup / BatteryPopup / FanPopup / ClipboardPopup | panel | 24 | FillPanelBright |
| NotificationCenter | panel | 28 | FillPanelBright |
| Spotlight | panel | 18(Compact) | FillPanelBright |
| WindowOverview | panel | 28 | FillPanelBright |
| Dock | dock | 24 | FillDock(0.149) |
| Launchpad | backdrop | 0 | FillBackdrop |

ControlCenter 与 Dock 的**浅色**分支 fill/stroke → `FillPanelBright`/`StrokePanelBright`；
深色分支按用户决策保持原样未动。

未改：DynamicIslandOverlay（pill，有意近不透明板）、NotificationToast（toast）、
LeftSidebar / SettingsPanel（自绘不透明板，治理豁免名单内）。

## 自查发现并已修的问题

**Launchpad 丢失 `shadow off`**：backdrop 材质在合成器侧默认 `shadow.on=false`
（`niri-config/src/tahoe_glass.rs:197`），menu 材质则为 true。若只换 material，
全屏面会获得一圈投影。已在 `Launchpad.qml:341` 显式 `shadow: false` 补回，
并在 `test_launchpad_refactor.py` 中加断言固化。

**圆角几何核算**：外壳 radius 28→18 后，内部卡片（radius 22，margin 14）
是否越界？按对角线精确计算：外壳内边界沿对角距角 7.46px，子卡最近点距角
28.91px，余量 +21.46px（改前为 +17.31px）。**缩小外壳圆角反而增大了余量**，
无出角风险。

## 完成判据核对

| 判据 | 是否满足 | 证据 |
|---|---|---|
| 全部 QML 结构测试通过 | 是 | `pytest tests/ -q` → 1023 passed, 287 subtests |
| 玻璃守护脚本通过 | 是 | `check-tahoe-glass-guardrails.sh` → passed（21 files, 7 regions, 24 namespaces） |
| qmllint 无新增错误 | 是 | 10 个改动文件仅余既有 import/unqualified 告警 |
| 治理表如实反映现状 | 是 | 两张表逐文件重写，非放宽断言 |

## 已知遗留（**不在 G1 范围，转 G2/G3**）

1. **大面 detail 仍为 0**：Dock(1518×84)、WindowOverview(1080×720)、
   Launchpad(全屏) 在着色器 `glass_surface_detail()` 下 detail=0，
   edge_highlight/inner_shadow/refraction 仍被压制。
   **G1 对这些面只改变了 tint/saturation/fill，未获得完整菜单质感。**
   这正是 G2 要解决的问题 —— 用户已同意为此付出性能开销。
2. **layer-rule 回退块未同步**：`config/niri/tahoe-phase0.kdl` 的
   `background-effect` 回退块（:388-401、:671-684 等）仍抄写 panel 数值，
   `geometry-corner-radius` 仍为 28/24（与新的 18 不符）。
   仅在私有协议失效时暴露。**转 G3 统一处理。**
3. **死令牌**：`MaterialDock`/`MaterialBackdrop`/`FillDock`/`FillBackdrop`/
   `RadiusDock`/`RadiusPopup`/`RadiusPanelCompact` 现已无生产使用者。
   合成器侧 material 词表仍需保留 dock/backdrop（配置与回退块引用），
   QML 侧令牌是否删除待 G3 决定。

## 最终结论

自查与几何核算通过，全量测试绿。遗留项均已明确归属后续任务，非本次缺陷。
