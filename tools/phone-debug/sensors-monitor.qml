// Prints QtSensors readings (sensorfw backend) for a few seconds.
//   QT_QPA_PLATFORM=minimal QT_SELECT=qt5 qmlscene /home/phablet/sensors-monitor.qml
import QtQuick 2.12
import QtSensors 5.12

Item {
    OrientationSensor { id: o; active: true }
    Accelerometer { id: acc; active: true }
    LightSensor { id: lux; active: true }
    ProximitySensor { id: prox; active: true }
    Gyroscope { id: gyro; active: true }
    Magnetometer { id: mag; active: true }
    property int n: 0
    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: {
            function r(s, f) { return s.reading ? f(s.reading) : (s.connectedToBackend ? "no reading" : "no backend") }
            console.log("orientation=" + r(o, function(x) { return x.orientation }) +
                        " acc=" + r(acc, function(x) { return x.x.toFixed(2) + "," + x.y.toFixed(2) + "," + x.z.toFixed(2) }) +
                        " lux=" + r(lux, function(x) { return x.illuminance.toFixed(1) }) +
                        " near=" + r(prox, function(x) { return x.near }) +
                        " gyro=" + r(gyro, function(x) { return x.x.toFixed(1) + "," + x.y.toFixed(1) + "," + x.z.toFixed(1) }) +
                        " mag=" + r(mag, function(x) { return (x.x * 1e6).toFixed(0) + "," + (x.y * 1e6).toFixed(0) + "," + (x.z * 1e6).toFixed(0) }))
            if (++n >= 6) Qt.quit()
        }
    }
}
