import QtQuick
import QtQuick.Window
import QtTest
import "../components/controls" as Controls

TestCase {
    id: testCase
    name: "PopupSharedControls"
    when: windowShown

    QtObject {
        id: reducedSettings
        property string motionProfile: "reduced"
    }

    Window {
        id: testWindow
        width: 240
        height: 100
        visible: true

        Controls.IconButton {
            id: iconButton
            x: 8
            y: 8
            width: 26
            height: 24
            iconCode: "\ue5d5"
            settingsService: reducedSettings
        }

        Controls.TextButton {
            id: textButton
            x: 48
            y: 8
            width: 80
            height: 24
            label: "删除"
            danger: true
            settingsService: reducedSettings
        }

        Controls.ToggleSwitch {
            id: toggleSwitch
            x: 144
            y: 8
            width: trackWidth
            height: trackHeight
            settingsService: reducedSettings
        }
    }

    SignalSpy {
        id: iconSpy
        target: iconButton
        signalName: "activated"
    }

    SignalSpy {
        id: textSpy
        target: textButton
        signalName: "activated"
    }

    SignalSpy {
        id: toggleSpy
        target: toggleSwitch
        signalName: "toggled"
    }

    function init() {
        iconButton.enabled = true;
        textButton.enabled = true;
        textButton.active = false;
        textButton.primary = false;
        toggleSwitch.enabled = true;
        toggleSwitch.interactive = true;
        toggleSwitch.checked = false;
        iconSpy.clear();
        textSpy.clear();
        toggleSpy.clear();
    }

    function test_buttons_emit_once_and_disabled_blocks_input() {
        mouseClick(iconButton, iconButton.width / 2, iconButton.height / 2);
        compare(iconSpy.count, 1);

        iconButton.enabled = false;
        mouseClick(iconButton, iconButton.width / 2, iconButton.height / 2);
        compare(iconSpy.count, 1);

        textButton.primary = true;
        mouseClick(textButton, textButton.width / 2, textButton.height / 2);
        compare(textSpy.count, 1);
        compare(textButton.scale, 1.0);
    }

    function test_switch_emits_once_and_supports_passive_mode() {
        mouseClick(toggleSwitch, toggleSwitch.width / 2, toggleSwitch.height / 2);
        compare(toggleSpy.count, 1);

        toggleSwitch.interactive = false;
        mouseClick(toggleSwitch, toggleSwitch.width / 2, toggleSwitch.height / 2);
        compare(toggleSpy.count, 1);

        toggleSwitch.compact = true;
        compare(toggleSwitch.trackWidth, 40);
        compare(toggleSwitch.trackHeight, 22);
        compare(toggleSwitch.knobSize, 18);
    }
}
