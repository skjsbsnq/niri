pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// LS12: 天气设置页。
//
// 职责：管理天气服务的自动定位、手动坐标覆盖和温度单位。持久化只走
// DesktopSettings 的 setter；立即更新天气只通过 Weather 服务 API 触发。
Flickable {
    id: page

    property var panel
    property var theme
    readonly property var settings: panel ? panel.settingsService : null
    readonly property var weather: panel ? panel.weatherService : null
    readonly property bool ready: !!settings
    readonly property bool automaticLocation: settings ? !settings.weatherManualOverride : true
    readonly property string statusText: weather ? String(weather.status || "idle") : "idle"
    property bool detectForManual: false
    property string validationMessage: ""

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Connections {
        target: page.weather

        function onRefreshed() {
            if (!page.detectForManual)
                return;

            page.detectForManual = false;
            if (page.weather && page.settings && page.validLocation(page.weather.latitude, page.weather.longitude)) {
                page.settings.setWeatherLocation(page.weather.latitude, page.weather.longitude, page.cleanName(page.weather.locationName, "当前位置"));
                page.validationMessage = "已填入当前定位";
            }
        }

        function onFailed(message) {
            if (page.detectForManual) {
                page.detectForManual = false;
                page.validationMessage = String(message || "定位失败");
            }
        }
    }

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function cleanName(value, fallback) {
        var text = String(value === undefined || value === null ? "" : value).trim();
        return text.length > 0 ? text : fallback;
    }

    function validLocation(lat, lon) {
        var latitude = Number(lat);
        var longitude = Number(lon);
        return isFinite(latitude) && latitude >= -90 && latitude <= 90
            && isFinite(longitude) && longitude >= -180 && longitude <= 180;
    }

    function coordText(value) {
        var number = Number(value);
        return isFinite(number) ? number.toFixed(6) : "";
    }

    function displayedLatitude() {
        if (automaticLocation && weather && weather.locationDetected)
            return coordText(weather.latitude);
        return settings ? coordText(settings.weatherLatitude) : "";
    }

    function displayedLongitude() {
        if (automaticLocation && weather && weather.locationDetected)
            return coordText(weather.longitude);
        return settings ? coordText(settings.weatherLongitude) : "";
    }

    function displayedLocationName() {
        if (automaticLocation && weather && weather.locationDetected)
            return cleanName(weather.locationName, "");
        return settings ? cleanName(settings.weatherLocationName, "") : "";
    }

    function currentLocationDetail() {
        if (!weather)
            return "天气服务不可用";
        if (!weather.locationDetected)
            return weather.updating ? "正在定位" : "尚未取得定位";
        return cleanName(weather.locationName, "当前位置") + " · "
            + coordText(weather.latitude) + ", " + coordText(weather.longitude);
    }

    function statusLabel() {
        if (!weather)
            return "不可用";
        if (weather.updating)
            return "更新中";
        if (statusText === "fresh")
            return "已更新";
        if (statusText === "stale")
            return "显示缓存";
        if (statusText === "error")
            return "更新失败";
        return "等待更新";
    }

    function applyManualLocation() {
        if (!settings) {
            validationMessage = "设置服务不可用";
            return false;
        }

        var lat = numberOr(latitudeInput.text, NaN);
        var lon = numberOr(longitudeInput.text, NaN);
        if (!validLocation(lat, lon)) {
            validationMessage = "坐标无效";
            return false;
        }

        var name = cleanName(locationNameInput.text, "手动位置");
        validationMessage = "";
        if (weather && typeof weather.setLocation === "function")
            weather.setLocation(lat, lon, name);
        else
            settings.setWeatherLocation(lat, lon, name);
        return true;
    }

    function setAutomaticLocation(enabled) {
        if (!settings)
            return;

        if (enabled) {
            validationMessage = "";
            if (weather && typeof weather.clearManualOverride === "function")
                weather.clearManualOverride();
            else
                settings.clearWeatherLocation();
            return;
        }

        var lat = numberOr(latitudeInput.text, NaN);
        var lon = numberOr(longitudeInput.text, NaN);
        var name = cleanName(locationNameInput.text, "");
        if (!validLocation(lat, lon) && weather && weather.locationDetected) {
            lat = numberOr(weather.latitude, 0);
            lon = numberOr(weather.longitude, 0);
            name = cleanName(weather.locationName, "手动位置");
        }
        if (!validLocation(lat, lon)) {
            lat = 0;
            lon = 0;
        }
        if (name.length === 0)
            name = "手动位置";

        validationMessage = "";
        if (weather && typeof weather.setLocation === "function")
            weather.setLocation(lat, lon, name);
        else
            settings.setWeatherLocation(lat, lon, name);
    }

    function detectLocationNow() {
        if (!weather || typeof weather.detectLocation !== "function") {
            validationMessage = "天气服务不可用";
            return;
        }

        validationMessage = "";
        detectForManual = !automaticLocation;
        weather.detectLocation();
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "定位"
            subtitle: "自动 IP 定位，或使用手动坐标覆盖"

            Controls.TahoeListRow {
                theme: page.theme
                label: "自动定位"
                detail: page.automaticLocation ? "使用 IP 定位刷新天气" : "使用下方手动坐标"
                iconCode: "\ue55f" // location_on
                checkable: true
                checked: page.automaticLocation
                enabled: page.ready
                onToggled: function(checked) {
                    page.setAutomaticLocation(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "当前定位"
                detail: page.currentLocationDetail()
                iconCode: "\ue0c8" // place

                Controls.TahoeButton {
                    theme: page.theme
                    iconCode: "\ue55c" // my_location
                    label: page.weather && page.weather.updating ? "检测中" : "立即检测"
                    enabled: !!page.weather && !page.weather.updating
                    onActivated: page.detectLocationNow()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "纬度"
                detail: "范围 -90 到 90"
                iconCode: "\ue55e" // explore_nearby
                enabled: page.ready && !page.automaticLocation
                opacity: enabled ? 1 : 0.52

                Controls.TahoeTextField {
                    id: latitudeInput
                    theme: page.theme
                    Layout.preferredWidth: Math.max(160, Math.min(220, page.width - 280))
                    text: page.displayedLatitude()
                    enabled: page.ready && !page.automaticLocation
                    onEditingFinished: page.applyManualLocation()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "经度"
                detail: "范围 -180 到 180"
                iconCode: "\ue55e" // explore_nearby
                enabled: page.ready && !page.automaticLocation
                opacity: enabled ? 1 : 0.52

                Controls.TahoeTextField {
                    id: longitudeInput
                    theme: page.theme
                    Layout.preferredWidth: Math.max(160, Math.min(220, page.width - 280))
                    text: page.displayedLongitude()
                    enabled: page.ready && !page.automaticLocation
                    onEditingFinished: page.applyManualLocation()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "城市"
                detail: page.validationMessage.length > 0 ? page.validationMessage : "用于侧边栏天气位置名"
                iconCode: "\ue7f1" // location_city
                enabled: page.ready && !page.automaticLocation
                opacity: enabled ? 1 : 0.52

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 360

                    Controls.TahoeTextField {
                        id: locationNameInput
                        theme: page.theme
                        Layout.preferredWidth: Math.max(150, Math.min(220, page.width - 360))
                        text: page.displayedLocationName()
                        enabled: page.ready && !page.automaticLocation
                        onEditingFinished: page.applyManualLocation()
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: page.ready && !page.automaticLocation
                        onActivated: page.applyManualLocation()
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "显示"
            subtitle: "天气页温度单位"

            Controls.TahoeListRow {
                theme: page.theme
                label: "温度单位"
                detail: page.settings && page.settings.weatherTempUnit === "f" ? "华氏度" : "摄氏度"
                iconCode: "\ue1b1" // device_thermostat
                enabled: page.ready

                Controls.TahoeSegmented {
                    theme: page.theme
                    Layout.preferredWidth: 180
                    value: page.settings ? page.settings.weatherTempUnit : "c"
                    model: [
                        { value: "c", label: "°C" },
                        { value: "f", label: "°F" }
                    ]
                    onSelected: function(value) {
                        if (page.settings)
                            page.settings.setWeatherTempUnit(value);
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "更新状态"
                detail: page.weather && page.weather.lastError.length > 0
                    ? page.weather.lastError
                    : page.statusLabel()
                iconCode: page.statusText === "error" ? "\ue001" : "\ue86a"
            }
        }
    }
}
