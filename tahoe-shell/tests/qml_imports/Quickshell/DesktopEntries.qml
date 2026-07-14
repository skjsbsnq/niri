pragma Singleton
import QtQml

// Minimal DesktopEntries fake for production Apps.qml under qmltestrunner.
// Apps reads DesktopEntries.applications.values and listens to applicationsChanged.
// Do not declare an explicit applicationsChanged signal: the applications property
// already owns that change signal name.
QtObject {
    id: root

    property var applications: ({ "values": [] })

    function reset() {
        applications = { "values": [] };
    }

    function setApplications(entries) {
        var list = Array.isArray(entries) ? entries.slice() : [];
        // Reassign the property so applicationsChanged fires for Connections.
        applications = { "values": list };
    }

    function replaceApplicationsSilent(entries) {
        // Mutate nested values without reassigning applications — no change signal.
        var list = Array.isArray(entries) ? entries.slice() : [];
        if (!applications)
            applications = { "values": list };
        else
            applications.values = list;
    }
}
