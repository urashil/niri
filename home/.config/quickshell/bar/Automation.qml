pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Per-Wi-Fi-network rules, applied when you connect: VPN (WireGuard / OpenVPN TCP 443 / off) and quiet mode.
// Stored in ~/.config/rice/networks.json: { "<ssid>": { "vpn": "wg"|"443"|"off"|"", "dnd": true|false } }
Singleton {
    id: root
    readonly property string path: Quickshell.env("HOME") + "/.config/rice/networks.json"
    property var rules: ({})
    property bool prevDnd: false
    property string appliedFor: ""

    function rule(ssid) { return rules[ssid] || { vpn: "", dnd: false }; }
    function set(ssid, key, value) {
        const r = JSON.parse(JSON.stringify(rules));
        r[ssid] = Object.assign({ vpn: "", dnd: false }, r[ssid] || {});
        r[ssid][key] = value;
        if (!r[ssid].vpn && !r[ssid].dnd) delete r[ssid];
        rules = r;
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", path, JSON.stringify(r)];
        save.running = true;
    }

    Process { id: save }
    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.rules = JSON.parse(text()); } catch (e) {} }
    }

    function apply(ssid) {
        const r = rule(ssid);
        let did = [];
        if (r.dnd) { if (appliedFor === "") prevDnd = UiState.dnd; UiState.dnd = true; did.push("quiet"); }
        if (r.vpn === "wg") { Vpn.useWireguard(); did.push("WireGuard"); }
        else if (r.vpn === "443") { Vpn.useSchool(); did.push("OpenVPN 443"); }
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
