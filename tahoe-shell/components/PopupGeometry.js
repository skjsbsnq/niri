.pragma library

function numberOr(value, fallback) {
    var number = Number(value);
    return isFinite(number) ? number : fallback;
}

function screenWidth(screen, fallbackWidth) {
    return Math.max(1, numberOr(screen && screen.width, fallbackWidth));
}

function anchorCenterX(anchorRect, width, popupWidth, fallbackRight) {
    if (anchorRect) {
        var x = numberOr(anchorRect.x, 0);
        var w = numberOr(anchorRect.width, numberOr(anchorRect.w, 1));
        return x + w / 2;
    }

    return width - fallbackRight - popupWidth / 2;
}

function popupLeft(anchorRect, popupWidth, width, edgePadding, fallbackRight) {
    var maxLeft = Math.max(edgePadding, width - popupWidth - edgePadding);
    var centerX = anchorCenterX(anchorRect, width, popupWidth, fallbackRight);
    return Math.round(Math.max(edgePadding, Math.min(maxLeft, centerX - popupWidth / 2)));
}

function popupTop(anchorRect, fallbackTop, gap) {
    if (!anchorRect)
        return fallbackTop;

    var y = numberOr(anchorRect.y, 0);
    var h = numberOr(anchorRect.height, numberOr(anchorRect.h, 0));
    return Math.round(Math.max(0, y + h + gap));
}

function originX(anchorRect, popupLeft, popupWidth, width, fallbackRight) {
    var centerX = anchorCenterX(anchorRect, width, popupWidth, fallbackRight);
    return Math.max(0, Math.min(popupWidth, centerX - popupLeft));
}
