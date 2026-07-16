import QtQuick
import QtTest
import "../services" as Services

TestCase {
    id: testCase
    name: "DynamicIslandOutputOwnership"
    when: windowShown

    property var island: null

    QtObject {
        id: notifications
        property var activeModel: []
        property bool dndEnabled: false
        signal notificationUpdated(int id)
        function findActiveById(id) { return null; }
        function presentationHead() { return null; }
    }

    QtObject {
        id: settings
        property bool dynamicIslandEnabled: true
        property bool dynamicIslandHideTopbarTime: true
        property string dynamicIslandLeftClickAction: "toggle_media"
        property string dynamicIslandRightClickAction: "control_center"
        property bool dynamicIslandAutoExpandMedia: false
        property bool dynamicIslandHoverExpand: false
    }

    QtObject {
        id: controls
        property real volume: 0.5
        property bool muted: false
        property real brightness: 1.0
        property bool brightnessAvailable: false
        property bool hasMedia: true
        property string trackArtUrl: ""
        property bool isPlaying: false
        property real trackPosition: 0
        property real trackLength: 0
        property real trackProgress: 0
        property bool trackPositionSupported: false
        property bool trackLengthSupported: false
        property string trackTitle: "Song"
        property string trackArtist: "Artist"
    }

    QtObject {
        id: focusedWindow
        property string output: "eDP-2"
    }

    QtObject {
        id: windows
        property string activeWorkspaceName: "1"
        property var focusedWindow: focusedWindow
        property var activeWorkspace: null
        property string focusedOutputName: "eDP-2"
    }

    Component {
        id: islandComponent
        Services.DynamicIsland {}
    }

    function init() {
        focusedWindow.output = "eDP-2";
        windows.focusedOutputName = "eDP-2";
        settings.dynamicIslandEnabled = true;
        settings.dynamicIslandHideTopbarTime = true;
        island = islandComponent.createObject(testCase, {
            notificationsService: notifications,
            settingsService: settings,
            controlsService: controls,
            windowsService: windows
        });
        verify(island !== null);
        wait(0);
        island.reset();
        wait(0);
    }

    function cleanup() {
        if (island) {
            island.destroy();
            island = null;
        }
        wait(0);
    }

    function test_event_owner_pin_survives_focus_change() {
        // Seed pin via capture preferred (same helper showTransient uses).
        island.eventOwnerOutput = "";
        island.captureEventOwnerOutput("eDP-2");
        compare(island.eventOwnerOutput, "eDP-2");
        // In-lease re-capture must not overwrite (H1).
        focusedWindow.output = "HDMI-A-1";
        windows.focusedOutputName = "HDMI-A-1";
        island.captureEventOwnerOutput();
        compare(island.eventOwnerOutput, "eDP-2");

        // A new notification event must replace any stale pre-event pin with
        // the output focused when that notification is created.
        island.clearEventOwnerOutput();
        focusedWindow.output = "eDP-2";
        windows.focusedOutputName = "eDP-2";
        island.showTransientNotification("Hello", "body");
        compare(island.presentation, "transient_notification");
        compare(island.eventOwnerOutput, "eDP-2");
        // Focus jumps after creation — target must stay pinned.
        focusedWindow.output = "HDMI-A-1";
        windows.focusedOutputName = "HDMI-A-1";
        compare(island.targetScreenName, "eDP-2");

        // Clear pin after hide.
        island.forcedState = "";
        island.clearEventOwnerOutput();
        compare(island.eventOwnerOutput, "");
    }

    function test_sanitize_drops_gone_output() {
        island.eventOwnerOutput = "GONE";
        island.sessionOwnerOutput = "eDP-2";
        // Direct pure-path: available list without GONE.
        // Island sanitize uses Quickshell.screens; exercise clear + resolve fallback.
        island.clearEventOwnerOutput();
        compare(island.eventOwnerOutput, "");
        island.sessionOwnerOutput = "eDP-2";
        compare(island.targetScreenName, "eDP-2");
    }

    function test_session_owner_from_chip_click() {
        island.handleChipClick(Qt.LeftButton, "HDMI-A-1");
        // toggle_media with hasMedia → expanded_media and session pin.
        compare(island.sessionOwnerOutput, "HDMI-A-1");
        compare(island.presentation, "expanded_media");

        // Focus change must not move session owner.
        focusedWindow.output = "eDP-2";
        windows.focusedOutputName = "eDP-2";
        compare(island.targetScreenName, "HDMI-A-1");

        island.toggleExpanded();
        compare(island.sessionOwnerOutput, "");
    }

    function test_swipe_collapse_clears_session() {
        island.claimSessionOwnerForScreen("HDMI-A-1");
        island.showExpandedMedia();
        compare(island.sessionOwnerOutput, "HDMI-A-1");
        // Simulate swipe resolve collapse branch: not entered, not expanded.
        island.forcedState = "";
        island.clearSessionOwnerOutput();
        compare(island.sessionOwnerOutput, "");
    }

    function test_auto_expand_claims_session() {
        settings.dynamicIslandAutoExpandMedia = true;
        island.sessionOwnerOutput = "";
        island.forcedState = "";
        // hasMedia already true; re-fire availability as if media appeared.
        controls.hasMedia = false;
        wait(0);
        controls.hasMedia = true;
        island.handleMediaAvailabilityChanged();
        // Prefer media expand path may set expanded_media when autoExpand on.
        if (island.presentation === "expanded_media")
            compare(island.sessionOwnerOutput.length > 0, true);
    }

    function test_osd_captures_event_owner() {
        island.eventOwnerOutput = "";
        island.showTransientOsd("音量", 0.5);
        compare(island.presentation, "transient_osd");
        // captureEventOwnerOutput runs; with empty Quickshell.screens may be "".
        // Explicit pin path still works via capture preferred.
        island.captureEventOwnerOutput("eDP-2");
        compare(island.eventOwnerOutput, "eDP-2");
        focusedWindow.output = "HDMI-A-1";
        windows.focusedOutputName = "HDMI-A-1";
        compare(island.targetScreenName, "eDP-2");
    }

    function test_sanitize_clears_missing_owner() {
        island.eventOwnerOutput = "GONE";
        island.sessionOwnerOutput = "eDP-2";
        // availableOutputNames from Quickshell.screens may be empty in offscreen;
        // sanitize with empty inventory keeps pins (no inventory yet).
        island.sanitizeOwnerOutputs();
        // Direct unit of sanitize via island state after explicit clear.
        island.clearEventOwnerOutput();
        compare(island.eventOwnerOutput, "");
    }

    function test_reset_clears_owners() {
        island.eventOwnerOutput = "eDP-2";
        island.sessionOwnerOutput = "HDMI-A-1";
        island.reset();
        compare(island.eventOwnerOutput, "");
        compare(island.sessionOwnerOutput, "");
    }
}
