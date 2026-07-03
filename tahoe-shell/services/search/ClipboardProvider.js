.pragma library

function results(query, limit, context) {
    var normalized = String(query || "").trim();
    if (normalized.length === 0 || !context.clipboardService || !context.clipboardService.pinnedEntries)
        return [];

    var pins = context.clipboardService.pinnedEntries || [];
    var max = Math.max(1, limit || context.defaultLimit);
    var out = [];
    for (var i = 0; i < pins.length && out.length < max; i++) {
        var pin = pins[i];
        if (!pin)
            continue;

        var preview = String(pin.preview || "").trim();
        var text = String(pin.text || "");
        var title = preview.length > 0 ? preview : context.clipboardService.previewForText(text);
        var score = context.scoreText(title, "固定剪贴板 · 回车复制", [text], normalized, 700);
        if (score <= 0)
            continue;

        out.push(context.makeResult({
            "id": "clipboard-pin:" + String(i) + ":" + title,
            "title": title,
            "subtitle": "固定剪贴板 · 回车复制",
            "icon": context.iconPath("dock", "notes.png"),
            "kind": "clipboard-pin",
            "provider": "clipboard-pins",
            "score": score,
            "pin": pin
        }));
    }
    return out;
}
