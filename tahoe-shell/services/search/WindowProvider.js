.pragma library

function results(query, limit, context) {
    var normalized = String(query || "").trim();
    if (normalized.length === 0 || !context.windowsService)
        return [];

    var windows = context.windowsService.recentWindowList || context.windowsService.windowList || [];
    var max = Math.max(1, limit || context.defaultLimit);
    var out = [];
    for (var i = 0; i < windows.length && out.length < max; i++) {
        var window = windows[i];
        if (!window)
            continue;

        var titleText = title(window, context);
        var subtitleText = subtitle(window, context);
        var score = context.scoreText(titleText, subtitleText, [window.appId || "", window.output || ""], normalized, 820);
        if (score <= 0)
            continue;

        if (window.isFocused)
            score += 16;
        if (window.isMinimized)
            score += 12;

        out.push(context.makeResult({
            "id": "window:" + String(window.modelKey || window.id || i),
            "title": titleText,
            "subtitle": subtitleText,
            "icon": icon(window, context),
            "kind": "window",
            "provider": "windows",
            "score": score,
            "window": window
        }));
    }
    return out;
}

function title(window, context) {
    var titleText = String(window && window.title || "").trim();
    if (titleText.length > 0)
        return titleText;
    if (context.appsService)
        return context.appsService.windowAppLabel(window);
    var appId = String(window && window.appId || "").trim();
    return appId.length > 0 ? appId : "窗口";
}

function subtitle(window, context) {
    var parts = [];
    var app = context.appsService ? context.appsService.windowAppLabel(window) : String(window && window.appId || "").trim();
    if (app.length > 0)
        parts.push(app);
    var workspace = window && window.workspace ? String(window.workspace.name || window.workspace.id || "").trim() : "";
    if (workspace.length > 0)
        parts.push("工作区 " + workspace);
    if (window && window.isMinimized)
        parts.push("已最小化");
    return parts.length > 0 ? parts.join(" · ") : "打开窗口";
}

function icon(window, context) {
    if (!context.appsService)
        return context.iconPath("dock", "finder.png");
    var app = context.appsService.appForWindow(window);
    if (app)
        return context.appsService.iconForApp(app);
    return context.appsService.iconForAppId(window && window.appId ? window.appId : "");
}
