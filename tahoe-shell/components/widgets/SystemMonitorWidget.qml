pragma ComponentBehavior: Bound

import QtQuick
import ".."

// 系统监控小部件（small 2×2）—— macOS 风格迷你监控卡。
// 数据源：services/SystemStats.qml（只读注入；服务进程由宿主可见性
// 门控：小部件在场且宿主可见 → 激活既有 SystemStats，宿主隐藏即停，
// 见 shell.qml systemStats.setWidgetDemand 接线，遵守 A-C3）。
// 本组件不建任何 Timer / 不 spawn 进程；刷新门控于 dataRefreshActive：
// 宿主隐藏时锁存快照，显示不再随服务事件变化。
Widget {
    id: root

    property var systemStatsService

    // ---- 实时值（_live* 只依赖服务可用性，live→false 锁存可取最后值）----
    readonly property bool _svcAvailable: !!root.systemStatsService
    readonly property bool _liveAvailable: root._svcAvailable && !!root.systemStatsService.available
    readonly property real _liveCpu: root._liveAvailable ? finiteNumber(root.systemStatsService.cpuUsage, 0) : 0
    readonly property real _liveRam: root._liveAvailable ? finiteNumber(root.systemStatsService.ramUsage, 0) : 0
    readonly property real _liveDisk: root._liveAvailable ? finiteNumber(root.systemStatsService.diskUsage, 0) : 0
    readonly property real _liveNetDown: root._liveAvailable ? finiteNumber(root.systemStatsService.netDownBps, 0) : 0
    readonly property real _liveNetUp: root._liveAvailable ? finiteNumber(root.systemStatsService.netUpBps, 0) : 0

    // 预览/隐藏快照。
    property bool _snapAvailable: false
    property real _snapCpu: 0
    property real _snapRam: 0
    property real _snapDisk: 0
    property real _snapNetDown: 0
    property real _snapNetUp: 0

    function latchSnapshot() {
        root._snapAvailable = root._liveAvailable;
        root._snapCpu = root._liveCpu;
        root._snapRam = root._liveRam;
        root._snapDisk = root._liveDisk;
        root._snapNetDown = root._liveNetDown;
        root._snapNetUp = root._liveNetUp;
    }

    readonly property bool live: root.dataRefreshActive
    onLiveChanged: {
        if (!root.live)
            root.latchSnapshot();
    }
    Component.onCompleted: {
        if (!root.live)
            root.latchSnapshot();
    }

    // ---- 对外显示值 ----
    readonly property bool available: root.live ? root._liveAvailable : root._snapAvailable
    readonly property real cpu: root.live ? root._liveCpu : root._snapCpu
    readonly property real ram: root.live ? root._liveRam : root._snapRam
    readonly property real disk: root.live ? root._liveDisk : root._snapDisk
    readonly property real netDown: root.live ? root._liveNetDown : root._snapNetDown
    readonly property real netUp: root.live ? root._liveNetUp : root._snapNetUp

    // ---- 纯函数辅助 ----
    function finiteNumber(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function fmtBytes(bps) {
        var n = Number(bps);
        if (!isFinite(n) || n <= 0)
            return "0 B/s";
        if (n < 1024)
            return Math.round(n) + " B/s";
        if (n < 1024 * 1024)
            return (n / 1024).toFixed(1) + " KB/s";
        return (n / (1024 * 1024)).toFixed(1) + " MB/s";
    }

    // ---- 视觉（macOS 系统色：CPU 蓝 / 内存绿 / 磁盘紫 + 细圆条）----
    readonly property color textPrimary: "#ffffff"
    readonly property color textSecondary: "#c7ffffff"
    readonly property color colorCpu: "#0a84ff"
    readonly property color colorRam: "#30d158"
    readonly property color colorDisk: "#bf5af2"

    component MetricBar: Column {
        id: metricBar
        required property string labelText
        required property real value
        required property color barColor
        property bool available: true

        spacing: 4

        Item {
            width: parent.width
            height: 12

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: metricBar.labelText
                color: root.textSecondary
                font.pixelSize: 11
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: metricBar.available ? Math.round(metricBar.value) + "%" : "--"
                color: root.textPrimary
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }

        Rectangle {
            width: parent.width
            height: 5
            radius: Math.round(height / 2)
            color: "#33ffffff"

            Rectangle {
                width: Math.max(0, Math.min(parent.width, parent.width * (metricBar.available ? metricBar.value : 0) / 100))
                height: parent.height
                radius: parent.radius
                color: metricBar.barColor
            }
        }
    }

    // 三条指标贴顶、网络行贴底，垂直空间不悬空（macOS 卡片信息密度）。
    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 8

        MetricBar {
            width: parent.width
            labelText: "CPU"
            value: root.cpu
            barColor: root.colorCpu
            available: root.available
        }

        MetricBar {
            width: parent.width
            labelText: "内存"
            value: root.ram
            barColor: root.colorRam
            available: root.available
        }

        MetricBar {
            width: parent.width
            labelText: "磁盘"
            value: root.disk
            barColor: root.colorDisk
            available: root.available
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        height: 14

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "↓ " + root.fmtBytes(root.netDown) + "   ↑ " + root.fmtBytes(root.netUp)
            color: root.textSecondary
            font.pixelSize: 10
        }
    }
}
