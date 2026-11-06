import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Now-playing card (click the island while a player is going): opens centered under the island.
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
    readonly property var p: Song.shownMpris || (Mpris.players.values.length > 0 ? Mpris.players.values[0] : null)

    MouseArea { anchors.fill: parent; onClicked: UiState.media = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.media = false }

    // keep the progress bar moving while open
    Timer { interval: 500; running: win.visible && win.p && win.p.isPlaying; repeat: true; onTriggered: if (win.p) win.p.positionChanged() }

    Rectangle {
        id: card
        x: (win.width - width) / 2
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
                Text { anchors.centerIn: parent; visible: !win.p || !win.p.trackArtUrl; text: "\uf001"; font.family: Theme.font; font.pixelSize: 54; color: Theme.outline }
            }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: win.p ? win.p.trackTitle : "Nothing playing"; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: win.p ? win.p.trackArtist : ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim }
            Text { Layout.fillWidth: true; visible: text !== ""; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: win.p ? win.p.trackAlbum : ""; font.family: Theme.font; font.pixelSize: 10; color: Theme.outline }

            // progress: click or drag to seek
            Item {
                Layout.fillWidth: true; height: 14
                visible: win.p && win.p.lengthSupported && win.p.length > 0
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Theme.surfaceHigh }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; height: 6; radius: 3; color: Theme.tertiary
                    width: win.p && win.p.length > 0 ? parent.width * Math.min(1, win.p.position / win.p.length) : 0
                }
                MouseArea {
                    anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                    cursorShape: Qt.PointingHandCursor
                    onPressed: m => { if (win.p && win.p.canSeek) win.p.position = win.p.length * (m.x / width); }
                    onPositionChanged: m => { if (pressed && win.p && win.p.canSeek) win.p.position = win.p.length * Math.max(0, Math.min(1, m.x / width)); }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: win.p && win.p.lengthSupported && win.p.length > 0
                Text { text: win.p ? Song.clock(win.p.position) : ""; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Item { Layout.fillWidth: true }
                Text { text: win.p ? Song.clock(win.p.length) : ""; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
            }

            // transport: shuffle, previous, play/pause, next, repeat
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 22
                Text {
                    visible: win.p && win.p.shuffleSupported
                    text: "\uf074"; font.family: Theme.font; font.pixelSize: 15
                    color: win.p && win.p.shuffle ? Theme.primary : Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.shuffle = !win.p.shuffle }
                }
                Text { text: "\uf048"; font.family: Theme.font; font.pixelSize: 18; color: Theme.text; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.previous() } }
                Text { text: win.p && win.p.isPlaying ? "\uf04c" : "\uf04b"; font.family: Theme.font; font.pixelSize: 26; color: Theme.primary; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.togglePlaying() } }
                Text { text: "\uf051"; font.family: Theme.font; font.pixelSize: 18; color: Theme.text; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.next() } }
                Text {
                    visible: win.p && win.p.loopSupported
                    text: "\uf01e"; font.family: Theme.font; font.pixelSize: 15
                    color: win.p && win.p.loopState !== MprisLoopState.None ? Theme.primary : Theme.textDim
                    // a dot marks "repeat one"
                    Rectangle { visible: win.p && win.p.loopState === MprisLoopState.Track; width: 5; height: 5; radius: 3; color: Theme.primary; anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 1 } }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                        onClicked: if (win.p) win.p.loopState = win.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist : win.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                    }
                }
            }

            // volume and the player itself
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    visible: win.p && win.p.volumeSupported
                    text: win.p && win.p.volume === 0 ? "\uf026" : "\uf028"; font.family: Theme.font; font.pixelSize: 13; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.volume = win.p.volume === 0 ? 0.6 : 0 }
                }
                Item {
                    visible: win.p && win.p.volumeSupported
                    Layout.fillWidth: true; height: 14
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.surfaceHigh }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: win.p ? parent.width * Math.min(1, win.p.volume) : 0; height: 4; radius: 2; color: Theme.textDim }
                    MouseArea {
                        anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                        cursorShape: Qt.PointingHandCursor
                        onPressed: m => { if (win.p) win.p.volume = Math.max(0, Math.min(1, m.x / width)); }
                        onPositionChanged: m => { if (pressed && win.p) win.p.volume = Math.max(0, Math.min(1, m.x / width)); }
                    }
                }
                Item { visible: !(win.p && win.p.volumeSupported); Layout.fillWidth: true }
                Text {
                    text: win.p ? win.p.identity : ""
                    font.family: Theme.font; font.pixelSize: 10; color: Theme.outline
                }
                Text {
                    visible: win.p && win.p.canRaise
                    text: "\uf08e"; font.family: Theme.font; font.pixelSize: 13; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { if (win.p) win.p.raise(); UiState.media = false; } }
                }
            }
        }
    }
}
