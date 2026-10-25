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

    // ---- toggles ----
    property bool togReady: false
    Connections {
        target: UiState
        function onCaffeineChanged() { UiState.pulse("toggle", "", UiState.caffeine ? "Staying awake" : "Idle lock on", -1, Theme.yellow, 1600); }
        function onDndChanged() { UiState.pulse("toggle", UiState.dnd ? "" : "", UiState.dnd ? "Do not disturb" : "Notifications on", -1, Theme.magenta, 1600); }
    }
}
