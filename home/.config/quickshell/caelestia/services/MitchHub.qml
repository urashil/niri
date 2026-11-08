pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// GitHub status for github.com/mitch-pro/mitch.pro: open PRs + deployments waiting on your
// approval + recent failed runs (via ~/.local/bin/mitch-gh). Read-only; the one write is approve.
Singleton {
    id: root

    property bool loaded: false
    property string error: ""
    property string repo: "mitch-pro/mitch.pro"
    property var prs: []
    property var deploys: []
    property var runs: []
    readonly property string repoUrl: "https://github.com/" + repo
    readonly property string home: Quickshell.env("HOME")

    readonly property int prCount: prs.length
    readonly property int deployCount: deploys.length
    readonly property bool needsYou: deploys.some(d => d.canApprove)

    function isBad(c) { return ["failure", "cancelled", "timed_out", "startup_failure", "action_required"].indexOf(c) >= 0; }
    property var dismissed: ({})
    readonly property var failedRuns: runs.filter(r => r.status === "completed" && isBad(r.conclusion) && !dismissed[r.id])
    function dismiss(id) {
        const m = Object.assign({}, dismissed);
        m[id] = true;
        dismissed = m;
        dfile.setText(JSON.stringify(Object.keys(m).map(Number)));
    }
    FileView {
        id: dfile
        path: root.home + "/.local/share/rice/mitch-dismissed.json"
        printErrors: false
        onLoaded: {
            try {
                const a = JSON.parse(text());
                const m = {};
                for (const id of a)
                    m[id] = true;
                root.dismissed = m;
            } catch (e) {}
        }
    }

    function refresh() { if (!proc.running) proc.running = true; }
    function approve(runId, envId) {
        appr.command = [root.home + "/.local/bin/mitch-gh", "approve", String(runId), String(envId)];
        appr.running = true;
    }
    function open(url) { if (url) Quickshell.execDetached(["librewolf", url]); }

    function ago(iso) {
        if (!iso)
            return "";
        const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d > 0 ? d + "d ago" : h > 0 ? h + "h ago" : m > 0 ? m + "m ago" : "just now";
    }

    Process { id: appr; onExited: root.refresh() }

    Process {
        id: proc
        command: [root.home + "/.local/bin/mitch-gh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.repo = d.repo || root.repo;
                    root.error = d.error || "";
                    root.prs = d.prs || [];
                    root.deploys = d.deploys || [];
                    root.runs = d.runs || [];
                    // keep the dismissed set small: forget ids no longer in the recent list
                    if (root.runs.length > 0) {
                        const present = {};
                        for (const r of root.runs)
                            present[r.id] = true;
                        const keep = {};
                        let shrank = false;
                        for (const id in root.dismissed) {
                            if (present[id])
                                keep[id] = true;
                            else
                                shrank = true;
                        }
                        if (shrank) {
                            root.dismissed = keep;
                            dfile.setText(JSON.stringify(Object.keys(keep).map(Number)));
                        }
                    }
                    root.loaded = true;
                } catch (e) {
                    root.error = "bad reply";
                }
            }
        }
    }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    IpcHandler {
        function refresh(): void { root.refresh(); }
        target: "mitch"
    }
}
