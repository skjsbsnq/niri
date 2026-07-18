from __future__ import annotations

import importlib.util
import json
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parent
TOOL_PATH = ROOT / "services" / "niri_settings_tool.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "niri-settings"
TAHOE_PHASE0 = REPO_ROOT / "config" / "niri" / "tahoe-phase0.kdl"

spec = importlib.util.spec_from_file_location("niri_settings_tool", TOOL_PATH)
assert spec and spec.loader
niri_settings_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(niri_settings_tool)


def read_fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def write_fake_niri(path: Path, exit_code: int, message: str) -> None:
    path.write_text(f"#!/bin/sh\necho {message!r}\nexit {exit_code}\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def shader_block(text: str) -> str:
    start = text.index('custom-shader r#"')
    end = text.index('"#', start) + 2
    return text[start:end]


class NiriSettingsToolTests(unittest.TestCase):
    def test_writable_field_specs_are_an_explicit_whitelist(self) -> None:
        fields = set(niri_settings_tool.WRITABLE_FIELD_SPECS)

        self.assertEqual(len(fields), 72)
        for field in (
            "layout.gaps",
            "glass.panel.refraction",
            "glass.backdrop.lens_depth",
            "blur.saturation",
            "input.touchpad.accel_speed",
            "output.scale",
            "animations.layer_animations_enabled",
            "animations.profile",
            "animations.overview_open_close.epsilon",
        ):
            spec = niri_settings_tool.WRITABLE_FIELD_SPECS[field]
            self.assertEqual(spec["field"], field)
            self.assertIn("kdlPath", spec)
            self.assertIn("range", spec)
            self.assertIn("validation", spec)
            self.assertIn("rollback", spec)

        self.assertFalse(any(field.startswith("binds.") for field in fields))
        self.assertNotIn("glass.panel.xray", fields)
        self.assertNotIn("animations.window_open.duration_ms", fields)

    def test_motion_profile_write_updates_springs_and_layer_rules(self) -> None:
        original = TAHOE_PHASE0.read_text(encoding="utf-8")
        self.assertEqual(niri_settings_tool.read_animations_text(original)["profile"], "balanced")

        fast = niri_settings_tool.update_field(original, "animations.profile", "fast")
        anim = niri_settings_tool.read_animations_text(fast)
        self.assertEqual(anim["profile"], "fast")
        self.assertEqual(anim["actions"]["workspace_switch"], {
            "damping_ratio": 1,
            "stiffness": 860,
            "epsilon": 0.0001,
        })
        # T03: layer-open transform channels ride per-profile main-channel
        # springs; closes stay easing-based.
        self.assertIn("spring damping-ratio=0.9 stiffness=520 epsilon=0.0005", fast)
        self.assertIn("spring damping-ratio=0.95 stiffness=750 epsilon=0.001", fast)
        self.assertIn("opacity-duration-ms 70", fast)
        self.assertIn("transform-duration-ms 140", fast)

        balanced = niri_settings_tool.update_field(fast, "animations.profile", "balanced")
        self.assertEqual(niri_settings_tool.read_animations_text(balanced)["profile"], "balanced")
        self.assertEqual(balanced, original)

    def test_layer_animation_toggle_is_reversible_and_profile_safe(self) -> None:
        original = TAHOE_PHASE0.read_text(encoding="utf-8")
        field = "animations.layer_animations_enabled"
        self.assertTrue(niri_settings_tool.read_animations_text(original)["layerAnimationsEnabled"])

        disabled = niri_settings_tool.update_field(original, field, "false")
        self.assertFalse(niri_settings_tool.read_animations_text(disabled)["layerAnimationsEnabled"])
        self.assertEqual(niri_settings_tool.update_field(disabled, field, "false"), disabled)

        lines = disabled.splitlines(True)
        for group in niri_settings_tool.LAYER_PROFILE_GROUPS:
            rule = niri_settings_tool.find_layer_rule_for_group(lines, group)
            for phase in niri_settings_tool.LAYER_PHASES:
                block = niri_settings_tool.find_layer_phase_block(lines, rule, phase)
                self.assertTrue(niri_settings_tool.phase_has_off(lines, block), f"{group}.{phase}")

        reenabled = niri_settings_tool.update_field(disabled, field, "true")
        self.assertEqual(reenabled, original)

        disabled_fast = niri_settings_tool.update_field(disabled, "animations.profile", "fast")
        anim = niri_settings_tool.read_animations_text(disabled_fast)
        self.assertEqual(anim["profile"], "fast")
        self.assertFalse(anim["layerAnimationsEnabled"])
        enabled_fast = niri_settings_tool.update_field(disabled_fast, field, "true")
        self.assertTrue(niri_settings_tool.read_animations_text(enabled_fast)["layerAnimationsEnabled"])

        disabled_reduced = niri_settings_tool.update_field(disabled, "animations.profile", "reduced")
        reduced_anim = niri_settings_tool.read_animations_text(disabled_reduced)
        self.assertEqual(reduced_anim["profile"], "reduced")
        self.assertFalse(reduced_anim["layerAnimationsEnabled"])

        missing_group = original.replace(
            'match namespace="^tahoe-notification-toast$"',
            'match namespace="^other-toast$"',
            1,
        )
        self.assertFalse(niri_settings_tool.read_animations_text(missing_group)["layerAnimationsEnabled"])
        with self.assertRaises(niri_settings_tool.KdlEditError):
            niri_settings_tool.update_field(missing_group, field, "false")

    def test_motion_profile_reduced_roundtrip_stays_byte_identical(self) -> None:
        original = TAHOE_PHASE0.read_text(encoding="utf-8")

        reduced = niri_settings_tool.update_field(original, "animations.profile", "reduced")
        self.assertEqual(niri_settings_tool.read_animations_text(reduced)["profile"], "reduced")
        # reduced zeroes the transform override channel; the now-inert spring
        # main-channel line is left untouched.
        self.assertIn("transform-duration-ms 0", reduced)
        self.assertIn("spring damping-ratio=0.88 stiffness=500 epsilon=0.001", reduced)

        balanced = niri_settings_tool.update_field(reduced, "animations.profile", "balanced")
        self.assertEqual(niri_settings_tool.read_animations_text(balanced)["profile"], "balanced")
        self.assertEqual(balanced, original)

    def test_motion_profile_write_requires_known_layer_animation_groups(self) -> None:
        original = TAHOE_PHASE0.read_text(encoding="utf-8")
        # T21/T22: process menu lives in the unified `menu` layer-rule; renaming
        # any of its namespaces makes the exact-tuple match fail.
        broken = original.replace('match namespace="^tahoe-process-menu$"', 'match namespace="^tahoe-other-menu$"')

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(broken, "animations.profile", "fast")

        self.assertIn("expected exactly one layer-rule for menu", str(raised.exception))

    def test_layout_write_matches_golden_and_preserves_unmanaged_block(self) -> None:
        original = read_fixture("managed.kdl")
        updated = niri_settings_tool.update_field(original, "layout.gaps", "24")

        self.assertEqual(updated, read_fixture("managed-gaps-24.kdl"))
        self.assertIn('custom-user-token "keep-me"', updated)
        self.assertEqual(
            original[original.index("window-rule {"): original.index("// tahoe-managed: begin animations")],
            updated[updated.index("window-rule {"): updated.index("// tahoe-managed: begin animations")],
        )

    def test_unmarked_target_block_is_rejected_with_recovery_hint(self) -> None:
        text = "\n".join(
            line for line in read_fixture("managed.kdl").splitlines()
            if not line.startswith("// tahoe-managed:")
        ) + "\n"

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(text, "layout.gaps", "24")

        error = str(raised.exception)
        self.assertIn("refusing to edit layout.gaps", error)
        self.assertIn("layout block is not Tahoe-managed", error)
        self.assertIn("Recovery:", error)

    def test_duplicate_target_block_is_rejected(self) -> None:
        text = read_fixture("managed.kdl") + "\nlayout {\n    gaps 4\n}\n"

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(text, "layout.gaps", "24")

        self.assertIn("expected exactly one top-level layout block, found 2", str(raised.exception))

    def test_unknown_and_readonly_fields_are_rejected_before_writes(self) -> None:
        original = read_fixture("managed.kdl")
        for field in (
            "glass.unknown.refraction",
            "glass.panel.xray",
            "binds.Mod+T.action",
            "animations.window_open.duration_ms",
            "input.mouse.accel_speed",
            "variable-refresh-rate",
        ):
            with self.subTest(field=field):
                with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
                    niri_settings_tool.update_field(original, field, "1")
                self.assertIn(f"unsupported field: {field}", str(raised.exception))

    def test_malformed_kdl_is_rejected_before_editing(self) -> None:
        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(read_fixture("malformed-layout.kdl"), "layout.gaps", "24")

        self.assertIn("unterminated top-level layout block", str(raised.exception))

    def test_comments_and_multiline_raw_string_survive_scoped_writes(self) -> None:
        original = read_fixture("comments-and-multiline.kdl")

        layout_updated = niri_settings_tool.update_field(original, "layout.gaps", "18")
        self.assertIn("gaps 18 // user gap comment", layout_updated)
        self.assertIn("off // inline flag comment", layout_updated)
        self.assertEqual(shader_block(original), shader_block(layout_updated))

        anim_updated = niri_settings_tool.update_field(
            original,
            "animations.window_resize.damping_ratio",
            "0.9",
        )
        self.assertIn(
            "spring damping-ratio=0.9 stiffness=700 epsilon=0.0005 // motion comment",
            anim_updated,
        )
        self.assertEqual(shader_block(original), shader_block(anim_updated))

    def test_missing_top_level_block_is_rejected(self) -> None:
        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(read_fixture("missing-blur.kdl"), "blur.passes", "5")

        self.assertIn("expected exactly one top-level blur block, found 0", str(raised.exception))

    def test_missing_child_block_is_created_inside_managed_parent(self) -> None:
        updated = niri_settings_tool.update_field(
            read_fixture("missing-child-block.kdl"),
            "input.touchpad.tap",
            "true",
        )

        self.assertIn("    touchpad {\n        tap\n    }\n", updated)
        self.assertIn("repeat-rate 25", updated)

    def test_output_scale_is_rejected_for_multi_output_layouts(self) -> None:
        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.update_field(read_fixture("multi-output.kdl"), "output.scale", "1.5")

        self.assertIn("expected exactly one top-level output block, found 2", str(raised.exception))

    def test_config_guardrails_require_vrr_off_and_block_broad_namespace(self) -> None:
        base = read_fixture("managed.kdl")
        niri_settings_tool.config_guardrails(base + "\n// variable-refresh-rate\n")
        niri_settings_tool.config_guardrails(base)

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.config_guardrails(base + "\nvariable-refresh-rate\n")
        self.assertIn("must stay disabled", str(raised.exception))

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.config_guardrails(
                base + "\nvariable-refresh-rate on-demand=true\n"
            )
        self.assertIn("must stay disabled", str(raised.exception))

        with self.assertRaises(niri_settings_tool.KdlEditError) as raised:
            niri_settings_tool.config_guardrails(
                base.replace('match namespace="^tahoe-test$"', 'match namespace="^quickshell"')
            )
        self.assertIn('broad namespace="^quickshell"', str(raised.exception))

    def test_cli_successful_write_uses_atomic_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = tmp_path / "config.kdl"
            config.write_text(read_fixture("managed.kdl"), encoding="utf-8")
            fake_niri = tmp_path / "niri-ok"
            write_fake_niri(fake_niri, 0, "config is valid")

            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "write",
                    "--config",
                    str(config),
                    "--field",
                    "layout.gaps",
                    "--value",
                    "24",
                    "--niri-bin",
                    str(fake_niri),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertTrue(payload["ok"])
            self.assertTrue(payload["changed"])
            self.assertEqual(payload["layout"]["gaps"], 24)
            self.assertEqual(config.read_text(encoding="utf-8"), read_fixture("managed-gaps-24.kdl"))
            self.assertEqual(list(tmp_path.glob(".config.kdl.*.tmp")), [])

    def test_validate_failure_preserves_live_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = tmp_path / "config.kdl"
            original = read_fixture("managed.kdl")
            config.write_text(original, encoding="utf-8")
            fake_niri = tmp_path / "niri-fail"
            write_fake_niri(fake_niri, 1, "bad config near layout")

            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "write",
                    "--config",
                    str(config),
                    "--field",
                    "layout.gaps",
                    "--value",
                    "24",
                    "--niri-bin",
                    str(fake_niri),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            payload = json.loads(result.stdout)
            self.assertFalse(payload["ok"])
            self.assertIn("niri validate failed", payload["error"])
            self.assertIn("bad config near layout", payload["error"])
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            self.assertEqual(list(tmp_path.glob(".config.kdl.*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
