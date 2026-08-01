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
        id: mockScreen
        property string name: "eDP-1"
    }

    QtObject {
        id: mockToplevel
        // Property change signal is auto-generated; WindowButton Connections uses it.
        property var screens: [mockScreen]
        property bool activated: false
        property bool minimized: false
    }

    QtObject {
        id: windowModel
        property var toplevel: mockToplevel
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
        property var lastToplevel: null
        property var lastScreen: null
        property var events: []
        property var pendingByKey: ({})
        property int flushCount: 0
        property int invalidateCount: 0

        function reset() {
            callCount = 0;
            events = [];
            pendingByKey = ({});
            flushCount = 0;
            invalidateCount = 0;
            lastToplevel = null;
            lastScreen = null;
        }

        // Production Windows.qml service hook: the wire-dedup cache is dropped
        // when the Dock layer unmaps for fullscreen (niri wipes rects).
        function invalidateDockRectanglePublish(toplevel) {
            invalidateCount += 1;
        }

        // Mirror production publisher entry used by WindowButton.
        function submitDockRectangle(toplevel, sourceWindow, dockScreen, left, top, width, height, options) {
            callCount += 1;
            lastLeft = left;
            lastTop = top;
            lastToplevel = toplevel;
            lastScreen = dockScreen;
            events.push({
                "kind": "rectangle",
                "left": left,
                "top": top,
                "force": !!(options && options.force),
                "toplevel": toplevel,
                "screen": dockScreen
            });
            return true;
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
        property var screen: mockScreen

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
                toplevel: mockToplevel
                windowsService: windowsService
                settingsService: settings
                dockWindow: testWindow
                dockScreen: mockScreen
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
        compare(windowsService.lastToplevel, mockToplevel);
        compare(windowsService.lastScreen, mockScreen);

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
        compare(windowsService.events[0].force, true);

        // Disarm the post-remap force timer armed by the false edge so it
        // cannot fire into a later test.
        button.stopDockRectangleTimers();
    }

    function test_visual_mag_push_excluded_from_rest_hint() {
        // T19: the hover wave (magnification/pushX) is a visual-only transform
        // and must NOT enter the foreign-toplevel hint or trigger a republish —
        // the hint is the icon's REST geometry. Changing the wave leaves the
        // reported rectangle at its rest value with no new publish, and a forced
        // re-publish reports the same rest rect (no wave distortion).
        windowsService.reset();
        button.updateDockRectangle();
        compare(windowsService.callCount, 1);
        var restLeft = windowsService.lastLeft;
        var restTop = windowsService.lastTop;

        windowsService.reset();
        button.magnification = 1.4;
        button.pushX = 12;
        wait(60);  // allow any (incorrect) queued republish to flush
        compare(windowsService.callCount, 0);

        // A forced re-publish still reports the REST rect, unchanged by the wave.
        button.updateDockRectangle(true);
        compare(windowsService.callCount, 1);
        compare(windowsService.lastLeft, restLeft);
        compare(windowsService.lastTop, restTop);

        // Restore the default wave state for any later test in this case.
        button.magnification = 1.0;
        button.pushX = 0;
    }

    function test_fullscreen_transition_invalidates_dedup_cache() {
        // niri wipes foreign-toplevel rects when the Dock layer unmaps for
        // fullscreen; the delegate must drop the service-side dedup cache on
        // both edges so the post-remap republish is not suppressed as
        // "unchanged".
        windowsService.reset();
        button.dockFullscreenActive = true;
        compare(windowsService.invalidateCount, 1);
        button.dockFullscreenActive = false;
        compare(windowsService.invalidateCount, 2);
        // Disarm the timers armed by the false edge (refresh/settle/remap
        // force) so none can fire into a later test.
        button.stopDockRectangleTimers();
    }

    function test_no_direct_setrectangle_bypass() {
        // Production path must not call a legacy setRectangle that skips ownership.
        windowsService.reset();
        button.updateDockRectangle(true);
        compare(windowsService.callCount, 1);
        compare(windowsService.events[0].toplevel, mockToplevel);
        compare(windowsService.events[0].screen, mockScreen);
    }
}
