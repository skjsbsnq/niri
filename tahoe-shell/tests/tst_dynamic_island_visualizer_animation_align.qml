import QtQuick
import QtTest
import QtQuick.Window
import "../components" as Components

// T17: expanded media no longer runs a visualizer Timer. Keep a multi-instance
// gate smoke test so non-owner / collapsed scenes stay free of side effects.
TestCase {
    id: testCase
    name: "DynamicIslandExpandedMediaScreenGate"
    when: windowShown

    Window {
        id: windowA
        width: 400
        height: 166
        visible: true
        color: "transparent"
        flags: Qt.FramelessWindowHint
    }
    Window {
        id: windowB
        width: 400
        height: 166
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
        return item;
    }

    function mediaChild(content) {
        // Loader-hosted DynamicIslandMediaView.
        for (var i = 0; i < content.children.length; ++i) {
            var c = content.children[i];
            if (c && c.objectName === "mediaLoader")
                return c.item;
        }
        // Walk loaders by active/sourceComponent presence.
        function walk(item) {
            if (!item)
                return null;
            if (item.artUrl !== undefined && item.playPauseRequested !== undefined)
                return item;
            if (item.children) {
                for (var j = 0; j < item.children.length; ++j) {
                    var found = walk(item.children[j]);
                    if (found)
                        return found;
                }
            }
            // Loader
            if (item.item)
                return walk(item.item);
            return null;
        }
        return walk(content);
    }

    function test_collapsed_has_no_media_view() {
        var a = makeContent(windowA, true, false);
        wait(30);
        compare(mediaChild(a), null);
        a.destroy();
    }

    function test_expanded_loads_media_without_timer() {
        var a = makeContent(windowA, true, true);
        wait(50);
        var media = mediaChild(a);
        verify(media !== null);
        // No visualizerTimer property on T17 MediaView.
        compare(media.visualizerPhase === undefined, true);
        a.destroy();
    }

    function test_two_instances_only_expanded_has_hits_target() {
        var a = makeContent(windowA, true, true);
        var b = makeContent(windowB, true, false);
        wait(50);
        verify(mediaChild(a) !== null);
        compare(mediaChild(b), null);
        a.destroy();
        b.destroy();
    }
}
