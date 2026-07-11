# T08-fix4 · Dock 波形抖动 + autohide 唤起慢 · 验收记录

日期：2026-07-11

## 背景

用户反馈：
1. 鼠标划过时整条 Dock **不停缩放抖动**；
2. autohide 后鼠标放到边缘要 **等很久** 才上来。

## 根因

### 1. 整条抖动（反馈环）

T08-fix / fix2 为了「不挤出左缘图标」引入了：
- 波形实时扩展 **section viewport / surface 宽度**；
- `dockWaveSurfaceBias` **每帧移动 surface.x**；
- `sync*ViewportToCursor` 每帧改 contentX；
- `dockMouseX` 存的是 **surface 本地坐标**（由动画中的 delegate `mapToItem(dockSurface)` 得到）。

链条：`dockMouseX → wave → width/x 动画 → mapToItem 结果变 → dockMouseX 变 → wave…`  
整条玻璃条跟着缩放/平移，肉眼就是「不停抖」。

### 2. 唤起慢

`markDockHovered()` 在 reveal 区 `positionChanged` 上每次都 `dockRevealDebounceTimer.restart()`（150ms）。  
鼠标在底边一动，计时器永远重新计时，感觉像卡住。

## 改动

| 项 | 处理 |
| --- | --- |
| section / surface 宽度 | 固定为 **rest** 尺寸；波形只在 Flickable **内部** 推挤图标 |
| surface.x | 恢复 `anchors.horizontalCenter`；`dockWaveSurfaceBias()` 恒为 0 |
| contentX 跟光标 | 去掉每帧 sync（空函数保留符号）；hover 离开仍 contentX=0 |
| dockMouseX | 改为 **root（PanelWindow）坐标**；`pinnedCursorX`/`windowCursorX` 用 viewport→root |
| 指针映射 | pinned / surface / tool / WindowButton / minimized 统一 `mapToItem(root)` |
| reveal debounce | 仅在 **未 running** 时 `start()`，禁止 move 时 `restart`；间隔 150→**40ms** |

解析式推挤（pinned + 窗口 icon-only 的 x/width）保留。底部放大（fix3）保留。

## 验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **90 passed** |
| quickshell 冒烟 | Configuration Loaded；Binding loop=0；interceptor=0 |

## 手测

1. 快速横扫 Dock：玻璃条宽度/位置稳定，图标波形平滑，无整条缩放抖。
2. autohide 开：指针触底边约 40ms 内开始升起（再加 spring 动画），不再「一直不动」。
3. 窗口半区推挤、底部放大不回归。

## 部署

必须 rsync `tahoe-shell` → `~/.config/quickshell/tahoe` 并重启 shell。

## 结论

反馈环与 reveal 死重启已断；可 `git revert` 单独回滚。
