pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "CalendarLogic.js" as CalendarLogic

// 日历小部件（medium 4×2）—— macOS 风格月历。
// 数据：纯本地计算，零 I/O（CalendarLogic.js 只算月网格）。
// 遵守 A-C3：唯一 Timer 为分钟对齐刷新（借鉴 services/DynamicIsland.qml
// 的 msecsToNextMinute 语义），running 门控于 dataRefreshActive
// （宿主可见且非 previewMode）；宿主隐藏即停，非常驻轮询。
// previewMode 下网格停在创建时刻，不随分钟刷新。
Widget {
    id: root

    property date now: new Date()

    readonly property int gridYear: root.now.getFullYear()
    readonly property int gridMonth: root.now.getMonth() // 0-11
    readonly property var cells: CalendarLogic.monthGrid(root.gridYear, root.gridMonth, root.now)
    readonly property string title: CalendarLogic.monthTitle(root.gridYear, root.gridMonth)
    readonly property string todayLabel: CalendarLogic.todayDayLabel(root.gridYear, root.gridMonth, root.now)

    // 分钟对齐：每次触发重算到下一分钟的毫秒数（DynamicIsland 同款语义）。
    function msecsToNextMinute() {
        return Math.max(250, 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()));
    }

    Timer {
        id: minuteTimer

        interval: root.msecsToNextMinute()
        repeat: true
        running: root.dataRefreshActive
        onRunningChanged: {
            // 恢复运行（宿主可见/previewMode 退出）时立即刷新，避免沿用
            // 停止前遗留的 interval 造成最多 ~60s 的陈旧日期。
            if (running) {
                root.now = new Date();
                minuteTimer.interval = root.msecsToNextMinute();
            }
        }
        onTriggered: {
            root.now = new Date();
            minuteTimer.interval = root.msecsToNextMinute();
            minuteTimer.restart();
        }
    }

    // ---- 视觉（A8：照 macOS 日历小部件：月/年头 + 周首字母 + 42 格
    // 月历；文字色阶读基类 root.text*，深浅外观自适应）----
    readonly property color todayRed: root.darkMode ? "#ff453a" : "#ff3b30"
    readonly property real cellW: Math.max(1, (root.width - 24) / 7)
    // 网格可用高度 = 小部件高 - 上下边距 - 头部/周行（42 格分 6 行）。
    readonly property real gridTop: 12 + root.headerH + 4 + root.weekdayH + 6
    readonly property real cellH: Math.max(1, Math.floor((root.height - root.gridTop - 12) / 6))
    readonly property real headerH: 26
    readonly property real weekdayH: 18

    Item {
        anchors.fill: parent
        anchors.margins: 12

        // 头部：月份标题 + 今日（红字）。用 Item + 两侧锚定，
        // 不用 Row（Row 内 children 不得用左右锚定）。
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.headerH

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: root.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.todayLabel.length > 0 ? "今天 " + root.todayLabel : ""
                color: root.todayRed
                font.pixelSize: 13
                font.weight: Font.Medium
                visible: root.todayLabel.length > 0
            }
        }

        // 周首字母行。
        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: root.headerH + 4
            height: root.weekdayH

            Repeater {
                model: CalendarLogic.weekdayLabels()
                delegate: Text {
                    required property var modelData
                    width: root.cellW
                    height: parent.height
                    text: modelData
                    color: root.textSecondary
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // 月历 42 格。
        Grid {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: root.headerH + 4 + root.weekdayH + 6
            anchors.bottom: parent.bottom
            columns: 7
            rows: 6

            Repeater {
                model: root.cells

                delegate: Item {
                    required property var modelData

                    width: root.cellW
                    height: root.cellH

                    // 今日红底圆。
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(1, Math.min(root.cellW, root.cellH) - 1)
                        height: width
                        radius: width / 2
                        color: root.todayRed
                        visible: modelData.isToday
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.isToday ? "#ffffff"
                            : modelData.inMonth ? (modelData.isWeekend ? root.textSecondary : root.textPrimary)
                            : root.textTertiary
                        font.pixelSize: Math.min(13, Math.max(10, Math.round(root.cellH - 1)))
                        font.weight: modelData.isToday ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
