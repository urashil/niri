import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Mod+Shift+E: "log out?" in the rice's own style instead of niri's dialog.
// Enter / E / Mod+Shift+E again logs out, Esc or a click outside cancels.
PanelWindow {
    id: win
    visible: UiState.quitAsk
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.35)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-quit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.quitAsk ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: backdrop }
    Item { id: backdrop; anchors.fill: parent }

    function quit() { UiState.quitAsk = false; Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]); }
    function cancel() { UiState.quitAsk = false; }

    // how many windows the logout would close
    property int windows: -1
    Process {
        id: count
        command: ["sh", "-c", "niri msg --json windows | jq length"]
        stdout: StdioCollector { onStreamFinished: win.windows = parseInt(text) }
    }
    onVisibleChanged: if (visible) { windows = -1; count.running = true; }

    MouseArea { anchors.fill: parent; onClicked: win.cancel() }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape || e.text === "n") win.cancel();
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.text === "e" || e.text === "y") win.quit();
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 340; height: col.implicitHeight + 44; radius: 22
        color: Qt.alpha(Theme.surface, 0.96)
        border.width: 2; border.color: Theme.outlineVariant
        scale: win.visible ? 1 : 0.92
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        MouseArea { anchors.fill: parent }       // clicks on the card do not cancel

        Column {
            id: col
            anchors.centerIn: parent
            width: parent.width - 44
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ""; font.family: Theme.font; font.pixelSize: 34; color: Theme.yellow
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Log out?"; font.family: Theme.font; font.pixelSize: 17; font.bold: true; color: Theme.text
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: win.windows > 0 ? "Ends the niri session and closes " + win.windows + (win.windows === 1 ? " window." : " windows.")
                                      : "Ends the niri session."
                font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: [
                        { label: "Cancel", key: "Esc", accent: Theme.outline, go: false },
                        { label: "Log out", key: "Enter", accent: Theme.yellow, go: true }
                    ]
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        width: 128; height: 40; radius: 12
                        color: hover.containsMouse ? Theme.surfaceHigh : "transparent"
                        border.width: 1.5
                        border.color: hover.containsMouse || modelData.go ? modelData.accent : Theme.outlineVariant
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: btn.modelData.label; font.family: Theme.font; font.pixelSize: 12; color: btn.modelData.go ? btn.modelData.accent : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: btn.modelData.key; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btn.modelData.go ? win.quit() : win.cancel()
                        }
                    }
                }
            }
        }
    }
}
