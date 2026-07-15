"""T10: Dynamic Island V2 non-production preview + token baseline."""

from __future__ import annotations

import hashlib
import re
import subprocess
import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
PREVIEW_ROOT = SHELL_ROOT / "preview" / "dynamic-island-v2"
THEME = SHELL_ROOT / "components" / "settings" / "SettingsTheme.js"
MOTION = SHELL_ROOT / "components" / "DynamicIslandMotion.js"
SHELL_QML = SHELL_ROOT / "shell.qml"
BASELINE_DOC = SHELL_ROOT / "docs" / "dynamic-island-v2-preview-baseline-2026-07-15.md"
MATRIX_DIR = SHELL_ROOT / "docs" / "visual-baselines" / "dynamic-island-v2-preview" / "matrix"

REQUIRED_SCENES = [
    "ClockScene.qml",
    "CompactMediaScene.qml",
    "OsdScene.qml",
    "NotificationCompactScene.qml",
    "NotificationExpandedScene.qml",
    "ExpandedMediaScene.qml",
    "WorkspaceScene.qml",
    "TimerScene.qml",
]

ISLAND_THEME_FUNCS = [
    "islandTextPrimary",
    "islandTextSecondary",
    "islandTextMuted",
    "islandSurfaceFill",
    "islandSurfaceStroke",
    "islandProgressTrack",
    "islandControlFill",
    "islandRecording",
    "islandCriticalEdge",
]

V2_MOTION_TOKENS = [
    "v2CompactToTransientMs",
    "v2CompactToExpandedMs",
    "v2ExpandedToCompactMs",
    "v2ContentExitMs",
    "v2ContentEnterMs",
    "v2ContentMaxTravelPx",
    "v2RadiusExpandedMin",
    "v2RadiusExpandedMax",
    "v2ClockHeight",
    "v2CompactTopInset",
]

# Wallpaper / shell backgrounds must differ so offline tiles are comparable.
BG_WALLPAPER = {
    "bright": "#d8e2ec",
    "dark": "#1a1c20",
}
BG_SHELL_CHROME = {
    "light": "#ebf5f6f8",
    "dark": "#eb1d1f24",
}
FILL_BY_ROLE = {
    "compact": "#cc10141a",
    "transient": "#d610141a",
    "expanded": "#df10141a",
}
STROKE_BY_ROLE = {
    "compact": "#24ffffff",
    "transient": "#28ffffff",
    "expanded": "#30ffffff",
}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_motion_int(name: str, text: str) -> int:
    match = re.search(rf"var {re.escape(name)}\s*=\s*(-?\d+);", text)
    if not match:
        raise AssertionError(f"missing motion token {name}")
    return int(match.group(1))


def write_capsule_svg(
    path: Path,
    *,
    width: int,
    height: int,
    radius: int,
    fill: str,
    stroke: str,
    label: str,
    secondary: str = "",
    title: str = "",
    wallpaper: str = "dark",
    shell_mode: str = "dark",
    scale: float = 1.0,
    viewport_width: int = 2048,
) -> None:
    text_primary = "#f7f8fa"
    text_secondary = "#aeb6c2"
    safe_label = (
        label.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )
    safe_secondary = (
        secondary.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )
    bg = BG_WALLPAPER[wallpaper]
    chrome = BG_SHELL_CHROME[shell_mode]
    # Scale affects rendered capsule size (logical → CSS px at this scale).
    draw_w = max(1, int(round(width * scale)))
    draw_h = max(1, int(round(height * scale)))
    draw_r = max(1, int(round(radius * scale)))
    pad_top = 28
    chrome_h = max(8, int(round(10 * scale)))
    canvas_h = draw_h + pad_top + chrome_h + 28
    canvas_w = max(draw_w + 40, 220, int(round(min(viewport_width, 480) * 0.25 * scale) + 40))
    cx = (canvas_w - draw_w) // 2
    cy = pad_top + chrome_h + 4
    secondary_svg = ""
    if safe_secondary:
        secondary_svg = (
            f'\n  <text x="{canvas_w / 2}" y="{cy + draw_h / 2 + 11 * scale}" '
            f'text-anchor="middle" font-family="Noto Sans CJK SC, sans-serif" '
            f'font-size="{11 * scale:.1f}" fill="{text_secondary}">{safe_secondary}</text>'
        )
    primary_y = cy + draw_h / 2 + ((4 if not safe_secondary else -4) * scale)
    # Simulated top-bar chrome strip — light vs dark shell must differ in pixels.
    chrome_y = pad_top - 2
    chrome_w = min(canvas_w - 24, max(draw_w + 80, int(round(160 * scale))))
    chrome_x = (canvas_w - chrome_w) // 2
    svg = (
        f'<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas_w}" height="{canvas_h}" '
        f'viewBox="0 0 {canvas_w} {canvas_h}">\n'
        f'  <rect width="100%" height="100%" fill="{bg}"/>\n'
        f'  <rect x="{chrome_x}" y="{chrome_y}" width="{chrome_w}" height="{chrome_h}" '
        f'rx="{chrome_h / 2:.1f}" fill="{chrome}" stroke="#30ffffff" stroke-width="1"/>\n'
        f'  <text x="12" y="14" font-family="Noto Sans CJK SC, sans-serif" font-size="10" '
        f'fill="#7f8996">{title}</text>\n'
        f'  <rect x="{cx}" y="{cy}" width="{draw_w}" height="{draw_h}" rx="{draw_r}" ry="{draw_r}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="1"/>\n'
        f'  <text x="{canvas_w / 2}" y="{primary_y}" text-anchor="middle" '
        f'font-family="Noto Sans CJK SC, sans-serif" font-size="{13 * scale:.1f}" '
        f'font-weight="600" fill="{text_primary}">{safe_label}</text>'
        f"{secondary_svg}\n"
        f'  <text x="12" y="{canvas_h - 6}" font-family="monospace" font-size="9" '
        f'fill="#5f6870">{width}x{height} r{radius} @s{scale} vp{viewport_width} '
        f"{shell_mode}/{wallpaper}</text>\n"
        f"</svg>\n"
    )
    path.write_text(svg, encoding="utf-8")


def maybe_png(svg_path: Path, png_path: Path) -> bool:
    for cmd in (
        ["rsvg-convert", "-o", str(png_path), str(svg_path)],
        ["convert", str(svg_path), str(png_path)],
    ):
        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=30)
            return png_path.is_file()
        except (FileNotFoundError, subprocess.SubprocessError):
            continue
    return False


class DynamicIslandV2PreviewTests(unittest.TestCase):
    def test_preview_tree_exists(self) -> None:
        self.assertTrue((PREVIEW_ROOT / "DynamicIslandV2Preview.qml").is_file())
        self.assertTrue((PREVIEW_ROOT / "DynamicIslandV2Surface.qml").is_file())
        self.assertTrue((PREVIEW_ROOT / "mock" / "MockStates.js").is_file())
        self.assertTrue((PREVIEW_ROOT / "README.md").is_file())
        for name in REQUIRED_SCENES:
            self.assertTrue((PREVIEW_ROOT / "scenes" / name).is_file(), name)

    def test_preview_not_wired_into_production_shell(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        self.assertNotIn("DynamicIslandV2Preview", shell)
        self.assertNotIn("preview/dynamic-island-v2", shell)
        for path in (SHELL_ROOT / "components").rglob("DynamicIsland*.qml"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("preview/dynamic-island-v2", text, path.name)

    def test_preview_has_no_service_or_ipc_hooks(self) -> None:
        preview_files = list(PREVIEW_ROOT.rglob("*.qml")) + list(PREVIEW_ROOT.rglob("*.js"))
        banned = [
            "IpcHandler",
            "NIRI_SOCKET",
            "org.freedesktop.Notifications",
            "Mpris",
            "Quickshell.Services",
            "dynamicIslandGetState",
            "PanelWindow",
            "WlrLayershell",
        ]
        for path in preview_files:
            text = path.read_text(encoding="utf-8")
            for token in banned:
                self.assertNotIn(token, text, f"{path.name} contains {token}")

    def test_no_parallel_theme_file(self) -> None:
        forbidden = list((SHELL_ROOT / "components").rglob("DynamicIslandTheme.js"))
        self.assertEqual(forbidden, [])
        self.assertFalse((PREVIEW_ROOT / "DynamicIslandTheme.js").exists())

    def test_island_theme_tokens(self) -> None:
        text = THEME.read_text(encoding="utf-8")
        for name in ISLAND_THEME_FUNCS:
            self.assertIn(f"function {name}(", text, name)
        self.assertIn("#cc10141a", text)
        self.assertIn("#d610141a", text)
        self.assertIn("#df10141a", text)
        self.assertIn("#f7f8fa", text)
        island_section = text[text.index("Dynamic Island V2 surface tokens") :]
        self.assertNotIn("#b56cff", island_section)

    def test_v2_motion_tokens(self) -> None:
        text = MOTION.read_text(encoding="utf-8")
        for name in V2_MOTION_TOKENS:
            self.assertRegex(text, rf"var {name}\s*=", name)
        self.assertIn("var v2CompactToTransientMs = 240;", text)
        self.assertIn("var v2CompactToExpandedMs = 280;", text)
        self.assertIn("var v2ExpandedToCompactMs = 240;", text)
        self.assertIn("var v2ContentExitMs = 110;", text)
        self.assertIn("var v2ContentEnterMs = 170;", text)
        self.assertIn("var v2ContentMaxTravelPx = 6;", text)
        self.assertIn("var v2RadiusExpandedMin = 28;", text)
        self.assertIn("var v2RadiusExpandedMax = 32;", text)
        self.assertIn("var overlayMorphDuration = 380;", text)

    def test_mock_geometry_within_v2_bands(self) -> None:
        motion = MOTION.read_text(encoding="utf-8")
        mock = (PREVIEW_ROOT / "mock" / "MockStates.js").read_text(encoding="utf-8")
        bands = {
            "clock": (
                parse_motion_int("v2ClockWidthMin", motion),
                parse_motion_int("v2ClockWidthMax", motion),
                parse_motion_int("v2ClockHeight", motion),
                parse_motion_int("v2RadiusCompactClock", motion),
            ),
            "compact_media": (
                parse_motion_int("v2CompactMediaWidthMin", motion),
                parse_motion_int("v2CompactMediaWidthMax", motion),
                parse_motion_int("v2CompactMediaHeight", motion),
                parse_motion_int("v2RadiusCompactMedia", motion),
            ),
            "osd": (
                parse_motion_int("v2OsdWidthMin", motion),
                parse_motion_int("v2OsdWidthMax", motion),
                parse_motion_int("v2OsdHeight", motion),
                parse_motion_int("v2RadiusOsd", motion),
            ),
        }
        # Sample midpoints used by mock constructors.
        samples = {
            "clock": (124, 32, 16),
            "compact_media": (212, 36, 18),
            "osd": (232, 44, 22),
        }
        for kind, (w, h, r) in samples.items():
            wmin, wmax, h_tok, r_tok = bands[kind]
            self.assertGreaterEqual(w, wmin, kind)
            self.assertLessEqual(w, wmax, kind)
            self.assertEqual(h, h_tok, kind)
            self.assertEqual(r, r_tok, kind)
        # Expanded radius samples must sit in 28-32.
        for needle in ("radius: 28", "radius: 30"):
            self.assertIn(needle, mock)
        r_min = parse_motion_int("v2RadiusExpandedMin", motion)
        r_max = parse_motion_int("v2RadiusExpandedMax", motion)
        self.assertEqual(r_min, 28)
        self.assertEqual(r_max, 32)

    def test_mock_states_cover_required_kinds_and_locales(self) -> None:
        mock = (PREVIEW_ROOT / "mock" / "MockStates.js").read_text(encoding="utf-8")
        for kind in (
            "clock",
            "compact_media",
            "osd",
            "notification_compact",
            "notification_expanded",
            "expanded_media",
            "workspace",
            "timer_compact",
            "timer_expanded",
        ):
            self.assertIn(f'kind: "{kind}"', mock, kind)
        self.assertIn('osd("brightness", 0', mock)
        self.assertIn('osd("muted", 0', mock)
        # Locale must thread through allStates.
        self.assertIn("function allStates(localeTag)", mock)
        self.assertIn('compactMedia("playing", tag)', mock)
        self.assertIn('notificationCompact("short", tag)', mock)
        self.assertIn('timer("compact", tag)', mock)
        self.assertIn("matrixCells", mock)
        self.assertIn("geometryBands", mock)

    def test_surface_caps_expanded_radius(self) -> None:
        surface = (PREVIEW_ROOT / "DynamicIslandV2Surface.qml").read_text(encoding="utf-8")
        self.assertIn('fillRole) === "expanded"', surface)
        self.assertIn("Math.min(Math.max(28, r), 32", surface)
        self.assertIn("Theme.islandSurfaceFill", surface)

    def test_expanded_media_no_fake_visualizer(self) -> None:
        media = (PREVIEW_ROOT / "scenes" / "ExpandedMediaScene.qml").read_text(encoding="utf-8")
        self.assertNotIn("visualizer", media.lower())
        self.assertNotIn("Math.sin", media)
        self.assertIn("64", media)
        self.assertIn("36", media)

    def test_osd_uses_horizontal_bar_not_ring(self) -> None:
        osd = (PREVIEW_ROOT / "scenes" / "OsdScene.qml").read_text(encoding="utf-8")
        self.assertNotIn("Canvas", osd)
        self.assertNotIn("arc", osd.lower())
        self.assertIn("mutedLabel", osd)

    def test_clock_has_no_negative_letter_spacing(self) -> None:
        for path in (PREVIEW_ROOT / "scenes").glob("*.qml"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("letterSpacing: -", text, path.name)

    def test_preview_scale_and_locale_controls(self) -> None:
        preview = (PREVIEW_ROOT / "DynamicIslandV2Preview.qml").read_text(encoding="utf-8")
        self.assertIn("SettingsTheme.js", preview)
        self.assertIn("registersIpc: false", preview)
        self.assertIn("isProductionShell: false", preview)
        self.assertIn('action: "s1"', preview)
        self.assertIn('action: "s125"', preview)
        self.assertIn("viewportScale = 1.0", preview)
        self.assertIn("viewportScale = 1.25", preview)

    def test_timer_uses_control_fill_property(self) -> None:
        timer = (PREVIEW_ROOT / "scenes" / "TimerScene.qml").read_text(encoding="utf-8")
        self.assertIn("property color controlFill", timer)
        self.assertIn("color: root.controlFill", timer)
        self.assertIn("pauseLabel", timer)
        self.assertIn("cancelLabel", timer)

    def test_baseline_doc_exists(self) -> None:
        self.assertTrue(BASELINE_DOC.is_file(), "missing T10 baseline doc")

    def test_generate_offline_visual_matrix(self) -> None:
        MATRIX_DIR.mkdir(parents=True, exist_ok=True)
        # Core state tiles — both locales, critical notif, with appearance axes.
        core_specs = [
            ("clock", 124, 32, 16, "compact", {"zh-CN": ("周二  22:31", ""), "en-US": ("Tue  22:31", "")}),
            ("compact-media", 212, 36, 18, "compact", {
                "zh-CN": ("午夜驰骋", "▶"),
                "en-US": ("Midnight Drive", "▶"),
            }),
            ("osd-volume", 232, 44, 22, "transient", {
                "zh-CN": ("音量  72", ""),
                "en-US": ("Volume  72", ""),
            }),
            ("osd-muted", 232, 44, 22, "transient", {
                "zh-CN": ("静音", "0"),
                "en-US": ("Muted", "0"),
            }),
            ("osd-brightness-0", 232, 44, 22, "transient", {
                "zh-CN": ("亮度  0", ""),
                "en-US": ("Brightness  0", ""),
            }),
            ("osd-brightness-100", 232, 44, 22, "transient", {
                "zh-CN": ("亮度  100", ""),
                "en-US": ("Brightness  100", ""),
            }),
            ("notification-short", 320, 64, 22, "transient", {
                "zh-CN": ("信息 · 新消息", "晚上有空吗？"),
                "en-US": ("Messages · New message", "Are you free later?"),
            }),
            ("notification-long", 400, 76, 24, "transient", {
                "zh-CN": ("信息 · 项目同步完成", "夜间构建已发布产物…"),
                "en-US": ("Messages · Project sync", "The overnight build…"),
            }),
            ("notification-critical", 320, 64, 22, "transient", {
                "zh-CN": ("信息 · 新消息", "critical"),
                "en-US": ("Messages · New message", "critical"),
            }),
            ("notification-expanded", 420, 148, 28, "expanded", {
                "zh-CN": ("通知展开 · 操作", "回复  稍后  归档"),
                "en-US": ("Notification expanded", "Reply  Later  Archive"),
            }),
            ("expanded-media", 420, 168, 30, "expanded", {
                "zh-CN": ("霓虹公路", "夜行者"),
                "en-US": ("Neon Highways", "Night Runner"),
            }),
            ("workspace", 156, 36, 18, "transient", {
                "zh-CN": ("2  设计", "● ○ ○"),
                "en-US": ("2  Design", "● ○ ○"),
            }),
            ("timer-compact", 148, 36, 18, "compact", {
                "zh-CN": ("⏱  12:48", ""),
                "en-US": ("⏱  12:48", ""),
            }),
            ("timer-expanded", 360, 144, 30, "expanded", {
                "zh-CN": ("12:48", "进行中"),
                "en-US": ("12:48", "Running"),
            }),
        ]

        # Appearance cross-product for representative compact media tile.
        appearance_axes = []
        for locale in ("zh-CN", "en-US"):
            for mode in ("light", "dark"):
                for wallpaper in ("bright", "dark"):
                    for scale in (1.0, 1.25):
                        for width in (1366, 1920, 2048):
                            appearance_axes.append((locale, mode, wallpaper, scale, width))

        manifest_lines = ["# Dynamic Island V2 preview matrix (offline SVG)", ""]
        digests: dict[str, str] = {}
        rendered = 0

        # Full state × locale on default dark/dark/1.0/2048.
        for name, w, h, r, role, locale_labels in core_specs:
            for locale, (label, secondary) in locale_labels.items():
                tile = f"{name}-{locale}"
                svg_path = MATRIX_DIR / f"{tile}.svg"
                write_capsule_svg(
                    svg_path,
                    width=w,
                    height=h,
                    radius=r,
                    fill=FILL_BY_ROLE[role],
                    stroke=STROKE_BY_ROLE[role],
                    label=label,
                    secondary=secondary,
                    title=tile,
                    wallpaper="dark",
                    shell_mode="dark",
                    scale=1.0,
                    viewport_width=2048,
                )
                digests[tile] = sha256_file(svg_path)
                manifest_lines.append(
                    f"- `{svg_path.name}`  {w}x{h} r{r}  sha256={digests[tile]}"
                )
                png_path = MATRIX_DIR / f"{tile}.png"
                if maybe_png(svg_path, png_path):
                    manifest_lines.append(
                        f"  - png `{png_path.name}` sha256={sha256_file(png_path)}"
                    )
                rendered += 1
                if h >= 96:
                    self.assertLessEqual(r, 32, tile)
                    self.assertLess(r, h / 2, tile)

        # Appearance matrix: same compact-media content, varying axes.
        for locale, mode, wallpaper, scale, vp in appearance_axes:
            label = "午夜驰骋" if locale.startswith("zh") else "Midnight Drive"
            tile = f"appear-media-{locale}-m{mode}-wp{wallpaper}-s{scale}-w{vp}"
            svg_path = MATRIX_DIR / f"{tile}.svg"
            write_capsule_svg(
                svg_path,
                width=212,
                height=36,
                radius=18,
                fill=FILL_BY_ROLE["compact"],
                stroke=STROKE_BY_ROLE["compact"],
                label=label,
                secondary="▶",
                title=tile,
                wallpaper=wallpaper,
                shell_mode=mode,
                scale=scale,
                viewport_width=vp,
            )
            digests[tile] = sha256_file(svg_path)
            manifest_lines.append(
                f"- `{svg_path.name}`  212x36 r18  sha256={digests[tile]}"
            )
            png_path = MATRIX_DIR / f"{tile}.png"
            if maybe_png(svg_path, png_path):
                manifest_lines.append(
                    f"  - png `{png_path.name}` sha256={sha256_file(png_path)}"
                )
            rendered += 1

        # Comparability assertions: opposite axes must not share digests.
        self.assertNotEqual(
            digests["appear-media-zh-CN-mlight-wpbright-s1.0-w2048"],
            digests["appear-media-zh-CN-mdark-wpdark-s1.0-w2048"],
            "light/bright vs dark/dark must differ",
        )
        self.assertNotEqual(
            digests["appear-media-zh-CN-mdark-wpbright-s1.0-w2048"],
            digests["appear-media-zh-CN-mdark-wpdark-s1.0-w2048"],
            "bright vs dark wallpaper must differ",
        )
        self.assertNotEqual(
            digests["appear-media-zh-CN-mdark-wpdark-s1.0-w2048"],
            digests["appear-media-zh-CN-mdark-wpdark-s1.25-w2048"],
            "scale 1.0 vs 1.25 must differ",
        )
        self.assertNotEqual(
            digests["clock-zh-CN"],
            digests["clock-en-US"],
            "zh vs en clock labels must differ",
        )
        self.assertNotEqual(
            digests["notification-short-zh-CN"],
            digests["notification-short-en-US"],
        )
        self.assertIn("notification-critical-zh-CN", digests)

        # light shell chrome vs dark shell chrome differ even on same wallpaper.
        self.assertNotEqual(
            digests["appear-media-en-US-mlight-wpdark-s1.0-w1366"],
            digests["appear-media-en-US-mdark-wpdark-s1.0-w1366"],
        )

        manifest = MATRIX_DIR / "MANIFEST.md"
        manifest.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
        self.assertTrue(manifest.is_file())
        self.assertGreaterEqual(rendered, 14 + 48)  # states×locale + appearance product
        self.assertGreaterEqual(len(list(MATRIX_DIR.glob("*.svg"))), 50)


if __name__ == "__main__":
    unittest.main()
