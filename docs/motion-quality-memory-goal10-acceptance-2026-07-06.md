# GOAL-10 验收：默认策略与回退整理

日期：2026-07-06

范围：在 GOAL-0 到 GOAL-9 完成后，决定 motion 默认策略、compositor layer animation 默认开关、fallback 保留计划和用户回退路径。不删除 fallback，不引入新配置源。

## 完成了什么

- 新增 `tahoe-shell/docs/tahoe-motion-default-policy.md`：
  - 默认 motion profile 决策：`balanced`。
  - 新 shell state 的 compositor layer animation 默认：`false` / opt-in。
  - 保守 profile：`reduced`。
  - 回退基线：`balanced`。
  - 记录 QML fallback、TahoeGlass fallback、thumbnail fallback 和未迁移 surface 的保留计划。
  - 记录 settings UI、state JSON 和现有 `niri_settings_tool.py` 写入路径的 rollback 方法。
- 更新 `NiriAnimationsPage.qml` 文案：
  - `balanced` 明确为默认/回退基线。
  - `reduced` 明确为保守回退 profile。
  - compositor layer animation 开关说明关闭时保留 QML 外层 fallback。
- 更新 `docs/layer-animation-motion-v2-roadmap.md`：
  - 在任务 13J 记录 2026-07-06 GOAL-10 default decision。
  - 指向 `tahoe-motion-default-policy.md`。
- 新增 `tahoe-shell/tests/test_motion_default_policy.py`：
  - 校验 policy doc 写明 conservative defaults 和 fallback。
  - 校验 `DesktopSettings.qml` / `NiriSettings.qml` / `Motion.js` defaults 与 policy 一致。
  - 校验设置页保留 rollback 语义文案。
  - 校验 layer roadmap 指向 policy。

## 默认策略

| 项 | 决策 | 原因 |
| --- | --- | --- |
| Motion profile | `balanced` | GOAL-0 baseline，GOAL-5 已证明 `fast -> balanced` byte-for-byte rollback，当前 config read 检出 `balanced` |
| Compositor layer animation source default | `false` / opt-in | GOAL-7 有自动生命周期测试，但 live DRM/TTY 视觉验收和 post-deploy RSS 仍需后续实机确认 |
| Conservative profile | `reduced` | 复用现有 profile writer，降低空间 transform，保留必要 opacity feedback |
| Fallback removal | 不删除 | QML fallback、TahoeGlass fallback 和 thumbnail fallback 都仍是用户可恢复路径 |

注意：active user state 可以选择 `compositorLayerAnimations=true`；本 gate 决定的是 new/reset shell state 的 source default，不覆盖用户已有选择。

## 用户回退路径

- Settings UI：
  - `Motion profile` 选择 `Balanced` 回到默认基线。
  - `Motion profile` 选择 `Reduced` 使用保守低空间位移 profile。
  - 关闭 `使用 compositor layer 动画` 回到 QML 外层 open/close fallback。
- State JSON：
  - `compositorLayerAnimations: false`
  - `motionProfile: "balanced"`
- KDL profile writer：
  - `python3 tahoe-shell/services/niri_settings_tool.py write --config "$HOME/.config/niri/tahoe/config.kdl" --field animations.profile --value balanced --niri-bin /home/wwt/.local/bin/niri`
  - `/home/wwt/.local/bin/niri validate --config "$HOME/.config/niri/tahoe/config.kdl"`

## 没有做什么

- 没有把 compositor layer animation 默认改成 `true`。
- 没有删除 QML 外层 fallback。
- 没有删除 TahoeGlass / BackgroundEffect fallback。
- 没有删除 thumbnail fallback。
- 没有新增 profile JSON、第二套 motion token 文件、第二套 KDL writer 或用户可见新开关。
- 没有改 KDL motion 数值、material 数值或 blur 数值。

## 复用了哪些现有接口

- `DesktopSettings.qml` existing `compositorLayerAnimations` and `motionProfile` state。
- `NiriSettings.qml` existing `motionProfile` mirror and `setMotionProfile()` writer path。
- `niri_settings_tool.py` existing `animations.profile` writer。
- `Motion.js` existing profile-aware duration helpers。
- Existing settings page `NiriAnimationsPage.qml`。

## 是否新增接口

没有新增 runtime、IPC、config 或用户可见接口。

新增的是治理文档和测试：

- `tahoe-shell/docs/tahoe-motion-default-policy.md`
- `tahoe-shell/tests/test_motion_default_policy.py`

## 运行命令

```text
python3 tahoe-shell/tests/test_motion_default_policy.py
python3 tahoe-shell/tests/test_motion_token_convergence.py
python3 tahoe-shell/tests/test_niri_settings_tool.py
python3 -m unittest discover tahoe-shell/tests
python3 tahoe-shell/services/niri_settings_tool.py read --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
git diff --check
```

结果：

- `test_motion_default_policy.py`：4 tests passed。
- `test_motion_token_convergence.py`：3 tests passed。
- `test_niri_settings_tool.py`：15 tests passed。
- Full `python3 -m unittest discover tahoe-shell/tests`：60 tests passed。
- `niri_settings_tool.py read`：`animations.profile` 为 `balanced`，available profiles 为 `fast/balanced/liquid/reduced`。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- `git diff --check`：passed。

## 剩余风险

- 本 gate 没有重启 live Tahoe shell，也没有做鼠标/键盘实机设置页验收；验证是 source/test/config 级。
- 如果未来要把 `compositorLayerAnimations` 默认改成 `true`，需要新的 live visual、frame-time/RSS 记录和 rollback 验收。
- `reduced` 不是全局 no-animation 开关；它是低空间位移 profile，仍保留必要 opacity feedback。
- Active user state 可能与 source default 不同；这是用户选择，不应被本 policy 覆盖。

## 回滚方式

- Revert `tahoe-shell/docs/tahoe-motion-default-policy.md`。
- Revert the GOAL-10 text edits in `NiriAnimationsPage.qml` and `docs/layer-animation-motion-v2-roadmap.md`。
- Delete `tahoe-shell/tests/test_motion_default_policy.py`。
- Delete this acceptance document and revert the GOAL-10 status row。

No runtime config rollback is required because this gate did not change KDL values or source defaults.
