pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// LS11: 左侧边栏天气页组装。
//
// 职责：把 WeatherBackground、当前天气头部、daily/hourly 趋势卡和指标卡网格组装成
// 一个 Tahoe 风格天气页。数据只读 Weather 服务；刷新调用 weather.refresh()，设置入口
// 只发信号给容器，具体设置页注册留给 LS12。
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
    readonly property string iconFont: "Material Icons"
    readonly property color textPrimary: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color textSecondary: darkMode ? "#c8d0d8" : "#991d1d1f"
    readonly property color textTertiary: darkMode ? "#9da7b1" : "#731d1d1f"
    readonly property color accentBlue: darkMode ? "#2c9cf2" : "#0b6bd3"
    readonly property color cardFill: darkMode ? "#28ffffff" : "#60ffffff"
    readonly property color cardStroke: darkMode ? "#32ffffff" : "#70ffffff"
    readonly property color buttonFill: darkMode ? "#24ffffff" : "#38ffffff"
    readonly property color buttonHover: darkMode ? "#34ffffff" : "#54ffffff"
    readonly property color danger: darkMode ? "#ff453a" : "#e54857"
    readonly property color warning: darkMode ? "#ffd60a" : "#b56a00"
    readonly property real scrollProgress: contentFlick.contentHeight > contentFlick.height
        ? Math.max(0, Math.min(1, contentFlick.contentY / (contentFlick.contentHeight - contentFlick.height)))
        : 0

    signal openWeatherSettingsRequested()

    property real currentEpoch: Math.floor(Date.now() / 1000)

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.currentEpoch = Math.floor(Date.now() / 1000)
    }

    WeatherBackground {
        anchors.fill: parent
        weatherCode: root.currentWeatherCode()
        night: root.currentIsNight()
        windSpeedMs: root.weatherNumber("currentWindSpeedMs", 0)
        windGustsMs: root.weatherNumber("currentWindGustMs", 0)
        animate: root.sidebarOpen && root.active
        darkMode: root.darkMode
        scrollProgress: root.scrollProgress
        visible: true
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.darkMode ? "#52000000" : "#34ffffff" }
            GradientStop { position: 0.45; color: root.darkMode ? "#30000000" : "#1effffff" }
            GradientStop { position: 1.0; color: root.darkMode ? "#70000000" : "#46ffffff" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46

            RowLayout {
                anchors.fill: parent
                spacing: 10

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
                        color: root.status === "error" ? root.danger : (root.status === "stale" ? root.warning : root.textTertiary)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    iconCode: "\ue5d5" // refresh
                    tooltip: root.updating ? "正在刷新" : "刷新"
                    enabled: !!root.weatherService && !root.updating
                    busy: root.updating
                    onActivated: {
                        if (root.weatherService && typeof root.weatherService.refresh === "function")
                            root.weatherService.refresh();
                    }
                }

                IconButton {
                    iconCode: "\ue3c9" // edit
                    tooltip: "天气设置"
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

            Column {
                id: contentColumn

                width: contentFlick.width
                spacing: 14

                Item {
                    width: parent.width
                    height: 186

                    MeteoIcon {
                        id: mainIcon

                        width: 96
                        height: 96
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        weatherCode: root.currentWeatherCode()
                        night: root.currentIsNight()
                        color: root.darkMode ? "#f5f7fb" : "#1d1d1f"
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: mainIcon.left
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        anchors.rightMargin: 10
                        spacing: 5

                        Row {
                            spacing: 8

                            Text {
                                text: root.fmtTemp(root.weatherNumber("currentTemperatureC", NaN), true)
                                color: root.textPrimary
                                font.pixelSize: 58
                                font.family: root.monoFontFamily
                                font.weight: Font.DemiBold
                                lineHeight: 0.9
                            }

                            Text {
                                visible: root.hasData
                                text: root.status === "stale" ? "缓存" : (root.status === "error" ? "失败" : "")
                                color: root.status === "error" ? root.danger : root.warning
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
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

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: 8

                        InfoPill {
                            width: (parent.width - 16) / 3
                            iconCode: "\ue1b1" // device_thermostat
                            label: "体感"
                            value: root.fmtTemp(root.weatherNumber("currentApparentTemperatureC", NaN), true)
                        }

                        InfoPill {
                            width: (parent.width - 16) / 3
                            iconCode: "\ue798" // water_drop
                            label: "湿度"
                            value: root.fmtPercent(root.weatherNumber("currentHumidity", NaN))
                        }

                        InfoPill {
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
                    accent: root.status === "error" ? root.danger : root.warning
                }

                WeatherTrendCard {
                    width: parent.width
                    sourceModel: root.dailyTrendModel()
                    settingsService: root.settingsService
                    mode: "daily"
                    darkMode: root.darkMode
                    monoFontFamily: root.monoFontFamily
                }

                WeatherTrendCard {
                    width: parent.width
                    sourceModel: root.hourlyTrendModel()
                    settingsService: root.settingsService
                    mode: "hourly"
                    darkMode: root.darkMode
                    monoFontFamily: root.monoFontFamily
                }

                WeatherCards {
                    width: parent.width
                    height: implicitHeight
                    weatherService: root.weatherService
                    settingsService: root.settingsService
                    darkMode: root.darkMode
                    monoFontFamily: root.monoFontFamily
                }

                Item {
                    width: parent.width
                    height: 6
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.hasData && !root.updating
        radius: 18
        color: root.darkMode ? "#22000000" : "#22ffffff"

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 320)
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\ue2bd" // wb_cloudy
                color: root.accentBlue
                font.family: root.iconFont
                font.pixelSize: 42
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

    BusyStripe {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.updating
    }

    // --- Section 1: 数据 / 格式化 helper ---
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

    function weatherNumber(key, fallback) {
        var w = service();
        if (!root.hasData || w[key] === undefined || w[key] === null)
            return fallback;
        var n = Number(w[key]);
        return isFinite(n) ? n : fallback;
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

        var apparent = fmtTemp(weatherNumber("currentApparentTemperatureC", NaN), true);
        var wind = fmtSpeed(weatherNumber("currentWindSpeedMs", NaN));
        var uv = weatherNumber("currentUvIndex", NaN);
        var parts = ["体感 " + apparent, "风 " + wind];
        if (validNumber(uv))
            parts.push("UV " + Number(uv).toFixed(1));
        return parts.join(" · ");
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

    function cloneMap(item) {
        var copy = {};
        if (!item)
            return copy;
        var keys = Object.keys(item);
        for (var i = 0; i < keys.length; i++)
            copy[keys[i]] = item[keys[i]];
        return copy;
    }

    function dailyTrendModel() {
        if (tempUnit() !== "f")
            return root.dailyForecast;

        var out = [];
        for (var i = 0; i < root.dailyForecast.length; i++) {
            var item = cloneMap(root.dailyForecast[i]);
            if (validNumber(item.temperatureMaxC))
                item.temperatureMaxC = convertTemp(item.temperatureMaxC);
            if (validNumber(item.temperatureMinC))
                item.temperatureMinC = convertTemp(item.temperatureMinC);
            out.push(item);
        }
        return out;
    }

    function hourlyTrendModel() {
        if (tempUnit() !== "f")
            return root.hourlyForecast;

        var out = [];
        for (var i = 0; i < root.hourlyForecast.length; i++) {
            var item = cloneMap(root.hourlyForecast[i]);
            if (validNumber(item.temperatureC))
                item.temperatureC = convertTemp(item.temperatureC);
            out.push(item);
        }
        return out;
    }

    // --- Section 2: 内联小组件 ---
    component IconButton: Rectangle {
        id: button

        property string iconCode: ""
        property string tooltip: ""
        property bool busy: false

        signal activated()

        Layout.preferredWidth: 34
        Layout.preferredHeight: 34
        radius: 12
        color: enabled ? (buttonMouse.containsMouse ? root.buttonHover : root.buttonFill) : "transparent"
        border.color: enabled ? root.cardStroke : "transparent"
        border.width: 1
        opacity: enabled ? 1 : 0.55

        Text {
            anchors.centerIn: parent
            text: button.busy ? "\ue863" : button.iconCode // sync
            color: root.textPrimary
            font.family: root.iconFont
            font.pixelSize: 18
            rotation: button.busy ? 360 : 0

            Behavior on rotation {
                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
            }
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

    component InfoPill: Rectangle {
        id: pill

        property string iconCode: ""
        property string label: ""
        property string value: "--"

        height: 42
        radius: 14
        color: root.cardFill

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.cardStroke
            border.width: 1
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 7

            Text {
                text: pill.iconCode
                color: root.accentBlue
                font.family: root.iconFont
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
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

    component StatusBanner: Rectangle {
        id: banner

        property string iconCode: ""
        property string title: ""
        property string message: ""
        property color accent: root.warning

        height: 58
        radius: 16
        color: Qt.rgba(accent.r, accent.g, accent.b, root.darkMode ? 0.16 : 0.12)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: Qt.rgba(banner.accent.r, banner.accent.g, banner.accent.b, 0.42)
            border.width: 1
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            spacing: 10

            Text {
                text: banner.iconCode
                color: banner.accent
                font.family: root.iconFont
                font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter
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

            SequentialAnimation on x {
                running: stripe.visible
                loops: Animation.Infinite
                NumberAnimation { from: -stripe.width * 0.36; to: stripe.width; duration: 1100; easing.type: Easing.InOutCubic }
            }
        }
    }
}
