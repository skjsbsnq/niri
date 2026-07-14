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

    signal completed(int result)
    signal error(int err)
    signal pamMessage()

    function start() {
        return true;
    }

    function abort() {
        active = false;
    }

    function respond(text) {
        return true;
    }
}
