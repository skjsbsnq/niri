pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower

// UPower-backed battery state exposed as simple display strings for panels.
Item {
    id: root
    visible: false

    readonly property var device: UPower.displayDevice
    readonly property bool ready: !!device && !!device.ready
    readonly property bool available: ready && (device.isLaptopBattery || device.percentage > 0)
    readonly property real percentage: available ? Math.max(0, Math.min(100, Number(device.percentage) || 0)) : 0
    readonly property int roundedPercentage: Math.round(percentage)
    readonly property int state: available ? Number(device.state) : UPowerDeviceState.Unknown
    readonly property bool charging: state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge
    readonly property bool fullyCharged: state === UPowerDeviceState.FullyCharged
    readonly property bool discharging: state === UPowerDeviceState.Discharging || state === UPowerDeviceState.PendingDischarge
    readonly property bool onBattery: UPower.onBattery
    readonly property string iconName: available ? String(device.iconName || "") : ""
    readonly property string stateText: stateLabel(state)
    readonly property string powerSourceText: available
        ? (onBattery ? "Battery" : "Power Adapter")
        : "Unavailable"
    readonly property string timeText: timeLabel()
    readonly property string healthText: healthLabel()

    function stateLabel(value) {
        if (!available)
            return "No Battery";
        if (value === UPowerDeviceState.Charging)
            return "Charging";
        if (value === UPowerDeviceState.Discharging)
            return "On Battery";
        if (value === UPowerDeviceState.Empty)
            return "Empty";
        if (value === UPowerDeviceState.FullyCharged)
            return "Fully Charged";
        if (value === UPowerDeviceState.PendingCharge)
            return "Waiting to Charge";
        if (value === UPowerDeviceState.PendingDischarge)
            return "Waiting to Discharge";
        return onBattery ? "On Battery" : "Power Adapter";
    }

    function formatSeconds(value) {
        var seconds = Math.max(0, Math.round(Number(value) || 0));
        if (seconds <= 0)
            return "";

        var minutes = Math.round(seconds / 60);
        var hours = Math.floor(minutes / 60);
        var mins = minutes % 60;

        if (hours > 0 && mins > 0)
            return hours + " hr " + mins + " min";
        if (hours > 0)
            return hours + " hr";
        return mins + " min";
    }

    function timeLabel() {
        if (!available)
            return "";

        if (charging) {
            var full = formatSeconds(device.timeToFull);
            return full.length > 0 ? full + " until full" : "";
        }

        if (discharging) {
            var empty = formatSeconds(device.timeToEmpty);
            return empty.length > 0 ? empty + " remaining" : "";
        }

        return "";
    }

    function healthLabel() {
        if (!available || !device.healthSupported)
            return "";

        var health = Math.round(Number(device.healthPercentage) || 0);
        if (health <= 0)
            return "";

        return health + "% health";
    }
}
