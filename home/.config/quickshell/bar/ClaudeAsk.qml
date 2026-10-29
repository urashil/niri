import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Ask Claude (launcher "? question", Mod+Alt+A) and explain a screenshot (Mod+Alt+S): a card that streams the answer
// from `claude -p`; follow-ups continue the same conversation. Runs in ~/.cache/rice/claude-ask, without tools
// (only Read, for the screenshot).
PanelWindow {
    id: win
    visible: UiState.ask
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.25)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-ask"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.ask ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 8 }

    readonly property string dir: Quickshell.env("HOME") + "/.cache/rice/claude-ask"
    property var turns: []              // [{ q, image, a }]
    property string session: ""
    property bool busy: false
    property string error: ""

    function close() { UiState.ask = false; }
    function reset() { proc.running = false; turns = []; session = ""; error = ""; busy = false; }

    // UiState.askRequest() fills these; a new request starts a new conversation
    Connections {
        target: UiState
        function onAskRequested(q, image) { win.reset(); win.send(q, image); }
    }
    onVisibleChanged: if (visible) input.forceActiveFocus(); else proc.running = false

    function send(q, image) {
        q = (q || "").trim();
        if (busy || (!q && !image)) return;
        if (image && !q) q = "Explain what's in this screenshot. If it shows an error or a problem, say what it means and how to fix it.";
        turns = turns.concat([{ q: q, image: image || "", a: "" }]);
        error = "";
        busy = true;
        const prompt = image ? q + "\n\nThe screenshot is " + image : q;
        const cmd = ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                     "--append-system-prompt", "You are answering in a small popup on the user's Linux desktop (Arch, niri). Be direct and brief; use short Markdown."];
        if (image) cmd.push("--tools", "Read", "--allowedTools", "Read", "--add-dir", image.replace(/\/[^/]*$/, ""));
        else cmd.push("--tools", "");
        if (session) cmd.push("--resume", session);
        proc.command = ["sh", "-c", "mkdir -p \"$0\" && cd \"$0\" && exec \"$@\"", dir].concat(cmd);
        proc.running = true;
    }
    function append(t) {
        const l = turns.slice();
        l[l.length - 1] = Object.assign({}, l[l.length - 1], { a: l[l.length - 1].a + t });
        turns = l;
        scroller.follow();
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d.session_id) win.session = d.session_id;
                if (d.type === "stream_event" && d.event.type === "content_block_delta" && d.event.delta.type === "text_delta") win.append(d.event.delta.text);
                // a new text block after a tool call: keep it apart from the last one
                else if (d.type === "stream_event" && d.event.type === "content_block_start" && d.event.content_block.type === "text" && win.turns.length && win.turns[win.turns.length - 1].a !== "") win.append("\n\n");
                else if (d.type === "result" && d.is_error) win.error = d.result || "Claude returned an error";
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "" && win.turns.length && win.turns[win.turns.length - 1].a === "") win.error = text.trim().split("\n").slice(-1)[0] }
        onExited: code => { win.busy = false; if (code !== 0 && win.error === "" && win.turns.length && win.turns[win.turns.length - 1].a === "") win.error = "claude exited with " + code; }
    }

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.12
        width: 680
        height: Math.min(parent.height * 0.76, col.implicitHeight + 32)
        radius: Theme.radius + 8
        color: Qt.alpha(Theme.surface, 0.9)
        border.width: 1
        border.color: Theme.outlineVariant
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text { text: ""; font.family: Theme.font; font.pixelSize: 16; color: Theme.primary }
                Text { text: "Claude"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                Text {
                    visible: win.turns.length > 0 && !win.busy
                    text: "  Copy"; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["wl-copy", win.turns[win.turns.length - 1].a]) }
                }
                Text {
                    text: ""; font.family: Theme.font; font.pixelSize: 13; color: Theme.textDim; Layout.leftMargin: 10
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                }
            }

            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: convo.implicitHeight
                Layout.maximumHeight: convo.implicitHeight
                contentHeight: convo.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                property bool pinned: true
                onMovementEnded: pinned = contentY >= contentHeight - height - 20
                function follow() { if (pinned) Qt.callLater(() => contentY = Math.max(0, contentHeight - height)); }

                ColumnLayout {
                    id: convo
                    width: scroller.width
                    spacing: 12
                    Repeater {
                        model: win.turns
                        delegate: ColumnLayout {
                            id: turn
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: qcol.implicitHeight + 16
                                radius: 12
                                color: Theme.surfaceContainer
                                ColumnLayout {
                                    id: qcol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; leftMargin: 12; rightMargin: 12 }
                                    Image {
                                        visible: turn.modelData.image !== ""
                                        source: turn.modelData.image ? "file://" + turn.modelData.image : ""
                                        Layout.maximumWidth: 300; Layout.maximumHeight: 160
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Text { Layout.fillWidth: true; text: turn.modelData.q; wrapMode: Text.Wrap; textFormat: Text.PlainText; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim }
                                }
                            }
                            TextEdit {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: turn.modelData.a
                                textFormat: TextEdit.MarkdownText
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                font.family: Theme.font; font.pixelSize: 13
                                color: Theme.text
                                selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
                                onLinkActivated: link => Quickshell.execDetached(["xdg-open", link])
                            }
                            Text {
                                visible: win.busy && turn.index === win.turns.length - 1 && turn.modelData.a === ""
                                text: "Thinking…"; font.family: Theme.font; font.pixelSize: 12; color: Theme.outline
                                SequentialAnimation on opacity { running: parent.visible; loops: Animation.Infinite; NumberAnimation { to: 0.3; duration: 600 } NumberAnimation { to: 1; duration: 600 } }
                            }
                        }
                    }
                    Text { visible: win.error !== ""; Layout.fillWidth: true; text: win.error; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 11; color: Theme.error }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40; radius: 12
                color: Theme.surfaceContainer
                border.width: input.activeFocus ? 1 : 0
                border.color: Theme.primary
                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font; font.pixelSize: 13
                    color: Theme.text
                    selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
                    Keys.onEscapePressed: win.close()
                    Keys.onReturnPressed: { win.send(text, ""); text = ""; }
                    Keys.onEnterPressed: { win.send(text, ""); text = ""; }
                    Text { visible: !input.text; text: win.busy ? "Answering…" : win.turns.length ? "Follow up…" : "Ask anything…"; font: input.font; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
}
