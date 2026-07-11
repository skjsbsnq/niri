# T14 · 颜色语义化 + accent 系统 · 验收记录

日期：2026-07-11

## 目标

把 `SettingsTheme.js` 扩展为全 shell 共享 token 库；语义色 + macOS 八色 accent 入 DesktopSettings；迁移 TopBar / 菜单 / 控制中心 / 左侧边栏四面（设置面控件精修留给 T15/T16）。

## 实现摘要

### Token 库（收编，非并存）

`SettingsTheme.js` 新增 / 统一：

| API | 用途 |
| --- | --- |
| `label` / `secondaryLabel` / `tertiaryLabel` | 语义文字色（兼容 `textPrimary` 等旧名） |
| `separator` / `danger` / `systemBlue` | 分割线 / 危险 / 系统蓝 |
| `accent` / `systemAccent` / `normalizeAccentId` / `accentIds` | 可选 accent |
| `cardFill` / `controlTile*` / `buttonHover` / `sliderFill` … | shell 面共享表面色 |

**未**新建第二套 theme 文件（规则 §2.4）。

### Accent 系统

- 八色 id：`blue` / `purple` / `pink` / `red` / `orange` / `yellow` / `green` / `graphite`
- `DesktopSettings.accentColor`（JsonAdapter 默认 `"blue"`）+ `setAccentColor` / `accentColorLabel` / sanitize
- 设置 → 外观页色板选择器（即时写 settings）

### 四面迁移

| 面 | 绑定 |
| --- | --- |
| TopBar | `Theme.label` / `accent` / `statusAttention` / `buttonHover`… |
| MenuRow | `Theme.accent` / `danger` / `separator` / label 语义色 |
| ControlCenter | `Theme.accent` → `accentActive`；tile/text/slider token |
| LeftSidebar + Weather/System | `Theme.accent` → `accentBlue`；card/text token |

SettingsPanel 的 `accentBlue` / `accentFillStrong` / `fieldStrokeFocus` / `categoryColor` 同步读 `accentId`。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，110 passed**（+7 T14 相关） |
| `rg '#2c9cf2\|#007ff7\|#0a84ff\|#0b6bd3' TopBar/CC/LeftSidebar/MenuRow` | **无命中**（accent 已 token 化） |
| 四面 `SettingsTheme.js` import | 有 |

## RSS 阶段检查点（规则 §4.9，对照 T00）

| 进程 | T00 RSS | 当前 (2026-07-11) | Δ |
| --- | --- | --- | --- |
| niri | ≈206.9 MB | **180,604 KB ≈ 176.4 MB** | 低于基线 |
| quickshell | ≈570.6 MB | **672,756 KB ≈ 657.0 MB** | +15% 量级（长会话常驻，非 T14 新增 surface） |

T14 仅扩展 token 与设置字段，无新常驻 layer。T23 冷启动复测。

## 功能不回归

- 既有 IPC / 弹窗 / 深浅色路径未删
- 默认 accent = blue，视觉与改前系统蓝一致
- 设置页其它控件仍用 SettingsPanel theme 属性（向后兼容 `textPrimary`/`accentBlue` 名）

## 发现待办

- 实机：外观页切换 accent 后 TopBar/菜单/CC/侧边栏即时变色。
- 四面仍有结构性半透明 hex（玻璃/hover 填充），非语义一次性色；可后续继续收编。
- 设置控件精修 / 外壳重设计 → T15/T16。
