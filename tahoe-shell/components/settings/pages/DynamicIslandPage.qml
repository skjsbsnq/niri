pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme
    readonly property var svc: panel ? panel.settingsService : null
    readonly property bool ready: !!svc

    function actionLabel(action) {
        return page.svc ? page.svc.dynamicIslandClickActionLabel(action) : "";
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "灵动岛"
            subtitle: "顶栏时间、点击行为和展开偏好"

            Controls.TahoeListRow {
                theme: page.theme
                label: "启用灵动岛"
                detail: page.svc && page.svc.dynamicIslandEnabled
                    ? "顶栏中心由灵动岛接管"
                    : "使用可读时间胶囊作为 fallback"
                iconCode: "\ueb81"
                checkable: true
                checked: page.svc && page.svc.dynamicIslandEnabled
                enabled: page.ready
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setDynamicIslandEnabled(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "隐藏旧顶栏时间"
                detail: page.svc && page.svc.dynamicIslandHideTopbarTime
                    ? "resting 状态由 overlay 胶囊显示"
                    : "顶栏保留时间胶囊，动态内容只在 overlay 出现"
                iconCode: "\ue8b5"
                checkable: true
                checked: page.svc && page.svc.dynamicIslandHideTopbarTime
                enabled: page.ready && page.svc && page.svc.dynamicIslandEnabled
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setDynamicIslandHideTopbarTime(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "自动媒体展开"
                detail: page.svc && page.svc.dynamicIslandAutoExpandMedia
                    ? "检测到媒体时自动展开一次"
                    : "媒体只进入 resting 状态，点击后展开"
                iconCode: "\ue037"
                checkable: true
                checked: page.svc && page.svc.dynamicIslandAutoExpandMedia
                enabled: page.ready && page.svc && page.svc.dynamicIslandEnabled
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setDynamicIslandAutoExpandMedia(checked);
                }
            }


            Controls.TahoeListRow {
                theme: page.theme
                label: "工作区反馈"
                detail: page.svc && page.svc.dynamicIslandWorkspaceFeedback
                    ? "切换工作区时在灵动岛显示短暂反馈"
                    : "顶栏工作区已可见，默认不在岛上重复"
                iconCode: "\ue1b1"
                checkable: true
                checked: page.svc && page.svc.dynamicIslandWorkspaceFeedback
                enabled: page.ready && page.svc && page.svc.dynamicIslandEnabled
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setDynamicIslandWorkspaceFeedback(checked);
                }
            }
            Controls.TahoeListRow {
                theme: page.theme
                label: "悬停展开"
                detail: page.svc && page.svc.dynamicIslandHoverExpand
                    ? "350 ms 后展开，离开后 250 ms 收起"
                    : "只通过点击和手势展开"
                iconCode: "\ue8b6"
                checkable: true
                checked: page.svc && page.svc.dynamicIslandHoverExpand
                enabled: page.ready && page.svc && page.svc.dynamicIslandEnabled
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setDynamicIslandHoverExpand(checked);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "点击行为"
            subtitle: "左键和右键分别选择一个动作"

            Controls.TahoeListRow {
                theme: page.theme
                label: "左键"
                detail: page.svc ? page.actionLabel(page.svc.dynamicIslandLeftClickAction) : "设置服务不可用"
                iconCode: "\ue5cb"
                enabled: page.ready && page.svc && page.svc.dynamicIslandEnabled

                Controls.TahoeSegmented {
                    theme: page.theme
                    Layout.preferredWidth: Math.max(220, Math.min(360, page.width - 190))
                    value: page.svc ? page.svc.dynamicIslandLeftClickAction : "toggle_media"
                    model: [
                        { value: "toggle_media", label: "媒体" },
                                                { value: "notifications", label: "通知" },
                        { value: "control_center", label: "控制" },
                        { value: "none", label: "无" }
                    ]
                    onSelected: function(value) {
                        if (page.svc)
                            page.svc.setDynamicIslandLeftClickAction(value);
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "右键"
                detail: page.svc ? page.actionLabel(page.svc.dynamicIslandRightClickAction) : "设置服务不可用"
                iconCode: "\ue5cc"
                enabled: page.ready && page.svc && page.svc.dynamicIslandEnabled

                Controls.TahoeSegmented {
                    theme: page.theme
                    Layout.preferredWidth: Math.max(220, Math.min(360, page.width - 190))
                    value: page.svc ? page.svc.dynamicIslandRightClickAction : "control_center"
                    model: [
                        { value: "control_center", label: "控制" },
                        { value: "notifications", label: "通知" },
                                                { value: "toggle_media", label: "媒体" },
                        { value: "none", label: "无" }
                    ]
                    onSelected: function(value) {
                        if (page.svc)
                            page.svc.setDynamicIslandRightClickAction(value);
                    }
                }
            }
        }
    }
}
