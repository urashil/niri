pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Night light via wlsunset: "off", "auto" (warm from sunset to sunrise) or "on" (warm now).
// Saved in ~/.config/rice/nightlight.json. Auto uses fixed local times since the weather location is unset.
Singleton {
    id: root

    property string mode: "off"
    property int temp: 4000 // K at night
    property bool installed: true
    readonly property bool active: mode !== "off" && installed

    function setMode(m: string): void { mode = m; save(); }
    function cycle(): void { setMode(mode === "off" ? "auto" : mode === "auto" ? "on" : "off"); }
    function setTemp(t: int): void { temp = Math.round(t / 100) * 100; save(); }
    function save(): void { cfg.setText(JSON.stringify({ mode: root.mode, temp: root.temp })); }

    FileView {
        id: cfg
        path: Quickshell.env("HOME") + "/.config/rice/nightlight.json"
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.mode = j.mode || "off";
                root.temp = j.temp || 4000;
            } catch (e) {}
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        onExited: code => root.installed = code === 0
    }

    // the wlsunset invocation for the current settings; a change restarts it (debounced, since the
    // temperature can be dragged through many values)
    readonly property var command: {
        if (!active)
            return [];
        if (mode === "on")
            return ["wlsunset", "-t", String(temp), "-T", String(temp + 1)]; // day == night (wlsunset needs day > night)
        return ["wlsunset", "-t", String(temp), "-T", "6500", "-S", "07:00", "-s", "19:30"];
    }
    onCommandChanged: restart.restart()

    Timer {
        id: restart
        interval: 400
        onTriggered: {
            proc.running = false;
            if (root.command.length) {
                proc.command = root.command;
                startLater.restart();
            }
        }
    }
    Timer { id: startLater; interval: 150; onTriggered: proc.running = true }
    Process { id: proc }

    Component.onCompleted: cfg.reload()
}
