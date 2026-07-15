pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// V2 workspace transient (T18): index/name + optional dots.
// Directional slide is applied by Content via layer offset (activation direction).
Item {
    id: root

    property string workspaceLabel: ""
    property int workspaceIndex: 0
    property int workspaceCount: 0
    property int direction: 0 // -1 left, +1 right, 0 none
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"

    readonly property string indexText: {
        if (root.workspaceIndex > 0)
            return String(root.workspaceIndex);
        // Fall back to leading token of label (e.g. "Workspace 2").
        var label = String(root.workspaceLabel || "").trim();
        var m = label.match(/(\d+)/);
        return m ? m[1] : "";
    }
    readonly property string nameText: {
        var label = String(root.workspaceLabel || "").trim();
        if (label.length === 0)
            return "";
        // Prefer trailing name after "Workspace N".
        var cleaned = label.replace(/^Workspace\s+\d+\s*/i, "").trim();
        return cleaned.length > 0 ? cleaned : label;
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Text {
            text: root.indexText
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 0
            visible: text.length > 0
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            text: root.nameText
            color: root.textSecondary
            font.pixelSize: 13
            font.letterSpacing: 0
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: text.length > 0
            width: Math.min(implicitWidth, 96)
            verticalAlignment: Text.AlignVCenter
        }

        Row {
            spacing: 5
            anchors.verticalCenter: parent.verticalCenter
            visible: root.workspaceCount >= 2 && root.workspaceCount <= 6

            Repeater {
                model: Math.max(0, Math.min(6, root.workspaceCount))
                delegate: Rectangle {
                    required property int index
                    width: 5
                    height: 5
                    radius: 2.5
                    color: (index + 1) === root.workspaceIndex
                           ? root.accentColor
                           : "#40ffffff"
                }
            }
        }
    }
}
