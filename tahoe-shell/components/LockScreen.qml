pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam
import Quickshell.Wayland
import "Motion.js" as Motion
import "controls" as Controls

WlSessionLock {
    id: root

    property var settingsService
    property bool unlocking: false
    property int failureFeedbackSerial: 0
    property int focusRequestSerial: 0
    property string credentialText: ""
    readonly property bool reducedMotion: Motion.reducedMotion(settingsService)
    readonly property int lockEnterDuration: reducedMotion ? 0 : Motion.panelEnter(settingsService)
    readonly property int unlockExitDuration: reducedMotion
        ? 0 : Math.min(180, Motion.panelExit(settingsService))
    readonly property int feedbackFadeDuration: reducedMotion
        ? 0 : Motion.fadeFast(settingsService)

    // WlSessionLock's default property is the per-output surface Component.
    // Keep process-wide clock/PAM/exit owners in explicit typed properties so
    // they are not captured inside that component (one instance per screen).
    property SystemClock lockClock: SystemClock {
        precision: SystemClock.Minutes
        enabled: root.locked
    }

    property string statusText: ""
    property bool authFailed: false
    // Display only: wall time comes from the sole SystemClock owner above.
    readonly property date clockNow: root.lockClock.date
    readonly property string userName: {
        var user = Quickshell.env("USER");
        return user ? String(user) : "用户";
    }

    function resetPasswordInput(requestFocus) {
        root.credentialText = "";
        if (requestFocus)
            root.focusRequestSerial += 1;
    }

    function lock() {
        root.unlockSequence.stop();
        root.unlocking = false;
        if (root.pam.active)
            root.pam.abort();
        root.statusText = "";
        root.authFailed = false;
        root.locked = true;
        root.resetPasswordInput(true);
        // Wake / re-lock: explicit resync on the SystemClock owner.
        root.syncLockClock();
    }

    function syncLockClock() {
        // Single authorized refresh entry from Task 12A (SystemClock.resync).
        root.lockClock.resync();
    }

    function unlock() {
        root.unlockSequence.stop();
        if (root.pam.active)
            root.pam.abort();
        root.resetPasswordInput(false);
        root.statusText = "";
        root.authFailed = false;
        root.locked = false;
        root.unlocking = false;
    }

    function beginUnlock() {
        if (!root.locked || root.unlocking)
            return;
        root.resetPasswordInput(false);
        root.statusText = "";
        root.authFailed = false;
        root.unlocking = true;
        root.unlockSequence.restart();
    }

    function finishUnlock() {
        if (root.unlocking)
            root.unlock();
    }

    function triggerAuthenticationFailure(message) {
        root.resetPasswordInput(true);
        root.authFailed = true;
        root.statusText = message;
        root.failureFeedbackSerial += 1;
    }

    function submitPassword() {
        var value = String(root.credentialText || "");
        if (value.length === 0 || root.pam.active || root.unlocking)
            return;

        root.authFailed = false;
        root.statusText = "正在验证...";

        if (!root.pam.start())
            root.triggerAuthenticationFailure("无法启动认证");
    }

    onLockedChanged: {
        if (!locked) {
            root.unlockSequence.stop();
            if (root.pam.active)
                root.pam.abort();
            root.resetPasswordInput(false);
            root.unlocking = false;
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

    property SequentialAnimation unlockSequence: SequentialAnimation {
        PauseAnimation {
            duration: root.unlockExitDuration
        }
        ScriptAction {
            script: root.finishUnlock()
        }
    }

    property PamContext pam: PamContext {
        config: "login"

        onResponseRequiredChanged: {
            if (responseRequired) {
                root.pam.respond(root.credentialText);
                root.resetPasswordInput(false);
            }
        }

        onCompleted: function(result) {
            if (result === PamResult.Success) {
                root.beginUnlock();
                return;
            }

            root.triggerAuthenticationFailure(result === PamResult.MaxTries
                ? "认证次数过多，请稍后重试"
                : "密码不正确");
        }

        onError: function(error) {
            root.triggerAuthenticationFailure("认证失败：" + PamError.toString(error));
        }
    }

    WlSessionLockSurface {
        id: surface

        property bool entered: false
        color: "#101215"

        Component.onCompleted: {
            Qt.callLater(function() {
                surface.entered = true;
            });
        }

        Item {
            id: visualLayer

            anchors.fill: parent
            opacity: surface.entered && !root.unlocking ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: root.unlocking
                        ? root.unlockExitDuration : root.lockEnterDuration
                    easing.type: root.unlocking
                        ? Motion.emphasizedAccel : Motion.emphasizedDecel
                }
            }

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
                id: contentColumn

                width: Math.min(parent.width - 48, 390)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                transform: Translate {
                    id: contentShift

                    y: root.unlocking ? -10 : (surface.entered ? 0 : 10)

                    Behavior on y {
                        NumberAnimation {
                            duration: root.unlocking
                                ? root.unlockExitDuration : root.lockEnterDuration
                            easing.type: root.unlocking
                                ? Motion.emphasizedAccel : Motion.emphasizedDecel
                        }
                    }
                }

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
                id: passwordFrame

                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.topMargin: 4
                radius: 22
                color: "#5cf7f8fb"
                border.color: root.authFailed ? "#ccff453a" : "#70ffffff"
                border.width: 1
                transform: Translate {
                    id: passwordShake
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: root.feedbackFadeDuration
                        easing.type: Motion.standardDecel
                    }
                }

                TextInput {
                    id: passwordInput
                    anchors.left: parent.left
                    anchors.right: submitButton.left
                    anchors.leftMargin: 18
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    text: ""
                    color: "#ffffff"
                    selectionColor: "#7ab7ff"
                    selectedTextColor: "#ffffff"
                    font.pixelSize: 15
                    echoMode: TextInput.Password
                    focus: true
                    clip: true
                    enabled: !root.pam.active && !root.unlocking
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: root.submitPassword()
                    Keys.onEscapePressed: root.resetPasswordInput(true)

                    onTextChanged: {
                        if (root.credentialText !== text)
                            root.credentialText = text;
                        if (root.authFailed) {
                            root.authFailed = false;
                            root.statusText = "";
                        }
                    }

                    Component.onCompleted: {
                        text = root.credentialText;
                        if (root.locked)
                            forceActiveFocus();
                    }

                    Connections {
                        target: root
                        function onCredentialTextChanged() {
                            if (passwordInput.text !== root.credentialText)
                                passwordInput.text = root.credentialText;
                        }
                    }
                }

                Controls.IconButton {
                    id: submitButton

                    width: 34
                    height: 34
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    iconCode: "\ue5cc"
                    iconColor: "#1d1d1f"
                    iconSize: 22
                    enabled: root.credentialText.length > 0
                        && !root.pam.active && !root.unlocking
                    baseColor: "#d8ffffff"
                    hoverColor: "#f0ffffff"
                    borderColor: "transparent"
                    cornerRadius: 17
                    settingsService: root.settingsService
                    onActivated: root.submitPassword()
                }
            }

                Text {
                    id: statusLabel

                    property string renderedText: ""

                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    text: renderedText
                    color: root.authFailed ? "#ffb4ad" : "#dce3ea"
                    opacity: renderedText.length > 0 && root.statusText.length > 0 ? 1 : 0
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight

                    Behavior on opacity {
                        NumberAnimation {
                            id: statusOpacityAnimation

                            duration: root.feedbackFadeDuration
                            easing.type: Motion.standardDecel
                            onFinished: {
                                if (statusLabel.opacity <= 0.001
                                        && root.statusText.length === 0)
                                    statusLabel.renderedText = "";
                            }
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: root.feedbackFadeDuration
                            easing.type: Motion.standardDecel
                        }
                    }

                    Component.onCompleted: {
                        if (root.statusText.length > 0)
                            renderedText = root.statusText;
                    }

                    Connections {
                        target: root
                        function onStatusTextChanged() {
                            if (root.statusText.length > 0)
                                statusLabel.renderedText = root.statusText;
                        }
                    }
                }
            }

            SequentialAnimation {
                id: failureShakeAnimation

                NumberAnimation { target: passwordShake; property: "x"; to: -9; duration: 45; easing.type: Easing.OutQuad }
                NumberAnimation { target: passwordShake; property: "x"; to: 8; duration: 55; easing.type: Easing.InOutQuad }
                NumberAnimation { target: passwordShake; property: "x"; to: -6; duration: 55; easing.type: Easing.InOutQuad }
                NumberAnimation { target: passwordShake; property: "x"; to: 5; duration: 55; easing.type: Easing.InOutQuad }
                NumberAnimation { target: passwordShake; property: "x"; to: -3; duration: 50; easing.type: Easing.InOutQuad }
                NumberAnimation { target: passwordShake; property: "x"; to: 0; duration: 40; easing.type: Easing.OutQuad }
            }

            Connections {
                target: root

                function onFailureFeedbackSerialChanged() {
                    failureShakeAnimation.stop();
                    passwordShake.x = 0;
                    if (!root.reducedMotion)
                        failureShakeAnimation.restart();
                }

                function onUnlockingChanged() {
                    if (root.unlocking) {
                        failureShakeAnimation.stop();
                        passwordShake.x = 0;
                    }
                }

                function onFocusRequestSerialChanged() {
                    Qt.callLater(function() {
                        if (root.locked && !root.pam.active && !root.unlocking)
                            passwordInput.forceActiveFocus();
                    });
                }
            }
        }
    }
}
