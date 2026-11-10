pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// GitHub status for github.com/mitch-pro/mitch.pro: open PRs + deployments waiting on your
// approval + running and recently failed workflow runs (via ~/.local/bin/mitch-gh).
// Polls every 10 s while the popout is open or something is in flight, every 60 s otherwise; opening the popout
// refreshes at once. Writes: approve a deploy, re-run failed jobs, cancel a run.
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

    readonly property var activeRuns: runs.filter(r => r.status !== "completed" && r.status !== "waiting")
    readonly property bool inFlight: activeRuns.length > 0 || deployCount > 0 || prs.some(p => p.checks === "pending")
    readonly property bool fetching: proc.running
    property real lastUpdate: 0
    property int reviewPr: 0            // PR number shown in the review window (modules/prreview), 0 = closed
    function review(n) { reviewPr = n; }
    property int watchers: 0            // open popouts; Mitch.qml bumps this while it is shown
    onWatchersChanged: if (watchers > 0) { now = Date.now(); refresh(); }
    property real now: Date.now()       // ticks so "Ns ago" / elapsed times stay live
    Timer { interval: 1000; running: root.watchers > 0; repeat: true; onTriggered: root.now = Date.now() }
    property var busyIds: ({})          // run ids with an action in flight (approve / rerun / cancel)

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

    property bool again: false
    function refresh() { if (proc.running) again = true; else proc.running = true; }
    function act(args, id) {
        const b = Object.assign({}, busyIds);
        b[id] = true;
        busyIds = b;
        const p = actComp.createObject(root, { command: [root.home + "/.local/bin/mitch-gh"].concat(args.map(String)), rid: id });
        p.running = true;
    }
    function approve(runId, envId) { act(["approve", runId, envId], runId); }
    function rerun(runId) { act(["rerun", runId], runId); }
    function cancel(runId) { act(["cancel", runId], runId); }
    function open(url) { if (url) Quickshell.execDetached(["librewolf", url]); }

    function dur(iso) {
        if (!iso)
            return "";
        const s = Math.max(0, Math.round((root.now - new Date(iso).getTime()) / 1000));
        return s >= 3600 ? Math.floor(s / 3600) + "h " + Math.floor(s % 3600 / 60) + "m" : s >= 60 ? Math.floor(s / 60) + "m " + (s % 60) + "s" : s + "s";
    }
    function ago(iso) {
        if (!iso)
            return "";
        const s = Math.max(0, Math.round((root.now - new Date(iso).getTime()) / 1000));
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d > 0 ? d + "d ago" : h > 0 ? h + "h ago" : m > 0 ? m + "m ago" : "just now";
    }

    Component {
        id: actComp
        Process {
            id: ap
            property var rid
            stderr: StdioCollector { id: apErr }
            onExited: code => {
                if (code !== 0)
                {
                    root.actionError = apErr.text.trim().split("\n").pop() || "action failed";
                    clearActErr.restart();
                }
                const b = Object.assign({}, root.busyIds);
                delete b[ap.rid];
                root.busyIds = b;
                root.refresh();
                // GitHub takes a moment to reflect re-runs / cancels: look again shortly
                settle.restart();
                ap.destroy();
            }
        }
    }
    property string actionError: ""
    Timer { id: clearActErr; interval: 10000; onTriggered: root.actionError = "" }
    Timer { id: settle; interval: 3000; onTriggered: root.refresh() }

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
                    root.lastUpdate = Date.now();
                } catch (e) {
                    root.error = "bad reply";
                }
            }
        }
    }
    Connections {
        target: proc
        function onRunningChanged() {
            if (!proc.running && root.again) {
                root.again = false;
                proc.running = true;
            }
        }
    }
    Timer {
        interval: root.watchers > 0 || root.inFlight ? 10000 : 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    IpcHandler {
        function refresh(): void { root.refresh(); }
        function review(n: int): void { root.reviewPr = n; }
        function closeReview(): void { root.reviewPr = 0; }
        target: "mitch"
    }
}
