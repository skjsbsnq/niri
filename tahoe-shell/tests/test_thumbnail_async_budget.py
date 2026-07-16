from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ThumbnailAsyncBudgetContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_provider_owns_overview_budget_and_cancellation(self) -> None:
        provider = self.read("services/ThumbnailProvider.qml")
        for needle in (
            "property int overviewBatchLimit: 8",
            "property int overviewMinIntervalMs: 48",
            "function cancelRequests(reason)",
            'hasOnlyOverviewRequester(state.pendingRequesters)',
            'requesterKey(reason) === "window-overview"',
        ):
            self.assertIn(needle, provider)

        self.assertEqual(provider.count("Process {"), 1)

    def test_overview_defers_capture_until_enter_flight_settles(self) -> None:
        overview = self.read("components/WindowOverview.qml")
        open_prefix = overview.split("onWindowChoicesChanged", 1)[0]
        self.assertNotIn("requestVisibleThumbnails(false);", open_prefix)
        self.assertIn(
            'onFlightPhaseChanged: if (open && flightPhase === "open") requestVisibleThumbnails(false)',
            overview,
        )
        self.assertIn('thumbnailProvider.cancelRequests("window-overview")', overview)
        self.assertNotIn("niri msg window-thumbnail", overview)


if __name__ == "__main__":
    unittest.main()
