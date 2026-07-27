# Tahoe cross-process contracts

This document is the single index of the three IPC / protocol channels that
tie the Tahoe shell (`tahoe-shell/`), the Quickshell client fork, and the
niri compositor fork together. It is deliberately a **field and dependency
map**, not a rewrite of the wire specs.

**Conflict rule:** if anything in this document disagrees with the
authoritative source of a channel, the source wins and this file is what
needs fixing:

| Channel | Authoritative source |
|---|---|
| tahoe_glass requests / enums | [`tahoe-glass-v1.xml`](./tahoe-glass-v1.xml) |
| event-stream / action schemas | `niri/niri-ipc/src/lib.rs` (`Event`, `Action`, `Window`, …) |
| shell behaviour described here | the cited QML/JS files themselves |

When any of the three channels changes, update this file in the same
serial roadmap task so the next reader does not have to rediscover the
coupling the hard way.

---

## Channel overview

| # | Channel | Transport | Direction | Owner of schema | Primary consumers |
|---|---|---|---|---|---|
| 1 | **tahoe_glass_v1** | Wayland private protocol | shell → compositor (requests only; no events yet) | [`protocols/tahoe-glass-v1.xml`](./tahoe-glass-v1.xml) (authoritative); copies in `niri/resources/` and `quickshell/src/wayland/tahoe_glass/` | quickshell `TahoeGlass*` QML types; niri `niri/src/protocols/tahoe_glass.rs` + render helpers |
| 2 | **niri event-stream** | `niri msg --json event-stream` (newline-delimited JSON over a long-lived process) | compositor → shell | `niri/niri-ipc/src/lib.rs` `Event` enum | `tahoe-shell/services/Windows.qml` |
| 3 | **niri msg action** | one-shot `niri msg action <verb> …` (and a few non-action `niri msg` queries) | shell → compositor | `niri/niri-ipc/src/lib.rs` `Action` enum + CLI | `Windows.qml` `action()`, `CommandRunner.qml`, `Power.qml`, `NiriSettings.qml`, `ThumbnailProvider.qml` |

A fourth, related but **not Tahoe-private** channel is also load-bearing for
genie minimize and must be kept in the same mental model:

| # | Channel | Transport | Notes |
|---|---|---|---|
| 4 | **wlr foreign-toplevel `set_rectangle`** | Wayland (wlr-foreign-toplevel-management) | Dock publishes the genie target rect via `Toplevel.setRectangle(sourceWindow, x, y, w, h)`. Protocol is wlr's; Tahoe policy lives in `DockRectanglePublisher.js`. niri handles it in `niri/src/handlers/mod.rs` (`ForeignToplevelHandler::set_rectangle`) which writes `Mapped::set_foreign_toplevel_rect_hint` (`ForeignToplevelRectHint`). |

There is currently **no compositor→shell animation-completion event** on
channel 1. The only roadmap item that would need a new protocol event is
S-L10 (`transform_done`); everything else in the 2026-07-27 roadmap stays
inside the existing three channels.

---

## 1. tahoe_glass_v1

### Source of truth and copies

```
protocols/tahoe-glass-v1.xml                         ← authoritative (this repo)
niri/resources/tahoe-glass-v1.xml                    ← niri wayland-scanner input
quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml ← quickshell wl_proto input
```

Gate: `bash scripts/check-protocol-sync.sh` (also *printed* from
`scripts/check-submodules.sh`, which is a diagnostic aggregator and always
exits 0 — scrape `PROTOCOL_SYNC_EXIT` or call the leaf script to gate).
All three copies must be byte-identical (sha256). Drift is always a bug —
never "niri is ahead, we'll catch up later".

**Multi-repo edit flow** (easy to get wrong — the two consumer paths live
in **separate git repositories** tracked as submodules):

1. Edit `protocols/tahoe-glass-v1.xml` in the superproject.
2. Copy identical bytes into both submodule paths.
3. `bash scripts/check-protocol-sync.sh` → `IN_SYNC`.
4. **Commit + push inside `niri/`**, then **commit + push inside
   `quickshell/`** (each is its own remote).
5. In the superproject, advance both submodule pointers and commit
   `protocols/` + the pointer bump together.
6. Rebuild both forks (scanner / `wl_proto` codegen) and update any
   changed rows in this document in the same superproject commit.

Skipping step 4 leaves the forks unshipped even if the superproject looks
green. Skipping step 5 leaves CI / other machines on the old submodule
SHAs.

Current version: **v4** (manager and surface interfaces are kept in
lockstep so surface objects inherit the bound manager version and can
negotiate the presentation-transform requests added in v4).

### Interfaces and requests

Summary only — the XML is authoritative if this table drifts.

`tahoe_glass_manager_v1`

| Request | Args | Semantics |
|---|---|---|
| `destroy` | — | destructor |
| `get_tahoe_glass_surface` | `id: new_id`, `surface: wl_surface` | create the per-surface controller; pending state commits with the next `wl_surface.commit` |

`tahoe_glass_surface_v1`

| Request | Since | Args (summary) | Semantics |
|---|---|---|---|
| `destroy` | 1 | — | destructor |
| `set_region` | 1 | `id, x, y, w, h, r_tl/tr/br/bl, material, flags, interaction, material_alpha` | upsert a rounded glass region in surface-local logical px; `interaction`/`material_alpha` are 0..1 fixed |
| `remove_region` | 1 | `id` | drop one pending region |
| `clear_regions` | 1 | — | drop all pending regions |
| `set_transform` | 4 | `x, y, scale_x, scale_y` | set presentation transform immediately (cancels running anim); identity = `(0,0,1,1)` |
| `set_transform_target` | 4 | `x, y, scale_x, scale_y, curve, p1..p5` | animate presentation transform to target; spring carries velocity on retarget |
| `set_region_morph` | 4 | `region_id, curve, p1..p5` | on the commit that changes that region's rect, morph from old visual footprint to identity |

Enums: `error.invalid_region`; `region_flags` bitfield (`blur=1`, `shadow=2`,
`clip=4`); `transform_curve` (`spring=0`, `eased=1`) with p1..p5 laid out
as damping/stiffness/epsilon (spring) or duration-ms + cubic-bezier
(eased).

### Commit / double-buffer contract (load-bearing)

- Every region and transform request is **double-buffered** and applied on
  the next `wl_surface.commit` of the associated surface.
- At most one of `set_transform` / `set_transform_target` /
  `set_region_morph` takes effect per commit; **last one wins**.
- Coordinates are surface-local **logical** pixels. Scales clamp to
  `[0.05, 20]`, translations to `[-16384, 16384]`.
- The presentation transform is **presentation-only**: it must never
  affect input, layout, or the protocol region geometry itself. niri may
  restrict it to layer-shell surfaces.
- **Atomicity requirement (S-H1 / T-17):** region updates and buffer
  attaches that belong to the same visual frame must share one
  `wl_surface.commit`. Today quickshell's polish path can early-commit a
  region change against a stale buffer (`qml.cpp` region rebuild); that
  is the upstream root cause of the mid-animation glass band that
  `42039bb` clamps around. Do not add a parallel commit channel to paper
  over it — fix the existing path.

### Shell-side material / region rules

- Glass region geometry (`x/y/width/height/region*`) must **not** be driven
  by `SpringAnimation` — overshoot lets the region exceed the surface and
  niri rejects / corrupts the texture (guardrail in
  `scripts/check-tahoe-glass-guardrails.sh`).
- QML must not declare bare `BackgroundEffect.blurRegion` for Tahoe
  panels; compositor-owned glass via this protocol is the only path.
- `PanelWindow` files need a `tahoe-*` namespace; `TahoeGlassRegion`
  declarations need material + radius (same guardrail script).

### Known absences

- No `transform_done` / `morph_done` event (S-L10). Shell cannot precisely
  sequence post-animation work off the compositor clock.
- No compositor→client region ack. Clients that need confirmation must
  observe side effects (damage, visual) or stay conservative.

---

## 2. niri event-stream JSON

### Transport

```
niri msg --json event-stream
```

Long-lived process; one JSON value per line after the initial handshake.
Owned by `niri/niri-ipc`. Shell owner: `tahoe-shell/services/Windows.qml`
(`Process` at the bottom of the file, `handleEventLine`).

### Events the shell actually handles today

From `Windows.qml::handleEventLine` (names are the serde externally-tagged
enum variants — the JSON key *is* the variant name):

| Event | Payload fields used by shell | Effect |
|---|---|---|
| `WindowsChanged` | `windows: Window[]` | full replace of IPC window map |
| `WindowOpenedOrChanged` | `window: Window` | upsert one window; may clear others' focus |
| `WindowClosed` | `id: u64` | remove from map / order |
| `WindowFocusChanged` | `id: u64 \| null` | recompute focused flags |
| `WindowFocusTimestampChanged` | `id, focus_timestamp` | MRU ordering input |
| `WindowUrgencyChanged` | `id, urgent` | urgency flag |
| `WindowLayoutsChanged` | `changes: [[id, WindowLayout], …]` | geometry patch (cheaper than full rebuild) |
| `WorkspacesChanged` | `workspaces: Workspace[]` | full workspace baseline |
| `WorkspaceActivated` | `id, focused` | active/focused bits per output |
| `WorkspaceUrgencyChanged` | `id, urgent` | workspace urgency |
| `WorkspaceActiveWindowChanged` | `workspace_id, active_window_id` | per-workspace active window |
| `OverviewOpenedOrClosed` | `is_open` (also accepts camelCase `isOpen`) | shell overview state |

Events that exist in `niri-ipc::Event` but are **ignored** by the shell
today (safe to start using; do not remove from compositor):  
`KeyboardLayoutsChanged`, `KeyboardLayoutSwitched`, `ConfigLoaded`,
`ScreenshotCaptured`, `CastsChanged`, `CastStartedOrChanged`,
`CastStopped`, …

### `Window` fields the shell depends on

Snake_case on the wire (see `Windows.qml` header comment):

| Field | Type | Shell use |
|---|---|---|
| `id` | `u64` | stable key; CLI `--id` for actions; **never** invent from title/app_id |
| `title` | `string?` | labels |
| `app_id` | `string?` | app identity / icons |
| `workspace_id` | `u64?` | workspace membership |
| `is_focused` | `bool` | focus chrome |
| `is_floating` | `bool` | layout cues |
| `is_urgent` | `bool` | urgency chrome |
| `is_minimized` | `bool` | Dock minimized shelf membership (alongside wlr `Toplevel.minimized`) |
| `layout` | `WindowLayout` | tile/window sizes & positions (logical px, may be fractional) |
| `focus_timestamp` | `{secs, nanos}?` | MRU / task switcher |
| `pid` | `i32?` | App menu / window probes (`AppMenu.qml` `activePid`, `CommandRunner.appMenuProbeCommand`) — not diagnostics-only |

Identity rule (R11): pair IPC rows to wlr foreign-toplevel handles by
`Toplevel.identifier` / numeric id — **never** by fuzzy appId/title
match. `DockRectanglePublisher.js` keys candidates by the actual wlr
handle object identity for the same reason.

### `Workspace` fields the shell depends on

| Field | Notes |
|---|---|
| `id` | stable entity key |
| `idx` | per-output user-visible index; **changes on reorder**; OK for `focus-workspace` CLI, not for long-lived identity |
| `name` / output association / active / focused bits | via `WindowModel` helpers |

### Failure / reconnect

On event-stream `onExited` (`Windows.qml`):

- `available` is set `false` and `lastError` may record the exit code.
- `clearIpcWorkspaceBaseline()` drops `ipcWorkspaces` / `workspacesById`
  so a dead stream cannot keep a stale **workspace** focus baseline that
  would mask the Quickshell `WindowManager` fallback before the next
  `WorkspacesChanged`.
- The **window** IPC snapshot (`ipcWindows` / per-window `isFocused`) is
  **not** cleared today. Window focus chrome can therefore remain pinned
  to the last stream state across a dead connection until a new
  `WindowsChanged` / `WindowFocusChanged` arrives, or until wlr
  toplevel state disagrees hard enough in the merge path. Do not
  document or rely on "stream exit clears window focus".

---

## 3. `niri msg action` (and related one-shot queries)

### Transport

```
niri msg action <verb> [flags…]
```

Fire-and-forget from the shell via `Quickshell.execDetached`  
(`Windows.qml::action(args)` concatenates `["niri","msg","action"] + args`).
There is **no completion callback** on this path — success is observed
indirectly through the event-stream (channel 2) or wlr toplevel state.

### Actions the shell issues today

| Caller | argv after `niri msg action` | When it runs |
|---|---|---|
| `Windows.qml::minimize` | `minimize-window --id <id>` | **fallback only** — when the window has no wlr `toplevel` handle; production path sets `toplevel.minimized = true` |
| `Windows.qml::restore` | `restore-window --id <id>` | **fallback only** — production path sets `toplevel.minimized = false` (+ `activate`) |
| `Windows.qml::activate` | `focus-window --id <id>` | **fallback only** — production path: if already minimized, only `toplevel.minimized = false` (no `activate()`); otherwise `toplevel.activate()` |
| `Windows.qml::closeWindow` | `close-window --id <id>` | always (no wlr close shortcut used here) |
| `Windows.qml` | `move-window-to-workspace --window-id <id> --focus <bool> <ref>` | move |
| `Windows.qml` | `focus-workspace <label>` | workspace focus |
| `CommandRunner.qml` / `Power.qml` | `quit --skip-confirmation` | session logout |
| `NiriSettings.qml` | `load-config-file [--path <config>]` | live config reload |

Related **non-action** one-shots (still `niri msg`, still one-shot):

| Caller | Command | Purpose |
|---|---|---|
| `ThumbnailProvider.qml` | `niri msg --json window-thumbnail --id … --path … --max-width … --max-height …` | write a thumbnail PNG; 8s `timeout` wrapper |
| `SystemStatus.qml` | `niri msg --json outputs` | health probe |
| (diagnostics) | `niri msg outputs` plain text | resolution scripts |

### Pairing rules with channel 2 and channel 4

- Production minimize/restore/activate prefer the **wlr foreign-toplevel
  handle** (`toplevel.minimized` / `toplevel.activate`). Channel-3 action
  verbs are the no-handle fallback. Both paths must keep using the same
  `Window.id` the event-stream reported whenever an id is required.
- Before minimize (either path), the Dock must have published a fresh
  `set_rectangle` (channel 4) for that wlr handle so niri's genie has a
  target. Publisher policy:
  - only the Dock whose `screen` is the handle's **sole** current screen
    may publish (fail closed on 0 / multi / mismatch);
  - last rectangle wins (wlr protocol rule) — no history;
  - high-frequency geometry is frame-coalesced; minimize/restore clicks
    pass `force: true` to flush immediately
    (`Windows.qml::submitDockRectangle`).
- After minimize, shelf membership is driven by the merge of wlr
  `Toplevel.minimized` and event-stream `is_minimized` — **not** by the
  action's exit status (there is none visible to QML).

### What not to do

- Do not spawn `niri msg window-thumbnail` from UI components other than
  `ThumbnailProvider.qml` (enforced by
  `tests/test_thumbnail_provider_contract.py`).
- Do not add a second shell-side wrapper around `niri msg action` that
  parallels `Windows.qml::action` — extend that helper or
  `CommandRunner` instead (no parallel interfaces).

---

## Cross-channel dependency checklist

Use this when changing any one channel:

1. **Changing `tahoe-glass-v1.xml`**
   - [ ] Edit `protocols/tahoe-glass-v1.xml` first.
   - [ ] Copy identical bytes into both submodule paths.
   - [ ] `bash scripts/check-protocol-sync.sh` → `IN_SYNC`.
   - [ ] Commit+push **niri** submodule, commit+push **quickshell**
         submodule, then advance both pointers in the superproject
         (see multi-repo flow above).
   - [ ] Rebuild niri **and** quickshell (scanner / `wl_proto` codegen).
   - [ ] If adding an event: update this document and the shell handler;
         today there are none.
   - [ ] If touching commit semantics: re-read S-H1 / T-17 (no early
         region-only commit).
   - [ ] On conflict between this summary table and the XML, **trust the
         XML** and fix this file.

2. **Changing `Event` / `Window` / `Workspace` in niri-ipc**
   - [ ] Update `Windows.qml::handleEventLine` and `WindowModel.js`.
   - [ ] Keep snake_case wire names; document any new field here.
   - [ ] Never break `id` stability assumptions for open windows.
   - [ ] Remember stream-exit only clears the workspace baseline, not
         the window snapshot.

3. **Changing `Action` verbs the shell calls**
   - [ ] Grep `tahoe-shell/` for the old verb; migrate every caller in
         the same change (no parallel old/new verb).
   - [ ] Confirm whether the production path is actually wlr (minimize /
         restore / activate) before assuming the action verb is hot.
   - [ ] Confirm the event-stream still surfaces the state the UI needs
         after the action (minimize → `is_minimized`, etc.).

4. **Changing Dock / genie rectangle policy**
   - [ ] `DockRectanglePublisher.js` + niri
         `ForeignToplevelHandler::set_rectangle` /
         `Mapped::set_foreign_toplevel_rect_hint` + r16 genie tests stay
         coherent.
   - [ ] Still fail closed on multi-screen handles.
   - [ ] Still last-rectangle-wins; no side channel.
   - [ ] Production minimize still goes through wlr `toplevel.minimized`
         and still needs a prior rectangle publish.

---

## Related scripts and tests

| Path | Role |
|---|---|
| `scripts/check-protocol-sync.sh` | sha256 **gate** for the three XML copies (exit 0/1/2) |
| `scripts/check-submodules.sh` | diagnostic aggregator; prints protocol-sync + fork-lag; always exits 0 |
| `scripts/check-tahoe-glass-guardrails.sh` | QML/config guardrails for glass usage |
| `scripts/report-fork-lag.sh` | how far the forks lag real upstream (T-01) |
| `tahoe-shell/tests/test_thumbnail_provider_contract.py` | no ad-hoc `window-thumbnail` spawns |
| `niri/src/tests/foreign_toplevel.rs` | `set_rectangle` ownership / 0×0 clear |
| `niri/src/tests/r16_genie_identity.rs` | genie target identity under rectangle updates |
| `niri/src/tests/tahoe_glass.rs` | compositor protocol handler tests |
