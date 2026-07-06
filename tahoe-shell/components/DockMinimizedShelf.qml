pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root

    property var windowsService
    property var thumbnailProvider
    property var appsService
    property var settingsService
    property var dockWindow
    property var dockSurfaceItem
    property int thumbnailWidth: 112
    readonly property var minimizedWindows: windowsService && windowsService.minimizedWindowList
        ? windowsService.minimizedWindowList
        : []

    signal contextMenuRequested(var window, var anchorItem)
    signal dockPointerMoved(real x, int buttons)
    signal dockPointerEntered()
    signal dockPointerExited()

    height: 64
    visible: minimizedWindows.length > 0 && width > 0

    Flickable {
        id: viewport

        x: 0
        y: -30
        width: parent.width
        height: parent.height + 30
        contentWidth: shelfRow.implicitWidth
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: shelfRow

            y: 30
            spacing: 8

            Repeater {
                model: ScriptModel {
                    objectProp: "modelKey"
                    values: root.minimizedWindows
                }

                delegate: DockMinimizedWindow {
                    id: minimizedWindow

                    required property var modelData

                    width: root.thumbnailWidth
                    windowModel: modelData
                    windowsService: root.windowsService
                    thumbnailProvider: root.thumbnailProvider
                    appsService: root.appsService
                    settingsService: root.settingsService
                    dockWindow: root.dockWindow
                    dockSurfaceItem: root.dockSurfaceItem
                    onDockPointerMoved: function(x, buttons) {
                        root.dockPointerMoved(x, buttons === undefined ? Qt.NoButton : buttons);
                    }
                    onDockPointerEntered: root.dockPointerEntered()
                    onDockPointerExited: root.dockPointerExited()
                    onContextMenuRequested: function(window, anchorItem) {
                        root.contextMenuRequested(window, anchorItem);
                    }
                }
            }
        }
    }
}
