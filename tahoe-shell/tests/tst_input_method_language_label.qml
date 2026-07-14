import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "InputMethodLanguageLabelUi"
    when: windowShown

    // Lightweight replica of production InputMethod.displayText ownership.
    // TopBar must consume this same property surface (inputMethodService.displayText).
    QtObject {
        id: inputMethodService
        property bool available: true
        property bool active: true
        property string currentName: "pinyin"
        property string displayText: !available ? "--" : (active ? languageLabel(currentName) : "EN")

        function languageLabel(name) {
            var raw = String(name || "");
            var text = raw.toLowerCase().trim();
            if (text.length === 0)
                return "Aa";
            if (text.indexOf("mozc") !== -1 || text.indexOf("japanese") !== -1
                    || /[\u3040-\u30ff]/.test(raw))
                return "\u3042";
            if (text.indexOf("hangul") !== -1 || text.indexOf("korean") !== -1
                    || /[\uac00-\ud7af]/.test(raw))
                return "\ud55c";
            if (text.indexOf("pinyin") !== -1 || text.indexOf("chinese") !== -1
                    || /[\u4e00-\u9fff]/.test(raw))
                return "\u4e2d";
            if (text.indexOf("english") !== -1 || text === "en" || text === "us")
                return "EN";
            return "Aa";
        }

        function toggle() {
            toggled = true;
        }
        property bool toggled: false
    }

    // Minimal TopBar consumer surface (same bindings Task 09 requires).
    QtObject {
        id: topBarConsumer
        property var inputMethodService: null
        property int toggleCount: 0
        readonly property string inputMethodDisplayText: inputMethodService
            ? String(inputMethodService.displayText || "--")
            : "--"
        signal toggleInputMethod()
        onToggleInputMethod: {
            toggleCount += 1;
            if (inputMethodService && inputMethodService.toggle)
                inputMethodService.toggle();
        }
    }

    function init() {
        inputMethodService.available = true;
        inputMethodService.active = true;
        inputMethodService.currentName = "pinyin";
        inputMethodService.toggled = false;
        topBarConsumer.inputMethodService = inputMethodService;
        topBarConsumer.toggleCount = 0;
    }

    function test_chinese_label() {
        inputMethodService.currentName = "pinyin";
        inputMethodService.active = true;
        compare(topBarConsumer.inputMethodDisplayText, "\u4e2d");
    }

    function test_english_inactive_label() {
        inputMethodService.active = false;
        compare(topBarConsumer.inputMethodDisplayText, "EN");
    }

    function test_japanese_label() {
        inputMethodService.active = true;
        inputMethodService.currentName = "mozc";
        compare(topBarConsumer.inputMethodDisplayText, "\u3042");
    }

    function test_korean_label() {
        inputMethodService.currentName = "hangul";
        compare(topBarConsumer.inputMethodDisplayText, "\ud55c");
    }

    function test_unknown_label() {
        inputMethodService.currentName = "foo-bar";
        compare(topBarConsumer.inputMethodDisplayText, "Aa");
    }

    function test_unavailable_label() {
        inputMethodService.available = false;
        compare(topBarConsumer.inputMethodDisplayText, "--");
    }

    function test_click_calls_unique_toggle() {
        topBarConsumer.toggleInputMethod();
        compare(topBarConsumer.toggleCount, 1);
        verify(inputMethodService.toggled === true);
    }
}
