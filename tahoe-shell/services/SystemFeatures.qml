pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var commandRunner
    property var items: []
    property var itemMap: ({})
    property bool refreshing: false
    property int revision: 0
    property string lastUpdatedText: "尚未检测"

    function refresh() {
        if (probe.running)
            return;
        root.refreshing = true;
        probe.running = true;
    }

    function item(id) {
        return root.itemMap[String(id || "")] || null;
    }

    function state(id) {
        var value = item(id);
        return value ? String(value.state || "unknown") : "unknown";
    }

    function detail(id) {
        var value = item(id);
        return value ? String(value.detail || "") : "未检测";
    }

    function openExternal(command, args, action) {
        var cmd = [String(command || "")];
        var values = Array.isArray(args) ? args : [];
        for (var i = 0; i < values.length; i++)
            cmd.push(String(values[i] || ""));

        if (root.commandRunner && root.commandRunner.runDetached) {
            root.commandRunner.runDetached(action || "system-feature.open", cmd, [String(command || "")], {
                "missingMessage": "入口不可用",
                "missingDetail": "缺少 " + String(command || ""),
                "successMessage": "已打开"
            });
            return;
        }
        Quickshell.execDetached({ command: cmd, workingDirectory: "" });
    }

    function parse(text) {
        var out = [];
        var map = {};
        var lines = String(text || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (!line || line.length === 0)
                continue;
            var fields = line.split("|");
            if (fields[0] !== "ITEM" || fields.length < 5)
                continue;
            var item = {
                "id": fields[1],
                "state": fields[2],
                "title": fields[3],
                "detail": fields.slice(4).join("|")
            };
            out.push(item);
            map[item.id] = item;
        }
        root.items = out;
        root.itemMap = map;
        root.lastUpdatedText = Qt.formatDateTime(new Date(), "HH:mm:ss");
        root.revision += 1;
    }

    function script() {
        return [
            "set +e",
            "have() { command -v \"$1\" >/dev/null 2>&1; }",
            "active() { systemctl --user is-active --quiet \"$1\" 2>/dev/null || systemctl is-active --quiet \"$1\" 2>/dev/null; }",
            "bus_user() { have busctl && busctl --user status \"$1\" >/dev/null 2>&1; }",
            "emit() { printf 'ITEM|%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$4\"; }",
            "if have tracker3; then emit search-index ok Tracker 'tracker3 可用，可用于文件索引诊断'; else emit search-index missing Tracker '缺少 tracker3，Tahoe 仍可搜索应用和窗口'; fi",
            "if bus_user org.gnome.OnlineAccounts; then emit online-accounts ok 'Online Accounts' 'GOA daemon 正在运行'; elif have goa-daemon; then emit online-accounts warn 'Online Accounts' 'goa-daemon 已安装但未检测到用户总线服务'; else emit online-accounts missing 'Online Accounts' '缺少 GNOME Online Accounts'; fi",
            "if have gnome-control-center; then emit gnome-control-center ok 'GNOME Control Center' '可打开外部系统设置作为补充入口'; else emit gnome-control-center missing 'GNOME Control Center' '缺少 gnome-control-center'; fi",
            "if have busctl && busctl --user status org.freedesktop.impl.portal.PermissionStore >/dev/null 2>&1; then emit portal-permissions ok 'Portal Permission Store' '应用权限记录可读取'; else emit portal-permissions warn 'Portal Permission Store' '未检测到权限存储，权限页会降级为只读说明'; fi",
            "if have busctl && busctl --user status org.freedesktop.portal.Desktop >/dev/null 2>&1; then emit desktop-portal ok 'Desktop Portal' '截图、文件选择、位置等 portal 可用'; else emit desktop-portal warn 'Desktop Portal' '未检测到 xdg-desktop-portal 用户服务'; fi",
            "if have ssh || have sshd; then if active sshd.service; then emit remote-login ok '远程登录' 'sshd.service 正在运行'; else emit remote-login warn '远程登录' 'OpenSSH 已安装但 sshd 未运行'; fi; else emit remote-login missing '远程登录' '缺少 OpenSSH'; fi",
            "if have avahi-browse; then if active avahi-daemon.service; then emit discovery ok '网络发现' 'Avahi/mDNS 正在运行'; else emit discovery warn '网络发现' 'Avahi 已安装但 daemon 未运行'; fi; else emit discovery missing '网络发现' '缺少 avahi-browse'; fi",
            "if have smbd; then if active smbd.service; then emit file-sharing ok '文件共享' 'Samba smbd 正在运行'; else emit file-sharing warn '文件共享' 'Samba 已安装但 smbd 未运行'; fi; else emit file-sharing missing '文件共享' '缺少 Samba smbd'; fi",
            "if have rygel; then if active rygel.service; then emit media-sharing ok '媒体共享' 'Rygel 正在运行'; else emit media-sharing warn '媒体共享' 'Rygel 已安装但未运行'; fi; else emit media-sharing missing '媒体共享' '缺少 Rygel'; fi",
            "if have colormgr; then emit color ok '色彩管理' \"$(colormgr get-devices 2>/dev/null | awk '/^Object Path/ {n++} END {print n+0 \" 个设备\"}')\"; else emit color missing '色彩管理' '缺少 colormgr'; fi",
            "if have lpstat; then lpstat -r >/dev/null 2>&1 && emit printers ok '打印服务' 'CUPS scheduler 正在运行' || emit printers warn '打印服务' 'lpstat 可用但 CUPS scheduler 未运行'; else emit printers missing '打印服务' '缺少 CUPS lpstat'; fi",
            "if have gsettings && gsettings writable org.gnome.desktop.a11y.applications screen-reader-enabled >/dev/null 2>&1; then emit accessibility ok '辅助功能' 'GNOME a11y gsettings schema 可用'; else emit accessibility warn '辅助功能' '未检测到 GNOME a11y gsettings schema'; fi",
            "exit 0"
        ].join("\n");
    }

    Process {
        id: probe
        running: false
        command: ["sh", "-lc", root.script()]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.parse(probeOut.text)
        }
        onExited: function(code, exitStatus) {
            root.refreshing = false;
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
