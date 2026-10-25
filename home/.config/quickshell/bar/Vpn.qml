pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Private Internet Access through piactl. State comes from `piactl monitor`, so changes show up instantly.
Singleton {
    id: root

    property string state: "Disconnected"
    property string region: "auto"
    property string method: "wireguard"      // piactl "protocol": wireguard | openvpn
    property string vpnIp: ""
    property string pubIp: ""
    property string forwardedPort: "Inactive"
    property bool allowLan: true
    property bool requestPortForward: false
    property var regions: []
    property bool available: true

    // from /opt/piavpn/etc/settings.json (world-readable)
    property string transport: "udp"
    property int tcpPort: 0
    property bool autoTransport: true
    property string killswitch: "auto"
    readonly property bool schoolConfigured: transport === "tcp" && tcpPort === 443 && !autoTransport

    readonly property bool connected: state === "Connected"
    readonly property bool busy: state === "Connecting" || state === "Reconnecting" || state === "DisconnectingToReconnect" || state === "Disconnecting"
    readonly property string label: method === "openvpn"
        ? (schoolConfigured ? "OpenVPN · TCP 443" : "OpenVPN · " + transport.toUpperCase() + (tcpPort > 0 && transport === "tcp" ? " " + tcpPort : ""))
        : "WireGuard"

    function pretty(id) {
        if (id === "auto") return "Auto";
        return id.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    function connect()    { run(["sh", "-c", "piactl background enable; piactl connect"]); }
    function disconnect() { run(["piactl", "disconnect"]); }
    function toggle()     { if (connected || busy) disconnect(); else connect(); }
    function setRegion(r) { run(["sh", "-c", "piactl set region '" + r + "'" + (connected ? " && piactl connect" : "")]); }
    function setAllowLan(on) { run(["piactl", "set", "allowlan", on ? "true" : "false"]); }
    function setPortForward(on) { run(["piactl", "set", "requestportforward", on ? "true" : "false"]); }

    // WireGuard: one piactl call, no password.
    function useWireguard() {
        run(["sh", "-c", "piactl set protocol wireguard && piactl background enable; piactl connect"]);
    }
    // OpenVPN over TCP 443 (the only thing a locked-down school network lets through).
    // The very first time, the transport has to be pinned in the daemon settings, which needs root once.
    function useSchool() {
        if (schoolConfigured) {
            run(["sh", "-c", "piactl set protocol openvpn && piactl background enable; piactl connect"]);
        } else {
            run(["sh", "-c", "pkexec /usr/local/lib/rice/net-helper pia school && sleep 2 && piactl set protocol openvpn && piactl background enable; piactl connect"]);
        }
    }
    function useOpenvpnAuto() {
        run(["sh", "-c", "piactl set protocol openvpn && piactl background enable; piactl connect"]);
    }

    property string lastError: ""
    function run(cmd) { lastError = ""; act.command = cmd; act.running = true; }
    Process {
        id: act
        stderr: StdioCollector { id: actErr }
        onExited: code => { if (code !== 0) root.lastError = actErr.text.trim().split("\n").pop() || ("failed (" + code + ")"); }
    }

    // ---- live state ----
    component Mon: Process {
        id: mon
        required property string what
        property var apply
        command: ["piactl", "monitor", what]
        running: true
        stdout: SplitParser { onRead: line => apply(line.trim()) }
        onExited: restart.start()
        property Timer restart: Timer { interval: 3000; onTriggered: mon.running = true }
    }
    Mon { what: "connectionstate"; apply: v => { root.state = v; } }
    Mon { what: "region"; apply: v => { root.region = v; } }
    Mon { what: "protocol"; apply: v => { root.method = v; } }
    Mon { what: "vpnip"; apply: v => { root.vpnIp = v === "Unknown" ? "" : v; } }
    Mon { what: "pubip"; apply: v => { root.pubIp = v === "Unknown" ? "" : v; } }
    Mon { what: "portforward"; apply: v => { root.forwardedPort = v; } }
    Mon { what: "allowlan"; apply: v => { root.allowLan = v === "true"; } }
    Mon { what: "requestportforward"; apply: v => { root.requestPortForward = v === "true"; } }

    Process {
        id: regionList
        command: ["piactl", "get", "regions"]
        stdout: StdioCollector {
            onStreamFinished: root.regions = text.trim().split("\n").filter(r => r && r !== "auto").sort()
        }
    }
    function loadRegions() { regionList.running = true; }

    FileView {
        path: "/opt/piavpn/etc/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.transport = j.protocol || "udp";
                root.tcpPort = j.remotePortTCP || 0;
                root.autoTransport = j.automaticTransport !== false;
                root.killswitch = j.killswitch || "auto";
                if (j.method) root.method = j.method;
            } catch (e) {}
        }
    }
    Component.onCompleted: loadRegions()
}
