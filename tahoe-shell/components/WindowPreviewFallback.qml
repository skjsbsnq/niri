pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property string iconSource: ""
    property string title: "窗口"
    property bool minimized: false
    property bool focused: false
    property bool showTitle: false
    property bool showGeometry: false
    property var geometryRect: null
    property int iconSize: 38
    property int titlePixelSize: 10
    property int titleBottomMargin: 7
    property color backgroundColor: "transparent"
    property color titleColor: "#202124"
    property color placeholderColor: "#5a626a"
    property color geometryFillColor: minimized ? "#5f8c929a" : "#8af7fbff"
    property color geometryBorderColor: focused ? "#202124" : "#66ffffff"
    property string fallbackIconCode: "\ue8d0"

    function rectValue(name, fallback) {
        if (!geometryRect || geometryRect[name] === undefined || geometryRect[name] === null)
            return fallback;
        var number = Number(geometryRect[name]);
        return isFinite(number) ? number : fallback;
    }

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        visible: root.backgroundColor.a > 0
    }

    Rectangle {
        x: Math.round(root.rectValue("x", root.width * 0.22))
        y: Math.round(root.rectValue("y", root.height * 0.22))
        width: Math.max(1, Math.round(root.rectValue("width", root.width * 0.56)))
        height: Math.max(1, Math.round(root.rectValue("height", root.height * 0.56)))
        radius: 7
        color: root.geometryFillColor
        border.color: root.geometryBorderColor
        border.width: root.focused ? 2 : 1
        visible: root.showGeometry
    }

    Item {
        id: iconSlot

        width: root.iconSize
        height: root.iconSize
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.showTitle
            ? Math.max(6, Math.round((root.height - root.iconSize - root.titlePixelSize - root.titleBottomMargin) * 0.28))
            : Math.round((root.height - height) / 2)
        visible: !root.showGeometry
        opacity: root.minimized ? 0.58 : 1

        Image {
            id: iconImage

            anchors.fill: parent
            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            visible: root.iconSource.length > 0 && status !== Image.Error
        }

        TahoeSymbol {
            anchors.centerIn: parent
            name: root.fallbackIconCode
            color: root.placeholderColor
            size: Math.max(16, Math.round(root.iconSize * 0.58))
            visible: !iconImage.visible
        }
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.titleBottomMargin
        text: root.title
        color: root.titleColor
        font.pixelSize: root.titlePixelSize
        elide: Text.ElideRight
        maximumLineCount: 1
        horizontalAlignment: Text.AlignHCenter
        visible: root.showTitle
    }
}
