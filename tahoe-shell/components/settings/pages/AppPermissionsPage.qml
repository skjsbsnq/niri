pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../controls" as Controls
import "../.."

Flickable {
    id: page

    property var panel
    property var theme
    property var app
    property var appsSettingsService

    readonly property int serviceRevision: appsSettingsService ? appsSettingsService.revision : 0
    readonly property var permissions: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.permissionItems : []
    readonly property var staticPermissions: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.staticPermissionItems : []
    readonly property var snapConnections: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.snapConnectionItems : []
    readonly property var storageInfo: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.storageInfo : ({ "total": "0 B", "items": [] })
    readonly property var sandbox: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.sandboxInfo : ({})
    readonly property var permissionCapability: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.permissionCapability : ({})
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"
    readonly property color danger: theme ? theme.danger : "#ff453a"

    signal backRequested()

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    onAppChanged: {
        if (page.app && page.appsSettingsService)
            page.appsSettingsService.selectApp(page.app);
    }

    function appName() {
        return page.appsSettingsService && page.app ? page.appsSettingsService.appLabel(page.app) : "应用";
    }

    function appSubtitle() {
        return page.appsSettingsService && page.app ? page.appsSettingsService.appGenericName(page.app) : "";
    }

    function desktopId() {
        if (!page.appsSettingsService)
            return "";
        return page.appsSettingsService.selectedDesktopId || page.appsSettingsService.desktopIdForApp(page.app);
    }

    function sandboxTitle() {
        var type = String(page.sandbox.type || "unknown");
        if (type === "flatpak")
            return "Flatpak sandbox";
        if (type === "snap")
            return "Snap sandbox";
        if (type === "none")
            return "普通桌面应用";
        return "Sandbox 状态未知";
    }

    function sandboxDetail() {
        var id = String(page.sandbox.id || "");
        var type = String(page.sandbox.type || "unknown");
        if (type === "flatpak" || type === "snap")
            return id.length > 0 ? id : "sandbox 应用";
        if (type === "none")
            return "权限不能被 Tahoe 完整强制执行";
        return "未识别 sandbox 元数据";
    }

    function portalDetail() {
        if (!page.appsSettingsService)
            return "应用设置服务不可用";
        if (page.appsSettingsService.permissionsRefreshing)
            return "正在读取 portal permission store";
        return page.appsSettingsService.permissionDetail;
    }

    function permissionStatusText(status) {
        if (status === "allowed")
            return "允许";
        if (status === "denied")
            return "拒绝";
        if (status === "unrecorded")
            return "未记录";
        if (status === "unavailable")
            return "不可用";
        return "未知";
    }

    function permissionIcon(status) {
        if (status === "allowed")
            return "\ue5ca";
        if (status === "denied")
            return "\ue14b";
        if (status === "unrecorded")
            return "\ue88e";
        if (status === "unavailable")
            return "\ue002";
        return "\ue8b8";
    }

    function ordinaryWarningVisible() {
        if (page.permissionCapability && typeof page.permissionCapability.ordinaryAppWarning !== "undefined")
            return page.permissionCapability.ordinaryAppWarning === true;
        return String(page.sandbox.type || "") === "none";
    }

    function controlRangeDetail() {
        if (page.ordinaryWarningVisible())
            return "普通桌面应用只显示 portal 记录；系统无法完整强制限制";
        if (page.permissionCapability && page.permissionCapability.canTogglePortalPermissions === true)
            return "portal 权限可在 Tahoe 中切换";
        if (page.permissionCapability && String(page.permissionCapability.writeScope || "none") === "none")
            return "Tahoe 当前只读展示权限记录和运行时静态权限";
        return "权限控制能力由应用 sandbox 和 portal 状态决定";
    }

    function controlText(entry) {
        if (entry && entry.canToggle === true)
            return "可切换";

        var control = String(entry && (entry.control || entry.presentation) ? (entry.control || entry.presentation) : "readonly");
        if (control === "external")
            return "外部";
        if (control === "warning")
            return "警告";
        return "只读";
    }

    function permissionRowDetail(entry) {
        var detail = String(entry && entry.detail ? entry.detail : "");
        var reason = String(entry && entry.readOnlyReason ? entry.readOnlyReason : "");
        if (reason.length === 0 || detail.indexOf(reason) >= 0)
            return detail;
        if (detail.length === 0)
            return reason;
        return detail + "；" + reason;
    }

    function permissionRowStatusText(entry) {
        if (!entry)
            return "";
        return page.controlText(entry) + " · " + page.permissionStatusText(entry.status);
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: page.appName()
            subtitle: page.appSubtitle()

            Controls.TahoeListRow {
                theme: page.theme
                label: page.appName()
                detail: page.desktopId()
                iconCode: "\ue5c3"

                Image {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: page.appsSettingsService && page.app ? page.appsSettingsService.iconForApp(page.app) : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    sourceSize.width: 80
                    sourceSize.height: 80
                    asynchronous: true
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "返回"
                    iconCode: "\ue5cb"
                    onActivated: page.backRequested()
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    iconCode: "\ue89e"
                    enabled: !!(page.appsSettingsService && page.app)
                    onActivated: page.appsSettingsService.launchApp(page.app)
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "应用权限"
            subtitle: page.portalDetail()

            Controls.TahoeListRow {
                theme: page.theme
                label: page.sandboxTitle()
                detail: page.sandboxDetail()
                iconCode: page.sandbox && page.sandbox.fullyEnforceable ? "\ue897" : "\ue002"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "权限控制范围"
                detail: page.controlRangeDetail()
                iconCode: "\ue002"
                visible: page.ordinaryWarningVisible()
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "Portal Permission Store"
                detail: page.portalDetail()
                iconCode: page.appsSettingsService && page.appsSettingsService.permissionStatus === "ok" ? "\ue5ca" : "\ue002"

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.appsSettingsService && page.appsSettingsService.permissionsRefreshing ? "读取中" : "刷新"
                    iconCode: "\ue5d5"
                    enabled: !!page.appsSettingsService && !page.appsSettingsService.permissionsRefreshing
                    onActivated: page.appsSettingsService.refreshPermissions()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "无权限记录"
                detail: page.portalDetail()
                iconCode: "\ue8b6"
                visible: page.permissions.length === 0
            }

            Repeater {
                model: ScriptModel {
                    values: page.permissions
                }

                delegate: PermissionRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    detailText: page.permissionRowDetail(modelData)
                    statusText: page.permissionRowStatusText(modelData)
                    iconCode: page.permissionIcon(modelData.status)
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "静态权限"
            subtitle: "Flatpak metadata 和 Snap connections"

            Controls.TahoeListRow {
                theme: page.theme
                label: "Flatpak 静态权限"
                detail: page.staticPermissions.length === 0
                    ? "不是 Flatpak 应用，或未声明额外静态权限"
                    : page.staticPermissions.length + " 条静态权限"
                iconCode: "\ue897"
            }

            Repeater {
                model: ScriptModel {
                    values: page.staticPermissions
                }

                delegate: PermissionRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    detailText: page.permissionRowDetail(modelData)
                    statusText: page.controlText(modelData) + " · " + String(modelData.status || "")
                    iconCode: "\ue897"
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "Snap connections"
                detail: page.snapConnections.length === 0
                    ? "不是 Snap 应用，或没有可读取连接"
                    : page.snapConnections.length + " 条连接"
                iconCode: "\ue897"
            }

            Repeater {
                model: ScriptModel {
                    values: page.snapConnections
                }

                delegate: PermissionRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    detailText: page.permissionRowDetail(modelData)
                    statusText: page.controlText(modelData) + " · " + String(modelData.status || "")
                    iconCode: "\ue897"
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "存储"
            subtitle: "应用数据、缓存和配置目录估算"

            Controls.TahoeListRow {
                theme: page.theme
                label: "总用量"
                detail: page.storageInfo ? String(page.storageInfo.total || "0 B") : "0 B"
                iconCode: "\ue2c7"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "未发现应用数据"
                detail: "没有找到常见 XDG、Flatpak 或 Snap 数据目录"
                iconCode: "\ue8b6"
                visible: !(page.storageInfo && page.storageInfo.items && page.storageInfo.items.length > 0)
            }

            Repeater {
                model: ScriptModel {
                    values: page.storageInfo && page.storageInfo.items ? page.storageInfo.items : []
                }

                delegate: StorageRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                }
            }
        }
    }

    component PermissionRow: Item {
        id: row

        property var theme
        property var entry
        property string statusText: ""
        property string iconCode: ""
        property string detailText: entry ? String(entry.detail || "") : ""

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"

        Layout.fillWidth: true
        Layout.preferredHeight: 50

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: row.rowFill
            border.color: row.rowStroke
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            TahoeSymbol {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                name: row.iconCode
                color: row.textPrimary
                size: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.title : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.detailText
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 120
                text: row.statusText
                color: row.textPrimary
                font.pixelSize: 11
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
    }

    component StorageRow: Item {
        id: row

        property var theme
        property var entry

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"

        Layout.fillWidth: true
        Layout.preferredHeight: 50

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: row.rowFill
            border.color: row.rowStroke
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            TahoeSymbol {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                name: "\ue2c7"
                color: row.textPrimary
                size: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.title : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.path : ""
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: row.entry ? row.entry.size : ""
                color: row.textPrimary
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
}
