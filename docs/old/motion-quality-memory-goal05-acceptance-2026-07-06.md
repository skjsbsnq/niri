# GOAL-5 验收：motion profile 写入

日期：2026-07-06

范围：通过现有设置链路把 motion profile 写入 niri KDL，并把同一个 profile 镜像到 QML motion token 行为。不新增 KDL writer，不让组件直接写配置，不开始 GOAL-6。

## 完成了什么

- 扩展现有 `tahoe-shell/services/niri_settings_tool.py` writer，新增可写字段 `animations.profile`。
- `read` 输出现在包含：
  - `animations.profile`
  - `animations.availableProfiles`
- 支持 profile：
  - `fast`
  - `balanced`
  - `liquid`
  - `reduced`
- 扩展 `tahoe-shell/services/NiriSettings.qml`：
  - `motionProfile`
  - `motionProfileModel`
  - `setMotionProfile(profile)`
  - `applyAnimations(anim)` 读取 tool 返回的 `anim.profile`，不匹配内置 profile 时显示 `custom`。
- 扩展 `tahoe-shell/services/DesktopSettings.qml`：
  - 持久化 `motionProfile`
  - `validMotionProfile(value)`
  - `setMotionProfile(profile)`
  - 非法值回退到 `balanced`。
- 在 `tahoe-shell/components/settings/pages/NiriAnimationsPage.qml` 新增 `Motion profile` 选择入口。
  - `custom` 状态不直接写入；选择任一内置 profile 后通过 `NiriSettings.setMotionProfile()` 回写。
- 扩展 `tahoe-shell/components/Motion.js`：
  - 保留 GOAL-4 原 token 作为 `balanced` 默认。
  - 新增 profile duration table。
  - 新增 `fadeFast(settingsService)`、`menuEnter(settingsService)`、`menuExit(settingsService)`、`panelEnter(settingsService)`、`panelExit(settingsService)`、`elementMove(settingsService)`、`elementResize(settingsService)`。
- 把需要 profile duration 的 QML call site 改为读取 `Motion.*(settingsService)`。
- 在 `tahoe-shell/shell.qml` 复用现有 service wiring，把 `NiriSettings.motionProfile` 镜像到 `DesktopSettings.motionProfile`，再传给 shell 组件。

## 写入的 KDL 字段

`animations.profile` 不是新 KDL 节点；它是现有 writer 的聚合字段，写入以下现有 KDL 位置。

Top-level `animations` spring actions：

| Action | Fields |
| --- | --- |
| `workspace-switch` | `spring damping-ratio`, `spring stiffness`, `spring epsilon` |
| `window-movement` | `spring damping-ratio`, `spring stiffness`, `spring epsilon` |
| `window-resize` | `spring damping-ratio`, `spring stiffness`, `spring epsilon` |
| `overview-open-close` | `spring damping-ratio`, `spring stiffness`, `spring epsilon` |

Profile spring values：

| Profile | `workspace-switch` | `window-movement` | `window-resize` | `overview-open-close` |
| --- | --- | --- | --- | --- |
| `fast` | `1.0 / 860 / 0.0001` | `0.9 / 700 / 0.001` | `1.0 / 760 / 0.0005` | `0.98 / 820 / 0.0005` |
| `balanced` | `1.0 / 780 / 0.0001` | `0.86 / 620 / 0.001` | `0.96 / 700 / 0.0005` | `0.95 / 760 / 0.0005` |
| `liquid` | `0.92 / 680 / 0.0001` | `0.82 / 560 / 0.001` | `0.92 / 620 / 0.0005` | `0.9 / 680 / 0.0005` |
| `reduced` | `1.0 / 1000 / 0.001` | `1.0 / 1000 / 0.001` | `1.0 / 1000 / 0.001` | `1.0 / 1000 / 0.001` |

Each tuple is `damping-ratio / stiffness / epsilon`.

Layer-rule groups matched by exact existing namespace sets:

| Group | Namespaces |
| --- | --- |
| `control_center` | `tahoe-control-center` |
| `notification_center` | `tahoe-notification-center` |
| `left_sidebar` | `tahoe-left-sidebar` |
| `spotlight` | `tahoe-spotlight` |
| `small_popup` | `tahoe-battery-popup`, `tahoe-wifi-popup`, `tahoe-fan-popup`, `tahoe-clipboard-popup`, `tahoe-menu-popup`, `tahoe-application-menu`, `tahoe-tray-menu` |
| `dock_menu` | `tahoe-dock-app-menu`, `tahoe-dock-window-menu` |
| `process_menu` | `tahoe-process-menu` |
| `toast` | `tahoe-notification-toast` |

For each matched layer-rule, profile write updates existing `animations { layer-open { ... } layer-close { ... } }` leaves:

- `transform-duration-ms`
- `opacity-duration-ms`
- `opacity-from` or `opacity-to`
- `opacity-curve` where the profile defines one

The matcher refuses to write if an expected layer-rule group is missing, duplicated, or does not contain an `animations` block.

## 没有做什么

- 没有新增第二套 KDL 写入工具。
- 没有新增第二套动画配置系统。
- 没有让 QML 组件直接写 niri 配置。
- 没有把 Tahoe namespace 写进 niri Rust 逻辑。
- 没有修改 `window-open` / `window-close` shader action。
- 没有把 `reduced` profile 实现为全局 `animations off`；它使用更硬的 spring、短 opacity feedback，并把部分 QML transform duration 降为 `0`。
- 没有部署或 live reload Quickshell。
- 没有开始 GOAL-6。

## 复用了哪些现有接口

- `NiriSettings.qml` 的现有 load/write queue。
- `niri_settings_tool.py` 的现有 guarded writer、temporary file、fsync、`niri validate`、atomic replace 路径。
- `DesktopSettings.qml` 的现有 JsonAdapter 持久化。
- `Motion.js` 的 GOAL-4 token vocabulary。
- `NiriAnimationsPage.qml` 的现有 settings page/control structure。
- Existing Quickshell service wiring in `shell.qml`。

## 是否新增接口

新增的是现有接口上的扩展，不是平行系统：

- `niri_settings_tool.py` writable field `animations.profile`。
- `NiriSettings.qml` mirror property/method `motionProfile`、`motionProfileModel`、`setMotionProfile(profile)`。
- `DesktopSettings.qml` mirror property/method `motionProfile`、`setMotionProfile(profile)`。
- `Motion.js` profile-aware duration helper functions。

新增 source tests：

- `tahoe-shell/tests/test_niri_settings_tool.py` 覆盖 `animations.profile` write/read/rollback 和 missing group refusal。
- GOAL-4/GOAL-3 的 `test_motion_token_convergence.py`、`test_motion_preview.py` 继续作为 regression checks。

## 运行命令

```text
python3 tahoe-shell/tests/test_niri_settings_tool.py
python3 tahoe-shell/tests/test_motion_token_convergence.py
python3 tahoe-shell/tests/test_motion_preview.py
git diff --check
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/settings/controls/TahoeSwitch.qml
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/WindowButton.qml
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/settings/pages/NiriAnimationsPage.qml
python3 tahoe-shell/services/niri_settings_tool.py write --config "$tmp/config.kdl" --field animations.profile --value fast --niri-bin /home/wwt/.local/bin/niri
python3 tahoe-shell/services/niri_settings_tool.py write --config "$tmp/config.kdl" --field animations.profile --value balanced --niri-bin /home/wwt/.local/bin/niri
python3 -m unittest discover tahoe-shell/tests
```

结果：

- `test_niri_settings_tool.py`：15 tests passed。
- `test_motion_token_convergence.py`：3 tests passed。
- `test_motion_preview.py`：2 tests passed。
- `git diff --check`：passed。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- Three bounded `qml6` loads exited with expected `124` timeout and no stderr.
- Temporary profile write check:
  - `fast_profile=fast`
  - `fast_workspace_stiffness=860`
  - writing `balanced` back produced `rollback_cmp=0` against `config/niri/tahoe-phase0.kdl`。
- Full `python3 -m unittest discover tahoe-shell/tests` still fails because `tahoe-shell/docs/tahoe-material-governance.md` is missing in `test_tahoe_material_governance.py`; this is pre-existing/unrelated to GOAL-5 and was not fixed in this gate.

Tooling note：`qmllint` / `qmlformat` were unavailable on PATH; bounded `qml6` loads were used instead.

## 剩余风险

- No live Quickshell deploy/reload was performed, so this gate proves source wiring and bounded QML load, not screenshot-level visual behavior.
- Exact namespace matching is intentionally strict; hand-edited configs with missing/duplicated Tahoe layer-rule groups will refuse profile writes.
- `reduced` profile does not disable all motion; it reduces spatial motion while preserving opacity feedback. A global no-animation policy, if wanted, must be a later explicit goal.
- Hot reload relies on the existing `NiriSettings.qml` write path and niri validation path; no separate runtime session validation was performed in this environment.

## 回滚方式

- User-level rollback：select `balanced` in the Motion profile selector. Current `config/niri/tahoe-phase0.kdl` detects as `balanced`, and the temp check proved `fast -> balanced` returns to a byte-for-byte match.
- Source rollback：revert the GOAL-5 changes in `Motion.js`, `DesktopSettings.qml`, `NiriSettings.qml`, `niri_settings_tool.py`, `NiriAnimationsPage.qml`, `shell.qml`, and the related QML call-site wiring; delete this acceptance document; revert the GOAL-5 status row to `in-progress` or `pending` as appropriate.
