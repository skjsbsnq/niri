pragma ComponentBehavior: Bound

import QtQuick

// LS10: 天气指标卡片网格。
//
// 职责：把 Weather 服务已整理好的 current/daily/air 数据展示成 Tahoe 风格玻璃卡。
// 本文件只做指标卡，不组装天气页、不发网络请求；LS11 负责把它放进天气页 Flickable。
Item {
    id: root

    property var weatherService: null
    property var settingsService: null
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"

    readonly property int cardCount: 10
    readonly property int columns: width >= 420 ? 2 : 1
    readonly property int cardRows: Math.ceil(cardCount / columns)
    readonly property real cardSpacing: 10
    readonly property real cardWidth: columns === 1
        ? Math.max(160, width)
        : Math.max(160, (width - cardSpacing) / 2)
    readonly property real cardHeight: 148
    readonly property color cardFill: darkMode ? "#28ffffff" : "#60ffffff"
    readonly property color cardStroke: darkMode ? "#32ffffff" : "#70ffffff"
    readonly property color hoverFill: darkMode ? "#20ffffff" : "#32ffffff"
    readonly property color textPrimary: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color textSecondary: darkMode ? "#c8d0d8" : "#991d1d1f"
    readonly property color textTertiary: darkMode ? "#9da7b1" : "#731d1d1f"
    readonly property color accentBlue: darkMode ? "#2c9cf2" : "#0b6bd3"
    readonly property string iconFont: "Material Icons"

    property real currentEpoch: Math.floor(Date.now() / 1000)

    implicitHeight: cardRows * cardHeight + Math.max(0, cardRows - 1) * cardSpacing

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.currentEpoch = Math.floor(Date.now() / 1000)
    }

    // --- Section 1: 通用数据 / 格式化 helper ---
    function service() {
        return root.weatherService || {};
    }

    function hasWeatherData() {
        var w = service();
        var daily = w.dailyForecast || [];
        var hourly = w.hourlyForecast || [];
        return !!root.weatherService
            && (!!w.locationDetected || daily.length > 0 || hourly.length > 0
                || w.status === "fresh" || w.status === "stale");
    }

    function air() {
        var w = service();
        return w.currentAirQuality || {};
    }

    function hasAirData() {
        var a = air();
        var keys = Object.keys(a);
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] !== "time" && validNumber(a[keys[i]]))
                return true;
        }
        return false;
    }

    function dailyItems() {
        var w = service();
        return w.dailyForecast || [];
    }

    function today() {
        var items = dailyItems();
        if (!items || items.length === 0)
            return {};

        var now = new Date(root.currentEpoch * 1000);
        for (var i = 0; i < items.length; i++) {
            var t = Number(items[i] && items[i].time);
            if (!isFinite(t) || t <= 0)
                continue;
            var d = new Date(t * 1000);
            if (d.getFullYear() === now.getFullYear()
                    && d.getMonth() === now.getMonth()
                    && d.getDate() === now.getDate())
                return items[i];
        }

        // Weather.qml 请求 past_days=1；找不到本地日期时优先取第二格（通常为今天）。
        return items.length > 1 ? items[1] : items[0];
    }

    function validNumber(value) {
        var n = Number(value);
        return isFinite(n);
    }

    function numeric(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function valueAt(map, key, fallback) {
        if (!map || map[key] === undefined || map[key] === null)
            return fallback;
        return numeric(map[key], fallback);
    }

    function currentValue(key, fallback) {
        if (!hasWeatherData())
            return fallback;
        return valueAt(service(), key, fallback);
    }

    function clamp01(value) {
        var n = Number(value);
        if (!isFinite(n))
            return 0;
        return Math.max(0, Math.min(1, n));
    }

    function fmtFixed(value, digits) {
        return validNumber(value) ? Number(value).toFixed(digits) : "--";
    }

    function fmtInt(value) {
        return validNumber(value) ? Math.round(Number(value)).toString() : "--";
    }

    function fmtTemp(value) {
        if (!validNumber(value))
            return "--";
        var temp = Number(value);
        var unit = settingsService ? String(settingsService.weatherTempUnit || "c").toLowerCase() : "c";
        if (unit === "f")
            temp = temp * 9 / 5 + 32;
        return Math.round(temp) + (unit === "f" ? "°F" : "°C");
    }

    function fmtPercent(value) {
        return validNumber(value) ? Math.round(Number(value)) + "%" : "--";
    }

    function fmtSpeed(value) {
        return validNumber(value) ? Number(value).toFixed(1) : "--";
    }

    function fmtDistance(meters) {
        if (!validNumber(meters))
            return { value: "--", unit: "" };
        var m = Number(meters);
        if (m >= 1000) {
            var km = m / 1000;
            return { value: km < 100 ? km.toFixed(1) : Math.round(km).toString(), unit: "km" };
        }
        return { value: Math.round(m).toString(), unit: "m" };
    }

    function fmtTime(epoch) {
        var n = Number(epoch);
        return isFinite(n) && n > 0 ? Qt.formatDateTime(new Date(n * 1000), "hh:mm") : "--";
    }

    function fmtHours(seconds) {
        var n = Number(seconds);
        if (!isFinite(n) || n <= 0)
            return "--";
        return (n / 3600).toFixed(1) + " h";
    }

    // --- Section 2: AQI / 花粉 / UV / 风况等数据逻辑 ---
    function aqiThresholds() {
        return [0, 20, 50, 100, 150, 250];
    }

    function pollutantIndex(value, thresholds) {
        if (!validNumber(value))
            return NaN;

        var v = Number(value);
        var level = -1;
        for (var i = 0; i < thresholds.length; i++) {
            if (v >= thresholds[i])
                level = i;
        }
        if (level < 0)
            return NaN;

        var aqi = aqiThresholds();
        if (level < thresholds.length - 1) {
            var bpLo = thresholds[level];
            var bpHi = thresholds[level + 1];
            var inLo = aqi[level];
            var inHi = aqi[level + 1];
            return Math.round(((inHi - inLo) / (bpHi - bpLo)) * (v - bpLo) + inLo);
        }
        return Math.round((v * aqi[aqi.length - 1]) / thresholds[thresholds.length - 1]);
    }

    function aqiLevelIndex(value) {
        if (!validNumber(value))
            return -1;
        var thresholds = aqiThresholds();
        var level = 0;
        for (var i = 0; i < thresholds.length; i++) {
            if (Number(value) >= thresholds[i])
                level = i;
        }
        return Math.min(level, 5);
    }

    function aqiPalette(level) {
        var colors = ["#00e59b", "#ffc302", "#ff712b", "#f62a55", "#c72eaa", "#9930ff"];
        return colors[Math.max(0, Math.min(colors.length - 1, level))];
    }

    function aqiLevelName(level) {
        var names = ["优", "良", "差", "不健康", "很不健康", "危险"];
        return level < 0 || level >= names.length ? "--" : names[level];
    }

    function aqiSummary() {
        var a = air();
        var candidates = [
            { label: "O3", value: pollutantIndex(a.ozone, [0, 50, 100, 160, 240, 480]) },
            { label: "NO2", value: pollutantIndex(a.nitrogenDioxide, [0, 10, 25, 200, 400, 1000]) },
            { label: "PM10", value: pollutantIndex(a.pm10, [0, 15, 45, 80, 160, 400]) },
            { label: "PM2.5", value: pollutantIndex(a.pm25, [0, 5, 15, 30, 60, 150]) }
        ];

        var best = null;
        for (var i = 0; i < candidates.length; i++) {
            var item = candidates[i];
            if (!validNumber(item.value))
                continue;
            if (!best || item.value > best.value)
                best = item;
        }
        if (!best)
            return { value: NaN, level: "--", color: "#00e59b", pollutant: "--" };

        var level = aqiLevelIndex(best.value);
        return {
            value: best.value,
            level: aqiLevelName(level),
            color: aqiPalette(level),
            pollutant: best.label
        };
    }

    function pollenDefinitions() {
        return [
            { key: "grassPollen", title: "草类", thresholds: [0, 3, 30, 50, 250] },
            { key: "birchPollen", title: "桦树", thresholds: [0, 10, 60, 100, 500] },
            { key: "alderPollen", title: "桤木", thresholds: [0, 10, 60, 100, 500] },
            { key: "mugwortPollen", title: "艾蒿", thresholds: [0, 3, 30, 50, 250] },
            { key: "olivePollen", title: "橄榄", thresholds: [0, 20, 100, 200, 500] },
            { key: "ragweedPollen", title: "豚草", thresholds: [0, 3, 30, 50, 250] }
        ];
    }

    function pollenIndexThresholds() {
        return [0, 25, 50, 75, 100];
    }

    function pollenLevelColor(level) {
        var colors = ["#bfbfbf", "#08c286", "#6ad555", "#ffd741", "#ffab40", "#ff3b30"];
        return colors[Math.max(0, Math.min(colors.length - 1, level))];
    }

    function pollenLevelName(level) {
        var names = ["无", "非常低", "低", "中", "高", "非常高"];
        return names[Math.max(0, Math.min(names.length - 1, level))];
    }

    function pollenIndex(value, thresholds) {
        if (!validNumber(value))
            return null;

        var v = Number(value);
        var level = -1;
        for (var i = 0; i < thresholds.length; i++) {
            if (v >= thresholds[i])
                level = i;
        }
        if (level < 0)
            return 0;

        var out = pollenIndexThresholds();
        if (level < thresholds.length - 1) {
            var bpLo = thresholds[level];
            var bpHi = thresholds[level + 1];
            var inLo = out[level];
            var inHi = out[level + 1];
            return Math.round(((inHi - inLo) / (bpHi - bpLo)) * (v - bpLo) + inLo);
        }
        return Math.round((v * out[out.length - 1]) / thresholds[thresholds.length - 1]);
    }

    function pollenLevel(indexValue) {
        if (indexValue === null || indexValue === undefined)
            return null;

        var thresholds = pollenIndexThresholds();
        var level = -1;
        for (var i = 0; i < thresholds.length; i++) {
            if (Number(indexValue) >= thresholds[i])
                level = i;
        }
        return Math.max(0, Math.min(5, level < 0 ? 0 : level));
    }

    function pollenSummary() {
        var a = air();
        var defs = pollenDefinitions();
        var items = [];
        for (var i = 0; i < defs.length; i++) {
            var def = defs[i];
            var indexValue = pollenIndex(a[def.key], def.thresholds);
            if (indexValue === null)
                continue;
            var level = pollenLevel(indexValue);
            items.push({
                title: def.title,
                index: indexValue,
                level: level,
                levelText: pollenLevelName(level),
                color: pollenLevelColor(level)
            });
        }

        if (items.length === 0)
            return { title: "花粉", index: NaN, levelText: "暂无数据", color: pollenLevelColor(0) };

        items.sort(function(a, b) { return b.index - a.index; });
        if (items[0].index <= 0)
            return { title: "今日花粉", index: 0, levelText: "无", color: pollenLevelColor(0) };
        return items[0];
    }

    function uvLevel(value) {
        if (!validNumber(value))
            return "--";
        var v = Number(value);
        if (v < 3)
            return "低";
        if (v < 6)
            return "中";
        if (v < 8)
            return "高";
        if (v < 11)
            return "很高";
        return "极高";
    }

    function uvAccent(value) {
        if (!validNumber(value))
            return "#8e8e93";
        var v = Number(value);
        if (v < 3)
            return "#72d572";
        if (v < 6)
            return "#ffca28";
        if (v < 8)
            return "#ffa726";
        if (v < 11)
            return "#ff453a";
        return "#bf5af2";
    }

    function windAccent(ms) {
        if (!validNumber(ms))
            return "#4d8d7b";
        var v = Number(ms);
        if (v < 4)
            return "#72d572";
        if (v < 6)
            return "#ffca28";
        if (v < 8)
            return "#ffa726";
        if (v < 10)
            return "#e52f35";
        if (v < 12)
            return "#99004c";
        return "#7e0023";
    }

    function directionLabel(degree) {
        if (!validNumber(degree))
            return "--";
        var normalized = ((Number(degree) % 360) + 360) % 360;
        if (normalized < 22.5 || normalized >= 337.5)
            return "N";
        if (normalized < 67.5)
            return "NE";
        if (normalized < 112.5)
            return "E";
        if (normalized < 157.5)
            return "SE";
        if (normalized < 202.5)
            return "S";
        if (normalized < 247.5)
            return "SW";
        if (normalized < 292.5)
            return "W";
        return "NW";
    }

    function visibilityDescription(meters) {
        if (!validNumber(meters))
            return "--";
        var km = Number(meters) / 1000;
        if (km >= 16)
            return "极清";
        if (km >= 10)
            return "清晰";
        if (km >= 6)
            return "良好";
        if (km >= 3)
            return "轻雾";
        if (km >= 1)
            return "低";
        return "浓雾";
    }

    function pressureDescription(value) {
        if (!validNumber(value))
            return "--";
        var p = Number(value);
        if (p < 1000)
            return "偏低";
        if (p < 1013)
            return "略低";
        if (p < 1025)
            return "正常";
        if (p < 1040)
            return "偏高";
        return "很高";
    }

    function pressureProgress(value) {
        return clamp01((Number(value) - 963) / 100);
    }

    function todayPrecipitation() {
        if (!hasWeatherData())
            return NaN;
        var day = today();
        var dailySum = valueAt(day, "precipitationSumMm", NaN);
        var current = valueAt(service(), "currentPrecipitationMm", NaN);
        if (validNumber(dailySum))
            return dailySum;
        return current;
    }

    function todayPrecipitationProbability() {
        if (!hasWeatherData())
            return NaN;
        return valueAt(today(), "precipitationProbabilityMax", NaN);
    }

    function sunProgress() {
        var day = today();
        var rise = Number(day.sunrise);
        var set = Number(day.sunset);
        if (!isFinite(rise) || !isFinite(set) || set <= rise)
            return 0;
        return clamp01((root.currentEpoch - rise) / (set - rise));
    }

    function moonPhaseInfo(epoch) {
        var seconds = Number(epoch);
        if (!isFinite(seconds) || seconds <= 0)
            seconds = root.currentEpoch;

        var synodicMonth = 29.53058867 * 24 * 3600;
        var knownNewMoon = Date.UTC(2000, 0, 6, 18, 14, 0) / 1000;
        var phase = ((seconds - knownNewMoon) % synodicMonth) / synodicMonth;
        if (phase < 0)
            phase += 1;

        var illum = phase <= 0.5 ? phase * 2 : (1 - phase) * 2;
        var name = "新月";
        if (phase < 0.03 || phase > 0.97)
            name = "新月";
        else if (phase < 0.22)
            name = "蛾眉月";
        else if (phase < 0.28)
            name = "上弦月";
        else if (phase < 0.47)
            name = "盈凸月";
        else if (phase < 0.53)
            name = "满月";
        else if (phase < 0.72)
            name = "亏凸月";
        else if (phase < 0.78)
            name = "下弦月";
        else
            name = "残月";

        return { phase: phase, illumination: Math.round(illum * 100), name: name };
    }

    // --- Section 3: 网格 ---
    Grid {
        id: cardGrid

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        columns: root.columns
        spacing: root.cardSpacing

        MetricCard {
            readonly property var summary: root.aqiSummary()

            iconCode: "\uefd8" // air
            title: "空气质量"
            valueText: root.validNumber(summary.value) ? Math.round(summary.value).toString() : "--"
            unitText: "AQI"
            detailText: summary.level
            footerText: summary.pollutant === "--" ? "暂无污染物数据" : "主导 " + summary.pollutant
            accent: summary.color
            progress: root.validNumber(summary.value) ? root.clamp01(summary.value / 250) : 0
        }

        MetricCard {
            readonly property var summary: root.pollenSummary()

            iconCode: "\ueb4c" // spa
            title: "花粉"
            valueText: summary.levelText
            unitText: ""
            detailText: summary.title
            footerText: root.validNumber(summary.index) ? "指数 " + Math.round(summary.index) : "等待空气质量数据"
            accent: summary.color
            progress: root.validNumber(summary.index) ? root.clamp01(summary.index / 100) : 0
        }

        MetricCard {
            readonly property real humidity: root.currentValue("currentHumidity", NaN)
            readonly property real dewPoint: root.currentValue("currentDewPointC", NaN)

            iconCode: "\ue798" // water_drop
            title: "湿度"
            valueText: root.fmtInt(humidity)
            unitText: "%"
            detailText: "露点 " + root.fmtTemp(dewPoint)
            footerText: "体感湿度"
            accent: "#625985"
            progress: root.validNumber(humidity) ? root.clamp01(humidity / 100) : 0
        }

        MetricCard {
            readonly property real uv: root.currentValue("currentUvIndex", NaN)

            iconCode: "\ue430" // wb_sunny
            title: "紫外线"
            valueText: root.fmtFixed(uv, 1)
            unitText: ""
            detailText: root.uvLevel(uv)
            footerText: "当前指数"
            accent: root.uvAccent(uv)
            progress: root.validNumber(uv) ? root.clamp01(uv / 12) : 0
        }

        MetricCard {
            readonly property real meters: root.currentValue("currentVisibilityM", NaN)
            readonly property var distance: root.fmtDistance(meters)

            iconCode: "\ue8f4" // visibility
            title: "能见度"
            valueText: distance.value
            unitText: distance.unit
            detailText: root.visibilityDescription(meters)
            footerText: "地表水平视程"
            accent: "#7ed0ff"
            progress: root.validNumber(meters) ? root.clamp01(meters / 40000) : 0
        }

        MetricCard {
            readonly property real pressure: root.currentValue("currentPressureHpa", NaN)

            iconCode: "\ue9e4" // speed
            title: "气压"
            valueText: root.fmtFixed(pressure, 1)
            unitText: "hPa"
            detailText: root.pressureDescription(pressure)
            footerText: "海平面气压"
            accent: "#7ed0ff"
            progress: root.validNumber(pressure) ? root.pressureProgress(pressure) : 0
        }

        MetricCard {
            readonly property real speed: root.currentValue("currentWindSpeedMs", NaN)
            readonly property real gust: root.currentValue("currentWindGustMs", NaN)
            readonly property real direction: root.currentValue("currentWindDirectionDeg", NaN)

            iconCode: "\uefd8" // air
            title: "风况"
            valueText: root.fmtSpeed(speed)
            unitText: "m/s"
            detailText: "阵风 " + root.fmtSpeed(gust) + " m/s"
            footerText: "方向 " + root.directionLabel(direction)
            accent: root.windAccent(speed)
            progress: root.validNumber(speed) ? root.clamp01(speed / 12) : 0
        }

        MetricCard {
            readonly property real amount: root.todayPrecipitation()
            readonly property real probability: root.todayPrecipitationProbability()

            iconCode: "\ue798" // water_drop
            title: "降水"
            valueText: root.fmtFixed(amount, 1)
            unitText: "mm"
            detailText: root.validNumber(probability) ? "概率 " + root.fmtPercent(probability) : "今日累计"
            footerText: root.currentValue("currentPrecipitationMm", NaN) > 0 ? "当前有降水" : "未来预报"
            accent: "#2c9cf2"
            progress: root.validNumber(probability)
                ? root.clamp01(probability / 100)
                : (root.validNumber(amount) ? root.clamp01(amount / 20) : 0)
        }

        MetricCard {
            readonly property var day: root.today()

            iconCode: "\ue430" // wb_sunny
            title: "太阳"
            valueText: root.fmtTime(day.sunrise)
            unitText: ""
            detailText: "日落 " + root.fmtTime(day.sunset)
            footerText: "日照 " + root.fmtHours(day.sunshineDurationS)
            accent: "#ffca28"
            progress: root.sunProgress()
        }

        MetricCard {
            readonly property var info: root.moonPhaseInfo((root.today() || {}).time)

            iconCode: "\uea46" // nights_stay
            title: "月相"
            valueText: info.name
            unitText: ""
            detailText: "照明约 " + info.illumination + "%"
            footerText: "按日期估算"
            accent: "#b48ead"
            progress: root.clamp01(info.illumination / 100)
        }
    }

    // --- Section 4: 统一 Tahoe 指标卡样式 ---
    component MetricCard: Rectangle {
        id: card

        property string iconCode: ""
        property string title: ""
        property string valueText: "--"
        property string unitText: ""
        property string detailText: ""
        property string footerText: ""
        property color accent: root.accentBlue
        property real progress: 0

        width: root.cardWidth
        height: root.cardHeight
        radius: 18
        color: root.cardFill
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(4, parent.width * root.clamp01(card.progress))
            radius: parent.radius
            color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, root.darkMode ? 0.14 : 0.12)
        }

        Rectangle {
            anchors.fill: parent
            color: hoverMouse.containsMouse ? root.hoverFill : "transparent"
            radius: parent.radius

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.cardStroke
            border.width: 1
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 12
            spacing: 8

            Rectangle {
                width: 30
                height: 30
                radius: 10
                color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, root.darkMode ? 0.20 : 0.16)

                Text {
                    anchors.centerIn: parent
                    text: card.iconCode
                    color: card.accent
                    font.family: root.iconFont
                    font.pixelSize: 17
                }
            }

            Text {
                width: parent.width - 38
                text: card.title
                color: root.textSecondary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 54
            spacing: 5

            Text {
                width: Math.min(implicitWidth, parent.width - (unitLabel.visible ? unitLabel.implicitWidth + 8 : 0))
                text: card.valueText
                color: root.textPrimary
                font.pixelSize: card.valueText.length > 5 ? 23 : 29
                font.family: root.monoFontFamily
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: unitLabel

                visible: card.unitText.length > 0 && card.valueText !== "--"
                text: card.unitText
                color: root.textSecondary
                font.pixelSize: 12
                font.family: root.monoFontFamily
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 5
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footerText.visible ? footerText.top : parent.bottom
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.bottomMargin: footerText.visible ? 3 : 14
            text: card.detailText
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            id: footerText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.bottomMargin: 12
            visible: card.footerText.length > 0
            text: card.footerText
            color: root.textTertiary
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        MouseArea {
            id: hoverMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }
}
