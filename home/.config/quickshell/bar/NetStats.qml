pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Up/down rate of the Wi-Fi interface, and how much each Wi-Fi network has used (by day; ~/.local/state/rice/data-usage.json).
Singleton {
    id: root
    property real down: 0   // bytes/s
    property real up: 0
    property var last: null
    property var downHist: []
    property var upHist: []

    // ---- data used per network: { ssid: { "YYYY-MM-DD": [rx, tx] } } ----
    property var usage: ({})
    property bool usageDirty: false
    function day(d) { return Qt.formatDate(d || new Date(), "yyyy-MM-dd"); }
    function used(ssid, scope) {           // bytes, scope "today" | "month" | "all"
        const u = usage[ssid];
        if (!u) return 0;
        const today = day(), month = today.slice(0, 7);
        let n = 0;
        for (const k in u) if (scope === "all" || (scope === "today" ? k === today : k.startsWith(month))) n += u[k][0] + u[k][1];
        return n;
    }
    function size(b) {
        if (b < 1e6) return Math.round(b / 1e3) + " KB";
        if (b < 1e9) return (b / 1e6).toFixed(b < 1e7 ? 1 : 0) + " MB";
        return (b / 1e9).toFixed(2) + " GB";
    }
    function account(rx, tx) {
        const ssid = Wifi.connected ? Wifi.ssid : "";
        if (!ssid || (rx <= 0 && tx <= 0)) return;
        const u = usage[ssid] || {};
        const k = day();
        const c = u[k] || [0, 0];
        u[k] = [c[0] + rx, c[1] + tx];
        usage[ssid] = u;
        usageDirty = true;
    }
    FileView {
        id: usageFile
        path: Quickshell.env("HOME") + "/.local/state/rice/data-usage.json"
        onLoaded: { try { root.usage = JSON.parse(text()); } catch (e) {} }
    }
    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: if (root.usageDirty) { root.usageDirty = false; root.usageChanged(); usageFile.setText(JSON.stringify(root.usage)); }
    }
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/rice"] }

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
                        // counters reset when the interface goes down: skip that sample
                        if (p[0] >= root.last.rx && p[1] >= root.last.tx) root.account(p[0] - root.last.rx, p[1] - root.last.tx);
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
