# T08-fix6 · Dock 波形跟踪恢复 · 验收记录

日期：2026-07-11

## 背景

用户反馈：鼠标在 Dock 图标上划过时，**放大/推挤波动动效完全没有了**（多次 fix 后回归）。

## 根因（两层）

### A. fix5 过度收敛到 HoverHandler

T08-fix5 把波形位置**完全**交给 `HoverHandler.point`，并删掉 pinned/tool 上 `updateDockHoverFromItem`。子 `MouseArea` 下 `HandlerPoint` 常不更新 → 即使 hover 为真也无 wave。

### B. fix4 坐标空间错误（冒烟日志确认）

`mapToItem(root)` / `mapToItem(dockWindow)` 目标是 **PanelWindow**，不是 `QQuickItem`：

```
Could not convert argument 0 from Dock_QMLTYPE_* to const QQuickItem*
TypeError: Passing incompatible arguments to C++ functions from JavaScript is not allowed.
```

`dockMouseX` 从未被正确写入 → 波形恒为 1。这是「修了好几次仍无动效」的硬根因。

## 改动

| 项 | 处理 |
| --- | --- |
| hide 所有权 | **仍**由 `dockSurfaceHover` 负责；子项 `onExited` **只清标签**（保留 fix5） |
| 波形驱动 | 恢复 surface `MouseArea`（NoButton）+ pinned/tool/window 的 position 更新 |
| 坐标空间 | `dockMouseX` / cursor 映射目标改为 **`dockSurface`（真实 Item）**；禁止 `mapToItem(PanelWindow)` |
| WindowButton / minimized | `mapToItem(dockSurfaceItem)` 替代 `mapToItem(dockWindow)` |
| surface 稳定 | 仍 rest 宽 + horizontalCenter（fix4），避免 surface-local 再引入抖动环 |

## 验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **90 passed** |
| quickshell 冒烟（`timeout 12s qs -p tahoe-shell`） | Configuration Loaded；`Could not convert … Dock … QQuickItem` = **0**；Binding loop / interceptor 无新增 |

## 手测

1. 慢/快横扫 pinned：余弦放大 + 邻图标推挤连续。
2. 图标间距上：Dock 不收起（HoverHandler 仍覆盖）。
3. 真正离开玻璃：宽限后 hide。
4. 窗口 icon-only 半区：同样有波形。

## 部署

必须同步 `tahoe-shell` → `~/.config/quickshell/tahoe` 并重启 shell。

## 结论

可 `git revert` 单独回滚。
