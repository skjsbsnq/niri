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
    property var appMenuService
    property var anchorRect: null
    property var settingsService
    property bool darkMode: false
    readonly property int edgePadding: 8
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int screenHeight: Math.max(1, PopupGeometry.numberOr(root.screen && root.screen.height, root.height))
    readonly property int maxPanelHeight: Math.max(180, screenHeight - popupTopMargin - edgePadding)
    readonly property bool nativeMenuAvailable: root.appMenuService && root.appMenuService.nativeMenuAvailable
    readonly property int popupLeftMargin: anchorRect
        ? PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, 96)
        : 96
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: anchorRect
        ? PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, 96)
        : 0
    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 286
    implicitHeight: panel.height
    color: "transparent"
    WlrLayershell.namespace: "tahoe-application-menu"

    onOpenChanged: {
        // Explicit demand: same-identity in-flight health/focus probes must not
        // swallow menu-open freshness (single refresh() entry with demand flag).
        if (open && appMenuService)
            appMenuService.refresh(true);
    }

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    TahoeGlass.regions: [panel.region]

    GlassPanel {
        id: panel

        width: parent.width
        implicitHeight: Math.min(root.maxPanelHeight, content.implicitHeight + 16)
        height: implicitHeight
        material: GlassStyle.MaterialMenu
        radius: GlassStyle.RadiusMenu
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 8
                        color: "#48ffffff"
                        border.color: "#40ffffff"

                        TahoeSymbol {
                            anchors.centerIn: parent
                            name: root.nativeMenuAvailable ? "\ue86c" : "\ue8a0"
                            color: root.darkMode ? "#f5f7fb" : "#202124"
                            size: 18
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: root.appMenuService ? root.appMenuService.activeTitle : "桌面"
                            color: root.darkMode ? "#f5f7fb" : "#1d1d1f"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.appMenuService ? root.appMenuService.menuStatusText : ""
                            color: root.darkMode ? "#94a0ad" : "#721d1d1f"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            visible: text.length > 0
                        }
                    }
                }

                MenuSeparator {
                    darkMode: root.darkMode
                }

                Repeater {
                    model: ScriptModel {
                        objectProp: "modelKey"
                        values: root.nativeMenuAvailable && root.appMenuService
                            ? root.appMenuService.nativeMenuItems
                            : []
                    }

                    delegate: MenuRow {
                        required property var modelData

                        Layout.fillWidth: true
                        text: modelData ? String(modelData.text || "") : ""
                        separator: modelData && String(modelData.kind || "item") === "separator"
                        header: modelData && String(modelData.kind || "item") === "header"
                        enabledRow: !!modelData && !!modelData.enabled
                            && String(modelData.kind || "item") !== "separator"
                            && String(modelData.kind || "item") !== "header"
                        checked: !!modelData && !!modelData.checked
                        showCheckColumn: true
                        hasSubmenu: !!modelData && !!modelData.hasChildren
                        indent: modelData ? Math.max(0, Number(modelData.indent || 0)) : 0
                        settingsService: root.settingsService
                        darkMode: root.darkMode
                        onActivated: {
                            if (!root.appMenuService)
                                return;
                            root.appMenuService.activateNativeItem(modelData);
                        }
                        onFlashFinished: root.closeRequested()
                    }
                }

                MenuSeparator {
                    darkMode: root.darkMode
                    visible: root.nativeMenuAvailable
                }

                MenuRow {
                    text: "固定到 Dock"
                    icon: "\ue866"
                    enabledRow: root.appMenuService && root.appMenuService.hasFocusedWindow
                    settingsService: root.settingsService
                    darkMode: root.darkMode
                    onActivated: {
                        if (root.appMenuService)
                            root.appMenuService.pinFocusedApp();
                    }
                    onFlashFinished: root.closeRequested()
                }

                MenuRow {
                    text: "显示窗口"
                    icon: "\ue8d0"
                    enabledRow: root.appMenuService && root.appMenuService.hasFocusedWindow
                    settingsService: root.settingsService
                    darkMode: root.darkMode
                    onActivated: {
                        if (root.appMenuService)
                            root.appMenuService.activateFocusedWindow();
                    }
                    onFlashFinished: root.closeRequested()
                }

                MenuRow {
                    text: "最小化"
                    icon: "\ue15b"
                    enabledRow: root.appMenuService && root.appMenuService.hasFocusedWindow
                    settingsService: root.settingsService
                    darkMode: root.darkMode
                    onActivated: {
                        if (root.appMenuService)
                            root.appMenuService.minimizeFocusedWindow();
                    }
                    onFlashFinished: root.closeRequested()
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.open
        onClicked: root.closeRequested()
    }
}
