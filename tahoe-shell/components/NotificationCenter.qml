pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var notificationsService
    property var anchorRect: null

    readonly property var history: notificationsService ? notificationsService.historyModel : []
    readonly property int historyCount: history.length
    readonly property bool dndEnabled: notificationsService ? notificationsService.dndEnabled : false
    readonly property string iconFont: "Material Icons"
    readonly property int edgePadding: 8
    readonly property int fallbackRight: 56
    readonly property int fallbackTop: 28
    readonly property int popupGap: -1
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, fallbackRight)

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 360
    implicitHeight: panel.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-notification-center"

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
            material: panel.tahoeGlassMaterial
            radius: panel.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: panel.opacity
            materialAlpha: panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    Rectangle {
        id: panel
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
        readonly property real tahoeGlassRadius: GlassStyle.RadiusPanel
        property real contentScale: root.open ? 1 : 0.98

        // Keep the compositor glass region anchored; popup motion is content
        // scale/opacity plus material alpha, not region translation.
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.open ? 1 : 0

        transform: Scale {
            origin.x: root.popupOriginX
            origin.y: 0
            xScale: panel.contentScale
            yScale: panel.contentScale
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on contentScale {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Notifications"
                    color: "#1d1d1f"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Item {
                    Layout.preferredWidth: clearLabel.implicitWidth + 18
                    Layout.preferredHeight: 24
                    visible: root.historyCount > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: clearMouse.containsMouse ? "#70ffffff" : "#34ffffff"
                        border.color: "#50ffffff"
                    }

                    Text {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "Clear"
                        color: "#1d1d1f"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.notificationsService)
                                root.notificationsService.clearEverything();
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 42

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: "#52ffffff"
                    border.color: "#4cffffff"
                    border.width: 1
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: root.dndEnabled ? "\ue7f6" : "\ue7f4"
                        color: "#1d1d1f"
                        font.family: root.iconFont
                        font.pixelSize: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Do Not Disturb"
                            color: "#1d1d1f"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.dndEnabled ? "Toasts are muted" : "Toasts are allowed"
                            color: "#881d1d1f"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 22
                        radius: 11
                        color: root.dndEnabled ? "#2c9cf2" : "#32000000"

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            x: root.dndEnabled ? parent.width - width - 2 : 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"

                            Behavior on x {
                                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.notificationsService)
                            root.notificationsService.toggleDnd();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22000000"
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                visible: root.historyCount === 0

                Text {
                    anchors.centerIn: parent
                    text: "No Notifications"
                    color: "#8a1d1d1f"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, Math.max(120, historyColumn.implicitHeight))
                visible: root.historyCount > 0
                contentWidth: width
                contentHeight: historyColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: historyColumn

                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.history

                        delegate: NotificationRow {
                            required property var modelData

                            width: historyColumn.width
                            entry: modelData
                        }
                    }
                }
            }
        }
    }

    component NotificationRow: Item {
        id: row

        property var entry
        readonly property string iconUrl: root.notificationsService
            ? root.notificationsService.iconUrlForHistory(entry)
            : ""

        height: card.implicitHeight

        Rectangle {
            id: card

            width: parent.width
            implicitHeight: rowContent.implicitHeight + 18
            height: implicitHeight
            radius: 14
            color: "#54ffffff"
            border.color: "#48ffffff"
            border.width: 1

            RowLayout {
                id: rowContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 9
                spacing: 9

                Item {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: "#44ffffff"
                    }

                    Image {
                        id: historyIcon
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: row.iconUrl
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: row.iconUrl.length > 0 && status !== Image.Error
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\ue7f4"
                        color: "#661d1d1f"
                        font.family: root.iconFont
                        font.pixelSize: 17
                        visible: !historyIcon.visible
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: row.entry ? row.entry.appName : ""
                            color: "#991d1d1f"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.timeText(row.entry)
                            color: "#731d1d1f"
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        text: row.entry ? row.entry.summary : ""
                        color: "#1d1d1f"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: row.entry ? row.entry.body : ""
                        color: "#991d1d1f"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: text.length > 0
                        Layout.fillWidth: true
                    }
                }

                Item {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: closeMouse.containsMouse ? "#70ffffff" : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\ue5cd"
                        color: "#731d1d1f"
                        font.family: root.iconFont
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.notificationsService && row.entry)
                                root.notificationsService.removeHistoryItem(row.entry.id);
                        }
                    }
                }
            }
        }
    }

    function timeText(entry) {
        if (!entry || !entry.time)
            return "";

        try {
            return Qt.formatTime(entry.time, "HH:mm");
        } catch (e) {
            return "";
        }
    }
}
