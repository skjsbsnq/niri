#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT/niri"

cargo test -p niri minimize_restore_with_rect
cargo test -p niri genie_
cargo test -p niri foreign_toplevel_set_rectangle_tracks_layer_surface_rect
cargo test -p niri xdg_toplevel_set_minimized_minimizes_window

cat <<'CHECKLIST'

Manual Genie minimize/restore visual matrix:

1. floating window: minimize and restore from Dock icon; no jump, natural icon-directed shrink/expand.
2. scrolling window: same check in a normal column; no extra horizontal movement unless focus must switch columns.
3. multi-output: Dock rect on the same output animates; rect from another output falls back without a bad target jump.
4. fractional scale: repeat at 125% and 150%; no 1 px end-frame snap.
5. CSD shadow: terminal/browser with client shadow keeps shadow aligned through the animation.
6. SSD or borderless: no black edges or stale borders.
7. minimized restore: restore an already minimized window from Dock; it must not flash at full size first.
8. rapid repeated clicks: minimize/restore/minimize quickly; final IPC state and visibility must match the last click.
9. Dock restart: restart Quickshell/Tahoe Dock, then repeat; stale foreign-toplevel rectangles must not be reused.
10. performance: enable niri debug damage if needed and confirm the damaged area follows the window/target union, not the whole output.

CHECKLIST
