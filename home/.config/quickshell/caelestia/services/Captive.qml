pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Detects Wi-Fi sign-in pages (Mozilla's connectivity check). Toasts once when a portal appears.
Singleton {
    id: root

    property string status: "unknown"      // ok | portal | offline | unknown
    property bool announced: false

    readonly property bool connected: !!Nmcli.active
    readonly property string ssid: Nmcli.active ? Nmcli.active.ssid : ""

    function check() {
        if (connected)
            probe.running = true;
        else
            status = "unknown";
    }
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
                    Quickshell.execDetached(["caelestia", "shell", "toaster", "warn", "Wi-Fi", "Sign-in required — open the login page", "wifi"]);
                }
                if (root.status === "ok")
                    root.announced = false;
            }
        }
    }

    onSsidChanged: {
        root.announced = false;
        delay.restart();
    }
    Timer { id: delay; interval: 2500; onTriggered: root.check() }
    Timer { interval: 25000; running: true; repeat: true; onTriggered: root.check() }
}
