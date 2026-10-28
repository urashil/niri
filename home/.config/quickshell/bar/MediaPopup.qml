import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Now-playing card (click the island while a player is going): opens under the CPU/RAM chip.
PanelWindow {
    id: win
    visible: UiState.media
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-media"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.media ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 4 }
    readonly property var p: Song.mprisPlayer || (Mpris.players.values.length > 0 ? Mpris.players.values[0] : null)

    MouseArea { anchors.fill: parent; onClicked: UiState.media = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.media = false }

    // keep the progress bar moving while open
    Timer { interval: 1000; running: win.visible && win.p && win.p.isPlaying; repeat: true; onTriggered: if (win.p) win.p.positionChanged() }

    Rectangle {
        id: card
        x: Math.max(8, Math.min(win.width - width - 8, UiState.statsCenter - width / 2))
        y: 56
        width: 340
        height: col.implicitHeight + 32
        radius: Theme.radius + 4
        color: Qt.alpha(Theme.surface, 0.82)
        border.width: 1
        border.color: Theme.outlineVariant
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 200; height: 200; radius: 16
                color: Theme.surfaceHigh
                clip: true
                Image {
                    anchors.fill: parent
                    source: win.p && win.p.trackArtUrl ? win.p.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text { anchors.centerIn: parent; visible: !win.p || !win.p.trackArtUrl; text: ""; font.family: Theme.font; font.pixelSize: 54; color: Theme.outline }
            }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: win.p ? win.p.trackTitle : "Nothing playing"; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: win.p ? win.p.trackArtist : ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim }

            Rectangle {
                Layout.fillWidth: true; height: 6; radius: 3; color: Theme.surfaceHigh
                visible: win.p && win.p.lengthSupported && win.p.length > 0
                Rectangle {
                    height: parent.height; radius: 3; color: Theme.tertiary
                    width: win.p && win.p.length > 0 ? parent.width * Math.min(1, win.p.position / win.p.length) : 0
                }
                MouseArea {
                    anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: m => { if (win.p && win.p.canSeek) win.p.position = win.p.length * (m.x / width); }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 26
                Text { text: ""; font.family: Theme.font; font.pixelSize: 20; color: Theme.text; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.previous() } }
                Text { text: win.p && win.p.isPlaying ? "" : ""; font.family: Theme.font; font.pixelSize: 26; color: Theme.primary; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.togglePlaying() } }
                Text { text: ""; font.family: Theme.font; font.pixelSize: 20; color: Theme.text; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.next() } }
            }
        }
    }
}
