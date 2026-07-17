import QtQuick
import QtQuick.Window
import QtTest
import "../components/settings/controls" as Controls

TestCase {
    id: testCase
    name: "SettingsSliderCommit"
    when: windowShown

    Window {
        id: testWindow
        width: 360
        height: 56
        visible: true

        Controls.TahoeSlider {
            id: slider
            anchors.fill: parent
            value: 0.2
            onUserCommit: function(next) { value = next; }
        }
    }

    SignalSpy {
        id: previewSpy
        target: slider
        signalName: "userPreview"
    }

    SignalSpy {
        id: commitSpy
        target: slider
        signalName: "userCommit"
    }

    function init() {
        slider.value = 0.2;
        previewSpy.clear();
        commitSpy.clear();
    }

    function test_drag_previews_locally_and_commits_once() {
        var track = findChild(slider, "trackMouse");
        verify(track !== null);
        mousePress(track, track.width * 0.2, track.height / 2, Qt.LeftButton);
        mouseMove(track, track.width * 0.5, track.height / 2, -1, Qt.LeftButton);
        mouseMove(track, track.width * 0.8, track.height / 2, -1, Qt.LeftButton);

        verify(slider.dragging);
        verify(slider.displayValue > slider.value);
        verify(previewSpy.count >= 3);
        compare(commitSpy.count, 0);

        mouseRelease(track, track.width * 0.9, track.height / 2, Qt.LeftButton);
        compare(commitSpy.count, 1);
        verify(!slider.dragging);
        verify(slider.value > 0.8);
    }
}
