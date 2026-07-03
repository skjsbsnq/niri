import QtQuick

QtObject {
    id: popupState

    property bool appMenuOpen: false
    property bool applicationMenuOpen: false
    property bool controlCenterOpen: false
    property bool notificationCenterOpen: false
    property bool batteryPopupOpen: false
    property bool wifiPopupOpen: false
    property bool fanPopupOpen: false
    property bool clipboardPopupOpen: false
    property bool trayMenuOpen: false
    property var trayMenuItem: null
    property var topBarPopupAnchorRect: null
    property string topBarPopupScreenName: ""

    function prepareTopBarPopup(screenName, anchorRect) {
        topBarPopupScreenName = String(screenName || "");
        topBarPopupAnchorRect = anchorRect || null;
    }

    function topBarPopupOpenValue(popupName) {
        switch (popupName) {
        case "appMenu":
            return appMenuOpen;
        case "applicationMenu":
            return applicationMenuOpen;
        case "controlCenter":
            return controlCenterOpen;
        case "notificationCenter":
            return notificationCenterOpen;
        case "battery":
            return batteryPopupOpen;
        case "wifi":
            return wifiPopupOpen;
        case "fan":
            return fanPopupOpen;
        case "clipboard":
            return clipboardPopupOpen;
        case "trayMenu":
            return trayMenuOpen;
        default:
            return false;
        }
    }

    function setTopBarPopupOpen(popupName, open) {
        var nextOpen = Boolean(open);
        switch (popupName) {
        case "appMenu":
            appMenuOpen = nextOpen;
            break;
        case "applicationMenu":
            applicationMenuOpen = nextOpen;
            break;
        case "controlCenter":
            controlCenterOpen = nextOpen;
            break;
        case "notificationCenter":
            notificationCenterOpen = nextOpen;
            break;
        case "battery":
            batteryPopupOpen = nextOpen;
            break;
        case "wifi":
            wifiPopupOpen = nextOpen;
            break;
        case "fan":
            fanPopupOpen = nextOpen;
            break;
        case "clipboard":
            clipboardPopupOpen = nextOpen;
            break;
        case "trayMenu":
            trayMenuOpen = nextOpen;
            if (!nextOpen)
                trayMenuItem = null;
            break;
        }
    }

    function topBarPopupOpenFor(open, screenName) {
        return open && topBarPopupScreenName === String(screenName || "");
    }

    function topBarPopupOpenForName(popupName, screenName) {
        return topBarPopupOpenFor(topBarPopupOpenValue(popupName), screenName);
    }

    function toggleTopBarPopup(popupName, screenName, anchorRect) {
        var wasOpenHere = topBarPopupOpenForName(popupName, screenName);
        prepareTopBarPopup(screenName, anchorRect);
        closeTopBarPopups(popupName);
        setTopBarPopupOpen(popupName, !wasOpenHere);
    }

    function openTopBarTrayMenu(item, screenName, anchorRect) {
        prepareTopBarPopup(screenName, anchorRect);
        closeTopBarPopups("trayMenu");
        trayMenuItem = item;
        trayMenuOpen = true;
    }

    function closeTopBarPopups(except) {
        if (except !== "appMenu")
            appMenuOpen = false;
        if (except !== "applicationMenu")
            applicationMenuOpen = false;
        if (except !== "controlCenter")
            controlCenterOpen = false;
        if (except !== "notificationCenter")
            notificationCenterOpen = false;
        if (except !== "battery")
            batteryPopupOpen = false;
        if (except !== "wifi")
            wifiPopupOpen = false;
        if (except !== "fan")
            fanPopupOpen = false;
        if (except !== "clipboard")
            clipboardPopupOpen = false;
        if (except !== "trayMenu") {
            trayMenuOpen = false;
            trayMenuItem = null;
        }
    }

    function topBarDismissOpenFor(screenName) {
        return topBarPopupOpenFor(appMenuOpen, screenName)
            || topBarPopupOpenFor(applicationMenuOpen, screenName)
            || topBarPopupOpenFor(controlCenterOpen, screenName)
            || topBarPopupOpenFor(notificationCenterOpen, screenName)
            || topBarPopupOpenFor(batteryPopupOpen, screenName)
            || topBarPopupOpenFor(wifiPopupOpen, screenName)
            || topBarPopupOpenFor(fanPopupOpen, screenName)
            || topBarPopupOpenFor(clipboardPopupOpen, screenName)
            || topBarPopupOpenFor(trayMenuOpen, screenName);
    }

    function topBarDismissPopupWidth() {
        if (applicationMenuOpen)
            return 286;
        if (controlCenterOpen)
            return 360;
        if (notificationCenterOpen)
            return 360;
        if (batteryPopupOpen)
            return 292;
        if (wifiPopupOpen)
            return 328;
        if (fanPopupOpen)
            return 328;
        if (clipboardPopupOpen)
            return 360;
        if (trayMenuOpen)
            return 238;
        return 218;
    }

    function topBarDismissPopupHeight() {
        if (applicationMenuOpen)
            return 700;
        if (controlCenterOpen)
            return 380;
        if (notificationCenterOpen)
            return 560;
        if (batteryPopupOpen)
            return 340;
        if (wifiPopupOpen)
            return 520;
        if (fanPopupOpen)
            return 440;
        if (clipboardPopupOpen)
            return 620;
        if (trayMenuOpen)
            return 560;
        return 420;
    }

    function topBarDismissFallbackRight() {
        if (applicationMenuOpen)
            return 96;
        if (notificationCenterOpen)
            return 56;
        if (batteryPopupOpen)
            return 92;
        if (wifiPopupOpen)
            return 132;
        if (fanPopupOpen)
            return 164;
        if (clipboardPopupOpen)
            return 202;
        if (trayMenuOpen)
            return 40;
        return 12;
    }
}
