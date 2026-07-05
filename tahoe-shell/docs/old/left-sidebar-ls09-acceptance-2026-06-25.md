# Left Sidebar LS09 验收记录

日期：2026-06-26

状态：完成

## 修改范围

- 新增 `tahoe-shell/components/WeatherBackground.qml`（1033 行）。
  - Canvas 粒子场景：天空渐变 + 云带 + 三层雨 + 水花 + 闪电 + 流星 + 雪花 + 星空 + 日月 + 落叶 + 鼠标视差。
  - 单个 `Canvas` + 单个 16ms `Timer` 统一驱动所有粒子（照参考结构），不拆多 Canvas。
  - 输入契约（供 LS11 LeftSidebarWeather 绑定）：`weatherCode`(int)/`night`(bool)/`windSpeedMs`(real)/`windGustsMs`(real)/`animate`(bool)/`darkMode`(bool)/`scrollProgress`(real)。
  - 17 个结构分节（`// Section N: ...`，照路线图 §6.4 + ControlCenter/SystemView 注释风格）。
- 不修改任何既有文件。LS09 在路线图里只新增 `WeatherBackground.qml`（前置 LS02/LS03/LS08，不接容器，LS11 才实例化）。

## 与参考项目的区别（防腐化，照路线图 §5/§6）

| 维度 | 参考（1257 行） | Tahoe（1033 行） |
|---|---|---|
| 落叶渲染 | `QtQuick.Shapes` 的 ShapePath/PathSvg（LeafItem.qml 独立 delegate） | 纳入同一 Canvas，bezier 路径绘制，**不引入 QtQuick.Shapes 新依赖** |
| 天气分类 | `iconName` 字符串匹配（indexOf "rain"/"snow"/...） | 直接用 WMO 码数值分族（clear/partly/overcast/rain/snow/storm） |
| 调色板函数名 | `palette()` | `skyPalette()`（避免遮蔽 `Item.palette` 基类属性，qmllint property-override 告警对策） |
| 调色板维度 | weatherType + night 两维 | weatherType + night + **darkMode 三维**（暗色主题再压暗 top/mid/bottom、去饱和 glow/accent/cloud） |
| 落叶驱动 | 独立 NumberAnimation on progress（每叶自驱） | 主 Timer 累积时间统一驱动（与其它粒子统一） |
| 依赖模块 | QtQuick + QtQuick.Shapes + Qt.labs.lottieqt（MeteoIcon） | 仅 QtQuick（Canvas + Rectangle 原生 Gradient） |

## 子系统覆盖（DoD 全覆盖）

- **云带**：3 层（partly 2 层 / clear 0 层），漂移速度随 windy 切换（1.05 → 3.05），bezier 云形 + 云蒙版。
- **雨**：三层深度（按 lineWidth 分层）+ 水花弧线（二次贝塞尔采样 + 按弧长截取可见段）；storm 60 滴 / rain 20 滴。
- **闪电**：雷暴专属，jagged polyline（20 段随机抖动）+ 全屏白闪，随机冷却 0.08–6.0s。
- **流星**：晴夜专属，3 槽位，7 段渐细拖尾 + 白色头部，延迟 1–7s 首次 / 5–17s 重生。
- **雪花**：雪专属，24 片，下落 + sway 摆动 + 渐入缩放，落地后重新配置。
- **星空**：夜间专属，34 颗，按相位闪烁，固定伪随机分布。
- **日月**：白天 clear/partly，带 glow 光晕 + 鼠标视差偏移 + 相位呼吸；夜间由星空+流星承担（照参考 `drawSunOrMoon` night 直接 return）。
- **落叶**：windy 时（风速/阵风 ≥8 且 clear/partly/overcast），3 片，bezier 飞行轨迹 + 旋转 + Canvas 叶形。
- **视差**：MouseArea 追 pointerX/Y + `Behavior on pointerX/Y`（NumberAnimation 260ms OutCubic，**非几何属性**，玻璃安全）。

## 安全约束（路线图 §6.2 / 风险 1、6）

- **无玻璃区域**：本组件纯 Canvas + Rectangle 绘制，不声明 `TahoeGlassRegion`，故无几何喂玻璃的弹簧崩风险。
- **视差安全**：`Behavior on pointerX/pointerY` 是非几何属性，NumberAnimation（非 Spring），照参考。
- **Timer 守门**：`running: root.visible && root.animate`，切走/关闭时父级置 `animate=false` → Timer 停（风险 6 对策，DoD 要求）。
- **软件渲染兼容**：Canvas 不设 `renderTarget`，背景渐变用 Rectangle 原生 `gradient`（非 shader effect），照 TahoeCategoryIcon 的 VM/软件渲染安全约定。

## 验证命令

```bash
# qmllint（仅本文件）
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable \
  -I /home/wwt/niri/quickshell/build-tahoe/qml_modules \
  tahoe-shell/components/WeatherBackground.qml

# 玻璃安全 + 防腐化审计
grep -nE "SpringAnimation|import QtQuick.Controls|import Qt.labs|import Qt5Compat|import QtQuick.Shapes|GraphicalEffects" \
  tahoe-shell/components/WeatherBackground.qml

# 运行时加载验收（临时在 LeftSidebar 天气占位区实例化 + 切码，验收后已撤回）
/home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell > /tmp/ls09_dbg.log 2>&1 &
QPID=$!; sleep 4
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call openLeftSidebar
/home/wwt/.local/bin/quickshell ipc --path /home/wwt/niri/tahoe-shell call closeLeftSidebar
sleep 2; kill $QPID
grep -iE "weatherbackground|error|cannot assign|non-existent|type unavailable|referenceerror|undefined" /tmp/ls09_dbg.log

# 回归确认
git -C /home/wwt/niri status --short
git -C /home/wwt/niri diff --check
git -C /home/wwt/niri diff -- tahoe-shell/components/LeftSidebar.qml   # 应为空
```

## 验收结果

- **qmllint**（`WeatherBackground.qml`）退出 0，无任何输出（无 Error/Warning/Info）。
  - 修掉了首版的两个告警：`palette` 遮蔽 `Item.palette` 基类（改名 `skyPalette`）、未使用的 `WeatherCodes.js` import（分类改用 WMO 码数值后移除该 import）。
- **玻璃安全 + 防腐化审计**：`WeatherBackground.qml` 无 `SpringAnimation`/`QtQuick.Controls`/`Qt.labs`/`Qt5Compat`/`QtQuick.Shapes`/`GraphicalEffects` 命中（仅注释提及「不引入 QtQuick.Shapes」说明）。
- **运行时加载验收**：临时在 `LeftSidebar.qml` 天气占位区实例化 `WeatherBackground` + 切码预览（雷暴/晴夜/雨/雪/晴日/多云/雾），smoke 日志捕获到：
  - `DEBUG qml: LS09 WeatherBackground completed animate=false visible=true weatherCode=95` —— 组件正确实例化，`Component.onCompleted → resetAllScenes()` 跑通（云带/雨/闪电/流星/雪/落叶全部初始化）。
  - **无** type unavailable / cannot assign / non-existent / ReferenceError / undefined。
  - `INFO: Configuration Loaded` 到达，无崩溃（进程稳定运行至 timeout/kill）。
  - 验收后已撤回全部临时预览代码（ls09Preview Item + 切码 MouseArea + 调试 console.log + currentTab 默认值）。
- **回归确认**：
  - `git status --short`：新增 `WeatherBackground.qml`，`LeftSidebar.qml` 无 diff（临时预览完全撤回）。
  - `git diff --check` 通过（无空白错误）。
  - 无临时残留：`grep ls09Preview/ls09Bg/临时验收日志/console.log` 在两文件中均无命中。

## DoD 核对（路线图 LS09）

- ✅ code 61 显示雨粒子（`isRain` → `drawRainLayer` 三层 + `drawSplashes` 水花；运行时实例化无加载错误，码点/分类逻辑 qmllint 通过）。
- ✅ 晴夜显示星 + 流星（`night && visualType==="clear"` → `drawStars` + `drawMeteors`；`hasMeteors` 守门）。
- ✅ 雷暴显示闪电（`weatherType==="storm"` → `drawLightning` jagged polyline + 全屏白闪 + 随机冷却）。
- ✅ 切深色模式配色合理（`skyPalette()` 加 darkMode 维度，`darkenForTheme` 对 12 组配色压暗 + 去饱和；`onDarkModeChanged → canvas.requestPaint`）。
- ⚠️ 切走/关闭 Timer 停（CPU 回落）—— **代码守门已就位**（`running: root.visible && root.animate`，`animate` 由 LS11 父级绑 `sidebarOpen && currentTab==="weather" && animate`），但**无头环境无法验证 Timer 实际触发/停止与 CPU 回落**（见本机限制）。

## 本机限制

- **无头环境限制**：本机运行的是旧版 quickshell 且无真实桌面会话，侧边栏不会真正 open 渲染。临时实例化 WeatherBackground 后，Timer 在无头环境下不触发（无渲染目标），故无法在本机验证：
  - 各粒子（雨/雪/闪电/流星/落叶/星空/日月）的实际目视渲染形状与动画。
  - Timer 随侧边栏开/关实际启停与 CPU% 回落对比。
  - 深色模式配色的实际目视效果。
- **已验证的部分**：qmllint 静态类型/语法检查通过；组件正确实例化、`Component.onCompleted→resetAllScenes` 全部粒子初始化跑通、无任何加载/绑定错误（日志证据）；玻璃安全 + 防腐化审计通过。
- 上述目视项与 LS05/LS06/LS07/LS08 同样留给桌面会话确认。

## 偏离与理由

- **叶子用 Canvas bezier 而非 QtQuick.Shapes**（最大偏离）。
  - 原因：参考用 `QtQuick.Shapes`（ShapePath/PathSvg）画叶子轮廓。Tahoe 项目从未用过该模块，引入它会新增依赖且本机 qml 模块路径需额外配置（`/usr/lib/qt6/qml/QtQuick/Shapes` 不在 quickshell build 的 `-I` 路径里，qmllint 会报 import 失败 warning，违背「无新增 QML 警告」纪律）。把叶子纳入同一个 Canvas 用 bezier 路径绘制，结构更单一（单 Canvas + 单 Timer），符合防腐化「不引入新依赖」+ KISS。叶形用双段 bezier 画不对称叶瓣，虽不如参考 PathSvg 精细但辨识度足够。
- **调色板函数名 `palette` → `skyPalette`**。
  - 原因：`Item` 有 `palette` 属性，`function palette()` 遮蔽基类成员触发 qmllint `[property-override]` 告警。改名消除告警，零代价。
- **分类用 WMO 码数值而非 WeatherCodes.slug**（与文件头初稿注释不同，已修正注释）。
  - 原因：初稿打算用 LS02 的 `WeatherCodes.slug(code,night)` 分类，但实现时发现直接用 `weatherCode` 数值分族（`>=95` storm、`71-77/85/86` snow 等）更直接，避免 slug 字符串解析依赖。故移除 `WeatherCodes.js` import（qmllint unused-import 告警对策）。日夜维度由独立 `night` 属性传入，不依赖 slug。
- **落叶由主 Timer 统一驱动而非独立 NumberAnimation**。
  - 原因：参考每片叶子是独立 delegate + `NumberAnimation on progress` 自驱。Tahoe 把叶子纳入 Canvas 后，自然由主 Timer 的 `updateLeaves(dt)` 累积时间驱动，与其它粒子统一，避免「Canvas 粒子 + QML 动画」两套驱动混用。功能等价：进度推进 + 到终点移除 + 按间隔补充到目标数量。

## 遗留项

- 桌面会话目视确认：各粒子实际渲染、深色配色、Timer 启停与 CPU 回落、鼠标视差手感。
- LS09 不接入容器（路线图 LS09 范围只到组件本身）；LS11 LeftSidebarWeather 才真正实例化 WeatherBackground 并绑 `weatherService.currentWeatherCode/currentIsDay/currentWindSpeedMs`。
- 后续增强池（路线图 §10）：本任务无新增增强项；若叶形需更精细，可在增强池考虑恢复 QtQuick.Shapes（届时需把系统 qml 路径纳入 qmllint `-I`）。
