# T20 · 任务切换器 / 窗口概览手感 · 验收记录

日期：2026-07-11

## 目标

- TaskSwitcher：即时出现（去入场缩放），选中框在图标间弹簧平移。
- WindowOverview：缩略图从近似窗口位置向网格位弹簧飞行，关闭反向；无常驻克隆层。
- 不破坏既有 IPC / 激活 / 缩略图 / 键盘 / 点外关闭。

## 实现摘要

| 项 | 改动 |
| --- | --- |
| TaskSwitcher 入场 | 去掉 `scale` + opacity Behavior；`visible`/`opacity` 与 `open` 同步即时出现 |
| TaskSwitcher 选中 | 独立 `selectionHighlight`（content 坐标 `contentX`），`springSnappy` / eased 双分支；相对 ListView `contentX` 跟随滚动 |
| WindowOverview 入场 | 去掉面板 scale settle；卡片 `Translate`+`Scale` 从 `flightOffsetForCard(geometry)` 弹簧到 (0,0) |
| WindowOverview 关闭 | `flightPhase=leaving`，反向弹簧飞回窗口近似位；`leaveWatchdog` 480ms 硬收尾 |
| 克隆层 | **未**使用 `createObject` 独立克隆；在卡片自身 transform 上飞，结束 `snapHome`/`snapAway` + `stopFlightAnims`（§4.4） |
| useSpring | `TaskSwitcher`/`WindowOverview` 新增 `useSpring`；`shell.qml` 转发 `shell.useSpring` |
| 玻璃 region | 仍为固定面板 rect，**无**弹簧驱动 region 几何 |

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，146 passed**（+`test_task_overview_motion.py` 3） |
| `test_thumbnail_provider_contract.py` | **PASS**（两组件仍走 ThumbnailProvider + WindowPreviewFallback） |
| quickshell `-p tahoe-shell` 冒烟 | **Configuration Loaded**；无 TaskSwitcher/WindowOverview 错误（StartupPage `addCandidateRow` 预存 WARN） |

## RSS 阶段检查点（阶段 D 末 / T20）

| 进程 | RSS (kB) | 对照 |
| --- | --- | --- |
| quickshell | 584840 | 会话内与 T20 前 ~584804 持平（运行中进程未强制重载仓库树） |
| niri | 177468 | 正常波动 |

相对 T00 基线：若 live shell 未同步仓库，RSS 不代表本任务 diff 引入；本任务无常驻新 surface / 无 createObject 克隆池。

## 红线自查

| § | 结论 |
| --- | --- |
| 玻璃 region 禁弹簧 | region 仍静态绑定 panel 几何；飞行只动卡片 transform |
| useSpring 门控 | highlight / flight 均为 spring 与 NumberAnimation 双分支 |
| 不破坏入口 | IPC `open/cycle/confirm/close TaskSwitcher`、`open/toggle/close WindowOverview` 未改签名 |
| 克隆用完即毁 | 无独立克隆 Item；transform 复位 + destruction 停动画 |
| 不引入 QtQuick.Controls | 是 |

## 功能不回归（设计覆盖）

- Tab/方向键循环、Enter 激活、Esc/点外关闭
- 修饰键释放确认（keyboardMode + release timer）
- 最小化窗口 restore / 普通 activate
- 工作区分组、缩略图失败 fallback
- reduced / `useSpring=false`：飞行与选中框 snap 或短 easing

## 手测矩阵（设计覆盖）

- Mod+Ctrl+Tab 连击切换选中框弹簧跟手
- 概览开/关 10 次：无残留 transform、无卡在 leaving
- 多窗口 / 无 geometry / 最小化：fallback 上升位移
- 深浅色：未改材质常量语义

## 审查结论

实现覆盖 roadmap T20 清单；pytest 与冒烟通过；IPC 与缩略图契约保留。建议 live 会话同步 `~/.config/quickshell/tahoe` 后手测飞行起点与选中框滚动对齐。

## 发现待办

- 运行中的 `~/.config/quickshell/tahoe` 需同步/重载才能吃到仓库改动
- `flightOffsetForCard` 将 geometry 视为与 overview 同屏输出坐标；多输出时偏移可能偏差（仍钳制在 screen 范围）
- StartupPage `addCandidateRow` 预存 WARN（非本任务）
