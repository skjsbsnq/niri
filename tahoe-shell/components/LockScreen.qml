pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam
import Quickshell.Wayland

WlSessionLock {
    id: root

    // Declare the sole wall-clock owner before bindings consume its id. This
    // avoids an early construction-time ReferenceError in the lock root.
    SystemClock {
        id: lockClock
        precision: SystemClock.Minutes
        enabled: root.locked
    }

    property string statusText: ""
    property bool authFailed: false
    // Display only: wall time comes from the sole SystemClock owner above.
    readonly property date clockNow: lockClock.date
    readonly property string userName: {
        var user = Quickshell.env("USER");
        return user ? String(user) : "用户";
    }

    function resetPasswordInput(requestFocus) {
        passwordInput.text = "";
        if (requestFocus) {
            Qt.callLater(function() {
                if (root.locked && !pam.active)
                    passwordInput.forceActiveFocus();
            });
        }
    }

    function lock() {
        if (pam.active)
            pam.abort();
        root.statusText = "";
        root.authFailed = false;
        root.locked = true;
        root.resetPasswordInput(true);
        // Wake / re-lock: explicit resync on the SystemClock owner.
        root.syncLockClock();
    }

    function syncLockClock() {
        // Single authorized refresh entry from Task 12A (SystemClock.resync).
        lockClock.resync();
    }

    function unlock() {
        if (pam.active)
            pam.abort();
        root.resetPasswordInput(false);
        root.statusText = "";
        root.authFailed = false;
        root.locked = false;
    }

    function submitPassword() {
        var value = String(passwordInput.text || "");
        if (value.length === 0 || pam.active)
            return;

        root.authFailed = false;
        root.statusText = "正在验证...";

        if (!pam.start()) {
            root.resetPasswordInput(true);
            root.statusText = "无法启动认证";
            root.authFailed = true;
        }
    }

    onLockedChanged: {
        if (!locked) {
            if (pam.active)
                pam.abort();
            root.resetPasswordInput(false);
        } else {
            root.resetPasswordInput(true);
        }
        // enabled is bound to locked; only reseed wall time when locking.
        if (locked)
            root.syncLockClock();
    }

    // Suspend/resume: call the same SystemClock.resync entry (no local Timer).
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive && root.locked)
                root.syncLockClock();
        }
    }

    PamContext {
        id: pam
        config: "login"

        onResponseRequiredChanged: {
            if (responseRequired) {
                pam.respond(passwordInput.text);
                root.resetPasswordInput(false);
            }
        }

        onCompleted: function(result) {
            if (result === PamResult.Success) {
                root.unlock();
                return;
            }

            root.resetPasswordInput(true);
            root.authFailed = true;
            root.statusText = result === PamResult.MaxTries
                ? "认证次数过多，请稍后重试"
                : "密码不正确";
        }

        onError: function(error) {
            root.resetPasswordInput(true);
            root.authFailed = true;
            root.statusText = "认证失败：" + PamError.toString(error);
        }
    }

    WlSessionLockSurface {
        id: surface
        color: "#101215"

        Image {
            anchors.fill: parent
            source: Quickshell.shellPath("assets/backgrounds/iridescence.jpg")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Rectangle {
            anchors.fill: parent
            color: "#52000000"
        }

        ColumnLayout {
            width: Math.min(parent.width - 48, 390)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16

            Text {
                id: clockText
                Layout.fillWidth: true
                text: Qt.formatDateTime(root.clockNow, "HH:mm")
                color: "#ffffff"
                font.pixelSize: 64
                font.weight: Font.Light
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                text: Qt.formatDateTime(root.clockNow, "yyyy年M月d日 dddd")
                color: "#dce3ea"
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                width: 86
                height: 86
                radius: 43
                color: "#80ffffff"
                border.color: "#70ffffff"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "U"
                    color: "#1d1d1f"
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.userName
                color: "#ffffff"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.topMargin: 4
                radius: 22
                color: "#5cf7f8fb"
                border.color: root.authFailed ? "#ccff453a" : "#70ffffff"
                border.width: 1

                TextInput {
                    id: passwordInput
                    anchors.left: parent.left
                    anchors.right: submitButton.left
                    anchors.leftMargin: 18
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    color: "#ffffff"
                    selectionColor: "#7ab7ff"
                    selectedTextColor: "#ffffff"
                    font.pixelSize: 15
                    echoMode: TextInput.Password
                    focus: true
                    clip: true
                    enabled: !pam.active
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: root.submitPassword()
                    Keys.onEscapePressed: root.resetPasswordInput(true)

                    onTextChanged: {
                        if (root.authFailed) {
                            root.authFailed = false;
                            root.statusText = "";
                        }
                    }

                    Component.onCompleted: {
                        if (root.locked)
                            forceActiveFocus();
                    }
                }

                Rectangle {
                    id: submitButton
                    width: 34
                    height: 34
                    radius: 17
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: submitMouse.containsMouse ? "#f0ffffff" : "#d8ffffff"
                    opacity: passwordInput.text.length > 0 && !pam.active ? 1 : 0.45

                    Text {
                        anchors.centerIn: parent
                        text: "\u203a"
                        color: "#1d1d1f"
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: submitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.opacity > 0.5 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (passwordInput.text.length > 0 && !pam.active)
                                root.submitPassword();
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                text: root.statusText
                color: root.authFailed ? "#ffb4ad" : "#dce3ea"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }
    }
}
