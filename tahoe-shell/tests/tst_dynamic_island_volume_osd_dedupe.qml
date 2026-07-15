import QtQuick
import QtTest
import "../services" as Services

TestCase {
    id: testCase
    name: "DynamicIslandVolumeOsdBaselineLifecycle"
    when: windowShown

    property var island: null

    QtObject {
        id: notifications
        property var activeModel: []
        property bool dndEnabled: false
        signal notificationUpdated(int id)
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

    // Minimal Controls-shaped sink: volume/muted plus audioReady for reconnect.
    QtObject {
        id: controls
        property real volume: 0.4
        property bool muted: false
        property real brightness: 1.0
        property bool brightnessAvailable: false
        property bool audioReady: true
        property bool hasMedia: false
        property string trackArtUrl: ""
        property bool isPlaying: false
        property real trackPosition: 0
        property real trackLength: 0
        property real trackProgress: 0
        property bool trackPositionSupported: false
        property bool trackLengthSupported: false
        // Property change signals are automatic for QML properties.
    }

    QtObject {
        id: windows
        property string activeWorkspaceName: ""
    }

    Component {
        id: islandComponent
        Services.DynamicIsland {}
    }

    function init() {
        notifications.activeModel = [];
        notifications.dndEnabled = false;
        settings.dynamicIslandEnabled = true;
        controls.volume = 0.4;
        controls.muted = false;
        controls.brightness = 1.0;
        controls.brightnessAvailable = false;
        controls.audioReady = true;
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
        // Seed baselines at known values without relying on timer side effects.
        island.captureOsdBaselines();
        wait(0);
        compare(island.lastVolume, 0.4);
        compare(island.lastMuted, false);
        island.forcedState = "";
        island.pendingOsd = null;
        wait(0);
    }

    function cleanup() {
        if (island) {
            island.destroy();
            island = null;
        }
        wait(0);
    }

    function isVolumeOsdVisible() {
        return island.presentation === "transient_osd"
                && island.transientDisplayText !== ""
                && (island.transientDisplayText === "音量"
                    || island.transientDisplayText === "静音");
    }

    function clearOsdPresentation() {
        island.forcedState = "";
        island.clearTransientFields();
        island.pendingOsd = null;
        wait(0);
    }

    function test_disabled_volume_change_resyncs_baseline_without_show() {
        // disabled 期间 0.4→0.6: update baseline, never present.
        settings.dynamicIslandEnabled = false;
        wait(0);
        verify(!island.islandEnabled);

        controls.volume = 0.6;
        wait(0); // property → Connections → callLater
        wait(0); // callLater flush

        compare(island.lastVolume, 0.6);
        compare(isVolumeOsdVisible(), false);
        compare(island.pendingOsd, null);
    }

    function test_reenable_same_volume_does_not_present() {
        // After disable-period 0.4→0.6, reenable with 0.6 must not show OSD.
        settings.dynamicIslandEnabled = false;
        wait(0);
        controls.volume = 0.6;
        wait(0);
        wait(0);
        compare(island.lastVolume, 0.6);

        clearOsdPresentation();
        settings.dynamicIslandEnabled = true;
        wait(0);
        wait(0);

        compare(island.islandEnabled, true);
        compare(island.lastVolume, 0.6);
        compare(isVolumeOsdVisible(), false);
        // Explicit re-emit of the same pair after reenable still suppressed.
        controls.volume = 0.6;
        wait(0);
        wait(0);
        compare(isVolumeOsdVisible(), false);
    }

    function test_reenable_then_real_step_presents() {
        settings.dynamicIslandEnabled = false;
        wait(0);
        controls.volume = 0.6;
        wait(0);
        wait(0);

        settings.dynamicIslandEnabled = true;
        wait(0);
        wait(0);
        clearOsdPresentation();

        controls.volume = 0.5;
        wait(0);
        wait(0);

        compare(island.lastVolume, 0.5);
        verify(isVolumeOsdVisible() || island.pendingOsd !== null
               || island.transientProgress === 0.5);
        // Prefer direct OSD presentation when not blocked.
        if (!island.blocksTransientOsd()) {
            compare(island.presentation, "transient_osd");
            compare(island.transientProgress, 0.5);
            compare(island.transientDisplayText, "音量");
        }
    }

    function test_sink_reconnect_first_value_only_baselines() {
        // Production-shaped cascade: volume follows audioReady (Controls binds
        // volume to 0 while !audioReady, then to the live sink on reconnect).
        island.captureOsdBaselines();
        clearOsdPresentation();
        compare(island.lastVolume, 0.4);
        compare(island.volumeOsdTrackingReady, true);

        controls.audioReady = false;
        controls.volume = 0;
        wait(0);
        wait(0);
        compare(island.volumeOsdTrackingReady, false);
        compare(island.lastVolume, 0);
        clearOsdPresentation();

        // Ready first, then binding publishes sink volume (production order).
        controls.audioReady = true;
        wait(0);
        controls.volume = 0.72;
        wait(0);
        wait(0);

        compare(island.lastVolume, 0.72);
        compare(island.lastMuted, false);
        compare(island.volumeOsdTrackingReady, true);
        // First reconnect value is baseline-only: no volume OSD for that sample.
        compare(isVolumeOsdVisible(), false);

        // A subsequent real step after reconnect still presents.
        clearOsdPresentation();
        controls.volume = 0.5;
        wait(0);
        wait(0);
        if (!island.blocksTransientOsd()) {
            compare(island.presentation, "transient_osd");
            compare(island.transientProgress, 0.5);
        }
    }

    function test_mute_and_volume_same_turn_present_once() {
        clearOsdPresentation();
        island.captureOsdBaselines();
        wait(0);
        compare(island.lastVolume, 0.4);
        compare(island.lastMuted, false);

        // One user action: set both before callLater flushes.
        controls.volume = 0.55;
        controls.muted = true;
        wait(0);
        wait(0);

        compare(island.lastVolume, 0.55);
        compare(island.lastMuted, true);
        if (!island.blocksTransientOsd()) {
            compare(island.presentation, "transient_osd");
            compare(island.transientDisplayText, "静音");
            compare(island.transientProgress, 0);
        }
        // A second flush with identical pair must not re-present a new step.
        var textAfter = island.transientDisplayText;
        island.syncVolumeOsdFromControls();
        wait(0);
        compare(island.transientDisplayText, textAfter);
        compare(island.lastVolume, 0.55);
    }

    function test_rapid_volume_updates_patch_active_osd_in_place() {
        clearOsdPresentation();
        island.captureOsdBaselines();

        controls.volume = 0.41;
        wait(0);
        compare(island.presentation, "transient_osd");
        compare(island.transientProgress, 0.41);
        compare(island.transientIconCode, "\ue04d");
        compare(island.pendingOsd, null);

        controls.volume = 0.64;
        wait(0);
        compare(island.presentation, "transient_osd");
        compare(island.transientProgress, 0.64);
        compare(island.transientSecondaryText, "64%");
        compare(island.transientIconCode, "\ue050");
        compare(island.pendingOsd, null);
    }

    function test_osd_preempts_expanded_and_restores_after_exit() {
        island.showExpandedSummary();
        wait(0);
        compare(island.presentation, "expanded_summary");

        controls.volume = 0.61;
        wait(0);
        compare(island.presentation, "transient_osd");
        compare(island.transientOsdReturnState, "expanded_summary");

        island.beginOsdExit("", "");
        compare(island.transientOsdExiting, true);
        compare(island.transientSecondaryText, "61%");
        wait(140);
        compare(island.presentation, "expanded_summary");
        compare(island.transientOsdExiting, false);
    }

    function test_brightness_icon_tracks_low_medium_high() {
        clearOsdPresentation();
        controls.brightnessAvailable = true;
        wait(0);
        island.captureOsdBaselines();

        controls.brightness = 0.2;
        wait(0);
        compare(island.presentation, "transient_osd");
        compare(island.transientIconCode, "\ue1ad");

        controls.brightness = 0.5;
        wait(0);
        compare(island.transientIconCode, "\ue1ae");

        controls.brightness = 0.8;
        wait(0);
        compare(island.transientIconCode, "\ue1ac");
        compare(island.pendingOsd, null);
    }

    function test_osd_click_defers_action_until_retained_exit_finishes() {
        clearOsdPresentation();
        island.captureOsdBaselines();
        controls.volume = 0.42;
        wait(0);
        compare(island.presentation, "transient_osd");

        island.handleChipClick(Qt.LeftButton, "");
        compare(island.presentation, "transient_osd");
        compare(island.transientOsdExiting, true);
        compare(island.transientSecondaryText, "42%");

        wait(140);
        compare(island.presentation, "expanded_summary");
        compare(island.transientOsdExiting, false);
    }
}
