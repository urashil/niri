pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Night light through wlsunset: "off", "auto" (warm from sunset to sunrise at the weather location) or "on" (warm now).
// Saved in ~/.config/rice/nightlight.json.
Singleton {
    id: root
    property string mode: "off"
    property int temp: 4000              // K at night
    property bool installed: true
    readonly property bool active: mode !== "off" && installed

    function setMode(m) { mode = m; save(); }
    function cycle() { setMode(mode === "off" ? "auto" : mode === "auto" ? "on" : "off"); }
    function setTemp(t) { temp = Math.round(t / 100) * 100; save(); }
    function save() { cfg.setText(JSON.stringify({ mode: mode, temp: temp })); }

    FileView {
        id: cfg
        path: Quickshell.env("HOME") + "/.config/rice/nightlight.json"
        onLoaded: { try { const j = JSON.parse(text()); root.mode = j.mode || "off"; root.temp = j.temp || 4000; } catch (e) {} }
    }
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        onExited: code => root.installed = code === 0
    }

    // the command for the current settings; a change restarts wlsunset (debounced, the slider moves a lot)
    readonly property var command: {
        if (!active) return [];
        // "on": day and night the same warmth (wlsunset needs day > night)
        if (mode === "on") return ["wlsunset", "-t", String(temp), "-T", String(temp + 1)];
        const c = ["wlsunset", "-t", String(temp), "-T", "6500"];
        if (Weather.configured) return c.concat(["-l", String(Weather.lat), "-L", String(Weather.lon)]);
        return c.concat(["-S", "07:00", "-s", "19:30"]);
    }
    onCommandChanged: restart.restart()
    Timer {
        id: restart
        interval: 400
        onTriggered: {
            proc.running = false;
            if (root.command.length) { proc.command = root.command; startLater.restart(); }
        }
    }
    Timer { id: startLater; interval: 150; onTriggered: proc.running = true }
    Process {
        id: proc
        onExited: code => { if (code !== 0 && root.active && proc.command.length) console.warn("wlsunset exited", code); }
    }
}
