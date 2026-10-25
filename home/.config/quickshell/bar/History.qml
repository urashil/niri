import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Notification history drawer (bell in the bar).
PanelWindow {
    id: win
    visible: UiState.history
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-history"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.history ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onVisibleChanged: if (visible) UiState.unread = 0

    MouseArea { anchors.fill: parent; onClicked: UiState.history = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.history = false }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 56; rightMargin: 12 }
        width: 380
        height: Math.min(parent.height - 90, 120 + Math.min(UiState.notes.length, 6) * 92)
        radius: Theme.radius + 4
        color: Qt.alpha(Theme.surface, 0.985)
        border.width: 1
        border.color: Theme.outlineVariant

        MouseArea { anchors.fill: parent }

        RowLayout {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
            Text { text: "Notifications"; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text; Layout.fillWidth: true }
            Rectangle {
                width: dndText.implicitWidth + 24; height: 26; radius: 13
                color: UiState.dnd ? Theme.primaryContainer : Theme.surfaceHigh
                Text { id: dndText; anchors.centerIn: parent; text: (UiState.dnd ? " " : " ") + "DND"; font.family: Theme.font; font.pixelSize: 11; color: UiState.dnd ? Theme.fgContainer : Theme.textDim }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: UiState.dnd = !UiState.dnd }
            }
            Rectangle {
                width: clearText.implicitWidth + 24; height: 26; radius: 13
                color: Theme.surfaceHigh
                Text { id: clearText; anchors.centerIn: parent; text: "Clear"; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: UiState.clearNotes() }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: UiState.notes.length === 0
            text: "Nothing yet"
            font.family: Theme.font; font.pixelSize: 13; color: Theme.outline
        }

        ListView {
            anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            clip: true
            spacing: 8
            model: UiState.notes
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: body.implicitHeight + 24
                radius: 12
                color: Theme.surfaceContainer
                border.width: modelData.critical ? 1 : 0
                border.color: Theme.error
                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: modelData.app; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: modelData.time; font.family: Theme.font; font.pixelSize: 10; color: Theme.outline }
                    }
                    Text { Layout.fillWidth: true; text: modelData.summary; font.family: Theme.font; font.pixelSize: 13; font.bold: true; color: Theme.text; wrapMode: Text.Wrap }
                    Text { Layout.fillWidth: true; visible: text !== ""; text: modelData.body; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; textFormat: Text.PlainText }
                }
            }
        }
    }
}
