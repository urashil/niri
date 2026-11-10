pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// PR review window for mitch.pro, opened from the GitHub card (click a PR) or `caelestia shell mitch review <n>`.
// Conversation (description, commits, comments, reviews), the diff (with line comments inline), CI checks with the
// failing log, and the actions: comment, approve, request changes, merge, close / reopen, ready for review.
// Everything goes through ~/.local/bin/mitch-gh; it refreshes every 10 s while open.
PanelWindow {
    id: win

    readonly property int num: MitchHub.reviewPr
    readonly property bool shown: num > 0
    readonly property string gh: Quickshell.env("HOME") + "/.local/bin/mitch-gh"

    property var pr: null
    property string loadError: ""
    property string diffText: ""
    property var diffLines: []
    property var diffFiles: []
    property var collapsed: ({})
    property string headOid: ""
    property int tab: 0
    property string busy: ""        // action label while one runs
    property string note: ""
    property bool noteErr: false
    property string confirm: ""     // "merge" | "close": second click confirms
    property string mergeHow: "squash"
    property bool deleteBranch: true
    property var logs: ({})         // run id -> log text ("" while loading)
    property string openLog: ""
    property var drafts: ({})       // PR number -> unsent message

    visible: shown
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.45)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "caelestia-prreview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() {
        saveDraft();
        MitchHub.reviewPr = 0;
    }
    function saveDraft() {
        if (pr) {
            const d = Object.assign({}, drafts);
            d[pr.number] = msg.text;
            drafts = d;
        }
    }

    onNumChanged: {
        saveDraft();
        pr = null;
        loadError = "";
        diffText = "";
        diffLines = [];
        diffFiles = [];
        collapsed = ({});
        headOid = "";
        confirm = "";
        openLog = "";
        note = "";
        msg.text = drafts[num] || "";
        if (num > 0) {
            tab = 0;
            load();
            loadDiff();
            card.forceActiveFocus();
        }
    }

    function load() { if (num > 0 && !prProc.running) { prProc.command = [gh, "pr", String(num)]; prProc.running = true; } }
    function loadDiff() { if (num > 0) { diffProc.running = false; diffProc.command = [gh, "diff", String(num)]; diffProc.running = true; } }

    function act(label, args, body) {
        if (busy !== "")
            return;
        busy = label;
        note = "";
        actProc.body = body || "";
        actProc.label = label;
        actProc.command = [gh].concat(args.map(String));
        actProc.running = true;
    }

    function showLog(run) {
        if (!run)
            return;
        openLog = openLog === run ? "" : run;
        if (openLog !== "" && logs[run] === undefined) {
            const l = Object.assign({}, logs);
            l[run] = "";
            logs = l;
            const p = logComp.createObject(win, { run: run, command: [gh, "log", run] });
            p.running = true;
        }
    }

    // ---------- diff ----------
    function parseDiff(text) {
        const out = [], files = [];
        const lc = {};
        for (const c of (pr && pr.lineComments) || []) {
            const k = c.path + ":" + c.line + ":" + (c.side === "LEFT" ? "L" : "R");
            (lc[k] = lc[k] || []).push(c);
        }
        let o = 0, n = 0, fi = -1, header = false;
        const pushComments = (path, line, side) => {
            for (const c of lc[path + ":" + line + ":" + side] || [])
                out.push({ k: "comment", t: c.body, a: c.author, f: fi });
        };
        for (const line of text.split("\n")) {
            if (line.startsWith("diff --git ")) {
                const m = line.match(/ b\/(.*)$/);
                const path = m ? m[1] : line.slice(11);
                fi = files.length;
                files.push({ path: path, add: 0, del: 0, status: "", at: out.length });
                out.push({ k: "file", t: path, f: fi });
                header = true;
                continue;
            }
            if (fi < 0)
                continue;
            const f = files[fi];
            if (header) {
                if (line.startsWith("new file"))
                    f.status = "added";
                else if (line.startsWith("deleted file"))
                    f.status = "deleted";
                else if (line.startsWith("rename from"))
                    f.status = "renamed";
                else if (line.startsWith("Binary files"))
                    out.push({ k: "meta", t: "binary file", f: fi });
                if (!line.startsWith("@@"))
                    continue;
            }
            if (line.startsWith("@@")) {
                header = false;
                const m = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/);
                if (m) {
                    o = +m[1];
                    n = +m[2];
                }
                out.push({ k: "hunk", t: m ? m[3].trim() : line, f: fi });
                continue;
            }
            const c = line.charAt(0);
            if (c === "+") {
                out.push({ k: "add", t: line.slice(1), n: n, f: fi });
                f.add++;
                pushComments(f.path, n, "R");
                n++;
            } else if (c === "-") {
                out.push({ k: "del", t: line.slice(1), o: o, f: fi });
                f.del++;
                pushComments(f.path, o, "L");
                o++;
            } else if (c === " ") {
                out.push({ k: "ctx", t: line.slice(1), o: o, n: n, f: fi });
                pushComments(f.path, n, "R");
                o++;
                n++;
            } else if (c === "\\") {
                out.push({ k: "meta", t: line.slice(2), f: fi });
            }
        }
        // lockfiles and generated stuff start folded
        const fold = {};
        for (let i = 0; i < files.length; i++)
            if (/(\.lock|-lock\.json|-lock\.yaml|\.min\.(js|css)|\.snap)$/.test(files[i].path) || files[i].add + files[i].del > 1500)
                fold[i] = true;
        collapsed = fold;
        diffFiles = files;
        diffLines = out;
    }
    readonly property var visibleLines: {
        const c = collapsed;
        return diffLines.filter(l => l.k === "file" || !c[l.f]);
    }
    function jumpTo(fi) {
        const i = visibleLines.findIndex(l => l.k === "file" && l.f === fi);
        if (i >= 0)
            diffView.positionViewAtIndex(i, ListView.Beginning);
    }
    function toggleFile(fi) {
        const c = Object.assign({}, collapsed);
        if (c[fi])
            delete c[fi];
        else
            c[fi] = true;
        collapsed = c;
    }

    // ---------- helpers ----------
    function checkState(c) {
        if (c.status !== "COMPLETED")
            return "pending";
        return ["SUCCESS", "NEUTRAL", "SKIPPED"].indexOf(c.conclusion) >= 0 ? "ok" : "fail";
    }
    readonly property var checks: pr ? pr.checks || [] : []
    readonly property int failing: checks.filter(c => checkState(c) === "fail").length
    readonly property int pending: checks.filter(c => checkState(c) === "pending").length
    function stateColour(s) {
        return s === "fail" ? Colours.palette.m3error : s === "pending" ? Colours.palette.m3tertiary : Colours.palette.m3success;
    }
    function dur(a, b) {
        if (!a)
            return "";
        const s = Math.max(0, Math.round(((b ? new Date(b).getTime() : MitchHub.now) - new Date(a).getTime()) / 1000));
        return s >= 60 ? Math.floor(s / 60) + "m " + (s % 60) + "s" : s + "s";
    }
    readonly property var timeline: {
        if (!pr)
            return [];
        const t = [];
        for (const c of pr.comments || [])
            t.push({ kind: "comment", who: c.author ? c.author.login : "?", at: c.createdAt, body: c.body, state: "" });
        for (const r of pr.reviews || [])
            t.push({ kind: "review", who: r.author ? r.author.login : "?", at: r.submittedAt, body: r.body, state: r.state });
        for (const c of pr.lineComments || [])
            if (!c.reply_to)
                t.push({ kind: "line", who: c.author, at: c.at, body: c.body, state: "", where: c.path + ":" + c.line });
        return t.sort((a, b) => new Date(a.at) - new Date(b.at));
    }

    Process {
        id: prProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                try {
                    const d = JSON.parse(text);
                    if (d.number !== win.num)
                        return;
                    const oid = d.commits && d.commits.length ? d.commits[d.commits.length - 1].oid : "";
                    const first = win.pr === null;
                    win.pr = d;
                    win.loadError = "";
                    // the diff came first: lay it out again with the line comments in
                    if (first && win.diffText !== "" && (d.lineComments || []).length > 0)
                        win.parseDiff(win.diffText);
                    if (!first && oid !== win.headOid)
                        win.loadDiff();
                    win.headOid = oid;
                } catch (e) {
                    win.loadError = "bad reply";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) win.loadError = text.trim().split("\n").pop()
        }
    }
    Process {
        id: diffProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.diffText = text;
                win.parseDiff(text);
            }
        }
    }
    Timer {
        interval: 10000
        running: win.shown
        repeat: true
        onTriggered: win.load()
    }
    // keeps MitchHub polling fast and its clock ticking while the window is open
    onShownChanged: shown ? MitchHub.watchers++ : MitchHub.watchers--

    Process {
        id: actProc
        property string body
        property string label
        stdinEnabled: true
        onStarted: {
            write(body);
            stdinEnabled = false;
        }
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            stdinEnabled = true;
            win.busy = "";
            win.confirm = "";
            if (code === 0) {
                win.noteErr = false;
                win.note = label + ": done";
                if (["Comment", "Approve", "Request changes"].indexOf(label) >= 0) {
                    msg.text = "";
                    const d = Object.assign({}, win.drafts);
                    delete d[win.num];
                    win.drafts = d;
                }
                if (label === "Merge" || label === "Close")
                    MitchHub.refresh();
            } else {
                win.noteErr = true;
                win.note = actErr.text.trim().split("\n").pop() || (label + " failed");
            }
            win.load();
            settle.restart();
        }
    }
    Timer { id: settle; interval: 3000; onTriggered: { win.load(); MitchHub.refresh(); } }

    Component {
        id: logComp
        Process {
            id: lp
            property string run
            stdout: StdioCollector {
                onStreamFinished: {
                    const l = Object.assign({}, win.logs);
                    l[lp.run] = text.trim() || "(no failed-job log — the run may still be going)";
                    win.logs = l;
                    lp.destroy();
                }
            }
        }
    }

    // click outside the card closes
    MouseArea {
        anchors.fill: parent
        onClicked: win.close()
    }

    StyledRect {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1500)
        height: parent.height - 80
        radius: Tokens.rounding.large
        color: Colours.palette.m3surface
        focus: true

        Keys.onEscapePressed: win.close()
        Keys.onPressed: event => {
            if (event.modifiers & Qt.AltModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                win.tab = event.key - Qt.Key_1;
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: card.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.large

            // ---------- PR list ----------
            ColumnLayout {
                Layout.preferredWidth: 250
                Layout.maximumWidth: 250
                Layout.fillWidth: false
                Layout.fillHeight: true
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Open PRs")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: MitchHub.prs
                    delegate: StyledRect {
                        id: prItem
                        required property var modelData
                        readonly property bool current: modelData.number === win.num
                        width: ListView.view.width
                        implicitHeight: pcol.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.small
                        color: current ? Colours.palette.m3secondaryContainer : "transparent"

                        StateLayer {
                            radius: Tokens.rounding.small
                            onClicked: MitchHub.reviewPr = prItem.modelData.number
                        }
                        ColumnLayout {
                            id: pcol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.padding.small
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small
                                StyledRect {
                                    visible: prItem.modelData.checks !== ""
                                    implicitWidth: 8
                                    implicitHeight: 8
                                    radius: 4
                                    color: win.stateColour(prItem.modelData.checks)
                                }
                                StyledText {
                                    text: "#" + prItem.modelData.number
                                    color: Colours.palette.m3primary
                                    font: Tokens.font.label.medium
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: prItem.modelData.author ? prItem.modelData.author.login.replace(/^app\//, "") : ""
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: prItem.modelData.title
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font: Tokens.font.body.small
                            }
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Colours.palette.m3outlineVariant
            }

            // ---------- main ----------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.fillHeight: true
                spacing: Tokens.spacing.small

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    StyledText {
                        Layout.fillWidth: true
                        text: win.pr ? "#" + win.pr.number + "  " + win.pr.title : win.loadError ? win.loadError : qsTr("Loading #%1…").arg(win.num)
                        color: win.loadError && !win.pr ? Colours.palette.m3error : Colours.palette.m3onSurface
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }
                    IconButton {
                        icon: "refresh"
                        type: IconButton.Text
                        onClicked: { win.load(); win.loadDiff(); }
                    }
                    IconButton {
                        icon: "open_in_new"
                        type: IconButton.Text
                        onClicked: if (win.pr) MitchHub.open(win.pr.url)
                    }
                    IconButton {
                        icon: "close"
                        type: IconButton.Text
                        onClicked: win.close()
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: win.pr !== null
                    Badge { text: win.pr ? (win.pr.author ? win.pr.author.login : "?") : "" }
                    Badge { text: win.pr ? win.pr.headRefName + " → " + win.pr.baseRefName : ""; mono: true }
                    Badge { text: win.pr ? "+" + win.pr.additions : ""; fg: Colours.palette.m3success }
                    Badge { text: win.pr ? "−" + win.pr.deletions : ""; fg: Colours.palette.m3error }
                    Badge { text: win.pr ? win.pr.changedFiles + " files" : "" }
                    Badge { visible: !!win.pr && win.pr.state !== "OPEN"; text: win.pr ? win.pr.state.toLowerCase() : ""; fg: Colours.palette.m3tertiary }
                    Badge { visible: !!win.pr && win.pr.isDraft; text: qsTr("draft"); fg: Colours.palette.m3tertiary }
                    Badge {
                        visible: !!win.pr && win.pr.reviewDecision !== ""
                        text: win.pr ? win.pr.reviewDecision.toLowerCase().replace(/_/g, " ") : ""
                        fg: win.pr && win.pr.reviewDecision === "APPROVED" ? Colours.palette.m3success : win.pr && win.pr.reviewDecision === "CHANGES_REQUESTED" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    }
                    Badge {
                        visible: !!win.pr && win.pr.state === "OPEN"
                        text: !win.pr ? "" : win.pr.mergeable === "CONFLICTING" ? qsTr("conflicts") : win.pr.mergeStateStatus === "CLEAN" ? qsTr("ready to merge") : win.pr.mergeStateStatus === "BLOCKED" ? qsTr("merge blocked") : win.pr.mergeStateStatus === "BEHIND" ? qsTr("behind base") : win.pr.mergeStateStatus === "UNSTABLE" ? qsTr("checks failing") : qsTr("mergeability: %1").arg(win.pr.mergeStateStatus.toLowerCase())
                        fg: !win.pr ? Colours.palette.m3onSurface : win.pr.mergeable === "CONFLICTING" || win.pr.mergeStateStatus === "BLOCKED" ? Colours.palette.m3error : win.pr.mergeStateStatus === "CLEAN" ? Colours.palette.m3success : Colours.palette.m3onSurfaceVariant
                    }
                    Badge { text: win.pr ? qsTr("updated %1").arg(MitchHub.ago(win.pr.updatedAt)) : ""; fg: Colours.palette.m3outline }
                }

                // tabs
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    Repeater {
                        model: [
                            qsTr("Conversation") + (win.timeline.length ? "  " + win.timeline.length : ""),
                            qsTr("Files") + (win.diffFiles.length ? "  " + win.diffFiles.length : ""),
                            qsTr("Checks") + (win.checks.length ? "  " + (win.failing ? win.failing + " failing" : win.pending ? win.pending + " running" : "all passed") : "")
                        ]
                        delegate: IconTextButton {
                            required property var modelData
                            required property int index
                            isToggle: true
                            checked: win.tab === index
                            text: modelData
                            icon: index === 0 ? "forum" : index === 1 ? "difference" : win.failing ? "error" : win.pending ? "pending" : "check_circle"
                            font: Tokens.font.label.medium
                            onClicked: win.tab = index
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: win.tab

                    // ---------- conversation ----------
                    Flickable {
                        id: convFlick
                        clip: true
                        contentWidth: width
                        contentHeight: conv.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        ColumnLayout {
                            id: conv
                            width: convFlick.width - 12
                            spacing: Tokens.spacing.medium

                            Post {
                                Layout.fillWidth: true
                                who: win.pr && win.pr.author ? win.pr.author.login : ""
                                at: win.pr ? win.pr.createdAt : ""
                                body: win.pr ? (win.pr.body || "_No description._") : ""
                                tag: qsTr("description")
                            }

                            StyledText {
                                visible: !!win.pr && (win.pr.commits || []).length > 0
                                text: qsTr("Commits")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.medium
                            }
                            Repeater {
                                model: win.pr ? win.pr.commits || [] : []
                                delegate: RowLayout {
                                    id: cm
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.medium
                                    StyledText {
                                        text: cm.modelData.oid.slice(0, 7)
                                        font: Tokens.font.mono.small
                                        color: Colours.palette.m3primary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cm.modelData.messageHeadline
                                        elide: Text.ElideRight
                                        font: Tokens.font.body.small
                                    }
                                    StyledText {
                                        text: (cm.modelData.authors && cm.modelData.authors.length ? cm.modelData.authors[0].login || cm.modelData.authors[0].name : "") + "  ·  " + MitchHub.ago(cm.modelData.committedDate)
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.label.small
                                    }
                                }
                            }

                            Repeater {
                                model: win.timeline
                                delegate: Post {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    who: modelData.who
                                    at: modelData.at
                                    body: modelData.body || ""
                                    tag: modelData.kind === "line" ? modelData.where : modelData.state === "APPROVED" ? qsTr("approved") : modelData.state === "CHANGES_REQUESTED" ? qsTr("requested changes") : modelData.state === "DISMISSED" ? qsTr("dismissed") : modelData.kind === "review" ? qsTr("reviewed") : ""
                                    tagColour: modelData.state === "APPROVED" ? Colours.palette.m3success : modelData.state === "CHANGES_REQUESTED" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                    visible: body !== "" || modelData.kind === "review"
                                }
                            }
                        }
                    }

                    // ---------- files ----------
                    RowLayout {
                        spacing: Tokens.spacing.medium

                        ListView {
                            Layout.preferredWidth: 280
                            Layout.maximumWidth: 280
                            Layout.fillWidth: false
                            Layout.fillHeight: true
                            clip: true
                            model: win.diffFiles
                            delegate: StyledRect {
                                id: fItem
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                implicitHeight: frow.implicitHeight + Tokens.padding.small * 2
                                radius: Tokens.rounding.small
                                color: "transparent"
                                StateLayer {
                                    radius: Tokens.rounding.small
                                    onClicked: {
                                        if (win.collapsed[fItem.index])
                                            win.toggleFile(fItem.index);
                                        Qt.callLater(() => win.jumpTo(fItem.index));
                                    }
                                }
                                RowLayout {
                                    id: frow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Tokens.padding.small
                                    spacing: Tokens.spacing.small
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: fItem.modelData.path.split("/").pop()
                                        elide: Text.ElideMiddle
                                        font: Tokens.font.body.small
                                        color: win.collapsed[fItem.index] ? Colours.palette.m3outline : Colours.palette.m3onSurface
                                    }
                                    StyledText { text: "+" + fItem.modelData.add; color: Colours.palette.m3success; font: Tokens.font.label.small }
                                    StyledText { text: "−" + fItem.modelData.del; color: Colours.palette.m3error; font: Tokens.font.label.small }
                                }
                            }
                        }

                        ListView {
                            id: diffView
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            Layout.fillHeight: true
                            clip: true
                            model: win.visibleLines
                            reuseItems: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}
                            cacheBuffer: 2000

                            StyledText {
                                anchors.centerIn: parent
                                visible: win.diffLines.length === 0
                                text: diffProc.running ? qsTr("Loading diff…") : qsTr("No diff")
                                color: Colours.palette.m3outline
                            }

                            delegate: Rectangle {
                                id: dl
                                required property var modelData
                                readonly property string k: modelData.k
                                width: ListView.view.width - 12
                                implicitHeight: k === "file" ? fileHead.implicitHeight + 12 : k === "comment" ? cmt.implicitHeight + 12 : Math.max(18, code.implicitHeight)
                                color: k === "add" ? Qt.alpha(Colours.palette.m3success, 0.14)
                                     : k === "del" ? Qt.alpha(Colours.palette.m3error, 0.14)
                                     : k === "hunk" ? Qt.alpha(Colours.palette.m3primary, 0.08)
                                     : k === "file" ? Colours.palette.m3surfaceContainerHigh
                                     : k === "comment" ? Colours.palette.m3surfaceContainer : "transparent"
                                radius: k === "file" || k === "comment" ? Tokens.rounding.small : 0

                                // file header
                                RowLayout {
                                    id: fileHead
                                    visible: dl.k === "file"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.small
                                    anchors.rightMargin: Tokens.padding.small
                                    spacing: Tokens.spacing.small
                                    MaterialIcon {
                                        text: win.collapsed[dl.modelData.f] ? "chevron_right" : "expand_more"
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: dl.k === "file" ? dl.modelData.t : ""
                                        font: Tokens.font.mono.small
                                        elide: Text.ElideMiddle
                                    }
                                    StyledText {
                                        readonly property var f: dl.k === "file" ? win.diffFiles[dl.modelData.f] : null
                                        text: f ? (f.status ? f.status + "  " : "") + "+" + f.add + " −" + f.del : ""
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.small
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: dl.k === "file"
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.toggleFile(dl.modelData.f)
                                }

                                // review comment on a line
                                Column {
                                    id: cmt
                                    visible: dl.k === "comment"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 96
                                    anchors.rightMargin: Tokens.padding.medium
                                    spacing: 2
                                    StyledText {
                                        text: dl.k === "comment" ? dl.modelData.a : ""
                                        color: Colours.palette.m3primary
                                        font: Tokens.font.label.small
                                    }
                                    StyledText {
                                        width: parent.width
                                        text: dl.k === "comment" ? dl.modelData.t : ""
                                        textFormat: Text.MarkdownText
                                        wrapMode: Text.Wrap
                                        font: Tokens.font.body.small
                                    }
                                }

                                // code line
                                Row {
                                    visible: dl.k !== "file" && dl.k !== "comment"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    StyledText {
                                        width: 44
                                        horizontalAlignment: Text.AlignRight
                                        text: dl.modelData.o !== undefined ? dl.modelData.o : ""
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.mono.small
                                    }
                                    StyledText {
                                        width: 44
                                        horizontalAlignment: Text.AlignRight
                                        text: dl.modelData.n !== undefined ? dl.modelData.n : ""
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.mono.small
                                    }
                                    StyledText {
                                        width: 18
                                        horizontalAlignment: Text.AlignHCenter
                                        text: dl.k === "add" ? "+" : dl.k === "del" ? "−" : ""
                                        color: dl.k === "add" ? Colours.palette.m3success : Colours.palette.m3error
                                        font: Tokens.font.mono.small
                                    }
                                    StyledText {
                                        id: code
                                        width: parent.width - 106
                                        text: dl.k === "hunk" ? "@@ " + dl.modelData.t : dl.modelData.t
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WrapAnywhere
                                        color: dl.k === "hunk" ? Colours.palette.m3primary : dl.k === "meta" ? Colours.palette.m3outline : Colours.palette.m3onSurface
                                        font: Tokens.font.mono.small
                                    }
                                }
                            }
                        }
                    }

                    // ---------- checks ----------
                    Flickable {
                        id: checksFlick
                        clip: true
                        contentWidth: width
                        contentHeight: checksCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        ColumnLayout {
                            id: checksCol
                            width: checksFlick.width - 12
                            spacing: Tokens.spacing.small

                            StyledText {
                                visible: win.checks.length === 0
                                text: qsTr("No checks on this PR.")
                                color: Colours.palette.m3outline
                            }

                            Repeater {
                                model: win.checks
                                delegate: ColumnLayout {
                                    id: ck
                                    required property var modelData
                                    readonly property string st: win.checkState(modelData)
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.small

                                    StyledRect {
                                        Layout.fillWidth: true
                                        implicitHeight: ckRow.implicitHeight + Tokens.padding.small * 2
                                        radius: Tokens.rounding.small
                                        color: Colours.palette.m3surfaceContainer

                                        RowLayout {
                                            id: ckRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.margins: Tokens.padding.medium
                                            spacing: Tokens.spacing.medium

                                            MaterialIcon {
                                                text: ck.st === "ok" ? "check_circle" : ck.st === "fail" ? "cancel" : "progress_activity"
                                                color: win.stateColour(ck.st)
                                                RotationAnimation on rotation {
                                                    running: ck.st === "pending"
                                                    loops: Animation.Infinite
                                                    from: 0
                                                    to: 360
                                                    duration: 1200
                                                }
                                            }
                                            Column {
                                                Layout.fillWidth: true
                                                StyledText {
                                                    text: ck.modelData.name
                                                    font: Tokens.font.body.small
                                                }
                                                StyledText {
                                                    text: (ck.modelData.workflow ? ck.modelData.workflow + "  ·  " : "") + (ck.st === "pending" ? ck.modelData.status.toLowerCase().replace(/_/g, " ") : ck.modelData.conclusion.toLowerCase()) + (ck.modelData.started ? "  ·  " + win.dur(ck.modelData.started, ck.modelData.done) : "")
                                                    color: Colours.palette.m3onSurfaceVariant
                                                    font: Tokens.font.label.small
                                                }
                                            }
                                            IconTextButton {
                                                visible: ck.st === "fail" && !!ck.modelData.run
                                                type: ButtonBase.Text
                                                icon: "terminal"
                                                text: win.openLog === ck.modelData.run ? qsTr("Hide log") : qsTr("Log")
                                                onClicked: win.showLog(ck.modelData.run)
                                            }
                                            IconTextButton {
                                                visible: ck.st === "fail" && !!ck.modelData.run
                                                type: ButtonBase.Text
                                                icon: "replay"
                                                text: qsTr("Re-run")
                                                onClicked: win.act("Re-run", ["rerun", ck.modelData.run])
                                            }
                                            IconButton {
                                                icon: "open_in_new"
                                                type: IconButton.Text
                                                onClicked: MitchHub.open(ck.modelData.url)
                                            }
                                        }
                                    }

                                    StyledRect {
                                        visible: win.openLog !== "" && win.openLog === ck.modelData.run
                                        Layout.fillWidth: true
                                        implicitHeight: Math.min(logText.implicitHeight + Tokens.padding.medium * 2, 520)
                                        radius: Tokens.rounding.small
                                        color: Colours.palette.m3surfaceContainerLowest
                                        clip: true

                                        Flickable {
                                            id: logFlick
                                            anchors.fill: parent
                                            anchors.margins: Tokens.padding.medium
                                            contentWidth: width
                                            contentHeight: logText.implicitHeight
                                            boundsBehavior: Flickable.StopAtBounds
                                            ScrollBar.vertical: ScrollBar {}
                                            // the error is at the bottom
                                            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                                            TextEdit {
                                                id: logText
                                                width: logFlick.width - 12
                                                readOnly: true
                                                selectByMouse: true
                                                wrapMode: TextEdit.WrapAnywhere
                                                textFormat: TextEdit.PlainText
                                                text: win.logs[ck.modelData.run] || qsTr("Loading log…")
                                                color: Colours.palette.m3onSurface
                                                selectionColor: Colours.palette.m3primaryContainer
                                                font: Tokens.font.mono.small
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------- actions ----------
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: actions.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surfaceContainer
                    visible: win.pr !== null

                    ColumnLayout {
                        id: actions
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            Layout.preferredHeight: Math.min(Math.max(msg.implicitHeight, 56), 160)
                            TextArea {
                                id: msg
                                placeholderText: qsTr("Message for a comment or review (Markdown). Ctrl+Enter comments.")
                                wrapMode: TextArea.Wrap
                                color: Colours.palette.m3onSurface
                                placeholderTextColor: Colours.palette.m3outline
                                selectionColor: Colours.palette.m3primaryContainer
                                font: Tokens.font.body.small
                                background: StyledRect {
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerHigh
                                    border.width: msg.activeFocus ? 1 : 0
                                    border.color: Colours.palette.m3primary
                                }
                                Keys.onEscapePressed: card.forceActiveFocus()
                                Keys.onPressed: event => {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && event.modifiers & Qt.ControlModifier) {
                                        if (msg.text.trim())
                                            win.act("Comment", ["comment", win.num], msg.text);
                                        event.accepted = true;
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            IconTextButton {
                                type: ButtonBase.Tonal
                                icon: "chat"
                                text: qsTr("Comment")
                                disabled: win.busy !== "" || !msg.text.trim()
                                onClicked: win.act("Comment", ["comment", win.num], msg.text)
                            }
                            IconTextButton {
                                type: ButtonBase.Tonal
                                icon: "check"
                                text: qsTr("Approve")
                                disabled: win.busy !== "" || !win.pr || win.pr.state !== "OPEN"
                                onClicked: win.act("Approve", ["review", win.num, "approve"], msg.text)
                            }
                            IconTextButton {
                                type: ButtonBase.Tonal
                                icon: "block"
                                text: qsTr("Request changes")
                                disabled: win.busy !== "" || !msg.text.trim() || !win.pr || win.pr.state !== "OPEN"
                                onClicked: win.act("Request changes", ["review", win.num, "request"], msg.text)
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.leftMargin: Tokens.spacing.medium
                                text: win.busy !== "" ? win.busy + "…" : win.note
                                color: win.busy !== "" ? Colours.palette.m3secondary : win.noteErr ? Colours.palette.m3error : Colours.palette.m3success
                                elide: Text.ElideRight
                                font: Tokens.font.label.medium
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small
                            visible: !!win.pr && win.pr.state !== "MERGED"

                            Item { Layout.fillWidth: true }

                            IconTextButton {
                                visible: !!win.pr && win.pr.isDraft && win.pr.state === "OPEN"
                                type: ButtonBase.Text
                                icon: "rate_review"
                                text: qsTr("Ready for review")
                                disabled: win.busy !== ""
                                onClicked: win.act("Ready", ["ready", win.num])
                            }

                            // merge: method + delete branch + two-click confirm
                            Repeater {
                                model: !!win.pr && win.pr.state === "OPEN" ? [["squash", qsTr("Squash")], ["merge", qsTr("Merge commit")], ["rebase", qsTr("Rebase")]] : []
                                delegate: IconTextButton {
                                    required property var modelData
                                    isToggle: true
                                    checked: win.mergeHow === modelData[0]
                                    text: modelData[1]
                                    font: Tokens.font.label.small
                                    verticalPadding: Tokens.padding.small
                                    onClicked: win.mergeHow = modelData[0]
                                }
                            }
                            IconTextButton {
                                visible: !!win.pr && win.pr.state === "OPEN"
                                isToggle: true
                                checked: win.deleteBranch
                                icon: "delete_sweep"
                                text: qsTr("Delete branch")
                                font: Tokens.font.label.small
                                verticalPadding: Tokens.padding.small
                                onClicked: win.deleteBranch = !win.deleteBranch
                            }
                            IconTextButton {
                                visible: !!win.pr && win.pr.state === "OPEN"
                                type: ButtonBase.Filled
                                icon: "merge"
                                text: win.confirm === "merge" ? qsTr("Confirm merge") : qsTr("Merge")
                                disabled: win.busy !== "" || (!!win.pr && (win.pr.isDraft || win.pr.mergeable === "CONFLICTING"))
                                onClicked: {
                                    if (win.confirm !== "merge") {
                                        win.confirm = "merge";
                                        confirmReset.restart();
                                    } else {
                                        win.act("Merge", ["merge", win.num, win.mergeHow].concat(win.deleteBranch ? ["delete"] : []));
                                    }
                                }
                            }
                            IconTextButton {
                                visible: !!win.pr && win.pr.state !== "MERGED"
                                type: ButtonBase.Text
                                icon: win.pr && win.pr.state === "CLOSED" ? "replay" : "cancel"
                                text: win.pr && win.pr.state === "CLOSED" ? qsTr("Reopen") : win.confirm === "close" ? qsTr("Confirm close") : qsTr("Close PR")
                                disabled: win.busy !== ""
                                onClicked: {
                                    if (win.pr.state === "CLOSED") {
                                        win.act("Reopen", ["reopen", win.num]);
                                    } else if (win.confirm !== "close") {
                                        win.confirm = "close";
                                        confirmReset.restart();
                                    } else {
                                        win.act("Close", ["close", win.num], msg.text);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Timer { id: confirmReset; interval: 4000; onTriggered: win.confirm = "" }

    component Badge: StyledRect {
        property alias text: bt.text
        property color fg: Colours.palette.m3onSurfaceVariant
        property bool mono: false
        implicitWidth: bt.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: bt.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainer
        visible: text !== ""
        StyledText {
            id: bt
            anchors.centerIn: parent
            color: parent.fg
            font: parent.mono ? Tokens.font.mono.small : Tokens.font.label.small
        }
    }

    component Post: StyledRect {
        id: post
        property string who
        property string at
        property string body
        property string tag
        property color tagColour: Colours.palette.m3onSurfaceVariant
        implicitHeight: postCol.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainer

        ColumnLayout {
            id: postCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small
            RowLayout {
                spacing: Tokens.spacing.small
                StyledText {
                    text: post.who
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.medium
                }
                StyledText {
                    visible: post.tag !== ""
                    text: post.tag
                    color: post.tagColour
                    font: Tokens.font.label.small
                }
                StyledText {
                    text: MitchHub.ago(post.at)
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }
            TextEdit {
                Layout.fillWidth: true
                visible: post.body !== ""
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.MarkdownText
                wrapMode: TextEdit.Wrap
                text: post.body
                color: Colours.palette.m3onSurface
                selectionColor: Colours.palette.m3primaryContainer
                font: Tokens.font.body.small
                onLinkActivated: link => MitchHub.open(link)
                HoverHandler {
                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
                }
            }
        }
    }
}
