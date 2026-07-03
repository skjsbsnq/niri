.pragma library

function results(query, context) {
    if (!context.screenshotService || !context.screenshotService.matchesQuery(query))
        return [];

    var raw = context.screenshotService.spotlightResult();
    return [
        context.makeResult({
            "id": "screenshot:" + String(raw.id || "selection"),
            "title": String(raw.title || raw.name || "截图选区"),
            "subtitle": String(raw.subtitle || raw.genericName || "保存、复制并可标注"),
            "icon": context.iconPath("dock", raw.icon || "photos.png"),
            "kind": "screenshot",
            "provider": "screenshot",
            "score": Number(raw.score || 860),
            "resultType": "screenshot"
        })
    ];
}
