import QtQuick
import QtQuick.Window
import QtTest
import "../components" as Components

TestCase {
    id: testCase
    name: "WindowButtonRectangleTracking"
    when: windowShown

    QtObject {
        id: settings
        property string motionProfile: "reduced"
    }

    QtObject {
        id: windowModel
        property var toplevel: null
        property bool isFocused: false
        property bool isMinimized: false
        property string title: "Sparkle"
        property string appId: "sparkle"
    }

    QtObject {
        id: windowsService
        property int callCount: 0
        property real lastLeft: 0
        property real lastTop: 0
        property var events: []

        function reset() {
            callCount = 0;
            events = [];
        }

        function setRectangle(windowModelArg, sourceWindow, left, top, width, height) {
            callCount += 1;
            lastLeft = left;
            lastTop = top;
            events.push({ "kind": "rectangle", "left": left, "top": top });
        }

        function recordExternalMinimize() {
            events.push({ "kind": "minimize" });
        }
    }

    Window {
        id: testWindow
        width: 480
        height: 180
        visible: true

        Item {
            id: movingParent
            x: 24
            y: 18
            width: 300
            height: 80

            Components.WindowButton {
                id: button
                showTitle: false
                windowModel: windowModel
                windowsService: windowsService
                settingsService: settings
                dockWindow: testWindow
                dockSceneOffsetX: movingParent.x
                dockSceneOffsetY: movingParent.y
            }
        }
    }

    function test_ancestor_motion_republishes_final_scene_rectangle() {
        windowsService.reset();
        button.updateDockRectangle();
        compare(windowsService.callCount, 1);
        var initialLeft = windowsService.lastLeft;
        var initialTop = windowsService.lastTop;

        windowsService.reset();
        movingParent.x += 120;
        movingParent.y += 18;

        tryVerify(function() { return windowsService.callCount > 0; }, 500);
        compare(windowsService.lastLeft, initialLeft + 120);
        compare(windowsService.lastTop, initialTop + 18);

        // This models xdg_toplevel.set_minimized from the application: the
        // compositor must already have the final Dock rectangle before that
        // first request arrives.
        windowsService.recordExternalMinimize();
        compare(windowsService.events[windowsService.events.length - 2].kind, "rectangle");
        compare(windowsService.events[windowsService.events.length - 2].left, initialLeft + 120);
        compare(windowsService.events[windowsService.events.length - 1].kind, "minimize");
    }

    function test_fullscreen_suppresses_rectangle_republish() {
        windowsService.reset();
        button.dockFullscreenActive = true;
        button.updateDockRectangle();
        compare(windowsService.callCount, 0);
        // Force also blocked while still fullscreen (layer unmapped).
        button.updateDockRectangle(true);
        compare(windowsService.callCount, 0);

        // After fullscreen clears, offset may still be non-zero during reveal —
        // publish must work so minimize targets are refilled after niri unmap clear.
        button.dockFullscreenOffset = 40;
        button.dockFullscreenActive = false;
        button.updateDockRectangle();
        compare(windowsService.callCount, 1);

        windowsService.reset();
        button.updateDockRectangle(true);
        compare(windowsService.callCount, 1);
    }
}
