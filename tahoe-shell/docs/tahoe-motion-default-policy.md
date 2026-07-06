# Tahoe Motion Default Policy

日期：2026-07-06

本文是 GOAL-10 的默认策略记录。它只决策默认 profile、compositor layer animation 开关和 fallback 保留计划；不新增第二套 motion 配置，不删除 fallback。

## Decisions

| Area | Decision | Source |
| --- | --- | --- |
| Default motion profile | `balanced` | `config/niri/tahoe-phase0.kdl`, `NiriSettings.qml`, `DesktopSettings.qml`, `Motion.js`, `niri_settings_tool.py` |
| New shell state default for compositor layer animations | `false` / opt-in | `DesktopSettings.qml` `JsonAdapter.compositorLayerAnimations` |
| Conservative user profile | `reduced` | Existing `animations.profile` writer and settings page selector |
| Baseline rollback profile | `balanced` | GOAL-5 byte-for-byte rollback check |

## Why Balanced Stays Default

`balanced` remains the default because it is the only profile with all of the following evidence:

- GOAL-0 recorded it as the current KDL/QML timing baseline.
- GOAL-5 proved `fast -> balanced` returns `config/niri/tahoe-phase0.kdl` to a byte-for-byte match.
- GOAL-7 added snapshot lifecycle tests for fast toggle and one-frame close snapshot release.
- GOAL-8 kept material strength unchanged because live DRM/TTY render timing was not captured.
- GOAL-9 reduced allocation churn but did not deploy/restart the running compositor, so no live after-RSS win is claimed.

`fast`, `liquid`, and `reduced` remain selectable profiles. They are not the default because they have less live visual and performance evidence than `balanced`.

## Layer Animation Default

`compositorLayerAnimations` remains `false` for new `desktop-settings.json` state. Users can opt in from the Niri animations page.

Reasons:

- The compositor layer animation path has stronger automated lifecycle coverage after GOAL-7, but live DRM/TTY visual acceptance is still partial.
- The active user state may choose `true`; this policy only defines the source default for new or reset shell state.
- Keeping the default off preserves the QML outer animation fallback as the first-run compatibility path.
- The KDL layer animation rules remain present, validated, and ready for opt-in.

## Fallback Retention Plan

Keep these fallback paths:

| Fallback | Keep/Remove | Reason |
| --- | --- | --- |
| QML outer open/close animation when `compositorLayerAnimations=false` | Keep | Primary user rollback path |
| Launchpad QML outer animation | Keep | Not migrated to compositor layer animation |
| Dock, TaskSwitcher, WindowOverview QML path | Keep | Not forced into compositor layer animation |
| TahoeGlass client fallback to BackgroundEffect | Keep | Protocol/fallback lifecycle is separate from motion defaults |
| Thumbnail `WindowPreviewFallback` | Keep | Required when niri thumbnail IPC or image decode fails |
| `reduced` motion profile | Keep | Conservative profile for low-motion preference |

Do not remove any fallback until a later, explicit goal provides live visual/RSS/frame-time evidence and a rollback plan.

## User Rollback Paths

Settings UI:

- Open Niri animations.
- Set `Motion profile` to `Balanced` for the baseline profile.
- Set `Motion profile` to `Reduced` for conservative low-spatial-motion behavior.
- Turn off `使用 compositor layer 动画` to return outer surface open/close to QML fallback.

State file rollback:

```json
{
  "compositorLayerAnimations": false,
  "motionProfile": "balanced"
}
```

KDL/profile rollback through the existing writer:

```text
python3 tahoe-shell/services/niri_settings_tool.py write --config "$HOME/.config/niri/tahoe/config.kdl" --field animations.profile --value balanced --niri-bin /home/wwt/.local/bin/niri
/home/wwt/.local/bin/niri validate --config "$HOME/.config/niri/tahoe/config.kdl"
```

## Maintenance Rules

- Do not introduce a profile JSON file or component-private motion token file.
- Do not let QML components write niri KDL directly.
- Keep `Motion.js` profile names synchronized with `niri_settings_tool.py`.
- Keep `DesktopSettings.qml` source defaults aligned with this document.
- If the default `compositorLayerAnimations` value changes to `true`, update this document, the GOAL acceptance record, and tests in the same change.
- If a fallback is removed, document the measured evidence, affected surfaces, and user rollback path in a new goal.
