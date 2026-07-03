.pragma library

function commandText(query) {
    var text = String(query || "").trim();
    if (text.length < 2)
        return "";

    var prefix = text.charAt(0);
    if (prefix !== ">" && prefix !== "!")
        return "";

    return text.substring(1).trim();
}

function results(query, context) {
    var command = commandText(query);
    if (command.length === 0)
        return [];

    return [
        context.makeResult({
            "id": "command:" + command,
            "title": "运行 Shell 命令",
            "subtitle": "危险：回车将在 shell 中执行 · " + command,
            "icon": context.iconPath("dock", "terminal.png"),
            "kind": "command",
            "provider": "command",
            "score": 950,
            "command": command
        })
    ];
}
