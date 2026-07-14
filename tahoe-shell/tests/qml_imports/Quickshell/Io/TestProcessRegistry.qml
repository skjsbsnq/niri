pragma Singleton
import QtQml

QtObject {
    property var startedIds: []
    // Each entry: { match: string, delayMs?: number, payload?: string,
    //               code?: number, failStart?: bool }
    // First match on joined command wins. Used by the Io Process fake only.
    property var commandRules: []

    function reset() {
        startedIds = [];
        commandRules = [];
    }

    function record(command) {
        // Prefer a city/query-looking token when present; fall back to argv[1].
        var id = "";
        var joined = (command || []).join(" ");
        var nameMatch = joined.match(/(?:[?&]name=)([^&]+)/);
        if (nameMatch)
            id = decodeURIComponent(nameMatch[1]);
        else if (command && command.length > 1)
            id = String(command[1]);
        startedIds = startedIds.concat([id]);
    }

    function ruleFor(command) {
        var joined = (command || []).join(" ");
        for (var i = 0; i < commandRules.length; i++) {
            var rule = commandRules[i] || {};
            if (joined.indexOf(String(rule.match || "")) >= 0)
                return rule;
        }
        return null;
    }

    function shouldFailStart(command) {
        var rule = ruleFor(command);
        return !!(rule && rule.failStart);
    }

    function delayMsFor(command) {
        var rule = ruleFor(command);
        if (rule && rule.delayMs !== undefined)
            return Number(rule.delayMs);
        // Legacy AppMenu-style: argv[2] is delay seconds as string when argv[0] is test-*.
        if (command && command.length > 2 && String(command[0]).indexOf("test-") === 0)
            return Number(command[2]);
        return 0;
    }

    function payloadFor(command) {
        var rule = ruleFor(command);
        if (rule && rule.payload !== undefined)
            return String(rule.payload);
        if (command && command.length > 3 && String(command[0]).indexOf("test-") === 0)
            return String(command[3] || "");
        return "";
    }

    function exitCodeFor(command) {
        var rule = ruleFor(command);
        if (rule && rule.code !== undefined)
            return Number(rule.code);
        if (command && command.length > 4 && String(command[0]).indexOf("test-") === 0)
            return Number(command[4]);
        return 0;
    }
}
