pragma ComponentBehavior: Bound

import QtQuick

// LS09: 天气页动画背景 —— Canvas 粒子场景。
//
// 职责：根据当前 WMO 天气码 + 日夜 + 暗色主题，绘制匹配天气的天空渐变与粒子动效
// （云带 / 三层雨 / 水花 / 闪电 / 流星 / 雪花 / 星空 / 日月 / 落叶），并随鼠标轻微视差。
//
// 与参考项目 WeatherBackground.qml 的区别（防腐化，照路线图 §5/§6）：
//   - 参考用 `QtQuick.Shapes` 的 ShapePath/PathSvg 画落叶（LeafItem.qml 独立 delegate）；
//     Tahoe 把落叶纳入同一个 Canvas，用 bezier 路径绘制，避免引入 QtQuick.Shapes 新依赖。
//   - 参考按 `iconName` 字符串匹配分类；Tahoe 直接用 WMO 码数值分族（clear/partly/
//     overcast/rain/snow/storm），避免引入 slug 字符串解析依赖。
//   - 参考调色板函数名为 palette()；Tahoe 改名 skyPalette() 以免遮蔽 Item.palette 基类
//     属性。调色板加 darkMode 维度（暗色主题下天空再压暗、glow/accent/cloud 去饱和），
//     与 Tahoe 深/浅色玻璃语言一致。
//   - 全部粒子由单个 FrameAnimation 统一驱动、在单个 Canvas 里绘制（参考同结构），不拆多 Canvas。
//     FrameAnimation 跟帧走，避免 <100ms Timer 动画轮询（motion-visual rules §4.2）。
//
// 安全约束（路线图 §6.2 / 风险 1、6）：
//   - 不喂任何几何给 TahoeGlassRegion（本组件无玻璃区域，纯 Canvas 绘制），故无弹簧崩风险。
//   - 视差用 Behavior on pointerX/Y（NumberAnimation，非几何属性），照参考。
//   - FrameAnimation.running 守门于 `visible && animate`，切走/关闭即停（风险 6 对策，DoD 要求）。
Item {
    id: root

    // --- 输入契约（供 LS11 LeftSidebarWeather 绑定）---
    property int weatherCode: -1          // WMO 码，-1/越界 → overcast 兜底
    property bool night: false            // 天文日夜（来自 weather.currentIsDay 取反）
    property real windSpeedMs: 0          // 持续风速 m/s，驱动 windy → 落叶 + 云加速
    property real windGustsMs: 0          // 阵风 m/s
    property bool animate: true           // 动效总开关；切走/关闭时父级置 false
    property bool darkMode: false         // Tahoe UI 暗色主题（与天文 night 不同维度）
    property real scrollProgress: 0       // 0=顶部，1=滚到底；渐隐粒子（参考同款）

    // --- 派生分类 ---
    readonly property string weatherType: classifyWeatherType()
    readonly property string visualType: classifyVisualType()
    readonly property bool windy: classifyWindy()
    readonly property bool isRain: weatherType === "rain" || weatherType === "storm"
    readonly property bool hasSnow: weatherType === "snow"
    readonly property bool hasMeteors: night && visualType === "clear"
    readonly property bool hasLeaf: windy && (weatherType === "clear" || weatherType === "partly" || weatherType === "overcast")
    readonly property bool hasClouds: cloudBandCount() > 0
    readonly property bool hasSunMoon: visualType === "clear" || visualType === "partly"

    // --- 鼠标视差（非几何属性，NumberAnimation 缓动，安全）---
    property real pointerX: width * 0.5
    property real pointerY: height * 0.28
    readonly property real parallaxX: width > 0 ? (pointerX / width - 0.5) * 18 : 0
    readonly property real parallaxY: height > 0 ? (pointerY / height - 0.35) * 14 : 0
    Behavior on pointerX { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on pointerY { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // --- 粒子状态数组（视图内，照 LeftSidebarSystem 历史数组模式）---
    property var cloudBands: []
    property var rainLayers: [[], [], []]
    property var splashes: []
    property var lightningStrikes: []
    property real lightningCooldown: 0
    property var meteors: []
    property var snowflakes: []
    property var leaves: []
    property int nextLeafId: 0
    property real rainBounceY: height   // 雨落地 y（随高度）

    // --- 魔数提为常量（路线图 §6.4）---
    readonly property real frameBaseDt: 33 / 1000.0
    readonly property real cloudMaskOpacity: 0.18
    readonly property int snowflakeTargetCount: 24
    readonly property int meteorSlotCount: 3
    readonly property int windLeafTargetCount: 3
    readonly property int starCount: 34

    // ============================================================
    // Section 1: 分类
    // ============================================================

    // 用 WeatherCodes.slug 区分天气族，比参考的 iconName 字符串匹配更干净。
    // slug 已含日夜（clear-day / clear-night / partly-cloudy-* / overcast-* / drizzle
    // / *-rain / *-snow / *-sleet / thunderstorms-* / fog-* / cloudy）。
    function classifyWeatherType() {
        if (weatherCode >= 95)
            return "storm"
        if ((weatherCode >= 71 && weatherCode <= 77) || weatherCode === 85 || weatherCode === 86)
            return "snow"
        if ((weatherCode >= 51 && weatherCode <= 67) || (weatherCode >= 80 && weatherCode <= 82))
            return "rain"
        if (weatherCode === 0)
            return "clear"
        if (weatherCode === 1 || weatherCode === 2)
            return "partly"
        // 3 / 45 / 48 / 未知 → overcast
        return "overcast"
    }

    // windy 时把 clear/partly/overcast 当作 overcast 渲染（加云层 + 落叶），照参考 visualWeatherType。
    function classifyVisualType() {
        if (windy && (weatherType === "clear" || weatherType === "partly" || weatherType === "overcast"))
            return "overcast"
        return weatherType
    }

    function classifyWindy() {
        var sustained = isFinite(windSpeedMs) ? windSpeedMs : 0
        var gusts = isFinite(windGustsMs) ? windGustsMs : 0
        return Math.max(sustained, gusts) >= 8.0
            && (weatherType === "clear" || weatherType === "partly" || weatherType === "overcast")
    }

    function cloudBandCount() {
        var type = visualType
        if (type === "clear")
            return 0
        if (type === "partly")
            return 2
        return 3
    }

    // ============================================================
    // Section 2: 调色板（weatherType + night + darkMode 三维）
    // ============================================================

    // 继承参考 8 组配色，darkMode 维度在 night 基础上压暗 top/mid/bottom、去饱和 glow/accent/cloud。
    // darkMode 是 Tahoe UI 主题暗色（玻璃面板本身已暗），背景需更深才不糊成一片。
    function skyPalette() {
        var p = basePalette()
        if (darkMode)
            p = darkenForTheme(p)
        return p
    }

    function basePalette() {
        switch (visualType + (night ? "_night" : "_day")) {
        case "clear_day":      return sky("#7fc5e5", "#dde7ec", "#f7fbfd", "#fff6cd", "#f0efed", "#e0dfdd", "#cecdcb", "#fff2c0", "#ffd96d")
        case "clear_night":    return sky("#45578f", "#8ca0d8", "#c0cbef", "#e8edff", "#eef2fb", "#d7dce8", "#c4cad8", "#eef2ff", "#d9e5ff")
        case "partly_day":     return sky("#7fc5e5", "#dde7ec", "#f7fbfd", "#fff6cd", "#f0efed", "#e0dfdd", "#cecdcb", "#fff2c0", "#ffd96d")
        case "partly_night":   return sky("#45578f", "#8ca0d8", "#c0cbef", "#e8edff", "#eef2fb", "#d7dce8", "#c4cad8", "#eef2ff", "#d9e5ff")
        // Overcast / rain: cooler blue-grey (not cement) so hero reads as sky.
        case "overcast_day":   return sky("#6d8fa8", "#9bb4c6", "#c5d6e2", "#e4eef4", "#dce6ec", "#c8d4dc", "#b4c2cc", "#e0ecf4", "#b8d0e4")
        case "overcast_night": return sky("#3a4e66", "#5a7088", "#7a90a4", "#a8b8c8", "#6a7888", "#5a6878", "#4a5868", "#8aa0b8", "#7088a0")
        case "rain_day":       return sky("#5b7fa8", "#8aa4c0", "#b8cce0", "#dceaf4", "#c8d4e0", "#b0c0d0", "#98a8b8", "#c8e0f4", "#a8c8e8")
        case "rain_night":     return sky("#2e4560", "#4a6684", "#6a88a4", "#90a8c0", "#4a5e74", "#3e5268", "#34485c", "#7aa0c8", "#5a88b0")
        case "snow_day":       return sky("#a5bdd5", "#d1dfe9", "#f7fbfd", "#ffffff", "#f2f2f1", "#e4e3e1", "#d3d2d0", "#ffffff", "#f5fbff")
        case "snow_night":     return sky("#566d91", "#9ab0cb", "#d1dce8", "#f0f5fa", "#edf1f8", "#d5dae4", "#c4ccd8", "#ffffff", "#e7f1ff")
        case "storm_day":      return sky("#78879a", "#adb8c9", "#dbe1ea", "#f5f7fc", "#9fa4ad", "#8b8e98", "#7b7988", "#d7e8ff", "#f0d48f")
        case "storm_night":    return sky("#49516f", "#8790b0", "#c0c6da", "#e9ecf8", "#8f949d", "#7d8089", "#6d6c79", "#d3dfff", "#f6dea6")
        default:               return sky("#86a0b5", "#bccad5", "#e4ebf1", "#f6f9fb", "#f0efed", "#e0dfdd", "#cecdcb", "#eef3f8", "#dae3ec")
        }
    }

    // 天空调色板：top/mid/bottom 渐变 + glow 高光 + cloud1/2/3 三层云 + particle 粒子 + accent 日月。
    function sky(top, mid, bottom, glow, c1, c2, c3, particle, accent) {
        return { top: top, mid: mid, bottom: bottom, glow: glow,
                 cloud1: c1, cloud2: c2, cloud3: c3, particle: particle, accent: accent }
    }

    // 暗色主题压暗：top/mid/bottom 整体压暗 ~45%，glow/accent/cloud 去饱和（混入中性灰）。
    // 用 Qt.rgba/qt.hsla 太繁，这里直接给出一组「已经压暗过」的覆盖色，照参考硬编码风格。
    function darkenForTheme(p) {
        var dim = {
            "clear_day":      sky("#243a4e", "#3a5263", "#4a5d6b", "#6b6a55", "#5a5a58", "#4e4e4c", "#444442", "#7a7a66", "#8a7a44"),
            "clear_night":    sky("#1a2236", "#2a3450", "#38425c", "#5a6178", "#3a4050", "#343a48", "#2e3440", "#5a6178", "#5a6478"),
            "partly_day":     sky("#243a4e", "#3a5263", "#4a5d6b", "#6b6a55", "#5a5a58", "#4e4e4c", "#444442", "#7a7a66", "#8a7a44"),
            "partly_night":   sky("#1a2236", "#2a3450", "#38425c", "#5a6178", "#3a4050", "#343a48", "#2e3440", "#5a6178", "#5a6478"),
            "overcast_day":   sky("#2c3a44", "#3e4a54", "#505a64", "#6a7078", "#4a4a48", "#424240", "#3a3a38", "#5a626a", "#5a6470"),
            "overcast_night": sky("#222a36", "#323a48", "#424a58", "#5a626e", "#3a4050", "#343a48", "#2e3440", "#4a525e", "#4a5260"),
            "rain_day":       sky("#2a3850", "#3a4858", "#4a5664", "#5a626a", "#4a4a48", "#424240", "#3a3a38", "#5a6a7e", "#5a6e82"),
            "rain_night":     sky("#1e2a3e", "#2e3a4e", "#3e4a5c", "#525a68", "#3a4050", "#343a48", "#2e3440", "#4a6078", "#4a6680"),
            "snow_day":       sky("#344258", "#445266", "#546072", "#6a7078", "#4e4e4c", "#464644", "#3e3e3c", "#6a6a68", "#6a7078"),
            "snow_night":     sky("#222e44", "#324056", "#424e62", "#5a626e", "#3a4050", "#343a48", "#2e3440", "#5a626e", "#4e5868"),
            "storm_day":      sky("#262e3e", "#38404e", "#48505c", "#5a5e68", "#3e4248", "#363a40", "#2e3238", "#4a5668", "#6a5e44"),
            "storm_night":    sky("#1a2236", "#2a3044", "#3a4054", "#4e5268", "#363a44", "#2e323c", "#262a34", "#4a5668", "#6a5e44")
        }
        var key = visualType + (night ? "_night" : "_day")
        return hasOwn(dim, key) ? dim[key] : p
    }

    function hasOwn(map, key) {
        return Object.prototype.hasOwnProperty.call(map, key)
    }

    // ============================================================
    // Section 3: 颜色工具
    // ============================================================

    function alphaColor(hex, alpha) {
        var value = String(hex).replace("#", "")
        var r = parseInt(value.slice(0, 2), 16)
        var g = parseInt(value.slice(2, 4), 16)
        var b = parseInt(value.slice(4, 6), 16)
        return "rgba(" + r + "," + g + "," + b + "," + alpha + ")"
    }

    function cloudFillColor(index, pal) {
        if (index === 0) return pal.cloud1
        if (index === 1) return pal.cloud2
        return pal.cloud3
    }

    function rainStrokeColor() {
        return weatherType === "storm" ? "#d7deec" : "#5a86c8"
    }

    function rainTargetCount() {
        return weatherType === "storm" ? 60 : 20
    }

    function leafColors() {
        return ["#76993E", "#4A5E23", "#6D632F"]
    }

    function meteorColors() {
        return ["#d2f7ff", "#d0e9ff", "#afd0ec", "#a4c2dc", "#ecead5", "#f0dc97"]
    }

    function randomLightningDelay() {
        return Math.max(0.08, Math.random() * 6.0)
    }

    // ============================================================
    // Section 4: 云带
    // ============================================================

    function cloudSpeedFactor(index) {
        var factors = [1.0, 0.72, 0.48]
        return factors[Math.max(0, Math.min(index, factors.length - 1))]
    }

    function cloudProfile(index) {
        var wide = Math.max(width, 1)
        var configs = [
            { height: wide * 0.255, archBase: wide * 0.124, archVariance: wide * 0.124, speed: cloudSpeedFactor(0) },
            { height: wide * 0.335, archBase: wide * 0.124, archVariance: wide * 0.124, speed: cloudSpeedFactor(1) },
            { height: wide * 0.405, archBase: wide * 0.124, archVariance: wide * 0.124, speed: cloudSpeedFactor(2) }
        ]
        var config = configs[Math.max(0, Math.min(index, configs.length - 1))]
        return { h: config.height, arch: config.height + config.archBase + Math.random() * config.archVariance, speed: config.speed }
    }

    function cloudSourceIndex(slotIndex) {
        return visualType === "clear" ? slotIndex + 1 : slotIndex
    }

    function initCloudBands() {
        var bands = []
        var count = cloudBandCount()
        for (var i = 0; i < count; ++i) {
            var sourceIndex = cloudSourceIndex(i)
            var profile = cloudProfile(sourceIndex)
            bands.push({ offset: Math.random() * Math.max(width, 1), height: profile.h, arch: profile.arch, speed: profile.speed, toneIndex: sourceIndex })
        }
        cloudBands = bands
        canvas.requestPaint()
    }

    function driftBaseSpeed() {
        if (!hasClouds)
            return 0
        return windy ? 3.05 : 1.05
    }

    // ============================================================
    // Section 5: 雨 + 水花（三层深度）
    // ============================================================

    function makeEmptyRainLayers() {
        return [[], [], []]
    }

    function resetRainScene() {
        rainLayers = makeEmptyRainLayers()
        splashes = []
        canvas.requestPaint()
    }

    function makeRainDrop() {
        var lineWidth = Math.random() * 3
        var lineLength = weatherType === "storm" ? 35 : 14
        var layerIndex = Math.max(0, Math.min(2, 2 - Math.floor(lineWidth)))
        rainLayers[layerIndex].push({ x: 20 + Math.random() * Math.max(1, width - 40), width: lineWidth, len: lineLength, age: 0, delay: Math.random(), duration: 1 })
    }

    function makeSplash(x, stroke) {
        var splashLength = weatherType === "storm" ? 30 : 20
        var splashBounce = weatherType === "storm" ? 120 : 100
        var splashDistance = 80
        var randomX = (Math.random() * splashDistance) - (splashDistance / 2)
        var curve = makeQuadraticSamples(0, 0, randomX, -(Math.random() * splashBounce), randomX * 2, splashDistance)
        splashes.push({ x: x, y: Math.max(0, Math.min(height, rainBounceY)), segmentLength: splashLength, duration: weatherType === "storm" ? 0.7 : 0.5, age: 0, color: stroke, samples: curve.points, totalLength: curve.totalLength })
    }

    function updateRain(dt) {
        for (var layerIndex = 0; layerIndex < rainLayers.length; ++layerIndex) {
            var layer = rainLayers[layerIndex]
            for (var i = layer.length - 1; i >= 0; --i) {
                var drop = layer[i]
                drop.age += dt
                if (drop.age >= drop.delay + drop.duration) {
                    if (drop.width > 2)
                        makeSplash(drop.x, rainStrokeColor())
                    layer.splice(i, 1)
                }
            }
        }
        var dropCount = 0
        for (var li = 0; li < rainLayers.length; ++li)
            dropCount += rainLayers[li].length
        while (dropCount < rainTargetCount()) {
            makeRainDrop()
            ++dropCount
        }
    }

    function updateSplashes(dt) {
        for (var i = splashes.length - 1; i >= 0; --i) {
            var splash = splashes[i]
            splash.age += dt
            if (splash.age >= splash.duration)
                splashes.splice(i, 1)
        }
    }

    function rainDropTop(drop, bounceY) {
        if (drop.age <= drop.delay)
            return -drop.len
        var progress = Math.min(1, (drop.age - drop.delay) / drop.duration)
        return -drop.len + (bounceY + drop.len) * progress * progress
    }

    // ============================================================
    // Section 6: 二次贝塞尔采样（水花弧线用）
    // ============================================================

    function quadraticPoint(sx, sy, cx, cy, ex, ey, t) {
        var inv = 1 - t
        return { x: inv * inv * sx + 2 * inv * t * cx + t * t * ex, y: inv * inv * sy + 2 * inv * t * cy + t * t * ey }
    }

    function makeQuadraticSamples(sx, sy, cx, cy, ex, ey) {
        var steps = 20
        var points = [{ x: sx, y: sy, len: 0 }]
        var prev = { x: sx, y: sy }
        var total = 0
        for (var i = 1; i <= steps; ++i) {
            var pt = quadraticPoint(sx, sy, cx, cy, ex, ey, i / steps)
            var dx = pt.x - prev.x
            var dy = pt.y - prev.y
            total += Math.sqrt(dx * dx + dy * dy)
            points.push({ x: pt.x, y: pt.y, len: total })
            prev = pt
        }
        return { points: points, totalLength: total }
    }

    function sampleAtLength(samples, target) {
        if (samples.length === 0)
            return { x: 0, y: 0 }
        if (target <= 0)
            return { x: samples[0].x, y: samples[0].y }
        var end = samples[samples.length - 1]
        if (target >= end.len)
            return { x: end.x, y: end.y }
        for (var i = 1; i < samples.length; ++i) {
            var cur = samples[i]
            if (target <= cur.len) {
                var prev = samples[i - 1]
                var span = Math.max(0.0001, cur.len - prev.len)
                var ratio = (target - prev.len) / span
                return { x: prev.x + (cur.x - prev.x) * ratio, y: prev.y + (cur.y - prev.y) * ratio }
            }
        }
        return { x: end.x, y: end.y }
    }

    // ============================================================
    // Section 7: 闪电（雷暴）
    // ============================================================

    function resetLightningScene() {
        lightningStrikes = []
        lightningCooldown = randomLightningDelay()
        canvas.requestPaint()
    }

    function makeLightningStrike() {
        if (width <= 0 || height <= 0)
            return
        var steps = 20
        var hMargin = Math.min(width * 0.25, Math.max(24, width * 0.10))
        var hJitter = Math.max(20, width * 0.07)
        var pathX = hMargin + Math.random() * Math.max(1, width - hMargin * 2)
        var points = [{ x: pathX, y: 0 }]
        for (var i = 0; i < steps; ++i) {
            points.push({ x: pathX + (Math.random() * hJitter - hJitter * 0.5), y: (height / steps) * (i + 1) })
        }
        lightningStrikes = lightningStrikes.concat([{ points: points, age: 0, duration: 1.0, strokeWidth: 2.8 + Math.random() * 1.2 }])
    }

    function updateLightning(dt) {
        if (weatherType !== "storm") {
            if (lightningStrikes.length > 0)
                lightningStrikes = []
            return
        }
        for (var i = lightningStrikes.length - 1; i >= 0; --i) {
            var strike = lightningStrikes[i]
            strike.age += dt
            if (strike.age >= strike.duration)
                lightningStrikes.splice(i, 1)
        }
        lightningCooldown -= dt
        while (lightningCooldown <= 0) {
            makeLightningStrike()
            lightningCooldown += randomLightningDelay()
        }
    }

    // ============================================================
    // Section 8: 流星（晴夜）
    // ============================================================

    function meteorRespawnDelay(firstSpawn) {
        return (firstSpawn ? 1.0 : 5.0) + Math.random() * (firstSpawn ? 6.0 : 12.0)
    }

    function makeMeteorState(delaySeconds) {
        var colors = meteorColors()
        var scale = 0.45 + Math.random() * 0.55
        var size = Math.max(1, Math.min(width, height))
        var angle = (108 + Math.random() * 18) * Math.PI / 180.0
        return {
            active: false, delay: delaySeconds, progress: 0,
            startX: width * (0.22 + Math.random() * 0.96),
            startY: height * (-0.30 + Math.random() * 0.42),
            dx: Math.cos(angle), dy: Math.sin(angle),
            travel: size * (0.50 + Math.random() * 0.26),
            len: size * (0.24 + Math.random() * 0.14) * scale,
            strokeWidth: 1.5 + scale * 1.5,
            color: colors[Math.floor(Math.random() * colors.length)]
        }
    }

    function resetMeteorScene() {
        meteors = []
        if (hasMeteors) {
            var slots = []
            for (var i = 0; i < meteorSlotCount; ++i)
                slots.push(makeMeteorState(meteorRespawnDelay(true)))
            meteors = slots
        }
        canvas.requestPaint()
    }

    function updateMeteors(dt) {
        if (!hasMeteors) {
            if (meteors.length > 0)
                meteors = []
            return
        }
        var next = meteors.slice(0, meteorSlotCount)
        while (next.length < meteorSlotCount)
            next.push(makeMeteorState(meteorRespawnDelay(true)))
        for (var i = 0; i < next.length; ++i) {
            var meteor = next[i]
            if (!meteor.active) {
                meteor.delay -= dt
                if (meteor.delay <= 0) {
                    meteor.active = true
                    meteor.progress = 0
                }
                continue
            }
            meteor.progress += dt * meteor.travel * 1.85
            if (meteor.progress >= meteor.travel)
                next[i] = makeMeteorState(meteorRespawnDelay(false))
        }
        meteors = next
    }

    // ============================================================
    // Section 9: 雪花
    // ============================================================

    function snowFloorY(radius) {
        var margin = radius === undefined ? 0 : radius
        return Math.max(margin, Math.min(height, rainBounceY - margin))
    }

    function configureSnowflake(flake, ageOverride) {
        var scale = 0.5 + Math.random() * 0.5
        var fallDuration = 3.0 + Math.random() * 5.0
        var radiusBase = 5 * scale
        flake.age = ageOverride === undefined ? 0 : ageOverride
        flake.x = 20 + Math.random() * Math.max(0, width - 40)
        flake.y = -10
        flake.endY = snowFloorY(radiusBase)
        flake.swayTarget = (Math.random() * 150) - 75
        flake.swayFactor = Math.PI / 3.0
        flake.fallDuration = fallDuration
        flake.fallInverse = 1.0 / fallDuration
        flake.radiusBase = radiusBase
        flake.alphaBase = 0.34 + scale * 0.42
    }

    function makeSnowflake(ageOverride) {
        var flake = {}
        configureSnowflake(flake, ageOverride)
        return flake
    }

    function resetSnowScene() {
        snowflakes = []
        if (!hasSnow || width <= 40 || height <= 0)
            return
        var next = []
        var target = snowflakeTargetCount
        for (var i = 0; i < target; ++i) {
            var flake = makeSnowflake()
            flake.age = Math.random() * flake.fallDuration
            next.push(flake)
        }
        snowflakes = next
    }

    function updateSnow(dt) {
        if (!hasSnow) {
            if (snowflakes.length > 0)
                snowflakes = []
            return
        }
        var target = snowflakeTargetCount
        for (var i = 0; i < snowflakes.length; ++i) {
            var flake = snowflakes[i]
            flake.age += dt
            if (flake.age >= flake.fallDuration)
                configureSnowflake(flake, 0)
        }
        while (snowflakes.length < target)
            snowflakes.push(makeSnowflake())
        while (snowflakes.length > target)
            snowflakes.pop()
    }

    // ============================================================
    // Section 10: 落叶（windy 时，Canvas bezier 绘制）
    // ============================================================

    function leafFlightBounds() {
        var bottom = Math.max(120, height)
        return { top: 0, bottom: bottom, span: Math.max(48, bottom) }
    }

    function nextLeafSpawnInterval() {
        return 260 + Math.random() * 420
    }

    function makeLeafState() {
        var colors = leafColors()
        var scale = 0.5 + Math.random() * 0.5
        var bounds = leafFlightBounds()
        var areaY = bounds.span / 2
        var startY = areaY + Math.random() * areaY
        var endY = startY - ((Math.random() * (areaY * 2)) - areaY)
        var controlY = Math.random() * endY + endY / 3
        return {
            leafId: ++nextLeafId,
            scale: scale,
            color: colors[Math.floor(Math.random() * colors.length)],
            startRotation: Math.random() * 180,
            endRotation: Math.random() * 360,
            progress: 0,
            duration: 2.0,
            x0: -100, y0: startY,
            x1: width / 2, y1: controlY,
            x2: width + 50, y2: endY
        }
    }

    function quadPoint(p0, p1, p2, t) {
        var inv = 1 - t
        return { x: inv * inv * p0.x + 2 * inv * t * p1.x + t * t * p2.x,
                 y: inv * inv * p0.y + 2 * inv * t * p1.y + t * t * p2.y }
    }

    function resetLeafScene() {
        leaves = []
        leafSpawnAccum = 0
        if (hasLeaf)
            scheduleLeafSpawn = true
    }

    // 落叶由主 FrameAnimation 驱动（与其它粒子统一），用累积时间触发新叶。
    property bool scheduleLeafSpawn: false
    property real leafSpawnAccum: 0

    function updateLeaves(dt) {
        if (!hasLeaf) {
            if (leaves.length > 0)
                leaves = []
            scheduleLeafSpawn = false
            leafSpawnAccum = 0
            return
        }
        // 推进已存在叶子的进度
        for (var i = leaves.length - 1; i >= 0; --i) {
            var leaf = leaves[i]
            leaf.progress += dt / leaf.duration
            if (leaf.progress >= 1)
                leaves.splice(i, 1)
        }
        // 按间隔补充到目标数量
        leafSpawnAccum += dt * 1000
        while (leaves.length < windLeafTargetCount && leafSpawnAccum >= 0) {
            leaves.push(makeLeafState())
            leafSpawnAccum -= nextLeafSpawnInterval()
        }
        if (leaves.length >= windLeafTargetCount)
            leafSpawnAccum = 0
    }

    // ============================================================
    // Section 11: 场景重置
    // ============================================================

    function resetAllScenes() {
        initCloudBands()
        resetRainScene()
        resetLightningScene()
        resetMeteorScene()
        resetSnowScene()
        resetLeafScene()
    }

    // ============================================================
    // Section 12: 绘制
    // ============================================================

    function drawCloudBandShape(ctx, offset, bandHeight, archHeight) {
        var w = Math.max(width, 1)
        var startX = -w + offset
        ctx.beginPath()
        ctx.moveTo(startX, 0)
        ctx.lineTo(startX + w * 2.0, 0)
        ctx.quadraticCurveTo(startX + w * 3.0, bandHeight * 0.5, startX + w * 2.0, bandHeight)
        ctx.quadraticCurveTo(startX + w * 1.5, archHeight, startX + w, bandHeight)
        ctx.quadraticCurveTo(startX + w * 0.5, archHeight, startX, bandHeight)
        ctx.quadraticCurveTo(startX - w, bandHeight * 0.5, startX - w, 0)
        ctx.closePath()
    }

    function drawCloudBand(ctx, offset, bandHeight, archHeight, fillColor) {
        ctx.fillStyle = fillColor
        drawCloudBandShape(ctx, offset, bandHeight, archHeight)
        ctx.fill()
        ctx.fillStyle = alphaColor("#6a7078", cloudMaskOpacity)
        drawCloudBandShape(ctx, offset, bandHeight, archHeight)
        ctx.fill()
    }

    function drawSunOrMoon(ctx, fade, pal) {
        if (night)
            return // 夜间由星空 + 流星承担，参考同款（drawSunOrMoon 在 night 直接 return）
        var cx = width * 0.80 + parallaxX * 0.8 + Math.sin(canvas.phase * 0.18) * 9
        var cy = height * 0.17 + parallaxY * 0.5 + Math.cos(canvas.phase * 0.15) * 7
        var radius = Math.min(width, height) * 0.13
        ctx.fillStyle = alphaColor(pal.glow, 0.22 * fade)
        ctx.beginPath()
        ctx.arc(cx, cy, radius * 2.0, 0, Math.PI * 2)
        ctx.fill()
        ctx.fillStyle = alphaColor(pal.accent, 0.90 * fade)
        ctx.beginPath()
        ctx.arc(cx, cy, radius, 0, Math.PI * 2)
        ctx.fill()
    }

    function drawStars(ctx, fade, pal) {
        for (var i = 0; i < starCount; ++i) {
            var twinkle = 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(canvas.phase * (0.5 + (i % 4) * 0.09) + i * 1.3))
            var x = (i * 43 + (i % 3) * 29) % Math.max(width, 1)
            var y = (i * 27 + (i % 6) * 15) % Math.max(80, height * 0.48)
            var r = 0.9 + (i % 3) * 0.35
            ctx.fillStyle = alphaColor(pal.particle, twinkle * 0.56 * fade)
            ctx.beginPath()
            ctx.arc(x, y, r, 0, Math.PI * 2)
            ctx.fill()
        }
    }

    function drawMeteors(ctx, fade) {
        ctx.lineCap = "round"
        for (var i = 0; i < meteors.length; ++i) {
            var meteor = meteors[i]
            if (!meteor.active)
                continue
            var progress = Math.max(0, Math.min(1, meteor.progress / meteor.travel))
            var opacity = Math.sin(progress * Math.PI) * 0.92 * fade
            if (opacity <= 0.02)
                continue
            var headX = meteor.startX + meteor.dx * meteor.progress
            var headY = meteor.startY + meteor.dy * meteor.progress
            var tailX = headX - meteor.dx * meteor.len
            var tailY = headY - meteor.dy * meteor.len
            ctx.strokeStyle = alphaColor(meteor.color, opacity * 0.16)
            ctx.lineWidth = meteor.strokeWidth * 2.4
            ctx.beginPath()
            ctx.moveTo(tailX, tailY)
            ctx.lineTo(headX, headY)
            ctx.stroke()
            var segments = 7
            for (var s = 0; s < segments; ++s) {
                var startRatio = s / segments
                var endRatio = (s + 1) / segments
                var sx = tailX + (headX - tailX) * startRatio
                var sy = tailY + (headY - tailY) * startRatio
                var ex = tailX + (headX - tailX) * endRatio
                var ey = tailY + (headY - tailY) * endRatio
                ctx.strokeStyle = alphaColor(meteor.color, opacity * (0.10 + 0.90 * Math.pow(endRatio, 1.7)))
                ctx.lineWidth = meteor.strokeWidth * (0.30 + 0.70 * endRatio)
                ctx.beginPath()
                ctx.moveTo(sx, sy)
                ctx.lineTo(ex, ey)
                ctx.stroke()
            }
            ctx.fillStyle = alphaColor("#ffffff", Math.min(1, opacity * 0.95))
            ctx.beginPath()
            ctx.arc(headX, headY, meteor.strokeWidth * 0.45, 0, Math.PI * 2)
            ctx.fill()
        }
    }

    function drawRainLayer(ctx, fade, layerIndex) {
        var layer = rainLayers[layerIndex]
        var bounceY = Math.max(0, Math.min(height, rainBounceY))
        ctx.lineCap = "butt"
        ctx.strokeStyle = alphaColor(rainStrokeColor(), fade)
        for (var i = 0; i < layer.length; ++i) {
            var drop = layer[i]
            if (drop.age < drop.delay)
                continue
            var dropTop = rainDropTop(drop, bounceY)
            ctx.lineWidth = drop.width
            ctx.beginPath()
            ctx.moveTo(drop.x, dropTop)
            ctx.lineTo(drop.x, dropTop + drop.len)
            ctx.stroke()
        }
    }

    function drawSplashes(ctx, fade) {
        ctx.lineCap = "butt"
        for (var i = 0; i < splashes.length; ++i) {
            var splash = splashes[i]
            var progress = splash.age / splash.duration
            var strokeWidth = 2 * (1 - progress)
            var startLength = progress * splash.totalLength
            var endLength = Math.min(splash.totalLength, startLength + splash.segmentLength)
            if (strokeWidth <= 0.02 || endLength <= startLength)
                continue
            var startPoint = sampleAtLength(splash.samples, startLength)
            var endPoint = sampleAtLength(splash.samples, endLength)
            ctx.strokeStyle = alphaColor(splash.color, fade)
            ctx.lineWidth = strokeWidth
            ctx.beginPath()
            ctx.moveTo(splash.x + startPoint.x, splash.y + startPoint.y)
            for (var si = 1; si < splash.samples.length - 1; ++si) {
                var sample = splash.samples[si]
                if (sample.len <= startLength || sample.len >= endLength)
                    continue
                ctx.lineTo(splash.x + sample.x, splash.y + sample.y)
            }
            ctx.lineTo(splash.x + endPoint.x, splash.y + endPoint.y)
            ctx.stroke()
        }
    }

    function drawSnow(ctx, fade, pal) {
        if (fade <= 0 || snowflakes.length === 0)
            return
        ctx.fillStyle = pal.particle
        for (var i = 0; i < snowflakes.length; ++i) {
            var flake = snowflakes[i]
            var fallProgress = Math.max(0, Math.min(1, flake.age * flake.fallInverse))
            var growEase = 0.5 - 0.5 * Math.cos(Math.max(0, Math.min(1, flake.age)) * Math.PI)
            var sway = flake.swayTarget * 0.5 * (1 - Math.cos(flake.age * flake.swayFactor))
            var x = flake.x + sway
            var y = flake.y + (flake.endY - flake.y) * fallProgress
            var radius = flake.radiusBase * growEase
            if (radius <= 0.05)
                continue
            ctx.globalAlpha = flake.alphaBase * fade
            ctx.beginPath()
            ctx.arc(x, y, radius, 0, Math.PI * 2)
            ctx.fill()
        }
        ctx.globalAlpha = 1
    }

    function drawLightning(ctx, fade) {
        var flashOpacity = 0
        for (var i = 0; i < lightningStrikes.length; ++i) {
            var strike = lightningStrikes[i]
            var progress = Math.max(0, Math.min(1, strike.age / strike.duration))
            flashOpacity = Math.max(flashOpacity, Math.pow(1 - progress, 10) * 0.22 * fade)
        }
        if (flashOpacity > 0.01) {
            ctx.fillStyle = "rgba(255,255,255," + flashOpacity + ")"
            ctx.fillRect(0, 0, width, height)
        }
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        for (var j = 0; j < lightningStrikes.length; ++j) {
            var s = lightningStrikes[j]
            var p = Math.max(0, Math.min(1, s.age / s.duration))
            var opacity = Math.pow(1 - p, 4) * fade
            if (opacity <= 0.01 || s.points.length === 0)
                continue
            ctx.strokeStyle = "rgba(255,255,255," + opacity + ")"
            ctx.lineWidth = s.strokeWidth
            ctx.beginPath()
            ctx.moveTo(s.points[0].x, s.points[0].y)
            for (var k = 1; k < s.points.length; ++k)
                ctx.lineTo(s.points[k].x, s.points[k].y)
            ctx.stroke()
        }
    }

    // 落叶：bezier 飞行轨迹 + 旋转 + 简化叶形（两段 bezier 画不对称叶瓣，照参考轮廓意）。
    function drawLeaf(ctx, leaf, fade) {
        var t = Math.max(0, Math.min(1, leaf.progress))
        var pos = quadPoint({ x: leaf.x0, y: leaf.y0 }, { x: leaf.x1, y: leaf.y1 }, { x: leaf.x2, y: leaf.y2 }, t)
        var rotation = (leaf.startRotation + (leaf.endRotation - leaf.startRotation) * t) * Math.PI / 180.0
        var size = 18 * leaf.scale
        ctx.save()
        ctx.translate(pos.x, pos.y)
        ctx.rotate(rotation)
        ctx.globalAlpha = 0.88 * fade
        ctx.fillStyle = leaf.color
        ctx.beginPath()
        // 叶身：从叶柄到叶尖的不对称双弧，近似参考的 PathSvg 轮廓。
        ctx.moveTo(-size, 0)
        ctx.bezierCurveTo(-size * 0.5, -size * 0.55, size * 0.5, -size * 0.45, size, 0)
        ctx.bezierCurveTo(size * 0.5, size * 0.45, -size * 0.5, size * 0.55, -size, 0)
        ctx.fill()
        // 叶脉中线
        ctx.strokeStyle = alphaColor(leaf.color, 0.0) // 透明，留作占位；叶形已足够辨识
        ctx.restore()
        ctx.globalAlpha = 1
    }

    function drawLeaves(ctx, fade) {
        for (var i = 0; i < leaves.length; ++i)
            drawLeaf(ctx, leaves[i], fade)
    }

    // ============================================================
    // Section 13: 背景渐变层（Rectangle，原生 Gradient，软件渲染安全）
    // ============================================================

    Rectangle {
        anchors.fill: parent
        opacity: Math.max(0.46, 0.96 - root.scrollProgress * 0.28)
        gradient: Gradient {
            orientation: Qt.Vertical
            GradientStop { position: 0.0; color: root.skyPalette().top }
            GradientStop { position: 0.54; color: root.skyPalette().mid }
            GradientStop { position: 1.0; color: root.skyPalette().bottom }
        }
    }

    Rectangle {
        anchors.fill: parent
        opacity: Math.max(0, 0.20 - root.scrollProgress * 0.08)
        gradient: Gradient {
            orientation: Qt.Vertical
            GradientStop { position: 0.0; color: root.alphaColor(root.skyPalette().glow, 0.18) }
            GradientStop { position: 0.44; color: root.alphaColor(root.skyPalette().glow, 0.04) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // ============================================================
    // Section 14: Canvas（所有粒子）
    // ============================================================

    Canvas {
        id: canvas
        anchors.fill: parent
        opacity: Math.max(0, 0.92 - root.scrollProgress * 0.34)
        // 软件渲染路径下 Canvas 默认即可；不设 renderTarget 以兼容 VM。
        property real phase: 0

        onPaint: {
            var ctx = getContext("2d")
            var fade = Math.max(0, 1 - root.scrollProgress)
            var colors = root.skyPalette()
            ctx.clearRect(0, 0, width, height)

            if (root.night)
                root.drawStars(ctx, fade, colors)

            if (root.hasSunMoon)
                root.drawSunOrMoon(ctx, fade, colors)

            if (root.hasMeteors)
                root.drawMeteors(ctx, fade)

            if (root.hasClouds) {
                for (var i = root.cloudBands.length - 1; i >= 0; --i) {
                    if (root.isRain)
                        root.drawRainLayer(ctx, fade, i)
                    if (root.weatherType === "storm" && i === 0)
                        root.drawLightning(ctx, fade)
                    var band = root.cloudBands[i]
                    root.drawCloudBand(ctx, band.offset, band.height, band.arch, root.cloudFillColor(band.toneIndex, colors))
                }
            }

            if (root.isRain)
                root.drawSplashes(ctx, fade)

            if (root.hasSnow)
                root.drawSnow(ctx, fade, colors)

            if (root.hasLeaf)
                root.drawLeaves(ctx, fade)
        }
    }

    // 底部暗角，增强卡片内容可读性（照参考）。
    Rectangle {
        anchors.fill: parent
        opacity: Math.max(0, 0.18 - root.scrollProgress * 0.08)
        gradient: Gradient {
            orientation: Qt.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.62; color: "transparent" }
            GradientStop { position: 1.0; color: root.alphaColor("#0d1220", root.night ? 0.12 : 0.09) }
        }
    }

    // ============================================================
    // Section 15: 鼠标视差
    // ============================================================

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
            root.pointerX = mouse.x
            root.pointerY = mouse.y
        }
        onExited: {
            root.pointerX = root.width * 0.5
            root.pointerY = root.height * 0.28
        }
    }

    // ============================================================
    // Section 16: FrameAnimation 驱动（守门 visible && animate）
    // ============================================================

    FrameAnimation {
        id: tick
        // Parent gates animate (sidebar tab + reduced motion). Do not also
        // require visible — MultiEffect mask paths may hide the source item.
        running: root.animate

        property double lastTickMs: 0

        onRunningChanged: {
            if (!running)
                lastTickMs = 0
        }

        onTriggered: {
            var now = Date.now()
            // Cap dt so a hitch does not fling particles across the card.
            var dt = lastTickMs > 0 ? Math.min(0.05, (now - lastTickMs) / 1000.0) : root.frameBaseDt
            var stepScale = dt / root.frameBaseDt
            lastTickMs = now

            // 云带漂移
            var base = root.driftBaseSpeed()
            var nextBands = []
            for (var i = 0; i < root.cloudBands.length; ++i) {
                var band = root.cloudBands[i]
                var wrappedOffset = band.offset
                if (base > 0) {
                    var nextOffset = band.offset + base * band.speed * stepScale
                    wrappedOffset = nextOffset
                    if (wrappedOffset > root.width)
                        wrappedOffset = wrappedOffset - root.width
                }
                nextBands.push({ offset: wrappedOffset, height: band.height, arch: band.arch, speed: band.speed, toneIndex: band.toneIndex })
            }
            root.cloudBands = nextBands

            // 雨 + 水花
            if (root.isRain) {
                root.updateRain(dt)
                root.updateSplashes(dt)
            } else if (root.rainLayers.length > 0 || root.splashes.length > 0) {
                root.rainLayers = root.makeEmptyRainLayers()
                root.splashes = []
            }

            root.updateSnow(dt)
            root.updateLightning(dt)
            root.updateMeteors(dt)
            root.updateLeaves(dt)

            canvas.phase += 0.04 * stepScale
            canvas.requestPaint()
        }
    }

    // ============================================================
    // Section 17: 生命周期
    // ============================================================

    Component.onCompleted: resetAllScenes()

    onWidthChanged: resetAllScenes()
    onHeightChanged: resetAllScenes()
    onWeatherTypeChanged: resetAllScenes()
    onNightChanged: {
        // 日夜切换影响流星/星空/日月，重置流星与场景。
        resetMeteorScene()
        canvas.requestPaint()
    }
    onDarkModeChanged: canvas.requestPaint()
    onScrollProgressChanged: canvas.requestPaint()
}
