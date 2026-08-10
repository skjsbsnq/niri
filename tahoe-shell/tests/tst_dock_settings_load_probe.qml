import QtQuick
import QtTest
import "../services" as Services

// D2 load probe: DesktopSettings must instantiate in a real QML engine.
// Static text guards cannot catch load-time rejections such as
// "Property names cannot begin with an upper case letter", and that failure
// takes the entire shell down at startup.
TestCase {
    id: testCase
    name: "DockSettingsLoadProbe"
    when: windowShown

    Services.DesktopSettings {
        id: settings
    }

    function test_settings_component_loaded() {
        verify(settings !== null, "DesktopSettings failed to instantiate");
    }

    function test_slider_bounds_are_readable_and_sane() {
        verify(settings.dockSurfaceHeightMin < settings.dockSurfaceHeightMax);
        verify(settings.dockIconSizeMin < settings.dockIconSizeMax);
        // Defaults must sit inside their own range.
        verify(settings.dockSurfaceHeightDefault >= settings.dockSurfaceHeightMin);
        verify(settings.dockSurfaceHeightDefault <= settings.dockSurfaceHeightMax);
        verify(settings.dockIconSizeDefault >= settings.dockIconSizeMin);
        verify(settings.dockIconSizeDefault <= settings.dockIconSizeMax);
        // The compact preset must also be reachable by the sliders.
        verify(settings.dockCompactSurfaceHeight >= settings.dockSurfaceHeightMin);
        verify(settings.dockCompactIconSize >= settings.dockIconSizeMin);
    }

    function test_setters_exist() {
        verify(typeof settings.setDockSurfaceHeightPx === "function");
        verify(typeof settings.setDockIconSizePx === "function");
        verify(typeof settings.setDockCompact === "function");
    }
}
