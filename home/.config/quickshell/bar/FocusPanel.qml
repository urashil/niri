import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Timer + todo popout under the island (Mod+Alt+T, or click the timer / todo chip in the island).
PanelWindow {
    id: win
    visible: UiState.focusOpen
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-focus"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.focusOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 6 }

    readonly property string tab: UiState.focusTab
    onVisibleChanged: if (visible) { if (tab === "todo") todoIn.forceActiveFocus(); else customIn.forceActiveFocus(); }
    onTabChanged: if (visible) { if (tab === "todo") todoIn.forceActiveFocus(); }

    MouseArea { anchors.fill: parent; onClicked: UiState.focusOpen = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.focusOpen = false }

    component Btn: Rectangle {
        id: b
        property string label
        property color accent: Theme.primary
        property bool strong: false
        signal clicked()
        height: 32; radius: 16; width: bl.implicitWidth + 30
        color: strong ? accent : Theme.surfaceHigh
        Text { id: bl; anchors.centerIn: parent; text: b.label; font.family: Theme.font; font.pixelSize: 12; font.bold: b.strong; color: b.strong ? Theme.fgPrimary : Theme.text }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    Rectangle {
        id: card
        anchors { top: parent.top; topMargin: 56; horizontalCenter: parent.horizontalCenter }
        width: 400
        height: body.implicitHeight + 36
        radius: Theme.radius + 6
        color: Qt.alpha(Theme.surface, 0.86)
        border.width: 1
        border.color: Theme.outlineVariant
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 12

            // ============ timer ============
            ColumnLayout {
                visible: win.tab === "timer"
                Layout.fillWidth: true
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Focus.active ? Focus.clockText : "00:00"
                    font.family: Theme.font; font.pixelSize: 52; font.bold: true
                    color: !Focus.active ? Theme.outline : Focus.paused ? Theme.textDim : Focus.urgent ? Theme.red : Theme.text
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: Focus.active
                    text: (Focus.mode === "pomodoro" ? (Focus.phase === "work" ? "Focus" : "Break") + "  ·  " + Focus.cycles + " done" : Focus.mode === "stopwatch" ? "Stopwatch" : "Countdown") + (Focus.paused ? "  ·  paused" : "")
                    font.family: Theme.font; font.pixelSize: 12; color: Theme.primary
                }
                Rectangle {
                    visible: Focus.active && Focus.mode !== "stopwatch"
                    Layout.fillWidth: true; height: 6; radius: 3; color: Theme.surfaceHigh
                    Rectangle { width: parent.width * Focus.fraction; height: parent.height; radius: 3; color: Focus.mode === "pomodoro" && Focus.phase === "break" ? Theme.green : Theme.primary; Behavior on width { NumberAnimation { duration: 400 } } }
                }

                // running controls
                RowLayout {
                    visible: Focus.active
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    Btn { label: Focus.paused ? "  Resume" : "  Pause"; strong: true; onClicked: Focus.toggle() }
                    Btn { label: "  Stop"; accent: Theme.red; onClicked: Focus.stop() }
                    Btn { visible: Focus.mode === "pomodoro"; label: "  Skip"; onClicked: Focus.skip() }
                }

                // start something
                ColumnLayout {
                    visible: !Focus.active
                    Layout.fillWidth: true
                    spacing: 10
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: [5, 10, 15, 25, 45, 60]
                            delegate: Rectangle {
                                required property int modelData
                                height: 32; radius: 16; width: pl.implicitWidth + 26
                                color: Theme.surfaceHigh
                                Text { id: pl; anchors.centerIn: parent; text: parent.modelData + " min"; font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Focus.start(parent.modelData) }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Rectangle {
                            Layout.fillWidth: true; height: 32; radius: 10; color: Theme.surfaceHigh
                            TextInput {
                                id: customIn
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                                selectionColor: Theme.primary
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 1; top: 999 }
                                onAccepted: if (text) { Focus.start(parseInt(text)); text = ""; }
                                Text { visible: !customIn.text; text: "custom minutes, Enter to start"; color: Theme.outline; font: customIn.font; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        Btn { label: "Start"; strong: true; onClicked: if (customIn.text) { Focus.start(parseInt(customIn.text)); customIn.text = ""; } }
                    }
                    RowLayout {
                        spacing: 8
                        Btn { label: "  Pomodoro  " + Focus.workMin + "/" + Focus.breakMin; accent: Theme.red; onClicked: Focus.startPomodoro() }
                        Btn { label: "  Stopwatch"; onClicked: Focus.startStopwatch() }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    height: 28; radius: 14; width: bt1.implicitWidth + 26; color: Theme.surfaceHigh
                    Text { id: bt1; anchors.centerIn: parent; text: "\uf053  Tasks"; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: UiState.focusTab = "todo" }
                }
            }

            // ============ todo ============
            ColumnLayout {
                visible: win.tab === "todo"
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 10; color: Theme.surfaceHigh
                        TextInput {
                            id: todoIn
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                            selectionColor: Theme.primary
                            onAccepted: { Focus.addTodo(text); text = ""; }
                            Text { visible: !todoIn.text; text: "add a task, Enter"; color: Theme.outline; font: todoIn.font; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Btn { label: "Add"; strong: true; onClicked: { Focus.addTodo(todoIn.text); todoIn.text = ""; } }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 280)
                    clip: true; spacing: 4
                    model: Focus.todos
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width; height: 36; radius: 10
                        color: hov.containsMouse ? Theme.surfaceContainer : "transparent"
                        Text { id: box; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } text: row.modelData.done ? "" : ""; font.family: Theme.font; font.pixelSize: 15; color: row.modelData.done ? Theme.green : Theme.primary }
                        Text {
                            anchors { left: box.right; leftMargin: 12; right: del.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: row.modelData.text; elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 12; font.strikeout: row.modelData.done
                            color: row.modelData.done ? Theme.outline : Theme.text
                        }
                        Text {
                            id: del
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            visible: hov.containsMouse
                            text: ""; font.family: Theme.font; font.pixelSize: 13; color: Theme.error
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: Focus.removeTodo(row.index) }
                        }
                        MouseArea { id: hov; anchors.fill: parent; z: -1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Focus.toggleTodo(row.index) }
                    }
                }
                Text { visible: Focus.todos.length === 0; Layout.alignment: Qt.AlignHCenter; text: "Nothing to do"; font.family: Theme.font; font.pixelSize: 12; color: Theme.outline }
                RowLayout {
                    visible: Focus.todos.length > 0
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: Focus.openCount + " open · " + (Focus.todos.length - Focus.openCount) + " done"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                    Btn { visible: Focus.todos.length - Focus.openCount > 0; label: "Clear done"; onClicked: Focus.clearDone() }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    height: 28; radius: 14; width: bt2.implicitWidth + 26; color: Theme.surfaceHigh
                    Text { id: bt2; anchors.centerIn: parent; text: "\uf252  Timer / Stopwatch" + (Focus.active ? "  ·  " + Focus.clockText : "") + "  \uf054"; font.family: Theme.font; font.pixelSize: 11; color: Focus.active ? Theme.primary : Theme.textDim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: UiState.focusTab = "timer" }
                }
            }
        }
    }
}
