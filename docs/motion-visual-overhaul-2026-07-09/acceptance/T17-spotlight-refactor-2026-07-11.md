# T17 · Spotlight 重构 · 验收记录

日期：2026-07-11

## 目标

单面板 Spotlight：搜索行 + 结果同一玻璃；高度 250ms emphasized；↑↓ 键盘选中 + 高亮胶囊 y 弹簧；分组标题；右侧预览 220px 交叉淡化；删输入框内快捷按钮。**不破坏** 既有 IPC / Search 服务 / 点外关闭。

## 实现摘要

| 项 | 改动 |
| --- | --- |
| 单面板 | 两块 `GlassPanel` → 一块；`TahoeGlass.regions` 仅 `panelSurface` |
| 高度 | `targetPanelHeight` 随结果体变化；`Behavior on height` = `NumberAnimation` + emphasized（**无弹簧**） |
| 键盘 | `Keys.onUp/Down/Tab/Backtab` + Enter 激活选中项 |
| 高亮胶囊 | `selectionHighlight` y 弹簧（`useSpring` 双分支） |
| 分组 | `buildSections` / `groupTitleForProvider` 按 provider |
| 预览 | 右侧 220px；`previewEpoch` 触发 150ms 交叉淡化 |
| 快捷按钮 | 已删（`launchShortcut` 函数保留兼容） |
| 主题 | `SettingsTheme` label/accent；`darkMode` + `useSpring` 由 shell 注入 |

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，131 passed**（+`test_spotlight_refactor.py`） |
| Motion tokens `spotlightHeightMs=250` / preview 150 / width 220 | **是** |
| `GlassPanel {` 计数 = 1 | **是** |
| `shortcutRow` / 快捷符号 PNG | **无** |

## 红线自查

| § | 结论 |
| --- | --- |
| 玻璃 region 禁弹簧 | height 仅 NumberAnimation/emphasized |
| useSpring 门控 | 高亮 y 双分支 Spring / NumberAnimation |
| 不新建 token 文件 | 扩展 `Motion.js` |
| 不破坏 IPC | `openSpotlight` / toggle / close 未改 |
| 无 QtQuick.Controls | 是 |

## 功能不回归

- `Search.resultsForQuery` / `activateResult` 链路不变
- 点外 `MouseArea` 关闭、Esc 关闭
- compositor layer 与 QML fallback opacity/scale 路径保留
- reduced：高度/预览淡化 duration 0

## 手测矩阵（设计覆盖 / 实机待确认）

- 输入 → ↑↓ → Enter；空结果；单结果
- 高度变化时无 niri region 拒绝日志
- 深浅色；reduced profile

## 发现待办

- 实机：预览栏在极窄屏幕上的宽度压缩（当前 min 面板 760 宽）
- 分组标题顺序跟随 provider 首次出现序（非固定 macOS 序）— 可接受
