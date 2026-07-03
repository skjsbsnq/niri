.pragma library

var OK = "ok";
var WARN = "warn";
var MISSING = "missing";
var BROKEN = "broken";
var UNKNOWN = "unknown";
var STALE = "stale";

var STATUS_FIELDS = [
    "id",
    "state",
    "title",
    "detail",
    "impact",
    "action",
    "missing",
    "updatedAt"
];

function nowIso() {
    return new Date().toISOString();
}

function normalizeText(value, fallback) {
    if (value === undefined || value === null)
        return String(fallback || "");
    return String(value);
}

function normalizeState(state) {
    var value = String(state || "").trim().toLowerCase();
    if (value === OK || value === WARN || value === MISSING || value === BROKEN || value === UNKNOWN || value === STALE)
        return value;
    if (value === "success" || value === "ready")
        return OK;
    if (value === "failure" || value === "failed" || value === "error" || value === "timeout")
        return BROKEN;
    if (value === "unavailable")
        return MISSING;
    return UNKNOWN;
}

function normalizeMissing(value) {
    var out = [];
    var values = [];
    if (Array.isArray(value)) {
        values = value;
    } else if (value !== undefined && value !== null) {
        values = String(value).split(/\s+/);
    }

    for (var i = 0; i < values.length; i++) {
        var item = String(values[i] || "").trim();
        if (item.length > 0)
            out.push(item);
    }
    return out;
}

function normalizeStatus(value, defaults, updatedAt) {
    var source = value || {};
    var fallback = defaults || {};
    var item = {};

    for (var key in fallback)
        item[key] = fallback[key];
    for (var sourceKey in source)
        item[sourceKey] = source[sourceKey];

    item.id = normalizeText(source.id !== undefined ? source.id : fallback.id, "");
    item.state = normalizeState(source.state !== undefined ? source.state : fallback.state);
    item.title = normalizeText(source.title !== undefined ? source.title : fallback.title, item.id);
    item.detail = normalizeText(source.detail !== undefined ? source.detail : fallback.detail, "");
    item.impact = normalizeText(source.impact !== undefined ? source.impact : fallback.impact, "");
    item.action = normalizeText(source.action !== undefined ? source.action : fallback.action, "");
    item.missing = normalizeMissing(source.missing !== undefined ? source.missing : fallback.missing);
    item.updatedAt = normalizeText(source.updatedAt !== undefined ? source.updatedAt : fallback.updatedAt, updatedAt || nowIso());
    return item;
}

function status(id, state, title, detail, impact, action, missing, updatedAt) {
    return normalizeStatus({
        "id": id,
        "state": state,
        "title": title,
        "detail": detail,
        "impact": impact,
        "action": action,
        "missing": missing
    }, {}, updatedAt);
}

function fromStatusFields(fields, updatedAt) {
    var values = Array.isArray(fields) ? fields : [];
    return status(
        values.length > 1 ? values[1] : "",
        values.length > 2 ? values[2] : UNKNOWN,
        values.length > 3 ? values[3] : "",
        values.length > 4 ? values[4] : "",
        values.length > 5 ? values[5] : "",
        values.length > 6 ? values[6] : "",
        values.length > 7 ? values[7] : [],
        updatedAt
    );
}

function unknownStatus(id, title, detail, updatedAt) {
    return status(id, UNKNOWN, title || id, detail || "尚未检测", "", "", [], updatedAt);
}

function stateFromActionStatus(actionStatus) {
    var value = String(actionStatus || "").trim().toLowerCase();
    if (value === "success")
        return OK;
    if (value === "missing")
        return MISSING;
    if (value === "failure" || value === "timeout")
        return BROKEN;
    if (value === "cancelled")
        return WARN;
    return UNKNOWN;
}

function isReady(value) {
    var state = normalizeState(typeof value === "string" ? value : (value ? value.state : ""));
    return state === OK || state === WARN;
}

function isWarnState(value) {
    var state = normalizeState(typeof value === "string" ? value : (value ? value.state : ""));
    return state === WARN || state === STALE;
}

function isMissingState(value) {
    var state = normalizeState(typeof value === "string" ? value : (value ? value.state : ""));
    return state === MISSING || state === BROKEN;
}

function countByState(items, state) {
    var count = 0;
    var values = Array.isArray(items) ? items : [];
    var normalized = normalizeState(state);
    for (var i = 0; i < values.length; i++) {
        if (values[i] && normalizeState(values[i].state) === normalized)
            count += 1;
    }
    return count;
}

function countWarn(items) {
    var count = 0;
    var values = Array.isArray(items) ? items : [];
    for (var i = 0; i < values.length; i++) {
        if (values[i] && isWarnState(values[i]))
            count += 1;
    }
    return count;
}

function countMissing(items) {
    var count = 0;
    var values = Array.isArray(items) ? items : [];
    for (var i = 0; i < values.length; i++) {
        if (values[i] && isMissingState(values[i]))
            count += 1;
    }
    return count;
}

function availabilityLabel(value) {
    var state = normalizeState(typeof value === "string" ? value : (value ? value.state : ""));
    if (state === OK)
        return "可用";
    if (state === WARN)
        return "部分可用";
    if (state === STALE)
        return "过期";
    if (state === MISSING)
        return "缺失";
    if (state === BROKEN)
        return "损坏";
    return "未知";
}

function iconCode(value) {
    var state = normalizeState(typeof value === "string" ? value : (value ? value.state : ""));
    if (state === OK)
        return "\ue5ca";
    if (state === WARN || state === STALE)
        return "\ue002";
    if (state === MISSING || state === BROKEN)
        return "\ue14b";
    return "\ue8b8";
}
