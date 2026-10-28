import Quickshell
import Quickshell.Wayland
import QtQuick

// The island opened up: click the song in the island and it grows into the film, with the transport underneath.
PanelWindow {
    id: win
    readonly property bool open: UiState.songOpen && Song.started
    visible: UiState.songOpen || card.height > Theme.islandHeight + 2
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-song"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.songOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: card.radius }

    function close() { UiState.songOpen = false; }
    // leaving the expanded state when the song is stopped or ends
    onOpenChanged: if (!open && UiState.songOpen) close()

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) win.close();
            else if (e.key === Qt.Key_Space) Song.toggle();
            else if (e.key === Qt.Key_Left) Song.seek(Song.position - 5);
            else if (e.key === Qt.Key_Right) Song.seek(Song.position + 5);
            else if (e.key === Qt.Key_N) Song.nextChapter();
            else if (e.key === Qt.Key_P) Song.prevChapter();
            else if (e.key === Qt.Key_M) Song.muted = !Song.muted;
        }
    }

    Rectangle {
        id: card
        x: (parent.width - width) / 2
        y: 8
        width: win.open ? 520 : UiState.pillW
        height: win.open ? body.implicitHeight + 28 : Theme.islandHeight
        radius: win.open ? Theme.radius + 10 : height / 2
        color: Qt.alpha(Theme.surface, win.open ? 0.93 : 0.86)
        border.width: 1
        border.color: Qt.alpha(Theme.primary, win.open ? 0.45 : 0.7)
        clip: true
        Behavior on width { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on height { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }
        MouseArea { anchors.fill: parent }

        Column {
            id: body
            x: 14; y: 14
            width: parent.width - 28
            spacing: 12
            opacity: win.open && card.height > 200 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            // ---- the film ----
            Rectangle {
                width: parent.width
                height: Math.round(width * 9 / 16)
                radius: Theme.radius + 2
                color: "#08090a"
                clip: true
                Image {
                    anchors.fill: parent
                    source: Song.frameUrl
                    cache: false
                    asynchronous: false
                    fillMode: Image.PreserveAspectCrop
                    visible: Song.frameCount > 0
                }
                Column {
                    visible: Song.frameCount === 0
                    anchors.centerIn: parent
                    spacing: 10
                    Equalizer { anchors.horizontalCenter: parent.horizontalCenter; active: true; barColor: "#ff593c"; barWidth: 5; barHeight: 26 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Starting the film…"; font.family: Theme.font; font.pixelSize: 11; color: "#8b8f98" }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Song.toggle() }
            }

            // ---- title ----
            Item {
                width: parent.width; height: 38
                Column {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { text: Song.name; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text }
                    Text { text: String(Song.chapter + 1).padStart(2, "0") + " / " + Song.chapterTitle; font.family: Theme.font; font.pixelSize: 11; color: Theme.primary }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: Song.clock(Song.position) + " / " + Song.clock(Song.duration)
                    font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim
                }
            }

            // ---- seek bar with a tick for every scene ----
            Item {
                id: seek
                width: parent.width; height: 14
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Theme.surfaceHigh }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, Song.position / Song.duration); height: 6; radius: 3; color: Theme.primary }
                Repeater {
                    model: Song.chapters
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        visible: index > 0
                        x: modelData.start / Song.duration * seek.width - 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 10; radius: 1
                        color: modelData.start <= Song.position ? Theme.fgPrimary : Theme.outline
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(seek.width, seek.width * Song.position / Song.duration) - 6
                    width: 12; height: 12; radius: 6; color: Theme.text
                    visible: seekArea.containsMouse || seekArea.pressed
                }
                MouseArea {
                    id: seekArea
                    anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: m => Song.seek(m.x / width * Song.duration)
                    onPositionChanged: m => { if (pressed) Song.seek(Math.max(0, Math.min(1, m.x / width)) * Song.duration); }
                }
            }

            // ---- controls ----
            Item {
                width: parent.width; height: 40
                Row {
                    anchors.centerIn: parent
                    spacing: 30
                    Repeater {
                        model: [{ g: "", act: 0, big: false }, { g: "", act: 1, big: true }, { g: "", act: 2, big: false }]
                        delegate: Text {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.act === 1 ? (Song.playing ? "" : "") : modelData.g
                            font.family: Theme.font; font.pixelSize: modelData.big ? 28 : 18
                            color: modelData.big ? Theme.primary : Theme.text
                            scale: ma.containsMouse ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            MouseArea {
                                id: ma
                                anchors { fill: parent; margins: -10 }
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.act === 0 ? Song.prevChapter() : modelData.act === 1 ? Song.toggle() : Song.nextChapter()
                            }
                        }
                    }
                }
                // volume
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Song.muted || Song.volume === 0 ? "" : ""
                        font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim
                        MouseArea { anchors { fill: parent; margins: -6 } cursorShape: Qt.PointingHandCursor; onClicked: Song.muted = !Song.muted }
                    }
                    Item {
                        id: vol
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70; height: 14
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.surfaceHigh }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * (Song.muted ? 0 : Song.volume); height: 4; radius: 2; color: Theme.textDim }
                        MouseArea {
                            anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                            cursorShape: Qt.PointingHandCursor
                            onPressed: m => { Song.muted = false; Song.volume = Math.max(0, Math.min(1, m.x / width)); }
                            onPositionChanged: m => { if (pressed) Song.volume = Math.max(0, Math.min(1, m.x / width)); }
                        }
                    }
                }
                // stop / collapse
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 18
                    Repeater {
                        model: [{ g: "", act: 0 }, { g: "", act: 1 }]
                        delegate: Text {
                            required property var modelData
                            text: modelData.g
                            font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim
                            MouseArea { anchors { fill: parent; margins: -6 } cursorShape: Qt.PointingHandCursor; onClicked: modelData.act === 0 ? Song.stop() : win.close() }
                        }
                    }
                }
            }
        }
    }
}
