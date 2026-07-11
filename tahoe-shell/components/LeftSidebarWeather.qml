pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// 左侧边栏天气页。
//
// 重构目标：天气页只做侧栏内的信息布局，玻璃、模糊、阴影继续由
// LeftSidebar.qml 的玻璃 region 统一拥有。这里不再绘制独立天气背景或
// 大型图表卡，避免在一个系统侧栏里嵌入第二套天气 App 视觉语言。
Item {
    id: root

    property var weatherService: null
    property var settingsService: null
    property bool sidebarOpen: false
    property bool active: false
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"

    readonly property var dailyForecast: weatherService ? (weatherService.dailyForecast || []) : []
    readonly property var hourlyForecast: weatherService ? (weatherService.hourlyForecast || []) : []
    readonly property bool hasData: hasWeatherData()
    readonly property bool updating: !!(weatherService && weatherService.updating)
    readonly property string status: weatherService ? String(weatherService.status || "idle") : "idle"

    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color accentBlue: Theme.accent(darkMode, accentId)
    readonly property color successGreen: darkMode ? "#63d471" : "#248a3d"
    readonly property color warningYellow: darkMode ? "#ffd60a" : "#b56a00"
    readonly property color dangerRed: Theme.danger(darkMode)
    readonly property color precipBlue: darkMode ? "#7dc8ff" : "#2c9cf2"
    readonly property color cardFill: darkMode ? "#18ffffff" : "#34ffffff"
    readonly property color cardHover: darkMode ? "#26ffffff" : "#50ffffff"
    readonly property color cardStroke: darkMode ? "#26ffffff" : "#54ffffff"
    readonly property color separator: darkMode ? "#18ffffff" : "#241d1d1f"

    readonly property int metricColumns: width >= 360 ? 2 : 1
    readonly property real metricGap: 8
    readonly property real metricTileWidth: metricColumns === 1
        ? Math.max(0, contentColumn.width)
        : Math.max(0, (contentColumn.width - metricGap) / 2)

    property real currentEpoch: Math.floor(Date.now() / 1000)

    signal openWeatherSettingsRequested()

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.currentEpoch = Math.floor(Date.now() / 1000)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 42

            RowLayout {
                anchors.fill: parent
                spacing: 9

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: root.locationTitle()
                        color: root.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.updatedText()
                        color: root.statusColor()
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    iconCode: "\ue5d5" // refresh
                    enabled: !!root.weatherService && !root.updating
                    busy: root.updating
                    onActivated: {
                        if (root.weatherService && typeof root.weatherService.refresh === "function")
                            root.weatherService.refresh();
                    }
                }

                IconButton {
                    iconCode: "\ue8b8" // settings
                    enabled: true
                    onActivated: root.openWeatherSettingsRequested()
                }
            }
        }

        Flickable {
            id: contentFlick

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            visible: root.hasData || root.updating

            Column {
                id: contentColumn

                width: contentFlick.width
                spacing: 12

                Item {
                    width: parent.width
                    height: 168

                    Column {
                        anchors.left: parent.left
                        anchors.right: heroIcon.left
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        anchors.rightMargin: 12
                        spacing: 4

                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: root.fmtTemp(root.weatherNumber("currentTemperatureC", NaN), true)
                                color: root.textPrimary
                                font.pixelSize: 58
                                font.family: root.monoFontFamily
                                font.weight: Font.DemiBold
                                lineHeight: 0.88
                            }

                            StatusCapsule {
                                visible: root.hasData && (root.status === "stale" || root.status === "error")
                                text: root.status === "error" ? "失败" : "缓存"
                                accent: root.status === "error" ? root.dangerRed : root.warningYellow
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.conditionText()
                            color: root.textPrimary
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.detailSummary()
                            color: root.textSecondary
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: heroIcon

                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 9
                        width: 82
                        height: 82
                        radius: 22
                        color: root.cardFill
                        border.color: root.cardStroke
                        border.width: 1

                        MeteoIcon {
                            anchors.centerIn: parent
                            width: 58
                            height: 58
                            weatherCode: root.currentWeatherCode()
                            night: root.currentIsNight()
                            color: root.textPrimary
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: 8

                        MiniMetricPill {
                            width: (parent.width - 16) / 3
                            iconCode: "\ue1b1" // device_thermostat
                            label: "体感"
                            value: root.fmtTemp(root.weatherNumber("currentApparentTemperatureC", NaN), true)
                        }

                        MiniMetricPill {
                            width: (parent.width - 16) / 3
                            iconCode: "\ue798" // water_drop
                            label: "湿度"
                            value: root.fmtPercent(root.weatherNumber("currentHumidity", NaN))
                        }

                        MiniMetricPill {
                            width: (parent.width - 16) / 3
                            iconCode: "\uefd8" // air
                            label: "风"
                            value: root.fmtSpeed(root.weatherNumber("currentWindSpeedMs", NaN))
                        }
                    }
                }

                StatusBanner {
                    width: parent.width
                    visible: root.status === "error" || (root.status === "stale" && root.lastErrorText().length > 0)
                    title: root.status === "error" ? "更新失败" : "显示缓存"
                    message: root.lastErrorText().length > 0 ? root.lastErrorText() : "最近一次天气数据不可用"
                    iconCode: root.status === "error" ? "\ue001" : "\ue86a"
                    accent: root.status === "error" ? root.dangerRed : root.warningYellow
                }

                SectionHeader {
                    title: "未来几小时"
                    detail: root.hourlyVisibleCount() + " 项"
                }

                HourlyStrip {
                    width: parent.width
                }

                SectionHeader {
                    title: "每日预报"
                    detail: root.dailyVisibleCount() + " 天"
                }

                DailyForecastList {
                    width: parent.width
                }

                SectionHeader {
                    title: "状况"
                    detail: root.status === "fresh" ? "实时" : root.statusLabel()
                }

                Grid {
                    width: parent.width
                    height: Math.ceil(6 / root.metricColumns) * 78
                        + (Math.ceil(6 / root.metricColumns) - 1) * root.metricGap
                    columns: root.metricColumns
                    spacing: root.metricGap

                    CompactMetricTile {
                        width: root.metricTileWidth
                        iconCode: "\ue430" // wb_sunny
                        title: "紫外线"
                        value: root.fmtUv(root.weatherNumber("currentUvIndex", NaN))
                        detail: root.uvLevel(root.weatherNumber("currentUvIndex", NaN))
                        accent: root.uvAccent(root.weatherNumber("currentUvIndex", NaN))
                    }

                    CompactMetricTile {
                        width: root.metricTileWidth
                        readonly property var summary: root.aqiSummary()
                        iconCode: "\uefd8" // air
                        title: "空气"
                        value: root.validNumber(summary.value) ? Math.round(summary.value).toString() : "--"
                        detail: root.validNumber(summary.value) ? summary.level : "暂无 AQI"
                        accent: summary.color
                    }

                    CompactMetricTile {
                        width: root.metricTileWidth
                        iconCode: "\ue9e4" // speed
                        title: "气压"
                        value: root.fmtPressure(root.weatherNumber("currentPressureHpa", NaN))
                        detail: "hPa"
                        accent: root.darkMode ? "#7dc8ff" : "#0b6bd3"
                    }

                    CompactMetricTile {
                        width: root.metricTileWidth
                        iconCode: "\ue8f4" // visibility
                        title: "能见度"
                        value: root.fmtDistance(root.weatherNumber("currentVisibilityM", NaN))
                        detail: root.visibilityDescription(root.weatherNumber("currentVisibilityM", NaN))
                        accent: "#7ed0ff"
                    }

                    CompactMetricTile {
                        width: root.metricTileWidth
                        iconCode: "\ue798" // water_drop
                        title: "降水"
                        value: root.fmtPrecip(root.todayPrecipitation())
                        detail: root.validNumber(root.todayPrecipProbability()) ? "概率 " + root.fmtPercent(root.todayPrecipProbability()) : "今日累计"
                        accent: root.precipBlue
                    }

                    CompactMetricTile {
                        width: root.metricTileWidth
                        iconCode: "\ue88a" // explore
                        title: "风向"
                        value: root.directionLabel(root.weatherNumber("currentWindDirectionDeg", NaN))
                        detail: "阵风 " + root.fmtSpeed(root.weatherNumber("currentWindGustMs", NaN))
                        accent: root.windAccent(root.weatherNumber("currentWindSpeedMs", NaN))
                    }
                }

                Item {
                    width: parent.width
                    height: 6
                }
            }
        }
    }

    EmptyState {
        anchors.fill: parent
        visible: !root.hasData && !root.updating
    }

    BusyStripe {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.updating
    }

    // --- Section 1: service / model helpers ---
    function service() {
        return root.weatherService || {};
    }

    function hasWeatherData() {
        var w = service();
        return !!root.weatherService
            && (!!w.locationDetected || root.dailyForecast.length > 0 || root.hourlyForecast.length > 0
                || w.status === "fresh" || w.status === "stale");
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

    function weatherNumber(key, fallback) {
        var w = service();
        if (!root.hasData || w[key] === undefined || w[key] === null)
            return fallback;
        return numeric(w[key], fallback);
    }

    function arrayCount(model) {
        if (!model)
            return 0;
        if (typeof model.count === "function")
            return Number(model.count()) || 0;
        if (model.count !== undefined)
            return Number(model.count) || 0;
        if (model.length !== undefined)
            return Number(model.length) || 0;
        return 0;
    }

    function modelItem(model, index) {
        if (!model || index < 0)
            return {};
        if (typeof model.get === "function")
            return model.get(index) || {};
        if (model.length !== undefined && index < model.length)
            return model[index] || {};
        return {};
    }

    function currentWeatherCode() {
        if (!root.hasData)
            return -1;
        var code = Number(service().currentWeatherCode);
        return isFinite(code) ? Math.round(code) : -1;
    }

    function currentIsNight() {
        if (!root.hasData)
            return false;
        return service().currentIsDay === false;
    }

    function dailyCount() {
        return arrayCount(root.dailyForecast);
    }

    function hourlyCount() {
        return arrayCount(root.hourlyForecast);
    }

    function dayStartEpoch(epoch) {
        var date = new Date(Number(epoch) * 1000);
        return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() / 1000;
    }

    function dailyStartIndex() {
        var count = dailyCount();
        if (count === 0)
            return 0;

        var todayStart = dayStartEpoch(root.currentEpoch);
        for (var i = 0; i < count; i++) {
            var t = Number(modelItem(root.dailyForecast, i).time);
            if (isFinite(t) && t >= todayStart)
                return i;
        }
        return 0;
    }

    function dailyVisibleCount() {
        return Math.min(8, Math.max(0, dailyCount() - dailyStartIndex()));
    }

    function dailyAt(index) {
        return modelItem(root.dailyForecast, dailyStartIndex() + index);
    }

    function todayDaily() {
        var count = dailyVisibleCount();
        if (count > 0)
            return dailyAt(0);
        return {};
    }

    function hourlyStartIndex() {
        var count = hourlyCount();
        if (count === 0)
            return 0;

        var threshold = root.currentEpoch - 1800;
        for (var i = 0; i < count; i++) {
            var t = Number(modelItem(root.hourlyForecast, i).time);
            if (isFinite(t) && t >= threshold)
                return i;
        }
        return 0;
    }

    function hourlyVisibleCount() {
        return Math.min(12, Math.max(0, hourlyCount() - hourlyStartIndex()));
    }

    function hourlyAt(index) {
        return modelItem(root.hourlyForecast, hourlyStartIndex() + index);
    }

    // --- Section 2: formatting ---
    function tempUnit() {
        var unit = root.settingsService ? String(root.settingsService.weatherTempUnit || "c").toLowerCase() : "c";
        return unit === "f" ? "f" : "c";
    }

    function convertTemp(value) {
        var n = Number(value);
        if (!isFinite(n))
            return NaN;
        return tempUnit() === "f" ? n * 9 / 5 + 32 : n;
    }

    function fmtTemp(value, includeUnit) {
        var n = convertTemp(value);
        if (!isFinite(n))
            return "--";
        return Math.round(n) + (includeUnit ? (tempUnit() === "f" ? "°F" : "°C") : "°");
    }

    function fmtPercent(value) {
        return validNumber(value) ? Math.round(Number(value)) + "%" : "--";
    }

    function fmtSpeed(value) {
        return validNumber(value) ? Number(value).toFixed(1) + " m/s" : "--";
    }

    function fmtPressure(value) {
        return validNumber(value) ? Math.round(Number(value)).toString() : "--";
    }

    function fmtUv(value) {
        return validNumber(value) ? Number(value).toFixed(1) : "--";
    }

    function fmtPrecip(value) {
        return validNumber(value) ? Number(value).toFixed(1) + " mm" : "--";
    }

    function fmtDistance(meters) {
        if (!validNumber(meters))
            return "--";
        var m = Number(meters);
        if (m >= 1000) {
            var km = m / 1000;
            return (km < 100 ? km.toFixed(1) : Math.round(km).toString()) + " km";
        }
        return Math.round(m).toString() + " m";
    }

    function fmtHour(epoch) {
        var n = Number(epoch);
        return isFinite(n) && n > 0 ? Qt.formatDateTime(new Date(n * 1000), "hh:00") : "--";
    }

    function fmtTime(epoch) {
        var n = Number(epoch);
        return isFinite(n) && n > 0 ? Qt.formatDateTime(new Date(n * 1000), "hh:mm") : "--";
    }

    function dayLabel(index, epoch) {
        if (index === 0)
            return "今天";
        if (index === 1)
            return "明天";
        if (!epoch)
            return "--";
        var week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
        return week[new Date(Number(epoch) * 1000).getDay()];
    }

    function locationTitle() {
        var name = String(service().locationName || "").trim();
        if (name.length > 0)
            return name;
        return root.updating ? "自动定位中" : "当前位置";
    }

    function conditionText() {
        if (!root.hasData)
            return root.updating ? "正在获取天气" : "暂无天气";
        var text = String(service().currentWeatherText || "").trim();
        return text.length > 0 ? text : "未知天气";
    }

    function detailSummary() {
        if (!root.hasData)
            return root.updating ? "正在连接 Open-Meteo" : "还没有可显示的预报";

        var uv = weatherNumber("currentUvIndex", NaN);
        var parts = [
            "体感 " + fmtTemp(weatherNumber("currentApparentTemperatureC", NaN), true),
            "风 " + fmtSpeed(weatherNumber("currentWindSpeedMs", NaN))
        ];
        if (validNumber(uv))
            parts.push("UV " + Number(uv).toFixed(1));
        return parts.join(" · ");
    }

    function lastErrorText() {
        return String(service().lastError || "").trim();
    }

    function statusColor() {
        if (root.status === "error")
            return root.dangerRed;
        if (root.status === "stale")
            return root.warningYellow;
        return root.textTertiary;
    }

    function statusLabel() {
        if (root.updating)
            return "更新中";
        if (root.status === "fresh")
            return "已更新";
        if (root.status === "stale")
            return "缓存";
        if (root.status === "error")
            return "失败";
        return "等待";
    }

    function updatedText() {
        if (root.updating)
            return "正在更新";

        if (root.status === "error")
            return root.lastErrorText().length > 0 ? root.lastErrorText() : "更新失败";

        var raw = String(service().updatedAt || "").trim();
        if (raw.length === 0)
            return root.status === "stale" ? "显示缓存" : "等待更新";

        var date = new Date(raw);
        var seconds = Math.max(0, Math.floor((root.currentEpoch * 1000 - date.getTime()) / 1000));
        var label = "";
        if (!isFinite(seconds))
            label = Qt.formatDateTime(date, "M/d hh:mm");
        else if (seconds < 60)
            label = "刚刚更新";
        else if (seconds < 3600)
            label = Math.floor(seconds / 60) + " 分钟前";
        else if (seconds < 86400)
            label = Math.floor(seconds / 3600) + " 小时前";
        else
            label = Qt.formatDateTime(date, "M/d hh:mm");

        return root.status === "stale" ? "缓存 · " + label : label;
    }

    // --- Section 3: weather summaries ---
    function dailyLow(item) {
        return valueAt(item, "temperatureMinC", NaN);
    }

    function dailyHigh(item) {
        return valueAt(item, "temperatureMaxC", NaN);
    }

    function dailyRangeMin() {
        var out = NaN;
        for (var i = 0; i < dailyVisibleCount(); i++) {
            var low = dailyLow(dailyAt(i));
            if (validNumber(low))
                out = validNumber(out) ? Math.min(out, low) : low;
        }
        return out;
    }

    function dailyRangeMax() {
        var out = NaN;
        for (var i = 0; i < dailyVisibleCount(); i++) {
            var high = dailyHigh(dailyAt(i));
            if (validNumber(high))
                out = validNumber(out) ? Math.max(out, high) : high;
        }
        return out;
    }

    function rangeOffset(low) {
        var minValue = dailyRangeMin();
        var maxValue = dailyRangeMax();
        if (!validNumber(low) || !validNumber(minValue) || !validNumber(maxValue) || maxValue <= minValue)
            return 0;
        return Math.max(0, Math.min(1, (low - minValue) / (maxValue - minValue)));
    }

    function rangeWidth(low, high) {
        var minValue = dailyRangeMin();
        var maxValue = dailyRangeMax();
        if (!validNumber(low) || !validNumber(high) || !validNumber(minValue) || !validNumber(maxValue) || maxValue <= minValue)
            return 0.35;
        return Math.max(0.18, Math.min(1, (high - low) / (maxValue - minValue)));
    }

    function todayPrecipitation() {
        var day = todayDaily();
        var dailySum = valueAt(day, "precipitationSumMm", NaN);
        if (validNumber(dailySum))
            return dailySum;
        return weatherNumber("currentPrecipitationMm", NaN);
    }

    function todayPrecipProbability() {
        return valueAt(todayDaily(), "precipitationProbabilityMax", NaN);
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
            return root.successGreen;
        if (v < 6)
            return "#ffca28";
        if (v < 8)
            return "#ffa726";
        if (v < 11)
            return root.dangerRed;
        return "#bf5af2";
    }

    function windAccent(ms) {
        if (!validNumber(ms))
            return "#8e8e93";
        var v = Number(ms);
        if (v < 4)
            return root.successGreen;
        if (v < 8)
            return "#ffca28";
        if (v < 12)
            return "#ff9f0a";
        return root.dangerRed;
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
        var colors = ["#00c781", "#9adf4f", "#ffd041", "#ff9f0a", "#ff453a", "#bf5af2"];
        return colors[Math.max(0, Math.min(colors.length - 1, level))];
    }

    function aqiLevelName(level) {
        var names = ["优", "良", "轻度", "中度", "重度", "危险"];
        return level < 0 || level >= names.length ? "--" : names[level];
    }

    function aqiSummary() {
        var a = service().currentAirQuality || {};
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
            return { value: NaN, level: "--", color: "#8e8e93", pollutant: "--" };

        var level = aqiLevelIndex(best.value);
        return {
            value: best.value,
            level: aqiLevelName(level),
            color: aqiPalette(level),
            pollutant: best.label
        };
    }

    // --- Section 4: inline components ---
    component IconButton: Rectangle {
        id: button

        property string iconCode: ""
        property bool busy: false

        signal activated()

        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        radius: 16
        color: enabled ? (buttonMouse.containsMouse ? root.cardHover : "transparent") : "transparent"
        border.color: buttonMouse.containsMouse && enabled ? root.cardStroke : "transparent"
        border.width: 1
        opacity: enabled ? 1 : 0.55

        TahoeSymbol {
            id: buttonIcon
            anchors.centerIn: parent
            name: button.busy ? "\ue863" : button.iconCode // sync
            color: root.textSecondary
            size: 18
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (button.enabled)
                    button.activated();
            }
        }
    }

    component StatusCapsule: Rectangle {
        id: capsule

        property string text: ""
        property color accent: root.warningYellow

        width: label.implicitWidth + 16
        height: 24
        radius: 12
        color: Qt.rgba(accent.r, accent.g, accent.b, root.darkMode ? 0.20 : 0.14)
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.42)
        border.width: 1

        Text {
            id: label

            anchors.centerIn: parent
            text: capsule.text
            color: capsule.accent
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    component MiniMetricPill: Rectangle {
        id: pill

        property string iconCode: ""
        property string label: ""
        property string value: "--"

        height: 42
        radius: 14
        color: root.cardFill
        border.color: root.cardStroke
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 7

            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: pill.iconCode
                color: root.accentBlue
                size: 16
            }

            Column {
                width: parent.width - 24
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: pill.label
                    color: root.textTertiary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: pill.value
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.family: root.monoFontFamily
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }
    }

    component SectionHeader: Row {
        id: header

        property string title: ""
        property string detail: ""

        width: parent ? parent.width : 0
        height: 20
        spacing: 8

        Text {
            width: parent.width - detailLabel.implicitWidth - 8
            text: header.title
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: detailLabel

            text: header.detail
            color: root.textTertiary
            font.pixelSize: 11
            font.family: root.monoFontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component HourlyStrip: Item {
        id: strip

        height: 108

        Flickable {
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: Math.max(width, root.hourlyVisibleCount() * 66)
            contentHeight: height
            interactive: contentWidth > width

            Row {
                height: parent.height
                spacing: 8

                Repeater {
                    model: root.hourlyVisibleCount()

                    delegate: HourlyChip {
                        required property int index

                        width: 58
                        hourIndex: index
                        item: root.hourlyAt(index)
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.hourlyVisibleCount() === 0
            text: "暂无逐时预报"
            color: root.textSecondary
            font.pixelSize: 13
        }
    }

    component HourlyChip: Rectangle {
        id: chip

        property int hourIndex: 0
        property var item: ({})

        readonly property bool cellNight: !root.valueAt(item, "isDay", true)
        readonly property real pop: root.valueAt(item, "precipitationProbability", 0)

        height: 100
        radius: 17
        color: chipMouse.containsMouse ? root.cardHover : root.cardFill
        border.color: root.cardStroke
        border.width: 1

        Behavior on color { ColorAnimation { duration: Motion.fadeFast(root.settingsService) } }

        Column {
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 4

            Text {
                width: parent.width
                text: chip.hourIndex === 0 ? "现在" : root.fmtHour(chip.item.time)
                color: root.textSecondary
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            MeteoIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28
                height: 28
                weatherCode: root.valueAt(chip.item, "weatherCode", -1)
                night: chip.cellNight
                color: root.textPrimary
            }

            Text {
                width: parent.width
                text: root.fmtTemp(root.valueAt(chip.item, "temperatureC", NaN), false)
                color: root.textPrimary
                font.pixelSize: 15
                font.family: root.monoFontFamily
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: chip.pop > 0 ? root.fmtPercent(chip.pop) : " "
                color: root.precipBlue
                font.pixelSize: 10
                font.family: root.monoFontFamily
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    component DailyForecastList: Rectangle {
        id: list

        readonly property int rowCount: root.dailyVisibleCount()
        readonly property int rowHeight: 42

        height: rowCount > 0 ? rowCount * rowHeight + 8 : 70
        radius: 18
        color: root.cardFill
        border.color: root.cardStroke
        border.width: 1
        clip: true

        Column {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4

            Repeater {
                model: list.rowCount

                delegate: DailyRow {
                    required property int index

                    width: list.width
                    rowIndex: index
                    item: root.dailyAt(index)
                    last: index === list.rowCount - 1
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: list.rowCount === 0
            text: "暂无每日预报"
            color: root.textSecondary
            font.pixelSize: 13
        }
    }

    component DailyRow: Item {
        id: row

        property int rowIndex: 0
        property var item: ({})
        property bool last: false

        readonly property real low: root.dailyLow(item)
        readonly property real high: root.dailyHigh(item)
        readonly property real barOffset: root.rangeOffset(low)
        readonly property real barWidth: root.rangeWidth(low, high)
        readonly property real pop: root.valueAt(item, "precipitationProbabilityMax", 0)

        height: 42

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            text: root.dayLabel(row.rowIndex, row.item.time)
            color: row.rowIndex === 0 ? root.textPrimary : root.textSecondary
            font.pixelSize: 12
            font.weight: row.rowIndex === 0 ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        MeteoIcon {
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            weatherCode: root.valueAt(row.item, "weatherCode", -1)
            night: false
            color: root.textPrimary
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 92
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: row.pop > 0 ? root.fmtPercent(row.pop) : ""
            color: root.precipBlue
            font.pixelSize: 10
            font.family: root.monoFontFamily
            elide: Text.ElideRight
        }

        Text {
            anchors.right: tempBar.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: root.fmtTemp(row.low, false)
            color: root.textTertiary
            font.pixelSize: 12
            font.family: root.monoFontFamily
            horizontalAlignment: Text.AlignRight
        }

        Item {
            id: tempBar

            anchors.right: highLabel.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(56, parent.width - 232)
            height: 6

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.darkMode ? "#18ffffff" : "#1c1d1d1f"
            }

            Rectangle {
                x: Math.max(0, Math.min(parent.width - width, parent.width * row.barOffset))
                width: Math.max(12, Math.min(parent.width, parent.width * row.barWidth))
                height: parent.height
                radius: height / 2
                color: root.accentBlue
            }
        }

        Text {
            id: highLabel

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: root.fmtTemp(row.high, false)
            color: root.textPrimary
            font.pixelSize: 12
            font.family: root.monoFontFamily
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            height: 1
            visible: !row.last
            color: root.separator
        }
    }

    component CompactMetricTile: Rectangle {
        id: tile

        property string iconCode: ""
        property string title: ""
        property string value: "--"
        property string detail: ""
        property color accent: root.accentBlue

        height: 78
        radius: 16
        color: tileMouse.containsMouse ? root.cardHover : root.cardFill
        border.color: root.cardStroke
        border.width: 1

        Behavior on color { ColorAnimation { duration: Motion.fadeFast(root.settingsService) } }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            anchors.topMargin: 10
            spacing: 7

            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: tile.iconCode
                color: tile.accent
                size: 17
            }

            Text {
                width: parent.width - 24
                text: tile.title
                color: root.textSecondary
                font.pixelSize: 11
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: detailText.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 2
            text: tile.value
            color: root.textPrimary
            font.pixelSize: tile.value.length > 8 ? 17 : 22
            font.family: root.monoFontFamily
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            id: detailText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 9
            text: tile.detail
            color: root.textTertiary
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    component StatusBanner: Rectangle {
        id: banner

        property string iconCode: ""
        property string title: ""
        property string message: ""
        property color accent: root.warningYellow

        height: 56
        radius: 16
        color: Qt.rgba(accent.r, accent.g, accent.b, root.darkMode ? 0.16 : 0.11)
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.38)
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            spacing: 10

            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: banner.iconCode
                color: banner.accent
                size: 20
            }

            Column {
                width: parent.width - 34
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: banner.title
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: banner.message
                    color: root.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }
    }

    component EmptyState: Item {
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 320)
            spacing: 10

            TahoeSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "\ue2bd" // wb_cloudy
                color: root.accentBlue
                size: 42
            }

            Text {
                width: parent.width
                text: root.status === "error" ? "更新失败" : "等待天气数据"
                color: root.textPrimary
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: root.lastErrorText().length > 0 ? root.lastErrorText() : "天气服务会在定位完成后显示预报"
                color: root.textSecondary
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }

    component BusyStripe: Rectangle {
        id: stripe

        height: 2
        color: "transparent"
        clip: true

        Rectangle {
            width: parent.width * 0.36
            height: parent.height
            radius: height / 2
            color: root.accentBlue
            x: -width

            // Local exception: loading shimmer is an ambient loop and keeps
            // its own InOut timing instead of shell surface motion tokens.
            SequentialAnimation on x {
                running: stripe.visible
                loops: Animation.Infinite
                NumberAnimation { from: -stripe.width * 0.36; to: stripe.width; duration: 1100; easing.type: Easing.InOutCubic }
            }
        }
    }
}
