.pragma library

function results(query, limit, context) {
    var normalized = String(query || "").trim();
    if (normalized.length === 0 || !context.appsService)
        return [];

    var max = Math.max(1, limit || context.defaultLimit);
    var apps = context.appsService.spotlightResults(normalized, Math.max(max * 2, 12));
    var out = [];
    for (var i = 0; i < apps.length; i++) {
        var app = apps[i];
        var title = context.appsService.appLabel(app);
        var subtitle = String(app.genericName || app.id || "应用");
        var score = context.scoreText(title, subtitle, [app.id || "", app.startupClass || "", app.execString || ""], normalized, 430);
        if (score <= 0)
            continue;

        out.push(context.makeResult({
            "id": "app:" + context.appsService.appStableId(app),
            "title": title,
            "subtitle": subtitle,
            "icon": context.appsService.iconForApp(app),
            "kind": "application",
            "provider": "apps",
            "score": score,
            "app": app
        }));
    }
    return out;
}
