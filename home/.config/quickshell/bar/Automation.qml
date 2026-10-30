pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Per-Wi-Fi-network rules, applied when you connect: VPN (WireGuard / OpenVPN TCP 443 / off) and quiet mode.
// Stored in ~/.config/rice/networks.json: { "<ssid>": { "vpn": "wg"|"443"|"off"|"", "dnd": true|false, "login": true|false, "ks": "on"|"auto"|"off"|"" } }
// "login": VPN + kill switch off, run ~/.config/rice/network-login.sh (captive portal), then kill switch "ks" and the VPN setting ("" = as before).
Singleton {
    id: root
    readonly property string path: Quickshell.env("HOME") + "/.config/rice/networks.json"
    property var rules: ({})
    property bool prevDnd: false
    property string appliedFor: ""
    property var lastApplied: ({})          // ssid -> ms of the last time its rule ran
    property int busyWaits: 0               // settle retries spent waiting for PIA to stop being busy

    function rule(ssid) { return rules[ssid] || { vpn: "", dnd: false, login: false, ks: "" }; }
    function set(ssid, key, value) {
        const r = JSON.parse(JSON.stringify(rules));
        r[ssid] = Object.assign({ vpn: "", dnd: false, login: false, ks: "" }, r[ssid] || {});
        r[ssid][key] = value;
        if (!r[ssid].vpn && !r[ssid].dnd && !r[ssid].login && !r[ssid].ks) delete r[ssid];
        rules = r;
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", path, JSON.stringify(r)];
        save.running = true;
    }

    Process { id: save }
    Process {
        id: signin
        property string ssid: ""
        // each step network-login prints stays in the island until the next one
        stdout: SplitParser { onRead: line => { if (line.trim() !== "") UiState.pulse("auto", "", signin.ssid + " · " + line.trim() + "…", -1, Theme.primary, 30000); } }
        onExited: code => UiState.pulse("auto", "", signin.ssid + (code === 0 ? " · done" : code === 3 ? " · sign-in failed, VPN left off" : " · sign-in script missing"),
                                         -1, code === 0 ? Theme.primary : Theme.red, code === 0 ? 3500 : 6000)
    }
    function startSignin(ssid, r) {
        if (signin.running) return;
        // what to restore afterwards: the rule's choice, else whatever was in use before
        const was = Vpn.connected || Vpn.busy ? (Vpn.choice === "wireguard" ? "wg" : Vpn.choice === "school" ? "443" : "auto") : "off";
        const vpn = r.vpn || was;
        signin.ssid = ssid;
        signin.command = ["network-login", vpn, r.ks || Vpn.killswitch, Wifi.dev, r.login ? "1" : "0"];
        signin.running = true;
    }
    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.rules = JSON.parse(text()); } catch (e) {} }
    }
    // the network whose rule already ran this login: a restarted shell must not run it again (a sign-in rule would drop the VPN)
    FileView {
        id: marker
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice-net-applied"
        blockLoading: true
        printErrors: false
    }
    property string startupApplied: marker.text().trim()
    function mark(ssid) {
        save.command = ["sh", "-c", "printf '%s' \"$2\" > \"$1\"", "_", marker.path, ssid];
        save.running = true;
    }

    function apply(ssid) {
        const r = rule(ssid);
        // a flapping link must not re-run the rule over and over (each run talks to the PIA daemon): once a minute per network at most,
        // and never while the previous run is still going
        if (Date.now() - (lastApplied[ssid] || 0) < 60000 || signin.running) return;
        // PIA still busy with the last network (e.g. "Reconnecting" after waking up somewhere new, which behind a portal never ends):
        // a sign-in rule disconnects it anyway; a plain VPN rule waits a little, then goes ahead
        if (Vpn.busy && !r.login && !r.ks && busyWaits < 6) { busyWaits++; settle.restart(); return; }
        busyWaits = 0;
        lastApplied[ssid] = Date.now();
        let did = [];
        if (r.dnd) { if (appliedFor === "") prevDnd = UiState.dnd; UiState.dnd = true; did.push("quiet"); }
        if (r.login || r.ks) startSignin(ssid, r);
        else if (r.vpn === "wg") { if (!(Vpn.connected && Vpn.choice === "wireguard")) Vpn.useWireguard(); did.push("WireGuard"); }
        else if (r.vpn === "443") { if (!(Vpn.connected && Vpn.choice === "school")) Vpn.useSchool(); did.push("OpenVPN 443"); }
        else if (r.vpn === "off") { Vpn.disconnect(); did.push("VPN off"); }
        appliedFor = ssid;
        slept = false;
        mark(ssid);
        if (did.length) UiState.pulse("auto", "", ssid + " · " + did.join(" · "), -1, Theme.primary, 3500);
    }
    function leave() {
        if (appliedFor !== "" && rule(appliedFor).dnd) UiState.dnd = prevDnd;
        if (appliedFor !== "") mark("");
        appliedFor = "";
    }

    // connect to a network that has rules -> apply once DHCP has settled; leave -> undo quiet mode.
    // Reacts to the name and to the connected state: after a wake the new name often shows up while iwd is still connecting.
    // the laptop slept since the rule ran (a 5 s tick that came late): the portal sign-in has likely expired
    property bool slept: false
    property real tick: Date.now()
    Timer { interval: 5000; running: true; repeat: true; onTriggered: { if (Date.now() - root.tick > 60000) { root.slept = true; wakeCheck.restart(); } root.tick = Date.now(); } }
    // the link often comes back before the 5 s Wi-Fi poll notices it dropped: look once things have settled
    Timer { id: wakeCheck; interval: 8000; onTriggered: root.changed() }
    // offline for a while (awake): undo quiet mode and forget the network, so joining it again runs the rule
    Timer { id: leaveLater; interval: 120000; onTriggered: if (!Wifi.connected) root.leave() }
    function changed() {
        settle.stop();
        if (Wifi.connected && Wifi.ssid !== "") {
            // first network seen after a shell restart, and its rule already ran: adopt it instead of re-running
            if (startupApplied !== "") {
                const same = Wifi.ssid === startupApplied;
                startupApplied = "";
                if (same) { appliedFor = Wifi.ssid; slept = false; return; }
            }
            leaveLater.stop();
            // back on the same network after a short drop: keep it; after a sleep run a sign-in rule again (the portal has likely forgotten us)
            if (Wifi.ssid === appliedFor && !(slept && rule(appliedFor).login)) return;
            leave(); busyWaits = 0; settle.restart();
        } else if (!Wifi.connected && appliedFor !== "") {
            leaveLater.restart();
        }
    }
    Connections {
        target: Wifi
        function onSsidChanged() { root.changed(); }
        function onConnectedChanged() { root.changed(); }
    }
    Timer { id: settle; interval: 3500; onTriggered: if (Wifi.connected && Wifi.ssid !== "") root.apply(Wifi.ssid) }
}
