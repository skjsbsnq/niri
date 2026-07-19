pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Motion.js" as Motion

Item {
    id: root

    property var windowsService
    property var thumbnailProvider
    property var appsService
    property var settingsService
    // See Dock.qml useSpring — forwarded to DockMinimizedWindow bounce.
    property bool useSpring: false
    property var dockWindow
    property var dockSurfaceItem
    property real dockSlideOffset: 0
    property int thumbnailWidth: 112
    readonly property var minimizedWindows: windowsService && windowsService.minimizedWindowList
        ? windowsService.minimizedWindowList
        : []
    readonly property bool hasWindows: minimizedWindows.length > 0

    signal contextMenuRequested(var window, var anchorItem)
    signal dockPointerMoved(real x, int buttons)
    signal dockPointerEntered()
    signal dockPointerExited()

    height: 64
    opacity: hasWindows ? 1 : 0
    scale: hasWindows ? 1 : 0.9
    transformOrigin: Item.Bottom
    visible: hasWindows || opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
    }

    Behavior on scale {
        NumberAnimation { duration: Motion.elementResize(root.settingsService); easing.type: Motion.emphasizedDecel }
    }

    ListView {
        id: viewport

        x: 0
        y: -30
        width: parent.width
        height: parent.height + 30
        topMargin: 30
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width + 1
        model: ScriptModel {
            objectProp: "modelKey"
            values: root.minimizedWindows
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "lifecycleOpacity"
                    from: 0
                    to: 1
                    duration: Motion.fadeFast(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
                NumberAnimation {
                    property: "lifecycleScale"
                    from: 0.9
                    to: 1
                    duration: Motion.elementResize(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
            }
        }

        remove: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "lifecycleOpacity"
                    from: 1
                    to: 0
                    duration: Motion.fadeFast(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
                NumberAnimation {
                    property: "lifecycleScale"
                    from: 1
                    to: 0.9
                    duration: Motion.elementResize(root.settingsService)
                    easing.type: Motion.emphasizedDecel
                }
            }
        }

        move: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Motion.elementMove(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
        }

        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Motion.elementMove(root.settingsService)
                easing.type: Motion.emphasizedDecel
            }
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
            useSpring: root.useSpring
            dockWindow: root.dockWindow
            dockSurfaceItem: root.dockSurfaceItem
            dockSlideOffset: root.dockSlideOffset
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
