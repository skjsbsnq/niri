from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ThumbnailProviderContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_provider_documents_phase3_interface_contract(self) -> None:
        text = self.read("services/ThumbnailProvider.qml")

        for needle in (
            "Public contract:",
            "requestThumbnail(window, maxWidth, maxHeight, reason, force)",
            "Cache key:",
            "$XDG_RUNTIME_DIR/tahoe/window-thumbnails/window-<id>.png",
            "Failure state:",
            "Cleanup:",
            "Do not spawn `niri msg window-thumbnail`",
        ):
            self.assertIn(needle, text)

    def test_window_preview_surfaces_use_shared_provider_and_fallback(self) -> None:
        expected = {
            "components/DockMinimizedWindow.qml": (
                "thumbnailProvider.requestThumbnail",
                "thumbnailProvider.thumbnailStateForWindow",
                "WindowPreviewFallback",
            ),
            "components/TaskSwitcher.qml": (
                "thumbnailProvider.requestThumbnail",
                "thumbnailProvider.requestThumbnails",
                "thumbnailProvider.thumbnailStateForWindow",
                "WindowPreviewFallback",
            ),
            "components/WindowOverview.qml": (
                "thumbnailProvider.requestThumbnail",
                "thumbnailProvider.requestThumbnails",
                "thumbnailProvider.thumbnailStateForWindow",
                "WindowPreviewFallback",
            ),
        }

        for relative, needles in expected.items():
            text = self.read(relative)
            for needle in needles:
                self.assertIn(needle, text, relative)
            self.assertNotIn("niri msg window-thumbnail", text, relative)
            self.assertNotIn("window-thumbnail --id", text, relative)

    def test_thumbnail_generation_request_is_only_in_provider(self) -> None:
        scanned = [
            path
            for directory in ("components", "services")
            for path in (ROOT / directory).rglob("*.qml")
        ]
        offenders = []
        for path in scanned:
            if path.relative_to(ROOT).as_posix() == "services/ThumbnailProvider.qml":
                continue
            text = path.read_text(encoding="utf-8")
            if re.search(r"\bniri\s+msg\b.*\bwindow-thumbnail\b.*\b(--id|--path|--max-width)\b", text):
                offenders.append(path.relative_to(ROOT).as_posix())

        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
