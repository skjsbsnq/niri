pragma ComponentBehavior: Bound

import QtQuick

// LS10: 天气趋势卡。
//
// 职责：用同一个 Tahoe 玻璃卡片组件展示 16 天 daily 或 24 小时 hourly 预报。
// 数据输入只读 sourceModel（JS 数组或 ListModel 均可），不直接依赖 Weather 服务；
// LS11 组装天气页时再绑定 weather.dailyForecast / weather.hourlyForecast。
Rectangle {
    id: root

    property var sourceModel: []
    property var settingsService: null
    property string mode: "daily" // "daily" | "hourly"
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"

    readonly property bool dailyMode: mode === "daily"
    readonly property int maxItems: dailyMode ? 16 : 24
    readonly property real itemWidth: dailyMode
        ? Math.max(76, trendFlick.width > 0 ? trendFlick.width / 5.6 : 82)
        : Math.max(68, trendFlick.width > 0 ? trendFlick.width / 6.4 : 72)
    readonly property int headerHeight: 48
    readonly property color cardFill: darkMode ? "#28ffffff" : "#60ffffff"
    readonly property color cardStroke: darkMode ? "#32ffffff" : "#70ffffff"
    readonly property color hoverFill: darkMode ? "#20ffffff" : "#3affffff"
    readonly property color textPrimary: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color textSecondary: darkMode ? "#c8d0d8" : "#991d1d1f"
    readonly property color textTertiary: darkMode ? "#9da7b1" : "#731d1d1f"
    readonly property color accentBlue: darkMode ? "#2c9cf2" : "#0b6bd3"
    readonly property color accentLow: darkMode ? "#b48ead" : "#7a4ed9"
    readonly property color precipBlue: darkMode ? "#7dc8ff" : "#2c9cf2"
    readonly property string iconFont: "Material Icons"

    implicitHeight: dailyMode ? 302 : 236
    radius: 18
    color: cardFill
    clip: true

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.color: root.cardStroke
        border.width: 1
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

    function boolAt(map, key, fallback) {
        if (!map || map[key] === undefined || map[key] === null)
            return fallback;
        return !!map[key];
    }

    function modelCount() {
        if (!sourceModel)
            return 0;
        if (typeof sourceModel.count === "function")
            return Math.min(maxItems, Number(sourceModel.count()) || 0);
        if (sourceModel.count !== undefined)
            return Math.min(maxItems, Number(sourceModel.count) || 0);
        if (sourceModel.length !== undefined)
            return Math.min(maxItems, Number(sourceModel.length) || 0);
        return 0;
    }

    function itemAt(index) {
        if (!sourceModel || index < 0)
            return {};
        if (typeof sourceModel.get === "function")
            return sourceModel.get(index) || {};
        if (sourceModel.length !== undefined && index < sourceModel.length)
            return sourceModel[index] || {};
        return {};
    }

    function fmtTemp(value) {
        if (!validNumber(value))
            return "--";
        var temp = Number(value);
        var unit = settingsService ? String(settingsService.weatherTempUnit || "c").toLowerCase() : "c";
        if (unit === "f")
            temp = temp * 9 / 5 + 32;
        return Math.round(temp) + "°";
    }

    function fmtPercent(value) {
        return validNumber(value) ? Math.round(Number(value)) + "%" : "--";
    }

    function dayLabel(index, epoch) {
        if (index === 0)
            return "昨天";
        if (index === 1)
            return "今天";
        if (index === 2)
            return "明天";
        if (!epoch)
            return "--";
        var week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
        return week[new Date(Number(epoch) * 1000).getDay()];
    }

    function dateLabel(epoch) {
        return epoch ? Qt.formatDateTime(new Date(Number(epoch) * 1000), "M/d") : "--";
    }

    function hourLabel(epoch) {
        return epoch ? Qt.formatDateTime(new Date(Number(epoch) * 1000), "hh:00") : "--";
    }

    function highTemp(item) {
        return valueAt(item, "temperatureMaxC", NaN);
    }

    function lowTemp(item) {
        return valueAt(item, "temperatureMinC", NaN);
    }

    function hourTemp(item) {
        return valueAt(item, "temperatureC", NaN);
    }

    function colorWithAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function requestRepaint() {
        trendCanvas.requestPaint();
    }

    onSourceModelChanged: requestRepaint()
    onSettingsServiceChanged: requestRepaint()
    onModeChanged: requestRepaint()
    onDarkModeChanged: requestRepaint()
    onWidthChanged: requestRepaint()
    onHeightChanged: requestRepaint()

    Connections {
        target: root.settingsService

        function onWeatherTempUnitChanged() {
            root.requestRepaint();
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Row {
            width: parent.width
            height: root.headerHeight
            leftPadding: 14
            rightPadding: 14
            spacing: 8

            Text {
                text: root.dailyMode ? "\ue935" : "\ue8b5" // calendar_month / schedule
                color: root.accentBlue
                font.family: root.iconFont
                font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                width: parent.width - 96
                text: root.dailyMode ? "16 天预报" : "逐时预报"
                color: root.textPrimary
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.modelCount() + " 格"
                color: root.textTertiary
                font.pixelSize: 11
                font.family: root.monoFontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Flickable {
            id: trendFlick

            width: parent.width
            height: parent.height - root.headerHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: Math.max(width, root.modelCount() * root.itemWidth)
            contentHeight: height
            interactive: root.modelCount() * root.itemWidth > width

            onWidthChanged: root.requestRepaint()
            onHeightChanged: root.requestRepaint()
            onContentWidthChanged: root.requestRepaint()

            Item {
                id: trendContent

                width: trendFlick.contentWidth
                height: trendFlick.height

                readonly property real dailyChartTop: 118
                readonly property real dailyChartBottom: Math.max(dailyChartTop + 54, height - 52)
                readonly property real hourlyChartTop: 92
                readonly property real hourlyChartBottom: Math.max(hourlyChartTop + 58, height - 30)

                Canvas {
                    id: trendCanvas

                    anchors.fill: parent
                    antialiasing: true

                    function pointX(index) {
                        return root.itemWidth * index + root.itemWidth / 2;
                    }

                    function yAt(value, minValue, maxValue, top, bottom) {
                        return bottom - (value - minValue) / (maxValue - minValue) * (bottom - top);
                    }

                    function drawDot(ctx, x, y, color) {
                        ctx.fillStyle = color;
                        ctx.beginPath();
                        ctx.arc(x, y, 4.2, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.fillStyle = root.cardFill;
                        ctx.beginPath();
                        ctx.arc(x, y, 2.0, 0, Math.PI * 2);
                        ctx.fill();
                    }

                    function drawLine(ctx, values, minTemp, maxTemp, top, bottom, color, widthPx) {
                        var count = values.length;
                        if (count < 2)
                            return;

                        ctx.strokeStyle = color;
                        ctx.lineWidth = widthPx;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";
                        ctx.beginPath();
                        for (var i = 0; i < count; i++) {
                            var x = pointX(i);
                            var y = yAt(values[i], minTemp, maxTemp, top, bottom);
                            if (i === 0)
                                ctx.moveTo(x, y);
                            else
                                ctx.lineTo(x, y);
                        }
                        ctx.stroke();

                        for (var p = 0; p < count; p++)
                            drawDot(ctx, pointX(p), yAt(values[p], minTemp, maxTemp, top, bottom), color);
                    }

                    function drawDaily(ctx) {
                        var count = root.modelCount();
                        if (count < 2)
                            return;

                        var highs = [];
                        var lows = [];
                        var minTemp = 999;
                        var maxTemp = -999;
                        for (var i = 0; i < count; i++) {
                            var item = root.itemAt(i);
                            var hi = root.highTemp(item);
                            var lo = root.lowTemp(item);
                            highs.push(hi);
                            lows.push(lo);
                            if (root.validNumber(hi)) {
                                minTemp = Math.min(minTemp, hi);
                                maxTemp = Math.max(maxTemp, hi);
                            }
                            if (root.validNumber(lo)) {
                                minTemp = Math.min(minTemp, lo);
                                maxTemp = Math.max(maxTemp, lo);
                            }
                        }
                        if (maxTemp < minTemp)
                            return;
                        if (Math.abs(maxTemp - minTemp) < 0.1) {
                            maxTemp += 1;
                            minTemp -= 1;
                        }

                        var top = trendContent.dailyChartTop;
                        var bottom = trendContent.dailyChartBottom;

                        ctx.beginPath();
                        for (var h = 0; h < count; h++) {
                            var hx = pointX(h);
                            var hy = yAt(highs[h], minTemp, maxTemp, top, bottom);
                            if (h === 0)
                                ctx.moveTo(hx, hy);
                            else
                                ctx.lineTo(hx, hy);
                        }
                        for (var l = count - 1; l >= 0; l--)
                            ctx.lineTo(pointX(l), yAt(lows[l], minTemp, maxTemp, top, bottom));
                        ctx.closePath();
                        var grad = ctx.createLinearGradient(0, top, 0, bottom);
                        grad.addColorStop(0, root.colorWithAlpha(root.accentBlue, 0.16));
                        grad.addColorStop(1, root.colorWithAlpha(root.accentLow, 0.04));
                        ctx.fillStyle = grad;
                        ctx.fill();

                        drawLine(ctx, highs, minTemp, maxTemp, top, bottom, root.accentBlue, 2.6);
                        drawLine(ctx, lows, minTemp, maxTemp, top, bottom, root.accentLow, 2.4);

                        ctx.font = "600 11px \"" + root.monoFontFamily + "\"";
                        ctx.textAlign = "center";
                        for (var t = 0; t < count; t++) {
                            var x = pointX(t);
                            var highY = yAt(highs[t], minTemp, maxTemp, top, bottom);
                            var lowY = yAt(lows[t], minTemp, maxTemp, top, bottom);
                            ctx.fillStyle = root.textPrimary;
                            ctx.fillText(root.fmtTemp(highs[t]), x, highY - 9);
                            ctx.fillStyle = root.textSecondary;
                            ctx.fillText(root.fmtTemp(lows[t]), x, lowY + 17);
                        }
                    }

                    function drawHourly(ctx) {
                        var count = root.modelCount();
                        if (count < 2)
                            return;

                        var values = [];
                        var minTemp = 999;
                        var maxTemp = -999;
                        for (var i = 0; i < count; i++) {
                            var item = root.itemAt(i);
                            var temp = root.hourTemp(item);
                            values.push(temp);
                            if (root.validNumber(temp)) {
                                minTemp = Math.min(minTemp, temp);
                                maxTemp = Math.max(maxTemp, temp);
                            }
                        }
                        if (maxTemp < minTemp)
                            return;
                        if (Math.abs(maxTemp - minTemp) < 0.1) {
                            maxTemp += 1;
                            minTemp -= 1;
                        }

                        var top = trendContent.hourlyChartTop;
                        var bottom = trendContent.hourlyChartBottom;
                        drawLine(ctx, values, minTemp, maxTemp, top, bottom, root.accentBlue, 2.8);

                        ctx.fillStyle = root.textPrimary;
                        ctx.font = "600 11px \"" + root.monoFontFamily + "\"";
                        ctx.textAlign = "center";
                        for (var t = 0; t < count; t++)
                            ctx.fillText(root.fmtTemp(values[t]), pointX(t), yAt(values[t], minTemp, maxTemp, top, bottom) - 10);
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (root.dailyMode)
                            drawDaily(ctx);
                        else
                            drawHourly(ctx);
                    }
                }

                Repeater {
                    model: root.modelCount()

                    delegate: Item {
                        id: cell

                        required property int index

                        readonly property var entry: root.itemAt(index)
                        readonly property bool cellNight: root.dailyMode ? false : !root.boolAt(entry, "isDay", true)
                        readonly property real pop: root.valueAt(entry, "precipitationProbabilityMax",
                            root.valueAt(entry, "precipitationProbability", 0))

                        x: root.itemWidth * index
                        width: root.itemWidth
                        height: trendContent.height
                        opacity: root.dailyMode && index === 0 ? 0.55 : 1

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 12
                            color: cellMouse.containsMouse ? root.hoverFill : "transparent"

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Column {
                            y: 6
                            width: parent.width
                            spacing: 2

                            Text {
                                width: parent.width
                                text: root.dailyMode ? root.dayLabel(cell.index, cell.entry.time) : root.hourLabel(cell.entry.time)
                                color: root.textPrimary
                                font.pixelSize: root.dailyMode ? 12 : 11
                                font.weight: root.dailyMode && cell.index === 1 ? Font.DemiBold : Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: root.dailyMode
                                text: root.dateLabel(cell.entry.time)
                                color: root.textTertiary
                                font.pixelSize: 10
                                font.family: root.monoFontFamily
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MeteoIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.dailyMode ? 42 : 29
                            width: root.dailyMode ? 34 : 32
                            height: width
                            weatherCode: root.valueAt(cell.entry, "weatherCode", -1)
                            night: cell.cellNight
                            color: root.textPrimary
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.dailyMode ? trendContent.dailyChartBottom + 20 : trendContent.hourlyChartBottom + 14
                            spacing: 3
                            visible: cell.pop > 0

                            Text {
                                text: "\ue798" // water_drop
                                color: root.precipBlue
                                font.family: root.iconFont
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: root.fmtPercent(cell.pop)
                                color: root.textSecondary
                                font.pixelSize: 10
                                font.family: root.monoFontFamily
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: cellMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.modelCount() === 0
        text: "暂无预报数据"
        color: root.textSecondary
        font.pixelSize: 13
    }
}
