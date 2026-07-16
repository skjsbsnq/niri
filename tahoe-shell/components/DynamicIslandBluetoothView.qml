pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Small, single-event Bluetooth lifecycle scene. Device lists stay in the
// Control Center; this view only renders one immutable event snapshot.
Item {
    id: root

    property string kind: "connected"
    property string deviceName: "蓝牙设备"
    property string deviceIcon: ""
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"

    function kindLabel() {
        switch (String(root.kind || "")) {
        case "connecting": return "正在连接";
        case "connected": return "已连接";
        case "failed": return "连接失败";
        case "disconnected": return "已断开";
        default: return "蓝牙";
        }
    }

    function kindSymbol() {
        switch (String(root.kind || "")) {
        case "connecting": return "\ue1ad";
        case "failed": return "\ue001";
        default: return "\ue1a7";
        }
    }

    function iconSource() {
        var name = String(root.deviceIcon || "").trim();
        if (name.length === 0)
            return "";
        if (name.charAt(0) === "/")
            return name;
        var themed = Quickshell.iconPath(name, true);
        return themed && themed.length > 0 ? themed : "";
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10

        Item {
            width: 32
            height: 32
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 9
                color: root.kind === "failed" ? "#32ff453a" : "#24ffffff"
            }

            Image {
                id: deviceImage
                anchors.fill: parent
                anchors.margins: 5
                source: root.iconSource()
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready && source.toString().length > 0
            }

            TahoeSymbol {
                anchors.centerIn: parent
                name: root.kindSymbol()
                color: root.kind === "failed" ? "#ff9f0a" : root.accentColor
                size: 20
                visible: !deviceImage.visible
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, parent.width - 42)
            spacing: 2

            Text {
                width: parent.width
                text: root.kindLabel()
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: root.deviceName
                color: root.textSecondary
                font.pixelSize: 12
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
