# T08-fix7 · 中心锚定波形（一劳永逸）· 验收记录

日期：2026-07-11

## 背景

反复回归：
1. 波形没了（HoverHandler / `mapToItem(PanelWindow)`）
2. 修好波形后图标被挤出玻璃
3. 为防挤出又扩 surface / 改 contentX → 整条抖动

根因是同一套错误模型：**布局槽位左对齐推挤 + 玻璃定宽裁切 + 指针坐标绑在动画几何上**。

## 一劳永逸模型

| 不变量 | 实现 |
| --- | --- |
| 槽位永不移动 | pinned / window 的 `x`/`width` 永远是 rest |
| 指针在 rest 空间 | `dockMouseX` = 节内 rest 坐标；图标用 `button.x + localX` |
| 波形相对光标扩张 | 先左打包余弦宽，再 `shift = cursor − packed(cursor)` |
| 视觉推挤 | 仅 `scale` + `Translate(pushX)`，不改 hit-target |
| 玻璃容纳溢出 | surface 左右长 `leftExtra/rightExtra`；`dockRestFrame` 右移 `leftExtra` 使 rest 图标屏幕位置不变 |
| 无反馈环 | 禁止 `mapToItem(growing surface)` / `mapToItem(PanelWindow)` / 每帧 contentX |
| 无裁切挤出 | 去掉 wave 路径上的 Flickable clip |

数学：`packed(cursor)+shift ≡ cursor`（光标下 rest 点屏幕坐标恒定）。

## 改动文件

- `Dock.qml`：重写 wave helpers + surface/rest frame + pinned/window 视觉 push
- `WindowButton.qml`：`pushX` 替代 slot 动画；指针报 rest-local x
- `test_motion_token_convergence.py`：断言新不变量

## 验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **90 passed** |
| 部署 + 重启 quickshell | Configuration Loaded；无 mapToItem TypeError / Binding loop / interceptor（见部署日志） |

## 手测

1. 横扫 pinned：余弦放大 + 邻图标推开，**左缘不挤出**。
2. 玻璃随波略变宽，**整条不抖**。
3. 窗口 icon-only 半区同样。
4. autohide / 标签 / 拖拽重排不回归。

## 部署

`rsync tahoe-shell → ~/.config/quickshell/tahoe` 并重启 shell。
