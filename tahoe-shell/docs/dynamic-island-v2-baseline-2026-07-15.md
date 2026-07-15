# Dynamic Island V2 — V1 Runtime and Visual Baseline (T00)

Date: 2026-07-15 (local) / 2026-07-14–15 UTC
Task: T00
Base git SHA: `2f96d003a6741dece84b47dfd5bf736a83289020`
Status: frozen baseline evidence (no production behavior change)

This document is the reproducible V1 baseline for Dynamic Island V2.
Asset root: `tahoe-shell/docs/visual-baselines/dynamic-island-v2-before/`

---

## 1. Environment

| Item | Value |
| --- | --- |
| Repo HEAD | `2f96d003a6741dece84b47dfd5bf736a83289020` |
| Branch | `main` (matches `origin/main` at capture) |
| Quickshell | 0.3.0 (revision `1f9ca7a915619632ff143a5ea0382ee988f4d9c4`, Tahoe fork) |
| niri CLI | 26.04 (`ad948d24`) |
| niri running | Compositor 26.04 (`ad948d24`) |
| Shell config path | `/home/wwt/.config/quickshell/tahoe` |
| Launch | `/home/wwt/.local/bin/quickshell -p /home/wwt/.config/quickshell/tahoe` |
| Output | `eDP-2` (Thermotrex TL160ADMP11-0) |
| Physical mode | 2560×1600 @ 239.998 Hz |
| Logical size | 2048×1280 |
| Scale | 1.25 |
| Appearance | `darkMode=false` (`appearance.json`) |
| Default wallpaper | `/home/wwt/Pictures/1.png` (restored after temporary bright/dark captures) |
| Dynamic Island settings | `enabled=true`; `hideTopbarTime=true`; `leftClickAction=toggle_media`; `rightClickAction=none`; `autoExpandMedia=false`; `hoverExpand=false` |
| DND at session default | `dndEnabled=true` in `~/.local/state/quickshell/by-shell/tahoe/notifications.json` |

Raw environment log: `visual-baselines/dynamic-island-v2-before/logs/environment.txt`

---

## 2. Source vs runtime relationship

Compared `tahoe-shell/` with `~/.config/quickshell/tahoe` (excluding `__pycache__` / `*.pyc`).

| Class | Result |
| --- | --- |
| Critical island production files | **SAME** byte-for-byte (`shell.qml`, `DynamicIsland*.qml`, `TopBar.qml`, …) |
| Content-differing tracked files | **0** |
| Only in runtime | `scripts/check-xwayland-satellite-compat.sh` (declared external deploy overlay from `scripts/check-xwayland-satellite-compat.sh`) |
| Only in source | T00 baseline docs/screenshots/perf artifacts under `docs/` (not yet deployed; docs-only) |

Conclusion: screenshots and IPC were taken from a runtime tree whose production QML matches the repository HEAD.
Detail: `logs/source-runtime-parity-detail.txt`

Note: the research roadmap recorded ~48 historical drifts at audit time. On this T00 capture, production QML parity was clean; remaining drift is docs-only source artifacts plus the single allowed external overlay script.

---

## 3. IPC debug snapshot (resting)

```text
state=resting_time
enabled=true; hideTopbarTime=true; leftClickAction=toggle_media; rightClickAction=none; autoExpandMedia=false; hoverExpand=false
displayText=Wed 07:48 (sample); secondaryText=2026-07-15; progress=-1
targetScreenName=eDP-2; expanded=false
pendingNotificationIds=0; displayingNotificationId=-1
swipeStartProgress=0; swipeProgress=0; swipePreviewWidth=-1; swipeDragging=false; swipeSettling=false
```

Command pattern:

```bash
qs ipc --pid <quickshell-pid> call tahoe dynamicIslandGetState
qs ipc --pid <quickshell-pid> call tahoe dynamicIslandGetDebugSummary
qs ipc --pid <quickshell-pid> call tahoe dynamicIslandGetSettingsSummary
```

---

## 4. Tests at baseline

Full Tahoe suite (from `repo` root):

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tahoe-shell/tests
# 453 passed, 143 subtests passed in 18.62s
```

Dynamic Island module suite:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tahoe-shell/tests/test_dynamic_island_*.py
# 106 passed, 13 subtests passed in 5.23s
```

Logs: `logs/pytest-full.txt`, `logs/pytest-island.txt`

QML harness files present (executed via the Python wrappers above):

- `tst_dynamic_island_manual_notification_queue.qml`
- `tst_dynamic_island_media_hit_testing.qml`
- `tst_dynamic_island_media_interaction_lifecycle.qml`
- `tst_dynamic_island_swipe_click_intent.qml`
- `tst_dynamic_island_visualizer_animation_align.qml`
- `tst_dynamic_island_volume_osd_dedupe.qml`

---

## 5. Quickshell warning baseline

Log source at first capture: `/run/user/1000/quickshell/by-id/c318bv6it/log.log`
Copy: `logs/quickshell-warnings-baseline.txt` (full runtime log path is gitignored as `*.log`; warnings extract is the tracked baseline)

Observed recurring warnings (not introduced by T00):

| Warning | Notes |
| --- | --- |
| `shell.qml[473]: TypeError: Cannot assign to read-only property "font"` | Startup |
| `LockScreen.qml[16]: ReferenceError: lockClock is not defined` | Startup |
| `StartupPage.qml[358]: ReferenceError: addCandidateRow is not defined` | Repeated |
| `qt.qpa.services: Failed to register with host portal ... org.quickshell.tahoe` | Portal app id |
| `quickshell.dbus.properties: Error updating property ... StatusNotifierItem:IconName` | Tray |

No Dynamic Island-specific QML warning was isolated in the baseline log slice.

---

## 6. Screenshots

All captures used `grim -o eDP-2` against the **running** config path `/home/wwt/.config/quickshell/tahoe` (not a separate undeployed tree).
Physical PNG size: 2560×1600 unless noted. Top crops are 2560×300 or 2560×320.

Manifest with SHA-256: `logs/screenshot-manifest.txt`

| Asset | Scene | How produced | Notes |
| --- | --- | --- | --- |
| `01-resting-clock-*` | resting clock | `dynamicIslandShowTime` | Primary resting baseline |
| `02-expanded-summary-*` | expanded summary | `dynamicIslandShowExpandedSummary` | V1 four-tile summary |
| `03-osd-volume-*` | volume OSD | `dynamicIslandShowOsd Volume 0.42` | IPC path uses volume icon `\ue050` (correct for volume) |
| `04-osd-brightness-*` | brightness OSD | **Real backlight change** via `brightnessctl set 65%` → `handleBrightnessChange` / `presentOsdEntry(kind=brightness)` | IPC `dynamicIslandShowOsd` cannot select brightness icon (always volume). Captured with `displayText=亮度`, `progress=0.65`, icon `\ue518`. Brightness restored to 100% after capture |
| `05-workspace-*` | workspace transient | `dynamicIslandShowWorkspace "Workspace 2"` | |
| `06-notification-*` | attempted notif (DND on) | IPC showNotification while DND=true | Stayed `resting_time` — documents DND suppress |
| `06b-notification-real-*` | notify-send while DND on | `notify-send` | Also suppressed |
| `06c-notification-dnd-off-*` | notification compact | Controlled session: DND temporarily false, then restored | **Valid notification visual** |
| `07-*` / `07b-*` | control center + island | `openControlCenter` + expanded summary | `07b` is the successful open |
| `08-media-attempt-*` | media compact attempt | `dynamicIslandShowMedia` | No active MPRIS → remained resting |
| `09-expanded-media-attempt-*` | expanded media attempt | `dynamicIslandShowExpandedMedia` | Without media fell through to expanded_summary |
| `10-current-wallpaper-*` | user wallpaper | default `/home/wwt/Pictures/1.png` | |
| `11-bright-wallpaper-resting-*` | bright wallpaper | temp `assets/backgrounds/monterey.jpg` (mean RGB luminance ≈140.5), then restored | Temporary only |
| `12-dark-wallpaper-resting-*` | dark wallpaper | temp `assets/backgrounds/mac os big sur.jpg` (mean RGB luminance ≈60.3), then restored | Temporary only |

### Known capture limits

- **Single output only:** `eDP-2`. No multi-monitor owner migration, focus jump, or per-output island screenshots were collected.
- **No live media baseline:** No active MPRIS player during capture; `08`/`09` document the no-media fallback, not compact/expanded player chrome.
- **Brightness IPC gap:** `dynamicIslandShowOsd` always routes through the volume icon path. Production brightness visuals must be driven via Controls brightness changes (as done for `04-*`).
- **Scale matrix not expanded:** Only scale 1.25 / logical 2048×1280 was captured live.
- **Old Tide CMake version:** local old tree `CMakeLists.txt` reports `1.0.4`; roadmap prose mentioned ~1.0.11 (likely packaging label). Tree SHA-256 is authoritative.

### Controlled DND session (must not leave user settings changed)

1. Backed up `notifications.json` → `logs/notifications.json.pre-t00`.
2. Wrote `dndEnabled=false`, restarted Quickshell, captured `06c`.
3. Restored backup file and restarted Quickshell.
4. Verified post-restore: `dynamicIslandShowNotification` returns `resting_time` (DND on again).
5. Wallpaper path temporarily changed for `11`/`12`, then `desktop-settings.json` restored from `logs/desktop-settings.json.pre-t00`.

User settings after T00: DND **true**, wallpaper **`/home/wwt/Pictures/1.png`**.

---

## 7. 10-minute idle performance baseline

Directory: `visual-baselines/dynamic-island-v2-before/perf/`

| Field | Value |
| --- | --- |
| Sampling | `ps -o pcpu=,rss=,etime= -p <pid>` every 2s, 300 samples (~600s) |
| Scene | resting_time idle after capture restore |
| Output / scale | eDP-2 / 1.25 |
| Raw log | `perf/quickshell-idle-10m.csv` |
| Meta | `perf/sample-meta.txt` |
| Summary | `perf/summary.md`, `perf/summary.json` |

| metric | value |
| --- | ---: |
| samples | 300 |
| CPU median | **2.2 %** |
| CPU p95 | **7.81 %** |
| CPU mean | 3.10 % |
| CPU min / max | 1.8 % / 11.8 % |
| RSS median | 648812 KiB (**633.61 MiB**) |
| RSS peak | 766648 KiB (**748.68 MiB**) |
| RSS min | 633296 KiB |
| sample window (UTC) | 2026-07-14T23:51:39Z → 2026-07-15T00:01:40Z |
| pid | 81938 |

Gate for later T22/T23 (from roadmap §15.4):

- CPU median ≤ baseline + `max(0.3 pp, baseline × 20%)` → ceiling **2.64 %** (2.2 + max(0.3, 0.44))
- RSS peak ≤ baseline + 12 MiB → ceiling **760.68 MiB**

---

## 8. Tide provenance audit

### 8.1 Local trees

| Tree | Path | Declared version | Tree SHA-256 (sorted file content hashes) | LICENSE SHA-256 |
| --- | --- | --- | --- | --- |
| New Tide | `/home/wwt/Downloads/Tide-island-main (1)/Tide-island-main` | 1.0.21 (`CMakeLists.txt`) | `408db8ee8aa78829755e7a67daea10bcb59a2fe6a7f6ed553e75fafa93dcde93` | `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` |
| Old Tide | `/home/wwt/Downloads/Tide-island-main` | 1.0.4 in `CMakeLists.txt` (roadmap prose said ~1.0.11; treat CMake + tree hash as authoritative) | `a9349c1173141ce37f7c283b9e064da2cc38c00f5fb22cb3e0562e4d3abe0da7` | `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` |

Archive SHA-256:

| Archive | SHA-256 |
| --- | --- |
| `/home/wwt/Downloads/Tide-island-main (1).zip` | `0c423f15cd2f8166f8382aaa933a87755cfd4a45208690380915b0a51b6d73f7` |
| `/home/wwt/Downloads/Tide-island-main.zip` | `fa1072bca5a3cd1d5fc42bf133f73c61ab02cc90cbc36ffda71fa45723b36d89` |

Tree hash method:

```bash
(cd "$ROOT" && find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 sha256sum | sha256sum)
```

LICENSE text is GNU GPL v3 (both trees share the same LICENSE hash).

### 8.2 Upstream source

| Field | Value |
| --- | --- |
| URL | https://github.com/enhaoswen/Tide-island |
| Access date (UTC) | 2026-07-14T23:48:13Z |
| GitHub license metadata | GPL-3.0 |
| Default branch | `main` |
| Latest commit at access | `3826f150a48e902f4bb31daee39b9a6fe6c4798a` — “Release 1.0.21” |
| AUR package | `tide-island` (license field on AUR: `unknown`; Depends includes `quickshell`) |

Local non-git directories **do not** embed a git commit; tree SHA-256 is the authoritative identity for the trees used by this roadmap.
URL alone does not substitute for the local tree hashes above.

### 8.3 Tide-derived production inventory (Tahoe)

Only **explicit Tide comments / “Tide-derived” notes** in production shell code (false positives from `targetIdentity` strings excluded):

| File | Lines | Nature |
| --- | --- | --- |
| `services/DynamicIsland.qml` | 573 | Comment: “matching Tide's sideSwipeVerticalTolerance behaviour” |
| `components/DynamicIslandMediaView.qml` | 8 | Comment: Tide expanded-player layout description |
| `components/DynamicIslandSummaryView.qml` | 8 | Comment: mirrors Tide “custom info” |
| `components/DynamicIslandMotion.js` | 5, 45, 59 | Comments: Tide-derived timings / side-swipe feel / hover timing |

No Tide `LICENSE` file, no Tide C++ backend, and no Tide QML module are present as production dependencies inside `tahoe-shell/`.

### 8.4 Root / Tahoe shell license decision

| Component | License evidence |
| --- | --- |
| `niri/` submodule | GPL-3.0 (`niri/LICENSE`, SHA-256 `e57f1c320b8cf8798a7d2ff83a6f9e06a33a03585f6e065fea97f1d86db84052`) |
| `quickshell/` submodule | LGPL-3.0 primary (`quickshell/LICENSE`) + `LICENSE-GPL` companion |
| `tahoe-shell/` | **No LICENSE file in tree** |
| Repo root | **No top-level LICENSE file** |

**Decision for V2 (T00 freeze):**

1. Tide is **GPL-3.0**. Local LICENSE SHA-256 and upstream metadata agree.
2. V2 continues the roadmap policy: **behavior research + independent rewrite only**. Do not copy Tide QML/C++/backends/private structure into Tahoe.
3. Existing Tahoe island code is treated as **independently authored Tahoe code with residual Tide-inspired comments/timings**, listed above. Those comments are provenance markers, not a license grant to import GPL sources.
4. Because `tahoe-shell/` itself has **no declared SPDX license file**, packaging/distribution license for the shell remains an open product decision **outside** Dynamic Island V2 tasks. For implementation gates:
   - **Unblocked for T01+** under the rewrite-only policy (no GPL Tide code intake).
   - **Blocked for any task that would copy Tide source** until a separate license decision commit exists.
5. This satisfies the roadmap T00 requirement to form an explicit conclusion before T01: **proceed with rewrite-only; do not proceed with Tide code reuse.**

---

## 9. Reproducibility checklist

Another engineer can reproduce by:

1. Check out `2f96d003a6741dece84b47dfd5bf736a83289020` (or later commits that preserve these baseline files).
2. Run the same Quickshell binary path against `~/.config/quickshell/tahoe` after confirming production QML parity with `tahoe-shell/`.
3. Use output `eDP-2` (or record different output/scale if hardware differs).
4. Drive states with `qs ipc --pid <pid> call tahoe dynamicIsland*` and capture with `grim -o <output>`.
5. Compare new screenshots against SHA-256 list in `logs/screenshot-manifest.txt`.
6. Re-run pytest commands in §4.
7. For perf, re-sample with the same `ps` interval and compare to `perf/summary.md`.

---

## 10. Explicit non-changes

T00 did **not** modify:

- Production QML under `components/` / `services/` / `shell.qml`
- niri config
- deploy scripts (`scripts/arch-update.sh` untouched)
- Permanent user DND or wallpaper (restored after controlled captures)

Only documentation and baseline assets under the T00 allowlist were added.
