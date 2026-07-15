# Dynamic Island V2 Preview (T10)

Non-production static preview for the V2 visual system.

## Purpose

- Freeze the “dark focus glass” direction before production scene rewrites (T11–T19).
- Share one color owner (`SettingsTheme.js` island tokens).
- Share V2 motion/geometry tokens (`DynamicIslandMotion.js` `v2*` exports).
- Provide mock presentation models for every core state.

## Launch

From the repository root:

```bash
qml tahoe-shell/preview/dynamic-island-v2/DynamicIslandV2Preview.qml
# or
qmlscene tahoe-shell/preview/dynamic-island-v2/DynamicIslandV2Preview.qml
```

Toolbar chips switch light/dark shell, bright/dark wallpaper simulation, zh/en locale, and logical viewport width (1366 / 1920 / 2048).

## Guarantees

| Rule | Status |
| --- | --- |
| Not imported by `shell.qml` | required |
| No IPC registration | required |
| No Notifications / MPRIS / niri socket | required |
| No `DynamicIslandTheme.js` | required |
| No eighth glass material | required |
| Production Overlay/Content unchanged in T10 | required |

## Token owners

- Colors: `components/settings/SettingsTheme.js` (`island*`)
- Motion / radius / geometry baselines: `components/DynamicIslandMotion.js` (`v2*`)
- Mock data: `mock/MockStates.js`

## Offline matrix

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider \
  tahoe-shell/tests/test_dynamic_island_v2_preview.py
```

Artifacts: `docs/visual-baselines/dynamic-island-v2-preview/`.
