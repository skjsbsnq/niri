#!/usr/bin/env python3

import json
import re
import subprocess
import sys


REGISTRAR_SERVICE = "com.canonical.AppMenu.Registrar"
REGISTRAR_IFACE = "com.canonical.AppMenu.Registrar"
REGISTRAR_PATHS = (
    "/com/canonical/AppMenu/Registrar",
    "/AppMenu/Registrar",
)
DBUSMENU_IFACE = "com.canonical.dbusmenu"
COMMON_MENU_PATHS = (
    "/MenuBar",
    "/menu",
    "/Menu",
    "/com/canonical/menu",
    "/com/canonical/MenuBar",
)
BUSCTL_TIMEOUT = 0.8
MAX_ITEMS = 64


def result(**kwargs):
    base = {
        "registrarAvailable": False,
        "registrarOwner": "",
        "menuService": "",
        "menuPath": "",
        "items": [],
        "status": "未检测",
        "detail": "",
    }
    base.update(kwargs)
    print(json.dumps(base, ensure_ascii=False, separators=(",", ":")))


def busctl_json(*args):
    output = subprocess.check_output(
        ["busctl", "--user", "--json=short", *args],
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=BUSCTL_TIMEOUT,
    )
    return json.loads(output)


def json_data(value):
    if isinstance(value, dict) and "data" in value:
        return value["data"]
    return value


def first_data(value):
    data = json_data(value)
    if isinstance(data, list) and len(data) == 1:
        return data[0]
    return data


def name_has_owner(name):
    try:
        reply = busctl_json(
            "call",
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            "s",
            name,
        )
        return bool(first_data(reply))
    except Exception:
        return False


def name_owner(name):
    try:
        reply = busctl_json(
            "call",
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetNameOwner",
            "s",
            name,
        )
        owner = first_data(reply)
        return str(owner or "")
    except Exception:
        return ""


def bus_names():
    try:
        data = busctl_json("list")
        return data if isinstance(data, list) else []
    except Exception:
        return []


def object_path(value):
    text = str(value or "")
    return text if text.startswith("/") else ""


def clean_label(text):
    label = str(text or "").replace("__", "\0").replace("_", "").replace("\0", "_")
    return re.sub(r"\s+", " ", label).strip()


def prop_value(props, name, default=None):
    if not isinstance(props, dict) or name not in props:
        return default
    value = props.get(name)
    if isinstance(value, dict) and "data" in value:
        return value.get("data", default)
    return value


def menu_node(raw):
    data = json_data(raw)
    if not isinstance(data, list) or len(data) < 3:
        return None
    try:
        node_id = int(data[0])
    except Exception:
        return None
    props = data[1] if isinstance(data[1], dict) else {}
    children = data[2] if isinstance(data[2], list) else []
    return node_id, props, children


def menu_item(raw, indent=0, group=""):
    node = menu_node(raw)
    if not node:
        return None

    node_id, props, children = node
    item_type = str(prop_value(props, "type", ""))
    if item_type == "separator":
        return {
            "id": node_id,
            "text": "",
            "kind": "separator",
            "enabled": False,
            "indent": indent,
            "group": group,
        }

    label = clean_label(prop_value(props, "label", ""))
    if not label:
        return None

    enabled = bool(prop_value(props, "enabled", True))
    toggle_state = prop_value(props, "toggle-state", -1)
    try:
        toggle_state = int(toggle_state)
    except Exception:
        toggle_state = -1

    return {
        "id": node_id,
        "text": label,
        "kind": "item",
        "enabled": enabled,
        "indent": indent,
        "group": group,
        "icon": str(prop_value(props, "icon-name", "") or ""),
        "toggleType": str(prop_value(props, "toggle-type", "") or ""),
        "checked": toggle_state == 1,
        "hasChildren": len(children) > 0 or str(prop_value(props, "children-display", "")) == "submenu",
    }


def append_item(items, item):
    if not item:
        return
    if item["kind"] == "separator":
        if not items or items[-1].get("kind") == "separator":
            return
    items.append(item)


def flatten_layout(layout_reply):
    data = json_data(layout_reply)
    if not isinstance(data, list) or len(data) < 2:
        return []

    root = menu_node(data[1])
    if not root:
        return []

    _, _, top_children = root
    items = []
    for child in top_children:
        if len(items) >= MAX_ITEMS:
            break

        child_node = menu_node(child)
        if not child_node:
            continue

        child_id, child_props, grand_children = child_node
        child_type = str(prop_value(child_props, "type", ""))
        child_label = clean_label(prop_value(child_props, "label", ""))

        if child_type == "separator":
            append_item(items, {
                "id": child_id,
                "text": "",
                "kind": "separator",
                "enabled": False,
                "indent": 0,
                "group": "",
            })
            continue

        if grand_children:
            if child_label:
                append_item(items, {
                    "id": child_id,
                    "text": child_label,
                    "kind": "header",
                    "enabled": False,
                    "indent": 0,
                    "group": "",
                })
            for grand_child in grand_children:
                if len(items) >= MAX_ITEMS:
                    break
                append_item(items, menu_item(grand_child, 1, child_label))
        else:
            append_item(items, menu_item(child, 0, ""))

    while items and items[-1].get("kind") == "separator":
        items.pop()
    return items


def menu_layout(service, path):
    if not service or not path:
        return []
    try:
        try:
            busctl_json("call", service, path, DBUSMENU_IFACE, "AboutToShow", "i", "0")
        except Exception:
            pass
        reply = busctl_json(
            "call",
            service,
            path,
            DBUSMENU_IFACE,
            "GetLayout",
            "iias",
            "0",
            "2",
            "0",
        )
        return flatten_layout(reply)
    except Exception:
        return []


def menu_from_registrar(window_id):
    if not window_id:
        return "", ""

    try:
        xid = int(window_id)
    except Exception:
        return "", ""

    if xid <= 0:
        return "", ""

    for path in REGISTRAR_PATHS:
        try:
            reply = busctl_json(
                "call",
                REGISTRAR_SERVICE,
                path,
                REGISTRAR_IFACE,
                "GetMenuForWindow",
                "u",
                str(xid),
            )
            data = json_data(reply)
            if isinstance(data, list) and len(data) >= 2:
                service = str(data[0] or "")
                menu_path = object_path(data[1])
                if service and menu_path:
                    return service, menu_path
        except Exception:
            continue

    return "", ""


def normalized_tokens(*values):
    tokens = []
    for value in values:
        text = str(value or "").lower()
        tokens.extend(part for part in re.split(r"[^a-z0-9]+", text) if part)
    return set(tokens)


def candidate_services(app_id, pid):
    candidates = []
    seen = set()
    app_id = str(app_id or "").strip()
    pid = str(pid or "").strip()

    def add(name):
        name = str(name or "").strip()
        if not name or name in seen:
            return
        seen.add(name)
        candidates.append(name)

    if "." in app_id:
        # Do not probe an activatable well-known name unless it is already
        # owned. Calling /MenuBar on a DBusActivatable desktop app starts it.
        owner = name_owner(app_id)
        if owner:
            add(app_id)
            add(owner)

    for row in bus_names():
        if not isinstance(row, dict):
            continue

        row_pid = str(row.get("pid") or "")
        name = str(row.get("name") or "")
        connection = str(row.get("connection") or "")
        process = str(row.get("process") or "")
        has_owner = connection.startswith(":") or (row_pid.isdigit() and int(row_pid) > 0)
        if not has_owner:
            continue

        if pid and row_pid == pid:
            add(name)
            add(connection)

    return candidates


def menu_from_candidates(app_id, pid):
    for service in candidate_services(app_id, pid):
        for path in COMMON_MENU_PATHS:
            items = menu_layout(service, path)
            if items:
                return service, path, items
    return "", "", []


def main():
    window_id = sys.argv[1] if len(sys.argv) > 1 else ""
    pid = sys.argv[2] if len(sys.argv) > 2 else ""
    app_id = sys.argv[3] if len(sys.argv) > 3 else ""

    registrar_available = name_has_owner(REGISTRAR_SERVICE)
    registrar_owner = name_owner(REGISTRAR_SERVICE) if registrar_available else ""

    service = ""
    path = ""
    items = []
    source = ""

    if registrar_available:
        service, path = menu_from_registrar(window_id)
        if service and path:
            items = menu_layout(service, path)
            source = "registrar"

    if not items:
        service, path, items = menu_from_candidates(app_id, pid)
        if items:
            source = "focused-app"

    if items:
        result(
            registrarAvailable=registrar_available,
            registrarOwner=registrar_owner,
            menuService=service,
            menuPath=path,
            items=items,
            status="原生应用菜单可用",
            detail=("registrar" if source == "registrar" else "focused app") + f" -> {service}{path}",
        )
        return

    if registrar_available:
        result(
            registrarAvailable=True,
            registrarOwner=registrar_owner,
            status="AppMenu registrar 在线，但当前窗口没有菜单",
            detail="应用可能未发布 dbus-menu，或 niri 窗口 ID 无法映射到 X11 appmenu window id",
        )
    else:
        result(
            registrarAvailable=False,
            registrarOwner="",
            status="未检测到 AppMenu registrar",
            detail="当前应用未发布可发现的 /MenuBar DBusMenu，或系统未启动 appmenu bridge",
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        result(status="应用菜单检测失败", detail=str(error))
