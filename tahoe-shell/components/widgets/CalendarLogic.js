.pragma library

// 日历小部件纯逻辑：月份网格、今日高亮、中文月/周标签。
// 零 I/O、零 QML 场景图依赖；与 WidgetGrid.js 同模式，可被结构测试
// 用 node 逐函数断言。日期一律使用本地时区 Date。
//
// 布局照 macOS 日历小部件：周一起始、7 列 6 行 42 格、今日以红底白字
// 高亮、周末与次月格弱化。

var GRID_CELLS = 42;   // 6 周 × 7 天
var WEEKDAY_LABELS = ["一", "二", "三", "四", "五", "六", "日"];

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function weekdayLabels() {
    return WEEKDAY_LABELS.slice();
}

// 当月 1 号所在周的周一作为网格起点，铺满 42 格。
// 返回 [{ day, inMonth, isToday, isWeekend }]。
// year / month 为数字（month 0-11）；today 缺省取当前日期。
function monthGrid(year, month, today) {
    var now = startOfDay(today || new Date());
    var first = new Date(year, month, 1);
    var mondayOffset = (first.getDay() + 6) % 7;   // 周一 = 0
    var gridStart = new Date(year, month, 1 - mondayOffset);
    var out = [];
    for (var i = 0; i < GRID_CELLS; i++) {
        var d = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + i);
        out.push({
            "day": d.getDate(),
            "inMonth": d.getMonth() === month,
            "isToday": d.getTime() === now.getTime(),
            "isWeekend": d.getDay() === 0 || d.getDay() === 6
        });
    }
    return out;
}

function monthTitle(year, month) {
    return year + "年" + (month + 1) + "月";
}

// 今日若在当月内返回日期数字字符串（如 "11"），否则 ""。
// 头部红色「今天」徽标用（macOS 日历小部件语义）。
function todayDayLabel(year, month, today) {
    var t = startOfDay(today || new Date());
    if (t.getFullYear() === year && t.getMonth() === month)
        return String(t.getDate());
    return "";
}
