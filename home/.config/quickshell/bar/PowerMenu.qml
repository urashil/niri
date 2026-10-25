import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Mod+X. Keys: l lock, s suspend, e exit niri, r reboot, p power off, Esc cancel.
PanelWindow {
    id: win
    visible: UiState.power
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.35)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.power ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Process { id: run }
    function act(cmd) {
        UiState.power = false;
        run.command = ["sh", "-c", cmd];
        run.running = true;
    }
    BackgroundEffect.blurRegion: Region { item: backdrop }
    Item { id: backdrop; anchors.fill: parent }
    readonly property var items: [
        { icon: "", name: "Lock",     key: "l", cmd: "pidof swaylock || swaylock -f", color: Theme.blue },
        { icon: "", name: "Suspend",  key: "s", cmd: "systemctl suspend",             color: Theme.cyan },
        { icon: "", name: "Log out",  key: "e", cmd: "niri msg action quit --skip-confirmation", color: Theme.yellow },
        { icon: "", name: "Reboot",   key: "r", cmd: "systemctl reboot",              color: Theme.magenta },
        { icon: "", name: "Power off", key: "p", cmd: "systemctl poweroff",           color: Theme.red }
    ]

    MouseArea { anchors.fill: parent; onClicked: UiState.power = false }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { UiState.power = false; return; }
            for (const it of win.items) if (e.text === it.key) win.act(it.cmd);
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 18
        Repeater {
            model: win.items
            delegate: Rectangle {
                id: btn
                required property var modelData
                width: 120; height: 130; radius: 22
                color: hover.containsMouse ? Theme.surfaceHigh : Qt.alpha(Theme.surface, 0.95)
                border.width: 2
                border.color: hover.containsMouse ? modelData.color : Theme.outlineVariant
                scale: hover.containsMouse ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: btn.modelData.icon
                        font.family: Theme.font; font.pixelSize: 34
                        color: btn.modelData.color
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: btn.modelData.name
                        font.family: Theme.font; font.pixelSize: 13; color: Theme.text
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: btn.modelData.key.toUpperCase()
                        font.family: Theme.font; font.pixelSize: 10; color: Theme.outline
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.act(btn.modelData.cmd)
                }
            }
        }
    }
}
