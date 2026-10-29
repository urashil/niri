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
    property bool autoConnect: true          // connect once per login (vpn-autoconnect, started by niri)

    // from /opt/piavpn/etc/settings.json (world-readable)
    property string transport: "udp"
    property int tcpPort: 0
    property bool autoTransport: true
    property string killswitch: "auto"
    readonly property bool schoolConfigured: transport === "tcp" && tcpPort === 443 && !autoTransport

    // what the user picked, shown at once; cleared when PIA reports it (or after 25 s)
    property string pending: ""          // "" | wireguard | school | auto
    property string pendingKs: ""        // "" | on | auto | off
    readonly property string choice: pending !== "" ? pending : method === "wireguard" ? "wireguard" : schoolConfigured ? "school" : "auto"
    readonly property string ksMode: pendingKs !== "" ? pendingKs : killswitch
    // traffic is cut while the killswitch is armed and the tunnel is not up
    readonly property bool blocked: ksMode === "on" ? state !== "Connected" : ksMode === "auto" ? (state === "Interrupted" || state === "Reconnecting") : false

    readonly property bool connected: state === "Connected"
    readonly property bool busy: state === "Connecting" || state === "Reconnecting" || state === "DisconnectingToReconnect" || state === "Disconnecting"
    readonly property string label: choice === "wireguard" ? "WireGuard" : choice === "school" ? "OpenVPN · TCP 443" : "OpenVPN · auto"

    function pretty(id) {
        if (id === "auto") return "Auto";
        return id.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    function connect()    { run(["sh", "-c", "piactl background enable; timeout 20 piactl connect"]); }
    function disconnect() { run(["piactl", "disconnect"]); }
    function toggle()     { if (connected || busy) disconnect(); else connect(); }
    function setRegion(r) { run(["sh", "-c", "piactl set region '" + r + "'" + (connected ? " && piactl connect" : "")]); }
    function setAllowLan(on) { run(["piactl", "set", "allowlan", on ? "true" : "false"]); }
    function setPortForward(on) { run(["piactl", "set", "requestportforward", on ? "true" : "false"]); }

    // WireGuard: one piactl call, no password.
    function useWireguard() {
        pick("wireguard");
        run(["sh", "-c", "piactl set protocol wireguard && piactl background enable; timeout 20 piactl connect"]);
    }
    // OpenVPN over TCP 443 (the only thing a locked-down school network lets through).
    // The very first time, the transport has to be pinned in the daemon settings, which needs root once.
    function useSchool() {
        pick("school");
        if (schoolConfigured) {
            run(["sh", "-c", "piactl set protocol openvpn && piactl background enable; timeout 20 piactl connect"]);
        } else {
            // first time only: pin TCP/443 in the daemon settings (helper restarts the daemon), then connect
            run(["sh", "-c", "pkexec /usr/local/lib/rice/net-helper pia school && piactl set protocol openvpn && piactl background enable; timeout 20 piactl connect"]);
        }
    }
    function useOpenvpnAuto() {
        pick("auto");
        run(["sh", "-c", "pkexec /usr/local/lib/rice/net-helper pia auto; piactl set protocol openvpn && piactl background enable; timeout 20 piactl connect"]);
    }

    // killswitch: always (blocks everything while the VPN is down) / auto (only while it should be up) / off
    function setKillswitch(mode) {
        if (mode === killswitch && pendingKs === "") return;      // nothing to change: restarting the daemon would only drop the tunnel
        pendingKs = mode;
        pendingTimer.restart();
        const reconnect = connected || busy;
        run([Quickshell.env("HOME") + "/.local/bin/pia-killswitch", mode].concat(reconnect ? ["reconnect"] : []));
    }
    function pick(c) { pending = c; pendingTimer.restart(); }
    Timer { id: pendingTimer; interval: 25000; onTriggered: { root.pending = ""; root.pendingKs = ""; } }
    onMethodChanged: if (pending !== "" && ((pending === "wireguard") === (method === "wireguard"))) pending = ""
    onKillswitchChanged: if (pendingKs === killswitch) pendingKs = ""

    property string lastError: ""
    function run(cmd) { lastError = ""; act.command = cmd; act.running = true; }
    Process {
        id: act
        stderr: StdioCollector { id: actErr }
        onExited: code => { if (code !== 0) root.lastError = actErr.text.trim().split("\n").pop() || ("failed (" + code + ")"); }
    }

    // ---- live state ----
    // One `piactl monitor` (connection state). Settings (region, protocol, allow LAN, port forward request) come from
    // settings.json below; the IPs and forwarded port are read with `piactl get` whenever the state changes.
    // When the daemon restarts, piactl monitor can spin reconnecting at full CPU, so it runs under a CPU-time limit
    // (an idle monitor uses next to none): a spinning one is killed and restarted with backoff.
    Process {
        id: mon
        property int fails: 0
        property real startedAt: 0
        // pdeathsig: the monitor dies with the shell instead of being left behind
        command: ["setpriv", "--pdeathsig", "SIGTERM", "prlimit", "--cpu=15:20", "piactl", "monitor", "connectionstate"]
        running: true
        stdout: SplitParser { onRead: line => { root.state = line.trim(); details.later(); } }
        onStarted: startedAt = Date.now()
        // while the daemon is down (restarting, no network) piactl exits at once: back off instead of respawning every 3 s forever
        onExited: {
            fails = Date.now() - startedAt < 60000 ? Math.min(fails + 1, 5) : 0;
            restartMon.interval = 3000 * Math.pow(2, fails);
            restartMon.start();
        }
    }
    Timer { id: restartMon; interval: 3000; onTriggered: mon.running = true }

    Process {
        id: details
        property int left: 0
        // read now, and again a few times: the public IP and forwarded port arrive some seconds after "Connected"
        function later() { left = 3; detailsTimer.interval = 500; detailsTimer.restart(); }
        command: ["sh", "-c", "for k in vpnip pubip portforward; do printf '%s %s\\n' $k \"$(timeout 4 piactl get $k)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const i = l.indexOf(" "), k = l.slice(0, i), v = l.slice(i + 1).trim();
                    if (k === "vpnip") root.vpnIp = v === "Unknown" ? "" : v;
                    else if (k === "pubip") root.pubIp = v === "Unknown" ? "" : v;
                    else if (k === "portforward" && v !== "") root.forwardedPort = v;
                }
            }
        }
        onExited: if (left > 0) { detailsTimer.interval = 5000; detailsTimer.restart(); }
    }
    Timer { id: detailsTimer; onTriggered: if (!details.running) { details.left--; details.running = true; } }

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
                root.region = j.location || "auto";
                root.allowLan = j.allowLAN === true;
                root.requestPortForward = j.portForward === true;
            } catch (e) {}
        }
    }
    function setAutoConnect(on) {
        autoConnect = on;
        run(["~/.local/bin/vpn-autoconnect".replace("~", Quickshell.env("HOME")), on ? "on" : "off"]);
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/vpn.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.autoConnect = JSON.parse(text()).autoConnect !== false; } catch (e) {} }
    }
    Component.onCompleted: loadRegions()
}
