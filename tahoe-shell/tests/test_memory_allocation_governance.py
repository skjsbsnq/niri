from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_ROOT = REPO_ROOT / "tahoe-shell"
NIRI_ROOT = REPO_ROOT / "niri"


class MemoryAllocationGovernanceTests(unittest.TestCase):
    def read_repo(self, relative: str) -> str:
        return (REPO_ROOT / relative).read_text(encoding="utf-8")

    def read_shell(self, relative: str) -> str:
        return (SHELL_ROOT / relative).read_text(encoding="utf-8")

    def test_xray_subregion_damage_reuses_render_cache_storage(self) -> None:
        text = self.read_repo("niri/src/render_helpers/xray.rs")

        self.assertIn("struct XrayElementCache", text)
        self.assertIn("filtered_damage: Vec<Rectangle<i32, Physical>>", text)
        self.assertIn("get_or_insert::<RefCell<XrayElementCache>", text)
        self.assertNotIn("FIXME: avoid reallocating a fresh Vec here somehow.", text)
        self.assertIsNone(
            re.search(r"let\s+mut\s+filtered_damage\s*=\s*Vec::new\(\)", text)
        )

    def test_thumbnail_provider_keeps_single_cursor_backed_queue(self) -> None:
        text = self.read_shell("services/ThumbnailProvider.qml")

        self.assertIn("property int queueHead", text)
        self.assertIn("function compactQueueStorage()", text)
        self.assertIn("root.queue.push(key)", text)
        self.assertNotIn("root.queue = root.queue.concat([key])", text)
        self.assertNotIn("root.queue = root.queue.slice(1)", text)
        self.assertNotIn("copyObject(root.cache)", text)
        self.assertNotIn("copyObject(root.queuedKeys)", text)
        self.assertIn("thumbnailProcess.command", text)
        self.assertIn("niri msg --json window-thumbnail", text)
        self.assertIn("$XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png", text)

    def test_snapshot_lifecycle_regression_tests_remain_present(self) -> None:
        text = (NIRI_ROOT / "src/tests/layer_shell.rs").read_text(encoding="utf-8")

        self.assertIn(
            "layer_animation_fast_toggle_settles_without_residual_snapshots",
            text,
        )
        self.assertIn(
            "layer_close_snapshot_releases_one_frame_after_duration",
            text,
        )


if __name__ == "__main__":
    unittest.main()
