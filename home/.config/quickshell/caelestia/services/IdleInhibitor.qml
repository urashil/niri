pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

Singleton {
    id: root

    // state (persisted across full restarts via the flag file below)
    property bool enabled: false               // caffeine: screen stays on (idle inhibit)
    property bool superEnabled: false          // super: also blocks suspend / lid sleep
    readonly property alias enabledSince: props.enabledSince

    // settings
    property alias stopAfterMin: props.stopAfterMin    // auto-off after N minutes (0 = never)
    property alias batteryCutoff: props.batteryCutoff  // auto-off below N% on battery (0 = off)

    property real endsAt: 0
    property real now: Date.now()
    readonly property string remaining: {
        if (!enabled || endsAt <= 0)
            return "";
        const m = Math.max(1, Math.ceil((endsAt - now) / 60000));
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }
    function arm() {
        endsAt = (enabled && stopAfterMin > 0) ? Date.now() + stopAfterMin * 60000 : 0;
        now = Date.now();
    }
    onStopAfterMinChanged: arm()

    onEnabledChanged: {
        if (enabled)
            props.enabledSince = new Date();
        else
            superEnabled = false;   // caffeine off drops super too
        arm();
        writeFlag();
    }
    onSuperEnabledChanged: {
        if (superEnabled)
            enabled = true;         // super implies caffeine
        else
            killInhibitors();       // turning super off kills ALL our inhibitors
        writeFlag();
    }

    // off -> caffeine -> super -> off
    function cycle(): void {
        if (!enabled)
            enabled = true;
        else if (!superEnabled)
            superEnabled = true;
        else
            disableAll();
    }
    function disableAll(): void {
        superEnabled = false;
        enabled = false;
    }

    // kill EVERY systemd-inhibit we own (orphaned or live) — nothing lingers after "off"
    function killInhibitors(): void {
        Quickshell.execDetached(["sh", "-c", "pkill -f 'systemd-inhibit .*--who=caelestia' 2>/dev/null; :"]);
    }

    // ---- persistence across full restarts: a flag file is the source of truth ----
    readonly property string flagPath: Quickshell.env("HOME") + "/.cache/caelestia/caffeine"
    function writeFlag(): void {
        const v = superEnabled ? "super" : enabled ? "caffeine" : "off";
        // also mirror the ~/.cache/rice/super flag that lid-close reads, so closing the lid
        // with super caffeine on locks + keeps awake instead of suspending
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"; " +
            "mkdir -p \"$HOME/.cache/rice\" && if [ \"$3\" = super ]; then touch \"$HOME/.cache/rice/super\"; else rm -f \"$HOME/.cache/rice/super\"; fi",
            "_", flagPath, v, v]);
    }
    FileView {
        id: flagFile
        path: root.flagPath
        printErrors: false
        onLoaded: {
            const v = text().trim();
            root.enabled = v === "caffeine" || v === "super";
            root.superEnabled = v === "super";
        }
    }
    // on startup: clear any orphan inhibitor, then restore the saved state
    Component.onCompleted: {
        killInhibitors();
        flagFile.reload();
    }

    PersistentProperties {
        id: props

        property date enabledSince
        property int stopAfterMin: 0
        property int batteryCutoff: 10    // auto-off below N% on battery; guards against a flat battery

        reloadableId: "idleInhibitor"
    }

    Timer {
        interval: 1000
        running: root.enabled
        repeat: true
        onTriggered: {
            root.now = Date.now();
            if (root.endsAt > 0 && root.now >= root.endsAt)
                root.disableAll();
        }
    }

    // auto-off on low battery (prevents a stuck super caffeine from draining the laptop flat)
    Connections {
        target: UPower.displayDevice
        ignoreUnknownSignals: true
        function onPercentageChanged() {
            const d = UPower.displayDevice;
            if (root.enabled && root.batteryCutoff > 0 && d.state === UPowerDeviceState.Discharging && d.percentage * 100 <= root.batteryCutoff)
                root.disableAll();
        }
    }

    // when the lid closes with super caffeine on, we still want the screen to power off (just no
    // suspend). The lid scripts pause this so niri's power-off-monitors sticks; the suspend block stays.
    property bool screenPaused: false

    // caffeine: wayland idle inhibitor (no idle lock / screen off)
    IdleInhibitor {
        enabled: root.enabled && !root.screenPaused
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    // super: block logind suspend + lid switch while it runs
    Process {
        id: superLock
        running: root.superEnabled
        command: ["systemd-inhibit", "--what=handle-lid-switch:sleep:idle", "--who=caelestia", "--why=Super caffeine", "--mode=block", "sleep", "infinity"]
    }

    IpcHandler {
        function isEnabled(): bool { return root.enabled; }
        function pauseScreen(): void { root.screenPaused = true; }
        function resumeScreen(): void { root.screenPaused = false; }
        function toggle(): void { root.enabled = !root.enabled; }
        function enable(): void { root.enabled = true; }
        function disable(): void { root.disableAll(); }
        function isSuper(): bool { return root.superEnabled; }
        function superToggle(): void { root.superEnabled = !root.superEnabled; }
        function superEnable(): void { root.superEnabled = true; }
        function superDisable(): void { root.superEnabled = false; }
        function cycle(): void { root.cycle(); }
        function setStopAfter(minutes: int): void { props.stopAfterMin = minutes; }
        function setBatteryCutoff(percent: int): void { props.batteryCutoff = percent; }
        function state(): string { return root.superEnabled ? "super" : root.enabled ? "caffeine" : "off"; }

        target: "idleInhibitor"
    }
}
