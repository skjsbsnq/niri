import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "DynamicIslandSwipeClickSessionSuppress"
    when: windowShown

    // Production capsule MouseArea session-scoped suppress logic (Task 10),
    // extracted as a driver so we can assert press/release/click without
    // instantiating PanelWindow/Wayland Overlay.
    Item {
        id: capsule
        width: 200
        height: 40

        property int pointerSession: 0
        property int suppressClickSession: -1
        property int chipClicks: 0
        property int suppressMs: 180

        function suppressClickTemporarily() {
            suppressClickSession = pointerSession;
            swipeClickSuppress.restart();
        }

        function clickSuppressedForCurrentSession() {
            return suppressClickSession === pointerSession;
        }

        function press() {
            pointerSession += 1;
            suppressClickSession = -1;
            swipeClickSuppress.stop();
        }

        function releaseAfterSwipe() {
            suppressClickTemporarily();
        }

        function releaseAfterReject() {
            suppressClickTemporarily();
        }

        function click() {
            if (clickSuppressedForCurrentSession())
                return;
            chipClicks += 1;
        }

        Timer {
            id: swipeClickSuppress
            interval: capsule.suppressMs
            repeat: false
            onTriggered: {
                if (capsule.suppressClickSession === capsule.pointerSession)
                    capsule.suppressClickSession = -1;
            }
        }
    }

    function init() {
        capsule.pointerSession = 0;
        capsule.suppressClickSession = -1;
        capsule.chipClicks = 0;
    }

    function test_swipe_composed_click_suppressed() {
        capsule.press();
        capsule.releaseAfterSwipe();
        capsule.click();
        compare(capsule.chipClicks, 0);
    }

    function test_second_click_within_180ms_succeeds() {
        capsule.press();
        capsule.releaseAfterSwipe();
        capsule.click();
        compare(capsule.chipClicks, 0);

        // New press within the suppress window must start a fresh session.
        wait(50);
        capsule.press();
        capsule.click();
        compare(capsule.chipClicks, 1);
    }

    function test_vertical_reject_then_second_click() {
        capsule.press();
        capsule.releaseAfterReject();
        capsule.click();
        compare(capsule.chipClicks, 0);

        wait(50);
        capsule.press();
        capsule.click();
        compare(capsule.chipClicks, 1);
    }

    function test_cancel_does_not_sticky_suppress() {
        capsule.press();
        // Cancel without setting suppress for this session.
        capsule.suppressClickSession = -1;
        capsule.click();
        compare(capsule.chipClicks, 1);
    }

    function test_old_shared_bool_would_fail_second_click() {
        // Sticky boolean model (pre-Task-10).
        var sticky = false;
        function oldPress() { /* does not clear sticky */ }
        function oldReleaseSwipe() { sticky = true; }
        function oldClick() {
            if (sticky)
                return false;
            return true;
        }
        oldPress();
        oldReleaseSwipe();
        verify(oldClick() === false);
        oldPress();
        verify(oldClick() === false, "sticky bool must still block second click");
    }
}
