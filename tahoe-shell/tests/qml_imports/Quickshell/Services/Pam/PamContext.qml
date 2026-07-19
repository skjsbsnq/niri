import QtQml

QtObject {
    property bool active: false
    property string config: ""
    property string configDirectory: ""
    property string user: ""
    property string message: ""
    property bool messageIsError: false
    property bool responseRequired: false
    property bool responseVisible: false
    property string lastResponse: ""
    property bool startResult: true
    property int startCount: 0
    property int abortCount: 0

    signal completed(int result)
    signal error(int err)
    signal pamMessage()

    function start() {
        startCount += 1;
        active = startResult;
        return startResult;
    }

    function abort() {
        abortCount += 1;
        active = false;
    }

    function respond(text) {
        lastResponse = String(text || "");
        return true;
    }

}
