// A Wayland client that animates continuously and counts the frames it gets
// to draw. Run as phablet with the screen on:
//   GLIBC_TUNABLES=glibc.rtld.optional_static_tls=4096 QT_QPA_PLATFORM=ubuntumirclient \
//     MIR_SOCKET=/run/user/32011/mir_socket QT_SELECT=qt5 qmlscene /home/phablet/fps-probe.qml
// Prints, once a second: frames swapped in that second, the longest gap
// between two swaps, and what Qt thinks the screen refresh rate is.
import QtQuick 2.12
import QtQuick.Window 2.12

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "black"
    property int limit: 15
    property int frames: 0
    property int total: 0
    property int seconds: 0
    property real last: 0
    property real maxGap: 0

    onFrameSwapped: {
        var now = Date.now();
        if (last > 0 && now - last > maxGap)
            maxGap = now - last;
        last = now;
        frames++;
    }

    Rectangle {
        id: box
        width: 300; height: 300
        anchors.centerIn: parent
        color: "orange"
        property real refresh: Screen.refreshRate || 0
        NumberAnimation on rotation { from: 0; to: 360; duration: 2000; loops: Animation.Infinite }
    }
    Rectangle {
        width: 60; height: parent.height
        color: "steelblue"
        NumberAnimation on x { from: 0; to: win.width - 60; duration: 1000; loops: Animation.Infinite }
    }
    Text {
        id: label
        color: "white"; font.pixelSize: 48
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.15
    }

    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: {
            win.seconds++;
            if (win.seconds > 1)        // skip the first, partial second
                win.total += win.frames;
            var line = "t=" + win.seconds + "s frames=" + win.frames + " maxgap=" + win.maxGap +
                       "ms Screen.refreshRate=" + Number(box.refresh).toFixed(2);
            console.log(line);
            label.text = win.frames + " fps";
            win.frames = 0;
            win.maxGap = 0;
            if (win.seconds >= win.limit) {
                console.log("mean fps (excluding first second): " + (win.total / (win.seconds - 1)).toFixed(1));
                Qt.quit();
            }
        }
    }
}
