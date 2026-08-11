pragma ComponentBehavior: Bound

import QtQuick
import ".."

// 电池小部件（small 2×2）—— A2 基类验证载体。
// 数据源：services/Battery.qml（UPower 事件驱动，零轮询，见 A-5）。
// 遵守 A-C3：本组件不建任何 Timer / 不 spawn 进程，只读注入的
// batteryService；previewMode 下显示真实当前值但不随事件刷新
// （A5 库预览禁止数据刷新）。
Widget {
    id: root

    property var batteryService

    // 实时值（live = hostVisible，即非 previewMode）。
    readonly property bool _liveAvailable: !!root.batteryService && root.batteryService.available
    readonly property int _livePercent: root._liveAvailable ? root.batteryService.roundedPercentage : 0
    readonly property bool _liveCharging: root._liveAvailable && !!root.batteryService && root.batteryService.charging
    readonly property bool _liveOnBattery: root._liveAvailable && !!root.batteryService && root.batteryService.onBattery

    // 预览/隐藏快照：进入非 live 时锁存一次，之后不再随 UPower 事件
    // 重算（A2 previewMode 行为：禁用数据刷新；A5 库预览依赖它）。
    // onLiveChanged 只在【转换】时发射——以 previewMode=true 作为初始
    // 属性创建（A5 预览实例的常见方式）不触发它，故 onCompleted 兜底
    // 锁存一次（初始即非 live 时用创建时的真实值）。
    property bool _snapAvailable: false
    property int _snapPercent: 0
    property bool _snapCharging: false
    property bool _snapOnBattery: false
    function latchSnapshot() {
        root._snapAvailable = root._liveAvailable;
        root._snapPercent = root._livePercent;
        root._snapCharging = root._liveCharging;
        root._snapOnBattery = root._liveOnBattery;
    }
    onLiveChanged: {
        if (!root.live)
            root.latchSnapshot();
    }
    Component.onCompleted: {
        if (!root.live)
            root.latchSnapshot();
    }

    readonly property bool live: root.dataRefreshActive
    readonly property bool available: root.live ? root._liveAvailable : root._snapAvailable
    readonly property int percentage: root.available ? (root.live ? root._livePercent : root._snapPercent) : 0
    readonly property bool charging: root.available && (root.live ? root._liveCharging : root._snapCharging)
    readonly property bool onBattery: root.available && (root.live ? root._liveOnBattery : root._snapOnBattery)

    // 低电量着色（照 BatteryPopup 语义：≤15% 且使用电池时警示色）。
    readonly property color percentColor: root.available
        && root.percentage <= 15
        && root.onBattery
        ? "#ff453a" : "#ffffff"

    // ---- 视觉（部署反馈修复：图标与百分比卡在一起）----
    // 旧布局用 cellSize 绝对偏移（bolt topMargin 0.45*cell、半透明轮廓
    // 居中、百分比 bottomMargin 0.22*cell）；实例因 gap 内缩 12px 后，
    // bolt 与轮廓互相挤压、百分比压上轮廓下沿。改为锚链顺序排布：
    // 轮廓贴顶（bolt 叠加其中心）、百分比锚在轮廓下沿、状态文本贴底 ——
    // 任意实例高度下三者互不重叠。
    TahoeSymbol {
        id: batteryShell

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(4, Math.round(root.height * 0.05))
        name: ""
        color: root.percentColor
        size: Math.min(52, Math.round(root.width * 0.58))
        opacity: 0.5
        asynchronous: true
    }

    // 充电 e1a3 / 放电 e1a4（与 BatteryPopup 一致）：叠加在轮廓中心。
    TahoeSymbol {
        id: icon

        anchors.centerIn: batteryShell
        name: root.charging ? "" : ""
        color: root.percentColor
        size: Math.min(40, Math.round(root.width * 0.46))
        asynchronous: true
    }

    // 百分比：锚在轮廓下沿 + 固定间隙，永远在图标之下、互不重叠。
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: batteryShell.bottom
        anchors.topMargin: Math.max(2, Math.round(root.height * 0.04))
        text: root.percentage + "%"
        color: "#ffffff"
        font.pixelSize: Math.min(26, Math.round(root.width * 0.26))
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: {
            if (!root.live || !root.available)
                return "";
            if (root.batteryService && root.batteryService.stateText.length > 0)
                return root.batteryService.stateText;
            return root.charging ? "充电中" : "";
        }
        color: "#b3ffffff"
        font.pixelSize: Math.max(10, Math.round(root.cellSize * 0.16))
        horizontalAlignment: Text.AlignHCenter
        visible: text.length > 0
    }
}
