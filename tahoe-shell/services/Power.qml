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
    property var lockService: null
    property var commandRunner
    property var lastResult: null
    property string lastError: ""

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
        if (commandRunner && commandRunner.powerCommandForAction)
            return commandRunner.powerCommandForAction(action);

        if (action === "lock") {
            return ["loginctl", "lock-session"];
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
        if (action === "lock" && lockService && lockService.lock) {
            lastAction = action;
            lockService.lock();
            return;
        }

        var command = commandFor(action);
        if (!command || command.length === 0)
            return;

        lastAction = action;
        if (commandRunner && commandRunner.runPowerAction) {
            var result = commandRunner.runPowerAction(action);
            lastResult = result;
            lastError = result && result.success ? "" : String(result && (result.detail || result.message) || "");
            return;
        }

        Quickshell.execDetached({
            command: command,
            workingDirectory: ""
        });
        lastResult = {
            "action": "power." + String(action || ""),
            "status": "success",
            "success": true,
            "message": "已请求电源操作"
        };
        lastError = "";
    }
}
