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
        if (r.login) UiState.pulse("auto", "", ssid + " · signing in…", -1, Theme.primary, 3500);
    }
    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.rules = JSON.parse(text()); } catch (e) {} }
    }

    function apply(ssid) {
        const r = rule(ssid);
        // a flapping link must not re-run the rule over and over (each run talks to the PIA daemon): once a minute per network at most,
        // and never while the previous run, or a VPN connect, is still going
        if (Date.now() - (lastApplied[ssid] || 0) < 60000 || signin.running || Vpn.busy) return;
        lastApplied[ssid] = Date.now();
        let did = [];
        if (r.dnd) { if (appliedFor === "") prevDnd = UiState.dnd; UiState.dnd = true; did.push("quiet"); }
        if (r.login || r.ks) startSignin(ssid, r);
        else if (r.vpn === "wg") { if (!(Vpn.connected && Vpn.choice === "wireguard")) Vpn.useWireguard(); did.push("WireGuard"); }
        else if (r.vpn === "443") { if (!(Vpn.connected && Vpn.choice === "school")) Vpn.useSchool(); did.push("OpenVPN 443"); }
        else if (r.vpn === "off") { Vpn.disconnect(); did.push("VPN off"); }
        appliedFor = ssid;
        if (did.length) UiState.pulse("auto", "", ssid + " · " + did.join(" · "), -1, Theme.primary, 3500);
    }
    function leave() {
        if (appliedFor !== "" && rule(appliedFor).dnd) UiState.dnd = prevDnd;
        appliedFor = "";
    }

    // connect to a network that has rules -> apply once DHCP has settled; leave -> undo quiet mode
    Connections {
        target: Wifi
        function onSsidChanged() {
            settle.stop();
            if (Wifi.connected && Wifi.ssid !== "") {
                if (Wifi.ssid !== root.appliedFor) { root.leave(); settle.restart(); }
            } else if (!Wifi.connected) {
                root.leave();
            }
        }
    }
    Timer { id: settle; interval: 3500; onTriggered: if (Wifi.connected && Wifi.ssid !== "") root.apply(Wifi.ssid) }
}
