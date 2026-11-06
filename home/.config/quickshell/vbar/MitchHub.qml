pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// GitHub status for github.com/mitch-pro/mitch.pro: open PRs and deployments waiting on your approval
// (via ~/.local/bin/mitch-gh). Read-only polling; the one write is approving a deploy.
Singleton {
    id: root
    property bool loaded: false
    property string error: ""
    property string repo: "mitch-pro/mitch.pro"
    property var prs: []
    property var deploys: []
    property var runs: []            // recent workflow runs of every kind, newest first
    readonly property string repoUrl: "https://github.com/" + repo

    readonly property int prCount: prs.length
    readonly property int deployCount: deploys.length
    // a dot on the glyph when something wants you: a deploy you can approve
    readonly property bool needsYou: deploys.some(d => d.canApprove)
    function isBad(c) { return ["failure", "cancelled", "timed_out", "startup_failure", "action_required"].indexOf(c) >= 0; }
    property var dismissed: ({})     // run id -> true: failures the user cleared from the card
    readonly property var failedRuns: runs.filter(r => r.status === "completed" && isBad(r.conclusion) && !dismissed[r.id])
    function dismiss(id) {
        const m = Object.assign({}, dismissed); m[id] = true; dismissed = m;
        dfile.setText(JSON.stringify(Object.keys(m).map(Number)));
    }
    FileView {
        id: dfile
        path: Quickshell.env("HOME") + "/.local/share/rice/mitch-dismissed.json"
        onLoaded: { try { const a = JSON.parse(text()); const m = {}; for (const id of a) m[id] = true; root.dismissed = m; } catch (e) {} }
    }

    // notify only on genuinely new items after the first successful load
    property var seenPr: ({})
    property var seenDeploy: ({})
    property var seenRun: ({})       // run id -> last conclusion we saw, so a run flips to failed only once
    property bool primed: false

    function refresh() { if (!proc.running) proc.running = true; }
    function approve(runId, envId) {
        appr.command = [Quickshell.env("HOME") + "/.local/bin/mitch-gh", "approve", String(runId), String(envId)];
        appr.running = true;
    }
    function open(url) { if (url) Quickshell.execDetached(["librewolf", url]); }

    function ago(iso) {
        if (!iso) return "";
        const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d > 0 ? d + "d ago" : h > 0 ? h + "h ago" : m > 0 ? m + "m ago" : "just now";
    }

    Process {
        id: appr
        stderr: StdioCollector { id: apprErr }
        onExited: code => {
            if (code === 0) UiState.pulse("mitch", "", "Deploy approved", -1, Theme.green, 4000);
            else UiState.pulse("mitch", "", "Approve failed: " + (apprErr.text.trim() || ("exit " + code)), -1, Theme.error, 6000);
            root.refresh();
        }
    }

    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/.local/bin/mitch-gh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.repo = d.repo || root.repo;
                    root.error = d.error || "";
                    root.prs = d.prs || [];
                    root.deploys = d.deploys || [];
                    root.runs = d.runs || [];

                    if (root.primed && root.error === "") {
                        for (const p of root.prs)
                            if (!root.seenPr[p.number])
                                UiState.pulse("mitch:pr" + p.number, "", "New PR #" + p.number + " · " + p.title, -1, Theme.primary, 7000);
                        for (const dp of root.deploys)
                            if (dp.canApprove && !root.seenDeploy[dp.run_id + ":" + dp.env_id])
                                UiState.pulse("mitch:dep" + dp.run_id, "", "Deploy needs approval · " + dp.env + " (" + (dp.title || dp.name) + ")", -1, Theme.yellow, 9000);
                        // any workflow run that just finished badly (CI, deploy, notify, ...)
                        for (const r of root.runs)
                            if (r.status === "completed" && root.isBad(r.conclusion) && root.seenRun[r.id] !== r.conclusion)
                                UiState.pulse("mitch:run" + r.id, "",
                                    r.name + " " + r.conclusion + " · " + r.branch + (r.title ? " · " + r.title : ""),
                                    -1, Theme.error, 9000);
                    }
                    const sp = {}; for (const p of root.prs) sp[p.number] = true; root.seenPr = sp;
                    const sd = {}; for (const dp of root.deploys) sd[dp.run_id + ":" + dp.env_id] = true; root.seenDeploy = sd;
                    const sr = {}; for (const r of root.runs) sr[r.id] = r.status === "completed" ? r.conclusion : r.status; root.seenRun = sr;
                    // forget dismissals for runs that have scrolled out of the recent list, so the file stays small
                    if (root.runs.length > 0) {
                        const present = {}; for (const r of root.runs) present[r.id] = true;
                        const keep = {}; let shrank = false;
                        for (const id in root.dismissed) { if (present[id]) keep[id] = true; else shrank = true; }
                        if (shrank) { root.dismissed = keep; dfile.setText(JSON.stringify(Object.keys(keep).map(Number))); }
                    }
                    if (root.error === "") root.primed = true;
                    root.loaded = true;
                } catch (e) { root.error = "bad reply"; }
            }
        }
    }
    // livelier while the card is open; a background heartbeat otherwise
    Timer { interval: UiState.mitch ? 60000 : 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
