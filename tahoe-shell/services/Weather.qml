pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../components/WeatherCodes.js" as WeatherCodes

// 左侧边栏天气页的数据服务。
//
// 负责 IP 定位、Open-Meteo 预报/空气质量取数、缓存和最小状态机。
// 这里不承担任何界面职责；视图只读取已整理好的 current/daily/hourly/air 数据。
Item {
    id: root
    visible: false

    readonly property string cachePath: Quickshell.stateDir + "/weather-cache.json"
    readonly property int refreshIntervalMs: 10 * 60 * 1000
    readonly property int curlTimeoutSeconds: 8
    readonly property int dailyLimit: 16
    readonly property int hourlyLimit: 48

    property var settingsService: null
    property string status: "idle" // idle/fresh/stale/error
    property bool updating: false
    property string lastError: ""
    property string updatedAt: ""
    property real latitude: 0
    property real longitude: 0
    property string locationName: ""
    property bool locationDetected: false

    property int currentWeatherCode: -1
    property string currentWeatherText: WeatherCodes.text(-1)
    property string currentWeatherSlug: WeatherCodes.slug(-1, false)
    property real currentTemperatureC: 0
    property real currentApparentTemperatureC: 0
    property real currentWindSpeedMs: 0
    property real currentWindDirectionDeg: 0
    property real currentWindGustMs: 0
    property real currentUvIndex: 0
    property real currentHumidity: 0
    property real currentDewPointC: 0
    property real currentPressureHpa: 0
    property real currentCloudCover: 0
    property real currentVisibilityM: 0
    property real currentPrecipitationMm: 0
    property bool currentIsDay: true

    property var dailyForecast: []
    property var hourlyForecast: []
    property var currentAirQuality: ({})
    property var airQualityHourly: []

    property bool pendingRefresh: false
    property real pendingLatitude: 0
    property real pendingLongitude: 0
    property string pendingLocationName: ""
    property bool forecastDone: false
    property bool airDone: false
    property int forecastExitCode: -1
    property int airExitCode: -1
    property string locationRequestMode: "refresh"

    // 城市地理编码搜索（Open-Meteo Geocoding，支持中文城市名）。
    property var locationSearchResults: []
    property string locationSearchQuery: ""
    property bool locationSearching: false
    property string locationSearchError: ""
    // Single geocode Process pipeline: generation isolates late success/error/cancel.
    // geocodeGeneration is the latest search intent; only matching finishes may write
    // locationSearching/results/error/signals. Pending holds only the newest query
    // while an older curl is still exiting — not a second Process or debounce path.
    property int geocodeGeneration: 0
    property int geocodeInFlightGeneration: 0
    property string geocodeInFlightQuery: ""
    property bool geocodePending: false
    property string geocodePendingQuery: ""

    signal refreshed()
    signal failed(string message)
    signal locationSearchFinished()
    signal locationSearchFailed(string message)

    Component.onCompleted: {
        root.loadCache(false);
        root.refresh();
        refreshTimer.start();
    }

    function settingValue(name, fallback) {
        if (!settingsService)
            return fallback;

        try {
            var value = settingsService[name];
            return value === undefined || value === null ? fallback : value;
        } catch (e) {
            return fallback;
        }
    }

    function manualOverrideEnabled() {
        return !!settingValue("weatherManualOverride", false);
    }

    function manualLatitude() {
        return numberValue(settingValue("weatherLatitude", NaN), NaN);
    }

    function manualLongitude() {
        return numberValue(settingValue("weatherLongitude", NaN), NaN);
    }

    function manualLocationName() {
        return cleanText(settingValue("weatherLocationName", ""), "");
    }

    function validLatitude(value) {
        return isFinite(value) && value >= -90 && value <= 90;
    }

    function validLongitude(value) {
        return isFinite(value) && value >= -180 && value <= 180;
    }

    function canUseLocation(lat, lon) {
        return validLatitude(lat) && validLongitude(lon);
    }

    function numberValue(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function intValue(value, fallback) {
        var n = Math.round(numberValue(value, fallback));
        return isFinite(n) ? n : fallback;
    }

    function cleanText(value, fallback) {
        var text = String(value === undefined || value === null ? "" : value).trim();
        return text.length > 0 ? text : fallback;
    }

    function isoNow() {
        return new Date().toISOString();
    }

    function compactLocationName(city, region, country) {
        var parts = [];
        var cityText = cleanText(city, "");
        var regionText = cleanText(region, "");
        var countryText = cleanText(country, "");
        if (cityText.length > 0)
            parts.push(cityText);
        if (regionText.length > 0 && regionText !== cityText)
            parts.push(regionText);
        if (countryText.length > 0)
            parts.push(countryText);
        return parts.length > 0 ? parts.join(" · ") : "当前位置";
    }

    function queryString(params) {
        var parts = [];
        var keys = Object.keys(params);
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            var value = params[key];
            if (value === undefined || value === null)
                continue;
            parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
        }
        return parts.join("&");
    }

    function forecastUrl(lat, lon) {
        return "https://api.open-meteo.com/v1/forecast?" + queryString({
            "latitude": lat.toFixed(6),
            "longitude": lon.toFixed(6),
            "timezone": "auto",
            "timeformat": "unixtime",
            "models": "best_match",
            "forecast_days": 16,
            "past_days": 1,
            "windspeed_unit": "ms",
            "current": [
                "temperature_2m",
                "apparent_temperature",
                "weather_code",
                "wind_speed_10m",
                "wind_direction_10m",
                "wind_gusts_10m",
                "uv_index",
                "relative_humidity_2m",
                "dew_point_2m",
                "pressure_msl",
                "cloud_cover",
                "visibility",
                "is_day",
                "precipitation"
            ].join(","),
            "hourly": [
                "temperature_2m",
                "apparent_temperature",
                "precipitation_probability",
                "precipitation",
                "weather_code",
                "wind_speed_10m",
                "wind_direction_10m",
                "wind_gusts_10m",
                "uv_index",
                "is_day",
                "relative_humidity_2m",
                "dew_point_2m",
                "pressure_msl",
                "cloud_cover",
                "visibility"
            ].join(","),
            "daily": [
                "weather_code",
                "temperature_2m_max",
                "temperature_2m_min",
                "apparent_temperature_max",
                "apparent_temperature_min",
                "sunrise",
                "sunset",
                "sunshine_duration",
                "uv_index_max",
                "precipitation_probability_max",
                "precipitation_sum",
                "relative_humidity_2m_mean",
                "dew_point_2m_mean",
                "pressure_msl_mean",
                "cloud_cover_mean",
                "visibility_mean",
                "wind_speed_10m_max",
                "wind_gusts_10m_max",
                "wind_direction_10m_dominant"
            ].join(",")
        });
    }

    function airQualityUrl(lat, lon) {
        return "https://air-quality-api.open-meteo.com/v1/air-quality?" + queryString({
            "latitude": lat.toFixed(6),
            "longitude": lon.toFixed(6),
            "timezone": "auto",
            "timeformat": "unixtime",
            "forecast_days": 7,
            "past_days": 1,
            "hourly": [
                "pm10",
                "pm2_5",
                "carbon_monoxide",
                "nitrogen_dioxide",
                "sulphur_dioxide",
                "ozone",
                "alder_pollen",
                "birch_pollen",
                "grass_pollen",
                "mugwort_pollen",
                "olive_pollen",
                "ragweed_pollen"
            ].join(",")
        });
    }

    function geocodeUrl(name) {
        return "https://geocoding-api.open-meteo.com/v1/search?" + queryString({
            "name": name,
            "count": 12,
            "language": "zh",
            "format": "json"
        });
    }

    function curlCommand(url) {
        return ["curl", "-fsS", "--max-time", String(curlTimeoutSeconds), String(url)];
    }

    function formatGeocodeDisplayName(item) {
        if (!item)
            return "未知位置";
        return compactLocationName(item.name, item.admin1 || item.admin2 || "", item.country || "");
    }

    function normalizeGeocodeResults(payload) {
        var rows = payload && Array.isArray(payload.results) ? payload.results : [];
        var result = [];
        for (var i = 0; i < rows.length; i++) {
            var item = rows[i] || {};
            var lat = numberValue(item.latitude, NaN);
            var lon = numberValue(item.longitude, NaN);
            if (!canUseLocation(lat, lon))
                continue;
            var name = cleanText(item.name, "");
            if (name.length === 0)
                continue;
            result.push({
                "id": cleanText(item.id, String(i)),
                "name": name,
                "latitude": lat,
                "longitude": lon,
                "country": cleanText(item.country, ""),
                "countryCode": cleanText(item.country_code, ""),
                "admin1": cleanText(item.admin1, ""),
                "admin2": cleanText(item.admin2, ""),
                "timezone": cleanText(item.timezone, ""),
                "population": numberValue(item.population, 0),
                "displayName": formatGeocodeDisplayName(item)
            });
        }
        // 中国结果优先，其次按人口降序，便于中文城市搜索命中。
        result.sort(function(a, b) {
            var aCn = String(a.countryCode || "").toUpperCase() === "CN" ? 1 : 0;
            var bCn = String(b.countryCode || "").toUpperCase() === "CN" ? 1 : 0;
            if (aCn !== bCn)
                return bCn - aCn;
            return numberValue(b.population, 0) - numberValue(a.population, 0);
        });
        return result;
    }

    function clearLocationSearch() {
        // Invalidate any in-flight curl so its late exit cannot clear a later search.
        root.geocodeGeneration += 1;
        root.geocodePending = false;
        root.geocodePendingQuery = "";
        if (geocodeProcess.running)
            geocodeProcess.running = false;
        root.locationSearchResults = [];
        root.locationSearchQuery = "";
        root.locationSearchError = "";
        root.locationSearching = false;
    }

    function geocodeIdentityMatches(generation) {
        if (generation === undefined || generation === null)
            return false;
        return Number(generation) === Number(root.geocodeGeneration);
    }

    function searchLocations(query) {
        var name = cleanText(query, "");
        if (name.length === 0) {
            root.geocodeGeneration += 1;
            root.geocodePending = false;
            root.geocodePendingQuery = "";
            if (geocodeProcess.running)
                geocodeProcess.running = false;
            root.locationSearchResults = [];
            root.locationSearchQuery = "";
            root.locationSearchError = "请输入城市名";
            root.locationSearching = false;
            root.locationSearchFailed(root.locationSearchError);
            return;
        }

        // Always advance generation for a new intent. Never compare only query text:
        // two identical queries in a row still need isolated success/error/cancel.
        root.geocodeGeneration += 1;
        root.locationSearching = true;
        root.locationSearchQuery = name;
        root.locationSearchError = "";

        if (geocodeProcess.running) {
            // Keep only the newest pending query; stop the old curl so exit settles
            // and schedulePendingGeocode starts this generation after onExited.
            root.geocodePending = true;
            root.geocodePendingQuery = name;
            geocodeProcess.running = false;
            return;
        }

        root.startGeocode(root.geocodeGeneration, name);
    }

    function startGeocode(generation, query) {
        // Never start a superseded generation; keep pending so a later exit can re-run latest.
        if (!root.geocodeIdentityMatches(generation))
            return;
        if (String(query || "").length === 0)
            return;
        if (geocodeProcess.running) {
            root.geocodePending = true;
            root.geocodePendingQuery = String(query || "");
            return;
        }

        root.geocodePending = false;
        root.geocodePendingQuery = "";
        root.geocodeInFlightGeneration = generation;
        root.geocodeInFlightQuery = String(query || "");
        // Freeze command args at start so a later searchLocations cannot rebind mid-flight.
        geocodeProcess.command = root.curlCommand(root.geocodeUrl(root.geocodeInFlightQuery));
        root.locationSearching = true;
        root.locationSearchQuery = root.geocodeInFlightQuery;
        root.locationSearchError = "";
        geocodeProcess.running = true;
        if (!geocodeProcess.running) {
            // Failed to start: finish with the frozen generation so loading cannot stick.
            root.finishGeocodeRequest(1, "", generation);
        }
    }

    function schedulePendingGeocode() {
        // Defer restart until after Process exit handling settles.
        Qt.callLater(function() {
            if (!root.geocodePending)
                return;
            if (geocodeProcess.running)
                return;
            var query = root.geocodePendingQuery;
            root.geocodePending = false;
            root.geocodePendingQuery = "";
            root.startGeocode(root.geocodeGeneration, query);
        });
    }

    function selectSearchResult(index) {
        var rows = root.locationSearchResults || [];
        var i = intValue(index, -1);
        if (i < 0 || i >= rows.length) {
            root.locationSearchError = "无效的搜索结果";
            root.locationSearchFailed(root.locationSearchError);
            return false;
        }

        var item = rows[i] || {};
        var lat = numberValue(item.latitude, NaN);
        var lon = numberValue(item.longitude, NaN);
        if (!canUseLocation(lat, lon)) {
            root.locationSearchError = "搜索结果坐标无效";
            root.locationSearchFailed(root.locationSearchError);
            return false;
        }

        var name = cleanText(item.displayName, cleanText(item.name, "手动位置"));
        root.clearLocationSearch();
        root.setLocation(lat, lon, name);
        return true;
    }

    function finishGeocodeRequest(code, text, generation) {
        // Generation is mandatory: missing, already-consumed, or stale never write search state.
        // onExited freezes the in-flight generation before any pending restart can overwrite it.
        if (generation === undefined || generation === null) {
            root.schedulePendingGeocode();
            return;
        }
        var gen = generation;

        // Must still own the in-flight slot (rejects double onExited and foreign finishes).
        if (Number(gen) !== Number(root.geocodeInFlightGeneration)) {
            root.schedulePendingGeocode();
            return;
        }

        // Consume in-flight identity before latest-generation gate so a deferred
        // pending start cannot be attributed to this exit.
        root.geocodeInFlightGeneration = 0;
        root.geocodeInFlightQuery = "";

        if (!root.geocodeIdentityMatches(gen)) {
            root.schedulePendingGeocode();
            return;
        }

        root.locationSearching = false;

        if (code !== 0) {
            root.locationSearchResults = [];
            root.locationSearchError = "城市搜索失败";
            root.locationSearchFailed(root.locationSearchError);
            root.schedulePendingGeocode();
            return;
        }

        try {
            var payload = JSON.parse(String(text || ""));
            var results = root.normalizeGeocodeResults(payload);
            root.locationSearchResults = results;
            if (results.length === 0) {
                root.locationSearchError = "未找到匹配城市，可尝试拼音或更完整地名";
                root.locationSearchFailed(root.locationSearchError);
                root.schedulePendingGeocode();
                return;
            }
            root.locationSearchError = "";
            root.locationSearchFinished();
        } catch (e) {
            root.locationSearchResults = [];
            root.locationSearchError = "城市搜索解析失败";
            root.locationSearchFailed(root.locationSearchError);
        }

        root.schedulePendingGeocode();
    }

    function refresh() {
        if (root.updating) {
            root.pendingRefresh = true;
            return;
        }

        var lat = manualLatitude();
        var lon = manualLongitude();
        if (manualOverrideEnabled() && canUseLocation(lat, lon)) {
            root.startWeatherFetch(lat, lon, manualLocationName() || "手动位置");
            return;
        }

        root.detectLocation();
    }

    function detectLocation() {
        if (root.updating) {
            root.pendingRefresh = true;
            return;
        }

        root.updating = true;
        root.locationRequestMode = "refresh";
        root.lastError = "";
        locationProcess.running = true;
    }

    function setLocation(lat, lon, name) {
        var nextLat = numberValue(lat, NaN);
        var nextLon = numberValue(lon, NaN);
        if (!canUseLocation(nextLat, nextLon)) {
            root.failWithCache("无效的天气坐标");
            return;
        }

        if (settingsService && typeof settingsService.setWeatherLocation === "function")
            settingsService.setWeatherLocation(nextLat, nextLon, cleanText(name, "手动位置"));

        root.startWeatherFetch(nextLat, nextLon, cleanText(name, "手动位置"));
    }

    function clearManualOverride() {
        if (settingsService && typeof settingsService.clearWeatherLocation === "function")
            settingsService.clearWeatherLocation();
        root.refresh();
    }

    function startWeatherFetch(lat, lon, name) {
        if (forecastProcess.running || airProcess.running) {
            root.pendingRefresh = true;
            return;
        }

        root.updating = true;
        root.lastError = "";
        root.pendingLatitude = lat;
        root.pendingLongitude = lon;
        root.pendingLocationName = cleanText(name, "当前位置");
        root.forecastDone = false;
        root.airDone = false;
        root.forecastExitCode = -1;
        root.airExitCode = -1;
        forecastProcess.command = curlCommand(forecastUrl(lat, lon));
        airProcess.command = curlCommand(airQualityUrl(lat, lon));
        forecastProcess.running = true;
        airProcess.running = true;
    }

    function finishLocationRequest(code, text) {
        if (code !== 0) {
            root.failWithCache("定位失败");
            return;
        }

        try {
            var payload = JSON.parse(String(text || ""));
            if (!payload || payload.success === false)
                throw new Error("定位服务返回失败");

            var lat = numberValue(payload.latitude, NaN);
            var lon = numberValue(payload.longitude, NaN);
            if (!canUseLocation(lat, lon))
                throw new Error("定位坐标无效");

            root.startWeatherFetch(lat, lon, compactLocationName(payload.city, payload.region, payload.country));
        } catch (e) {
            root.failWithCache("定位解析失败");
        }
    }

    function finishForecast(code) {
        root.forecastExitCode = code;
        root.forecastDone = true;
        root.finishWeatherIfReady();
    }

    function finishAir(code) {
        root.airExitCode = code;
        root.airDone = true;
        root.finishWeatherIfReady();
    }

    function finishWeatherIfReady() {
        if (!root.forecastDone || !root.airDone)
            return;

        root.updating = false;

        if (root.forecastExitCode !== 0) {
            root.failWithCache("天气更新失败");
            root.maybeRunPendingRefresh();
            return;
        }

        try {
            var forecast = JSON.parse(String(forecastOut.text || ""));
            var air = root.airExitCode === 0 ? JSON.parse(String(airOut.text || "")) : null;
            root.applyWeatherPayload(forecast, air, root.pendingLatitude, root.pendingLongitude, root.pendingLocationName, false);
            if (root.airExitCode !== 0)
                root.lastError = "空气质量更新失败";
            root.saveCache();
            root.refreshed();
        } catch (e) {
            root.failWithCache("天气解析失败");
        }

        root.maybeRunPendingRefresh();
    }

    function maybeRunPendingRefresh() {
        if (!root.pendingRefresh)
            return;

        root.pendingRefresh = false;
        refreshDelay.restart();
    }

    function failWithCache(message) {
        var loaded = root.loadCache(true);
        root.updating = false;
        root.status = loaded ? "stale" : "error";
        root.lastError = message;
        root.failed(message);
        root.maybeRunPendingRefresh();
    }

    function valueAt(table, key, index, fallback) {
        if (!table || !table[key] || index < 0 || index >= table[key].length)
            return fallback;
        return numberValue(table[key][index], fallback);
    }

    function textAt(table, key, index, fallback) {
        if (!table || !table[key] || index < 0 || index >= table[key].length)
            return fallback;
        return cleanText(table[key][index], fallback);
    }

    function zipDaily(daily) {
        var times = daily && daily.time ? daily.time : [];
        var result = [];
        for (var i = 0; i < times.length && result.length < dailyLimit; i++) {
            var code = intValue(valueAt(daily, "weather_code", i, -1), -1);
            result.push({
                "time": numberValue(times[i], 0),
                "weatherCode": code,
                "weatherText": WeatherCodes.text(code),
                "weatherSlug": WeatherCodes.slug(code, false),
                "temperatureMaxC": valueAt(daily, "temperature_2m_max", i, 0),
                "temperatureMinC": valueAt(daily, "temperature_2m_min", i, 0),
                "apparentTemperatureMaxC": valueAt(daily, "apparent_temperature_max", i, 0),
                "apparentTemperatureMinC": valueAt(daily, "apparent_temperature_min", i, 0),
                "sunrise": textAt(daily, "sunrise", i, ""),
                "sunset": textAt(daily, "sunset", i, ""),
                "sunshineDurationS": valueAt(daily, "sunshine_duration", i, 0),
                "uvIndexMax": valueAt(daily, "uv_index_max", i, 0),
                "precipitationProbabilityMax": valueAt(daily, "precipitation_probability_max", i, 0),
                "precipitationSumMm": valueAt(daily, "precipitation_sum", i, 0),
                "humidityMean": valueAt(daily, "relative_humidity_2m_mean", i, 0),
                "dewPointMeanC": valueAt(daily, "dew_point_2m_mean", i, 0),
                "pressureMeanHpa": valueAt(daily, "pressure_msl_mean", i, 0),
                "cloudCoverMean": valueAt(daily, "cloud_cover_mean", i, 0),
                "visibilityMeanM": valueAt(daily, "visibility_mean", i, 0),
                "windSpeedMaxMs": valueAt(daily, "wind_speed_10m_max", i, 0),
                "windGustMaxMs": valueAt(daily, "wind_gusts_10m_max", i, 0),
                "windDirectionDominantDeg": valueAt(daily, "wind_direction_10m_dominant", i, 0)
            });
        }
        return result;
    }

    function zipHourly(hourly) {
        var times = hourly && hourly.time ? hourly.time : [];
        var result = [];
        var nowSeconds = Math.floor(Date.now() / 1000);
        for (var i = 0; i < times.length && result.length < hourlyLimit; i++) {
            var time = numberValue(times[i], 0);
            if (time > 0 && time < nowSeconds - 3600)
                continue;
            var code = intValue(valueAt(hourly, "weather_code", i, -1), -1);
            var isDay = intValue(valueAt(hourly, "is_day", i, 1), 1) !== 0;
            result.push({
                "time": time,
                "temperatureC": valueAt(hourly, "temperature_2m", i, 0),
                "apparentTemperatureC": valueAt(hourly, "apparent_temperature", i, 0),
                "precipitationProbability": valueAt(hourly, "precipitation_probability", i, 0),
                "precipitationMm": valueAt(hourly, "precipitation", i, 0),
                "weatherCode": code,
                "weatherText": WeatherCodes.text(code),
                "weatherSlug": WeatherCodes.slug(code, !isDay),
                "windSpeedMs": valueAt(hourly, "wind_speed_10m", i, 0),
                "windDirectionDeg": valueAt(hourly, "wind_direction_10m", i, 0),
                "windGustMs": valueAt(hourly, "wind_gusts_10m", i, 0),
                "uvIndex": valueAt(hourly, "uv_index", i, 0),
                "isDay": isDay,
                "humidity": valueAt(hourly, "relative_humidity_2m", i, 0),
                "dewPointC": valueAt(hourly, "dew_point_2m", i, 0),
                "pressureHpa": valueAt(hourly, "pressure_msl", i, 0),
                "cloudCover": valueAt(hourly, "cloud_cover", i, 0),
                "visibilityM": valueAt(hourly, "visibility", i, 0)
            });
        }
        return result;
    }

    function zipAirHourly(hourly) {
        var times = hourly && hourly.time ? hourly.time : [];
        var result = [];
        for (var i = 0; i < times.length; i++) {
            result.push({
                "time": numberValue(times[i], 0),
                "pm10": valueAt(hourly, "pm10", i, 0),
                "pm25": valueAt(hourly, "pm2_5", i, 0),
                "carbonMonoxide": valueAt(hourly, "carbon_monoxide", i, 0),
                "nitrogenDioxide": valueAt(hourly, "nitrogen_dioxide", i, 0),
                "sulphurDioxide": valueAt(hourly, "sulphur_dioxide", i, 0),
                "ozone": valueAt(hourly, "ozone", i, 0),
                "alderPollen": valueAt(hourly, "alder_pollen", i, 0),
                "birchPollen": valueAt(hourly, "birch_pollen", i, 0),
                "grassPollen": valueAt(hourly, "grass_pollen", i, 0),
                "mugwortPollen": valueAt(hourly, "mugwort_pollen", i, 0),
                "olivePollen": valueAt(hourly, "olive_pollen", i, 0),
                "ragweedPollen": valueAt(hourly, "ragweed_pollen", i, 0)
            });
        }
        return result;
    }

    function nearestAirQuality(items) {
        if (!items || items.length === 0)
            return {};

        var nowSeconds = Math.floor(Date.now() / 1000);
        var best = items[0];
        var bestDelta = Math.abs(numberValue(best.time, 0) - nowSeconds);
        for (var i = 1; i < items.length; i++) {
            var delta = Math.abs(numberValue(items[i].time, 0) - nowSeconds);
            if (delta < bestDelta) {
                best = items[i];
                bestDelta = delta;
            }
        }
        return best;
    }

    function applyWeatherPayload(forecast, air, lat, lon, name, stale) {
        var current = forecast && forecast.current ? forecast.current : {};
        var code = intValue(current.weather_code, -1);
        var isDay = intValue(current.is_day, 1) !== 0;
        var daily = zipDaily(forecast ? forecast.daily : null);
        var hourly = zipHourly(forecast ? forecast.hourly : null);
        var airHourly = zipAirHourly(air ? air.hourly : null);

        root.latitude = lat;
        root.longitude = lon;
        root.locationName = cleanText(name, "当前位置");
        root.locationDetected = true;
        root.currentWeatherCode = code;
        root.currentWeatherText = WeatherCodes.text(code);
        root.currentWeatherSlug = WeatherCodes.slug(code, !isDay);
        root.currentTemperatureC = numberValue(current.temperature_2m, 0);
        root.currentApparentTemperatureC = numberValue(current.apparent_temperature, 0);
        root.currentWindSpeedMs = numberValue(current.wind_speed_10m, 0);
        root.currentWindDirectionDeg = numberValue(current.wind_direction_10m, 0);
        root.currentWindGustMs = numberValue(current.wind_gusts_10m, 0);
        root.currentUvIndex = numberValue(current.uv_index, 0);
        root.currentHumidity = numberValue(current.relative_humidity_2m, 0);
        root.currentDewPointC = numberValue(current.dew_point_2m, 0);
        root.currentPressureHpa = numberValue(current.pressure_msl, 0);
        root.currentCloudCover = numberValue(current.cloud_cover, 0);
        root.currentVisibilityM = numberValue(current.visibility, 0);
        root.currentPrecipitationMm = numberValue(current.precipitation, 0);
        root.currentIsDay = isDay;
        root.dailyForecast = daily;
        root.hourlyForecast = hourly;
        root.airQualityHourly = airHourly;
        root.currentAirQuality = nearestAirQuality(airHourly);
        root.updatedAt = isoNow();
        root.status = stale ? "stale" : "fresh";
        if (!stale)
            root.lastError = "";
    }

    function cachePayload() {
        return {
            "schema": 1,
            "updatedAt": root.updatedAt,
            "latitude": root.latitude,
            "longitude": root.longitude,
            "locationName": root.locationName,
            "currentWeatherCode": root.currentWeatherCode,
            "currentTemperatureC": root.currentTemperatureC,
            "currentApparentTemperatureC": root.currentApparentTemperatureC,
            "currentWindSpeedMs": root.currentWindSpeedMs,
            "currentWindDirectionDeg": root.currentWindDirectionDeg,
            "currentWindGustMs": root.currentWindGustMs,
            "currentUvIndex": root.currentUvIndex,
            "currentHumidity": root.currentHumidity,
            "currentDewPointC": root.currentDewPointC,
            "currentPressureHpa": root.currentPressureHpa,
            "currentCloudCover": root.currentCloudCover,
            "currentVisibilityM": root.currentVisibilityM,
            "currentPrecipitationMm": root.currentPrecipitationMm,
            "currentIsDay": root.currentIsDay,
            "dailyForecast": root.dailyForecast,
            "hourlyForecast": root.hourlyForecast,
            "airQualityHourly": root.airQualityHourly,
            "currentAirQuality": root.currentAirQuality
        };
    }

    function saveCache() {
        if (!root.locationDetected || root.dailyForecast.length === 0)
            return;

        try {
            cacheFile.setText(JSON.stringify(cachePayload()));
        } catch (e) {
            root.lastError = "天气缓存写入失败";
        }
    }

    function applyCachePayload(cache, stale) {
        if (!cache || !canUseLocation(numberValue(cache.latitude, NaN), numberValue(cache.longitude, NaN)))
            return false;

        var code = intValue(cache.currentWeatherCode, -1);
        var isDay = cache.currentIsDay !== false;
        root.latitude = numberValue(cache.latitude, 0);
        root.longitude = numberValue(cache.longitude, 0);
        root.locationName = cleanText(cache.locationName, "缓存位置");
        root.locationDetected = true;
        root.currentWeatherCode = code;
        root.currentWeatherText = WeatherCodes.text(code);
        root.currentWeatherSlug = WeatherCodes.slug(code, !isDay);
        root.currentTemperatureC = numberValue(cache.currentTemperatureC, 0);
        root.currentApparentTemperatureC = numberValue(cache.currentApparentTemperatureC, 0);
        root.currentWindSpeedMs = numberValue(cache.currentWindSpeedMs, 0);
        root.currentWindDirectionDeg = numberValue(cache.currentWindDirectionDeg, 0);
        root.currentWindGustMs = numberValue(cache.currentWindGustMs, 0);
        root.currentUvIndex = numberValue(cache.currentUvIndex, 0);
        root.currentHumidity = numberValue(cache.currentHumidity, 0);
        root.currentDewPointC = numberValue(cache.currentDewPointC, 0);
        root.currentPressureHpa = numberValue(cache.currentPressureHpa, 0);
        root.currentCloudCover = numberValue(cache.currentCloudCover, 0);
        root.currentVisibilityM = numberValue(cache.currentVisibilityM, 0);
        root.currentPrecipitationMm = numberValue(cache.currentPrecipitationMm, 0);
        root.currentIsDay = isDay;
        root.dailyForecast = Array.isArray(cache.dailyForecast) ? cache.dailyForecast : [];
        root.hourlyForecast = Array.isArray(cache.hourlyForecast) ? cache.hourlyForecast : [];
        root.airQualityHourly = Array.isArray(cache.airQualityHourly) ? cache.airQualityHourly : [];
        root.currentAirQuality = cache.currentAirQuality || nearestAirQuality(root.airQualityHourly);
        root.updatedAt = cleanText(cache.updatedAt, "");
        root.status = stale ? "stale" : "fresh";
        return root.dailyForecast.length > 0 || root.hourlyForecast.length > 0;
    }

    function loadCache(stale) {
        var text = "";
        try {
            text = cacheFile.text();
        } catch (e) {
            return false;
        }

        if (String(text || "").trim().length === 0)
            return false;

        try {
            return applyCachePayload(JSON.parse(text), stale);
        } catch (e) {
            return false;
        }
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: root.loadCache(false)
    }

    Process {
        id: locationProcess
        running: false
        command: root.curlCommand("https://ipwho.is/?fields=success,latitude,longitude,city,region,country")
        stdout: StdioCollector {
            id: locationOut
        }
        onExited: function(code, exitStatus) {
            root.finishLocationRequest(code, locationOut.text);
        }
    }

    Process {
        id: geocodeProcess
        running: false
        stdout: StdioCollector {
            id: geocodeOut
        }
        onExited: function(code, exitStatus) {
            // Freeze generation at exit: pending restart must not rebind this completion.
            var generation = root.geocodeInFlightGeneration;
            var text = geocodeOut.text;
            root.finishGeocodeRequest(code, text, generation);
        }
    }

    Process {
        id: forecastProcess
        running: false
        stdout: StdioCollector {
            id: forecastOut
        }
        onExited: function(code, exitStatus) {
            root.finishForecast(code);
        }
    }

    Process {
        id: airProcess
        running: false
        stdout: StdioCollector {
            id: airOut
        }
        onExited: function(code, exitStatus) {
            root.finishAir(code);
        }
    }

    Timer {
        id: refreshTimer
        interval: root.refreshIntervalMs
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }
}
