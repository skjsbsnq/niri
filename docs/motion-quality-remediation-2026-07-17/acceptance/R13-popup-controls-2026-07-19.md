# R13 · 弹窗控件合并统一 · 2026-07-19

覆盖问题：#5（余）#11 #12 #18 #40（按钮部分）#66 #67 #68 #69，以及 S4/S5。

## 实施摘要

- 新建 `components/controls/`，由 `ButtonSurface.qml` 唯一拥有按钮 hover、press、disabled 与点击命中；`IconButton.qml` / `TextButton.qml` 仅负责内容表达，`ToggleSwitch.qml` 统一轨道与旋钮。
- Clipboard、WiFi、Battery、Fan、Menu、NotificationCenter 全部切到共享控件。Battery 性能配置按钮也直接使用共享 surface；Fan 四个预设按钮使用共享文字按钮。
- `LeftSidebarWeather.qml` 的同名内联 `IconButton` 一并替换：这是执行计划要求根目录 grep 零残留所必需的范围，不提前实施 R18 的刷新旋转。
- Toggle 轨道色与旋钮 x 共用 `Motion.elementMove()`；按钮/开关 press 统一走 `Motion.pressScaleFor()` / `pressDurationFor()`；disabled opacity 与 hover 颜色均有 profile-aware Behavior。
- Battery 电量填充 width + color 加 eased Behavior。Fan slider 使用本地 drag preview，按下时停止外部 follow，拖动 1:1，释放后恢复服务值的 eased follow。
- NotificationCenter 的清空、DND、单条关闭三处裸控件全部替换；DND switch 使用 passive 模式，由整行 MouseArea 单独拥有点击，避免双触发。

## 方案决策

- 选择新建 `components/controls/`，不扩展 `components/settings/controls/`。后者依赖 settings theme、尺寸与 preview/commit API，把 popup 语义塞入会造成反向耦合；仓库已有相对目录 import 惯例，无需 qmldir 或资源注册。
- 共享层不是五个旧组件的逐份搬家：Icon/Text 两个薄封装共用一个 `ButtonSurface`，Pill/Confirm 由 TextButton 的通用 `danger` / `primary` / `active` / `flat` 变体表达。
- Battery profile 的纵向图标+文字属于内容布局差异，直接把内容放进共享 surface，不另建平行交互控件。
- Fan slider 保留既有连续 `userSet()` 服务接口，只在表现层增加本地 preview 与 Behavior 门控；未改服务边界。

## 审查

独立只读审查逐 diff 检查共享 API、Layout/命中、disabled/dark/reduced、Fan 拖动、Notification DND 双触发、玻璃 guardrail 与测试有效性，结论 **CLEAN**。

复核要点：

- Button 点击唯一入口在 `ButtonSurface`；禁用态不发 signal。
- Clipboard 行级 MouseArea 位于按钮层下方，按钮事件不会落到整行复制。
- Notification DND switch 为 `interactive:false`，整行点击只触发一次。
- Battery/Fan 新动画只作用内容 width/color，无 Spring、无 GlassPanel/TahoeGlass region 几何变更。
- 旧五类内联定义零残留；共享 API 使用通用状态/颜色/尺寸属性，没有现场专名。

## 自动验收

- R13 专项及关联回归：`test_popup_shared_controls.py`、`test_motion_token_convergence.py`、WiFi/Clipboard/NotificationCenter 回归 → **53 passed, 32 subtests passed**。
- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -x -q -p no:cacheprovider tahoe-shell/tests/` → **790 passed, 230 subtests passed in 39.26s**。
- 真实 Qt QML probe：共享 Icon/Text/Toggle 覆盖正常点击一次、disabled 不触发、passive switch 不触发、reduced press scale=1、compact 尺寸。
- `qmllint`：4 个共享控件 + 7 个消费文件全部退出 0、无输出。
- `bash scripts/check-tahoe-glass-guardrails.sh`、`git diff --check` → 退出 0。
- 防腐 grep：`rg 'component\\s+(IconButton|PillButton|TextButton|ToggleSwitch|ConfirmButton)' tahoe-shell/components/*.qml` → **零结果**。
- 嵌套冒烟：`timeout 35s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell bash scripts/run-tahoe-session.sh` → 预期 **124**；配置正常运行至 timeout，仅既有 EGL/SIGTERM warning。
- 部署：`scripts/arch-update.sh --deploy-tahoe-shell` + `--verify-tahoe-shell` → parity OK，manifest `6ae21377761c095b71207fbac660166889a84e707166fa673973c6c9898c781c`。

## 验收矩阵

- 宿主 surface：通过 Tahoe IPC 实际 open/close Battery、WiFi、Fan、Clipboard、NotificationCenter；随后扫描 240 行 Quickshell 日志，新共享控件与六个消费文件无 ReferenceError、TypeError、绑定循环或赋值错误。
- 开/关、快速操作、禁用：真实 QML probe 验证按钮单次 emit 与 disabled/passive 门控；宿主 IPC 循环验证 surface 可重复映射/释放。外层 Esc/点外关闭链路未改。
- 深浅色：Menu confirm 的 secondary foreground 显式跟随 `darkMode`；天气按钮继续消费 SettingsTheme；其余 bright popup 保留原配色。
- reduced：共享控件 probe 使用 reduced profile，空间 press 归零；所有新增 duration 均来自 Motion profile。
- `useSpring=false`：R13 未新增或依赖 SpringAnimation，全部路径为 eased Number/ColorAnimation。
- 数据刷新：WiFi/Clipboard 稳定列表专项回归全绿；Fan 拖动期间本地值直跟，Battery/Fan 外部更新才走 follow。
- 服务不可用：共享控件统一 disabled opacity + input gate；各弹窗原有占位/错误文案保持。

## 范围外

- 天气刷新图标旋转仍留给 R18；R13 只因零残留约束替换其按钮外壳。
- 宿主日志仍有既有 `LockScreen.qml: lockClock is not defined` warning，与 R13 无关，交由紧随其后的 R14 处理。
