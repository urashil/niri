pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everything the IVPN client can tell us and do, for the IVPN menu (modules/bar/popouts/IvpnMenu.qml).
// Tunnel.qml takes its generic VPN state from here when IVPN is the provider.
// The CLI has no event stream or JSON, so `ivpn status` is polled (faster while the menu is open or the
// tunnel is changing) and the rest (account, DNS, keys, Wi-Fi, split tunnel) is read when the menu opens
// and after every change.
Singleton {
    id: root

    readonly property bool enabled: Tunnel.provider === "ivpn"
    property int watchers: 0                  // open menus
    readonly property bool open: watchers > 0

    // ── status (`ivpn status`) ──────────────────────────────────────────────
    property string vpn: ""                   // CONNECTED | DISCONNECTED | CONNECTING | PAUSED | ... ("" = daemon not answering)
    readonly property bool connected: vpn === "CONNECTED"
    readonly property bool paused: vpn === "PAUSED"
    readonly property bool busy: vpn !== "" && !connected && !paused && vpn !== "DISCONNECTED" && vpn !== "INITIALISED"
    property string pausedTill: ""
    property bool unhealthy: false
    property var entry: null                  // { gateway, host, city, cc, country }
    property var exit: null                   // Multi-Hop exit, same shape
    property string protocol: ""              // "WireGuard (V2Ray: VMESS/TCP)" etc.
    property string localIp: ""
    property string localIp6: ""
    property string serverIp: ""
    property string serverPort: ""            // "TCP:443"
    property double since: 0                  // ms epoch
    property string dnsLine: ""
    property bool loggedIn: true
    property bool fwEnabled: false
    property bool fwPersistent: false
    property bool fwAllowLan: false
    property bool fwAllowIvpn: true
    property string fwExceptions: ""
    property string splitLine: ""             // "Disabled" | "Enabled" | "Enabled (INVERSE MODE)"
    readonly property bool splitOn: splitLine.startsWith("Enabled")
    readonly property bool splitInverse: splitLine.indexOf("INVERSE") >= 0
    property var splitApps: []                // [{ pid, cmd }]
    signal statusParsed

    readonly property string liveMethod: protocol.indexOf("VMESS/QUIC") >= 0 ? "stealth-quic"
        : protocol.indexOf("VMESS/TCP") >= 0 ? "stealth"
        : protocol.indexOf("Obfsproxy") >= 0 ? "obfs4"
        : protocol.startsWith("WireGuard") ? "wireguard"
        : protocol.startsWith("OpenVPN") ? (serverPort === "TCP:443" ? "school" : "auto") : ""

    // ── settings (one command each) ─────────────────────────────────────────
    property string accountId: ""
    property string plan: ""
    property double activeUntil: 0
    property bool atEnabled: false
    property bool atHardcore: false
    property string atList: ""
    property var blocklists: []               // [{ name, details }]
    property string customDns: ""             // what `ivpn dns` reports, "" = default
    property bool autoconnectLaunch: false
    property string wifiNetwork: ""
    property bool wifiControl: false
    property string wifiDefault: ""           // trusted | untrusted | none
    property var wifiNetworks: ({})           // name -> trusted | untrusted
    property bool wifiUntrustedConnect: true
    property bool wifiUntrustedFirewall: true
    property bool wifiUntrustedBlockLan: true
    property bool wifiTrustedDisconnect: true
    property bool wifiTrustedFirewallOff: true
    property string keyGenerated: ""
    property int keyRotationDays: 1
    property bool quantumResistant: false

    // ── connection options (vpnctl keeps them, in ~/.config/rice/vpn.json) ──
    readonly property string method: Tunnel.conf.ivpnMethod || "wireguard"
    readonly property string port: Tunnel.conf.ivpnPort || ""
    readonly property string region: Tunnel.conf.ivpnRegion || "auto"
    readonly property string exitKey: Tunnel.conf.ivpnExit || ""
    readonly property bool ipv6: Tunnel.conf.ivpnIpv6 === true
    readonly property int mtu: Tunnel.conf.ivpnMtu || 0
    readonly property bool wgMethod: method === "wireguard" || method.startsWith("stealth")

    // label: short (menu tiles); full: everywhere else (lock screen, toasts, the generic popout)
    readonly property var methods: [
        { id: "wireguard", label: "WireGuard", full: "WireGuard", sub: "Fastest; UDP" },
        { id: "stealth", label: "V2Ray · TCP", full: "WireGuard · V2Ray TCP", sub: "WireGuard that looks like HTTPS on TCP 443" },
        { id: "stealth-quic", label: "V2Ray · QUIC", full: "WireGuard · V2Ray QUIC", sub: "WireGuard that looks like HTTP/3 on UDP 443" },
        { id: "school", label: "OpenVPN · TCP", full: "OpenVPN · TCP", sub: "TCP 443 by default" },
        { id: "auto", label: "OpenVPN · UDP", full: "OpenVPN · UDP", sub: "UDP 2049 by default" },
        { id: "obfs4", label: "OpenVPN · obfs4", full: "OpenVPN · obfs4", sub: "obfsproxy, for DPI-heavy networks" }
    ]
    function methodLabel(m) { const e = methods.find(x => x.id === m); return e ? e.full : m; }
    // port presets per method; "" = the method's default
    function portsFor(m) {
        if (m === "wireguard") return ["", "udp:53", "udp:80", "udp:123", "udp:443", "udp:500", "udp:1194", "udp:4500"];
        if (m === "stealth") return ["", "tcp:80"];          // default tcp:443
        if (m === "stealth-quic") return ["", "udp:80"];     // default udp:443
        if (m === "school") return ["", "tcp:80", "tcp:1194", "tcp:2049"];
        if (m === "auto") return ["", "udp:53", "udp:80", "udp:443", "udp:1194"];
        return [];
    }
    function defaultPort(m) {
        return m === "wireguard" ? "UDP 2049" : m === "stealth" ? "TCP 443" : m === "stealth-quic" ? "UDP 443"
            : m === "school" ? "TCP 443" : m === "auto" ? "UDP 2049" : "";
    }

    // ── servers ─────────────────────────────────────────────────────────────
    // locations keyed by gateway prefix ("us-ut" for us-ut.wg.ivpn.net / us-ut.gw.ivpn.net)
    property var locations: []                // [{ key, city, cc, country, isp, wg, ovpn, ipv6 }]
    property var pings: ({})                  // key -> ms
    property bool pinging: false
    readonly property var countries: {
        const seen = {};
        const out = [];
        for (const l of locations)
            if (!seen[l.cc]) { seen[l.cc] = true; out.push({ cc: l.cc, country: l.country }); }
        return out.sort((a, b) => a.country.localeCompare(b.country));
    }
    function location(key) { return locations.find(l => l.key === key) ?? null; }
    function regionLabel(id) {
        if (!id || id === "auto") return "Fastest";
        if (/^[A-Z]{2}$/.test(id)) { const c = countries.find(x => x.cc === id); return c ? c.country : id; }
        const l = location(id);
        return l ? l.city + ", " + l.cc : id;
    }
    function flag(cc) {
        if (!cc || cc.length !== 2) return "";
        return String.fromCodePoint(0x1F1E6 + cc.charCodeAt(0) - 65, 0x1F1E6 + cc.charCodeAt(1) - 65);
    }

    // ── actions ─────────────────────────────────────────────────────────────
    property string error: ""
    property string note: ""
    property string working: ""               // label of the running action
    Timer { id: noteTimer; interval: 6000; onTriggered: { root.error = ""; root.note = ""; } }
    property var actions: []
    // ivpn(["firewall", "-lan_allow"], "Allowing LAN") / vpnctl(["ivpn-set", "method", "stealth"], "Switching")
    function ivpn(args, label) { queue(["ivpn"].concat(args), label); }
    function vpnctl(args, label) { queue(["vpnctl"].concat(args), label); }
    function queue(cmd, label) {
        actions = actions.concat([{ cmd: cmd, label: label || "" }]);
        if (!act.running) next();
    }
    function next() {
        if (actions.length === 0) { working = ""; return; }
        const a = actions[0];
        actions = actions.slice(1);
        working = a.label;
        act.label = a.label;
        act.command = a.cmd;
        act.running = true;
    }
    Process {
        id: act
        property string label
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            if (code !== 0) {
                const lines = (actErr.text + "\n" + actOut.text).split("\n").map(l => l.trim())
                    .filter(l => l && !l.startsWith("Tips") && !l.startsWith("ivpn ") && !/^Usage|^Command usage/.test(l));
                const e = lines.find(l => /error|not |unable|failed|specify|denied|cannot/i.test(l)) || lines.pop() || "failed";
                root.error = (act.label ? act.label + ": " : "") + e.replace(/^Error[.:]?\s*/i, "");
                root.note = "";
            } else if (act.label) {
                root.note = act.label + " · done";
                root.error = "";
            }
            noteTimer.restart();
            root.refresh();
            root.next();
        }
    }

    function connect() { vpnctl(["connect"], "Connecting"); }
    function disconnect() { vpnctl(["disconnect"], "Disconnecting"); }
    function reconnect() { vpnctl(["connect"], "Reconnecting"); }
    function pause(min) { ivpn(["connection", "-pause", String(min)], "Pausing " + min + " min"); }
    function resume() { ivpn(["connection", "-resume"], "Resuming"); }
    // connection options: vpnctl stores them and reconnects if the tunnel is up
    function set(opts, label) {
        let args = ["ivpn-set"];
        for (const k in opts) args.push(k, String(opts[k]));
        vpnctl(args, label || "Applying");
    }
    function setMethod(m) { set({ method: m, port: "" }, methodLabel(m)); }
    function setRegion(id) {
        // a country or Fastest can't be a Multi-Hop entry
        if (exitKey !== "" && !/^[a-z0-9-]+$/.test(id)) set({ region: id, exit: "" }, "Server " + regionLabel(id) + " (Multi-Hop off)");
        else set({ region: id }, "Server " + regionLabel(id));
    }
    function setExit(key) { set({ exit: key }, key ? "Exit " + regionLabel(key) : "Single hop"); }

    function setAntitracker(mode, list) {
        const l = list !== undefined ? list : atList;
        if (mode === "off") ivpn(["antitracker", "-off"], "AntiTracker off");
        else ivpn(["antitracker", mode === "hardcore" ? "-on_hardcore" : "-on"].concat(l ? [l] : []), "AntiTracker " + (mode === "hardcore" ? "hardcore" : "on"));
        reconnectIfUp();
    }
    function setDns(ip, doh) {
        if (!ip) { ivpn(["dns", "-off"], "DNS back to IVPN"); }
        else ivpn(["dns"].concat(doh ? ["-doh", doh] : []).concat([ip]), "Custom DNS");
        reconnectIfUp();
    }
    // DNS / AntiTracker defaults apply on the next connect
    function reconnectIfUp() { if (connected) reconnect(); }

    // ── polling ─────────────────────────────────────────────────────────────
    Timer {
        interval: root.busy ? 1500 : root.open ? 2000 : 4000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!statusProc.running) statusProc.running = true
    }
    onOpenChanged: if (open) { refresh(); if (locations.length === 0) loadServers(); }
    onEnabledChanged: if (enabled && open) refresh()

    function parseTime(t) {   // "2026-11-10 12:27:43 -0800 PST"
        const m = (t || "").match(/(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d) ([+-]\d\d)(\d\d)/);
        return m ? new Date(m[1] + "T" + m[2] + m[3] + ":" + m[4]).getTime() : 0;
    }
    function parseServer(line) {   // "us-ut.wg.ivpn.net [us-ut2.wg.ivpn.net], Salt Lake City, Utah (US), United States"
        const m = line.match(/^(\S+) \[([^\]]*)\], (.*) \(([A-Z]{2})\), (.*?)( \(Multi-Hop exit server\))?$/);
        return m ? { gateway: m[1], key: m[1].split(".")[0], host: m[2], city: m[3], cc: m[4], country: m[5], isExit: !!m[6] } : null;
    }
    Process {
        id: statusProc
        command: ["timeout", "8", "ivpn", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const kv = {};
                let en = null, ex = null, apps = [];
                for (const raw of lines) {
                    const i = raw.indexOf(":");
                    const key = i > 0 ? raw.slice(0, i).trim() : "";
                    if (/^\s+\S/.test(raw) && (i < 0 || raw.indexOf(" [") > 0 && raw.indexOf(" [") < i)) {
                        const s = root.parseServer(raw.trim());
                        if (s) { if (s.isExit) ex = s; else en = s; }
                        continue;
                    }
                    if (raw.indexOf("WARNING! Unhealthy") >= 0) kv.unhealthy = "1";
                    if (key === "Running commands") { const m = raw.match(/\[pid:(\d+)\]\s*(.*)$/); if (m) apps.push({ pid: m[1], cmd: m[2] }); continue; }
                    if (key && kv[key] === undefined) kv[key] = raw.slice(i + 1).trim();
                }
                const v = (kv["VPN"] || "").split(/\s+/);
                root.vpn = v[0] || "";
                root.pausedTill = root.vpn === "PAUSED" ? (kv["VPN"] || "").replace(/^PAUSED\s*(till\s*)?/, "") : "";
                root.unhealthy = !!kv.unhealthy;
                root.loggedIn = !(kv["Account"] || "").startsWith("Not logged in");
                root.entry = en;
                root.exit = ex;
                root.protocol = root.connected ? (kv["Protocol"] || "") : "";
                root.localIp = root.connected ? (kv["Local IP"] || "") : "";
                root.localIp6 = root.connected ? (kv["Local IPv6"] || "") : "";
                const sip = (kv["Server IP"] || "").match(/^(\S+)(?: \((\w+:\d+)\))?/);
                root.serverIp = root.connected && sip ? sip[1] : "";
                root.serverPort = root.connected && sip && sip[2] ? sip[2] : "";
                root.since = root.connected ? root.parseTime(kv["Connected"]) : 0;
                root.dnsLine = kv["AntiTracker"] !== undefined ? "AntiTracker " + kv["AntiTracker"] : (kv["DNS"] || "");
                root.splitLine = kv["Split Tunnel"] || "Disabled";
                root.splitApps = apps;
                root.fwEnabled = (kv["Firewall"] || "").startsWith("Enabled");
                root.fwPersistent = kv["Persistent"] === "true";
                root.fwAllowLan = kv["Allow LAN"] === "true";
                root.fwAllowIvpn = kv["Allow IVPN servers"] !== "false";
                root.fwExceptions = kv["Allow IP masks"] || "";
                root.statusParsed();
            }
        }
        onExited: code => { if (code !== 0 && code !== 1) { root.vpn = ""; root.statusParsed(); } }
    }

    // settings: read in one go
    function refresh() { if (enabled && !settingsProc.running) settingsProc.running = true; }
    Process {
        id: settingsProc
        command: ["sh", "-c", "for c in account antitracker dns autoconnect wifi wgkeys 'splittun -status_full'; do echo \"@@ $c\"; timeout 8 ivpn $c 2>&1; done; echo '@@ blocklists'; timeout 8 ivpn antitracker -show_blocklists 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = {};
                let cur = "";
                for (const l of text.split("\n")) {
                    if (l.startsWith("@@ ")) { cur = l.slice(3).split(" ")[0]; parts[cur] = []; continue; }
                    if (cur) parts[cur].push(l);
                }
                const val = (sect, label) => {
                    for (const l of parts[sect] || []) {
                        const i = l.indexOf(":");
                        if (i > 0 && l.slice(0, i).trim() === label) return l.slice(i + 1).trim();
                    }
                    return "";
                };
                root.accountId = val("account", "Account ID");
                root.plan = val("account", "Plan");
                root.activeUntil = root.parseTime(val("account", "Active until"));

                const at = (parts.antitracker || []).join("\n");
                root.atEnabled = /AntiTracker\s*:?\s*Enabled/.test(at) || /AntiTracker Enabled/.test(at);
                root.atHardcore = root.atEnabled && /Hardcore/.test(at);
                const bl = at.match(/block list: '([^']+)'/);
                root.atList = bl ? bl[1] : "";

                const dns = (parts.dns || []).join("\n");
                const cd = dns.match(/Custom DNS (.*)/);
                root.customDns = cd && !/not defined/.test(cd[1]) ? cd[1].trim()
                    : (val("dns", "DNS") && !/Default/.test(val("dns", "DNS")) ? val("dns", "DNS") : "");

                root.autoconnectLaunch = val("autoconnect", "Autoconnect on daemon launch").startsWith("Enabled");

                root.wifiNetwork = val("wifi", "Connected WiFi network");
                root.wifiControl = val("wifi", "Trusted/Untrusted WiFi network control").startsWith("Enabled");
                const ds = val("wifi", "Default trust status for undefined networks").toLowerCase();
                root.wifiDefault = ds.indexOf("untrusted") >= 0 ? "untrusted" : ds.indexOf("trusted") >= 0 ? "trusted" : "none";
                // the action lines repeat labels (two "Disable firewall"-ish rows), so read them in order
                const w = parts.wifi || [];
                const on = re => { const l = w.find(x => re.test(x)); return l ? /Enabled\s*$/.test(l) : false; };
                root.wifiUntrustedConnect = on(/Connect to VPN/);
                root.wifiUntrustedFirewall = on(/Enable firewall/);
                root.wifiUntrustedBlockLan = on(/Block LAN traffic/);
                root.wifiTrustedDisconnect = on(/Disconnect from VPN/);
                root.wifiTrustedFirewallOff = on(/Disable firewall/);
                const nets = {};
                let inNets = false;
                for (const l of w) {
                    if (/^Networks/.test(l)) { inNets = true; const m = l.match(/^Networks\s*:\s*(.*)$/); if (m && /not defined/.test(m[1])) inNets = false; continue; }
                    if (!inNets) continue;
                    if (/^\S/.test(l) || /^Tips/.test(l.trim())) { inNets = false; continue; }
                    const m = l.match(/^\s+(.*?)\s*:\s*(trusted|untrusted)\s*$/i);
                    if (m) nets[m[1].replace(/^'|'$/g, "")] = m[2].toLowerCase();
                }
                root.wifiNetworks = nets;

                root.keyGenerated = val("wgkeys", "Generated");
                const rot = val("wgkeys", "Rotation interval").match(/(\d+)h/);
                root.keyRotationDays = rot ? Math.max(1, Math.round(parseInt(rot[1]) / 24)) : 1;
                root.quantumResistant = val("wgkeys", "Quantum Resistance").startsWith("Enabled");

                const lists = [];
                for (const l of parts.blocklists || []) {
                    const m = l.match(/^\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|$/);
                    if (m && m[1] && m[1] !== "DNS BLOCK LIST NAME") lists.push({ name: m[1], details: m[2] });
                }
                if (lists.length) root.blocklists = lists;
            }
        }
    }

    function loadServers() { if (enabled && !serversProc.running) serversProc.running = true; }
    function ping() { if (enabled && !pingProc.running) { pinging = true; pingProc.running = true; } }
    function parseRows(text) {
        const rows = [];
        for (const l of text.split("\n")) {
            const c = l.split("|").map(x => x.trim());
            if (c.length < 6 || (c[0] !== "WireGuard" && c[0] !== "OpenVPN")) continue;
            const city = c[2].match(/^(.*) \(([A-Z]{2})\)$/);
            if (!city) continue;
            rows.push({ proto: c[0], gateway: c[1], key: c[1].split(".")[0], city: city[1], cc: city[2], country: c[3], isp: c[4], ipv6: c[5].indexOf("IPv6") >= 0, ping: c[6] || "" });
        }
        return rows;
    }
    Process {
        id: serversProc
        command: ["timeout", "20", "ivpn", "servers"]
        stdout: StdioCollector {
            onStreamFinished: {
                const by = {};
                for (const r of root.parseRows(text)) {
                    const l = by[r.key] || (by[r.key] = { key: r.key, city: r.city, cc: r.cc, country: r.country, isp: r.isp, wg: false, ovpn: false, ipv6: false });
                    if (r.proto === "WireGuard") { l.wg = true; l.ipv6 = l.ipv6 || r.ipv6; } else l.ovpn = true;
                }
                const list = Object.values(by).sort((a, b) => a.country.localeCompare(b.country) || a.city.localeCompare(b.city));
                if (list.length) root.locations = list;
            }
        }
    }
    Process {
        id: pingProc
        command: ["timeout", "60", "ivpn", "servers", "-ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = {};
                for (const r of root.parseRows(text)) {
                    const m = r.ping.match(/(\d+)ms/);
                    if (m) p[r.key] = Math.min(p[r.key] || 99999, parseInt(m[1]));
                }
                root.pings = p;
                root.pinging = false;
            }
        }
        onExited: root.pinging = false
    }
}
