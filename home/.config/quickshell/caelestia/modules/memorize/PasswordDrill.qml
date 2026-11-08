pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Memorize (Mod+Alt+P): learn a long password / number in one sitting, then recall it at growing gaps.
// Diceware passphrases are generated / detected via the EFF wordlist. Typing is hidden. Saved (0600) in
// ~/.local/share/rice/memorize.json. Ported from the niri bar; the drill logic is unchanged.
PanelWindow {
    id: win

    property bool shown: false

    visible: shown
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.4)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "caelestia-memorize"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int need: 3
    readonly property var steps: [10, 30, 60, 120, 300]
    property var items: []
    property int cur: -1
    property bool adding: false
    property bool reveal: false
    property bool studying: false
    property string result: ""
    property int errAt: -1
    property string lastTry: ""
    property bool showTyping: false
    property real now: Date.now()
    readonly property var item: cur >= 0 && cur < items.length ? items[cur] : null
    function piecesOf(it) { return it && it.kind === "diceware" && it.words ? it.words : (it ? groups(it.text, it.chunk) : []); }
    function pieceCount(it) { return it && it.kind === "diceware" && it.words ? it.words.length : (it ? Math.ceil(it.text.length / it.chunk) : 0); }
    function sizeLabel(it) { return it.kind === "diceware" ? pieceCount(it) + " words" : it.text.length + " characters"; }
    function bitsOf(it) { return Math.round(pieceCount(it) * 12.925); }
    readonly property var pieces: piecesOf(item)
    readonly property int chunks: pieces.length
    readonly property bool learning: item !== null && item.learned < chunks
    readonly property string target: !item ? "" : learning ? pieces.slice(0, item.learned + 1).join("") : pieces.join("")

    function close() { win.shown = false; }
    function norm(s) { return s.replace(/\s+/g, ""); }
    function groups(s, n) { const out = []; for (let i = 0; i < s.length; i += n) out.push(s.slice(i, i + n)); return out; }
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
    function save() {
        file.setText(JSON.stringify(items));
        Quickshell.execDetached(["chmod", "600", file.path]);
    }
    function update(patch) {
        const l = items.slice();
        l[cur] = Object.assign({}, l[cur], patch);
        items = l;
        save();
    }
    function pick(i) {
        cur = i; adding = false; reveal = false; result = ""; errAt = -1; answer.text = "";
        studying = item !== null && learning && !(item.reps > 0);
        focusNow();
    }
    function focusNow() { if (studying) studyKeys.forceActiveFocus(); else answer.forceActiveFocus(); }
    function startAdd() { adding = true; cur = -1; reveal = false; result = ""; nameIn.text = ""; textIn.text = ""; if (addMode === "diceware") reroll(); nameIn.forceActiveFocus(); }

    property string addMode: "password"
    property int genCount: 6
    property var genWords: []
    property real genBits: 0
    function setAddMode(m) { addMode = m; if (m === "diceware") reroll(); else answer.text = ""; }
    function reroll() { gen.command = [Quickshell.env("HOME") + "/.local/bin/diceware", "--json", String(genCount)]; gen.running = true; }
    Process {
        id: gen
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); win.genWords = d.words || []; win.genBits = d.bits || 0; } catch (e) {} } }
    }
    function add() {
        if (adding && addMode === "diceware") {
            if (!genWords || genWords.length === 0) return;
            const dname = nameIn.text.trim() || "Passphrase " + (items.length + 1);
            items = items.concat([{ name: dname, text: genWords.join(" "), words: genWords.slice(), kind: "diceware", chunk: 0, learned: 0, step: 0, due: 0, streak: 0, misses: 0 }]);
            save();
            genWords = [];
            pick(items.length - 1);
            return;
        }
        const t = norm(textIn.text);
        if (t === "") return;
        const name = nameIn.text.trim() || "Item " + (items.length + 1);
        items = items.concat([{ name: name, text: t, chunk: /^[0-9]+$/.test(t) ? 5 : 4, learned: 0, step: 0, due: 0, streak: 0, misses: 0 }]);
        save();
        textIn.text = "";
        pick(items.length - 1);
    }
    function remove(i) {
        items = items.filter((_, k) => k !== i);
        save();
        cur = -1; result = "";
        if (items.length) pick(0); else startAdd();
    }
    function setChunk(n) { update({ chunk: n, learned: 0, reps: 0, step: 0, due: 0, done: false }); pick(cur); }
    function relearn() { update({ learned: 0, reps: 0, step: 0, due: 0, done: false }); pick(cur); }
    function again() { update({ step: 0, due: Date.now(), done: false }); pick(cur); }
    function learned(it) { return it.learned >= pieceCount(it); }
    function due(it) { return learned(it) && !it.done && it.due > 0 && it.due <= now; }
    function secs(ms) { const t = Math.max(0, Math.ceil(ms / 1000)); return t < 60 ? t + "s" : Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0"); }
    function when(it) {
        if (!learned(it)) return Math.round(100 * it.learned / Math.max(1, pieceCount(it))) + "% learned";
        if (it.done) return "memorized";
        return it.due <= now ? "recall now" : "recall in " + secs(it.due - now);
    }
    function pieceIndexAt(off) { let n = 0; for (let i = 0; i < pieces.length; i++) { n += pieces[i].length; if (off < n) return i; } return pieces.length - 1; }
    readonly property int errChunk: result === "wrong" && errAt >= 0 && item ? pieceIndexAt(errAt) : -1

    function check() {
        if (!item) return;
        if (studying) { studying = false; answer.text = ""; result = ""; focusNow(); return; }
        const a = norm(answer.text);
        if (a === "") return;
        lastTry = a;
        answer.text = "";
        if (a === target) {
            errAt = -1;
            if (learning) {
                const reps = (item.reps || 0) + 1;
                if (reps < need) { update({ reps: reps }); result = "again"; focusNow(); return; }
                const done = item.learned + 1 >= chunks;
                update({ learned: item.learned + 1, reps: 0, due: done ? Date.now() : 0, step: 0, done: false });
                result = done ? "learned" : "ok";
                studying = !done;
                focusNow();
                return;
            } else {
                const fin = item.step >= steps.length;
                update({ step: item.step + 1, due: fin ? 0 : Date.now() + steps[item.step] * 1000, streak: item.streak + 1, done: fin });
                result = fin ? "memorized" : "ok";
            }
        } else {
            let i = 0;
            while (i < a.length && i < target.length && a[i] === target[i]) i++;
            errAt = i;
            result = "wrong";
            if (learning) update({ misses: item.misses + 1, reps: 0 });
            else update({ step: Math.max(0, item.step - 1), due: Date.now(), streak: 0, misses: item.misses + 1 });
        }
        answer.forceActiveFocus();
    }

    onVisibleChanged: {
        if (!visible) { reveal = false; showTyping = false; answer.text = ""; textIn.text = ""; return; }
        now = Date.now();
        if (items.length === 0) startAdd();
        else if (cur < 0) { const d = items.findIndex(it => win.due(it)); pick(d >= 0 ? d : 0); }
        else pick(cur);
    }

    IpcHandler {
        function toggle(): void { win.shown = !win.shown; }
        function show(): void { win.shown = true; }
        function hide(): void { win.shown = false; }
        target: "drill"
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/share/rice/memorize.json"
        printErrors: false
        onLoaded: { try { win.items = JSON.parse(text()); } catch (e) { win.items = []; } win.detect(); }
    }

    property var effSet: ({})
    property int effMax: 1
    property bool effReady: false
    FileView {
        id: wordlist
        path: Quickshell.env("HOME") + "/.local/share/rice/eff_large_wordlist.txt"
        printErrors: false
        onLoaded: {
            const m = {}; let mx = 1;
            for (const w of text().split("\n")) { const t = w.trim(); if (t) { m[t] = true; if (t.length > mx) mx = t.length; } }
            win.effSet = m; win.effMax = mx; win.effReady = true;
            win.detect();
        }
    }
    function segment(s) {
        const n = s.length;
        const best = new Array(n + 1).fill(null);
        best[0] = { score: 0, words: [] };
        for (let i = 1; i <= n; i++)
            for (let j = Math.max(0, i - win.effMax); j < i; j++) {
                if (!best[j]) continue;
                const w = s.slice(j, i);
                if (win.effSet[w] === true) {
                    const sc = best[j].score + w.length * w.length;
                    if (!best[i] || sc > best[i].score) best[i] = { score: sc, words: best[j].words.concat([w]) };
                }
            }
        return best[n] ? best[n].words : null;
    }
    function asDiceware(t) {
        if (!win.effReady || !t || /[^a-z-]/.test(t)) return null;
        const seg = segment(t);
        return seg && seg.length >= 3 ? seg : null;
    }
    function detect() {
        if (!win.effReady || win.items.length === 0) return;
        let changed = false;
        const l = win.items.map(it => {
            if (it.kind || (it.words && it.words.length)) return it;
            const seg = win.asDiceware(it.text);
            if (!seg) return it;
            changed = true;
            return Object.assign({}, it, { kind: "diceware", words: seg });
        });
        if (changed) { win.items = l; win.save(); }
    }

    property var nudged: ({})
    Timer {
        interval: 5000; running: win.items.length > 0; repeat: true; triggeredOnStart: true
        onTriggered: {
            win.now = Date.now();
            if (win.visible) return;
            const d = win.items.filter(it => win.due(it) && win.nudged[it.name] !== it.due);
            if (d.length === 0) return;
            for (const it of d) win.nudged[it.name] = it.due;
            Quickshell.execDetached(["caelestia", "shell", "toaster", "info", "Memorize", "Recall " + d.map(it => it.name).join(", ") + " now (Mod+Alt+P)", "key"]);
        }
    }
    Timer { interval: 1000; running: win.visible; repeat: true; onTriggered: win.now = Date.now() }

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    component Chip: IconTextButton {
        property bool on: false
        isToggle: true
        checked: on
        font: Tokens.font.label.small
        verticalPadding: Tokens.padding.small
    }

    component Field: Rectangle {
        property alias input: ti
        property string hint
        property bool mono: false
        property bool secret: false
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh
        border.width: ti.activeFocus ? 1.5 : 0
        border.color: Colours.palette.m3primary
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
            echoMode: parent.secret && !win.showTyping ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            font.family: parent.mono ? Tokens.font.mono.medium.family : Tokens.font.body.medium.family
            font.pixelSize: parent.mono ? 17 : 14
            font.letterSpacing: parent.mono ? 1.5 : 0
            color: Colours.palette.m3onSurface
            selectionColor: Colours.palette.m3primary
            selectedTextColor: Colours.palette.m3onPrimary
            clip: true
            Keys.onEscapePressed: win.close()
            StyledText { visible: !ti.text; text: parent.parent.hint; color: Colours.palette.m3outline; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    StyledRect {
        id: card
        anchors.centerIn: parent
        width: 560
        implicitHeight: col.implicitHeight + 40
        radius: Tokens.rounding.large
        color: Colours.palette.m3surface
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                MaterialIcon { text: "password"; color: Colours.palette.m3primary }
                StyledText { text: "Memorize"; font: Tokens.font.title.small; Layout.fillWidth: true }
                MaterialIcon {
                    text: "close"
                    color: Colours.palette.m3onSurfaceVariant
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: win.items
                    delegate: StyledRect {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool sel: !win.adding && win.cur === index
                        implicitWidth: chipText.implicitWidth + 24
                        implicitHeight: 30
                        radius: Tokens.rounding.full
                        color: sel ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainer
                        border.width: win.due(modelData) ? 1 : 0
                        border.color: Colours.palette.m3primary
                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: (chip.modelData.kind === "diceware" ? "⚅ " : "") + chip.modelData.name + "  ·  " + win.when(chip.modelData)
                            font: Tokens.font.label.small
                            color: chip.sel ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(chip.index) }
                    }
                }
                StyledRect {
                    implicitWidth: addText.implicitWidth + 24
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: win.adding ? Colours.palette.m3primaryContainer : "transparent"
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant
                    StyledText { id: addText; anchors.centerIn: parent; text: "+ Add"; font: Tokens.font.label.small; color: win.adding ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.startAdd() }
                }
            }

            // ---- add ----
            RowLayout {
                visible: win.adding
                Layout.fillWidth: true; spacing: 6
                Chip { text: "Password / digits"; on: win.addMode === "password"; onClicked: win.setAddMode("password") }
                Chip { text: "Diceware"; on: win.addMode === "diceware"; onClicked: win.setAddMode("diceware") }
                Item { Layout.fillWidth: true }
            }
            Field { id: nameF; visible: win.adding; hint: "Name (e.g. pi, Bitwarden)" }
            Field { id: textF; visible: win.adding && win.addMode === "password"; mono: true; secret: true; hint: "What to memorize (digits, a password…)" }
            Connections { target: win.textIn; function onAccepted() { win.add(); } }

            ColumnLayout {
                visible: win.adding && win.addMode === "diceware"
                Layout.fillWidth: true; spacing: 8
                StyledRect {
                    Layout.fillWidth: true; implicitHeight: genT.implicitHeight + 24; radius: Tokens.rounding.medium; color: Colours.palette.m3surfaceContainer
                    StyledText {
                        id: genT
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                        wrapMode: Text.Wrap
                        font.family: Tokens.font.mono.medium.family
                        font.pixelSize: 19
                        font.letterSpacing: 1.0
                        color: Colours.palette.m3onSurface
                        text: win.genWords.length ? win.genWords.join("  ") : "generating…"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    StyledText { text: "Words"; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant; Layout.rightMargin: 4 }
                    Repeater {
                        model: [4, 5, 6, 7, 8]
                        delegate: Chip { required property int modelData; text: String(modelData); on: win.genCount === modelData; onClicked: { win.genCount = modelData; win.reroll(); } }
                    }
                    Item { Layout.fillWidth: true }
                    Chip { text: "Reroll"; icon: "casino"; onClicked: win.reroll() }
                }
                StyledText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "~" + win.genBits + " bits · cryptographic RNG over the EFF 7776-word list. Read it now — you'll memorise it word by word next."
                    font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant
                }
            }

            RowLayout {
                visible: win.adding
                Layout.fillWidth: true
                StyledText { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Kept in a file only you can read, so it can be shown again."; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant }
                Chip { text: "Start"; on: true; onClicked: win.add() }
            }

            // ---- practise ----
            ColumnLayout {
                visible: !win.adding && win.item !== null
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: win.chunks
                        delegate: StyledRect {
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: 3
                            color: win.item && index < win.item.learned ? Colours.palette.m3primary : win.item && index === win.item.learned && win.learning ? Colours.palette.m3secondary : Colours.palette.m3surfaceContainerHigh
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: {
                        if (!win.item) return "";
                        const dw = win.item.kind === "diceware" ? "Diceware · ~" + win.bitsOf(win.item) + " bits · " : "";
                        if (win.learning) return dw + (win.item.kind === "diceware" ? "Word " : "Chunk ") + (win.item.learned + 1) + " of " + win.chunks + "  ·  right " + (win.item.reps || 0) + " of " + win.need + " in a row  ·  " + win.sizeLabel(win.item);
                        if (win.item.done) return dw + "Memorized  ·  " + win.sizeLabel(win.item);
                        return dw + "Recall " + Math.min(win.item.step + 1, win.steps.length + 1) + " of " + (win.steps.length + 1) + "  ·  " + win.when(win.item) + (win.item.streak > 0 ? "  ·  " + win.item.streak + " in a row" : "");
                    }
                    font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant
                }

                StyledRect {
                    visible: win.studying || win.reveal || win.errChunk >= 0
                    Layout.fillWidth: true
                    implicitHeight: study.implicitHeight + 24
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surfaceContainer
                    StyledText {
                        id: study
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                        wrapMode: Text.Wrap
                        textFormat: Text.StyledText
                        font.family: Tokens.font.mono.medium.family
                        font.pixelSize: 20
                        font.letterSpacing: 1.5
                        color: Colours.palette.m3onSurfaceVariant
                        text: {
                            if (!win.item) return "";
                            const g = win.pieces;
                            if (win.reveal) return g.map(win.esc).join("  ");
                            if (win.errChunk >= 0) return g.slice(0, win.errChunk + 1).map((c, i) => i === win.errChunk ? "<font color='" + Colours.palette.m3onSurface + "'><b>" + win.esc(c) + "</b></font>" : "•".repeat(c.length)).join("  ");
                            return g.slice(0, win.item.learned + 1).map((c, i) => i === win.item.learned ? "<font color='" + Colours.palette.m3onSurface + "'><b>" + win.esc(c) + "</b></font>" : win.esc(c)).join("  ");
                        }
                    }
                }

                Field {
                    id: answerF
                    visible: !win.studying && !(win.item && win.item.done)
                    mono: true
                    secret: true
                    hint: !win.item ? "" : win.learning ? (win.item.kind === "diceware" ? "Type the first " + (win.item.learned + 1) + " of " + win.chunks + " words from memory" : "Type the first " + Math.min(win.item.text.length, (win.item.learned + 1) * win.item.chunk) + " from memory") : win.item.due > win.now ? "Next recall in " + win.secs(win.item.due - win.now) + " (waiting helps; you can type now)" : "Type all of it from memory"
                }
                Connections { target: win.answer; function onAccepted() { win.check(); } }
                Item { id: studyKeys; Keys.onReturnPressed: win.check(); Keys.onEnterPressed: win.check(); Keys.onEscapePressed: win.close() }

                StyledText {
                    visible: win.result === "wrong" && win.errAt >= 0
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.StyledText
                    font.family: Tokens.font.mono.medium.family
                    font.pixelSize: 15
                    font.letterSpacing: 1.5
                    text: "<font color='" + Colours.palette.m3primary + "'>" + "•".repeat(Math.max(0, win.errAt)) + "</font><font color='" + Colours.palette.m3error + "'><u>" + "•".repeat(Math.max(1, win.lastTry.length - win.errAt)) + "</u></font>"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: win.studying ? (win.result === "ok" ? "Right. " : "") + "Study the bold chunk, then hide it and type everything so far." : win.result === "ok" ? "Right. Next recall in " + win.secs(win.item.due - win.now) + ": look away, keep it in your head." : win.result === "again" ? "Right (" + (win.item.reps || 0) + " of " + win.need + "). Again, from memory." : win.result === "learned" ? "All of it! Now recall it a few times, with growing gaps." : win.result === "memorized" ? "Memorized." : win.result === "wrong" ? "Went wrong at character " + (win.errAt + 1) + ". Look at the bold chunk, then type it all again." : ""
                        font: Tokens.font.label.small
                        color: win.result === "ok" || win.result === "again" || win.result === "learned" || win.result === "memorized" ? Colours.palette.m3primary : win.result === "wrong" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    }
                    Chip { visible: !(win.item && win.item.done); text: win.studying ? "Hide & type" : "Check"; on: true; onClicked: win.check() }
                    Chip { visible: win.item !== null && win.item.done === true; text: "Practise again"; on: true; onClicked: win.again() }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Chip { text: win.reveal ? "Hide" : "Show"; icon: win.reveal ? "visibility_off" : "visibility"; onClicked: win.reveal = !win.reveal }
                    Chip { text: win.showTyping ? "Hide typing" : "Show typing"; on: win.showTyping; onClicked: { win.showTyping = !win.showTyping; win.focusNow(); } }
                    Chip { text: "Restart"; icon: "restart_alt"; onClicked: win.relearn() }
                    Item { Layout.fillWidth: true }
                    Chip { text: "Remove"; icon: "delete"; inactiveOnColour: Colours.palette.m3error; onClicked: win.remove(win.cur) }
                }
                RowLayout {
                    visible: win.item !== null && win.item.kind !== "diceware"
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: "Chunk size"; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant; Layout.rightMargin: 4 }
                    Repeater {
                        model: [3, 4, 5, 6, 8]
                        delegate: Chip {
                            required property int modelData
                            text: String(modelData)
                            on: win.item !== null && win.item.chunk === modelData
                            onClicked: win.setChunk(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                StyledText {
                    visible: win.item !== null && win.item.kind === "diceware"
                    text: "Diceware passphrase · memorised one word at a time"
                    font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
    property alias nameIn: nameF.input
    property alias textIn: textF.input
    property alias answer: answerF.input
}
