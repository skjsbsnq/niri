# GOAL-4 验收：QML motion token 收敛

日期：2026-07-06

范围：减少 QML 内部微动效的硬编码 duration/easing，迁移到现有 `Motion.js` / `DynamicIslandMotion.js` vocabulary。不新增 motion token 文件，不移动组件结构，不改 niri KDL。

## 完成了什么

- 将常见 `NumberAnimation` / `ColorAnimation` 的硬编码 duration/easing 迁到现有 token：
  - `Motion.fadeFastDuration`
  - `Motion.panelExitDuration`
  - `Motion.menuEnterDuration`
  - `Motion.elementMoveDuration`
  - `Motion.emphasizedDecel`
  - `IslandMotion.overlayProgressDuration`
- 覆盖 general shell surface 和 settings controls：
  - `TopBar.qml`
  - `WindowOverview.qml`
  - `TaskSwitcher.qml`
  - `Launchpad.qml`
  - `SettingsPanel.qml`
  - `Dock.qml`
  - `WindowButton.qml`
  - `DockMinimizedWindow.qml`
  - `LeftSidebarWeather.qml`
  - `LeftSidebarSystem.qml`
  - `settings/SettingsSidebar.qml`
  - `settings/controls/TahoeSwitch.qml`
  - `settings/controls/TahoeTextField.qml`
  - `DynamicIslandMediaView.qml`
- 保持原数值行为：被迁移的 `120/130/140/150/180` duration 对应现有 token 的同值；`Easing.OutCubic` 迁移到 `Motion.emphasizedDecel`，该 token 仍是 `QtQuick.Easing.OutCubic`。
- 为剩余局部例外加代码注释，说明为什么暂不收敛到现有 semantic duration。
- 新增 `tahoe-shell/tests/test_motion_token_convergence.py`，防止 QML 组件重新内联 `Easing.OutCubic`，并防止新增私有 motion token JS 文件。

## 硬编码数量变化

GOAL-4 开始前记录：

```text
NumberAnimation 74
ColorAnimation 6
Easing.OutCubic 32
hardcoded duration 42
```

GOAL-4 完成后：

```text
NumberAnimation 74
ColorAnimation 6
Easing.OutCubic 0
hardcoded duration 16
```

说明：`NumberAnimation` / `ColorAnimation` 数量不应下降，因为本 gate 保留动画机制和组件结构；下降目标是硬编码 duration/easing，而不是删除动画对象。

## 剩余例外清单

| File | Literal | 原因 |
| --- | --- | --- |
| `TopBar.qml` | `170ms` opacity | topbar glass fade 比 panelEnter 略短，避免状态区滞后 |
| `WindowOverview.qml` | `160ms` scale | 保持 overview 既有 scale settle |
| `SettingsPanel.qml` | `160ms` scale | 保持 settings panel 既有 scale settle |
| `Dock.qml` | `190ms` auto-hide slide | dock reveal zone 专用 timing |
| `Dock.qml` / `WindowButton.qml` | `220ms` fallback bounce | VM/software GPU fallback，替代 spring bounce |
| `DockMinimizedWindow.qml` | `170ms` thumbnail bounce | minimized shelf vertical travel 更短 |
| `SettingsSidebar.qml` / `TahoeTextField.qml` | `80ms` focus border | 输入焦点反馈需要短于 fadeFast |
| `LeftSidebarSystem.qml` | `600ms` smooth max, `1000ms` chart slide | telemetry/data visualization smoothing |
| `LeftSidebarWeather.qml` | `900ms` spinner, `1100ms` shimmer | ambient loading/status loops |
| `DynamicIslandMediaView.qml` | `100ms` press scale | press feedback 短于 overlay content fade |

`DynamicIslandMediaView.qml` 的 `property real duration: 0` 是媒体时长数据字段，不是 animation duration。

## 视觉行为保持记录

- 迁移时没有改动画组件、状态条件、anchors、geometry、opacity/scale target 或 SpringAnimation fallback。
- 迁移的 duration token 与原 literal 数值相同。
- 迁移的 general QML easing token `Motion.emphasizedDecel` 与原 `Easing.OutCubic` 等价。
- 未部署或 reload live Quickshell；本 gate 的视觉保持是 source-level equivalence + bounded QML load smoke，后续 visual gate 继续做截图/快速 toggle 验收。

## 没有做什么

- 没有新增 motion token 文件。
- 没有新增第二套动画配置系统。
- 没有修改 `Motion.js` / `DynamicIslandMotion.js` 的 token 值。
- 没有移动组件结构。
- 没有写 KDL。
- 没有开始 GOAL-5 profile 写入。

## 复用了哪些现有接口

- `tahoe-shell/components/Motion.js`
- `tahoe-shell/components/DynamicIslandMotion.js`
- Existing QML `Behavior`, `NumberAnimation`, `ColorAnimation`, and `SpringAnimation`
- Existing component imports and settings controls

## 是否新增接口

没有新增 runtime 接口。

新增了 source-level test `tahoe-shell/tests/test_motion_token_convergence.py`。原因：GOAL-4 的约束是防止组件继续私有化 motion vocabulary；测试比人工 `rg` 更能长期守住这个边界。

## 运行命令

```text
python3 tahoe-shell/tests/test_motion_token_convergence.py
python3 tahoe-shell/tests/test_motion_preview.py
git diff --check
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/settings/controls/TahoeSwitch.qml
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/settings/controls/TahoeTextField.qml
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/WindowButton.qml
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/DockMinimizedWindow.qml
rg -n "duration:\s*[0-9]+" tahoe-shell -g '*.qml'
rg -n "Easing\.OutCubic" tahoe-shell -g '*.qml'
```

结果：

- `test_motion_token_convergence.py`：2 tests passed。
- `test_motion_preview.py`：2 tests passed。
- `git diff --check`：passed。
- `niri validate`：config is valid。
- Four bounded `qml6` loads: no stderr before expected `timeout` exit `124`。
- `rg -n "Easing\.OutCubic" tahoe-shell -g '*.qml'`：no matches。

Tooling note：`qmllint` / `qmlformat` were still unavailable on PATH in this environment.

## 剩余风险

- No live Quickshell reload/deploy was performed, so this gate does not prove visual screenshots.
- Some literal durations remain by design; GOAL-5 may decide whether profile state should later control them.
- The source test blocks direct `Easing.OutCubic` in QML components, but it does not forbid every possible future literal duration because documented local exceptions remain valid.

## 回滚方式

Rollback is reverting the GOAL-4 component import/duration/easing substitutions, deleting `tahoe-shell/tests/test_motion_token_convergence.py`, deleting this acceptance document, and reverting the GOAL-4 status row. No persistent user config or KDL state is changed by this gate.
