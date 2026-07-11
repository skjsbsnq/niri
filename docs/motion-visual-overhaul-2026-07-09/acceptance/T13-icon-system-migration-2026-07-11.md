# T13 · 图标体系迁移 · 验收记录

日期：2026-07-11

## 目标

撤换全 shell Material Icons 字体字形，改为预渲染 PNG 符号集 + `TahoeSymbol.qml` 统一出口。

## 实现摘要

| 项 | 内容 |
| --- | --- |
| 资产 | `tahoe-shell/assets/icons/symbols/` 新增 **155** 个白色 @2x PNG（128×128，由 Material Icons Round 预渲染）+ 保留既有 6 个多色 Shortcut 符号 |
| 注册表 | `TahoeSymbols.js`：codepoint → 语义名 → 文件名；`resolveName` / `fileName` |
| 组件 | `TahoeSymbol.qml`：name/source 解析、`ColorOverlay` 着色、`sourceSize ≤128`、`asynchronous`、可选 `appsService.iconPath("symbols", …)` |
| 迁移面 | TopBar、菜单（MenuRow 等）、CC、侧边栏、设置控件/页、Launchpad/Spotlight、灵动岛、通知、MeteoIcon 等 |
| 移除 | `shell.qml` FontLoader；`assets/fonts/MaterialIconsRound.ttf`；全部 `iconFont` / `fallbackIconFamily` 属性 |

### 兼容策略

调用点仍可传遗留 Material 私用区码点字符串（如 `"\ue63e"`）；`TahoeSymbols.CodepointToName` 在运行时解析为 PNG。设置页 `SettingsModel.icon` 等字段无需本任务改语义名。

### 功能保留

- 菜单图标 / 勾选 / 子菜单 chevron
- TopBar 状态钮、CC 磁贴/媒体控件、侧边栏 Tab/天气
- 设置侧栏搜索清除钮（MouseArea 保留）
- CC 媒体 prev/next 按下缩放 + MouseArea
- MeteoIcon / WeatherCodes 映射仍工作（码点→PNG）
- Spotlight 多色 shortcut 符号路径不变（`iconPath("symbols", …)`）

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，103 passed**（+6 T13 治理） |
| `rg -n 'Material Icons\|MaterialIcons\|iconFont\|FontLoader' tahoe-shell --glob '!docs/**' --glob '!tests/**'` | 仅 `TahoeSymbols.js` 注释提及源字体；**无运行时引用** |
| 花括号平衡全 `*.qml` | OK |
| MouseArea 计数（相对 HEAD 迁移前） | ControlCenter 13、SettingsSidebar 1，与修复后一致 |

### 治理测试

`tests/test_tahoe_symbol_migration.py`：

- 无 Material Icons / iconFont 运行时残留
- FontLoader + TTF 已移除
- TahoeSymbol 含 ColorOverlay / sourceSize / iconPath
- ≥150 PNG + 关键符号存在
- 组件层 TahoeSymbol 引用 ≥40

## 手测矩阵（代码路径自检；实机 reload 见待办）

| 项 | 结果 |
| --- | --- |
| 深/浅色着色（ColorOverlay） | 组件均传 `color` token |
| reduced / useSpring | 未改动效门控 |
| Esc / 点外关闭 / IPC | 未改 shell 函数与弹窗协调 |
| 图标内存 | sourceSize clamp ≤128 |

## 发现待办

- 实机 reload 后目测全 shell 图标与深浅色。
- 部分符号仍为 Material 轮廓预渲染（非 SF Symbols 官方形），观感可在后续用 SF 风格开源集替换同名 PNG 而不改调用点。
- T14：颜色语义化 + accent。
