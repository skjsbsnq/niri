.pragma library

function results(query, context) {
    var normalized = String(query || "").trim();
    if (normalized.length === 0)
        return [];

    var items = context.settingsItems || [];
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var score = context.scoreText(item.title, item.subtitle, item.keywords || [], normalized, item.internalPage ? 760 : 620);
        if (score <= 0)
            continue;

        out.push(context.makeResult({
            "id": "settings:" + item.id,
            "title": item.title,
            "subtitle": item.subtitle,
            "icon": context.iconPath("dock", "preferences.png"),
            "kind": "settings",
            "provider": "settings",
            "score": score,
            "settingsItem": item
        }));
    }
    return out;
}
