import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Memorize (launcher "memorize", Mod+Alt+P): learn a long password / number right now, in one sitting.
// Learn: it is cut into chunks; study the next chunk, then type everything so far from memory, 3 times in a row without
// looking again (a miss starts the count over), before the next chunk comes.
// Recall: type it all again after 10 s, 30 s, 1, 2 and 5 minutes (about 9 minutes in all); then it counts as memorized.
// A miss shows only the chunk that went wrong, steps the gap back and asks again at once. The island says when a recall
// is due. Typing is hidden. Saved in ~/.local/share/rice/memorize.json (0600), so it can be shown again.
PanelWindow {
    id: win
    visible: UiState.drill
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.3)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-drill"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.drill ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 8 }

    readonly property int need: 3                             // right in a row, from memory, before the next chunk comes
    readonly property var steps: [10, 30, 60, 120, 300]      // seconds between recalls once learned; past the last one it is memorized
    property var items: []               // [{ name, text, chunk, learned, step, due, streak, misses }]
    property int cur: -1
    property bool adding: false
    property bool reveal: false
    property bool studying: false        // the next chunk is on screen to study
    property string result: ""           // "ok" | "wrong" | "learned"
    property int errAt: -1               // where the last wrong answer first went wrong
    property string lastTry: ""
    property bool showTyping: false      // typing is dots unless this is on
    property real now: Date.now()
    readonly property var item: cur >= 0 && cur < items.length ? items[cur] : null
    readonly property int chunks: item ? Math.ceil(item.text.length / item.chunk) : 0
    readonly property bool learning: item !== null && item.learned < chunks
    readonly property string target: !item ? "" : learning ? item.text.slice(0, (item.learned + 1) * item.chunk) : item.text

    function close() { UiState.drill = false; }
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
        // mid-way through the tries for a chunk: straight back to typing, no second look
        studying = item !== null && learning && !(item.reps > 0);
        focusNow();
    }
    function focusNow() { if (studying) studyKeys.forceActiveFocus(); else answer.forceActiveFocus(); }
    function startAdd() { adding = true; cur = -1; reveal = false; result = ""; nameIn.text = ""; textIn.text = ""; nameIn.forceActiveFocus(); }
    function add() {
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
    // another round of recalls for something already memorized
    function again() { update({ step: 0, due: Date.now(), done: false }); pick(cur); }
    function learned(it) { return it.learned * it.chunk >= it.text.length; }
    function due(it) { return learned(it) && !it.done && it.due > 0 && it.due <= now; }
    function secs(ms) { const t = Math.max(0, Math.ceil(ms / 1000)); return t < 60 ? t + "s" : Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0"); }
    function when(it) {
        if (!learned(it)) return Math.round(100 * it.learned * it.chunk / it.text.length) + "% learned";
        if (it.done) return "memorized";
        return it.due <= now ? "recall now" : "recall in " + secs(it.due - now);
    }
    // which chunk a wrong answer went wrong in (shown again to study)
    readonly property int errChunk: result === "wrong" && errAt >= 0 && item ? Math.floor(errAt / item.chunk) : -1

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
                // once right is not learned: the same again, from memory, until it is right `need` times in a row
                const reps = (item.reps || 0) + 1;
                if (reps < need) { update({ reps: reps }); result = "again"; focusNow(); return; }
                const done = item.learned + 1 >= chunks;
                // learned all of it: the first recall comes right away
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
            // a miss: one gap back, and again right now (after looking at the chunk that went wrong)
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

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/share/rice/memorize.json"
        onLoaded: { try { win.items = JSON.parse(text()); } catch (e) { win.items = []; } }
    }

    // a review is due: say so in the island, once per review
    property var nudged: ({})
    Timer {
        interval: 5000; running: win.items.length > 0; repeat: true; triggeredOnStart: true
        onTriggered: {
            win.now = Date.now();
            if (win.visible) return;
            const d = win.items.filter(it => win.due(it) && win.nudged[it.name] !== it.due);
            if (d.length === 0) return;
            for (const it of d) win.nudged[it.name] = it.due;
            UiState.pulse("drill", "", "Recall " + d.map(it => it.name).join(", ") + " now (Mod+Alt+P)", -1, Theme.primary, 8000);
        }
    }
    Timer { interval: 1000; running: win.visible; repeat: true; onTriggered: win.now = Date.now() }

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    component Field: Rectangle {
        property alias input: ti
        property string hint
        property bool mono: false
        property bool secret: false
        Layout.fillWidth: true
        height: 44; radius: 12
        color: Theme.surfaceHigh
        border.width: ti.activeFocus ? 1 : 0
        border.color: Theme.primary
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
            echoMode: parent.secret && !win.showTyping ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            font.family: Theme.font; font.pixelSize: parent.mono ? 17 : 14; font.letterSpacing: parent.mono ? 1.5 : 0
            color: Theme.text
            selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
            clip: true
            Keys.onEscapePressed: win.close()
            Text { visible: !ti.text; text: parent.parent.hint; font.family: Theme.font; font.pixelSize: 13; font.letterSpacing: 0; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 540
        height: col.implicitHeight + 40
        radius: Theme.radius + 8
        color: Qt.alpha(Theme.surface, 0.92)
        border.width: 1
        border.color: Theme.outlineVariant
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text { text: ""; font.family: Theme.font; font.pixelSize: 16; color: Theme.primary }
                Text { text: "Memorize"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                Text {
                    text: ""; font.family: Theme.font; font.pixelSize: 13; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: win.items
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: !win.adding && win.cur === index
                        width: chipText.implicitWidth + 24; height: 30; radius: 15
                        color: sel ? Theme.primaryContainer : Theme.surfaceContainer
                        border.width: win.due(modelData) ? 1 : 0
                        border.color: Theme.primary
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: parent.modelData.name + "  ·  " + win.when(parent.modelData)
                            font.family: Theme.font; font.pixelSize: 11
                            color: parent.sel ? Theme.fgContainer : Theme.text
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(parent.index) }
                    }
                }
                Rectangle {
                    width: addText.implicitWidth + 24; height: 30; radius: 15
                    color: win.adding ? Theme.primaryContainer : "transparent"
                    border.width: 1; border.color: Theme.outlineVariant
                    Text { id: addText; anchors.centerIn: parent; text: "+ Add"; font.family: Theme.font; font.pixelSize: 11; color: win.adding ? Theme.fgContainer : Theme.textDim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.startAdd() }
                }
            }

            // ---- add ----
            Field { id: nameF; visible: win.adding; hint: "Name (e.g. pi, Bitwarden)" }
            Field { id: textF; visible: win.adding; mono: true; secret: true; hint: "What to memorize (digits, a password…)" }
            Connections { target: win.textIn; function onAccepted() { win.add(); } }
            RowLayout {
                visible: win.adding
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Kept in a file only you can read, so it can be shown again."; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Controls.Chip { label: "Start"; on: true; onClicked: win.add() }
            }

            // ---- practise ----
            ColumnLayout {
                visible: !win.adding && win.item !== null
                Layout.fillWidth: true
                spacing: 10

                // progress through the chunks
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: win.chunks
                        delegate: Rectangle {
                            required property int index
                            Layout.fillWidth: true
                            height: 6; radius: 3
                            color: win.item && index < win.item.learned ? Theme.primary : win.item && index === win.item.learned && win.learning ? Theme.yellow : Theme.surfaceHigh
                        }
                    }
                }
                Text {
                    text: !win.item ? "" : win.learning ? "Chunk " + (win.item.learned + 1) + " of " + win.chunks + "  ·  right " + (win.item.reps || 0) + " of " + win.need + " in a row  ·  " + win.item.text.length + " characters"
                        : win.item.done ? "Memorized  ·  " + win.item.text.length + " characters"
                        : "Recall " + Math.min(win.item.step + 1, win.steps.length + 1) + " of " + (win.steps.length + 1) + "  ·  " + win.when(win.item) + (win.item.streak > 0 ? "  ·  " + win.item.streak + " in a row" : "")
                    font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim
                }

                // what to study: everything so far with the new chunk bold, or all of it while shown
                Rectangle {
                    visible: win.studying || win.reveal || win.errChunk >= 0
                    Layout.fillWidth: true
                    implicitHeight: study.implicitHeight + 24
                    radius: 12
                    color: Theme.surfaceContainer
                    Text {
                        id: study
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                        wrapMode: Text.Wrap
                        textFormat: Text.StyledText
                        font.family: Theme.font; font.pixelSize: 20; font.letterSpacing: 1.5
                        color: Theme.textDim
                        text: {
                            if (!win.item) return "";
                            const g = win.groups(win.item.text, win.item.chunk);
                            if (win.reveal) return g.map(win.esc).join("  ");
                            // after a miss: the chunk that went wrong, the ones before it as dots
                            if (win.errChunk >= 0) return g.slice(0, win.errChunk + 1).map((c, i) => i === win.errChunk ? "<font color='" + Theme.text + "'><b>" + win.esc(c) + "</b></font>" : "•".repeat(c.length)).join("  ");
                            return g.slice(0, win.item.learned + 1).map((c, i) => i === win.item.learned ? "<font color='" + Theme.text + "'><b>" + win.esc(c) + "</b></font>" : win.esc(c)).join("  ");
                        }
                    }
                }

                Field {
                    id: answerF
                    visible: !win.studying && !(win.item && win.item.done)
                    mono: true
                    secret: true
                    hint: !win.item ? "" : win.learning ? "Type the first " + Math.min(win.item.text.length, (win.item.learned + 1) * win.item.chunk) + " from memory"
                        : win.item.due > win.now ? "Next recall in " + win.secs(win.item.due - win.now) + " (waiting helps; you can type now)" : "Type all of it from memory"
                }
                Connections { target: win.answer; function onAccepted() { win.check(); } }
                Item { id: studyKeys; Keys.onReturnPressed: win.check(); Keys.onEnterPressed: win.check(); Keys.onEscapePressed: win.close() }

                // where it went wrong
                Text {
                    visible: win.result === "wrong" && win.errAt >= 0
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.StyledText
                    font.family: Theme.font; font.pixelSize: 15; font.letterSpacing: 1.5
                    text: "<font color='" + Theme.green + "'>" + "•".repeat(win.errAt) + "</font><font color='" + Theme.error + "'><u>" + "•".repeat(Math.max(1, win.lastTry.length - win.errAt)) + "</u></font>"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: win.studying ? (win.result === "ok" ? "  Right. " : "") + "Study the bold chunk, then hide it and type everything so far."
                            : win.result === "ok" ? "  Right. Next recall in " + win.secs(win.item.due - win.now) + ": look away, keep it in your head."
                            : win.result === "again" ? "  Right (" + (win.item.reps || 0) + " of " + win.need + "). Again, from memory."
                            : win.result === "learned" ? "  All of it! Now recall it a few times, with growing gaps."
                            : win.result === "memorized" ? "  Memorized."
                            : win.result === "wrong" ? "  Went wrong at character " + (win.errAt + 1) + ". Look at the bold chunk, then type it all again."
                            : ""
                        font.family: Theme.font; font.pixelSize: 11
                        color: win.result === "ok" || win.result === "again" || win.result === "learned" || win.result === "memorized" ? Theme.green : win.result === "wrong" ? Theme.error : Theme.textDim
                    }
                    Controls.Chip { visible: !(win.item && win.item.done); label: win.studying ? "Hide and type" : "Check"; on: true; onClicked: win.check() }
                    Controls.Chip { visible: win.item !== null && win.item.done === true; label: "Practise again"; on: true; onClicked: win.again() }
                }

                // tools: show it, start over, remove; chunk size on its own row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Controls.Chip { label: win.reveal ? "\uf070  Hide" : "\uf06e  Show"; onClicked: win.reveal = !win.reveal }
                    Controls.Chip { label: win.showTyping ? "\uf070  Hide typing" : "\uf06e  Show typing"; on: win.showTyping; onClicked: { win.showTyping = !win.showTyping; win.focusNow(); } }
                    Controls.Chip { label: "Restart"; onClicked: win.relearn() }
                    Item { Layout.fillWidth: true }
                    Controls.Chip { label: "\uf1f8  Remove"; accent: Theme.error; onClicked: win.remove(win.cur) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: "Chunk size"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; Layout.rightMargin: 4 }
                    Repeater {
                        model: [3, 4, 5, 6, 8]
                        delegate: Controls.Chip {
                            required property int modelData
                            label: String(modelData)
                            on: win.item !== null && win.item.chunk === modelData
                            onClicked: win.setChunk(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
    property alias nameIn: nameF.input
    property alias textIn: textF.input
    property alias answer: answerF.input
}
