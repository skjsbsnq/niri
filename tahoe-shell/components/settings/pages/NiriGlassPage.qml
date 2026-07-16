pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// S5.1: tahoe-glass materials + global blur. Material fields write through
// NiriSettings.setGlassField (optimistic object update + queued KDL write +
// hot-reload); blur fields go through setBlurX. Ranges follow the niri schema:
// edge-highlight [0,2], refraction [0,0.12], inner-shadow [0,0.5],
// chromatic [0,0.1], lens-depth [0,0.3]. xray is intentionally not exposed;
// the compositor material profile owns the shared/live sampling strategy.
Flickable {
    id: page

    property var panel
    property var theme
    property string material: "panel"

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded

    function glassValue(field) {
        if (!page.svc || !page.svc.glassMaterials)
            return 0;
        var entry = page.svc.glassMaterials[page.material];
        var value = entry ? entry[field] : 0;
        return isFinite(value) ? value : 0;
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

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
            title: "全局模糊"
            subtitle: "所有玻璃材质背后的模糊核"

            Controls.TahoeListRow {
                theme: page.theme
                label: "启用模糊"
                detail: page.svc && page.svc.blurEnabled ? "已开启" : "关闭"
                iconCode: "\e3a4"
                checkable: true
                checked: page.svc ? page.svc.blurEnabled : true
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setBlurEnabled(c);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e3d3"
                label: "模糊次数（passes）"
                valueText: page.svc ? page.svc.blurPasses : ""
                value: page.svc ? Math.max(0, Math.min(1, page.svc.blurPasses / 10)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setBlurPasses(Math.round(v * 10));
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e429"
                label: "偏移（offset）"
                valueText: page.svc ? page.svc.blurOffset : ""
                value: page.svc ? Math.max(0, Math.min(1, page.svc.blurOffset / 100)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setBlurOffset(v * 100);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e268"
                label: "噪点（noise）"
                valueText: page.svc ? page.svc.blurNoise : ""
                value: page.svc ? Math.max(0, Math.min(1, page.svc.blurNoise / 0.1)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setBlurNoise(v * 0.1);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e40a"
                label: "饱和度（saturation）"
                valueText: page.svc ? page.svc.blurSaturation : ""
                value: page.svc ? Math.max(0, Math.min(1, page.svc.blurSaturation / 3)) : 0.5
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setBlurSaturation(v * 3);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "材质"
            subtitle: "每种 Tahoe 玻璃材质的折射、边缘光与色散"

            Controls.TahoeSegmented {
                theme: page.theme
                Layout.fillWidth: true
                value: page.material
                model: [
                    { value: "panel", label: "面板" },
                    { value: "pill", label: "胶囊" },
                    { value: "launcher", label: "启动器" },
                    { value: "dock", label: "Dock" },
                    { value: "menu", label: "菜单" },
                    { value: "toast", label: "通知" },
                    { value: "backdrop", label: "背景" }
                ]
                onSelected: function(value) {
                    page.material = value;
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e3e4"
                label: "边缘高光（edge-highlight）"
                valueText: page.glassValue("edge_highlight")
                value: Math.max(0, Math.min(1, page.glassValue("edge_highlight") / 2))
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setGlassField(page.material, "edge_highlight", v * 2);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e84d"
                label: "折射（refraction）"
                valueText: page.glassValue("refraction")
                value: Math.max(0, Math.min(1, page.glassValue("refraction") / 0.12))
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setGlassField(page.material, "refraction", v * 0.12);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e892"
                label: "内阴影（inner-shadow）"
                valueText: page.glassValue("inner_shadow")
                value: Math.max(0, Math.min(1, page.glassValue("inner_shadow") / 0.5))
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setGlassField(page.material, "inner_shadow", v * 0.5);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e65f"
                label: "色散（chromatic）"
                valueText: page.glassValue("chromatic")
                value: Math.max(0, Math.min(1, page.glassValue("chromatic") / 0.1))
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setGlassField(page.material, "chromatic", v * 0.1);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e8f5"
                label: "透镜深度（lens-depth）"
                valueText: page.glassValue("lens_depth")
                value: Math.max(0, Math.min(1, page.glassValue("lens_depth") / 0.3))
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setGlassField(page.material, "lens_depth", v * 0.3);
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "这些选项写入 niri 的 config.kdl 并在写入后立即热重载，重启 niri 后仍然生效。采样策略由材质配置统一管理。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
