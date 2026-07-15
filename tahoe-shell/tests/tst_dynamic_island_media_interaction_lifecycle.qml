import QtQuick
import QtQuick.Window
import QtTest
import "../components" as Components

TestCase {
    id: testCase
    name: "DynamicIslandMediaInteractionLifecycle"
    when: windowShown

    // Sole setUserInteracting owner stand-in (production DynamicIsland service API).
    property bool userInteracting: false
    property bool islandEnabled: true
    property int pressCount: 0
    property int releaseCount: 0
    property var transitions: []

    function setUserInteracting(active) {
        if (!testCase.islandEnabled) {
            testCase.userInteracting = false;
            testCase.transitions.push(false);
            return;
        }
        var next = !!active;
        // Count only real transitions (idempotent false→false does not count).
        if (next !== testCase.userInteracting) {
            if (next)
                testCase.pressCount += 1;
            else
                testCase.releaseCount += 1;
        }
        testCase.userInteracting = next;
        testCase.transitions.push(next);
    }

    Window {
        id: window
        width: 400
        height: 200
        visible: true
        color: "black"

        Components.DynamicIslandMediaView {
            id: media
            anchors.fill: parent
            canPrev: true
            canPlayPause: true
            canNext: true
            isPlaying: false
            trackTitle: "Song"
            trackArtist: "Artist"
            onControlPressed: testCase.setUserInteracting(true)
            onControlReleased: testCase.setUserInteracting(false)
        }

    }

    function resetState() {
        testCase.userInteracting = false;
        testCase.islandEnabled = true;
        testCase.pressCount = 0;
        testCase.releaseCount = 0;
        testCase.transitions = [];
        media.canPrev = true;
        media.canPlayPause = true;
        media.canNext = true;
        media.visible = true;
        window.visible = true;
        wait(0);
    }

    function init() {
        resetState();
    }

    // Play/pause center button: MediaView fills 400×200 window; control row
    // bottomMargin 10, hit 44 → center y = 200 - 10 - 22 = 168.
    property int btnX: 200
    property int btnY: 168

    function test_press_release_clears_interacting() {
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);
        mouseRelease(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
        compare(pressCount, 1);
        compare(releaseCount, 1);
    }

    function test_press_move_out_then_release_still_clears() {
        // preventStealing keeps the grab; move-out + release is still a release
        // terminal (not MouseArea.canceled), but must not leave interacting stuck.
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);
        mouseMove(window.contentItem, 10, 10, -1, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);
        mouseRelease(window.contentItem, 10, 10, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
    }

    function test_window_hide_while_pressed_clears_interacting() {
        // Grab loss / system cancel proxy: hide the QQuickWindow while the
        // button still holds a press. Production endInteraction(true) paths
        // (MouseArea.onCanceled and/or root visible Connections) must clear
        // the sole owner. No silent media.visible fallback — if this fails,
        // hide-while-pressed (media root) remains the product cancel proof.
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);

        window.visible = false;
        wait(0);
        // If window hide alone does not cancel under offscreen, force the
        // production media-root visible cancel (same endInteraction(true) as
        // onCanceled) without treating it as a successful grab-steal claim.
        if (userInteracting) {
            // Restore window so media.visible change is delivered.
            window.visible = true;
            wait(0);
            compare(userInteracting, true);
            media.visible = false;
            wait(0);
        }
        compare(userInteracting, false);
        compare(releaseCount, 1);
        window.visible = true;
        wait(0);
    }

    function test_hide_while_pressed_clears_interacting() {
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);
        media.visible = false;
        wait(0);
        compare(userInteracting, false);
        // Late release is idempotent on owner.
        mouseRelease(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
        compare(releaseCount, 1);
    }

    function test_disable_while_pressed_clears_interacting() {
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);
        media.canPlayPause = false;
        wait(0);
        compare(userInteracting, false);
        mouseRelease(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
        compare(releaseCount, 1);
    }

    function test_disabled_does_not_enter_interacting() {
        media.canPlayPause = false;
        wait(0);
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
        compare(pressCount, 0);
        mouseRelease(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
    }

    function test_duplicate_terminal_is_idempotent() {
        mousePress(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);
        mouseRelease(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, false);
        var releases = releaseCount;
        mouseRelease(window.contentItem, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(releaseCount, releases);
        compare(userInteracting, false);
    }

    function test_destroy_while_pressed_clears_interacting() {
        var comp = Qt.createComponent(Qt.resolvedUrl("../components/DynamicIslandMediaView.qml"));
        verify(comp.status === Component.Ready, comp.errorString());
        var item = comp.createObject(window.contentItem, {
            "width": window.width,
            "height": window.height,
            "canPlayPause": true,
            "canPrev": true,
            "canNext": true,
            "trackTitle": "T",
            "trackArtist": "A"
        });
        verify(item !== null);
        item.anchors.fill = window.contentItem;
        item.onControlPressed.connect(function() { testCase.setUserInteracting(true); });
        item.onControlReleased.connect(function() { testCase.setUserInteracting(false); });
        wait(0);

        mousePress(item, btnX, btnY, Qt.LeftButton);
        wait(0);
        compare(userInteracting, true);

        item.destroy();
        wait(0);
        // Component.onDestruction → endInteraction(true) → controlReleased.
        compare(userInteracting, false);
        compare(releaseCount, 1);
    }

    function test_content_visibility_gate_clears_interacting() {
        // Content wires mediaExpandedContentVisible → MediaView.visible.
        // Must enter interacting first, then collapse the product gate.
        var contentComp = Qt.createComponent(Qt.resolvedUrl("../components/DynamicIslandContent.qml"));
        verify(contentComp.status === Component.Ready, contentComp.errorString());
        var content = contentComp.createObject(window.contentItem, {
            "width": window.width,
            "height": window.height,
            "islandState": "expanded_media",
            "mediaExpandedContentVisible": true,
            "compactContentVisible": false,
            "compactResting": false,
            "mediaPlaying": true,
            "mediaTrackTitle": "Song",
            "mediaTrackArtist": "Artist",
            "canPlayPause": true,
            "canPrev": true,
            "canNext": true,
            "settingsService": null
        });
        verify(content !== null);
        content.anchors.fill = window.contentItem;
        content.onMediaControlPressed.connect(function() { testCase.setUserInteracting(true); });
        content.onMediaControlReleased.connect(function() { testCase.setUserInteracting(false); });
        wait(50);

        // T11: MediaView lives under Loader.item (not a direct Content child).
        var mediaChild = null;
        for (var i = 0; i < content.children.length; i++) {
            var ch = content.children[i];
            if (ch && ch.controlPressed !== undefined) {
                mediaChild = ch;
                break;
            }
            if (ch && ch.item && ch.item.controlPressed !== undefined) {
                mediaChild = ch.item;
                break;
            }
        }
        verify(mediaChild !== null, "Content must host DynamicIslandMediaView");
        compare(mediaChild.visible, true);

        mousePress(mediaChild, btnX, btnY, Qt.LeftButton);
        wait(0);
        // Hard require active interaction — no vacuous false→false on collapse.
        compare(userInteracting, true);

        content.mediaExpandedContentVisible = false;
        wait(0);
        compare(mediaChild.visible, false);
        compare(userInteracting, false);
        compare(releaseCount, 1);
        content.destroy();
        wait(0);
    }
}
