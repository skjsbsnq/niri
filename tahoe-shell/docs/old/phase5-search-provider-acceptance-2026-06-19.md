# Tahoe Daily Desktop Phase 5 Acceptance

Date: 2026-06-19

Scope: Phase 5 from `sequential-daily-desktop-roadmap-2026-06-19.md`: move Spotlight to a unified search provider model and extend it beyond app launch without changing the existing launch/close behavior.

## Implementation

- Added `tahoe-shell/services/Search.qml`.
  - Provides a unified result shape with `id`, `title`, `subtitle`, `icon`, `kind`, `score`, and `activate()`.
  - Merges, sorts, limits, and de-duplicates provider results by stable result id.
  - Adds providers for applications, screenshot action, calculator expressions, explicit command prefixes, and settings entries.
- Updated `tahoe-shell/components/Spotlight.qml`.
  - Reads search results from `Search.qml` instead of directly combining `Apps.qml` and `Screenshot.qml`.
  - Keeps Enter activation, Escape close, outside-click close, and shortcut buttons.
  - Shows result subtitle text so non-app providers are identifiable without adding a new layout surface.
- Updated `tahoe-shell/components/Screenshot.qml`.
  - Keeps the old `resultType`, `name`, and `genericName` fields.
  - Adds `kind`, `title`, `subtitle`, and `score` so the screenshot action is a provider-compatible result.
- Updated `tahoe-shell/shell.qml`.
  - Instantiates one shared `Search` service at the shell root.
  - Passes it to each per-screen `Spotlight` instance.

## Provider Notes

- Application results continue to use the existing `Apps.qml.spotlightResults()` search path and `Apps.qml.launchApp()` activation path.
- Screenshot activation still routes through `Screenshot.qml.activateResult()`.
- Calculator results use a small local arithmetic parser, not `eval`; activation copies the result to the clipboard through `wl-copy`.
- Command results only appear for explicit `>` or `!` prefixes and run through `sh -lc` on activation.
- Settings results are bounded static entries. Activation tries the relevant desktop settings command or tool if it is installed.
- File search is intentionally not implemented in this phase. The roadmap calls for evaluating `fd`, `locate`, and tracker performance/privacy before adding a file provider, so this phase avoids any synchronous file scanning.

## Acceptance

- Existing app search remains backed by `Apps.qml`; pressing Enter activates the first provider result through the same Spotlight key path.
- Escape and outside-click closing remain handled by `Spotlight.qml` and were not moved into a provider.
- Provider expansion is bounded and synchronous only for cheap providers: static settings, screenshot keyword matching, command-prefix detection, calculator parsing, and the existing app list search. No slow file provider was introduced.
- Sorting is stable by score, title, and original provider order; duplicate ids are removed before limiting.
- Result activation is centralized in `Search.qml.activateResult()`, while each result still exposes an `activate()` function for provider-model compatibility.

## Runtime Checks

- `git diff --check -- tahoe-shell/services/Search.qml tahoe-shell/components/Spotlight.qml tahoe-shell/components/Screenshot.qml tahoe-shell/shell.qml`: exited `0`.
- `bash scripts/check-tahoe-glass-guardrails.sh`: exited `0`.
- `bash scripts/check-submodules.sh`: exited `0`.
  - The script still prints git's `submodule` usage during its dry-run probe, then continues and exits `0`; this is pre-existing script behavior.
- Temporary QML load:
  - `timeout 8s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell`
  - Reached `Configuration Loaded`; exit `124` was from `timeout`.
  - Existing warnings remained: duplicate Behavior interceptor warnings, `Qt.application.font` read-only warning, notification daemon conflict during temp load, and portal app-id warning. No `Search`, `Spotlight`, or screenshot provider parse/load failure appeared.
- Live deploy:
  - `diff -rq /home/wwt/niri/tahoe-shell /home/wwt/.config/quickshell/tahoe` initially showed only stage/documentation differences, including missing `services/Search.qml`.
  - `rsync -a /home/wwt/niri/tahoe-shell/ /home/wwt/.config/quickshell/tahoe/` synced the live Tahoe Quickshell config without deleting any extra live files.
  - Restarted the Tahoe Quickshell instance: killed old instance `m9m1aubugt` / PID `75514`, then launched `/home/wwt/.config/quickshell/tahoe` as new instance `fyx1jocugt` / PID `90663`.
  - `quickshell ipc -p /home/wwt/.config/quickshell/tahoe show` listed the existing `tahoe` IPC target after restart.
  - Startup logs scanned `/home/wwt/.config/quickshell/tahoe/services/Search.qml`; no startup parse error for the new service appeared.

## Residual Risk

- Physical typing smoke was not automated because there is no Wayland input automation tool installed in this environment.
- The stage 5 implementation does not deploy a real Tahoe Settings page; settings search entries open the host desktop settings tools until phase 6 provides Tahoe-owned Settings/About surfaces.
