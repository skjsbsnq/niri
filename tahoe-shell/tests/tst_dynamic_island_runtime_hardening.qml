import QtQuick
import QtTest
import "../components" as Components

TestCase {
    id: testCase
    name: "DynamicIslandRuntimeHardening"
    when: windowShown
    width: 520
    height: 240

    Components.DynamicIslandContent {
        id: content
        width: 440
        height: 176
        islandState: "resting_time"
        compactResting: islandState === "resting_time" || islandState === "resting_media"
        compactContentVisible: compactResting
        mediaExpandedContentVisible: islandState === "expanded_media"
        notificationAppName: "Test"
        notificationIconUrl: ""
        displayText: "Title"
        secondaryText: "Body"
        mediaTrackTitle: "Track"
    }

    function loader(name) {
        for (var i = 0; i < content.children.length; i++) {
            var child = content.children[i];
            if (child && child.objectName === name)
                return child;
        }
        return null;
    }

    function init() {
        content.islandState = "resting_time";
        wait(0);
    }

    function test_hidden_heavy_scenes_are_not_instantiated() {
        var notification = loader("notificationLoader");
        var media = loader("mediaLoader");
        verify(notification !== null);
        verify(media !== null);
        compare(notification.active, false);
        compare(notification.item, null);
        compare(media.active, false);
        compare(media.item, null);
    }

    function test_notification_loader_lifecycle() {
        var notification = loader("notificationLoader");
        content.islandState = "transient_notification";
        wait(0);
        compare(notification.active, true);
        verify(notification.item !== null);
        content.islandState = "resting_time";
        // R07: loader holds through the exit fade before unloading.
        wait(content.expandedUnloadHoldMs + 80);
        compare(notification.active, false);
        compare(notification.item, null);
    }

    function test_media_loader_lifecycle() {
        var media = loader("mediaLoader");
        content.islandState = "expanded_media";
        wait(0);
        compare(media.active, true);
        verify(media.item !== null);
        content.islandState = "resting_time";
        wait(content.expandedUnloadHoldMs + 80);
        compare(media.active, false);
        compare(media.item, null);
    }
}
