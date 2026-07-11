pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme
import "WeatherCodes.js" as WeatherCodes

// T19 weather widget: status-gradient mid-size card, large non-mono temp,
// embedded hourly strip, daily forecast gradient temp bars without stroke.
// Glass shell remains owned by LeftSidebar.qml.
Item {
    id: root

    property var weatherService: null
    property var settingsService: null
    property bool sidebarOpen: false
    property bool active: false
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"
    property bool cardsEnter: false
    property bool useSpring: false

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
    // Cards: fill + soft shadow plate; no 1px stroke (T19).
    readonly property color cardFill: darkMode ? "#22ffffff" : "#48ffffff"
    readonly property color cardHover: darkMode ? "#30ffffff" : "#60ffffff"
    readonly property color separator: Theme.separator(darkMode)

    property real currentEpoch: Math.floor(Date.now() / 1000)

    signal openWeatherSettingsRequested()

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.currentEpoch = Math.floor(Date.now() / 1000)
    }

    function heroGradientColors() {
        var code = currentWeatherCode();
        var night = currentIsNight();
        var slug = WeatherCodes.slug(code, night);
        // Status-tinted gradients (clear / rain / night / error / cloudy).
        if (root.status === "error" && !root.hasData)
            return ["#5a6570", "#2c333a"];
        if (night || slug.indexOf("night") !== -1)
            return ["#1a2744", "#0b1224"];
        if (slug.indexOf("rain") !== -1 || slug.indexOf("drizzle") !== -1
                || slug.indexOf("thunder") !== -1 || slug.indexOf("sleet") !== -1)
            return ["#3d5a80", "#1b3a4b"];
        if (slug.indexOf("snow") !== -1)
            return ["#7b8fa1", "#4a5d73"];
        if (slug.indexOf("fog") !== -1 || slug.indexOf("cloudy") !== -1 || slug === "cloudy")
            return ["#6b7c8f", "#3d4a5c"];
        // clear / mostly clear day
        return ["#4facfe", "#00c6fb"];
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Toolbar: location + refresh/settings (no chrome title).
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 76
                text: root.locationTitle()
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                IconButton {
                    iconCode: "\ue5d5"
                    enabled: !!root.weatherService && !root.updating
                    busy: root.updating
                    onActivated: {
                        if (root.weatherService && typeof root.weatherService.refresh === "function")
                            root.weatherService.refresh();
                    }
                }

                IconButton {
                    iconCode: "\ue8b8"
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

                // --- Hero gradient widget ---
                WidgetCard {
                    id: heroCard
                    width: parent.width
                    height: 168
                    cardIndex: 0
                    fillColor: "transparent"

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: root.heroGradientColors()[0]
                            }
                            GradientStop {
                                position: 1.0
                                color: root.heroGradientColors()[1]
                            }
                        }
                    }

                    // Soft bottom shadow plate (no stroke).
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.bottom
                        anchors.topMargin: -2
                        height: 8
                        radius: 4
                        color: "#18000000"
                        z: -1
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: heroIcon.left
                        anchors.top: parent.top
                        anchors.margins: 16
                        anchors.rightMargin: 8
                        spacing: 2

                        Row {
                            spacing: 8
                            Text {
                                text: root.fmtTemp(root.weatherNumber("currentTemperatureC", NaN), false)
                                color: "#ffffff"
                                // Large non-mono (T19).
                                font.pixelSize: 52
                                font.weight: Font.DemiBold
                                lineHeight: 0.9
                            }
                            Text {
                                text: root.tempUnit() === "f" ? "°F" : "°C"
                                color: "#ccffffff"
                                font.pixelSize: 18
                                font.weight: Font.Medium
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 10
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
                            color: "#f0ffffff"
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.detailSummary()
                            color: "#ccffffff"
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        id: heroIcon
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        width: 72
                        height: 72

                        MeteoIcon {
                            anchors.centerIn: parent
                            width: 64
                            height: 64
                            weatherCode: root.currentWeatherCode()
                            night: root.currentIsNight()
                            color: "#ffffff"
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        spacing: 8

                        MiniMetricPill {
                            width: (parent.width - 16) / 3
                            label: "体感"
                            value: root.fmtTemp(root.weatherNumber("currentApparentTemperatureC", NaN), true)
                        }
                        MiniMetricPill {
                            width: (parent.width - 16) / 3
                            label: "湿度"
                            value: root.fmtPercent(root.weatherNumber("currentHumidity", NaN))
                        }
                        MiniMetricPill {
                            width: (parent.width - 16) / 3
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

                // Embedded hourly strip (inside soft card, no stroke).
                WidgetCard {
                    width: parent.width
                    height: 118
                    cardIndex: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Text {
                            text: "逐时"
                            color: root.textSecondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        HourlyStrip {
                            width: parent.width
                            height: 80
                        }
                    }
                }

                // Daily forecast with gradient temp bars, no outer stroke.
                WidgetCard {
                    width: parent.width
                    height: dailyList.implicitHeight + 28
                    cardIndex: 2

                    Column {
                        id: dailyList
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 0

                        Text {
                            text: "每日"
                            color: root.textSecondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            height: 20
                        }

                        Repeater {
                            model: root.dailyVisibleCount()
                            delegate: DailyRow {
                                required property int index
                                width: dailyList.width
                                rowIndex: index
                                item: root.dailyAt(index)
                                last: index === root.dailyVisibleCount() - 1
                            }
                        }

                        Text {
                            width: parent.width
                            height: 40
                            visible: root.dailyVisibleCount() === 0
                            text: "暂无每日预报"
                            color: root.textSecondary
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // Compact metrics grid (no stroke).
                WidgetCard {
                    width: parent.width
                    height: metricsGrid.implicitHeight + 20
                    cardIndex: 3

                    Grid {
                        id: metricsGrid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        columns: root.width >= 360 ? 2 : 1
                        spacing: 8

                        CompactMetricTile {
                            width: metricsGrid.columns === 1
                                ? metricsGrid.width
                                : (metricsGrid.width - metricsGrid.spacing) / 2
                            iconCode: "\ue430"
                            title: "紫外线"
                            value: root.fmtUv(root.weatherNumber("currentUvIndex", NaN))
                            detail: root.uvLevel(root.weatherNumber("currentUvIndex", NaN))
                            accent: root.uvAccent(root.weatherNumber("currentUvIndex", NaN))
                        }
                        CompactMetricTile {
                            width: metricsGrid.columns === 1
                                ? metricsGrid.width
                                : (metricsGrid.width - metricsGrid.spacing) / 2
                            readonly property var summary: root.aqiSummary()
                            iconCode: "\uefd8"
                            title: "空气"
                            value: root.validNumber(summary.value) ? Math.round(summary.value).toString() : "--"
                            detail: root.validNumber(summary.value) ? summary.level : "暂无 AQI"
                            accent: summary.color
                        }
                        CompactMetricTile {
                            width: metricsGrid.columns === 1
                                ? metricsGrid.width
                                : (metricsGrid.width - metricsGrid.spacing) / 2
                            iconCode: "\ue9e4"
                            title: "气压"
                            value: root.fmtPressure(root.weatherNumber("currentPressureHpa", NaN))
                            detail: "hPa"
                            accent: root.darkMode ? "#7dc8ff" : "#0b6bd3"
                        }
                        CompactMetricTile {
                            width: metricsGrid.columns === 1
                                ? metricsGrid.width
                                : (metricsGrid.width - metricsGrid.spacing) / 2
                            iconCode: "\ue798"
                            title: "降水"
                            value: root.fmtPrecip(root.todayPrecipitation())
                            detail: root.validNumber(root.todayPrecipProbability())
                                ? "概率 " + root.fmtPercent(root.todayPrecipProbability())
                                : "今日累计"
                            accent: root.precipBlue
                        }
                    }
                }

                Item { width: 1; height: 4 }
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

    // --- helpers (service / format) — unchanged semantics ---
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

    function fmtHour(epoch) {
        var n = Number(epoch);
        return isFinite(n) && n > 0 ? Qt.formatDateTime(new Date(n * 1000), "hh:00") : "--";
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
        return root.updatedText();
    }

    function lastErrorText() {
        return String(service().lastError || "").trim();
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

    // --- components ---
    component WidgetCard: Item {
        id: wcard
        property int cardIndex: 0
        property color fillColor: root.cardFill

        // Shadow plate
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            radius: 18
            color: "#14000000"
            z: -1
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: wcard.fillColor
            // No border/stroke (T19).
        }

        property real enterY: Motion.sidebarCardEnterOffsetPx
        property real enterOpacity: 0
        transform: Translate { y: wcard.enterY }
        opacity: enterOpacity

        SpringAnimation {
            id: enterYSpring
            target: wcard
            property: "enterY"
            spring: Motion.springSmooth.spring
            damping: Motion.springSmooth.damping
            epsilon: 0.0005
        }
        NumberAnimation {
            id: enterYEase
            target: wcard
            property: "enterY"
            duration: Motion.elementMove(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
        NumberAnimation {
            id: enterOpacityAnim
            target: wcard
            property: "enterOpacity"
            duration: Motion.fadeFast(root.settingsService)
            easing.type: Motion.standardDecel
        }

        function animateEnter(toY, toOpacity) {
            enterYSpring.stop();
            enterYEase.stop();
            enterOpacityAnim.stop();
            if (root.useSpring && !Motion.reducedMotion(root.settingsService)) {
                enterYSpring.to = toY;
                enterYSpring.restart();
            } else {
                enterYEase.to = toY;
                enterYEase.duration = Motion.elementMove(root.settingsService);
                enterYEase.restart();
            }
            enterOpacityAnim.to = toOpacity;
            enterOpacityAnim.duration = Motion.fadeFast(root.settingsService);
            enterOpacityAnim.restart();
        }

        function snapEnter(toY, toOpacity) {
            enterYSpring.stop();
            enterYEase.stop();
            enterOpacityAnim.stop();
            wcard.enterY = toY;
            wcard.enterOpacity = toOpacity;
        }

        Connections {
            target: root
            function onCardsEnterChanged() {
                if (!root.cardsEnter) {
                    wcard.snapEnter(Motion.sidebarCardEnterOffsetPx, 0);
                    return;
                }
                revealTimer.interval = Motion.sidebarCardStaggerDelay(wcard.cardIndex);
                revealTimer.restart();
            }
        }
        Timer {
            id: revealTimer
            repeat: false
            onTriggered: wcard.animateEnter(0, 1)
        }
        Component.onCompleted: {
            if (root.cardsEnter)
                wcard.snapEnter(0, 1);
        }
    }

    component IconButton: Item {
        id: button
        property string iconCode: ""
        property bool busy: false
        property bool enabled: true
        signal activated()

        width: 28
        height: 28

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: buttonMouse.containsMouse && button.enabled ? root.cardHover : "transparent"
        }

        TahoeSymbol {
            anchors.centerIn: parent
            name: button.busy ? "\ue863" : button.iconCode
            color: root.textSecondary
            size: 16
            opacity: button.enabled ? 1 : 0.5
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: button.enabled
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.activated()
        }
    }

    component StatusCapsule: Rectangle {
        id: capsule
        property string text: ""
        property color accent: root.warningYellow
        width: label.implicitWidth + 14
        height: 22
        radius: 11
        color: Qt.rgba(accent.r, accent.g, accent.b, 0.28)
        // No stroke.
        Text {
            id: label
            anchors.centerIn: parent
            text: capsule.text
            color: "#ffffff"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    component MiniMetricPill: Rectangle {
        id: pill
        property string label: ""
        property string value: "--"
        height: 36
        radius: 12
        color: "#28ffffff"
        // No border.
        Column {
            anchors.centerIn: parent
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pill.label
                color: "#ccffffff"
                font.pixelSize: 10
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pill.value
                color: "#ffffff"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
    }

    component HourlyStrip: Item {
        Flickable {
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: Math.max(width, root.hourlyVisibleCount() * 56)
            contentHeight: height
            interactive: contentWidth > width

            Row {
                height: parent.height
                spacing: 6
                Repeater {
                    model: root.hourlyVisibleCount()
                    delegate: Column {
                        required property int index
                        width: 50
                        spacing: 3
                        Text {
                            width: parent.width
                            text: index === 0 ? "现在" : root.fmtHour(root.hourlyAt(index).time)
                            color: root.textTertiary
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MeteoIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 24
                            height: 24
                            weatherCode: root.valueAt(root.hourlyAt(index), "weatherCode", -1)
                            night: !root.valueAt(root.hourlyAt(index), "isDay", true)
                            color: root.textPrimary
                        }
                        Text {
                            width: parent.width
                            text: root.fmtTemp(root.valueAt(root.hourlyAt(index), "temperatureC", NaN), false)
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: root.hourlyVisibleCount() === 0
            text: "暂无逐时"
            color: root.textSecondary
            font.pixelSize: 12
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
        height: 36

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            text: root.dayLabel(row.rowIndex, row.item.time)
            color: row.rowIndex === 0 ? root.textPrimary : root.textSecondary
            font.pixelSize: 12
            font.weight: row.rowIndex === 0 ? Font.DemiBold : Font.Medium
        }

        MeteoIcon {
            anchors.left: parent.left
            anchors.leftMargin: 44
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            weatherCode: root.valueAt(row.item, "weatherCode", -1)
            night: false
            color: root.textPrimary
        }

        Text {
            anchors.right: tempBar.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            text: root.fmtTemp(row.low, false)
            color: root.textTertiary
            font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
        }

        Item {
            id: tempBar
            anchors.right: highLabel.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(48, parent.width - 180)
            height: 6

            Rectangle {
                anchors.fill: parent
                radius: 3
                color: root.darkMode ? "#18ffffff" : "#1c1d1d1f"
            }

            // Gradient temperature bar (no stroke).
            Rectangle {
                x: Math.max(0, Math.min(parent.width - width, parent.width * row.barOffset))
                width: Math.max(12, Math.min(parent.width, parent.width * row.barWidth))
                height: parent.height
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.precipBlue }
                    GradientStop { position: 1.0; color: root.warningYellow }
                }
            }
        }

        Text {
            id: highLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            text: root.fmtTemp(row.high, false)
            color: root.textPrimary
            font.pixelSize: 12
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            visible: !row.last
            color: root.separator
        }
    }

    component CompactMetricTile: Item {
        id: tile
        property string iconCode: ""
        property string title: ""
        property string value: "--"
        property string detail: ""
        property color accent: root.accentBlue
        height: 64

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.darkMode ? "#14ffffff" : "#28ffffff"
            // No stroke.
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 2

            Row {
                spacing: 6
                TahoeSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: tile.iconCode
                    color: tile.accent
                    size: 14
                }
                Text {
                    text: tile.title
                    color: root.textSecondary
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: tile.value
                color: root.textPrimary
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
            Text {
                text: tile.detail
                color: root.textTertiary
                font.pixelSize: 11
            }
        }
    }

    component StatusBanner: Rectangle {
        id: banner
        property string iconCode: ""
        property string title: ""
        property string message: ""
        property color accent: root.warningYellow
        height: 52
        radius: 14
        color: Qt.rgba(accent.r, accent.g, accent.b, root.darkMode ? 0.16 : 0.11)
        // No stroke.

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: banner.iconCode
                color: banner.accent
                size: 18
            }
            Column {
                width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: banner.title
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
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
            width: Math.min(parent.width - 40, 300)
            spacing: 10
            TahoeSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "\ue2bd"
                color: root.accentBlue
                size: 40
            }
            Text {
                width: parent.width
                text: root.status === "error" ? "更新失败" : "等待天气数据"
                color: root.textPrimary
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 16
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
            radius: 1
            color: root.accentBlue
            SequentialAnimation on x {
                running: stripe.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: -stripe.width * 0.36
                    to: stripe.width
                    duration: 1100
                    easing.type: Easing.InOutCubic
                }
            }
        }
    }
}
