pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick

// Options for caffeine / super caffeine. Stored in ~/.config/rice/caffeine.json.
// Caffeine: the bar holds a Wayland idle inhibitor (no idle lock / screen off).
// Super: also blocks logind from suspending; the options below say what still happens.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: home + "/.config/rice/caffeine.json"

    property string lid: "lockoff"      // when the lid closes: lockoff | lock | none
    property int idleLock: 0            // super: lock after N idle minutes (0 = never)
    property int screenOff: 0           // super: screen off after N idle minutes (0 = never)
    property int stopAfter: 0           // minutes until caffeine switches itself off (0 = never)
    property int cutoff: 0              // switch off below this battery % while discharging (0 = off)
    property bool blockSuspend: true    // super: also block manual suspend (power menu)
    property bool lowPower: true        // super: power saver + keyboard light off while the lid is closed

    property real endsAt: 0
    property real now: Date.now()
    readonly property string remaining: {
        if (!UiState.caffeine || endsAt <= 0) return "";
        const m = Math.max(1, Math.ceil((endsAt - now) / 60000));
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m left" : m + "m left";
    }

    function set(key, value) {
        root[key] = value;
        const j = JSON.stringify({ lid: lid, idleLock: idleLock, screenOff: screenOff, stopAfter: stopAfter, cutoff: cutoff, blockSuspend: blockSuspend, lowPower: lowPower });
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", path, j];
        save.running = true;
    }
    Process { id: save }
    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                for (const k of ["lid", "idleLock", "screenOff", "stopAfter", "cutoff", "blockSuspend", "lowPower"]) if (k in j) root[k] = j[k];
            } catch (e) {}
        }
    }

    // the lid script reads this file to know what to do while super caffeine is on
    function writeLid() {
        lidFlag.command = ["sh", "-c", "mkdir -p \"$HOME/.cache/rice\" && printf '%s' \"$1\" > \"$HOME/.cache/rice/super-lid\" && if [ \"$2\" = true ]; then touch \"$HOME/.cache/rice/super-lowpower\"; else rm -f \"$HOME/.cache/rice/super-lowpower\"; fi", "_", lid, String(lowPower)];
        lidFlag.running = true;
    }
    Process { id: lidFlag }
    onLidChanged: writeLid()
    onLowPowerChanged: writeLid()
    Component.onCompleted: writeLid()
    Connections { target: UiState; function onSuperCaffeineChanged() { if (UiState.superCaffeine) root.writeLid(); } }

    // stop after a while
    function arm() { endsAt = (UiState.caffeine && stopAfter > 0) ? Date.now() + stopAfter * 60000 : 0; now = Date.now(); }
    onStopAfterChanged: arm()
    Connections { target: UiState; function onCaffeineChanged() { root.arm(); } }
    function stopAll(why) {
        UiState.superCaffeine = false;
        UiState.caffeine = false;
        UiState.pulse("toggle", "", why, -1, Theme.yellow, 3500);
    }
    Timer {
        interval: 1000; running: UiState.caffeine; repeat: true
        onTriggered: { root.now = Date.now(); if (root.endsAt > 0 && root.now >= root.endsAt) root.stopAll("Caffeine timer ended"); }
    }

    // stop on a low battery
    Connections {
        target: UPower.displayDevice
        ignoreUnknownSignals: true
        function onPercentageChanged() {
            const d = UPower.displayDevice;
            if (UiState.caffeine && root.cutoff > 0 && d.state === UPowerDeviceState.Discharging && d.percentage * 100 <= root.cutoff)
                root.stopAll("Caffeine off · battery " + Math.round(d.percentage * 100) + "%");
        }
    }

    // super caffeine: the bar's idle inhibitor stops swayidle, so lock / screen-off on idle are done here
    IdleMonitor {
        enabled: UiState.superCaffeine && root.idleLock > 0
        timeout: root.idleLock * 60
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) Quickshell.execDetached([root.home + "/.local/bin/lock"])
    }
    IdleMonitor {
        enabled: UiState.superCaffeine && root.screenOff > 0
        timeout: root.screenOff * 60
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"])
    }

    // ---- awake <command>: super caffeine while jobs run, off again after the last one ----
    property var jobs: []               // [{ pid, name, start, watch? }]
    property bool autoSuper: false      // awake turned super caffeine on (so it turns it off again)
    property bool userOff: false        // switched off by hand while jobs ran: leave it off
    function refreshJobs() { if (!jobList.running) jobList.running = true; }
    Process {
        id: jobList
        command: ["sh", "-c", "d=\"${XDG_RUNTIME_DIR:-/tmp}/awake\"; for f in \"$d\"/*.json; do [ -e \"$f\" ] || continue; p=${f##*/}; p=${p%.json}; if [ -d /proc/$p ]; then cat \"$f\"; echo; else rm -f \"$f\"; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = [];
                for (const line of text.split("\n")) { try { if (line.trim()) l.push(JSON.parse(line)); } catch (e) {} }
                root.jobs = l;
            }
        }
    }
    onJobsChanged: {
        if (jobs.length > 0 && !UiState.superCaffeine && !userOff) { autoSuper = true; UiState.superCaffeine = true; }
        else if (jobs.length === 0) {
            userOff = false;
            if (autoSuper && UiState.superCaffeine) { autoSuper = false; UiState.superCaffeine = false; UiState.caffeine = false; }
            autoSuper = false;
        }
    }
    Connections {
        target: UiState
        function onSuperCaffeineChanged() { if (!UiState.superCaffeine && root.jobs.length > 0) { root.userOff = true; root.autoSuper = false; } }
    }
    function finished(name, code, took) {
        const t = parseInt(took);
        const d = t >= 3600 ? Math.floor(t / 3600) + "h " + Math.floor(t % 3600 / 60) + "m" : t >= 60 ? Math.floor(t / 60) + "m" : t + "s";
        const bad = code !== "done" && code !== "0";
        UiState.pulse("toggle", bad ? "\uf071" : "\uf00c", name.trim() + (bad ? " failed (" + code + ")" : " finished") + " · " + d, -1, bad ? Theme.error : Theme.green, 6000);
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshJobs() }
}
