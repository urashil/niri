pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The host VPN client: Private Internet Access, Mullvad or IVPN (whichever ~/.config/rice/vpn.json picks, else the
// first installed). These are their own daemons, not NetworkManager profiles, so caelestia's VPN service can't see them.
// Every action goes through ~/.local/bin/vpnctl; state is watched live per client
// (piactl monitor / mullvad status listen / Ivpn.qml polling ivpn status, which has no event stream).
Singleton {
    id: root

    // ── provider ─────────────────────────────────────────────────────────────
    property var installed: []                 // ["pia", "mullvad", "ivpn"] subset, from `vpnctl providers`
    property var conf: ({})                    // ~/.config/rice/vpn.json
    readonly property string provider: conf.provider && installed.indexOf(conf.provider) >= 0 ? conf.provider : (installed[0] || "")
    readonly property string providerName: providerLabel(provider)
    function providerLabel(p) { return p === "pia" ? "PIA" : p === "mullvad" ? "Mullvad" : p === "ivpn" ? "IVPN" : "VPN"; }
    property string switching: ""              // provider being switched to
    function setProvider(p) {
        if (switching !== "" || (p === provider && available))
            return;
        switching = p;
        queue(["provider", p]);
    }

    // ── connection state (PIA's vocabulary for every client) ─────────────────
    // Connected | Connecting | Reconnecting | Disconnecting | DisconnectingToReconnect | Disconnected | Interrupted | Unavailable
    property string state: "Disconnected"
    property string vpnIp: ""
    readonly property bool available: state !== "Unavailable"
    readonly property bool connected: state === "Connected"
    readonly property bool busy: state === "Connecting" || state === "Reconnecting" || state === "DisconnectingToReconnect" || state === "Disconnecting"

    // ── method (transport) ──────────────────────────────────────────────────
    // ids are shared so per-network rules work with any client: wireguard | school (gets through a network that only
    // lets TCP/443-ish traffic out) | auto | stealth (IVPN: WireGuard wrapped in V2Ray VMESS/TCP on 443)
    readonly property var methods: provider === "mullvad"
        ? [["wireguard", "WireGuard"], ["school", "WireGuard · TCP 443"], ["auto", "Auto obfuscation"]]
        : provider === "ivpn"
        ? Ivpn.methods.map(m => [m.id, m.full])
        : [["wireguard", "WireGuard"], ["school", "OpenVPN · TCP 443"], ["auto", "OpenVPN · auto"]]
    function methodLabel(m) { const e = methods.find(x => x[0] === m); return e ? e[1] : m; }
    property string liveMethod: "wireguard"    // what the client reports / was last told
    property string pending: ""                // optimistic UI, cleared when the client catches up
    readonly property string choice: pending !== "" ? pending : liveMethod
    readonly property string label: methodLabel(choice)
    onLiveMethodChanged: if (pending === liveMethod) pending = ""
    Timer { id: pendingTimer; interval: 25000; onTriggered: root.pending = "" }
    function use(m) { pending = m; pendingTimer.restart(); queue(["method", m]); }
    function useWireguard() { use("wireguard"); }
    function useSchool() { use("school"); }
    function useOpenvpnAuto() { use("auto"); }

    // ── kill switch ─────────────────────────────────────────────────────────
    // on: block while the VPN is down / auto: only while it should be up / off. Mullvad always blocks an unexpected
    // drop, so it has no "off" (its "on" is lockdown mode).
    readonly property var ksModes: provider === "mullvad" ? ["on", "auto"] : ["on", "auto", "off"]
    property string killswitch: "auto"
    property string pendingKs: ""
    readonly property string ksMode: pendingKs !== "" ? pendingKs : killswitch
    onKillswitchChanged: if (pendingKs === killswitch) pendingKs = ""
    Timer { id: pendingKsTimer; interval: 25000; onTriggered: root.pendingKs = "" }
    property bool fwActive: false              // the client says its firewall is blocking right now (Mullvad/IVPN)
    readonly property bool blocked: provider === "pia"
        ? (ksMode === "on" ? state !== "Connected" : ksMode === "auto" ? (state === "Interrupted" || state === "Reconnecting") : false)
        : fwActive
    function setKillswitch(mode) {
        if (mode === killswitch && pendingKs === "")
            return;
        pendingKs = mode;
        pendingKsTimer.restart();
        queue(["killswitch", mode].concat(connected || busy ? ["reconnect"] : []));
    }

    // ── region ──────────────────────────────────────────────────────────────
    property string region: "auto"
    property var regions: []                   // [{ id, label }]
    function pretty(id) {
        if (provider === "ivpn")
            return Ivpn.regionLabel(id);
        if (!id || id === "auto")
            return "Auto";
        const r = regions.find(x => x.id === id);
        if (r)
            return r.label;
        return id.split(/[-\/]/).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }
    function setRegion(r) { queue(["region", r]); if (provider !== "pia") region = r; }

    function connect() { queue(["connect"]); }
    function disconnect() { queue(["disconnect"]); }
    function toggle() { if (connected || busy) disconnect(); else connect(); }

    // ── actions: vpnctl, one at a time; the last error shows in the popout for a bit ──
    property string error: ""
    Timer { id: errorTimer; interval: 8000; onTriggered: root.error = "" }
    property var actions: []
    function queue(args) {
        actions = actions.concat([args]);
        if (!act.running)
            next();
    }
    function next() {
        if (actions.length === 0)
            return;
        act.args = actions[0];
        actions = actions.slice(1);
        act.command = ["vpnctl"].concat(act.args);
        act.running = true;
    }
    Process {
        id: act
        property var args: []
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            const msg = actErr.text.trim().split("\n").filter(l => l).pop() || "";
            if (code !== 0 && msg !== "" && act.args[0] !== "connect" && act.args[0] !== "toggle") {
                root.error = msg;
                errorTimer.restart();
            }
            if (act.args[0] === "provider") {
                root.switching = "";
                if (code !== 0) { root.error = msg || "Could not switch to " + root.providerLabel(act.args[1]); errorTimer.restart(); }
                root.restartWatch();
            }
            if (act.args[0] === "method" && code !== 0) root.pending = "";
            if (act.args[0] === "killswitch" && code !== 0) root.pendingKs = "";
            root.next();
        }
    }

    // ── config / installed clients ──────────────────────────────────────────
    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/vpn.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.conf = JSON.parse(text()); } catch (e) { root.conf = {}; } root.applyConf(); }
        onLoadFailed: { root.conf = {}; root.applyConf(); }
    }
    function applyConf() {
        if (provider === "mullvad") {
            liveMethod = conf.mullvadMethod || "auto";
            region = conf.mullvadRegion || "auto";
            if (!mvLockKnown) killswitch = conf.mullvadKs || "auto";
        } else if (provider === "ivpn") {
            if (!connected) liveMethod = conf.ivpnMethod || "wireguard";
            if (!connected) region = conf.ivpnRegion || "auto";
            killswitch = ivPersistent ? "on" : (conf.ivpnKs === "off" ? "off" : "auto");
        }
    }
    Process {
        id: listInstalled
        command: ["vpnctl", "providers"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n").filter(p => p);
                if (l.join() !== root.installed.join()) root.installed = l;
            }
        }
    }
    // a client installed (or removed) while the shell runs shows up without a restart
    Timer { interval: 30000; running: true; repeat: true; onTriggered: if (!listInstalled.running) listInstalled.running = true }

    onProviderChanged: restartWatch()
    function restartWatch() {
        state = "Disconnected";
        vpnIp = "";
        fwActive = false;
        pending = "";
        pendingKs = "";
        mvLockKnown = false;
        applyConf();
        loadRegions();
        mvMon.running = false;
        mvRestart.stop();
        if (provider === "pia") piaSettings.reload();
        if (provider === "mullvad") { mvOnce.running = true; mvMon.running = true; }
    }

    Process {
        id: regionList
        command: ["vpnctl", "regions"]
        stdout: StdioCollector {
            onStreamFinished: root.regions = text.trim().split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                const i = l.indexOf("\t");
                return { id: l.slice(0, i), label: l.slice(i + 1) };
            })
        }
    }
    function loadRegions() { regions = []; if (provider !== "") { regionList.running = false; regionList.running = true; } }
    // the list needs the daemon up (it may only just have started)
    onAvailableChanged: if (available && regions.length === 0) loadRegions()

    // ── PIA ─────────────────────────────────────────────────────────────────
    // live connection state (CPU-limited; piactl monitor can spin while the daemon restarts)
    Process {
        id: piaMon
        command: ["setpriv", "--pdeathsig", "SIGTERM", "prlimit", "--cpu=15:20", "piactl", "monitor", "connectionstate"]
        running: root.provider === "pia"
        stdout: SplitParser { onRead: line => { if (root.provider !== "pia") return; root.state = line.trim(); piaDetails.running = true; } }
        onExited: if (root.provider === "pia") { root.state = "Unavailable"; piaRestart.start(); }
    }
    Timer { id: piaRestart; interval: 3000; onTriggered: if (root.provider === "pia") piaMon.running = true }
    Process {
        id: piaDetails
        command: ["sh", "-c", "timeout 4 piactl get vpnip"]
        stdout: StdioCollector { onStreamFinished: { const v = text.trim(); root.vpnIp = v === "Unknown" ? "" : v; } }
    }
    FileView {
        id: piaSettings
        path: "/opt/piavpn/etc/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.provider !== "pia") return;
            try {
                const j = JSON.parse(text());
                root.region = j.location || "auto";
                root.killswitch = j.killswitch || "auto";
                const school = j.protocol === "tcp" && j.remotePortTCP === 443 && j.automaticTransport === false;
                root.liveMethod = j.method === "openvpn" ? (school ? "school" : "auto") : "wireguard";
            } catch (e) {}
        }
    }

    // ── Mullvad ─────────────────────────────────────────────────────────────
    property bool mvLockKnown: false
    function mvApply(line) {
        if (root.provider !== "mullvad" || line.charAt(0) !== "{") return;
        let j;
        try { j = JSON.parse(line); } catch (e) { return; }
        const map = { connected: "Connected", connecting: "Connecting", disconnecting: "Disconnecting", disconnected: "Disconnected", error: "Interrupted" };
        if (!j || !map[j.state]) return;    // other daemon events
        state = map[j.state];
        const d = j.details || {};
        vpnIp = j.state === "connected" && d.location && d.location.ipv4 ? d.location.ipv4 : "";
        if (j.state === "disconnected" && typeof d.locked_down === "boolean") {
            mvLockKnown = true;
            killswitch = d.locked_down ? "on" : "auto";
        }
        fwActive = j.state === "error" || (j.state === "disconnected" && d.locked_down === true);
    }
    Process {
        id: mvOnce
        command: ["mullvad", "status", "--json"]
        stdout: SplitParser { onRead: line => root.mvApply(line) }
        onExited: code => { if (code !== 0 && root.provider === "mullvad") root.state = "Unavailable"; }
    }
    Process {
        id: mvMon
        command: ["setpriv", "--pdeathsig", "SIGTERM", "mullvad", "status", "listen", "--json"]
        stdout: SplitParser { onRead: line => root.mvApply(line) }
        onExited: if (root.provider === "mullvad") { root.state = "Unavailable"; mvRestart.start(); }
    }
    Timer { id: mvRestart; interval: 5000; onTriggered: if (root.provider === "mullvad") { mvOnce.running = true; mvMon.running = true; } }

    // ── IVPN: Ivpn.qml polls `ivpn status` (no event stream); mirror it here ──
    property bool ivPersistent: false
    Connections {
        target: Ivpn
        function onStatusParsed() {
            if (root.provider !== "ivpn") return;
            const v = Ivpn.vpn;
            root.state = v === "" ? "Unavailable" : v === "CONNECTED" ? "Connected"
                : (v === "DISCONNECTED" || v === "PAUSED" || v === "INITIALISED") ? "Disconnected"
                : v === "EXITING" ? "Disconnecting" : v === "RECONNECTING" ? "Reconnecting" : "Connecting";
            root.ivPersistent = Ivpn.fwPersistent;
            root.fwActive = Ivpn.fwEnabled && !Ivpn.connected;
            root.vpnIp = Ivpn.localIp;
            if (Ivpn.connected && Ivpn.liveMethod !== "") root.liveMethod = Ivpn.liveMethod;
            if (Ivpn.connected && Ivpn.entry) root.region = (root.conf.ivpnRegion && /^[A-Z]{2}$|^auto$/.test(root.conf.ivpnRegion)) ? root.conf.ivpnRegion : Ivpn.entry.key;
            root.applyConf();
        }
    }

    // network-login (per-network automation) switches the VPN method through this:
    //   qs -c caelestia ipc call vpn <wg|school|auto|off>
    IpcHandler {
        target: "vpn"
        function wg(): void { root.useWireguard(); }
        function wireguard(): void { root.useWireguard(); }
        function school(): void { root.useSchool(); }
        function auto(): void { root.useOpenvpnAuto(); }
        function off(): void { root.disconnect(); }
        function toggle(): void { root.toggle(); }
        function state(): string { return root.state; }
        function choice(): string { return root.choice; }
        function provider(): string { return root.provider; }
        function use(p: string): void { root.setProvider(p); }
    }
}
