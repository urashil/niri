pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Claude plan usage: 5 hour and weekly limits (via ~/.local/bin/claude-usage) and all-time token totals from local transcripts.
Singleton {
    id: root
    property bool loaded: false
    property string error: ""
    property real session: 0            // percent used
    property string sessionReset: ""
    property real weekly: 0
    property string weeklyReset: ""
    property string plan: ""
    property var all: ({ in: 0, out: 0, cr: 0, cc: 0, msgs: 0, sessions: 0 })
    readonly property real hot: Math.max(session, weekly)

    function refresh() { if (!proc.running) proc.running = true; }

    // ---- Claude Code sessions (from the hooks, ~/.local/bin/claude-island) ----
    property var sessions: []
    readonly property int waiting: sessions.filter(s => s.state === "waiting").length
    function listSessions() { if (!lister.running) lister.running = true; }
    function event(state, win, project, msg, ping) {
        listSessions();
        if (!ping) return;
        const wait = state === "waiting";
        UiState.pulse(win > 0 ? "claude:" + win : "claude", "\uf069", project + (wait ? " · " + (msg || "needs you") : " · done"), -1, wait ? Theme.yellow : Theme.primary, wait ? 8000 : 5000);
    }
    Process {
        id: lister
        command: [Quickshell.env("HOME") + "/.local/bin/claude-island", "list"]
        stdout: StdioCollector { onStreamFinished: { try { root.sessions = JSON.parse(text); } catch (e) {} } }
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.listSessions() }
    function until(iso) {
        const s = Math.max(0, Math.round((new Date(iso).getTime() - Date.now()) / 1000));
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m";
    }
    function tokens(n) { return n >= 1e9 ? (n / 1e9).toFixed(2) + "B" : n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? (n / 1e3).toFixed(1) + "k" : String(n); }

    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/.local/bin/claude-usage"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.all = d.all;
                    root.plan = d.plan || "";
                    root.error = d.error || "";
                    if (d.limits) {
                        root.session = d.limits.five_hour ? d.limits.five_hour.utilization : 0;
                        root.sessionReset = d.limits.five_hour ? d.limits.five_hour.resets_at : "";
                        root.weekly = d.limits.seven_day ? d.limits.seven_day.utilization : 0;
                        root.weeklyReset = d.limits.seven_day ? d.limits.seven_day.resets_at : "";
                    }
                    root.loaded = true;
                } catch (e) { root.error = "bad reply"; }
            }
        }
    }
    Timer { interval: UiState.claude ? 60000 : 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
