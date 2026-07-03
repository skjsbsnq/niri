.pragma library

function results(query, context) {
    var normalized = String(query || "").trim();
    if (normalized.length === 0)
        return [];

    var items = context.systemActionItems || [];
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var score = context.scoreText(item.title, item.subtitle, item.keywords || [], normalized, 740);
        if (score <= 0)
            continue;

        out.push(context.makeResult({
            "id": "system-action:" + item.id,
            "title": item.title,
            "subtitle": item.subtitle,
            "icon": context.iconPath("dock", item.icon || "preferences.png"),
            "kind": "system-action",
            "provider": "system-actions",
            "score": score,
            "systemAction": item.action
        }));
    }
    return out;
}
