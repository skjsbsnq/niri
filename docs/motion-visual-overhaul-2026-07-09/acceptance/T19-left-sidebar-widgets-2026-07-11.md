# T19 · 左侧边栏 widget 化重构 · 验收记录

日期：2026-07-11

## 目标

去 chrome；天气状态渐变小组件；系统活动圆环 + top3 进程默认收起；卡片去描边改阴影；入场 stagger 30ms。**ProcessMenu 链路（shell.qml）不动**。系统刷新频率不加密。

## 实现摘要

| 项 | 改动 |
| --- | --- |
| 外壳 | 删标题「左侧边栏」与关闭钮；顶部小分段 `segmentBar` |
| 天气 | `heroGradientColors` 按 WeatherCodes slug（晴/雨/夜/雾…）；大温度 **非等宽** 52px；逐时内嵌；日预报渐变温度条；无 `border.width` |
| 系统 | `ActivityRing` CPU/内存/GPU；进程默认 top3，`展开全部` 保留过滤/排序/右键菜单 |
| 卡片 | SoftCard/WidgetCard：填充 + 软阴影板，无 1px 描边；stagger 30ms springSmooth 双分支（显式 Spring/NumberAnimation） |
| ProcessMenu | `openProcessMenuRequested` / `prepareProcessMenu` / ProcessMenu + PopupDismissLayer **未改语义** |

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，142 passed**（+`test_left_sidebar_widgets.py`） |
| quickshell `-p tahoe-shell` 冒烟 | **加载成功**（无 LeftSidebar Type unavailable） |
| SystemStats `sleep 1` / medium tick%2 / slow tick%5 | **未改** |
| `border.width: 1` in Weather/System | **无** |
| 标题「左侧边栏」/ closeMouse | **无** |

## 红线自查

| § | 结论 |
| --- | --- |
| 玻璃 region 禁弹簧 | 面板 slide 仍为 NumberAnimation；卡片 y 为内容层 |
| useSpring 门控 | segment / SoftCard / WidgetCard 显式双分支 |
| 不加密服务 Timer | SystemStats 脚本与 restart 2s 未动 |
| ProcessMenu 链路 | shell 段保留 |
| 无 QtQuick.Controls | 是 |

## 审查 follow-up（同会话）

| 问题 | 处置 |
| --- | --- |
| `ScriptModel is not a type`（System） | 改 JS 数组 `visibleProcessList` model |
| 双 `Behavior on y/scale` interceptor 警告 | SoftCard/WidgetCard/Spotlight 高亮/Launchpad 图标改为 **单 Behavior + 显式 SpringAnimation**（Dock 范式） |

## 功能不回归

- IPC `toggleLeftSidebar` / Esc 关闭
- 天气 refresh / 打开设置天气页
- 进程右键 → ProcessMenu；菜单打开时暂停列表刷新（`processMenuOpen`）
- 深浅色 token 走 SettingsTheme

## 手测矩阵（设计覆盖）

- 天气：晴/雨/夜/错误/缓存视觉
- 系统：圆环数值、展开进程、右键菜单
- 卡片入场 stagger；reduced 即时

## 发现待办

- 运行中的 `~/.config/quickshell/tahoe` 需同步/重载才能吃到仓库改动
- StartupPage `addCandidateRow` 预存 WARN（非本任务）
- 系统页去掉双弧仪表与完整折线 Tab 后，Net 仅保留迷你双线（信息密度下降，符合 widget 方向）
