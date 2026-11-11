// Holds a QtPositioning session (lomiri-location-service via its Qt plugin,
// like Pure Maps) and prints one line per second for $GNSS_SECONDS (120).
//   QT_QPA_PLATFORM=minimal QT_SELECT=qt5 qmlscene /home/phablet/gnss-monitor.qml
import QtQuick 2.12
import QtPositioning 5.12

Item {
    property int n: 0
    property int updates: 0
    property int limit: 120
    PositionSource {
        id: src
        active: true
        updateInterval: 1000
        preferredPositioningMethods: PositionSource.AllPositioningMethods
        onPositionChanged: updates++
        onSourceErrorChanged: console.log("sourceError", sourceError)
        Component.onCompleted: console.log("plugin:", name, "valid:", valid, "supported:", supportedPositioningMethods)
    }
    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: {
            var p = src.position
            console.log("t=" + (++n) + " updates=" + updates + " valid=" + p.latitudeValid +
                        " lat=" + p.coordinate.latitude.toFixed(5) + " lon=" + p.coordinate.longitude.toFixed(5) +
                        " acc=" + (p.horizontalAccuracyValid ? p.horizontalAccuracy.toFixed(0) : "-") +
                        " ts=" + p.timestamp + " err=" + src.sourceError)
            if (n >= limit) Qt.quit()
        }
    }
}
