pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The phone page (~/.local/bin/rice-remote): its two user services, passkeys, and what happened on it.
// Failed sign-ins and actions from the phone also show in the island.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    property bool server: false          // rice-remote.service active
    property bool tunnel: false          // rice-remote-tunnel.service active
    property bool serverFailed: false
    property bool tunnelFailed: false
    property bool configured: false      // a password is set
    property string origin: ""
    property int passkeys: 0
    property var events: []              // recent log lines, newest first
    property bool watching: false        // the page is open: poll faster
    readonly property bool on: server && tunnel

    function refresh() { if (!stat.running) stat.running = true; }
    function setServer(v) { ctl(["systemctl", "--user", v ? "enable" : "disable", "--now", "rice-remote.service"]); }
    function setTunnel(v) { ctl(["systemctl", "--user", v ? "enable" : "disable", "--now", "rice-remote-tunnel.service"]); }
    function setAll(v) { ctl(["systemctl", "--user", v ? "enable" : "disable", "--now", "rice-remote.service", "rice-remote-tunnel.service"]); }
    // sessions live in the server's memory: a restart signs every device out
    function signOutAll() { ctl(["systemctl", "--user", "restart", "rice-remote.service"]); UiState.pulse("toggle", "\uf3cd", "Phone page: every device signed out", -1, Theme.yellow, 2500); }
    function ctl(cmd) { runner.command = cmd; runner.running = true; }
    Process { id: runner; onExited: root.refresh() }

    Process {
        id: stat
        command: ["sh", "-c", "for u in rice-remote rice-remote-tunnel; do systemctl --user is-active $u.service; done; "
            + "test -f \"$HOME/.config/rice/remote.json\" && cat \"$HOME/.config/rice/remote.json\" | tr -d '\\n'; echo; "
            + "cat \"$HOME/.local/state/rice-remote/passkeys.json\" 2>/dev/null | tr -d '\\n'; echo; "
            + "journalctl --user -u rice-remote.service -n 40 -o short-iso --no-pager 2>/dev/null | grep -E 'rice-remote: (failed|action|passkey)' | tail -n 8"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                root.server = l[0] === "active"; root.serverFailed = l[0] === "failed" || l[0] === "activating";
                root.tunnel = l[1] === "active"; root.tunnelFailed = l[1] === "failed" || l[1] === "activating";
                try { const c = JSON.parse(l[2]); root.configured = !!c.hash; root.origin = c.origin || ""; } catch (e) { root.configured = false; }
                try { root.passkeys = JSON.parse(l[3]).length; } catch (e) { root.passkeys = 0; }
                root.events = l.slice(4).filter(x => x.trim()).map(x => {
                    const m = x.match(/^(\S+)T(\d\d:\d\d)\S*\s+\S+\s+\S+:\s+rice-remote:\s+(.*)$/);
                    return m ? m[2] + "  " + m[3] : x;
                }).reverse();
            }
        }
    }
    Timer { interval: root.watching ? 4000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    // live: tell me when someone fails to sign in or does something from the phone
    Process {
        running: true
        command: ["journalctl", "--user", "-u", "rice-remote.service", "-f", "-n", "0", "-o", "cat"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("failed") >= 0) UiState.pulse("toggle", "\uf071", "Phone page: " + line.replace(/^rice-remote:\s*/, ""), -1, Theme.error, 6000);
                else if (line.indexOf("action") >= 0) UiState.pulse("toggle", "\uf3cd", "Phone: " + line.replace(/^rice-remote:\s*action \/api\/action\//, "").replace(/ from .*/, ""), -1, Theme.primary, 4000);
                else if (line.indexOf("passkey added") >= 0) UiState.pulse("toggle", "\uf084", "Phone page: a passkey was added", -1, Theme.yellow, 5000);
                root.refresh();
            }
        }
    }
}
