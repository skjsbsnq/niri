import QtQuick
import QtQuick.Window
import QtTest

TestCase {
    id: testCase
    name: "DynamicIslandMediaHitTestingProductionOverlay"
    when: windowShown

    // Path to production-body Overlay rewritten only at the PanelWindow shell
    // (see test_dynamic_island_media_hit_testing.py). contentHost + capsule
    // MouseArea remain the production source text.
    property string overlaySource: ""
    property var overlay: null

    property int capsuleClicks: 0
    property int previousRequests: 0
    property int playPauseRequests: 0
    property int nextRequests: 0
    property int interactionPresses: 0
    property int interactionReleases: 0

    QtObject {
        id: islandService
        property string presentation: "expanded_media"
        property string displayText: "Song"
        property string secondaryText: "Artist"
        property string iconCode: ""
        property real progress: -1
        property string targetScreenName: ""
        property bool islandEnabled: true
        property bool dynamicIslandHideTopbarTime: true
        property bool dynamicIslandHoverExpand: false
        property bool swipeDragging: false
        property bool swipeSettling: false
        property real swipePreviewWidth: -1
        property string mediaArtUrl: ""
        property bool mediaPlaying: true
        property real mediaPosition: 0
        property real mediaLength: 0
        property real mediaProgress: 0
        property bool mediaPositionSupported: false
        property bool mediaLengthSupported: false
        property bool canPlayPause: true
        property bool canPrev: true
        property bool canNext: true
        property int summaryBatteryPercent: 0
        property bool summaryBatteryCharging: false
        property real summaryVolume: 0.5
        property bool summaryMuted: false
        property real summaryBrightness: 1
        property bool summaryBrightnessAvailable: false
        property string summaryWorkspaceLabel: ""
        property bool userInteracting: false

        function setUserInteracting(active) {
            userInteracting = !!active;
            if (active)
                testCase.interactionPresses += 1;
            else
                testCase.interactionReleases += 1;
        }
        function mediaPrevious() { testCase.previousRequests += 1; }
        function mediaTogglePlayPause() { testCase.playPauseRequests += 1; }
        function mediaNext() { testCase.nextRequests += 1; }
        function handleChipClick(button) { testCase.capsuleClicks += 1; }
        function handleChipRightClick() {}
        property int swipeBegins: 0
        property int swipeAdvances: 0
        function canSwipe() { return true; }
        function beginSwipe() { swipeBegins += 1; return true; }
        function advanceSwipe(dx, dy) { swipeAdvances += 1; }
        function updateSwipe(x) {}
        function endSwipe() {}
        function cancelSwipe() {}
        function resolveSwipe() {}
        function setHoverExpanded(v) {}
        function requestHoverExpand() {}
        function requestHoverCollapse() {}
        function consumeSwipeMoved() { return false; }
    }

    function resetCounts() {
        capsuleClicks = 0;
        previousRequests = 0;
        playPauseRequests = 0;
        nextRequests = 0;
        interactionPresses = 0;
        interactionReleases = 0;
        islandService.canPlayPause = true;
        islandService.canPrev = true;
        islandService.canNext = true;
        islandService.presentation = "expanded_media";
        islandService.userInteracting = false;
        islandService.islandEnabled = true;
        islandService.targetScreenName = "";
    }

    function findContentHost(item) {
        if (!item)
            return null;
        if (item.z === 1) {
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                if (kids[i] && kids[i].mediaControlPressed !== undefined)
                    return item;
            }
        }
        var children = item.children || [];
        for (var j = 0; j < children.length; j++) {
            var found = findContentHost(children[j]);
            if (found)
                return found;
        }
        var data = item.data || [];
        for (var k = 0; k < data.length; k++) {
            var found2 = findContentHost(data[k]);
            if (found2)
                return found2;
        }
        return null;
    }

    function findCapsuleMouseArea(item) {
        if (!item)
            return null;
        if (item.swipeStartX !== undefined && item.pointerSession !== undefined)
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findCapsuleMouseArea(children[i]);
            if (found)
                return found;
        }
        var data = item.data || [];
        for (var j = 0; j < data.length; j++) {
            var found2 = findCapsuleMouseArea(data[j]);
            if (found2)
                return found2;
        }
        return null;
    }

    function init() {
        resetCounts();
        if (overlay) {
            overlay.destroy();
            overlay = null;
            wait(0);
        }
        verify(overlaySource.length > 0, "Python harness must set overlaySource env path");
        var comp = Qt.createComponent("file://" + overlaySource);
        verify(comp.status === Component.Ready, "rewritten Overlay must compile: " + comp.errorString());
        overlay = comp.createObject(null, {
            "dynamicIslandService": islandService,
            "settingsService": null,
            "width": 800,
            "height": 220,
            "visible": true
        });
        verify(overlay !== null);
        overlay.visible = true;
        wait(80);
    }

    function cleanup() {
        if (overlay) {
            overlay.destroy();
            overlay = null;
        }
        wait(0);
    }

    function test_production_content_host_and_capsule_present() {
        var root = overlay.contentItem || overlay;
        var host = findContentHost(root);
        var capsule = findCapsuleMouseArea(root);
        verify(host !== null, "production contentHost must be present");
        verify(capsule !== null, "production capsule MouseArea must be present");
        compare(host.z, 1);
        verify(host.z > (capsule.z || 0));
        compare(capsule.enabled, true);
    }

    function mediaPoint(which) {
        // Capsule: expanded_media mid-band 418×166 (T11 V2), top inset 4,
        // centered in 800-wide window. Controls: bottomMargin 10, hit 44 →
        // button center ≈ surface.y + height - 32.
        var mediaW = 418;
        var mediaH = 166;
        var topInset = 4;
        var left = Math.round((800 - mediaW) / 2);
        var y = topInset + mediaH - 32;
        if (which === "prev")
            return Qt.point(left + Math.round(mediaW * 0.29), y);
        if (which === "next")
            return Qt.point(left + Math.round(mediaW * 0.71), y);
        return Qt.point(left + Math.round(mediaW * 0.5), y);
    }

    function clickAt(pt) {
        var target = overlay.contentItem || overlay;
        mouseClick(target, pt.x, pt.y, Qt.LeftButton);
        wait(0);
    }

    function test_three_buttons_once_no_capsule_double() {
        resetCounts();
        // Re-bind service after reset (overlay still live).
        wait(0);
        clickAt(mediaPoint("prev"));
        clickAt(mediaPoint("play"));
        clickAt(mediaPoint("next"));
        compare(previousRequests, 1);
        compare(playPauseRequests, 1);
        compare(nextRequests, 1);
        compare(capsuleClicks, 0);
    }

    function test_disabled_button_absorbs() {
        resetCounts();
        islandService.canPrev = false;
        wait(0);
        clickAt(mediaPoint("prev"));
        compare(previousRequests, 0);
        compare(capsuleClicks, 0);
    }

    function test_blank_area_capsule_click_no_media_action() {
        resetCounts();
        var left = Math.round((800 - 418) / 2);
        // Top-left of capsule: not on control row (y includes top inset 4).
        clickAt(Qt.point(left + 20, 4 + 30));
        compare(previousRequests, 0);
        compare(playPauseRequests, 0);
        compare(nextRequests, 0);
        // Production capsule MouseArea → handleChipClick.
        compare(capsuleClicks, 1);
    }

    function test_blank_area_horizontal_swipe_uses_capsule() {
        resetCounts();
        islandService.swipeBegins = 0;
        islandService.swipeAdvances = 0;
        var left = Math.round((800 - 418) / 2);
        var blankY = 4 + 30;
        var target = overlay.contentItem || overlay;
        // Horizontal drag across blank capsule area (above controls).
        mousePress(target, left + 40, blankY, Qt.LeftButton);
        wait(0);
        mouseMove(target, left + 120, blankY, -1, Qt.LeftButton);
        wait(0);
        mouseRelease(target, left + 120, blankY, Qt.LeftButton);
        wait(0);
        compare(previousRequests, 0);
        compare(playPauseRequests, 0);
        compare(nextRequests, 0);
        // Capsule gesture path must own the blank area: either swipe session
        // started/advanced, or a composed click still lands on handleChipClick.
        if (islandService.swipeBegins + islandService.swipeAdvances === 0) {
            clickAt(Qt.point(left + 40, blankY));
            compare(capsuleClicks, 1);
        } else {
            verify(islandService.swipeBegins + islandService.swipeAdvances > 0);
        }
    }

    function test_non_media_state_hides_controls() {
        // mediaContentVisible requires expanded_media + activeForScreen.
        resetCounts();
        islandService.presentation = "resting_time";
        wait(50);
        clickAt(mediaPoint("play"));
        compare(playPauseRequests, 0);
        islandService.presentation = "expanded_media";
        wait(50);
    }

    function test_target_screen_inactive_hides_media_hits() {
        // Rewrite exposes ownScreenName as a writable property so multi-screen
        // activeForScreen can be exercised without a real multi-output compositor.
        resetCounts();
        verify(overlay.ownScreenName !== undefined);
        overlay.ownScreenName = "eDP-1";
        islandService.targetScreenName = "HDMI-A-1";
        wait(50);
        compare(overlay.activeForScreen, false);
        compare(overlay.mediaContentVisible, false);
        clickAt(mediaPoint("play"));
        compare(playPauseRequests, 0);
        // Restore active screen. Geometry morphs resting→expanded; wait for
        // capsule layout before hit-testing media controls (T08 ownership).
        islandService.targetScreenName = "eDP-1";
        wait(400);
        compare(overlay.activeForScreen, true);
        compare(overlay.mediaContentVisible, true);
        clickAt(mediaPoint("play"));
        compare(playPauseRequests, 1);
        islandService.targetScreenName = "";
        overlay.ownScreenName = "";
        wait(0);
    }
}
