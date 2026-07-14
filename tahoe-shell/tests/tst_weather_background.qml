import QtQuick
import QtTest
import "../components" as Components

TestCase {
    id: testCase
    name: "WeatherBackgroundLoad"
    when: windowShown

    Component {
        id: weatherBackgroundComponent
        Components.WeatherBackground {
            width: 320
            height: 180
            weatherCode: 0
            night: false
            animate: false
            darkMode: false
        }
    }

    function test_weather_background_loads_with_shared_motion_easing() {
        var item = createTemporaryObject(weatherBackgroundComponent, testCase);
        verify(item !== null, "WeatherBackground must instantiate");
        compare(item.width, 320);
        compare(item.height, 180);
        compare(item.weatherType, "clear");
        // pointer properties exist and stay finite after load
        verify(isFinite(item.pointerX));
        verify(isFinite(item.pointerY));
        // Parallax derives from pointer without requiring FrameAnimation
        verify(isFinite(item.parallaxX));
        verify(isFinite(item.parallaxY));
    }
}
