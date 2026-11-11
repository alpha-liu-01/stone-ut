/*
 * stone: refresh rate section of System Settings > Brightness.
 * Loaded by the page copy that stone-display-setup bind-mounts over
 * lomiri-system-settings' brightness/PageComponent.qml. The backend is
 * refresh_rate.py (pyotherside): it reads /etc/stone/refresh-rate and drops
 * requests into /run/stone-refresh-rate/, which stone-refresh-rate.path
 * hands to root (save, and restart the display if asked).
 */
import QtQuick 2.12
import Lomiri.Components 1.3
import Lomiri.Components.ListItems 1.3 as ListItem
import Lomiri.Components.Popups 1.3
import SystemSettings 1.0
import io.thp.pyotherside 1.5

Column {
    id: refreshRate

    property int saved: 0          // rate used from the next display start
    property int current: 0        // rate the panel runs at now
    property bool available: false
    readonly property var rates: [60, 120]

    function indexOf(rate) { return rate === 60 ? 0 : 1 }

    function refresh() {
        py.call("refresh_rate.state", [], function(st) {
            refreshRate.saved = st.saved;
            refreshRate.current = st.current;
            refreshRate.available = st.available;
            selector.selectedIndex = indexOf(st.saved);
        });
    }

    Python {
        id: py
        Component.onCompleted: {
            addImportPath("/usr/share/stone/settings");
            importModule("refresh_rate", function() { refreshRate.refresh() });
        }
        onError: console.warn("refresh rate: " + traceback)
    }

    SettingsItemTitle {
        text: i18n.tr("Refresh rate:")
    }

    ListItem.ItemSelector {
        id: selector
        objectName: "refreshRateSelector"
        expanded: true
        showDivider: false
        enabled: refreshRate.available
        model: [i18n.tr("Standard (60 Hz)"), i18n.tr("Smooth (120 Hz)")]
        selectedIndex: -1
        onDelegateClicked: {
            var rate = refreshRate.rates[index];
            if (rate !== refreshRate.saved)
                PopupUtils.open(confirmDialog, refreshRate, { "rate": rate });
        }
    }

    ListItem.Caption {
        text: {
            var t = i18n.tr("120 Hz makes scrolling and animations smoother, and uses more battery.");
            if (refreshRate.saved && refreshRate.current && refreshRate.saved !== refreshRate.current)
                t += " " + i18n.tr("Now %1 Hz; %2 Hz after the display restarts.")
                        .arg(refreshRate.current).arg(refreshRate.saved);
            return t;
        }
    }

    Component {
        id: confirmDialog
        Dialog {
            id: dialog
            property int rate
            title: i18n.tr("Switch to %1 Hz").arg(rate)
            text: i18n.tr("The new rate takes effect when the display restarts. Restarting it now closes all open apps, and the phone locks.")
            Button {
                objectName: "refreshRateRestartNow"
                text: i18n.tr("Restart display now")
                color: theme.palette.normal.negative
                onClicked: {
                    py.call("refresh_rate.request", [dialog.rate, true]);
                    PopupUtils.close(dialog);
                }
            }
            Button {
                objectName: "refreshRateLater"
                text: i18n.tr("At next restart")
                onClicked: {
                    var r = dialog.rate;
                    py.call("refresh_rate.request", [r, false], function() {
                        // the root side saves it asynchronously
                        refreshRate.saved = r;
                        refreshTimer.start();
                    });
                    PopupUtils.close(dialog);
                }
            }
            Button {
                objectName: "refreshRateCancel"
                text: i18n.tr("Cancel")
                onClicked: {
                    selector.selectedIndex = refreshRate.indexOf(refreshRate.saved);
                    PopupUtils.close(dialog);
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 1500
        onTriggered: refreshRate.refresh()
    }
}
