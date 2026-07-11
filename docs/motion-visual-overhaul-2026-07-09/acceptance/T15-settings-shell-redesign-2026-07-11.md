# T15 · 设置外壳重设计 · 验收记录

日期：2026-07-11

## 目标

设置外壳 macOS System Settings 化：内容区近不透明、侧栏加宽 + 彩色方块图标 + 选中 accent 胶囊、页面切换双页过渡动画、子页返回箭头。**不破坏**既有 36 页可达性、搜索过滤、服务绑定与关闭路径。

## 实现摘要

| 项 | 落地 |
| --- | --- |
| 内容区不透明 | `SettingsTheme.panelFill` → `#eb…`（α≈0.92）深/浅 |
| 侧栏宽度 | `SettingsSidebar` 210 → **230** |
| 彩色圆角方块 | `TahoeSidebarButton` 使用 `TahoeCategoryIcon` + `categoryColor(id)` |
| 选中态 | 实心 `accentBlue` 胶囊 + 白字（非半透明灰底） |
| 页面切换 | `StackLayout` → `pageHost` 双页层；新页 +24px 滑入淡入、旧页 -12px 视差淡出；**280ms** `emphasizedDecel` |
| 连点无竞态 | `navigateTo` 中断在途动画并 retarget；`snapTo` 开面板无动画 |
| 子页返回 | `SettingsModel.parentId` → 标题栏返回 chevron + `goBack()` |
| 玻璃红线 | 只动内容 `x/opacity`，**不**动 `GlassPanel` region 几何；无 `SpringAnimation` |

`categoryColor` 补全侧栏主 id（wifi/network/…/system 等），概览/Niri 子色保留。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，126 passed**（含 `test_settings_shell_redesign.py`） |
| 36 页 `layerX("…")` 与 `SettingsModel.panels` 对齐 | **36/36** |
| `StackLayout` 残留 | **无** |
| `pageHost` 内 `SpringAnimation` | **无** |

## 功能不回归（设计保证）

- 全部页面实例常驻（与原 StackLayout 相同），仅可见性/透明度切换 → 表单状态、滚动位置不因卸载丢失
- `openPage` / `selectedPage` / IPC 打开设置页路径不变
- 搜索 `sidebarItems(query)` 逻辑未改
- Esc / 点 scrim 关闭、刷新钮（health/about/system）保留
- `reduced` profile：`settingsPageTransition` → 0ms 瞬时切换
- 服务 props（controls/network/apps…）按原页绑定转发

## 手测矩阵（实机）

| 项 | 预期 |
| --- | --- |
| 打开设置 → 侧栏扫过 主入口 | 彩色方块 + 选中蓝胶囊 |
| 主页 ↔ 主页连点 | 动画中断、最终页正确 |
| 子页（壁纸/Dock/健康…） | 返回箭头 → parent |
| 搜索过滤 | 结果列表仍可点开 |
| 深/浅色 | panelFill / 侧栏可读 |

## 性能

- 无新常驻 layer surface；页面实例数与改前一致（36）
- 过渡仅 transform/opacity（x + opacity）

## 发现待办

- 控件精修（Switch/Slider/Button…）→ **T16**
- 实机连点/深浅色观感确认（自动化无法覆盖视觉）
