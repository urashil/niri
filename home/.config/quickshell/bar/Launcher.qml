import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Mod+Space. Apps by default; "w " windows, "c " clipboard, "> " run, "s " web search; maths evaluates inline.
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
    function calc(q) {
        if (!/^[0-9+\-*/().%^\s,]+$/.test(q) || !/[0-9]/.test(q) || !/[+\-*/%^]/.test(q.replace(/^-/, ""))) return null;
        try {
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**").replace(/,/g, ".") + ")")();
            return typeof v === "number" && isFinite(v) ? v : null;
        } catch (e) { return null; }
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
            onTextChanged: { win.query = text; list.currentIndex = 0; if (text.startsWith("c ") && win.clip.length === 0) clipProc.running = true; if (text === "c") clipProc.running = true; }
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
                model: [["w", "windows"], ["c", "clipboard"], [">", "run"], ["s", "web"], ["1+2", "calc"]]
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
                IconImage { id: ic; implicitSize: 30; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } source: row.modelData.icon }
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
