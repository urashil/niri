pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Up/down rate of the Wi-Fi interface.
Singleton {
    id: root
    property real down: 0   // bytes/s
    property real up: 0
    property var last: null
    property var downHist: []
    property var upHist: []

    function fmt(b) {
        if (b < 1024) return Math.round(b) + "B";
        if (b < 1048576) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + "K";
        return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + "M";
    }

    Process {
        id: proc
        command: ["sh", "-c", "awk '$1==\"wlan0:\"{print $2, $10}' /proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ").map(Number);
                if (p.length < 2 || isNaN(p[0])) return;
                const now = Date.now();
                if (root.last) {
                    const dt = (now - root.last.t) / 1000;
                    if (dt > 0) {
                        root.down = Math.max(0, (p[0] - root.last.rx) / dt);
                        root.up = Math.max(0, (p[1] - root.last.tx) / dt);
                        root.downHist = root.downHist.concat([root.down]).slice(-60);
                        root.upHist = root.upHist.concat([root.up]).slice(-60);
                    }
                }
                root.last = { rx: p[0], tx: p[1], t: now };
            }
        }
    }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
}
