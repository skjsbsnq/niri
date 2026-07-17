from __future__ import annotations

import importlib.util
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "apps-settings"
PROBE_PATH = ROOT / "services" / "apps_settings_probe.py"


spec = importlib.util.spec_from_file_location("apps_settings_probe", PROBE_PATH)
probe = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(probe)


def completed(command, returncode=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(command, returncode, stdout, stderr)


def configure_fixture_env(monkeypatch, tmp_path):
    empty_data = tmp_path / "empty-data"
    home = tmp_path / "home"
    cache = tmp_path / "cache"
    config = tmp_path / "config"
    for path in (empty_data, home, cache, config):
        path.mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv("XDG_DATA_HOME", str(FIXTURES / "xdg-data"))
    monkeypatch.setenv("XDG_DATA_DIRS", str(empty_data))
    monkeypatch.setenv("XDG_CACHE_HOME", str(cache))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config))
    monkeypatch.setenv("HOME", str(home))


def install_command_fakes(monkeypatch, *, portal=True, xdg_mime=True, flatpak=True, snap=True):
    paths = {
        "busctl": "/mock/bin/busctl" if portal else None,
        "xdg-mime": "/mock/bin/xdg-mime" if xdg_mime else None,
        "flatpak": "/mock/bin/flatpak" if flatpak else None,
        "snap": "/mock/bin/snap" if snap else None,
    }

    def fake_which(name):
        return paths.get(name)

    def fake_run(command, timeout=4, budget=None):
        binary = Path(command[0]).name
        if binary == "busctl" and "status" in command:
            return completed(command, 0 if portal else 1, stdout="portal store\n", stderr="")
        if binary == "busctl" and "Lookup" in command:
            raw = (
                'a{sas} 3 "org.example.Editor" 1 "yes" '
                '"org.example.Flatpak" 1 "yes" "example-snap" 1 "yes"'
            )
            return completed(command, 0, stdout=raw)
        if binary == "flatpak":
            return completed(
                command,
                0,
                stdout=(
                    "[Context]\n"
                    "shared=network;ipc;\n"
                    "sockets=wayland;\n"
                    "[Session Bus Policy]\n"
                    "org.freedesktop.Notifications=talk\n"
                ),
            )
        if binary == "snap":
            return completed(
                command,
                0,
                stdout=(
                    "Interface Plug Slot Notes\n"
                    "network example-snap:network :network manual\n"
                    "camera example-snap:camera - -\n"
                ),
            )
        if binary == "xdg-mime" and command[1:3] == ["query", "default"]:
            return completed(command, 0, stdout="")
        if binary == "xdg-mime" and command[1:2] == ["default"]:
            return completed(command, 0, stdout="")
        return completed(command, 1, stderr="unexpected command")

    monkeypatch.setattr(probe.shutil, "which", fake_which)
    monkeypatch.setattr(probe, "run", fake_run)


def test_ordinary_desktop_app_schema_is_readonly_and_not_enforceable(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch)

    payload = probe.permissions_for("org.example.Editor.desktop")

    assert payload["schemaVersion"] == 1
    assert payload["mode"] == "permissions"
    assert payload["app"]["sandboxType"] == "none"
    assert payload["sandbox"]["type"] == "none"
    assert payload["sandbox"]["sandboxType"] == "none"
    assert payload["sandbox"]["fullyEnforceable"] is False
    assert payload["capability"]["fullyEnforceable"] is False
    assert payload["capability"]["ordinaryAppWarning"] is True
    assert payload["capability"]["canTogglePortalPermissions"] is False
    assert payload["portal"]["status"] == "ok"
    assert payload["portal"]["portalStatus"] == "ok"
    assert payload["portal"]["canWrite"] is False
    assert payload["staticPermissions"] == []
    assert payload["snapConnections"] == []

    assert payload["permissions"]
    for row in payload["permissions"]:
        assert row["control"] == "readonly"
        assert row["canToggle"] is False
        assert row["readOnly"] is True
        assert "普通桌面应用" in row["readOnlyReason"]


def test_flatpak_schema_exposes_runtime_sandbox_and_external_static_permissions(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch)

    payload = probe.permissions_for("org.example.Flatpak.desktop")

    assert payload["app"]["sandboxType"] == "flatpak"
    assert payload["sandbox"]["fullyEnforceable"] is True
    assert payload["sandbox"]["enforcementScope"] == "runtime-sandbox"
    assert payload["capability"]["staticPermissionScope"] == "runtime-metadata"
    assert payload["capability"]["canWriteStaticPermissions"] is False
    assert payload["snapConnections"] == []

    static_ids = {row["id"] for row in payload["staticPermissions"]}
    assert "flatpak:Context:shared" in static_ids
    assert "flatpak:Context:sockets" in static_ids
    for row in payload["staticPermissions"]:
        assert row["control"] == "external"
        assert row["canToggle"] is False
        assert "Flatpak" in row["readOnlyReason"]


def test_snap_schema_exposes_connections_without_treating_them_as_tahoe_switches(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch)

    payload = probe.permissions_for("example-snap_app.desktop")

    assert payload["app"]["sandboxType"] == "snap"
    assert payload["sandbox"]["fullyEnforceable"] is True
    assert payload["staticPermissions"] == []
    assert payload["snapConnections"]
    assert {row["status"] for row in payload["snapConnections"]} == {"connected", "unconnected"}
    for row in payload["snapConnections"]:
        assert row["control"] == "external"
        assert row["canToggle"] is False
        assert "Snap" in row["readOnlyReason"]


def test_portal_store_missing_makes_permission_rows_warning_only(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch, portal=False)

    payload = probe.permissions_for("org.example.Editor.desktop")

    assert payload["portal"]["status"] == "missing"
    assert payload["portal"]["available"] is False
    assert payload["capability"]["portalStatus"] == "missing"
    assert payload["capability"]["defaultControl"] == "warning"
    for row in payload["permissions"]:
        assert row["status"] == "unavailable"
        assert row["control"] == "warning"
        assert row["canToggle"] is False
        assert "portal permission store 不可用" in row["readOnlyReason"]


def test_xdg_mime_missing_is_explicit_in_defaults_schema(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch, xdg_mime=False)

    payload = probe.probe_defaults()

    assert payload["schemaVersion"] == 1
    assert payload["mode"] == "defaults"
    assert payload["status"] == "missing"
    assert payload["xdgMime"]["available"] is False
    assert payload["xdgMime"]["canRead"] is False
    assert payload["xdgMime"]["canWrite"] is False
    assert payload["categories"]
    assert "org.example.Editor.desktop" in payload["desktopMeta"]
    assert payload["fingerprint"]
    assert payload["budget"]["limitMs"] == probe.DEFAULT_PROBE_BUDGET_MS


def test_defaults_fingerprint_changes_with_desktop_and_mimeapps_metadata(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch)
    data_home = Path(FIXTURES / "xdg-data")
    config_home = Path(tmp_path / "config")

    first = probe.defaults_fingerprint()
    mimeapps = config_home / "mimeapps.list"
    mimeapps.write_text("[Default Applications]\ntext/plain=org.example.Editor.desktop\n", encoding="utf-8")
    second = probe.defaults_fingerprint()

    assert first["status"] == "ok"
    assert first["complete"] is True
    assert first["desktopFiles"] >= 3
    assert first["fingerprint"] != second["fingerprint"]
    assert data_home.is_dir()


def test_permission_and_storage_scan_obey_small_budget(monkeypatch, tmp_path):
    configure_fixture_env(monkeypatch, tmp_path)
    install_command_fakes(monkeypatch)
    data_dir = Path(tmp_path / "home" / ".local" / "share" / "org.example.Editor")
    data_dir.mkdir(parents=True)
    for index in range(32):
        (data_dir / f"{index}.dat").write_bytes(b"x" * 32)

    budget = probe.Budget(1)
    budget.deadline = budget.started
    payload = probe.permissions_for("org.example.Editor.desktop", budget_ms=budget)

    assert payload["budget"]["limitMs"] == 1
    assert payload["budget"]["expired"] is True
    assert payload["storage"]["budgetExpired"] is True
    assert any(row["status"] == "unavailable" for row in payload["permissions"])


def test_app_permissions_page_consumes_schema_without_permission_switches():
    text = (ROOT / "components" / "settings" / "pages" / "AppPermissionsPage.qml").read_text(encoding="utf-8")

    for forbidden in ("Switch {", "TahoeSwitch", "Controls.TahoeSwitch"):
        assert forbidden not in text

    assert "permissionCapability" in text
    assert "ordinaryAppWarning" in text
    assert "canToggle" in text
    assert "permissionRowStatusText(modelData)" in text
    assert "controlText(modelData)" in text
    assert "权限不能被 Tahoe 完整强制执行" in text
