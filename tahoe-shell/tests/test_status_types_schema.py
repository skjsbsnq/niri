from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class StatusTypesSchemaTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_status_types_exports_phase1_schema(self) -> None:
        text = self.read("services/StatusTypes.js")

        for state in ("OK", "WARN", "MISSING", "BROKEN", "UNKNOWN"):
            self.assertIn(f'var {state} = "', text)

        for field in ("id", "state", "title", "detail", "impact", "action", "missing", "updatedAt"):
            self.assertIn(f'"{field}"', text)

        for function in (
            "normalizeStatus",
            "fromStatusFields",
            "unknownStatus",
            "normalizeMissing",
            "stateFromActionStatus",
            "isReady",
            "countWarn",
            "countMissing",
        ):
            self.assertIn(f"function {function}(", text)

    def test_services_reuse_status_types(self) -> None:
        expected = {
            "services/CommandRunner.qml": (
                'import "StatusTypes.js" as StatusTypes',
                "StatusTypes.fromStatusFields",
                "StatusTypes.stateFromActionStatus",
            ),
            "services/SystemFeatures.qml": (
                'import "StatusTypes.js" as StatusTypes',
                "StatusTypes.fromStatusFields",
                "STATUS|%s|%s|%s|%s|%s|%s|%s",
            ),
            "services/SystemStatus.qml": (
                'import "StatusTypes.js" as StatusTypes',
                "StatusTypes.normalizeStatus",
                "StatusTypes.countWarn",
                "StatusTypes.countMissing",
            ),
        }

        for relative, needles in expected.items():
            text = self.read(relative)
            for needle in needles:
                self.assertIn(needle, text, relative)

    def test_feature_page_consumes_status_objects(self) -> None:
        text = self.read("components/settings/pages/FeatureProbePage.qml")

        self.assertIn('import "../../../services/StatusTypes.js" as StatusTypes', text)
        self.assertIn("StatusTypes.unknownStatus", text)
        self.assertIn("StatusTypes.availabilityLabel(row.entry)", text)
        self.assertIn("StatusTypes.iconCode(row.entry)", text)
        self.assertNotIn("statusText: page.stateText(modelData.state)", text)
        self.assertNotIn("iconCode: page.stateIcon(modelData.state)", text)


if __name__ == "__main__":
    unittest.main()
