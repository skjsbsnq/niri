from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "services" / "autostart_manager.py"

spec = importlib.util.spec_from_file_location("autostart_manager", HELPER_PATH)
autostart = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(autostart)


def write_desktop(path: Path, *, name: str = "Example", exec_line: str = "example", hidden: str | None = None, extra: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        f"Name={name}",
        f"Exec={exec_line}",
    ]
    if hidden is not None:
        lines.append(f"Hidden={hidden}")
    if extra:
        lines.extend(extra.strip().splitlines())
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def configure_env(monkeypatch, tmp_path):
    home = tmp_path / "home"
    config_home = home / ".config"
    system_config = tmp_path / "etc-xdg"
    data_home = home / ".local" / "share"
    data_system = tmp_path / "usr-share"

    for path in (config_home, system_config, data_home, data_system):
        path.mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config_home))
    monkeypatch.setenv("XDG_CONFIG_DIRS", str(system_config))
    monkeypatch.setenv("XDG_DATA_HOME", str(data_home))
    monkeypatch.setenv("XDG_DATA_DIRS", str(data_system))
    monkeypatch.setenv("XDG_CURRENT_DESKTOP", "niri")

    return {
        "home": home,
        "config_home": config_home,
        "system_config": system_config,
        "data_home": data_home,
        "data_system": data_system,
    }


def test_list_merges_user_override_and_reports_validation(monkeypatch, tmp_path):
    env = configure_env(monkeypatch, tmp_path)
    write_desktop(env["system_config"] / "autostart" / "org.example.Chat.desktop", name="Chat", exec_line="chat")
    write_desktop(
        env["config_home"] / "autostart" / "org.example.Chat.desktop",
        name="Chat",
        exec_line="chat",
        hidden="true",
    )
    (env["config_home"] / "autostart" / "broken.desktop").write_text("[Desktop Entry]\nName=Broken\n", encoding="utf-8")

    payload = autostart.list_autostart()
    by_id = {row["desktopId"]: row for row in payload["entries"]}

    assert payload["schemaVersion"] == 1
    assert by_id["org.example.Chat.desktop"]["source"] == "user-override"
    assert by_id["org.example.Chat.desktop"]["status"] == "disabled"
    assert by_id["org.example.Chat.desktop"]["hidden"] is True
    assert by_id["broken.desktop"]["status"] == "invalid"
    assert "missing Exec" in by_id["broken.desktop"]["validationIssues"]


def test_disable_system_entry_writes_hidden_user_override(monkeypatch, tmp_path):
    env = configure_env(monkeypatch, tmp_path)
    write_desktop(env["system_config"] / "autostart" / "org.example.Sync.desktop", name="Sync", exec_line="sync")

    result = autostart.set_enabled("org.example.Sync.desktop", False)
    user_file = env["config_home"] / "autostart" / "org.example.Sync.desktop"
    text = user_file.read_text(encoding="utf-8")

    assert result["status"] == "ok"
    assert "Hidden=true" in text
    assert "Exec=sync" in text
    assert autostart.list_autostart()["entries"][0]["status"] == "disabled"


def test_enable_user_override_preserves_file_and_unhides(monkeypatch, tmp_path):
    env = configure_env(monkeypatch, tmp_path)
    user_file = env["config_home"] / "autostart" / "org.example.Agent.desktop"
    write_desktop(user_file, name="Agent", exec_line="agent", hidden="true", extra="OnlyShowIn=niri;")

    result = autostart.set_enabled("org.example.Agent.desktop", True)
    text = user_file.read_text(encoding="utf-8")

    assert result["enabled"] is True
    assert "Hidden=false" in text
    assert "OnlyShowIn=niri;" in text
    assert "X-GNOME-Autostart-enabled=true" in text


def test_add_application_copies_xdg_desktop_entry(monkeypatch, tmp_path):
    env = configure_env(monkeypatch, tmp_path)
    source = env["data_home"] / "applications" / "org.example.Editor.desktop"
    write_desktop(source, name="Editor", exec_line="editor %U", extra="Icon=editor")

    result = autostart.add_application("org.example.Editor")
    target = env["config_home"] / "autostart" / "org.example.Editor.desktop"
    text = target.read_text(encoding="utf-8")

    assert result["status"] == "ok"
    assert result["desktopId"] == "org.example.Editor.desktop"
    assert "Exec=editor %U" in text
    assert "Hidden=false" in text
    assert "X-GNOME-Autostart-enabled=true" in text


def test_set_desktop_key_inserts_inside_desktop_entry_group():
    text = "[Desktop Entry]\nType=Application\nName=App\n\n[Other]\nHidden=true\n"
    updated = autostart.set_desktop_key(text, "Hidden", "false")

    assert "[Desktop Entry]\nType=Application\nName=App\n\nHidden=false\n[Other]" in updated
