import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Password practice (launcher "memorize", Mod+Alt+P): type a password from memory, checked against a scrypt hash
// (~/.local/bin/pw-drill; the password is only ever piped to it, never stored). Spaced repetition; the island
// says when one is due.
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

    readonly property string tool: Quickshell.env("HOME") + "/.local/bin/pw-drill"
    property var entries: []
    property string current: ""          // entry being practised
    property bool adding: false
    property string result: ""           // "ok" | "wrong" | "mismatch" | "added"
    property bool working: false
    property int dueCount: 0
    property string lastNudge: ""

    function close() { UiState.drill = false; }
    function refresh() { lister.running = true; }
    function pick(name) { current = name; adding = false; result = ""; pw.text = ""; pw.forceActiveFocus(); }
    function startAdd() { adding = true; current = ""; result = ""; nameIn.text = ""; pw.text = ""; pw2.text = ""; nameIn.forceActiveFocus(); }
    function due(e) { return e.due * 1000 <= Date.now(); }
    function when(e) {
        const s = Math.round((e.due * 1000 - Date.now()) / 1000);
        if (s <= 0) return "due now";
        const h = Math.round(s / 3600);
        return h < 24 ? "in " + Math.max(1, h) + "h" : "in " + Math.round(h / 24) + "d";
    }
    function submit() {
        if (working) return;
        if (adding) {
            if (nameIn.text.trim() === "" || pw.text === "") return;
            working = true;
            runner.command = [tool, "add", nameIn.text.trim()];
            runner.pending = pw.text + "\n" + pw2.text + "\n";
        } else {
            if (current === "" || pw.text === "") return;
            working = true;
            runner.command = [tool, "check", current];
            runner.pending = pw.text + "\n";
        }
        pw.text = ""; pw2.text = "";
        runner.running = true;
    }

    onVisibleChanged: {
        if (!visible) { pw.text = ""; pw2.text = ""; return; }
        result = ""; refresh();
    }

    Process {
        id: lister
        command: [win.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.entries = JSON.parse(text); } catch (e) { win.entries = []; }
                win.dueCount = win.entries.filter(e => win.due(e)).length;
                if (win.visible && win.current === "" && !win.adding) {
                    if (win.entries.length === 0) win.startAdd();
                    else win.pick((win.entries.find(e => win.due(e)) || win.entries[0]).name);
                }
            }
        }
    }
    Process {
        id: runner
        property string pending: ""
        stdinEnabled: true
        onStarted: { write(pending); pending = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                win.working = false;
                win.result = text.trim();
                if (win.result === "added") { win.current = nameIn.text.trim(); win.adding = false; win.result = "added"; }
                win.refresh();
                pw.forceActiveFocus();
            }
        }
    }

    // nudge in the island when something is due (at most once every few hours)
    Timer {
        interval: 30 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: lister.running = true
    }
    onDueCountChanged: {
        const stamp = new Date().toDateString() + Math.floor(new Date().getHours() / 4);
        if (dueCount > 0 && !visible && stamp !== lastNudge) {
            lastNudge = stamp;
            UiState.pulse("drill", "", dueCount === 1 ? "A password to practise" : dueCount + " passwords to practise", -1, Theme.primary, 6000);
        }
    }

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
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
                Text { text: win.adding ? "Add a password to practise" : "Practise from memory"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                Text {
                    text: ""; font.family: Theme.font; font.pixelSize: 13; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                }
            }

            // the list: click one to practise it, right-click to remove
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: win.entries.length > 0
                Repeater {
                    model: win.entries
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: !win.adding && win.current === modelData.name
                        width: chipText.implicitWidth + 24; height: 30; radius: 15
                        color: sel ? Theme.primaryContainer : Theme.surfaceContainer
                        border.width: win.due(modelData) ? 1 : 0
                        border.color: Theme.primary
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: parent.modelData.name + "  ·  " + win.when(parent.modelData) + (parent.modelData.streak > 0 ? "  ·  " + parent.modelData.streak + "" : "")
                            font.family: Theme.font; font.pixelSize: 11
                            color: parent.sel ? Theme.fgContainer : Theme.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: m => {
                                if (m.button === Qt.RightButton) { Quickshell.execDetached([win.tool, "remove", parent.modelData.name]); if (win.current === parent.modelData.name) win.current = ""; delay.restart(); }
                                else win.pick(parent.modelData.name);
                            }
                        }
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
            Timer { id: delay; interval: 300; onTriggered: win.refresh() }

            component Field: Rectangle {
                property alias input: ti
                property string hint
                property bool secret: true
                Layout.fillWidth: true
                height: 42; radius: 12
                color: Theme.surfaceHigh
                border.width: ti.activeFocus ? 1 : 0
                border.color: Theme.primary
                TextInput {
                    id: ti
                    activeFocusOnTab: true
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: parent.secret ? TextInput.Password : TextInput.Normal
                    passwordCharacter: "•"
                    inputMethodHints: parent.secret ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText : Qt.ImhNone
                    font.family: Theme.font; font.pixelSize: 14
                    color: Theme.text
                    selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
                    Keys.onEscapePressed: win.close()
                    Keys.onReturnPressed: win.submit()
                    Keys.onEnterPressed: win.submit()
                    Text { visible: !ti.text; text: parent.parent.hint; font.family: Theme.font; font.pixelSize: 13; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            Field { id: nameF; visible: win.adding; secret: false; hint: "Name (e.g. laptop disk, Bitwarden)" }
            Field { id: pwF; hint: win.adding ? "Password" : win.current ? "Type “" + win.current + "” from memory" : "Pick one above" }
            Field { id: pw2F; visible: win.adding; hint: "Once more" }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: win.working ? "Checking…"
                        : win.result === "ok" ? "  Correct. Next time " + (win.entries.find(e => e.name === win.current) ? win.when(win.entries.find(e => e.name === win.current)) : "later")
                        : win.result === "wrong" ? "  Not quite. Try again."
                        : win.result === "mismatch" ? "The two didn't match."
                        : win.result === "added" ? "Saved. Now type it once from memory."
                        : win.adding ? "Only a scrypt hash is saved; the password itself never is."
                        : ""
                    font.family: Theme.font; font.pixelSize: 11
                    color: win.result === "ok" || win.result === "added" ? Theme.green : win.result === "wrong" || win.result === "mismatch" ? Theme.error : Theme.textDim
                }
                Rectangle {
                    width: goText.implicitWidth + 28; height: 34; radius: 17
                    color: Theme.primary
                    Text { id: goText; anchors.centerIn: parent; text: win.adding ? "Save" : "Check"; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.fgPrimary }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.submit() }
                }
            }
        }
    }
    property alias nameIn: nameF.input
    property alias pw: pwF.input
    property alias pw2: pw2F.input
}
