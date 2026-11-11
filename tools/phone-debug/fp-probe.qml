// Fingerprint stack probe (no root): is biometryd available to QML, and does
// a template store query (size) reach the HAL? Prints and quits.
import QtQuick 2.12
import Biometryd 0.0
import Lomiri.Settings.Fingerprint 0.1

Item {
    User { id: user; uid: LomiriSettingsFingerprint.uid }
    Observer {
        id: obs
        onFailed: { console.log("size FAILED: " + reason); Qt.quit() }
        onSucceeded: { console.log("size OK: " + result + " enrolled fingerprint(s)"); Qt.quit() }
        onCanceled: { console.log("size canceled: " + reason); Qt.quit() }
    }
    Timer {
        interval: 1500; running: true
        onTriggered: {
            console.log("Biometryd.available=" + Biometryd.available + " uid=" + user.uid);
            if (!Biometryd.available) { Qt.quit(); return }
            var op = Biometryd.defaultDevice.templateStore.size(user);
            op.start(obs);
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.log("timeout"); Qt.quit() } }
}
