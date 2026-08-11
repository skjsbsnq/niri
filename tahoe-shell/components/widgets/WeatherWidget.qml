pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../WeatherCodes.js" as WeatherCodes

// 天气小部件（medium 4×2）—— macOS 风格当前天气 + 逐时条。
// 数据源：services/Weather.qml（磁盘缓存 + 10 分钟定时，只读注入）。
// 遵守 A-C3：本组件不建任何 Timer / 不 spawn 进程；刷新门控于
// dataRefreshActive（宿主可见且非 previewMode）：宿主隐藏时锁存快照，
// 显示不再随服务事件变化（A5 库预览依赖同一语义）。
Widget {
    id: root

    property var weatherService

    // ---- 实时值（live = dataRefreshActive；_live* 只依赖服务可用性，
    // 使 live→false 时锁存仍可取到最后值，见 BatteryWidget 同款模式）----
    readonly property bool _svcAvailable: !!root.weatherService
    readonly property bool _liveHasData: root._svcAvailable
        && (!!root.weatherService.locationDetected
            || (Array.isArray(root.weatherService.dailyForecast) && root.weatherService.dailyForecast.length > 0)
            || (Array.isArray(root.weatherService.hourlyForecast) && root.weatherService.hourlyForecast.length > 0))

    readonly property string _liveLocation: root._svcAvailable ? String(root.weatherService.locationName || "").trim() : ""
    readonly property real _liveTempC: root._liveHasData ? finiteNumber(root.weatherService.currentTemperatureC, NaN) : NaN
    readonly property int _liveCode: root._liveHasData ? Math.round(finiteNumber(root.weatherService.currentWeatherCode, -1)) : -1
    readonly property bool _liveIsDay: root._liveHasData ? root.weatherService.currentIsDay !== false : true
    readonly property string _liveText: root._liveHasData ? String(root.weatherService.currentWeatherText || "").trim() : ""
    readonly property var _liveDaily: root._liveHasData ? root.weatherService.dailyForecast : []
    readonly property var _liveToday: root._liveHasData ? root.todayDaily(root._liveDaily) : ({})
    readonly property real _liveHighC: root._liveHasData ? finiteNumber(root._liveToday.temperatureMaxC, NaN) : NaN
    readonly property real _liveLowC: root._liveHasData ? finiteNumber(root._liveToday.temperatureMinC, NaN) : NaN
    readonly property var _liveHourly: root._liveHasData ? root.hourlySlice(root.weatherService.hourlyForecast) : []

    // 预览/隐藏快照：进入非 live 时锁存一次（含数组复制，防服务整体替换
    // 数组后快照跟随变化）。
    property bool _snapHasData: false
    property string _snapLocation: ""
    property real _snapTempC: NaN
    property int _snapCode: -1
    property bool _snapIsDay: true
    property string _snapText: ""
    property real _snapHighC: NaN
    property real _snapLowC: NaN
    property var _snapHourly: []

    function latchSnapshot() {
        root._snapHasData = root._liveHasData;
        root._snapLocation = root._liveLocation;
        root._snapTempC = root._liveTempC;
        root._snapCode = root._liveCode;
        root._snapIsDay = root._liveIsDay;
        root._snapText = root._liveText;
        root._snapHighC = root._liveHighC;
        root._snapLowC = root._liveLowC;
        root._snapHourly = root._liveHourly.slice(0, 5);
    }

    readonly property bool live: root.dataRefreshActive
    onLiveChanged: {
        if (!root.live)
            root.latchSnapshot();
    }
    Component.onCompleted: {
        if (!root.live)
            root.latchSnapshot();
    }

    // ---- 对外显示值（单一分支：live ? 实时 : 快照）----
    readonly property bool hasData: root.live ? root._liveHasData : root._snapHasData
    readonly property string locationName: root.live ? root._liveLocation : root._snapLocation
    readonly property real currentTempC: root.live ? root._liveTempC : root._snapTempC
    readonly property int currentCode: root.live ? root._liveCode : root._snapCode
    readonly property bool currentIsDay: root.live ? root._liveIsDay : root._snapIsDay
    readonly property string currentText: root.live ? root._liveText : root._snapText
    readonly property real currentHighC: root.live ? root._liveHighC : root._snapHighC
    readonly property real currentLowC: root.live ? root._liveLowC : root._snapLowC
    readonly property var hourlyModel: root.live ? root._liveHourly : root._snapHourly

    // ---- 纯函数辅助 ----
    function finiteNumber(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function tempUnit() {
        var svc = root.weatherService || {};
        var settings = svc.settingsService || {};
        var unit = String(settings.weatherTempUnit || "c").toLowerCase();
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
        // false → 纯数字（供大数字 + 独立单位 Text 组合，避免 °°C 双度号）；
        // true → 带单位（"24°C"）。
        return Math.round(n) + (includeUnit ? (tempUnit() === "f" ? "°F" : "°C") : "");
    }

    function fmtHour(epoch) {
        var n = Number(epoch);
        return isFinite(n) && n > 0 ? Qt.formatDateTime(new Date(n * 1000), "hh:00") : "--";
    }

    // 今日条目：取时间 >= 今日零点的第一条（Open-Meteo 从今天开始）。
    // 找不到（如过期缓存跨日）返回空 → 高低温行隐藏，不显示昨日数据。
    function todayDaily(list) {
        var arr = Array.isArray(list) ? list : [];
        if (arr.length === 0)
            return {};
        var now = new Date();
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000;
        for (var i = 0; i < arr.length; i++) {
            var t = Number(arr[i] && arr[i].time || 0);
            if (isFinite(t) && t >= todayStart)
                return arr[i] || {};
        }
        return {};
    }

    // 逐时条：从最近半小时内开始，最多 5 格。
    function hourlySlice(list) {
        var arr = Array.isArray(list) ? list : [];
        if (arr.length === 0)
            return [];
        var nowSeconds = Math.floor(Date.now() / 1000);
        var start = 0;
        for (var i = 0; i < arr.length; i++) {
            var t = Number(arr[i] && arr[i].time || 0);
            if (isFinite(t) && t >= nowSeconds - 1800) {
                start = i;
                break;
            }
        }
        return arr.slice(start, start + 5);
    }

    // ---- 视觉（照 macOS 天气小部件：左当前天气 + 右大图标 + 底部逐时条）----
    // 部署反馈：44px 大字 + 52px 逐时条在小部件 2 行高度里放不下，顶部
    // Column 溢出并把「今日 x° ~ y°」压进/贴上逐时条。修复：收窄外边距、
    // 逐时条降到 50px、当前温度字号降到 34 并给各文本显式高度，使内容
    // 总高（≈85px）稳定小于 topArea 可用高；topArea 再设 clip 兜底，极端
    // 矮屏只裁切不重叠。
    readonly property color textPrimary: "#ffffff"
    readonly property color textSecondary: "#c7ffffff"
    readonly property color textSoft: "#8affffff"
    readonly property real hourlyH: 50
    // 外边距（内容区四周留白；与 Calendar/SystemMonitor 的 12 相比略窄，
    // 因为本组件还有逐时条要容纳）。单处定义供布局与测试使用。
    readonly property real contentMargin: 10
    // 顶部可用高：实例高 - 上下边距 - 逐时条 - 与逐时条的固定间隙。
    readonly property real topAreaH: Math.max(0, root.height - 2 * root.contentMargin - root.hourlyH - 4)
    // 固定行（位置 14 + 描述 14 + 今日 13 + spacing 2×3 = 47）之外的
    // 余量给当前温度行：矮屏收缩（最小 26）、高屏封顶 38。这样逻辑高
    // 720–1600 全范围 Column 总高 = fixedRowsH + tempRowH ≤ topAreaH
    // （审查 C1/C2：1366×768 与 761/762 边界不再把「今日」行裁掉）。
    readonly property real fixedRowsH: 14 + 14 + 13 + 2 * 3
    readonly property real tempRowMinH: 26
    readonly property real tempRowMaxH: 38
    readonly property real tempRowH: Math.max(root.tempRowMinH, Math.min(root.tempRowMaxH, root.topAreaH - root.fixedRowsH))

    Item {
        anchors.fill: parent
        anchors.margins: root.contentMargin

        // 顶部：当前天气。
        Item {
            id: topArea

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.topAreaH
            clip: true

            MeteoIcon {
                id: weatherIcon

                anchors.right: parent.right
                anchors.top: parent.top
                width: 44
                height: 44
                weatherCode: root.hasData ? root.currentCode : -1
                night: !root.currentIsDay
                color: root.textPrimary
                settingsService: root.weatherService ? root.weatherService.settingsService : null
            }

            Column {
                anchors.left: parent.left
                anchors.right: weatherIcon.left
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 2

                Text {
                    width: parent.width
                    height: 14
                    verticalAlignment: Text.AlignVCenter
                    text: root.hasData && root.locationName.length > 0 ? root.locationName : "--"
                    color: root.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Row {
                    height: root.tempRowH
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fmtTemp(root.currentTempC, false)
                        color: root.textPrimary
                        // 字号跟随温度行高度（行高 - 4 的下界），矮屏自动缩小。
                        font.pixelSize: Math.min(34, Math.max(24, root.tempRowH - 4))
                        font.weight: Font.Light
                        lineHeight: 0.9
                    }
                    Text {
                        text: root.tempUnit() === "f" ? "°F" : "°C"
                        color: root.textSecondary
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                    }
                }

                Text {
                    width: parent.width
                    height: 14
                    verticalAlignment: Text.AlignVCenter
                    text: root.hasData ? root.currentText : (root.weatherService && root.weatherService.updating ? "正在获取天气" : "暂无天气")
                    color: root.textPrimary
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    height: 13
                    verticalAlignment: Text.AlignVCenter
                    text: {
                        if (!root.hasData)
                            return "";
                        var has = isFinite(root.currentLowC) && isFinite(root.currentHighC);
                        if (!has)
                            return "";
                        return "今日 " + root.fmtTemp(root.currentLowC, false) + "° ~ " + root.fmtTemp(root.currentHighC, false) + "°";
                    }
                    color: root.textSoft
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }

        // 底部：逐时条（最多 5 格）。
        Row {
            id: hourlyRow

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.hourlyH
            visible: root.hourlyModel.length > 0

            Repeater {
                id: hourlyRepeater
                model: root.hourlyModel

                delegate: Column {
                    required property var modelData

                    width: hourlyRow.width / Math.max(1, hourlyRepeater.count)
                    height: parent.height
                    spacing: 3

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fmtHour(modelData.time)
                        color: root.textSecondary
                        font.pixelSize: 10
                    }

                    TahoeSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: WeatherCodes.materialIcon(Number(modelData.weatherCode), modelData.isDay === false)
                        color: root.textPrimary
                        size: 18
                        asynchronous: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fmtTemp(Number(modelData.temperatureC), false)
                        color: root.textPrimary
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
