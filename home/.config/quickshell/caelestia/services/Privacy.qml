pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Network privacy via the root helper /usr/local/lib/rice/net-helper (MAC randomization, Wi-Fi
// hostname, DUID rotation, hardening). status is read-only; changes go through pkexec.
Singleton {
    id: root

    readonly property string helper: "/usr/local/lib/rice/net-helper"
    property var s: ({ mode: "disabled", range: "full", mac: "", permanent: "", ssid: null, always: false, hostname: "", wifiHostname: "", bootHostname: false, harden: false, duidRotate: false, dhcpHostname: false })
    property bool installed: true
    property string busy: ""
    property string note: ""
    property bool noteErr: false

    // the per-network rule for an SSID (from status), or a default
    function ruleFor(ssid) {
        const rules = root.s.rules || [];
        for (const r of rules)
            if (r.ssid === ssid)
                return r;
        return { ssid: ssid, always: false, override: "", sendHostname: false };
    }

    function refresh() { stat.running = true; }
    function run(label, args) {
        busy = label;
        note = "";
        act.command = ["pkexec", root.helper].concat(args);
        act.running = true;
    }

    Process {
        id: stat
        command: [root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.s = JSON.parse(text);
                    root.installed = true;
                } catch (e) {
                    root.installed = false;
                }
            }
        }
        onExited: code => { if (code !== 0) root.installed = false; }
    }

    Process {
        id: act
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            root.busy = "";
            if (code === 0) {
                root.note = actOut.text.trim() ? "→ " + actOut.text.trim() : "Done";
                root.noteErr = false;
            } else if (code === 126 || code === 127) {
                root.note = "Cancelled";
                root.noteErr = true;
            } else {
                root.note = actErr.text.trim().split("\n").pop() || ("failed (" + code + ")");
                root.noteErr = true;
            }
            root.refresh();
            burst.n = 0;
            burst.restart();
        }
    }
    // iwd restarts and the new MAC only shows after it reconnects: keep polling for a few seconds
    Timer {
        id: burst
        property int n: 0
        interval: 900
        repeat: true
        onTriggered: { root.refresh(); if (++n >= 8) stop(); }
    }
    Timer { interval: 6000; running: root.note !== ""; onTriggered: root.note = "" }
    Timer { interval: 8000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
