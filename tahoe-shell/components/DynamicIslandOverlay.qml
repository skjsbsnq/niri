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
    property string lastIslandState: "resting_time"
    property string exitExpandedState: ""
    property bool exitingExpanded: false
    property string lastExpandedDisplayText: ""
    property string lastExpandedSecondaryText: ""
    property string lastExpandedIconCode: ""
    readonly property string islandState: dynamicIslandService ? String(dynamicIslandService.state || "resting_time") : "resting_time"
    readonly property string geometryState: exitingExpanded ? exitExpandedState : islandState
    readonly property string contentState: exitingExpanded ? exitExpandedState : islandState
    readonly property string displayText: dynamicIslandService ? String(dynamicIslandService.displayText || "") : ""
    readonly property string secondaryText: dynamicIslandService ? String(dynamicIslandService.secondaryText || "") : ""
    readonly property string iconCode: dynamicIslandService ? String(dynamicIslandService.iconCode || "") : ""
    readonly property string contentDisplayText: exitingExpanded ? lastExpandedDisplayText : displayText
    readonly property string contentSecondaryText: exitingExpanded ? lastExpandedSecondaryText : secondaryText
    readonly property string contentIconCode: exitingExpanded ? lastExpandedIconCode : iconCode
    readonly property real progress: dynamicIslandService ? Number(dynamicIslandService.progress) : -1
    readonly property string ownScreenName: root.screen ? String(root.screen.name || "") : ""
    readonly property string targetScreenName: dynamicIslandService ? String(dynamicIslandService.targetScreenName || "") : ""
    readonly property bool islandEnabled: dynamicIslandService ? !!dynamicIslandService.islandEnabled : true
    readonly property bool dynamicIslandHideTopbarTime: dynamicIslandService ? !!dynamicIslandService.dynamicIslandHideTopbarTime : true
    readonly property bool hoverExpandEnabled: dynamicIslandService ? !!dynamicIslandService.dynamicIslandHoverExpand : false
    readonly property bool activeForScreen: !!dynamicIslandService
        && (targetScreenName.length === 0 || ownScreenName.length === 0 || targetScreenName === ownScreenName)
    readonly property bool capsuleShown: activeForScreen
        && islandEnabled
        && (dynamicIslandHideTopbarTime
            || !isRestingState(geometryState)
            || exitingExpanded
            || swipeInteractive
            || swipeSettling)
    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property bool swipeInteractive: dynamicIslandService ? !!dynamicIslandService.swipeDragging : false
    readonly property bool swipeSettling: dynamicIslandService ? !!dynamicIslandService.swipeSettling : false
    readonly property real swipePreviewWidth: dynamicIslandService ? Number(dynamicIslandService.swipePreviewWidth) : -1
   readonly property int capsuleTargetWidth: swipePreviewWidth > 0 ? Math.round(swipePreviewWidth) : widthForState(geometryState)
    readonly property int swipeWidthDuration: swipeInteractive ? 0 : (swipeSettling ? IslandMotion.swipeSettleDuration : IslandMotion.overlayMorphDuration)
    readonly property int swipeWidthEasing: swipeInteractive ? IslandMotion.overlayColorEasing : (swipeSettling ? IslandMotion.swipeSettleEasing : IslandMotion.overlayMorphEasing)
    readonly property int capsuleTargetHeight: heightForState(geometryState)
    readonly property int capsuleTargetLeft: Math.round(Math.max(0, (screenWidth - capsuleTargetWidth) / 2))
    readonly property int capsuleTargetTop: 0
    readonly property bool compactResting: contentState === "resting_time" || contentState === "resting_media"
    readonly property bool compactContentVisible: !exitingExpanded && compactResting
    readonly property bool mediaContentVisible: !exitingExpanded && contentState === "expanded_media"
    readonly property bool summaryContentVisible: !exitingExpanded && contentState === "expanded_summary"
    readonly property bool showSecondaryText: contentSecondaryText.length > 0
        && !(safeProgress(progress) >= 0 && capsuleTargetHeight <= 44)
    readonly property color glassFill: "#f00b0c10"
    readonly property color glassFillExpanded: "#f2131419"
    readonly property color glassStroke: "#2effffff"
    readonly property color textPrimary: "#f7f9fc"
   readonly property color textSecondary: "#b9c0cc"
    readonly property string mediaArtUrl: dynamicIslandService ? String(dynamicIslandService.mediaArtUrl || "") : ""
    readonly property string mediaTrackTitle: contentDisplayText
    readonly property string mediaTrackArtist: contentSecondaryText
    readonly property bool mediaPlaying: dynamicIslandService ? !!dynamicIslandService.mediaPlaying : false
    readonly property real mediaPosition: dynamicIslandService ? Number(dynamicIslandService.mediaPosition) : 0
    readonly property real mediaLength: dynamicIslandService ? Number(dynamicIslandService.mediaLength) : 0
    readonly property real mediaProgress: dynamicIslandService ? Number(dynamicIslandService.mediaProgress) : 0
    readonly property bool mediaPositionSupported: dynamicIslandService ? !!dynamicIslandService.mediaPositionSupported : false
    readonly property bool mediaLengthSupported: dynamicIslandService ? !!dynamicIslandService.mediaLengthSupported : false
    readonly property bool canPlayPause: dynamicIslandService ? !!dynamicIslandService.canPlayPause : false
    readonly property bool canPrev: dynamicIslandService ? !!dynamicIslandService.canPrev : false
    readonly property bool canNext: dynamicIslandService ? !!dynamicIslandService.canNext : false
    readonly property int summaryBatteryPercent: dynamicIslandService ? Number(dynamicIslandService.summaryBatteryPercent) : 0
    readonly property bool summaryBatteryCharging: dynamicIslandService ? !!dynamicIslandService.summaryBatteryCharging : false
    readonly property real summaryVolume: dynamicIslandService ? Number(dynamicIslandService.summaryVolume) : 0
    readonly property bool summaryMuted: dynamicIslandService ? !!dynamicIslandService.summaryMuted : false
    readonly property real summaryBrightness: dynamicIslandService ? Number(dynamicIslandService.summaryBrightness) : 0
    readonly property bool summaryBrightnessAvailable: dynamicIslandService ? !!dynamicIslandService.summaryBrightnessAvailable : false
    readonly property string summaryWorkspaceLabel: dynamicIslandService ? String(dynamicIslandService.summaryWorkspaceLabel || "") : ""

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

    function isExpandedState(stateName) {
        return stateName === "expanded_media" || stateName === "expanded_summary";
    }

    function isRestingState(stateName) {
        return stateName === "resting_time" || stateName === "resting_media";
    }

    function rememberExpandedContent() {
        if (!isExpandedState(root.islandState))
            return;

        root.lastExpandedDisplayText = root.displayText;
        root.lastExpandedSecondaryText = root.secondaryText;
        root.lastExpandedIconCode = root.iconCode;
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

    Component.onCompleted: {
        root.lastIslandState = root.islandState;
        rememberExpandedContent();
    }

    onIslandStateChanged: {
        var previous = root.lastIslandState;
        root.lastIslandState = root.islandState;

        if (isExpandedState(previous) && !isExpandedState(root.islandState)) {
            root.exitExpandedState = previous;
            root.exitingExpanded = true;
            expandedExitHold.restart();
        } else {
            expandedExitHold.stop();
            root.exitingExpanded = false;
            root.exitExpandedState = "";
            rememberExpandedContent();
        }
    }

    onDisplayTextChanged: rememberExpandedContent()
    onSecondaryTextChanged: rememberExpandedContent()
    onIconCodeChanged: rememberExpandedContent()

    Timer {
        id: expandedExitHold
        interval: IslandMotion.overlayExpandedExitHoldMs
        repeat: false
        onTriggered: {
            root.exitingExpanded = false;
            root.exitExpandedState = "";
        }
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
            NumberAnimation { duration: root.swipeWidthDuration; easing.type: root.swipeWidthEasing }
        }

        Behavior on y {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on width {
            NumberAnimation { duration: root.swipeWidthDuration; easing.type: root.swipeWidthEasing }
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
        radius: root.radiusForState(root.geometryState, height)
        clip: true
        color: root.geometryState === "expanded_media" || root.geometryState === "expanded_summary"
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
            NumberAnimation { duration: root.swipeWidthDuration; easing.type: root.swipeWidthEasing }
        }

        Behavior on y {
            NumberAnimation { duration: IslandMotion.overlayMorphDuration; easing.type: IslandMotion.overlayMorphEasing }
        }

        Behavior on width {
            NumberAnimation { duration: root.swipeWidthDuration; easing.type: root.swipeWidthEasing }
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
           islandState: root.contentState
           displayText: root.contentDisplayText
           secondaryText: root.contentSecondaryText
           iconCode: root.contentIconCode
           progress: root.progress
           compactResting: root.compactResting
           compactContentVisible: root.compactContentVisible
           mediaExpandedContentVisible: root.mediaContentVisible
           summaryExpandedContentVisible: root.summaryContentVisible
           showSecondaryText: root.showSecondaryText
           textPrimary: root.textPrimary
           textSecondary: root.textSecondary
            mediaArtUrl: root.mediaArtUrl
            mediaTrackTitle: root.mediaTrackTitle
            mediaTrackArtist: root.mediaTrackArtist
            mediaPlaying: root.mediaPlaying
            mediaPosition: root.mediaPosition
            mediaLength: root.mediaLength
            mediaProgress: root.mediaProgress
            mediaPositionSupported: root.mediaPositionSupported
            mediaLengthSupported: root.mediaLengthSupported
            canPlayPause: root.canPlayPause
            canPrev: root.canPrev
            canNext: root.canNext
            summaryBatteryPercent: root.summaryBatteryPercent
            summaryBatteryCharging: root.summaryBatteryCharging
            summaryVolume: root.summaryVolume
            summaryMuted: root.summaryMuted
            summaryBrightness: root.summaryBrightness
            summaryBrightnessAvailable: root.summaryBrightnessAvailable
            summaryWorkspaceLabel: root.summaryWorkspaceLabel
            onMediaPreviousRequested: if (root.dynamicIslandService) root.dynamicIslandService.mediaPrevious()
            onMediaPlayPauseRequested: if (root.dynamicIslandService) root.dynamicIslandService.mediaTogglePlayPause()
            onMediaNextRequested: if (root.dynamicIslandService) root.dynamicIslandService.mediaNext()
            onMediaControlPressed: if (root.dynamicIslandService) root.dynamicIslandService.setUserInteracting(true)
        }

        MouseArea {
           anchors.fill: parent
           enabled: root.capsuleShown
           hoverEnabled: true
           acceptedButtons: Qt.LeftButton | Qt.RightButton
           cursorShape: Qt.PointingHandCursor
           property real swipeStartX: 0
           property real swipeLastX: 0
           property real swipeStartY: 0
           property bool armingSwipe: false
           property bool suppressClick: false
       
           Timer {
               id: swipeClickSuppress
               interval: IslandMotion.swipeSuppressClickMs
               repeat: false
               onTriggered: parent.suppressClick = false
           }

            Timer {
                id: hoverExpandDelay
                interval: IslandMotion.hoverExpandDelayMs
                repeat: false
                onTriggered: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.requestHoverExpand();
                }
            }

            Timer {
                id: hoverCollapseDelay
                interval: IslandMotion.hoverCollapseDelayMs
                repeat: false
                onTriggered: {
                    if (root.dynamicIslandService)
                        root.dynamicIslandService.requestHoverCollapse();
                }
            }

            onEntered: {
                if (!root.hoverExpandEnabled || !root.dynamicIslandService)
                    return;
                hoverCollapseDelay.stop();
                hoverExpandDelay.restart();
            }

            onExited: {
                hoverExpandDelay.stop();
                if (root.hoverExpandEnabled && root.dynamicIslandService)
                    hoverCollapseDelay.restart();
            }
       
           onPressed: function(mouse) {
               hoverExpandDelay.stop();
               hoverCollapseDelay.stop();
               if (root.dynamicIslandService)
                   root.dynamicIslandService.setUserInteracting(true);
               swipeStartX = mouse.x;
               swipeStartY = mouse.y;
               swipeLastX = mouse.x;
               armingSwipe = (mouse.button === Qt.LeftButton)
                   && root.dynamicIslandService
                   && root.dynamicIslandService.canSwipe();
           }
           onPositionChanged: function(mouse) {
               if (!pressed || !armingSwipe || !root.dynamicIslandService)
                   return;
       
               var deltaX = mouse.x - swipeLastX;
               var deltaY = Math.abs(mouse.y - swipeStartY);
               swipeLastX = mouse.x;
               if (!root.dynamicIslandService.swipeDragging)
                   root.dynamicIslandService.beginSwipe();
               root.dynamicIslandService.advanceSwipe(deltaX, deltaY);
           }
           onReleased: function(mouse) {
               if (root.dynamicIslandService) {
                   if (root.dynamicIslandService.swipeDragging) {
                       var moved = root.dynamicIslandService.consumeSwipeMoved();
                       root.dynamicIslandService.resolveSwipe();
                       if (moved) {
                           suppressClick = true;
                           swipeClickSuppress.restart();
                       }
                   }
                   root.dynamicIslandService.setUserInteracting(false);
               }
               armingSwipe = false;
           }
           onCanceled: {
               if (root.dynamicIslandService && root.dynamicIslandService.swipeDragging)
                   root.dynamicIslandService.cancelSwipe();
               if (root.dynamicIslandService)
                   root.dynamicIslandService.setUserInteracting(false);
               armingSwipe = false;
           }
           onClicked: function(mouse) {
               if (suppressClick)
                   return;
               if (root.dynamicIslandService)
                   root.dynamicIslandService.handleChipClick(mouse.button);
           }
           onWheel: function(wheel) {
               if (!root.dynamicIslandService || !root.dynamicIslandService.canSwipe())
                   return;
       
               var deltaX = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 4;
               var deltaY = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 4;
               var effective = Math.abs(deltaX) > Math.abs(deltaY) ? deltaX : deltaY;
               if (effective === 0)
                   return;
       
               if (!root.dynamicIslandService.swipeDragging)
                   root.dynamicIslandService.beginSwipe();
               root.dynamicIslandService.advanceSwipe(effective * 0.8, 0);
               wheelSwipeSettle.restart();
           }
       
            Timer {
                id: wheelSwipeSettle
                interval: IslandMotion.swipeSettleIdleMs
               repeat: false
               onTriggered: {
                   if (root.dynamicIslandService && root.dynamicIslandService.swipeDragging)
                       root.dynamicIslandService.resolveSwipe();
               }
           }
       }
    }
}
