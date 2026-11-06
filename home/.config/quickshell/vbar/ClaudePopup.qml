import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Claude usage card (button in the bar): 5 hour limit, weekly limit, all-time totals.
PanelWindow {
    id: win
    visible: UiState.claude
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-claude"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.claude ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 4 }
    onVisibleChanged: if (visible) { ClaudeUsage.refresh(); ClaudeUsage.listSessions(); }

    // Hover-opened: only the card catches the pointer, so the bar keeps its hover (no open/close flicker).
    // Click-opened: the whole screen catches, so a click outside closes it.
    readonly property bool hoverMode: UiState.hoverPopout === "claude"
    mask: Region { item: win.hoverMode ? card : clickCatcher }

    MouseArea { id: clickCatcher; anchors.fill: parent; onClicked: UiState.claude = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.claude = false }

    component Meter: ColumnLayout {
        id: m
        property string title
        property real pct
        property string reset
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text { text: m.title; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text }
            Item { Layout.fillWidth: true }
            Text { text: Math.round(m.pct) + "%"; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: m.pct >= 90 ? Theme.error : m.pct >= 70 ? Theme.yellow : Theme.primary }
        }
        Rectangle {
            Layout.fillWidth: true; height: 8; radius: 4; color: Theme.surfaceHigh
            Rectangle {
                height: parent.height; radius: 4
                width: parent.width * Math.min(1, m.pct / 100)
                color: m.pct >= 90 ? Theme.error : m.pct >= 70 ? Theme.yellow : Theme.primary
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
        Text { visible: m.reset !== ""; text: "resets in " + ClaudeUsage.until(m.reset); font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
    }

    Rectangle {
        id: card
        x: 54
        y: Math.min(win.height - height - 12, Math.max(12, UiState.claudeCenter - height / 2))
        width: 300
        height: col.implicitHeight + 32
        radius: Theme.radius + 4
        color: Qt.alpha(Theme.surface, 0.82)
        border.width: 1
        border.color: Theme.outlineVariant
        MouseArea { anchors.fill: parent }
        HoverHandler { onHoveredChanged: hovered ? UiState.hoverKeep() : UiState.hoverRelease() }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Claude usage"; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text }
                Item { Layout.fillWidth: true }
                Text { text: ClaudeUsage.plan; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
            }

            Text {
                visible: ClaudeUsage.error !== "" && !ClaudeUsage.loaded
                text: "Couldn't load limits: " + ClaudeUsage.error
                wrapMode: Text.Wrap; Layout.fillWidth: true
                font.family: Theme.font; font.pixelSize: 11; color: Theme.error
            }
            Meter { visible: ClaudeUsage.loaded && ClaudeUsage.accounts.length === 0; title: "5 hour limit"; pct: ClaudeUsage.session; reset: ClaudeUsage.sessionReset }
            Meter { visible: ClaudeUsage.loaded && ClaudeUsage.accounts.length === 0; title: "Weekly limit"; pct: ClaudeUsage.weekly; reset: ClaudeUsage.weeklyReset }

            // several accounts (claude-account): each one's limits; click one to switch to it
            Repeater {
                model: ClaudeUsage.accounts
                delegate: Rectangle {
                    id: arow
                    required property var modelData
                    readonly property var f: modelData.five_hour || {}
                    readonly property var w: modelData.seven_day || {}
                    Layout.fillWidth: true
                    implicitHeight: acol.implicitHeight + 20
                    radius: 10
                    color: modelData.active ? Qt.alpha(Theme.primary, 0.12) : ahov.hovered ? Theme.surfaceHigh : Theme.surfaceContainer
                    border.width: modelData.active ? 1 : 0
                    border.color: Qt.alpha(Theme.primary, 0.5)
                    HoverHandler { id: ahov; cursorShape: arow.modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    TapHandler { onTapped: if (!arow.modelData.active) ClaudeUsage.use(arow.modelData.name) }
                    ColumnLayout {
                        id: acol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: arow.modelData.name; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: arow.modelData.active ? Theme.primary : Theme.text }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: arow.modelData.email || ""; font.family: Theme.font; font.pixelSize: 9; color: Theme.textDim }
                            Text { text: arow.modelData.active ? "in use" : "switch"; font.family: Theme.font; font.pixelSize: 9; font.bold: arow.modelData.active; color: arow.modelData.active ? Theme.primary : Theme.outline }
                        }
                        Meter { title: "5 hour"; pct: arow.f.used || 0; reset: (arow.f.used || 0) > 0 && arow.f.resets ? arow.f.resets : "" }
                        Meter { title: "Weekly"; pct: arow.w.used || 0; reset: (arow.w.used || 0) > 0 && arow.w.resets ? arow.w.resets : "" }
                    }
                }
            }
            Text {
                visible: ClaudeUsage.accounts.length > 0
                text: ClaudeUsage.auto ? "Switches by itself when the one in use hits a limit." : "Auto switching is off (claude-account auto on)."
                font.family: Theme.font; font.pixelSize: 9; color: Theme.outline
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outlineVariant }

            // live Claude Code sessions (hooks): click to jump to the terminal
            Text { visible: ClaudeUsage.sessions.length > 0; text: "Sessions"; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text }
            Repeater {
                model: ClaudeUsage.sessions
                delegate: Rectangle {
                    id: srow
                    required property var modelData
                    readonly property color tint: modelData.state === "waiting" ? Theme.yellow : modelData.state === "working" ? Theme.primary : Theme.outline
                    Layout.fillWidth: true
                    implicitHeight: 40; radius: 10
                    color: hov.hovered ? Theme.surfaceHigh : Theme.surfaceContainer
                    HoverHandler { id: hov; cursorShape: srow.modelData.window ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    Rectangle {
                        id: dot
                        width: 8; height: 8; radius: 4; color: srow.tint
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        SequentialAnimation on opacity { running: srow.modelData.state === "working"; loops: Animation.Infinite; NumberAnimation { to: 0.3; duration: 600 } NumberAnimation { to: 1; duration: 600 } }
                    }
                    Column {
                        anchors { left: dot.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: srow.modelData.project + "  ·  " + (srow.modelData.state === "waiting" ? "needs you" : srow.modelData.state === "working" ? "working" : srow.modelData.state === "done" ? "done" : "idle")
                            font.family: Theme.font; font.pixelSize: 11; font.bold: true; color: Theme.text
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight; visible: text !== ""
                            text: srow.modelData.state === "waiting" ? srow.modelData.msg : (srow.modelData.prompt || "")
                            font.family: Theme.font; font.pixelSize: 9; color: Theme.textDim
                        }
                    }
                    TapHandler {
                        onTapped: if (srow.modelData.window) { Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(srow.modelData.window)]); UiState.claude = false; }
                    }
                }
            }
            Rectangle { visible: ClaudeUsage.sessions.length > 0; Layout.fillWidth: true; height: 1; color: Theme.outlineVariant }

            Text { text: "All time"; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text }
            GridLayout {
                Layout.fillWidth: true
                columns: 2; columnSpacing: 12; rowSpacing: 4
                Repeater {
                    model: [
                        ["Output", ClaudeUsage.tokens(ClaudeUsage.all.out)],
                        ["Input", ClaudeUsage.tokens(ClaudeUsage.all.in)],
                        ["Cache read", ClaudeUsage.tokens(ClaudeUsage.all.cr)],
                        ["Cache write", ClaudeUsage.tokens(ClaudeUsage.all.cc)],
                        ["Replies", ClaudeUsage.all.msgs.toLocaleString(Qt.locale(), "f", 0)],
                        ["Sessions", String(ClaudeUsage.all.sessions)]
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.columnSpan: 2
                        Text { text: modelData[0]; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
                        Item { Layout.fillWidth: true }
                        Text { text: modelData[1]; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                    }
                }
            }
            Text { text: "Totals are from this machine's transcripts."; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline }
        }
    }
}
