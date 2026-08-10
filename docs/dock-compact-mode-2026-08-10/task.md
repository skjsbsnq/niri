# D1 — Dock 紧凑模式（Win11 任务栏形态）

日期：2026-08-10
需求来源：用户口述（2026-08-10 会话）
流程依据：`docs/desktop-widgets-and-maximize-exclusivity-2026-08-09/execution-plan.md`
第 1 章七步流程 + 第 3 章审查机制（本任务复用该流程，但**不属于**该项目范围）。

---

## 0. 范围归属声明

本任务**不在** `desktop-widgets-and-maximize-exclusivity-2026-08-09` 项目内。
该项目的需求由 `research-report.md` A-0 锁定为小部件五条，
`constraints.md` G-8 禁止追加。故紧凑模式另立本文件，
按用户指示**先于** A2–A7 执行，完成后回到 A2。

本任务仍受该项目 `constraints.md` 第 1 章「项目既有守护规则」约束
（P-1 / P-3 / P-9 / P-10 / P-11 / P-12 全部有效，它们先于该项目存在）。

## 1. 需求（用户原话要点）

1. Dock 增加一个**紧凑模式**（与现有标准模式并存，可切换）。
2. 紧凑模式下 dock 条**两边延伸到整个屏幕**。
3. 看起来**更紧凑**：条更矮、图标更小。
4. 形态取向：**完全齐平、无圆角**（用户在两个方案中选定）。
5. 尺寸口径：**条 56 / 图标 36**（用户选定「要求一的水平」），
   视觉目标**对标 Windows 11 任务栏**。

## 2. 目标

给 Dock 增加一个由用户设置驱动的尺寸/形态档位。切到紧凑档时：
玻璃条通栏铺满屏幕宽度、四角齐平、条高 56、图标 36，
窗口自动多让出 28px 垂直空间（`exclusiveZone` 随条高）。

标准档（默认）行为、几何、观感**逐值不变**。

## 3. 范围

### 3.1 `components/Dock.qml`

- 现有几何常量（`dockIconSize` 48、`dockSurfaceHeight` 84、
  `dockPinnedRowHeight` 70、`dockWindowRowHeight` 60、各 slot 宽、
  `dockSurfacePadding`、`dockOuterMargin`、`dockItemSpacing`）
  由 `readonly property int <字面量>` 改为**按档位派生的表达式**。
  两档的值集中在一处可读的档位表内。
- `dockChromeTargetWidth`（`:158`）：紧凑档取整屏宽，
  标准档保持 `Math.min(dockSurfaceMaxWidth, dockRowTargetWidth + padding)`。
- `dockSurface.radius`（`:1117`）：紧凑档 0，标准档 `GlassStyle.RadiusMenu`。
- `mask`（`:1038-1055`）：**必须**从「跟随 dockChrome 全宽」改为
  内容区收敛 + 全宽条带分解，见下方 4.2。
- `Behavior on width`（`:1095`）：档位切换帧不得触发全宽扫动画。

### 3.2 `services/DesktopSettings.qml`

新增 `dockCompact`（bool，默认 false）四处齐全：
`readonly property`（:17 区）、`JsonAdapter` 默认值（:888 区）、
`sanitizeState` 校验（:701 区，bool 无需 clamp 但须与既有 5 键同风格）、
`setDockCompact` setter（:281 区，写盘走 `settingsFile.writeAdapter()`）。

### 3.3 `components/settings/pages/DockPage.qml`

在既有「Dock」section 内加一个 `Controls.TahoeListRow`（`checkable`），
与「自动隐藏」「最小化缩略栏」同风格。

### 3.4 测试

`tests/` 新增守护测试，锁：
- 标准档几何值**逐值等于**改动前（48/84/70/60/64/60/132/56/32/28/8）
- 紧凑档派生值正确（56/36 及随之下调的行高与 slot）
- 紧凑档 `radius` 为 0、宽度取整屏
- `mask` 在标准档语义等价（内容区 + headroom），紧凑档全宽条带不吞空白
- `exclusiveZone` 仍等于 `dockSurfaceHeight`（不得写死 84）

## 4. 关键约束与已知陷阱

### 4.1 G-6 禁止平行接口（最高风险条款）

**允许**：把常量参数化为单一档位表的派生值 —— 一条路径带参数。
**禁止**：`if (compact) { ...布局A... } else { ...布局B... }` 两套布局代码，
或新增第二个 `GlassPanel` / 第二个 `Row` / 第二套 mask 机制。

### 4.2 输入 mask 是最容易漏的回归点

现 mask 子 Region（`:1041-1046`）绑 `dockChrome.x/width`。
条宽变整屏后，若不改，**整条屏幕底部（含 `dockMagHeadroom` 透明带）
都会吞掉指针事件**，破坏「图标之外可点穿到桌面/窗口」的既有行为。

必须分解为两块：
- **内容区**：宽度按内容（rest 内容宽 + padding），高度含 headroom
  —— 标准档须与现行为逐值等价。
- **玻璃条带**：紧凑档为整屏宽但**高度只到玻璃条**（不含 headroom）；
  标准档宽度 0（不引入新命中区）。

理由：紧凑档玻璃通栏，条内空白处点击应落在 dock 上（Win11 行为），
但条**上方**的 headroom 透明带不该吞事件。

### 4.3 行高必须与条高同步下调

`:1176` 的垂直居中式 `(dockSurfaceHeight - dockPinnedRowHeight) / 2`
在行高 > 条高时被 clamp 到 0，内容会溢出玻璃。
紧凑档 56 条高下，`dockPinnedRowHeight` 必须 ≤ 56。

### 4.4 P-1 玻璃 region 几何禁弹簧

档位切换会改 region 的 width/height/radius。切换过渡若加动画，
只能用 `Motion.js` 时长 + Qt 缓动，**不得** `SpringAnimation`。
最简且最安全的做法：档位切换不加过渡（切换是设置行为，非高频交互）。

### 4.5 P-3 Motion.js 是唯一动效令牌来源

档位表是**几何**常量，放 `Dock.qml` 正确（现状即如此，`Motion.js`
只持动效）。不得因本任务把几何塞进 `Motion.js`，也不得在 Dock 里
硬编码新的 `duration:` 字面量。

### 4.6 玻璃着色器与 detail 门

紧凑档玻璃 2048×56（logical）比现 1518×84 面积更小，
仍落在 `postprocess.frag` 尺寸门的廉价侧；但 `config/niri/tahoe-phase0.kdl`
的 dock material 已有 `detail 1.0`（G2 落地）把细节钉满，**无需改 KDL**。
见 `glass-blur-differs-by-shader-size-gate-2026-08-10` 记忆。

### 4.7 niri 侧无需改动

`tahoe-dock` 无 `layer-rule` 的 `geometry-corner-radius`
（KDL 只有 `tahoe-dock-app-menu` / `tahoe-dock-window-menu` 有），
圆角完全由 QML `radius` + 玻璃 region 决定。齐平只改 QML。

### 4.8 `dockSlideDistance` 自动正确

`:81` `Math.max(Motion.dockAutohideSlidePx(88), dockSurfaceHeight)`：
紧凑档 56 < 88，token 占主导，autohide 仍完全收起（T08-fix4 的反向坑
是 surface 96 > token 88 留残条，本次方向相反、安全）。

## 5. 不做

- 不改标准档任何几何值
- 不改放大波（`computeSectionWave` 及 rest-only 玻璃铁律，`:417-434`）
- 不加第三档 / 无级滑块 / 每屏独立档位
- 不改 `DockRectanglePublisher.js` 决策逻辑（其输入坐标会随几何自然平移）
- 不改 niri、不改 KDL、不改着色器
- 不动 A2–A7 的任何文件

## 6. 完成判据

| # | 判据 | 证据形式 |
|---|---|---|
| 1 | 标准档几何逐值不变 | 新增测试 + `git diff` 显示无字面量被改动 |
| 2 | 紧凑档条高 56、图标 36、通栏整屏宽、四角齐平 | 部署后实机截图 |
| 3 | 紧凑档 `exclusiveZone`=56，窗口最大化紧贴条顶无缝隙 | 实机验证 |
| 4 | 标准档 mask 行为逐值等价（图标外可点穿） | 测试 + 实机点击 |
| 5 | 紧凑档条内空白点击落在 dock，条上方 headroom 可点穿 | 实机验证 |
| 6 | 设置面板开关可切换，重启 quickshell 后档位保持 | 实机 + `desktop-settings.json` |
| 7 | 两档下放大波、autohide、启动弹跳、tooltip 均正常 | 实机走查 |
| 8 | `qmllint --bare` 无新增告警 | 命令输出 |
| 9 | `pytest` 全绿（基线 1023 passed / 288 subtests） | 命令输出 |
| 10 | ≥2 独立子代理审查，全部 CONFIRMED 已修 | `acceptance/D1-review.md` |

## 7. 档位表（实现依据）

| 令牌 | 标准（现值） | 紧凑 | 依据 |
|---|---|---|---|
| `dockIconSize` | 48 | **36** | 用户选定 |
| `dockSurfaceHeight` | 84 | **56** | 用户选定 |
| `dockPinnedRowHeight` | 70 | **52** | ≤ 条高，留 2px 上下余量 |
| `dockWindowRowHeight` | 60 | **48** | 等比下调 |
| `dockPinnedButtonWidth` | 64 | **48** | 图标 36 + 12 间隙 |
| `dockWindowIconWidth` | 60 | **46** | 等比 |
| `dockWindowTitleWidth` | 132 | **120** | 标题仍可读 |
| `dockToolButtonWidth` | 56 | **44** | 等比 |
| `dockMinimizedThumbnailWidth` | 112 | **84** | 等比 |
| `dockMinimizedMinimumWidth` | 76 | **60** | 等比 |
| `dockSurfacePadding` | 32 | **12** | 通栏无需大内边距 |
| `dockOuterMargin` | 28 | **0** | 通栏 = 无外缘留白 |
| `dockItemSpacing` | 8 | **6** | 更密 |
| `dockTitledIconSize` | 40 | **30** | 标题模式图标，等比 |
| `dockMinimizedThumbnailHeight` | 62 | **44** | ≤ 窗口行高 48 |
| `dockToolIconSize` | 40 | **32** | 右侧工具图标，等比 |
| `radius` | `RadiusMenu`(18) | **0** | 用户选定齐平 |
| 宽度 | content-driven + 钳制 | **整屏** | 用户选定 |

`dockMagHeadroom` / `dockMagBleedPx` 为派生量，自动跟随 `dockIconSize`，
不入表（`:109` / `:111`）。

**全部 16 个 int 令牌集中在 `Dock.qml` 的档位块内**（`:92-115`），
使用点只引用、不内联字面量（审查 C-2 要求）。

## 8. 审查修复记录（2026-08-10）

两个独立子代理审查（几何视角 REJECT / 输入视角 APPROVE），
两条 CONFIRMED 均已修复：

- **C-1 档位切换期 mask 与玻璃失步**：原全宽条带用 `root.dockCompact ? root.width : 0`
  （瞬变），而 `dockChrome.width` 走 `Behavior` 缓动（~180ms）。
  切换途中 mask 已占满整屏而玻璃条尚未扫到边 → 屏幕两端空白吞点击；
  反向切换则条上点击穿透。**修复**：条带改为跟随 live `dockChrome.x/width`，
  与玻璃同源同相位。同类问题的 `radius` 一并改为按 live 宽度判定
  （`dockChrome.width >= root.width - 0.5`），使圆角与宽度同步变化。
  副作用：`Behavior on width` 无需再禁用（§3.1 原要求的「切换帧不得触发全宽扫动画」
  改为「扫动画期间 mask/玻璃/圆角三者保持一致」，语义更强且无需特例开关）。
- **C-2 三个档位值内联在使用点**：`dockTitledIconSize` / `dockMinimizedThumbnailHeight`
  / `dockToolIconSize` 已提升进档位块并纳入守护测试的 `TIER_TOKENS`（16 项全覆盖）。

审查提出但经核查不成立的：`iconCode` 为真实字形 U+EBA9（已用 fontTools
核验存在于 `assets/fonts/MaterialIconsRound.ttf`，Read 显示为空是私用区渲染问题）；
`sanitizeState` 不含 `dockCompact` 与既有 bool 键（`dockAutoHide`、
`dockMinimizedShelfEnabled`）同风格，JsonAdapter 对 bool 有强转。
