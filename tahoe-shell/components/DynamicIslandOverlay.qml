pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "DynamicIslandMotion.js" as IslandMotion
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var dynamicIslandService
    property bool darkMode: false
    readonly property string islandState: dynamicIslandService ? String(dynamicIslandService.state || "resting_time") : "resting_time"
    readonly property string displayText: dynamicIslandService ? String(dynamicIslandService.displayText || "") : ""
    readonly property string secondaryText: dynamicIslandService ? String(dynamicIslandService.secondaryText || "") : ""
    readonly property string iconCode: dynamicIslandService ? String(dynamicIslandService.iconCode || "") : ""
    readonly property real progress: dynamicIslandService ? Number(dynamicIslandService.progress) : -1
    readonly property string ownScreenName: root.screen ? String(root.screen.name || "") : ""
    readonly property string targetScreenName: dynamicIslandService ? String(dynamicIslandService.targetScreenName || "") : ""
    readonly property bool activeForScreen: !!dynamicIslandService
        && (targetScreenName.length === 0 || ownScreenName.length === 0 || targetScreenName === ownScreenName)
    readonly property bool capsuleShown: activeForScreen
    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int capsuleTargetWidth: widthForState(islandState)
    readonly property int capsuleTargetHeight: heightForState(islandState)
    readonly property int capsuleTargetLeft: Math.round(Math.max(0, (screenWidth - capsuleTargetWidth) / 2))
    readonly property int capsuleTargetTop: 0
    readonly property bool compactResting: islandState === "resting_time" || islandState === "resting_media"
    readonly property bool showSecondaryText: secondaryText.length > 0
        && !(safeProgress(progress) >= 0 && capsuleTargetHeight <= 44)
    readonly property color glassFill: "#f00b0c10"
    readonly property color glassFillExpanded: "#f2131419"
    readonly property color glassStroke: "#2effffff"
    readonly property color textPrimary: "#f7f9fc"
    readonly property color textSecondary: "#b9c0cc"

    function widthForState(stateName) {
        switch (stateName) {
        case "expanded_media":
            return 400;
        case "expanded_summary":
            return 360;
        case "transient_notification":
            return 320;
        case "transient_osd":
        case "transient_workspace":
            return 220;
        case "resting_media":
            return 190;
        case "resting_time":
        default:
            return 140;
        }
    }

    function heightForState(stateName) {
        switch (stateName) {
        case "expanded_media":
            return 165;
        case "expanded_summary":
            return 132;
        case "transient_notification":
            return 56;
        case "transient_osd":
            return 44;
        case "transient_workspace":
        case "resting_media":
        case "resting_time":
        default:
            return 38;
        }
    }

    function radiusForState(stateName, itemHeight) {
        if (stateName === "expanded_media" || stateName === "expanded_summary")
            return 30;

        return itemHeight / 2;
    }

    function safeProgress(value) {
        var number = Number(value);
        if (!isFinite(number) || number < 0)
            return -1;

        return Math.max(0, Math.min(1, number));
    }

    visible: true
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: false
    implicitWidth: screenWidth
    implicitHeight: 220
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "tahoe-dynamic-island"

    anchors {
        left: true
        right: true
        top: true
    }

    mask: Region {
        Region {
            x: Math.round(islandSurface.x)
            y: Math.round(islandSurface.y)
            width: root.capsuleShown ? Math.round(islandSurface.width) : 0
            height: root.capsuleShown ? Math.round(islandSurface.height) : 0
            radius: Math.round(islandSurface.radius)
        }
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: islandSurface
            material: islandSurface.tahoeGlassMaterial
            radius: islandSurface.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: islandSurface.opacity
            materialAlpha: islandSurface.opacity
            enabled: islandSurface.opacity > 0.01
        }
    ]

    Rectangle {
        id: islandShadow

        x: islandSurface.x
        y: islandSurface.y + 2
        width: islandSurface.width
        height: islandSurface.height
        radius: islandSurface.radius
        color: "#42000000"
        opacity: root.capsuleShown ? (root.darkMode ? 0.38 : 0.2) : 0

        Behavior on x {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on y {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on width {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on height {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on radius {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }
    }

    Rectangle {
        id: islandSurface

        readonly property string tahoeGlassMaterial: GlassStyle.MaterialPill
        readonly property real tahoeGlassRadius: radius

        x: root.capsuleTargetLeft
        y: root.capsuleTargetTop
        width: root.capsuleTargetWidth
        height: root.capsuleTargetHeight
        radius: root.radiusForState(root.islandState, height)
        color: root.islandState === "expanded_media" || root.islandState === "expanded_summary"
            ? root.glassFillExpanded
            : root.glassFill
        opacity: root.capsuleShown ? 1 : 0

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.color: root.glassStroke
            border.width: 1
        }

        Behavior on x {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on y {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on width {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on height {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on radius {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on color {
            ColorAnimation { duration: IslandMotion.overlayColorDuration; easing.type: IslandMotion.overlayColorEasing }
        }

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.overlayContentDuration; easing.type: IslandMotion.overlayColorEasing }
        }

        DynamicIslandContent {
            anchors.fill: parent
            islandState: root.islandState
            displayText: root.displayText
            secondaryText: root.secondaryText
            iconCode: root.iconCode
            progress: root.progress
            compactResting: root.compactResting
            showSecondaryText: root.showSecondaryText
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.capsuleShown
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) {
                if (root.dynamicIslandService)
                    root.dynamicIslandService.setUserInteracting(true);
            }
            onReleased: function(mouse) {
                if (root.dynamicIslandService)
                    root.dynamicIslandService.setUserInteracting(false);
            }
            onCanceled: {
                if (root.dynamicIslandService)
                    root.dynamicIslandService.setUserInteracting(false);
            }
            onClicked: function(mouse) {
                if (root.dynamicIslandService)
                    root.dynamicIslandService.handleChipClick(mouse.button);
            }
        }
    }
}
