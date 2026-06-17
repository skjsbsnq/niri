pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower

// UPower-backed battery state exposed as simple display strings for panels.
//
// Real-machine fix (roadmap T04): the top bar showed a flat "1%" while UPower
// reported 100%. Two causes handled here:
//   1. Prefer a real laptop-battery device over the aggregate displayDevice,
//      which may report a placeholder before it is ready.
//   2. Normalize the percentage against both the 0..100 and 0..1 scales — some
//      Quickshell builds surface percentage as a 0..1 fraction, which rounds
//      to 0 and reads as ~1% with the outline's Math.max(2, ...) floor.
Item {
    id: root
    visible: false

    // Prefer a real laptop battery; fall back to the aggregate display device.
    readonly property var realDevice: {
        try {
            var devs = UPower.devices.values;
            for (var i = 0; i < devs.length; i++) {
                var d = devs[i];
                if (d && d.isLaptopBattery)
                    return d;
            }
        } catch (e) {}
        return UPower.displayDevice;
    }

    readonly property bool ready: !!realDevice
        && (realDevice.ready === undefined || realDevice.ready === true)

    // Tolerate both 0..1 and 0..100 scales.
    function normalizePercent(raw) {
        var n = Number(raw);
        if (isNaN(n))
            return 0;
        if (n > 0 && n <= 1.0)
            return n * 100;   // 0..1 -> 0..100
        return n;
    }

    readonly property real rawPercent: ready ? normalizePercent(realDevice.percentage) : 0
    readonly property bool available: ready && rawPercent > 1
    readonly property real percentage: available ? Math.max(0, Math.min(100, rawPercent)) : 0
    readonly property int roundedPercentage: Math.round(percentage)
    readonly property int state: available ? Number(realDevice.state) : UPowerDeviceState.Unknown
    readonly property bool charging: state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge
    readonly property bool fullyCharged: state === UPowerDeviceState.FullyCharged
    readonly property bool discharging: state === UPowerDeviceState.Discharging || state === UPowerDeviceState.PendingDischarge
    readonly property bool onBattery: UPower.onBattery
    readonly property string iconName: available ? String(realDevice.iconName || "") : ""
    readonly property string stateText: stateLabel(state)
    readonly property string powerSourceText: available
        ? (onBattery ? "电池" : "电源适配器")
        : "不可用"
    readonly property string timeText: timeLabel()
    readonly property string healthText: healthLabel()

    Component.onCompleted: logState("completed")
    onReadyChanged: logState("readyChanged")
    onRawPercentChanged: logState("rawPercentChanged")

    function logState(reason) {
        console.log("[Battery]", reason,
                    "realDevice:", realDevice,
                    "rawPercent:", rawPercent,
                    "isLaptop:", realDevice && realDevice.isLaptopBattery,
                    "ready:", ready);
    }

    function stateLabel(value) {
        if (!available)
            return "无电池";
        if (value === UPowerDeviceState.Charging)
            return "充电中";
        if (value === UPowerDeviceState.Discharging)
            return "使用电池";
        if (value === UPowerDeviceState.Empty)
            return "电量耗尽";
        if (value === UPowerDeviceState.FullyCharged)
            return "已充满";
        if (value === UPowerDeviceState.PendingCharge)
            return "等待充电";
        if (value === UPowerDeviceState.PendingDischarge)
            return "等待放电";
        return onBattery ? "使用电池" : "电源适配器";
    }

    function formatSeconds(value) {
        var seconds = Math.max(0, Math.round(Number(value) || 0));
        if (seconds <= 0)
            return "";

        var minutes = Math.round(seconds / 60);
        var hours = Math.floor(minutes / 60);
        var mins = minutes % 60;

        if (hours > 0 && mins > 0)
            return hours + " 小时 " + mins + " 分";
        if (hours > 0)
            return hours + " 小时";
        return mins + " 分钟";
    }

    function timeLabel() {
        if (!available)
            return "";

        if (charging) {
            var full = formatSeconds(realDevice.timeToFull);
            return full.length > 0 ? "充满还需 " + full : "";
        }

        if (discharging) {
            var empty = formatSeconds(realDevice.timeToEmpty);
            return empty.length > 0 ? "剩余 " + empty : "";
        }

        return "";
    }

    function healthLabel() {
        if (!available || !realDevice.healthSupported)
            return "";

        var health = Math.round(Number(realDevice.healthPercentage) || 0);
        if (health <= 0)
            return "";

        return "健康度 " + health + "%";
    }
}
