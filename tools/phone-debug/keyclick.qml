import QtQuick 2.4
import QtMultimedia 5.6
// 12 keyboard clicks, 120 ms apart, the way the on-screen keyboard plays them.
Item {
    property int count: 0
    SoundEffect { id: fx; source: "file:///usr/share/maliit/plugins/lomiri-keyboard/styles/lomiri/sounds/key_tick2_quiet.wav" }
    Timer {
        interval: 120; repeat: true; running: fx.status == SoundEffect.Ready
        onTriggered: { if (count++ < 12) fx.play(); else Qt.quit() }
    }
}
