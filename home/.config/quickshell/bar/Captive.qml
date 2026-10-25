pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Detects Wi-Fi sign-in pages (Mozilla's connectivity check; no Google).
Singleton {
    id: root
    property string status: "unknown"      // ok | portal | offline | unknown
    property bool announced: false

    function check() { if (Wifi.connected) probe.running = true; else status = "unknown"; }
    function openLogin() { opener.running = true; }

    Process { id: opener; command: ["xdg-open", "http://neverssl.com"] }
    Process {
        id: probe
        command: ["curl", "-s", "--max-time", "6", "http://detectportal.firefox.com/success.txt"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                root.status = t === "success" ? "ok" : t === "" ? "offline" : "portal";
                if (root.status === "portal" && !root.announced) {
                    root.announced = true;
                    UiState.pulse("portal", "", "Wi-Fi sign-in required", -1, Theme.yellow, 6000);
                }
                if (root.status === "ok") root.announced = false;
            }
        }
    }
    Connections { target: Wifi; function onSsidChanged() { root.announced = false; delay.restart(); } }
    Timer { id: delay; interval: 2500; onTriggered: root.check() }
    Timer { interval: 25000; running: true; repeat: true; onTriggered: root.check() }
}
