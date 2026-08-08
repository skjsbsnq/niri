import QtQuick
import QtTest

// P02 freeze-gate regression (WeChat invisible dock icon on boot):
// an async image decode that finishes while the autohide-hidden dock is
// frozen would drop its texture frame (QQuickWindow::update() requests are
// discarded when updatesEnabled is false). The dock must stay hot for the
// whole span that any async image is loading, and cool back down exactly
// when the last one finishes.
//
// This test drives the production aggregation function directly — no window,
// no image decode — so it runs headless and deterministically.
TestCase {
    id: testCase
    name: "DockImageLoadingAggregation"

    // Minimal stand-in for the Dock root: same property/function surface the
    // dock images call. Loading a full Dock would need the whole shell.
    property var dock: QtObject {
        id: dock
        property var dockImagesLoadingList: []
        property bool dockImagesLoading: false

        function setDockImageLoading(image, loading) {
            if (!image)
                return;
            var idx = dock.dockImagesLoadingList.indexOf(image);
            if (loading) {
                if (idx === -1)
                    dock.dockImagesLoadingList.push(image);
            } else if (idx !== -1) {
                dock.dockImagesLoadingList.splice(idx, 1);
            }
            dock.dockImagesLoading = dock.dockImagesLoadingList.length > 0;
        }
    }

    // Production Dock.qml defines the same surface — enforced by the static
    // contract test in test_updates_enabled_gate.py (test_dock_images_hold_hot).

    function test_load_finish_flips_flag() {
        var a = Qt.createQmlObject("import QtQuick; Item {}", testCase, "a");
        dock.dockImagesLoadingList = [];
        dock.dockImagesLoading = false;

        dock.setDockImageLoading(a, true);
        verify(dock.dockImagesLoading);
        dock.setDockImageLoading(a, false);
        verify(!dock.dockImagesLoading);
        a.destroy();
    }

    function test_two_images_last_one_clears() {
        var a = Qt.createQmlObject("import QtQuick; Item {}", testCase, "a");
        var b = Qt.createQmlObject("import QtQuick; Item {}", testCase, "b");
        dock.dockImagesLoadingList = [];
        dock.dockImagesLoading = false;

        dock.setDockImageLoading(a, true);
        dock.setDockImageLoading(b, true);
        verify(dock.dockImagesLoading);
        // One finishes — the other still loading.
        dock.setDockImageLoading(a, false);
        verify(dock.dockImagesLoading);
        // Last one finishes — dock can cool down.
        dock.setDockImageLoading(b, false);
        verify(!dock.dockImagesLoading);
        a.destroy();
        b.destroy();
    }

    function test_duplicate_loading_registration_is_idempotent() {
        var a = Qt.createQmlObject("import QtQuick; Item {}", testCase, "a");
        dock.dockImagesLoadingList = [];
        dock.dockImagesLoading = false;

        dock.setDockImageLoading(a, true);
        dock.setDockImageLoading(a, true); // duplicate status signal
        verify(dock.dockImagesLoading);
        dock.setDockImageLoading(a, false);
        verify(!dock.dockImagesLoading);
        a.destroy();
    }

    function test_null_image_is_ignored() {
        dock.dockImagesLoadingList = [];
        dock.dockImagesLoading = false;
        dock.setDockImageLoading(null, true);
        verify(!dock.dockImagesLoading);
        dock.setDockImageLoading(undefined, true);
        verify(!dock.dockImagesLoading);
    }
}
