# T18-fix · Launchpad 分页手感 + 空白关闭 + 进出/启动动画 · 验收记录

日期：2026-07-11

## 问题（用户实机）

1. **分页过严**：左右滑必须拖到本页图标全部消失在边缘才翻页；露出一点图标就会被拉回。
2. **空白无法关闭**：点图标外空白不能关闭启动器。
3. **无进出动画**：进入/退出 Launchpad 像硬切。
4. **点图标启动无动画**：直接关层，无反馈。

根因：`3eb4e75` 撤回方向实验时，把 `ec60a78` 的**意图分页**（短拖/轻甩即提交）一并 revert，回退成 `Math.round(contentX/pageW)` 近邻 snap，阈值实际接近半页。

## 实现摘要

| 项 | 改动 |
| --- | --- |
| 分页 | 恢复 `finishPageGesture`：松手时用 **峰值速度** 或 **短位移**（8% 页宽 / ≥28px / flick≥80）提交 ±1 页；`cancelFlick` 后自管 snap |
| 空白关闭 | 根层 + 页内空隙 + 顶/底 chrome 条 `requestClose()`；搜索 pill / 图标 / 页点吞事件 |
| 进出场 | 显式 `layerProgress` 0→1 / 1→0（opacity + soft scale 0.985→1）；关闭时不再瞬间 `gridEnter=0` |
| 启动 | 图标 `launchPop` 放大 + 邻项淡化 → 再关层；reduced 即时 |
| Token | `Motion.js`：`launchpadPageCommit*`、`launchpadLayer*`、`launchpadLaunchPop*` |

**未改**：Apps 服务、IPC/`toggleLaunchpad`、搜索过滤、7×5、壁纸变焦链路、`compositorLayerAnimations: false`（§2.11）。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，148 passed**（+`test_empty_area_and_launch_motion`） |

## 红线自查

| § | 结论 |
| --- | --- |
| §2.11 QML 路径 | 保持；无 compositor 整层 scale |
| 玻璃 region 禁弹簧 | backdrop 全屏静态；layer soft scale 为内容 Item |
| 不破坏入口 | `open`/`closeRequested`/`launchApp`/Esc/键盘 保留 |
| Image sourceSize | ≤128 |

## 手测矩阵（设计覆盖）

- [ ] 短滑/轻甩左右各翻一页（不必拖满屏）
- [ ] 微小抖动不翻页
- [ ] 点图标间空白 / 顶栏搜索外 / 底栏页点外 → 关闭
- [ ] 点搜索 pill 聚焦，不关闭
- [ ] 打开：层淡入 + 网格 scale 入场；关闭：淡出
- [ ] 点图标：弹出再关；Esc 仍即时关
- [ ] reduced：无动画时长
- [ ] 多页 + 搜索过滤回第 0 页

## 审查结论

- 分页逻辑与 `ec60a78` 一致并补了空白关闭/进出/启动；无服务层改动。
- 页内 dismiss `MouseArea` 对横向拖动 `mouse.accepted = false`，避免抢 Flickable。
- 启动 pop 用独立 `transform: Scale`，不与 press `Behavior on scale` 冲突。
- 快速重开从当前 `layerProgress` 续播，避免闪断。

## 发现待办

- 动态壁纸仍无法 QML scale（T18 已知限制）
- 若实机仍觉得阈值偏高/偏低，只调 `launchpadPageCommitRatio` / `launchpadPageFlickVelocity`
