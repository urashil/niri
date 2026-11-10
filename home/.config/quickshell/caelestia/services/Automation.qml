pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Per-Wi-Fi-network rules, applied when you connect: VPN (WireGuard / OpenVPN TCP 443 / off), kill switch,
// quiet mode, and captive-portal sign-in. Stored in ~/.config/rice/networks.json:
//   { "<ssid>": { "vpn": "wg"|"443"|"off"|"", "dnd": bool, "login": bool, "ks": "on"|"auto"|"off"|"" } }
// "login": drops VPN + kill switch, runs ~/.config/rice/network-login.sh (captive portal), then restores
// the kill switch ("ks") and the VPN setting ("" = whatever was on before). The network-login helper does
// the heavy lifting and switches the VPN method via `qs -c caelestia ipc call vpn <wg|school|auto>`.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/rice/networks.json"
    property var rules: ({})
    property bool prevDnd: false
    property string appliedFor: ""
    property var lastApplied: ({})          // ssid -> ms of the last time its rule ran
    property int busyWaits: 0               // settle retries spent waiting for the VPN to stop being busy

    // live Wi-Fi state (from Nmcli)
    readonly property bool wifiConnected: !!Nmcli.active
    readonly property string wifiSsid: Nmcli.active ? Nmcli.active.ssid : ""

    function rule(ssid) { return rules[ssid] || { vpn: "", dnd: false, login: false, ks: "" }; }
    function set(ssid, key, value) {
        const r = JSON.parse(JSON.stringify(rules));
        r[ssid] = Object.assign({ vpn: "", dnd: false, login: false, ks: "" }, r[ssid] || {});
        r[ssid][key] = value;
        if (!r[ssid].vpn && !r[ssid].dnd && !r[ssid].login && !r[ssid].ks)
            delete r[ssid];
        rules = r;
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", path, JSON.stringify(r)];
        save.running = true;
    }

    function toast(level, msg) {
        Quickshell.execDetached(["caelestia", "shell", "toaster", level, "Wi-Fi", msg, "wifi"]);
    }

    Process { id: save }
    Process {
        id: signin
        property string ssid: ""
        property string lastStep: ""
        stdout: SplitParser { onRead: line => { if (line.trim() !== "") signin.lastStep = line.trim(); } }
        onExited: code => {
            const msg = signin.ssid + (code === 0 ? " · signed in" :
                code === 3 ? " · sign-in failed, VPN left off" :
                code === 4 ? " · " + (signin.lastStep || "something could not be turned back on") :
                code === 2 ? " · sign-in script missing" : " · stopped, protections back on");
            root.toast(code === 0 ? "success" : "warn", msg);
        }
    }
    function startSignin(ssid, r) {
        if (signin.running)
            return;
        // what to restore afterwards: the rule's choice, else whatever was in use before
        const was = (Tunnel.connected || Tunnel.busy) ? (Tunnel.choice === "wireguard" ? "wg" : Tunnel.choice === "school" ? "443" : "auto") : "off";
        const vpn = r.vpn || was;
        signin.ssid = ssid;
        signin.lastStep = "";
        signin.command = ["network-login", vpn, r.ks || Tunnel.killswitch, Nmcli.wifiDev, r.login ? "1" : "0"];
        signin.running = true;
    }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.rules = JSON.parse(text()); } catch (e) {} }
    }
    // the network whose rule already ran this login: a restarted shell must not run it again
    // (a sign-in rule would drop the VPN)
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
        // a flapping link must not re-run the rule over and over (each run talks to the VPN daemon):
        // once a minute per network at most, and never while the previous run is still going
        if (Date.now() - (lastApplied[ssid] || 0) < 60000 || signin.running)
            return;
        // the VPN still busy with the last network (e.g. "Reconnecting" after waking somewhere new, which
        // behind a portal never ends): a sign-in rule disconnects it anyway; a plain VPN rule waits a little
        if (Tunnel.busy && !r.login && !r.ks && busyWaits < 6) {
            busyWaits++;
            settle.restart();
            return;
        }
        busyWaits = 0;
        lastApplied[ssid] = Date.now();
        let did = [];
        if (r.dnd) {
            if (appliedFor === "")
                prevDnd = Notifs.dnd;
            Notifs.dnd = true;
            did.push("quiet");
        }
        if (r.login || r.ks) {
            startSignin(ssid, r);
        } else if (r.vpn === "wg") {
            if (!(Tunnel.connected && Tunnel.choice === "wireguard"))
                Tunnel.useWireguard();
            did.push(Tunnel.methodLabel("wireguard"));
        } else if (r.vpn === "443") {
            if (!(Tunnel.connected && Tunnel.choice === "school"))
                Tunnel.useSchool();
            did.push(Tunnel.methodLabel("school"));
        } else if (r.vpn === "off") {
            Tunnel.disconnect();
            did.push("VPN off");
        }
        appliedFor = ssid;
        slept = false;
        mark(ssid);
        if (did.length)
            toast("info", ssid + " · " + did.join(" · "));
    }
    function leave() {
        if (appliedFor !== "" && rule(appliedFor).dnd)
            Notifs.dnd = prevDnd;
        if (appliedFor !== "")
            mark("");
        appliedFor = "";
    }

    // connect to a network that has rules -> apply once DHCP has settled; leave -> undo quiet mode.
    property bool slept: false
    property real tick: Date.now()
    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: { if (Date.now() - root.tick > 60000) { root.slept = true; wakeCheck.restart(); } root.tick = Date.now(); }
    }
    // the link often comes back before the poll notices it dropped: look once things have settled
    Timer { id: wakeCheck; interval: 8000; onTriggered: root.changed() }
    // offline for a while (awake): undo quiet mode and forget the network, so rejoining runs the rule
    Timer { id: leaveLater; interval: 120000; onTriggered: if (!root.wifiConnected) root.leave() }
    function changed() {
        settle.stop();
        if (wifiConnected && wifiSsid !== "") {
            // first network seen after a shell restart, and its rule already ran: adopt it instead of re-running
            if (startupApplied !== "") {
                const same = wifiSsid === startupApplied;
                startupApplied = "";
                if (same) { appliedFor = wifiSsid; slept = false; return; }
            }
            leaveLater.stop();
            // back on the same network after a short drop: keep it; after a sleep run a sign-in rule again
            if (wifiSsid === appliedFor && !(slept && rule(appliedFor).login))
                return;
            leave();
            busyWaits = 0;
            settle.restart();
        } else if (!wifiConnected && appliedFor !== "") {
            leaveLater.restart();
        }
    }
    Connections {
        target: Nmcli
        function onActiveChanged() { root.changed(); }
    }
    Timer { id: settle; interval: 3500; onTriggered: if (root.wifiConnected && root.wifiSsid !== "") root.apply(root.wifiSsid) }
}
