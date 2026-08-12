pragma ComponentBehavior: Bound

import QtQuick
import ".."

// 电池小部件（small 2×2）—— A2 基类验证载体。
// 数据源：services/Battery.qml（UPower 事件驱动，零轮询，见 A-5）。
// 遵守 A-C3：本组件不建任何 Timer / 不 spawn 进程，只读注入的
// batteryService；previewMode 下显示真实当前值但不随事件刷新
// （A5 库预览禁止数据刷新）。
// A8：外观照 macOS Sonoma 电池小部件 —— 居中电池图标 + 大百分比 +
// 状态说明，颜色随深浅外观自适应（充电绿 / 低电量红 / 常规主色）。
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

    // ---- 视觉（A8：照 macOS Sonoma 电池小部件）----
    // 居中列：电池图标（充电绿 / 低电量红 / 常规自适应）+ 大百分比
    // （Semibold，随卡片宽度缩放）+ 状态说明（secondary）。
    // 颜色全部跟随 root.textPrimary / root.textSecondary（深/浅外观
    // 自适应），不再固定白字。
    readonly property color percentColor: {
        if (!root.available)
            return root.textPrimary;
        if (root.percentage <= 15 && root.onBattery)
            return root.darkMode ? "#ff453a" : "#ff3b30";
        if (root.charging)
            return root.darkMode ? "#30d158" : "#34c759";
        return root.textPrimary;
    }
    // 图标尺寸随卡片宽度缩放（small ~27px、medium/large 封顶 40px），
    // 百分比同理（small ~34px、封顶 44px）—— 三档都能完整容纳。
    readonly property real iconSize: Math.min(40, Math.max(26, Math.round(root.width * 0.16)))
    readonly property real percentSize: Math.min(44, Math.max(30, Math.round(root.width * 0.2)))

    Item {
        anchors.fill: parent
        anchors.margins: 14

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Math.max(2, Math.round(root.height * 0.03))

            // 电池轮廓 + 充放电 bolt（与 BatteryPopup 同款字形）。
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize

                TahoeSymbol {
                    id: batteryShell

                    anchors.fill: parent
                    name: "\ue1db"
                    color: root.percentColor
                    opacity: 0.55
                    asynchronous: true
                }

                TahoeSymbol {
                    anchors.centerIn: batteryShell
                    name: root.charging ? "\ue1a3" : "\ue1a4"
                    color: root.percentColor
                    size: Math.round(root.iconSize * 0.8)
                    asynchronous: true
                }
            }

            // 大百分比。
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.percentage + "%"
                color: root.percentColor
                font.pixelSize: root.percentSize
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                lineHeight: 1.0
            }

            // 状态说明（贴底语义由 Column 中心布局承担，不再绝对锚定）。
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (!root.live || !root.available)
                        return "";
                    if (root.batteryService && root.batteryService.stateText.length > 0)
                        return root.batteryService.stateText;
                    return root.charging ? "正在充电" : "";
                }
                color: root.textSecondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                visible: text.length > 0
            }
        }
    }
}
