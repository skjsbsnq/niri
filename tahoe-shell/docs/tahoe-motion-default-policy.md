# Tahoe Motion Default Policy

日期：2026-07-16

本文记录 Tahoe motion 的当前默认策略。2026-07-16 的 R10 所有权治理取代了 GOAL-10 的临时 fallback 保留决策：每类 surface 的外层进出场只有一个 owner。

## Decisions

| Area | Decision | Source |
| --- | --- | --- |
| Default motion profile | `balanced` | `config/niri/tahoe-phase0.kdl`, `NiriSettings.qml`, `DesktopSettings.qml`, `Motion.js`, `niri_settings_tool.py` |
| Tahoe surface outer animation owner | niri layer animation / default-on | `NiriSettings.qml`, `niri_settings_tool.py`, Tahoe `layer-rule` |
| Conservative user profile | `reduced` | Existing `animations.profile` writer and settings page selector |
| Baseline rollback profile | `balanced` | GOAL-5 byte-for-byte rollback check |

2026-07-09 update (motion-visual-overhaul T01): `balanced` now carries the
Tahoe Motion 2.0 timings (menuEnter 180 / menuExit 160 / panelEnter 320 /
panelExit 200) and `Motion.js` additionally exports the spring vocabulary
(`springSnappy`/`springSmooth`/`springPanel`/`springBouncy`) plus the press
tokens (`pressDuration` 120 / `pressScale` 0.96). No new profile was added;
`fast`/`liquid` scale proportionally and `reduced` stays minimal. The
byte-for-byte rollback property is a round-trip guarantee of the profile
writer, not a freeze of `balanced` values; rollback for the retiming itself is
`git revert` of the T01 commit.

2026-07-09 update (motion-visual-overhaul T03): compositor layer-rule
animations now open on spring main channels (menus/popovers `popin origin
"anchor"` dr=0.88 st=500; CC/NC/left-sidebar edge-reveal dr=0.85 st=380; toast
slide dr=0.8 st=320; spotlight popin dr=0.88 st=500, scale-from 0.96). The
profile writer manages those spring lines per profile and keeps the layer-open
transform override channel absent so the transform inherits the spring.
`reduced` keeps its conservative shape — it zeroes the layer transform channel
(`transform-duration-ms 0`, opacity-only feedback) and leaves the inert spring
line untouched — and every profile round-trips back to `balanced`
byte-identically. Rollback is `git revert` of the T03 commit.

2026-07-16 update (R10): Toast、LeftSidebar、Spotlight 删除了 surface 级 QML
位移、缩放和淡出 fallback，niri 成为这些 surface 外层进出场的唯一 owner。
`animations.layer_animations_enabled` 通过既有 `NiriSettings` writer 在全部受管
`layer-open`/`layer-close` 中增删 `off`，关闭时外层显隐即时完成，而不是切换到
第二套 QML 动画。Launchpad 仍明确由 QML 拥有，因为它没有对应 compositor
layer animation rule。`reduced` 同时约束 niri layer channel 和 QML 内部微动画。

## Why Balanced Stays Default

`balanced` remains the default because it is the only profile with all of the following evidence:

- GOAL-0 recorded it as the current KDL/QML timing baseline.
- GOAL-5 proved `fast -> balanced` returns `config/niri/tahoe-phase0.kdl` to a byte-for-byte match.
- GOAL-7 added snapshot lifecycle tests for fast toggle and one-frame close snapshot release.
- GOAL-8 kept material strength unchanged because live DRM/TTY render timing was not captured.
- GOAL-9 reduced allocation churn but did not deploy/restart the running compositor, so no live after-RSS win is claimed.

`fast`, `liquid`, and `reduced` remain selectable profiles. They are not the default because they have less live visual and performance evidence than `balanced`.

## Layer Animation Default

`layerAnimationsEnabled` 从当前 KDL layer rules 读取，默认配置中为 `true`。用户可在 Niri animations 页面关闭。

Reasons:

- The compositor layer animation path has automated lifecycle coverage after GOAL-7, including fast toggle, interrupt, and snapshot release tests.
- The KDL layer animation rules remain present and validated, and `balanced` remains the rollback profile.
- 开关由唯一 KDL writer 写入所有受管 layer phase，并在写入后热加载 niri。
- 关闭时 surface 即时 map/unmap；不会恢复 QML 外层 fallback。

## Ownership And Fallback Plan

| Fallback | Keep/Remove | Reason |
| --- | --- | --- |
| QML outer fallback for migrated Tahoe surfaces | Remove | niri is the sole outer owner; disabling means instant outer visibility |
| Launchpad QML outer animation | Keep | Not migrated to compositor layer animation |
| Dock, TaskSwitcher, WindowOverview QML path | Keep | Not forced into compositor layer animation |
| TahoeGlass client fallback to BackgroundEffect | Keep | Protocol/fallback lifecycle is separate from motion defaults |
| Thumbnail `WindowPreviewFallback` | Keep | Required when niri thumbnail IPC or image decode fails |
| `reduced` motion profile | Keep | Conservative profile for low-motion preference |

不得为 Toast、LeftSidebar、Spotlight 或其它已迁移 surface 重新增加条件式 QML 外层路径。

## User Rollback Paths

Settings UI:

- Open Niri animations.
- Set `Motion profile` to `Balanced` for the baseline profile.
- Set `Motion profile` to `Reduced` for conservative low-spatial-motion behavior.
- Turn off `使用 compositor layer 动画` for instant outer surface visibility.

KDL/profile rollback through the existing writer:

```text
python3 tahoe-shell/services/niri_settings_tool.py write --config "$HOME/.config/niri/tahoe/config.kdl" --field animations.profile --value balanced --niri-bin /home/wwt/.local/bin/niri
python3 tahoe-shell/services/niri_settings_tool.py write --config "$HOME/.config/niri/tahoe/config.kdl" --field animations.layer_animations_enabled --value false --niri-bin /home/wwt/.local/bin/niri
/home/wwt/.local/bin/niri validate --config "$HOME/.config/niri/tahoe/config.kdl"
```

## Maintenance Rules

- Do not introduce a profile JSON file or component-private motion token file.
- Do not let QML components write niri KDL directly.
- Keep `Motion.js` profile names synchronized with `niri_settings_tool.py`.
- Keep `NiriSettings.qml` and `niri_settings_tool.py` layer animation state aligned with this document.
- `DesktopSettings.qml` must not regain a compositor layer animation mirror.
- Migrated components may keep internal content motion, but must not retain a surface-level fallback owner.
