.pragma library

// WMO weather code → label, scene slug, and symbol key (legacy Material
// codepoint strings resolved by TahoeSymbols.js → pre-rendered PNG).

var UnknownText = "未知天气";
var UnknownSlug = "cloudy";
var UnknownIcon = "\ue2bd"; // cloud

var TextByCode = {
    0: "晴",
    1: "大致晴朗",
    2: "局部多云",
    3: "阴",
    45: "雾",
    48: "冻雾",
    51: "小毛毛雨",
    53: "毛毛雨",
    55: "浓毛毛雨",
    56: "小冻毛毛雨",
    57: "冻毛毛雨",
    61: "小雨",
    63: "雨",
    65: "大雨",
    66: "小冻雨",
    67: "冻雨",
    71: "小雪",
    73: "雪",
    75: "大雪",
    77: "雪粒",
    80: "小阵雨",
    81: "阵雨",
    82: "强阵雨",
    85: "小阵雪",
    86: "阵雪",
    95: "雷暴",
    96: "雷暴伴小冰雹",
    99: "雷暴伴冰雹"
};

var DaySlugByCode = {
    0: "clear-day",
    1: "mostly-clear-day",
    2: "partly-cloudy-day",
    3: "cloudy",
    45: "fog-day",
    48: "fog-day",
    51: "drizzle",
    53: "drizzle",
    55: "drizzle",
    56: "drizzle",
    57: "drizzle",
    61: "overcast-day-rain",
    63: "overcast-day-rain",
    65: "overcast-day-rain",
    66: "overcast-day-sleet",
    67: "overcast-day-sleet",
    71: "overcast-day-snow",
    73: "overcast-day-snow",
    75: "overcast-day-snow",
    77: "overcast-day-snow",
    80: "partly-cloudy-day-rain",
    81: "partly-cloudy-day-rain",
    82: "partly-cloudy-day-rain",
    85: "partly-cloudy-day-snow",
    86: "partly-cloudy-day-snow",
    95: "thunderstorms-day",
    96: "thunderstorms-day-hail",
    99: "thunderstorms-day-hail"
};

var NightSlugByCode = {
    0: "clear-night",
    1: "mostly-clear-night",
    2: "partly-cloudy-night",
    3: "cloudy",
    45: "fog-night",
    48: "fog-night",
    51: "drizzle",
    53: "drizzle",
    55: "drizzle",
    56: "drizzle",
    57: "drizzle",
    61: "overcast-night-rain",
    63: "overcast-night-rain",
    65: "overcast-night-rain",
    66: "overcast-night-sleet",
    67: "overcast-night-sleet",
    71: "overcast-night-snow",
    73: "overcast-night-snow",
    75: "overcast-night-snow",
    77: "overcast-night-snow",
    80: "partly-cloudy-night-rain",
    81: "partly-cloudy-night-rain",
    82: "partly-cloudy-night-rain",
    85: "partly-cloudy-night-snow",
    86: "partly-cloudy-night-snow",
    95: "thunderstorms-night",
    96: "thunderstorms-night-hail",
    99: "thunderstorms-night-hail"
};

var DayIconByCode = {
    0: "\ue81a", // sunny
    1: "\ue430", // wb_sunny
    2: "\ue2c2", // cloud_queue
    3: "\ue42d", // wb_cloudy
    45: "\ue818", // foggy
    48: "\ue818", // foggy
    51: "\ue798", // water_drop
    53: "\ue798", // water_drop
    55: "\ue798", // water_drop
    56: "\ueb3b", // ac_unit
    57: "\ueb3b", // ac_unit
    61: "\uf1ad", // umbrella
    63: "\uf1ad", // umbrella
    65: "\uf1ad", // umbrella
    66: "\ueb3b", // ac_unit
    67: "\ueb3b", // ac_unit
    71: "\ue80f", // snowing
    73: "\ue80f", // snowing
    75: "\ue80f", // snowing
    77: "\ue3ea", // grain
    80: "\uf1ad", // umbrella
    81: "\uf1ad", // umbrella
    82: "\uf1ad", // umbrella
    85: "\ue80f", // snowing
    86: "\ue80f", // snowing
    95: "\uebdb", // thunderstorm
    96: "\uebdb", // thunderstorm
    99: "\uebdb" // thunderstorm
};

var NightIconByCode = {
    0: "\uea46", // nights_stay
    1: "\uea46", // nights_stay
    2: "\ue2c2", // cloud_queue
    3: "\ue42d", // wb_cloudy
    45: "\ue818", // foggy
    48: "\ue818", // foggy
    51: "\ue798", // water_drop
    53: "\ue798", // water_drop
    55: "\ue798", // water_drop
    56: "\ueb3b", // ac_unit
    57: "\ueb3b", // ac_unit
    61: "\uf1ad", // umbrella
    63: "\uf1ad", // umbrella
    65: "\uf1ad", // umbrella
    66: "\ueb3b", // ac_unit
    67: "\ueb3b", // ac_unit
    71: "\ue80f", // snowing
    73: "\ue80f", // snowing
    75: "\ue80f", // snowing
    77: "\ue3ea", // grain
    80: "\uf1ad", // umbrella
    81: "\uf1ad", // umbrella
    82: "\uf1ad", // umbrella
    85: "\ue80f", // snowing
    86: "\ue80f", // snowing
    95: "\uebdb", // thunderstorm
    96: "\uebdb", // thunderstorm
    99: "\uebdb" // thunderstorm
};

function normalizedCode(code) {
    var value = Number(code);
    if (!isFinite(value))
        return -1;
    return Math.floor(value);
}

function hasOwn(map, code) {
    return Object.prototype.hasOwnProperty.call(map, code);
}

function text(code) {
    var key = normalizedCode(code);
    return hasOwn(TextByCode, key) ? TextByCode[key] : UnknownText;
}

function slug(code, isNight) {
    var key = normalizedCode(code);
    var map = isNight ? NightSlugByCode : DaySlugByCode;
    return hasOwn(map, key) ? map[key] : UnknownSlug;
}

function materialIcon(code, isNight) {
    var key = normalizedCode(code);
    var map = isNight ? NightIconByCode : DayIconByCode;
    return hasOwn(map, key) ? map[key] : UnknownIcon;
}
