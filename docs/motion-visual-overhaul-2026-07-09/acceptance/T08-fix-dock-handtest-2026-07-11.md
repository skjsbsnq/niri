# T08-fix · Dock 手测四问题修复 · 验收记录

日期：2026-07-11

## 背景

T08 落地后实机手测发现 4 个问题（T07/T08 引入或暴露）：

1. **图标太大** — T07 将基准 46→56 + peak 1.7，视觉过重。
2. **autohide 下滑过程中模糊突然丢失** — 变成纯半透明填充。
3. **鼠标滑过时左侧图标被挤出** — 推挤向右堆叠 + 定宽 viewport 裁切。
4. **隐藏后底部残留一条边** — slide 距离 88 < 表面高度 96。

## 根因

| # | 根因 |
| --- | --- |
| 1 | `dockIconSize=56` / `dockMagPeak=1.7` 偏大；槽位/表面随之膨胀。 |
| 2 | `onDockHiddenChanged` 在 hide 瞬间 `dockGlassActive=false`，`glassEnabled` 立刻关，region 模糊在 slide 中途就卸掉，只剩 `fillColor` 半透明。 |
| 3 | 有窗口半区时 `pinnedDisplayedWidth` 锁死 rest 预算，wave 加宽被 Flickable `clip:true` 裁掉；`dockSurface` 水平居中，左侧膨胀会把左缘图标推出玻璃。 |
| 4 | T07 表面高度 96，`dockAutohideSlidePx` 仍 88 → 完全收起后仍露 ~8px。 |

## 改动

### 1. 图标与峰值回落（`Motion.js` + `Dock.qml` + `WindowButton.qml`）

| token / 属性 | T07/T08 | T08-fix |
| --- | --- | --- |
| `dockMagPeak` | 1.7 | **1.55** |
| `dockIconSize` | 56 | **48** |
| `dockPinnedButtonWidth` | 72 | **64** |
| `dockWindowIconWidth` | 68 | **60** |
| `dockToolButtonWidth` | 64 | **56** |
| tool 图标 | 48 | **40** |
| `dockSurfaceHeight` | 96 | **84** |
| `dockPinnedRowHeight` | 78 | **70** |
| `dockWindowRowHeight` | 64 | **60** |
| `exclusiveZone` | 112 | **100** |
| `implicitHeight` | 150 | **140** |
| `dockLiftFactor` | 16 | **14** |

余弦钟形公式不变，仍走 `Motion.dockCosineScale`。

### 2. 下滑全程保持模糊（`Dock.qml`）

- hide 时**不再**立刻 `dockGlassActive=false`，只置 `dockVisualHidden=true` 开 slide。
- 新增 `onDockVisibleHeightChanged`：`visibleHeight > 0.5` 时强制 glass 开；**仅当** fully hidden 且 height ≤ 0.5 才关 glass。
- `glassEnabled` 阈值 `0.001` → `0.5`（避免最后 1px 抖开关）。

玻璃 region 几何仍只跟 `dockVisibleHeight` 裁剪，弹簧只驱动 content `Translate.y`（§2.1 合规）。

### 3. 推挤不再挤出左缘图标（`Dock.qml`）

- **有窗口半区时 wave 也扩展 pinned viewport**（在 flexible budget 内），不再锁死 rest 宽。
- `pinnedWaveLeftExtra()` / `dockWaveSurfaceBias()`：按光标左侧额外宽度偏置 surface `x`，使波形相对光标扩张，而非相对面板中点对称扩张。
- `dockSurface` 由 `anchors.horizontalCenter` 改为显式 `x`（带外缘 clamp）。
- `syncPinnedViewportToCursor()`：wave 溢出 viewport 时把 contentX 跟到光标；hover 离开归零。
- pinned Flickable 仅在 `contentWidth > width` 时 `clip`，否则让边缘图标画进 surface padding。

### 4. 完全隐藏（`Dock.qml`）

```
dockSlideDistance = max(Motion.dockAutohideSlidePx, dockSurfaceHeight)
dockSlideTarget   = dockVisualHidden ? dockSlideDistance : 0
```

表面 84、token 88 → 实际 slide 88 ≥ 高度，底部无残留。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，90 passed** |
| quickshell 冒烟（`timeout 15s qs -p tahoe-shell`） | PASS，`Configuration Loaded`；**Binding loop=0**；**interceptor=0**；无 Dock/WindowButton QML 错误 |
| 基线警告 | `shell.qml:479` font TypeError；`StartupPage.qml:358` addCandidateRow（既有，非本 fix） |

### 机械验证

```
rg -n 'dockIconSize: 48|dockMagPeak = 1.55|dockSlideDistance|pinnedWaveLeftExtra|onDockVisibleHeightChanged' \
  tahoe-shell/components/{Dock,Motion}.js* tahoe-shell/components/Dock.qml
→ 命中

rg -n 'dockGlassActive = false;\n            dockVisualHidden' tahoe-shell/components/Dock.qml
→ 无匹配（hide 路径不再立刻关 glass）
```

## 红线自查

- 玻璃 region 几何未弹簧 ✓
- `useSpring` 双分支保留 ✓
- 未新建 token 文件 / 未直写 KDL / 未动 quickshell C++ ✓
- 治理测试同提交更新 ✓

## 手测清单（请用户确认）

1. 图标尺寸目测合适（≈48，peak ~1.55）。
2. autohide 收起全程有模糊，无“突然变纯透明”。
3. 光标从左扫到右：左缘图标不挤出玻璃；surface 随波略偏。
4. 完全隐藏后屏幕底无残留条。

## 发现待办

- 部署副本 `~/.config/quickshell/tahoe` 需同步/重启 shell 才能看到本 fix。
- 窗口半区仍为 Row 定宽槽（仅 scale，无解析式推挤）——与 T07 待办一致，未在本 fix 扩展。

## 结论

四项手测问题均在源码层修复，治理测试与冒烟通过；可作为 `T08-fix:` 单独提交回滚。
