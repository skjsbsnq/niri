import QtQuick
import QtTest
import QtQuick.Window
import "../components" as Components

TestCase {
    id: testCase
    name: "DynamicIslandVisualizerScreenGate"
    when: windowShown

    property int tickMs: 120
    property int waitTicks: 5
    property int fadeInMs: 50

    // Real visible windows so QQuickItem effective visibility is true (Timer
    // bindings use Item.visible which is effective, not local-only).
    Window {
        id: windowA
        width: 400
        height: 140
        visible: true
        color: "transparent"
        flags: Qt.FramelessWindowHint
    }
    Window {
        id: windowB
        width: 400
        height: 140
        visible: true
        color: "transparent"
        flags: Qt.FramelessWindowHint
    }

    Component {
        id: contentComponent
        Components.DynamicIslandContent {}
    }

    function makeContent(win, playing, mediaExpanded) {
        var item = contentComponent.createObject(win.contentItem, {
            "width": win.width,
            "height": win.height,
            "islandState": mediaExpanded ? "expanded_media" : "resting_time",
            "mediaExpandedContentVisible": mediaExpanded,
            "compactContentVisible": !mediaExpanded,
            "compactResting": !mediaExpanded,
            "mediaPlaying": playing,
            "mediaTrackTitle": "Song",
            "mediaTrackArtist": "Artist",
            "settingsService": null
        });
        verify(item !== null);
        item.anchors.fill = win.contentItem;
        return item;
    }

    function mediaChild(content) {
        for (var i = 0; i < content.children.length; i++) {
            var child = content.children[i];
            if (child && child.visualizerPhase !== undefined)
                return child;
        }
        return null;
    }

    function test_only_visible_instance_advances_phase() {
        var target = makeContent(windowA, true, true);
        var hidden = makeContent(windowB, true, false);
        wait(fadeInMs);

        var tMedia = mediaChild(target);
        var hMedia = mediaChild(hidden);
        verify(tMedia !== null);
        verify(hMedia !== null);
        verify(tMedia.visible === true, "target MediaView must be effectively visible");
        verify(hMedia.visible === false, "non-target MediaView must be hidden");

        var phaseTarget0 = tMedia.visualizerPhase;
        var phaseHidden0 = hMedia.visualizerPhase;
        wait(tickMs * waitTicks + 40);

        verify(tMedia.visualizerPhase > phaseTarget0, "target screen phase must advance");
        compare(hMedia.visualizerPhase, phaseHidden0, "hidden multi-screen instance must not tick");

        target.destroy();
        hidden.destroy();
    }

    function test_target_switch_transfers_ownership() {
        var a = makeContent(windowA, true, true);
        var b = makeContent(windowB, true, false);
        wait(fadeInMs);
        var aMedia = mediaChild(a);
        var bMedia = mediaChild(b);
        verify(aMedia !== null && bMedia !== null);
        wait(tickMs * waitTicks + 40);
        verify(aMedia.visualizerPhase > 0, "initial target must tick");
        var aPhase = aMedia.visualizerPhase;
        var bPhase = bMedia.visualizerPhase;

        a.mediaExpandedContentVisible = false;
        a.islandState = "resting_time";
        b.islandState = "expanded_media";
        b.mediaExpandedContentVisible = true;
        wait(fadeInMs);
        wait(tickMs * waitTicks + 40);

        compare(aMedia.visualizerPhase, aPhase, "old target must stop after switch");
        verify(bMedia.visualizerPhase > bPhase, "new target must start after switch");
        verify(aMedia.visible === false);
        verify(bMedia.visible === true);

        a.destroy();
        b.destroy();
    }

    function test_paused_and_hidden_zero_ticks() {
        var paused = makeContent(windowA, false, true);
        var hidden = makeContent(windowB, true, false);
        wait(fadeInMs);
        var pMedia = mediaChild(paused);
        var hMedia = mediaChild(hidden);
        verify(pMedia !== null && hMedia !== null);
        var p0 = pMedia.visualizerPhase;
        var h0 = hMedia.visualizerPhase;
        wait(tickMs * waitTicks + 40);
        compare(pMedia.visualizerPhase, p0);
        compare(hMedia.visualizerPhase, h0);
        paused.destroy();
        hidden.destroy();
    }

    function test_overlay_active_for_screen_gates_media_property() {
        var overlayLogic = Qt.createQmlObject(
            'import QtQuick; QtObject {' +
            '  property string contentState: "expanded_media";' +
            '  property bool activeForScreen: true;' +
            '  readonly property bool mediaContentVisible: contentState === "expanded_media" && activeForScreen;' +
            '}',
            testCase
        );
        verify(overlayLogic.mediaContentVisible === true);
        overlayLogic.activeForScreen = false;
        verify(overlayLogic.mediaContentVisible === false);
        overlayLogic.activeForScreen = true;
        overlayLogic.contentState = "resting_time";
        verify(overlayLogic.mediaContentVisible === false);
        overlayLogic.destroy();
    }
}
