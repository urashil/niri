pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Power profile automation. Applied on changes only (plug / unplug / battery crossing the threshold),
// so a profile you pick by hand sticks until the next change. Stored in ~/.config/rice/power.json.
Singleton {
    id: root
    readonly property string path: Quickshell.env("HOME") + "/.config/rice/power.json"

    property bool auto: true
    property int lowAt: 30                  // switch to power saver at/below this % while discharging (0 = never)
    property string onCharger: "balanced"   // keep | balanced | performance
    property string onBattery: "balanced"   // keep | balanced | power-saver

    readonly property var dev: UPower.displayDevice
    readonly property bool plugged: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool discharging: dev && dev.state === UPowerDeviceState.Discharging
    property bool lowApplied: false

    function profileOf(n) { return n === "performance" ? PowerProfile.Performance : n === "power-saver" ? PowerProfile.PowerSaver : PowerProfile.Balanced; }
    function glyph(n) { return n === "performance" ? "" : n === "power-saver" ? "" : ""; }
    function label(n) { return n === "performance" ? "Performance" : n === "power-saver" ? "Power saver" : "Balanced"; }
    function color(n) { return n === "performance" ? Theme.red : n === "power-saver" ? Theme.green : Theme.blue; }

    function apply(name, why) {
        if (name === "keep") return;
        const p = profileOf(name);
        if (PowerProfiles.profile === p) return;
        PowerProfiles.profile = p;
        UiState.pulse("power", glyph(name), label(name) + " · " + why, -1, color(name), 2800);
    }
    function applyNow() {
        if (!auto || !dev) return;
        if (plugged) apply(onCharger, "plugged in");
        else if (discharging) {
            if (lowAt > 0 && dev.percentage * 100 <= lowAt) { apply("power-saver", "battery " + Math.round(dev.percentage * 100) + "%"); lowApplied = true; }
            else apply(onBattery, "on battery");
        }
    }

    Connections {
        target: root.dev
        ignoreUnknownSignals: true
        function onStateChanged() { root.lowApplied = false; if (root.auto) settle.restart(); }
        function onPercentageChanged() {
            if (!root.auto || !root.discharging || root.lowApplied || root.lowAt <= 0) return;
            if (root.dev.percentage * 100 <= root.lowAt) {
                root.lowApplied = true;
                root.apply("power-saver", "battery " + Math.round(root.dev.percentage * 100) + "%");
            }
        }
    }
    // UPower can report intermediate states while plugging in; act once it has settled
    Timer { id: settle; interval: 1500; onTriggered: root.applyNow() }
    Timer { interval: 5000; running: true; onTriggered: root.applyNow() }     // once after login

    function set(key, value) {
        root[key] = value;
        const j = JSON.stringify({ auto: auto, lowAt: lowAt, onCharger: onCharger, onBattery: onBattery });
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", path, j];
        save.running = true;
        if (key !== "lowAt" || true) { lowApplied = false; settle.restart(); }
    }
    Process { id: save }
    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); for (const k of ["auto", "lowAt", "onCharger", "onBattery"]) if (k in j) root[k] = j[k]; } catch (e) {} }
    }
}
