pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Session and power actions for the Tahoe menu.
//
// The service keeps confirmation state separate from the menu UI so any
// later entry point (Spotlight actions, Control Center, shortcuts) can reuse
// the same command policy.
Item {
    id: root
    visible: false

    property string pendingAction: ""
    property string pendingTitle: ""
    property string pendingMessage: ""
    property string lastAction: ""

    readonly property bool hasPending: pendingAction.length > 0

    function titleFor(action) {
        if (action === "lock")
            return "锁定屏幕";
        if (action === "sleep")
            return "睡眠";
        if (action === "logout")
            return "退出登录";
        if (action === "restart")
            return "重新启动";
        if (action === "shutdown")
            return "关机";
        return "";
    }

    function messageFor(action) {
        if (action === "sleep")
            return "让这台电脑进入睡眠？";
        if (action === "logout")
            return "退出当前 niri 会话？";
        if (action === "restart")
            return "现在重新启动这台电脑？";
        if (action === "shutdown")
            return "现在关闭这台电脑？";
        return "";
    }

    function requestAction(action) {
        if (action === "lock") {
            runAction(action);
            cancelPending();
            return false;
        }

        pendingAction = action;
        pendingTitle = titleFor(action);
        pendingMessage = messageFor(action);
        return true;
    }

    function cancelPending() {
        pendingAction = "";
        pendingTitle = "";
        pendingMessage = "";
    }

    function confirmPending() {
        if (!hasPending)
            return;

        var action = pendingAction;
        cancelPending();
        runAction(action);
    }

    function commandFor(action) {
        if (action === "lock") {
            return [
                "sh",
                "-lc",
                "if command -v swaylock >/dev/null 2>&1; then exec swaylock -f; " +
                "elif command -v gtklock >/dev/null 2>&1; then exec gtklock; " +
                "else exec loginctl lock-session; fi"
            ];
        }

        if (action === "sleep")
            return ["systemctl", "suspend"];

        if (action === "logout") {
            return [
                "sh",
                "-lc",
                "if command -v niri >/dev/null 2>&1; then niri msg action quit --skip-confirmation && exit 0; fi; " +
                "if [ -n \"$XDG_SESSION_ID\" ]; then exec loginctl terminate-session \"$XDG_SESSION_ID\"; fi; " +
                "exit 1"
            ];
        }

        if (action === "restart")
            return ["systemctl", "reboot"];

        if (action === "shutdown")
            return ["systemctl", "poweroff"];

        return [];
    }

    function runAction(action) {
        var command = commandFor(action);
        if (!command || command.length === 0)
            return;

        lastAction = action;
        Quickshell.execDetached({
            command: command,
            workingDirectory: ""
        });
    }
}
