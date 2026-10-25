pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Wi-Fi through iwd (iwctl). Read-only calls need no privileges.
Singleton {
    id: root

    readonly property string dev: "wlan0"
    property bool powered: true
    property string state: "disconnected"
    property string ssid: ""
    property int rssi: 0
    property var networks: []     // [{ssid, security, bars, known, connected}]
    property var known: []
    property bool scanning: false
    property string error: ""
    property var rules: ({})        // ssid -> {always, override, sendHostname} (mirror written by the helper)

    readonly property bool connected: state === "connected"
    readonly property int bars: !connected ? 0 : rssi > -55 ? 4 : rssi > -65 ? 3 : rssi > -75 ? 2 : 1

    function strip(s) { return s.replace(/\u001b\[[0-9;]*m/g, ""); }

    function refresh() { show.running = true; devShow.running = true; }

    function scan() {
        scanning = true;
        doScan.running = true;
    }
    function setPowered(on) {
        act.command = ["iwctl", "device", dev, "set-property", "Powered", on ? "on" : "off"];
        act.running = true;
    }
    function connectTo(name, pass) {
        error = "";
        act.command = pass ? ["iwctl", "--passphrase", pass, "station", dev, "connect", name]
                           : ["iwctl", "station", dev, "connect", name];
        act.running = true;
    }
    function disconnect() {
        act.command = ["iwctl", "station", dev, "disconnect"];
        act.running = true;
    }
    function forget(name) {
        act.command = ["iwctl", "known-networks", name, "forget"];
        act.running = true;
    }

    Process {
        id: act
        stderr: StdioCollector { id: actErr }
        stdout: StdioCollector { id: actOut }
        onExited: {
            const m = root.strip(actOut.text + actErr.text).trim();
            root.error = m.length > 0 && m.indexOf("Operation failed") >= 0 || m.indexOf("not found") >= 0 ? m.split("\n")[0] : "";
            after.restart();
        }
    }
    Timer { id: after; interval: 1500; onTriggered: { root.refresh(); root.scan(); } }

    Process {
        id: show
        command: ["iwctl", "station", root.dev, "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = root.strip(text);
                const g = (k) => { const m = t.match(new RegExp("^\\s*" + k + "\\s+(.+?)\\s*$", "m")); return m ? m[1] : ""; };
                root.state = g("State") || "disconnected";
                root.ssid = g("Connected network");
                const r = g("RSSI").match(/-?\d+/);
                root.rssi = r ? parseInt(r[0]) : 0;
            }
        }
    }
    Process {
        id: devShow
        command: ["iwctl", "device", root.dev, "show"]
        stdout: StdioCollector {
            onStreamFinished: { root.powered = /Powered\s+on/.test(root.strip(text)); }
        }
    }
    Process {
        id: doScan
        command: ["iwctl", "station", root.dev, "scan"]
        onExited: list.running = true
    }
    Process {
        id: knownProc
        command: ["iwctl", "known-networks", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of root.strip(text).split("\n")) {
                    const m = l.match(/^\s{2}(\S.*?)\s{2,}(open|psk|8021x|wep)\b/);
                    if (m && m[1] !== "Name") out.push(m[1]);
                }
                root.known = out;
            }
        }
    }
    Process {
        id: list
        command: ["iwctl", "station", root.dev, "get-networks"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const raw of text.split("\n")) {
                    const l = raw.replace(/\u001b\[[0-9;]*m/g, "");
                    const m = l.match(/^\s*(>)?\s*(\S.*?)\s{2,}(open|psk|8021x|wep)\s+(\*+)/);
                    if (!m) continue;
                    // dim stars (after an escape) are empty bars: count only the bright ones
                    const sig = raw.match(/(?:open|psk|8021x|wep)\s+(\*+)/);
                    out.push({ ssid: m[2], security: m[3], bars: sig ? sig[1].length : m[4].length, connected: m[1] === ">", known: root.known.indexOf(m[2]) >= 0 });
                }
                root.networks = out;
                root.scanning = false;
            }
        }
    }

    FileView {
        path: "/var/lib/rice-net/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const m = {};
                for (const r of JSON.parse(text())) m[r.ssid] = r;
                root.rules = m;
            } catch (e) {}
        }
    }

    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { root.refresh(); knownProc.running = true; } }
}
