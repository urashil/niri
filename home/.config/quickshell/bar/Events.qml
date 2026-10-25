import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick

// Feeds the dynamic island: volume, brightness, media, battery, wallpaper, toggles.
Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    // ---- volume ----
    property bool volReady: false
    Connections {
        target: root.sink ? root.sink.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() { root.volume(); }
        function onMutedChanged() { root.volume(); }
    }
    function volume() {
        if (!sink || !sink.audio) return;
        const a = sink.audio;
        UiState.pulse("volume", a.muted ? "󰖁" : a.volume > 0.5 ? "" : a.volume > 0 ? "" : "󰖁",
                      a.muted ? "Muted" : Math.round(a.volume * 100) + "%", a.muted ? 0 : a.volume, Theme.blue, 1500);
    }

    // ---- brightness ----
    property real maxBright: 1
    property bool brightReady: false
    FileView {
        path: "/sys/class/backlight/intel_backlight/max_brightness"
        onLoaded: root.maxBright = parseInt(text())
    }
    FileView {
        path: "/sys/class/backlight/intel_backlight/brightness"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text()) / root.maxBright;
            UiState.brightness = v;
            if (root.brightReady) UiState.pulse("brightness", "", Math.round(v * 100) + "%", v, Theme.yellow, 1500);
            root.brightReady = true;
        }
    }

    // ---- media ----
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property string lastTrack: ""
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() {
            const t = root.player.trackTitle;
            if (t && t !== root.lastTrack) {
                root.lastTrack = t;
                UiState.pulse("media", "", (root.player.trackArtist ? root.player.trackArtist + " – " : "") + t, -1, Theme.tertiary, 3500);
            }
        }
    }

    // ---- battery ----
    readonly property var bat: UPower.displayDevice
    property int lastState: -1
    property int warned: 100
    Connections {
        target: root.bat
        ignoreUnknownSignals: true
        function onStateChanged() {
            const s = root.bat.state;
            if (root.lastState !== -1 && s !== root.lastState) {
                if (s === UPowerDeviceState.Charging)
                    UiState.pulse("battery", "", "Charging · " + Math.round(root.bat.percentage * 100) + "%", root.bat.percentage, Theme.green, 2500);
                else if (s === UPowerDeviceState.Discharging)
                    UiState.pulse("battery", "", "On battery · " + Math.round(root.bat.percentage * 100) + "%", root.bat.percentage, Theme.yellow, 2500);
            }
            root.lastState = s;
            if (s === UPowerDeviceState.Charging) root.warned = 100;
        }
        function onPercentageChanged() {
            const p = Math.round(root.bat.percentage * 100);
            if (root.bat.state !== UPowerDeviceState.Discharging) return;
            if (p <= 5 && root.warned > 5) { root.warned = 5; UiState.pulse("warn", "", "Battery critical · " + p + "%", root.bat.percentage, Theme.error, 8000); }
            else if (p <= 15 && root.warned > 15) { root.warned = 15; UiState.pulse("warn", "", "Battery low · " + p + "%", root.bat.percentage, Theme.error, 6000); }
        }
    }

    // ---- wallpaper ----
    property bool wallReady: false
    FileView {
        path: Quickshell.env("HOME") + "/.cache/rice/current"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const n = text().trim().split("/").pop().replace(/\.[^.]+$/, "");
            if (root.wallReady) UiState.pulse("wallpaper", "", n, -1, Theme.primary, 2200);
            root.wallReady = true;
        }
    }

    // per-network rules apply as soon as Wi-Fi connects
    Component.onCompleted: Automation.rules

    // ---- vpn ----
    property string lastVpn: ""
    Connections {
        target: Vpn
        function onStateChanged() {
            const s = Vpn.state;
            if (root.lastVpn === "" ) { root.lastVpn = s; return; }
            if (s === root.lastVpn) return;
            root.lastVpn = s;
            if (s === "Connected") UiState.pulse("vpn", "\uf132", "VPN on · " + Vpn.pretty(Vpn.region) + " · " + Vpn.label, -1, Theme.green, 3200);
            else if (s === "Disconnected") { if (Vpn.blocked && Wifi.connected) UiState.pulse("warn", "\uf071", "Blocked by killswitch", -1, Theme.error, 6000); else UiState.pulse("vpn", "\udb82\udd9d", "VPN off", -1, Theme.error, 2500); }
            else if (s === "Connecting" || s === "Reconnecting") UiState.pulse("vpn", "\uf132", "Connecting VPN…", -1, Theme.yellow, 2500);
            else if (s === "Interrupted") UiState.pulse("warn", "\uf071", "VPN interrupted", -1, Theme.error, 5000);
        }
    }

    // ---- caps / num lock: the keyboard LEDs in sysfs (no change notifications there, so reload in-process) ----
    property string capsPath: ""
    property string numPath: ""
    property int caps: -1
    property int num: -1
    Process {
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock /sys/class/leds/*::numlock 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.trim().split("\n")) {
                    if (l.endsWith("capslock")) root.capsPath = l + "/brightness";
                    else if (l.endsWith("numlock")) root.numPath = l + "/brightness";
                }
            }
        }
    }
    FileView {
        id: capsFile
        path: root.capsPath
        onLoaded: {
            const v = parseInt(text()) > 0 ? 1 : 0;
            if (root.caps !== -1 && v !== root.caps) UiState.pulse("lock", "\uf11c", v ? "Caps Lock on" : "Caps Lock off", -1, v ? Theme.yellow : Theme.outline, 1500);
            root.caps = v;
        }
    }
    FileView {
        id: numFile
        path: root.numPath
        onLoaded: {
            const v = parseInt(text()) > 0 ? 1 : 0;
            if (root.num !== -1 && v !== root.num) UiState.pulse("lock", "\uf11c", v ? "Num Lock on" : "Num Lock off", -1, v ? Theme.cyan : Theme.outline, 1500);
            root.num = v;
        }
    }
    Timer { interval: 180; running: root.capsPath !== ""; repeat: true; onTriggered: { capsFile.reload(); if (root.numPath !== "") numFile.reload(); } }

    // ---- microphone mute ----
    readonly property var mic: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [Pipewire.defaultAudioSource] }
    Connections {
        target: root.mic ? root.mic.audio : null
        ignoreUnknownSignals: true
        function onMutedChanged() {
            const m = root.mic.audio.muted;
            UiState.pulse("mic", m ? "\uf131" : "\uf130", m ? "Microphone muted" : "Microphone on", -1, m ? Theme.error : Theme.green, 1700);
        }
    }

    // ---- screen recording (the rec script keeps ~/.cache/rice/recording = start time) ----
    FileView {
        id: recFile
        path: Quickshell.env("HOME") + "/.cache/rice/recording"
        onLoaded: UiState.recStart = parseInt(text()) || 0
        onLoadFailed: UiState.recStart = 0
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: recFile.reload() }
    property bool recSeen: false
    Connections {
        target: UiState
        function onRecordingChanged() {
            if (!root.recSeen) { root.recSeen = true; if (!UiState.recording) return; }
            UiState.pulse("rec", UiState.recording ? "\uf111" : "\uf03d", UiState.recording ? "Recording" : "Recording saved", -1, Theme.red, 2500);
        }
    }

    // ---- theme mode ----
    FileView {
        path: Quickshell.env("HOME") + "/.cache/rice/mode"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: UiState.mode = text().trim() === "light" ? "light" : "dark"
    }

    // ---- super caffeine: hold logind's lid-switch / sleep / idle locks and drop a flag for the lid script ----
    Process {
        id: superLock
        running: UiState.superCaffeine
        command: ["systemd-inhibit", "--what=handle-lid-switch:sleep:idle", "--who=rice", "--why=Super caffeine", "--mode=block", "sleep", "infinity"]
    }
    Process { id: superFlag }
    Process {
        id: superRestore
        command: ["sh", "-c", "test -f \"$HOME/.cache/rice/super\" && echo 1"]
        running: true
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "1") UiState.superCaffeine = true }
    }
    Connections {
        target: UiState
        function onSuperCaffeineChanged() {
            superFlag.command = ["sh", "-c", UiState.superCaffeine ? "mkdir -p \"$HOME/.cache/rice\" && touch \"$HOME/.cache/rice/super\"" : "rm -f \"$HOME/.cache/rice/super\""];
            superFlag.running = true;
            UiState.pulse("toggle", UiState.superCaffeine ? "\uf023" : "\uf0f4", UiState.superCaffeine ? "Super caffeine" : "Super caffeine off", -1, Theme.red, 2200);
        }
    }

    // ---- toggles ----
    property bool togReady: false
    Connections {
        target: UiState
        function onCaffeineChanged() { if (!UiState.superCaffeine) UiState.pulse("toggle", "\uf0f4", UiState.caffeine ? "Staying awake" : "Idle lock on", -1, Theme.yellow, 1600); }
        function onDndChanged() { UiState.pulse("toggle", UiState.dnd ? "" : "", UiState.dnd ? "Do not disturb" : "Notifications on", -1, Theme.magenta, 1600); }
    }
}
