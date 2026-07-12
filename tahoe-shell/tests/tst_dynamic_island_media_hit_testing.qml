import QtQuick
import QtQuick.Window
import QtTest
import "../components" as Components

TestCase {
    id: testCase
    name: "DynamicIslandMediaHitTesting"
    when: windowShown

    property int capsuleClicks: 0
    property int previousRequests: 0
    property int playPauseRequests: 0
    property int nextRequests: 0
    property int interactionPresses: 0
    property int interactionReleases: 0

    Window {
        id: window
        width: 400
        height: 200
        visible: true

        Rectangle {
            anchors.fill: parent
            color: "black"

            Item {
                id: contentHost
                anchors.fill: parent
                z: 1

                Components.DynamicIslandMediaView {
                    id: media
                    anchors.fill: parent
                    canPrev: true
                    canPlayPause: true
                    canNext: true
                    onPreviousRequested: testCase.previousRequests += 1
                    onPlayPauseRequested: testCase.playPauseRequests += 1
                    onNextRequested: testCase.nextRequests += 1
                    onControlPressed: testCase.interactionPresses += 1
                    onControlReleased: testCase.interactionReleases += 1
                }
            }

            // Mirrors Overlay: this fill MouseArea is declared after content.
            MouseArea {
                anchors.fill: parent
                onClicked: testCase.capsuleClicks += 1
            }
        }
    }

    function resetCounts() {
        capsuleClicks = 0;
        previousRequests = 0;
        playPauseRequests = 0;
        nextRequests = 0;
        interactionPresses = 0;
        interactionReleases = 0;
        media.canPrev = true;
        media.canPlayPause = true;
        media.canNext = true;
        media.visible = true;
    }

    function init() {
        resetCounts();
        wait(0);
    }

    function test_enabled_buttons_fire_once_without_capsule_click() {
        mouseClick(window.contentItem, 116, 168, Qt.LeftButton);
        mouseClick(window.contentItem, 200, 168, Qt.LeftButton);
        mouseClick(window.contentItem, 284, 168, Qt.LeftButton);
        compare(previousRequests, 1);
        compare(playPauseRequests, 1);
        compare(nextRequests, 1);
        compare(capsuleClicks, 0);
        compare(interactionPresses, 3);
        compare(interactionReleases, 3);
    }

    function test_disabled_button_absorbs_without_action_or_capsule_click() {
        media.canPrev = false;
        wait(0);
        mouseClick(window.contentItem, 116, 168, Qt.LeftButton);
        compare(previousRequests, 0);
        compare(capsuleClicks, 0);
        compare(interactionPresses, 0);
        compare(interactionReleases, 0);
    }

    function test_blank_content_falls_through_to_capsule() {
        mouseClick(window.contentItem, 20, 100, Qt.LeftButton);
        compare(capsuleClicks, 1);
        compare(previousRequests, 0);
        compare(playPauseRequests, 0);
        compare(nextRequests, 0);
    }

    function test_hide_during_press_closes_interaction_lifecycle() {
        mousePress(window.contentItem, 200, 168, Qt.LeftButton);
        compare(playPauseRequests, 1);
        compare(interactionPresses, 1);
        compare(interactionReleases, 0);
        media.visible = false;
        wait(0);
        compare(interactionReleases, 1);
        mouseRelease(window.contentItem, 200, 168, Qt.LeftButton);
        compare(interactionReleases, 1);
        compare(capsuleClicks, 0);
    }

}
