# T18 · Launchpad 全屏重构 · 验收记录

日期：2026-07-11

## 目标

全屏网格（自适应 7×5）+ backdrop；壁纸变焦 1→1.06 + 暗化 25%；距中心×6ms stagger（≤450ms）；横向分页 snap + OvershootBounds + 页点；方向键；删类别 chips。**保持 QML 动画路径**（§2.11）。不破坏启动/搜索/关闭入口。

## 实现摘要

| 项 | 改动 |
| --- | --- |
| 布局 | 居中 760×560 窗 → 全屏；`MaterialBackdrop` 全屏玻璃 region |
| 类别 chips | **删除**；`filteredLaunchpadApps(query, "all")` |
| 分页 | 水平 `Flickable` + `DragOverBounds` + snap；页点 |
| 键盘 | ←→↑↓ / PageUp/Down / Enter / Esc |
| Stagger | 距页中心距离 ×6ms；首屏 ≤40 项；总预算 450ms；`useSpring` 双分支 scale |
| 壁纸 | `Wallpaper.launchpadOpen` → scale 1.06 + dim 0.25，emphasized 400ms |
| 搜索过滤 | 保留；过滤后重排回第 0 页 |

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，136 passed**（+`test_launchpad_refactor.py`） |
| `categoryStrip` / categories 模型 | **无** |
| `compositorLayerAnimations: false` | **是**（QML 路径） |
| Motion tokens grid 7×5 / stagger budget | **是** |

## 红线自查

| § | 结论 |
| --- | --- |
| §2.11 Launchpad QML 路径 | 保持；无整层 compositor scale |
| 玻璃 region 禁弹簧 | backdrop 全屏静态 geometry；图标 scale 为内容层 |
| useSpring 门控 | 图标 scale 双分支 |
| 不加密服务 Timer | 未改 Apps 服务 |
| Image sourceSize ≤128 | 是 |

## 功能不回归

- Dock / TopBar `toggleLaunchpad`、IPC 开关
- 点外关闭、Esc、Enter 启动
- `appsService.launchApp` / `iconForApp` / `appLabel`
- 动态壁纸路径：zoom 仅作用于 static Image 层

## 手测矩阵（设计覆盖）

- 200+ 应用分页与滚动流畅度（实机记录帧感）
- 搜索过滤重排
- 壁纸变焦与 blur（xray false）无冲突
- reduced：无 stagger / 即时 wallpaper

## 发现待办

- 动态/外部壁纸引擎层无法由 QML scale（仅 static 变焦）— 记录为已知限制
- 首开大量异步图标加载可能仍有一帧尖峰（异步 + sourceSize 已约束）
