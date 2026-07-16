pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// S5.3: animations domain. Spring params (damping-ratio/stiffness/epsilon) for
// the four spring-based actions present in the config write through
// NiriSettings.setAnimParam (optimistic object update + queued KDL write +
// hot-reload). window-open/close carry custom GLSL shaders and are never
// written here. Ranges follow the niri schema parse-time bounds:
// damping-ratio [0.1,10], stiffness >=1, epsilon [0.00001,0.1].
Flickable {
    id: page

    property var panel
    property var theme

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded
    readonly property real f64Epsilon: 2.220446049250313e-16
    readonly property real f32Epsilon: 1.1920928955078125e-7
    property string selectedCurveName: "emphasized-decel"
    property string selectedSpringAction: "workspace_switch"

    readonly property var namedCurveModel: [
        { name: "linear", label: "linear", kind: "linear", use: "constant velocity" },
        { name: "ease-out-quad", label: "ease-out-quad", kind: "ease-out-quad", use: "short opacity" },
        { name: "ease-out-cubic", label: "ease-out-cubic", kind: "ease-out-cubic", use: "legacy QML-ish decel" },
        { name: "ease-out-expo", label: "ease-out-expo", kind: "ease-out-expo", use: "fast start, soft tail" },
        { name: "standard-decel", label: "standard-decel", kind: "cubic", x1: 0, y1: 0, x2: 0, y2: 1, use: "opacity channel" },
        { name: "emphasized-decel", label: "emphasized-decel", kind: "cubic", x1: 0.05, y1: 0.7, x2: 0.1, y2: 1, use: "panel enter transform" },
        { name: "emphasized-accel", label: "emphasized-accel", kind: "cubic", x1: 0.3, y1: 0, x2: 0.8, y2: 0.15, use: "panel close transform" },
        { name: "expressive-effects", label: "expressive-effects", kind: "cubic", x1: 0.34, y1: 0.8, x2: 0.34, y2: 1, use: "QML expressive effects" },
        { name: "menu-decel-safe", label: "menu-decel-safe", kind: "cubic", x1: 0.12, y1: 0.95, x2: 0.16, y2: 1, use: "safe menu enter" },
        { name: "menu-decel", label: "menu-decel", kind: "cubic", x1: 0.1, y1: 1, x2: 0, y2: 1, use: "compat only" },
        { name: "menu-accel", label: "menu-accel", kind: "cubic", x1: 0.52, y1: 0.03, x2: 0.72, y2: 0.08, use: "menu close" },
        { name: "stall", label: "stall", kind: "cubic", x1: 1, y1: -0.1, x2: 0.7, y2: 0.85, use: "compat only" }
    ]

    readonly property var springActionModel: [
        { value: "workspace_switch", label: "工作区" },
        { value: "window_movement", label: "移动" },
        { value: "window_resize", label: "缩放" },
        { value: "overview_open_close", label: "概览" }
    ]

    onSelectedCurveNameChanged: if (curveCanvas)
        curveCanvas.requestPaint()

    onSelectedSpringActionChanged: if (springCanvas)
        springCanvas.requestPaint()

    function animValue(action, param) {
        if (!page.svc || !page.svc.animSprings)
            return 0;
        var entry = page.svc.animSprings[action];
        var value = entry ? entry[param] : 0;
        return isFinite(value) ? value : 0;
    }

    function roundTo(value, decimals) {
        var factor = Math.pow(10, decimals);
        return Math.round(Number(value) * factor) / factor;
    }

    // damping-ratio [0.1, 10] <-> [0,1]
    function dampingFromValue(v) {
        return Math.max(0, Math.min(1, (Number(v) - 0.1) / 9.9));
    }
    function dampingToValue(r) {
        return page.roundTo(0.1 + r * 9.9, 2);
    }
    // stiffness [1, 1000] <-> [0,1]
    function stiffnessFromValue(v) {
        return Math.max(0, Math.min(1, (Number(v) - 1) / 999));
    }
    function stiffnessToValue(r) {
        return Math.round(1 + r * 999);
    }
    // epsilon [0.00001, 0.1] <-> [0,1]
    function epsilonFromValue(v) {
        return Math.max(0, Math.min(1, (Number(v) - 0.00001) / 0.09999));
    }
    function epsilonToValue(r) {
        return page.roundTo(0.00001 + r * 0.09999, 5);
    }

    function selectedCurve() {
        for (var i = 0; i < page.namedCurveModel.length; i++) {
            var curve = page.namedCurveModel[i];
            if (curve.name === page.selectedCurveName)
                return curve;
        }
        return page.namedCurveModel[0];
    }

    function cubicXForT(curve, t) {
        var omt = 1 - t;
        return 3 * omt * omt * t * curve.x1
            + 3 * omt * t * t * curve.x2
            + t * t * t;
    }

    function cubicYForT(curve, t) {
        var omt = 1 - t;
        return 3 * omt * omt * t * curve.y1
            + 3 * omt * t * t * curve.y2
            + t * t * t;
    }

    function cubicTForX(curve, x) {
        var minT = 0;
        var maxT = 1;
        for (var i = 0; i <= 30; i++) {
            var guessT = (minT + maxT) / 2;
            var guessX = page.cubicXForT(curve, guessT);
            if (x < guessX)
                maxT = guessT;
            else
                minT = guessT;
        }
        return (minT + maxT) / 2;
    }

    function curveY(curve, x) {
        x = Math.max(0, Math.min(1, Number(x)));
        if (x <= page.f64Epsilon)
            return 0;
        if (1 - page.f64Epsilon <= x)
            return 1;

        switch (curve.kind) {
        case "linear":
            return x;
        case "ease-out-quad":
            return 1 - Math.pow(1 - x, 2);
        case "ease-out-cubic":
            return 1 - Math.pow(1 - x, 3);
        case "ease-out-expo":
            return 1 - Math.pow(2, -10 * x);
        case "cubic":
        default:
            return page.cubicYForT(curve, page.cubicTForX(curve, x));
        }
    }

    function curveVelocity(curve, x) {
        var delta = 0.005;
        var a = Math.max(0, x - delta);
        var b = Math.min(1, x + delta);
        if (Math.abs(b - a) < 1e-9)
            return 0;
        return (page.curveY(curve, b) - page.curveY(curve, a)) / (b - a);
    }

    function curvePointText(curve) {
        return "25%=" + page.roundTo(page.curveY(curve, 0.25), 2)
            + "  50%=" + page.roundTo(page.curveY(curve, 0.5), 2)
            + "  75%=" + page.roundTo(page.curveY(curve, 0.75), 2);
    }

    function curveVelocityText(curve) {
        return "speed " + page.roundTo(page.curveVelocity(curve, 0.05), 2)
            + " / " + page.roundTo(page.curveVelocity(curve, 0.5), 2)
            + " / " + page.roundTo(page.curveVelocity(curve, 0.95), 2);
    }

    function curveSpecText(curve) {
        if (curve.kind !== "cubic")
            return curve.name;
        return "cubic-bezier("
            + curve.x1 + ", " + curve.y1 + ", "
            + curve.x2 + ", " + curve.y2 + ")";
    }

    function curveRiskText(curve) {
        var risks = [];
        if (curve.kind === "cubic" && curve.x2 < curve.x1)
            risks.push("non-monotonic x");
        if (curve.kind === "cubic"
                && (curve.y1 < 0 || curve.y1 > 1 || curve.y2 < 0 || curve.y2 > 1))
            risks.push("overshoot control");

        var previous = page.curveY(curve, 0);
        var minY = previous;
        var maxY = previous;
        var backtracks = false;
        for (var i = 1; i <= 100; i++) {
            var y = page.curveY(curve, i / 100);
            minY = Math.min(minY, y);
            maxY = Math.max(maxY, y);
            if (y + 0.001 < previous)
                backtracks = true;
            previous = y;
        }
        if (backtracks)
            risks.push("output backtracks");
        if (minY < -0.001 || maxY > 1.001)
            risks.push("value overshoot");

        return risks.length > 0 ? risks.join(" · ") : "safe";
    }

    function curveRiskColor(curve) {
        return page.curveRiskText(curve) === "safe"
            ? (page.theme ? page.theme.textSecondary : "#721d1d1f")
            : (page.theme ? page.theme.danger : "#ff453a");
    }

    function springParams(action) {
        return {
            "damping": page.animValue(action, "damping_ratio"),
            "stiffness": page.animValue(action, "stiffness"),
            "epsilon": page.animValue(action, "epsilon")
        };
    }

    function springValueAt(params, seconds) {
        var dampingRatio = Math.max(0, Number(params.damping) || 0);
        var stiffness = Math.max(0, Number(params.stiffness) || 0);

        var mass = 1;
        var damping = dampingRatio * 2 * Math.sqrt(mass * stiffness);
        var beta = damping / (2 * mass);
        var omega0 = Math.sqrt(stiffness / mass);
        var x0 = -1;
        var v0 = 0;
        var t = Math.max(0, Number(seconds) || 0);
        var envelope = Math.exp(-beta * t);
        var value;

        if (Math.abs(beta - omega0) <= page.f32Epsilon) {
            value = 1 + envelope * (x0 + (beta * x0 + v0) * t);
        } else if (beta < omega0) {
            var omega1 = Math.sqrt((omega0 * omega0) - (beta * beta));
            value = 1 + envelope * (x0 * Math.cos(omega1 * t)
                + ((beta * x0 + v0) / omega1) * Math.sin(omega1 * t));
        } else {
            var omega2 = Math.sqrt((beta * beta) - (omega0 * omega0));
            var cosh = (Math.exp(omega2 * t) + Math.exp(-omega2 * t)) / 2;
            var sinh = (Math.exp(omega2 * t) - Math.exp(-omega2 * t)) / 2;
            value = 1 + envelope * (x0 * cosh + ((beta * x0 + v0) / omega2) * sinh);
        }

        return isFinite(value) ? value : 1;
    }

    function springDurationSeconds(params) {
        var dampingRatio = Math.max(0, Number(params.damping) || 0);
        var stiffness = Math.max(0, Number(params.stiffness) || 0);
        var epsilon = Math.max(0.00001, Number(params.epsilon) || 0.0001);
        var damping = dampingRatio * 2 * Math.sqrt(stiffness);
        var beta = damping / 2;
        var omega0 = Math.sqrt(stiffness);
        if (beta <= page.f64Epsilon || stiffness <= page.f64Epsilon)
            return 3;

        var x0 = -Math.log(epsilon) / beta;
        if (Math.abs(beta - omega0) <= page.f32Epsilon || beta < omega0)
            return x0;

        var y0 = page.springValueAt(params, x0);
        var m = (page.springValueAt(params, x0 + 0.001) - y0) / 0.001;
        if (Math.abs(m) <= 1e-9)
            return x0;

        var x1 = (1 - y0 + m * x0) / m;
        var y1 = page.springValueAt(params, x1);
        for (var i = 0; i <= 1000 && Math.abs(1 - y1) > epsilon; i++) {
            x0 = x1;
            y0 = y1;
            m = (page.springValueAt(params, x0 + 0.001) - y0) / 0.001;
            if (Math.abs(m) <= 1e-9)
                break;
            x1 = (1 - y0 + m * x0) / m;
            y1 = page.springValueAt(params, x1);
            if (!isFinite(y1))
                return Math.max(0, x0);
        }

        return Math.max(0, isFinite(x1) ? x1 : x0);
    }

    function springClampedDurationSeconds(params) {
        var epsilon = Math.max(0.00001, Number(params.epsilon) || 0.0001);
        var y = page.springValueAt(params, 0.001);
        for (var i = 1; i <= 3000 && 1 - y > epsilon; i++)
            y = page.springValueAt(params, i / 1000);
        return Math.min(3, Math.max(0.001, i / 1000));
    }

    function springOvershootPercent(params) {
        var duration = Math.min(3, Math.max(0.25, page.springDurationSeconds(params)));
        var maxY = 0;
        for (var i = 0; i <= 200; i++)
            maxY = Math.max(maxY, page.springValueAt(params, duration * i / 200));
        return Math.max(0, (maxY - 1) * 100);
    }

    function springSummaryText(action) {
        var params = page.springParams(action);
        var reachMs = Math.round(page.springClampedDurationSeconds(params) * 1000);
        var settleMs = Math.round(page.springDurationSeconds(params) * 1000);
        var overshoot = page.roundTo(page.springOvershootPercent(params), 1);
        return "reach " + reachMs + "ms · settle " + settleMs + "ms · overshoot " + overshoot + "%";
    }

    function springRiskText(action) {
        var params = page.springParams(action);
        var risks = [];
        if (params.damping < 1)
            risks.push("overshoot risk");
        if (params.damping > 1.4)
            risks.push("overdamped");
        if (page.springDurationSeconds(params) > 1)
            risks.push("long settle");
        return risks.length > 0 ? risks.join(" · ") : "critically controlled";
    }

    function profileSummary(profile) {
        switch (profile) {
        case "fast":
            return "短反馈：写入更短的 layer duration、spring stiffness 和 QML token profile";
        case "liquid":
            return "更长空间运动：保留快速透明度，增加 surface transform 时间";
        case "reduced":
            return "保守回退：layer transform 归零，保留必要 opacity feedback";
        case "balanced":
            return "默认平衡：Tahoe 当前 KDL/QML token timing，可作为回退基线";
        case "custom":
            return "当前 KDL 参数不完全匹配内置 profile；选择任一 profile 可回写";
        default:
            return "读取 profile 中";
        }
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "面板显隐动画"

            Controls.TahoeListRow {
                theme: page.theme
                label: "使用 compositor layer 动画"
                detail: "默认开启：Tahoe surface 的打开/关闭由 niri 统一处理；关闭时外层显隐即时完成，内部按钮、列表和切页动画仍由 QML 处理。"
                iconCode: "\ue8d1"
                checkable: true
                checked: page.svc && page.svc.layerAnimationsEnabled
                enabled: page.ready
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setLayerAnimationsEnabled(checked);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "Motion profile"
            subtitle: page.profileSummary(page.svc ? page.svc.motionProfile : "")

            Controls.TahoeSegmented {
                theme: page.theme
                model: page.svc ? page.svc.motionProfileModel : []
                value: page.svc && page.svc.motionProfile !== "custom" ? page.svc.motionProfile : ""
                enabled: page.ready
                onSelected: function(value) {
                    if (page.svc)
                        page.svc.setMotionProfile(value);
                }
            }

            Text {
                Layout.fillWidth: true
                text: "edge-reveal 按 surface 宽/高完成 reveal/retract；KDL distance 仅为兼容保留，不是短滑动距离调参。"
                color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: page.svc && page.svc.motionProfile === "custom"
                text: "custom"
                color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !page.ready || (page.svc && page.svc.lastError.length > 0)
            text: !page.svc ? "niri 设置服务不可用"
                : !page.svc.loaded ? "正在读取 niri 配置…"
                : page.svc.lastError
            color: page.svc && page.svc.lastError.length > 0
                ? (page.theme ? page.theme.danger : "#ff453a")
                : (page.theme ? page.theme.textSecondary : "#721d1d1f")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "曲线预览"
            subtitle: page.curveSpecText(page.selectedCurve())

            Canvas {
                id: curveCanvas

                Layout.fillWidth: true
                Layout.preferredHeight: 160

                onPaint: {
                    var ctx = getContext("2d");
                    var w = width;
                    var h = height;
                    var pad = 18;
                    var graphW = Math.max(1, w - pad * 2);
                    var graphH = Math.max(1, h - pad * 2);
                    var curve = page.selectedCurve();

                    ctx.clearRect(0, 0, w, h);
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = page.theme ? page.theme.rowStroke : "#30ffffff";
                    ctx.beginPath();
                    for (var grid = 0; grid <= 4; grid++) {
                        var gx = pad + graphW * grid / 4;
                        var gy = pad + graphH * grid / 4;
                        ctx.moveTo(gx, pad);
                        ctx.lineTo(gx, pad + graphH);
                        ctx.moveTo(pad, gy);
                        ctx.lineTo(pad + graphW, gy);
                    }
                    ctx.stroke();

                    ctx.lineWidth = 2;
                    ctx.strokeStyle = page.theme ? page.theme.accentBlue : "#007ff7";
                    ctx.beginPath();
                    for (var i = 0; i <= 120; i++) {
                        var x = i / 120;
                        var y = page.curveY(curve, x);
                        var px = pad + x * graphW;
                        var py = pad + (1 - y) * graphH;
                        if (i === 0)
                            ctx.moveTo(px, py);
                        else
                            ctx.lineTo(px, py);
                    }
                    ctx.stroke();

                    ctx.fillStyle = page.theme ? page.theme.accentBlue : "#007ff7";
                    for (var mark = 1; mark <= 3; mark++) {
                        var mx = mark / 4;
                        var my = page.curveY(curve, mx);
                        ctx.beginPath();
                        ctx.arc(pad + mx * graphW, pad + (1 - my) * graphH, 3, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: page.curvePointText(page.selectedCurve()) + " · " + page.curveVelocityText(page.selectedCurve())
                color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: "risk: " + page.curveRiskText(page.selectedCurve())
                color: page.curveRiskColor(page.selectedCurve())
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: page.namedCurveModel

                    delegate: Rectangle {
                        id: curveRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 8
                        color: page.selectedCurveName === modelData.name
                            ? (page.theme ? page.theme.sidebarActiveFill : "#407dcfff")
                            : (curveMouse.containsMouse ? (page.theme ? page.theme.rowFillHover : "#40ffffff") : "transparent")
                        border.color: page.selectedCurveName === modelData.name
                            ? (page.theme ? page.theme.accentBlue : "#007ff7")
                            : (page.theme ? page.theme.rowStroke : "#24ffffff")
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.preferredWidth: 132
                                text: curveRow.modelData.label
                                color: page.theme ? page.theme.textPrimary : "#1d1d1f"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: page.curveSpecText(curveRow.modelData) + " · " + curveRow.modelData.use
                                color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.preferredWidth: 104
                                text: page.curveRiskText(curveRow.modelData)
                                color: page.curveRiskColor(curveRow.modelData)
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        MouseArea {
                            id: curveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.selectedCurveName = String(curveRow.modelData.name)
                        }
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "Spring response"
            subtitle: page.springSummaryText(page.selectedSpringAction)

            Controls.TahoeSegmented {
                theme: page.theme
                model: page.springActionModel
                value: page.selectedSpringAction
                onSelected: function(value) {
                    page.selectedSpringAction = value;
                }
            }

            Canvas {
                id: springCanvas

                Layout.fillWidth: true
                Layout.preferredHeight: 150

                Connections {
                    target: page.svc
                    ignoreUnknownSignals: true

                    function onAnimSpringsChanged() {
                        springCanvas.requestPaint();
                    }
                }

                onPaint: {
                    var ctx = getContext("2d");
                    var w = width;
                    var h = height;
                    var pad = 18;
                    var graphW = Math.max(1, w - pad * 2);
                    var graphH = Math.max(1, h - pad * 2);
                    var params = page.springParams(page.selectedSpringAction);
                    var duration = Math.min(3, Math.max(0.25, page.springDurationSeconds(params)));
                    var minY = 0;
                    var maxY = 1;

                    for (var i = 0; i <= 160; i++) {
                        var sample = page.springValueAt(params, duration * i / 160);
                        minY = Math.min(minY, sample);
                        maxY = Math.max(maxY, sample);
                    }
                    var span = Math.max(0.1, maxY - minY);
                    minY -= span * 0.12;
                    maxY += span * 0.12;
                    span = Math.max(0.1, maxY - minY);

                    function sx(t) {
                        return pad + (t / duration) * graphW;
                    }
                    function sy(y) {
                        return pad + (1 - ((y - minY) / span)) * graphH;
                    }

                    ctx.clearRect(0, 0, w, h);
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = page.theme ? page.theme.rowStroke : "#30ffffff";
                    ctx.beginPath();
                    for (var grid = 0; grid <= 4; grid++) {
                        var gx = pad + graphW * grid / 4;
                        ctx.moveTo(gx, pad);
                        ctx.lineTo(gx, pad + graphH);
                    }
                    ctx.moveTo(pad, sy(0));
                    ctx.lineTo(pad + graphW, sy(0));
                    ctx.moveTo(pad, sy(1));
                    ctx.lineTo(pad + graphW, sy(1));
                    ctx.stroke();

                    ctx.lineWidth = 2;
                    ctx.strokeStyle = page.theme ? page.theme.accentBlue : "#007ff7";
                    ctx.beginPath();
                    for (var step = 0; step <= 180; step++) {
                        var t = duration * step / 180;
                        var y = page.springValueAt(params, t);
                        if (step === 0)
                            ctx.moveTo(sx(t), sy(y));
                        else
                            ctx.lineTo(sx(t), sy(y));
                    }
                    ctx.stroke();
                }
            }

            Text {
                Layout.fillWidth: true
                text: page.springRiskText(page.selectedSpringAction)
                color: page.springRiskText(page.selectedSpringAction) === "critically controlled"
                    ? (page.theme ? page.theme.textSecondary : "#721d1d1f")
                    : (page.theme ? page.theme.danger : "#ff453a")
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "工作区切换（workspace-switch）"
            subtitle: "切换虚拟工作区时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("workspace_switch", "damping_ratio")
                value: page.dampingFromValue(page.animValue("workspace_switch", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("workspace_switch", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("workspace_switch", "stiffness")
                value: page.stiffnessFromValue(page.animValue("workspace_switch", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("workspace_switch", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("workspace_switch", "epsilon")
                value: page.epsilonFromValue(page.animValue("workspace_switch", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("workspace_switch", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口移动（window-movement）"
            subtitle: "拖动窗口跟随指针时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("window_movement", "damping_ratio")
                value: page.dampingFromValue(page.animValue("window_movement", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_movement", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("window_movement", "stiffness")
                value: page.stiffnessFromValue(page.animValue("window_movement", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_movement", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("window_movement", "epsilon")
                value: page.epsilonFromValue(page.animValue("window_movement", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_movement", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口缩放（window-resize）"
            subtitle: "调整窗口大小时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("window_resize", "damping_ratio")
                value: page.dampingFromValue(page.animValue("window_resize", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_resize", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("window_resize", "stiffness")
                value: page.stiffnessFromValue(page.animValue("window_resize", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_resize", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("window_resize", "epsilon")
                value: page.epsilonFromValue(page.animValue("window_resize", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_resize", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "概览开关（overview-open-close）"
            subtitle: "打开/关闭窗口概览时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("overview_open_close", "damping_ratio")
                value: page.dampingFromValue(page.animValue("overview_open_close", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("overview_open_close", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("overview_open_close", "stiffness")
                value: page.stiffnessFromValue(page.animValue("overview_open_close", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("overview_open_close", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("overview_open_close", "epsilon")
                value: page.epsilonFromValue(page.animValue("overview_open_close", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("overview_open_close", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "这些选项写入 niri 的 config.kdl 并在写入后立即热重载，重启 niri 后仍然生效。窗口打开/关闭动画使用自定义着色器，此处不提供修改。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
