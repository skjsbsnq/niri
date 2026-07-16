import QtQuick
import QtTest
import "../services" as Services

TestCase {
    id: testCase
    name: "DynamicIslandBluetooth"
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
        property bool hasMedia: false
        property string trackArtUrl: ""
        property bool isPlaying: false
        property real trackPosition: 0
        property real trackLength: 0
        property real trackProgress: 0
        property bool trackPositionSupported: false
        property bool trackLengthSupported: false
        signal bluetoothConnectionEvent(var event)
    }

    QtObject {
        id: windows
        property string activeWorkspaceName: "1"
        property string focusedOutputName: "eDP-2"
        property var focusedWindow: null
        property var activeWorkspace: null
    }

    QtObject {
        id: timerService
        property bool active: false
        property bool finished: false
        property bool running: false
        property bool paused: false
        property string remainingLabel: ""
        signal completed()
        signal cancelled()
        signal started(int seconds)
        signal tick()
    }

    Component {
        id: islandComponent
        Services.DynamicIsland {}
    }

    function event(kind, key, name, output, userInitiated) {
        var value = {
            kind: kind,
            deviceKey: key,
            deviceName: name,
            deviceIcon: "audio-headphones",
            userInitiated: userInitiated === undefined ? true : !!userInitiated
        };
        if (output !== null)
            value.output = output || "eDP-2";
        return value;
    }

    function init() {
        settings.dynamicIslandEnabled = true;
        windows.focusedOutputName = "eDP-2";
        island = islandComponent.createObject(testCase, {
            notificationsService: notifications,
            settingsService: settings,
            controlsService: controls,
            windowsService: windows,
            timerService: timerService
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

    function test_same_device_lifecycle_coalesces_in_place() {
        controls.bluetoothConnectionEvent(event("connecting", "dev-1", "耳机"));
        compare(island.presentation, "transient_bluetooth");
        compare(island.transientBluetoothKind, "connecting");
        compare(island.transientBluetoothDeviceName, "耳机");
        compare(island.pendingBluetoothEvent, null);

        controls.bluetoothConnectionEvent(event("connected", "dev-1", "耳机"));
        compare(island.presentation, "transient_bluetooth");
        compare(island.transientBluetoothKind, "connected");
        compare(island.transientBluetoothDeviceKey, "dev-1");
        compare(island.pendingBluetoothEvent, null);
    }

    function test_notification_blocks_then_drains_bluetooth() {
        island.forcedState = "transient_notification";
        island.displayingNotificationId = 42;
        wait(0);
        controls.bluetoothConnectionEvent(event("connected", "dev-2", "键盘"));
        compare(island.presentation, "transient_notification");
        verify(island.pendingBluetoothEvent !== null);
        compare(island.pendingBluetoothEvent.deviceKey, "dev-2");

        island.displayingNotificationId = -1;
        island.forcedState = "";
        wait(0);
        island.restoreAfterTransient();
        compare(island.presentation, "transient_bluetooth");
        compare(island.transientBluetoothDeviceName, "键盘");
        compare(island.pendingBluetoothEvent, null);
    }

    function test_different_device_queues_behind_current_bluetooth() {
        controls.bluetoothConnectionEvent(event("connected", "dev-a", "鼠标"));
        controls.bluetoothConnectionEvent(event("connected", "dev-b", "手柄"));
        compare(island.transientBluetoothDeviceKey, "dev-a");
        verify(island.pendingBluetoothEvent !== null);
        compare(island.pendingBluetoothEvent.deviceKey, "dev-b");
    }

    function test_event_owner_is_captured_at_creation() {
        controls.bluetoothConnectionEvent(event("connecting", "dev-3", "音箱", "eDP-2"));
        compare(island.eventOwnerOutput, "eDP-2");
        windows.focusedOutputName = "HDMI-A-1";
        compare(island.eventOwnerOutput, "eDP-2");
        compare(island.targetScreenName, "eDP-2");
    }

    function test_user_initiated_event_replaces_background_event() {
        controls.bluetoothConnectionEvent(event("connected", "auto", "自动设备", "eDP-2", false));
        compare(island.transientBluetoothUserInitiated, false);
        controls.bluetoothConnectionEvent(event("connecting", "user", "用户耳机", "eDP-2", true));
        compare(island.transientBluetoothDeviceKey, "user");
        compare(island.transientBluetoothUserInitiated, true);
        compare(island.pendingBluetoothEvent, null);
    }

    function test_real_payload_captures_output_before_queue() {
        island.forcedState = "transient_notification";
        island.displayingNotificationId = 51;
        windows.focusedOutputName = "eDP-2";
        controls.bluetoothConnectionEvent(event("connected", "queued", "键盘", null));
        verify(island.pendingBluetoothEvent !== null);
        compare(island.pendingBluetoothEvent.output, "eDP-2");

        windows.focusedOutputName = "HDMI-A-1";
        island.displayingNotificationId = -1;
        island.forcedState = "";
        wait(0);
        island.restoreAfterTransient();
        compare(island.presentation, "transient_bluetooth");
        compare(island.eventOwnerOutput, "eDP-2");
    }

    function test_same_device_refresh_keeps_original_owner() {
        windows.focusedOutputName = "eDP-2";
        controls.bluetoothConnectionEvent(event("connecting", "stable", "耳机", null));
        compare(island.eventOwnerOutput, "eDP-2");
        windows.focusedOutputName = "HDMI-A-1";
        controls.bluetoothConnectionEvent(event("connected", "stable", "耳机", null));
        compare(island.eventOwnerOutput, "eDP-2");
    }

    function test_reset_clears_pending_bluetooth() {
        island.userInteracting = true;
        controls.bluetoothConnectionEvent(event("connected", "reset", "手柄", null));
        verify(island.pendingBluetoothEvent !== null);
        island.reset();
        compare(island.pendingBluetoothEvent, null);
        compare(island.presentation, "resting_time");
    }

    function test_pending_same_device_keeps_latest_state() {
        island.forcedState = "transient_notification";
        island.displayingNotificationId = 61;
        controls.bluetoothConnectionEvent(event("connected", "latest", "耳机", null, true));
        controls.bluetoothConnectionEvent(event("disconnected", "latest", "耳机", null, false));
        compare(island.pendingBluetoothEvent.kind, "disconnected");
        compare(island.pendingBluetoothEvent.userInitiated, false);
    }

    function test_notification_preemption_captures_new_output() {
        windows.focusedOutputName = "eDP-2";
        controls.bluetoothConnectionEvent(event("connected", "owner-notif", "耳机", null));
        compare(island.eventOwnerOutput, "eDP-2");
        windows.focusedOutputName = "HDMI-A-1";
        island.showTransientNotification("消息", "正文", "应用");
        compare(island.presentation, "transient_notification");
        compare(island.eventOwnerOutput, "HDMI-A-1");
    }

    function test_osd_preemption_captures_new_output() {
        windows.focusedOutputName = "eDP-2";
        controls.bluetoothConnectionEvent(event("connected", "owner-osd", "键盘", null));
        compare(island.eventOwnerOutput, "eDP-2");
        windows.focusedOutputName = "HDMI-A-1";
        island.showTransientOsd("音量", 0.6);
        compare(island.presentation, "transient_osd");
        compare(island.eventOwnerOutput, "HDMI-A-1");
    }
}
