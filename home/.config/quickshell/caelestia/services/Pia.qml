pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Private Internet Access via piactl. State comes from `piactl monitor` so it updates live.
// (The host's VPN is PIA, not a NetworkManager profile, so caelestia's VPN service can't see it.)
Singleton {
    id: root

    property string state: "Disconnected"
    property string region: "auto"
    property string vpnIp: ""
    property string pubIp: ""

    // connection method (piactl "protocol"): wireguard | openvpn. "school" = OpenVPN pinned to TCP/443,
    // the only transport a locked-down network lets through. Read from /opt/piavpn/etc/settings.json below.
    property string method: "wireguard"
    property string transport: "udp"
    property int tcpPort: 0
    property bool autoTransport: true
    property string pending: "" // optimistic UI: "" | wireguard | school | auto, cleared when PIA reports it
    readonly property bool schoolConfigured: transport === "tcp" && tcpPort === 443 && !autoTransport
    readonly property string choice: pending !== "" ? pending : method === "wireguard" ? "wireguard" : schoolConfigured ? "school" : "auto"
    readonly property string label: choice === "wireguard" ? "WireGuard" : choice === "school" ? "OpenVPN · TCP 443" : "OpenVPN · auto"

    readonly property bool connected: state === "Connected"
    readonly property bool busy: state === "Connecting" || state === "Reconnecting" || state === "DisconnectingToReconnect" || state === "Disconnecting"

    // kill switch: on (block everything while VPN down) / auto (only while it should be up) / off
    property string killswitch: "auto"
    property string pendingKs: ""
    readonly property string ksMode: pendingKs !== "" ? pendingKs : killswitch
    readonly property bool blocked: ksMode === "on" ? state !== "Connected" : ksMode === "auto" ? (state === "Interrupted" || state === "Reconnecting") : false
    function setKillswitch(mode) {
        if (mode === killswitch && pendingKs === "")
            return;
        pendingKs = mode;
        pendingTimer.restart();
        const reconnect = connected || busy;
        run([Quickshell.env("HOME") + "/.local/bin/pia-killswitch", mode].concat(reconnect ? ["reconnect"] : []));
    }
    Timer { id: pendingTimer; interval: 25000; onTriggered: root.pendingKs = "" }
    onKillswitchChanged: if (pendingKs === killswitch) pendingKs = ""

    function pretty(id) {
        if (!id || id === "auto")
            return "Auto";
        return id.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    function connect() { run(["sh", "-c", "piactl background enable; timeout 20 piactl connect"]); }
    function disconnect() { run(["piactl", "disconnect"]); }
    function toggle() { if (connected || busy) disconnect(); else connect(); }
    function setRegion(r) { run(["sh", "-c", "piactl set region '" + r + "'" + (connected ? " && piactl connect" : "")]); }

    // method switching (optimistic): the chip lights up at once, PIA clears `pending` when it catches up
    Timer { id: pendingVpnTimer; interval: 25000; onTriggered: root.pending = "" }
    function pick(c) { pending = c; pendingVpnTimer.restart(); }
    onMethodChanged: if (pending === "wireguard" && method === "wireguard") pending = "";
    onSchoolConfiguredChanged: if ((pending === "school" && schoolConfigured) || (pending === "auto" && method === "openvpn" && !schoolConfigured)) pending = "";

    function useWireguard() {
        pick("wireguard");
        run(["sh", "-c", "piactl set protocol wireguard && piactl background enable; timeout 20 piactl connect"]);
    }
    // OpenVPN over TCP 443. The first time, the transport is pinned in the daemon settings (root, once).
    function useSchool() {
        pick("school");
        if (schoolConfigured)
            run(["sh", "-c", "piactl set protocol openvpn && piactl background enable; timeout 20 piactl connect"]);
        else
            run(["sh", "-c", "pkexec /usr/local/lib/rice/net-helper pia school && piactl set protocol openvpn && piactl background enable; timeout 20 piactl connect"]);
    }
    function useOpenvpnAuto() {
        pick("auto");
        run(["sh", "-c", "pkexec /usr/local/lib/rice/net-helper pia auto; piactl set protocol openvpn && piactl background enable; timeout 20 piactl connect"]);
    }

    Process { id: act }
    function run(cmd) { act.command = cmd; act.running = true; }

    property var regions: []
    Process {
        id: regionList
        command: ["piactl", "get", "regions"]
        stdout: StdioCollector {
            onStreamFinished: root.regions = text.trim().split("\n").filter(r => r && r !== "auto").sort()
        }
    }
    function loadRegions() { regionList.running = true; }

    // live connection state (CPU-limited; piactl monitor can spin while the daemon restarts)
    Process {
        id: mon
        command: ["setpriv", "--pdeathsig", "SIGTERM", "prlimit", "--cpu=15:20", "piactl", "monitor", "connectionstate"]
        running: true
        stdout: SplitParser { onRead: line => { root.state = line.trim(); details.running = true; } }
        onExited: restartMon.start()
    }
    Timer { id: restartMon; interval: 3000; onTriggered: mon.running = true }

    Process {
        id: details
        command: ["sh", "-c", "for k in vpnip pubip; do printf '%s %s\\n' $k \"$(timeout 4 piactl get $k)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const i = l.indexOf(" ");
                    if (i < 0) continue;
                    const k = l.slice(0, i), v = l.slice(i + 1).trim();
                    if (k === "vpnip") root.vpnIp = v === "Unknown" ? "" : v;
                    else if (k === "pubip") root.pubIp = v === "Unknown" ? "" : v;
                }
            }
        }
    }

    FileView {
        path: "/opt/piavpn/etc/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.region = j.location || "auto";
                root.killswitch = j.killswitch || "auto";
                root.transport = j.protocol || "udp";
                root.tcpPort = j.remotePortTCP || 0;
                root.autoTransport = j.automaticTransport !== false;
                if (j.method) root.method = j.method;
            } catch (e) {}
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
    }

    Component.onCompleted: loadRegions()
}
