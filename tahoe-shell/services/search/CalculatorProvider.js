.pragma library

function results(query, context) {
    var parsed = parseQuery(query);
    if (!parsed)
        return [];

    var valueText = formatNumber(parsed.value);
    return [
        context.makeResult({
            "id": "calculator:" + parsed.expression,
            "title": valueText,
            "subtitle": parsed.expression + " = " + valueText + " · 回车复制",
            "icon": context.iconPath("dock", "calculator.png"),
            "kind": "calculator",
            "provider": "calculator",
            "score": 920,
            "copyText": valueText
        })
    ];
}

function parseQuery(query) {
    var raw = String(query || "").trim();
    if (raw.length === 0)
        return null;

    var explicit = raw.charAt(0) === "=";
    var expression = explicit ? raw.substring(1).trim() : raw;
    expression = expression.replace(/×/g, "*").replace(/÷/g, "/").replace(/，/g, ".");
    if (expression.length === 0 || !/[0-9]/.test(expression))
        return null;
    if (!/^[0-9+\-*/%^().\s]+$/.test(expression))
        return null;
    if (!explicit && !/[+\-*/%^()]/.test(expression))
        return null;
    if (/^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$/.test(expression))
        return null;

    try {
        var state = { "text": expression, "pos": 0 };
        var value = parseExpression(state);
        skipSpaces(state);
        if (state.pos !== state.text.length || !isFinite(value))
            return null;
        return { "expression": expression, "value": value };
    } catch (e) {
        return null;
    }
}

function skipSpaces(state) {
    while (state.pos < state.text.length && /\s/.test(state.text.charAt(state.pos)))
        state.pos += 1;
}

function parseExpression(state) {
    var value = parseTerm(state);
    while (true) {
        skipSpaces(state);
        var op = state.text.charAt(state.pos);
        if (op !== "+" && op !== "-")
            break;

        state.pos += 1;
        var right = parseTerm(state);
        value = op === "+" ? value + right : value - right;
    }
    return value;
}

function parseTerm(state) {
    var value = parsePower(state);
    while (true) {
        skipSpaces(state);
        var op = state.text.charAt(state.pos);
        if (op !== "*" && op !== "/" && op !== "%")
            break;

        state.pos += 1;
        var right = parsePower(state);
        if (op === "*")
            value *= right;
        else if (op === "/")
            value /= right;
        else
            value %= right;
    }
    return value;
}

function parsePower(state) {
    var value = parseUnary(state);
    skipSpaces(state);
    if (state.text.charAt(state.pos) === "^") {
        state.pos += 1;
        value = Math.pow(value, parsePower(state));
    }
    return value;
}

function parseUnary(state) {
    skipSpaces(state);
    var op = state.text.charAt(state.pos);
    if (op === "+" || op === "-") {
        state.pos += 1;
        var value = parseUnary(state);
        return op === "-" ? -value : value;
    }
    return parsePrimary(state);
}

function parsePrimary(state) {
    skipSpaces(state);
    var ch = state.text.charAt(state.pos);
    if (ch === "(") {
        state.pos += 1;
        var value = parseExpression(state);
        skipSpaces(state);
        if (state.text.charAt(state.pos) !== ")")
            throw "missing closing parenthesis";
        state.pos += 1;
        return value;
    }
    return parseNumber(state);
}

function parseNumber(state) {
    skipSpaces(state);
    var start = state.pos;
    var dotSeen = false;
    var digitSeen = false;
    while (state.pos < state.text.length) {
        var ch = state.text.charAt(state.pos);
        if (ch >= "0" && ch <= "9") {
            digitSeen = true;
            state.pos += 1;
        } else if (ch === "." && !dotSeen) {
            dotSeen = true;
            state.pos += 1;
        } else {
            break;
        }
    }

    if (!digitSeen)
        throw "number expected";

    return Number(state.text.substring(start, state.pos));
}

function formatNumber(value) {
    if (Math.abs(value) < 1e-12)
        return "0";
    if (Math.abs(value - Math.round(value)) < 1e-10)
        return String(Math.round(value));

    var text = Math.abs(value) >= 1000000000000 || Math.abs(value) < 0.000001
        ? value.toPrecision(12)
        : value.toFixed(10);
    text = text.replace(/(\.\d*?)0+($|e)/, "$1$2");
    text = text.replace(/\.($|e)/, "$1");
    return text;
}
