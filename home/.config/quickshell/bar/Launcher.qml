import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Mod+Space. Apps by default; "w " windows, "c " clipboard, "e " emoji, "f " files, "> " run, "s " web search;
// maths and unit conversions ("5 km in mi") evaluate inline.
PanelWindow {
    id: win
    visible: UiState.launcher
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.25)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.launcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 8 }

    property string query: ""
    property var clip: []
    readonly property var results: build(query)

    onVisibleChanged: {
        if (visible) { input.text = ""; input.forceActiveFocus(); list.currentIndex = 0; Niri.refresh(); }
    }
    function close() { UiState.launcher = false; }

    Process {
        id: clipProc
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: win.clip = text.split("\n").filter(l => l.length > 0).slice(0, 60) }
    }
    property var emoji: []
    FileView {
        path: Quickshell.env("HOME") + "/.local/share/rice/emoji.tsv"
        onLoaded: win.emoji = text().split("\n").filter(l => l.length > 0).map(l => l.split("\t"))
    }
    property var files: []
    Process {
        id: fileProc
        stdout: StdioCollector { onStreamFinished: win.files = text.split("\n").filter(l => l.length > 0) }
    }
    Timer {
        id: fileDelay
        interval: 180
        onTriggered: {
            const t = win.query.slice(2).trim();
            if (t.length < 2) { win.files = []; return; }
            fileProc.command = ["fd", "--max-results", "40", "--ignore-case", "--hidden", "--exclude", ".git", "--exclude", ".cache", "--exclude", "node_modules", t, Quickshell.env("HOME")];
            fileProc.running = true;
        }
    }
    function iconFor(name) { return Quickshell.iconPath(name || "application-x-executable", "application-x-executable"); }

    function score(e, q) {
        const n = (e.name || "").toLowerCase();
        if (n === q) return 200;
        if (n.startsWith(q)) return 120;
        if (n.indexOf(" " + q) >= 0) return 90;
        if (n.indexOf(q) >= 0) return 60;
        const extra = ((e.genericName || "") + " " + (e.comment || "") + " " + (e.keywords ? e.keywords.join(" ") : "")).toLowerCase();
        if (extra.indexOf(q) >= 0) return 25;
        let i = 0;
        for (const c of n) if (c === q[i]) i++;
        return i === q.length ? 10 : 0;
    }
    readonly property var fns: ["sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "abs", "round", "floor", "ceil", "exp"]
    function calc(q) {
        let t = q.toLowerCase();
        let hasFn = false;
        for (const f of fns) if (new RegExp("\\b" + f + "\\s*\\(").test(t)) { hasFn = true; t = t.replace(new RegExp("\\b" + f + "(?=\\s*\\()", "g"), f === "ln" ? "Math.log" : f === "log" ? "Math.log10" : "Math." + f); }
        t = t.replace(/\bpi\b/g, "Math.PI").replace(/\be\b/g, "Math.E");
        const bare = t.replace(/Math\.[A-Za-z0-9]+/g, "1");
        if (!/^[0-9+\-*/().%^\s,]+$/.test(bare) || !/[0-9]/.test(bare)) return null;
        if (!hasFn && !/[+\-*/%^]/.test(bare.replace(/^-/, ""))) return null;
        try {
            const v = Function('"use strict"; return (' + t.replace(/\^/g, "**").replace(/,/g, ".") + ")")();
            return typeof v === "number" && isFinite(v) ? v : null;
        } catch (e) { return null; }
    }
    // unit -> [kind, factor to the kind's base]; temperatures are handled apart
    readonly property var units: ({
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], ft: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344],
        mg: ["mass", 0.000001], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.028349523], lb: ["mass", 0.45359237], st: ["mass", 6.35029318],
        ml: ["vol", 0.001], l: ["vol", 1], tsp: ["vol", 0.00492892], tbsp: ["vol", 0.0147868], floz: ["vol", 0.0295735], cup: ["vol", 0.236588], pt: ["vol", 0.473176], qt: ["vol", 0.946353], gal: ["vol", 3.78541],
        b: ["data", 1], kb: ["data", 1000], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12], kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        s: ["time", 1], min: ["time", 60], h: ["time", 3600], d: ["time", 86400], wk: ["time", 604800],
        "m/s": ["speed", 1], "km/h": ["speed", 0.277778], kph: ["speed", 0.277778], mph: ["speed", 0.44704], kn: ["speed", 0.514444],
        c: ["temp", 0], f: ["temp", 0], k: ["temp", 0]
    })
    function convert(q) {
        const m = q.toLowerCase().trim().match(/^(-?[0-9]*\.?[0-9]+)\s*°?\s*([a-z/]+)\s+(?:in|to|as|->)\s+°?([a-z/]+)$/);
        if (!m) return null;
        const x = parseFloat(m[1]), a = units[m[2]], b = units[m[3]];
        if (!a || !b || a[0] !== b[0]) return null;
        let v;
        if (a[0] === "temp") {
            const c = m[2] === "c" ? x : m[2] === "f" ? (x - 32) * 5 / 9 : x - 273.15;
            v = m[3] === "c" ? c : m[3] === "f" ? c * 9 / 5 + 32 : c + 273.15;
        } else v = x * a[1] / b[1];
        return { v: v, text: +v.toPrecision(8) + " " + (a[0] === "temp" ? "°" + m[3].toUpperCase() : m[3]) };
    }
    function build(q) {
        const out = [];
        const run = (cmd) => Quickshell.execDetached(cmd);
        if (q.startsWith("w ") || q === "w") {
            const f = q.slice(2).toLowerCase();
            for (const w of Niri.windows) {
                if (f && (w.title + " " + w.app_id).toLowerCase().indexOf(f) < 0) continue;
                out.push({ title: w.title || w.app_id, sub: w.app_id + (w.is_focused ? " · focused" : ""), icon: iconFor(w.app_id), go: () => run(["niri", "msg", "action", "focus-window", "--id", String(w.id)]) });
            }
            return out;
        }
        if (q.startsWith("c ") || q === "c") {
            const f = q.slice(2).toLowerCase();
            for (const l of clip) {
                const t = l.replace(/^\d+\t/, "");
                if (f && t.toLowerCase().indexOf(f) < 0) continue;
                out.push({ title: t.length > 90 ? t.slice(0, 90) + "…" : t, sub: "clipboard", icon: iconFor("edit-paste"), go: () => run(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "_", l]) });
            }
            return out;
        }
        if (q === "e" || q.startsWith("e ")) {
            const f = q.slice(2).trim().toLowerCase();
            if (f === "") return out;
            for (const e of emoji) {
                if (e[1].indexOf(f) < 0) continue;
                out.push({ title: e[1], sub: "emoji · Enter copies", glyph: e[0], go: () => run(["wl-copy", e[0]]) });
                if (out.length >= 40) break;
            }
            return out;
        }
        if (q === "f" || q.startsWith("f ")) {
            for (const p of files) {
                const name = p.replace(/.*\//, "").replace(/\/$/, "");
                out.push({ title: name, sub: p.replace(Quickshell.env("HOME"), "~"), icon: iconFor(p.endsWith("/") ? "folder" : "text-x-generic"), go: () => run(["xdg-open", p]) });
            }
            return out;
        }
        if (q === "t" || q.startsWith("t ")) {
            const n = parseInt(q.slice(2).trim());
            if (n > 0) out.push({ title: "Start a " + n + " minute timer", sub: "timer", icon: iconFor("alarm-clock"), go: () => Focus.start(n) });
            out.push({ title: "Pomodoro  " + Focus.workMin + " / " + Focus.breakMin, sub: "timer", icon: iconFor("alarm-clock"), go: () => Focus.startPomodoro() });
            out.push({ title: "Stopwatch", sub: "timer", icon: iconFor("chronometer"), go: () => Focus.startStopwatch() });
            if (Focus.active) {
                out.push({ title: Focus.paused ? "Resume the timer" : "Pause the timer", sub: Focus.clockText, icon: iconFor("media-playback-pause"), go: () => Focus.toggle() });
                out.push({ title: "Stop the timer", sub: Focus.clockText, icon: iconFor("media-playback-stop"), go: () => Focus.stop() });
            }
            return out;
        }
        if (q.startsWith("todo ") || q.startsWith("td ")) {
            const t = q.replace(/^(todo|td)\s+/, "").trim();
            if (t) out.push({ title: "Add todo:  " + t, sub: Focus.openCount + " open", icon: iconFor("task-new"), go: () => Focus.addTodo(t) });
            return out;
        }
        if (q.startsWith(">")) {
            const c = q.slice(1).trim();
            if (c) out.push({ title: "Run  " + c, sub: "shell", icon: iconFor("utilities-terminal"), go: () => run(["sh", "-c", c]) });
            return out;
        }
        if (q.startsWith("s ")) {
            const t = q.slice(2).trim();
            if (t) out.push({ title: "Search the web for “" + t + "”", sub: "DuckDuckGo", icon: iconFor("web-browser"), go: () => run(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(t)]) });
            return out;
        }
        const v = calc(q);
        if (v !== null) out.push({ title: "= " + (Number.isInteger(v) ? v : +v.toFixed(8)), sub: "press Enter to copy", icon: iconFor("accessories-calculator"), go: () => run(["wl-copy", String(v)]) });
        const q1 = q.toLowerCase().trim();
        if (Song.installed && q1.length >= 2 && ["still@server", "song", "film", "music"].some(w => w.startsWith(q1)))
            out.push({ title: "Play " + Song.name, sub: "the animated music film · opens in the island", icon: iconFor("multimedia-audio-player"), go: () => Song.open() });
        const cv = convert(q);
        if (cv) out.push({ title: "= " + cv.text, sub: "press Enter to copy", icon: iconFor("accessories-calculator"), go: () => run(["wl-copy", String(+cv.v.toPrecision(8))]) });
        const q2 = q.toLowerCase().trim();
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        const scored = q2 === "" ? apps.map(e => ({ e: e, s: 1 })) : apps.map(e => ({ e: e, s: score(e, q2) })).filter(x => x.s > 0);
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        for (const x of scored.slice(0, 40)) out.push({ title: x.e.name, sub: x.e.comment || x.e.genericName || "", icon: iconFor(x.e.icon), go: () => x.e.execute() });
        return out;
    }
    function accept() {
        const r = results[list.currentIndex];
        if (!r) return;
        close();
        r.go();
    }

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        width: 640
        height: 74 + (win.query === "" || results.length === 0 ? 40 : 0) + Math.min(results.length, 8) * 54 + (results.length > 0 ? 14 : 0)
        radius: Theme.radius + 8
        color: Qt.alpha(Theme.surface, 0.84)
        border.width: 1
        border.color: Theme.outlineVariant
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        Text {
            id: glyph
            anchors { left: parent.left; leftMargin: 24; top: parent.top; topMargin: 25 }
            text: ""; font.family: Theme.font; font.pixelSize: 18; color: Theme.primary
        }
        TextInput {
            id: input
            anchors { left: glyph.right; leftMargin: 14; right: parent.right; rightMargin: 24; top: parent.top; topMargin: 20 }
            height: 30
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.font; font.pixelSize: 17
            color: Theme.text
            selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
            onTextChanged: { win.query = text; if (text.startsWith("f ")) fileDelay.restart(); else if (win.files.length) win.files = []; list.currentIndex = 0; if (text.startsWith("c ") && win.clip.length === 0) clipProc.running = true; if (text === "c") clipProc.running = true; }
            Keys.onEscapePressed: win.close()
            Keys.onReturnPressed: win.accept()
            Keys.onEnterPressed: win.accept()
            Keys.onDownPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
            Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
            Keys.onTabPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
            Text { visible: !input.text; text: "Search apps…"; font: input.font; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
        }

        Row {
            visible: win.query === "" || results.length === 0
            anchors { left: parent.left; leftMargin: 24; top: parent.top; topMargin: 66 }
            spacing: 14
            Repeater {
                model: [["w", "windows"], ["c", "clipboard"], ["e", "emoji"], ["f", "files"], [">", "run"], ["s", "web"], ["t", "timer"], ["todo", "task"], ["5 km in mi", "convert"]]
                delegate: Text {
                    required property var modelData
                    text: modelData[0] + "  " + modelData[1]
                    font.family: Theme.font; font.pixelSize: 11; color: Theme.outline
                }
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            height: Math.min(results.length, 8) * 54
            clip: true
            model: win.results
            currentIndex: 0
            highlightMoveDuration: 90
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width; height: 54; radius: 14
                color: ListView.isCurrentItem ? Theme.primaryContainer : "transparent"
                IconImage { id: ic; visible: !row.modelData.glyph; implicitSize: 30; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } source: row.modelData.icon || "" }
                Text { visible: !!row.modelData.glyph; width: 30; horizontalAlignment: Text.AlignHCenter; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: row.modelData.glyph || ""; font.pixelSize: 24 }
                Column {
                    anchors { left: ic.right; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text { width: parent.width; text: row.modelData.title; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 13; font.bold: true; color: row.ListView.isCurrentItem ? Theme.fgContainer : Theme.text }
                    Text { width: parent.width; visible: text !== ""; text: row.modelData.sub; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 10; color: row.ListView.isCurrentItem ? Qt.alpha(Theme.fgContainer, 0.75) : Theme.textDim }
                }
                MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: list.currentIndex = row.index; onClicked: { list.currentIndex = row.index; win.accept(); } }
            }
        }
    }
}
