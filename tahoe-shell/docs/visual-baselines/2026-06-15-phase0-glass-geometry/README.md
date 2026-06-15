# Phase 0 glass geometry visual baseline

Date: 2026-06-15

Purpose: preserve the current rounded-corner / glass geometry failure cases
before compositor-owned Tahoe Glass work starts. These images are the Phase 0
reference set for comparing later namespace, niri blur-region, and private
protocol changes.

## Reference screenshots

| File | Surface | Failure to compare against |
| --- | --- | --- |
| `spotlight-search-halo.png` | Spotlight | Search pill has a blue backing / halo outside the intended rounded pill. |
| `notification-center-rectangular-backing.png` | Notification Center | Rounded panel sits on a visible rectangular blue backing. |
| `control-center-rectangular-backing.png` | Control Center | Rounded panel sits on a visible rectangular blue backing. |

## Asset metadata

| File | Size | SHA-256 |
| --- | --- | --- |
| `spotlight-search-halo.png` | 791x192 | `74570bd2bdcbf17d15ac307a6b122285861e3707ece5c64466908fc92da7aa77` |
| `notification-center-rectangular-backing.png` | 433x212 | `b7ae2355a092fb96a38cf66255ea5b0790c300f520a50adcbcc6b68d2ffe352a` |
| `control-center-rectangular-backing.png` | 406x378 | `e51a32d9d8d88216ae9df043f119808febddc1d402e9701f3c181b4070232200` |

Original local screenshot paths:

- `C:\Users\19180\Pictures\Screenshots\屏幕截图 2026-06-15 222845.png`
- `C:\Users\19180\Pictures\Screenshots\屏幕截图 2026-06-15 222855.png`
- `C:\Users\19180\Pictures\Screenshots\屏幕截图 2026-06-15 222902.png`

## Baseline source state

Captured from the Windows working tree when the baseline was created:

| Item | Value |
| --- | --- |
| Root repo HEAD | `48f91bc888fb` |
| niri submodule HEAD | `39d63f0a5307` |
| Quickshell submodule HEAD | `d99d87d5e5ec` |
| `config/niri/tahoe-phase0.kdl` git blob | `35b6aa5d5d8889b96327df5de90e9cc644bc8feb` |

For a runtime snapshot from inside the Arch VM, run:

```sh
bash scripts/capture-glass-baseline.sh
```

The script records repo/submodule commits, config hashes, niri/quickshell
versions, session environment, and `niri msg outputs` data when niri IPC is
reachable.

Runtime reports are generated under `tahoe-shell/docs/visual-baselines/runtime/`
and are intentionally ignored by git. Commit only curated baseline screenshots
and hand-written baseline notes.

## Acceptance rule for future phases

Before and after each architecture phase, compare the same three surfaces:

- Spotlight search.
- Notification Center.
- Control Center.

A change is not accepted if a rounded glass surface still shows a rectangular
backing from compositor shadow/background-effect geometry.
