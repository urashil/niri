import QtQuick

// The center pill: clock when idle, morphs into whatever just happened.
Rectangle {
    id: root
    readonly property bool active: UiState.islandActive
    readonly property real idleW: clockRow.implicitWidth + 32
    readonly property bool songShown: Song.nowPlaying
    readonly property real eventW: Math.max(idleW, evRow.implicitWidth + 36)

    width: active ? eventW : idleW
    height: Theme.islandHeight + (active ? 4 : 0)
    radius: height / 2
    color: Qt.alpha(Theme.surface, 0.86)
    border.width: 1
    border.color: active ? Qt.alpha(UiState.islandColor, 0.7) : Qt.alpha(Theme.outlineVariant, 0.8)
    clip: true

    onWidthChanged: UiState.pillW = width
    // the expanded song island takes over while it is open
    opacity: UiState.songOpen ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 300 } }
    Behavior on color { ColorAnimation { duration: 400 } }

    // idle: clock
    Row {
        id: clockRow
        z: 3
        anchors.centerIn: parent
        spacing: 10
        opacity: root.active ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Row {
            visible: !root.songShown
            spacing: 10
            Glyph { text: ""; color: Theme.primary; font.pixelSize: 14 }
            Label { text: Qt.formatDateTime(clock.date, "ddd d MMM"); color: Theme.textDim }
            Label { text: Qt.formatDateTime(clock.date, "HH:mm:ss"); font.weight: Font.Bold }
        }
        // a song is playing: it stays in the island until it stops
        Row {
            visible: root.songShown
            spacing: 10
            Equalizer { anchors.verticalCenter: parent.verticalCenter; active: Song.nowPlaying; barColor: Song.playing ? Theme.primary : Theme.tertiary }
            Label { text: Song.nowText; elide: Text.ElideRight; width: Math.min(implicitWidth, 260); font.weight: Font.Bold }
        }

        // timer chip (running timer: remaining time, red in the last minute)
        Item {
            visible: Focus.active
            width: tRow.implicitWidth; height: Theme.islandHeight
            Row {
                id: tRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Glyph { text: "\uf252"; font.pixelSize: 13; color: Focus.paused ? Theme.outline : Focus.urgent ? Theme.red : Theme.primary; height: Theme.islandHeight }
                Label { text: Focus.clockText; font.weight: Font.Bold; color: Focus.paused ? Theme.textDim : Focus.urgent ? Theme.red : Theme.text }
            }
            MouseArea { anchors.fill: parent; anchors.margins: -4; z: 5; cursorShape: Qt.PointingHandCursor; onClicked: UiState.openFocus("timer") }
        }
        // todo chip (open tasks)
        Item {
            visible: Focus.openCount > 0
            width: dRow.implicitWidth; height: Theme.islandHeight
            Row {
                id: dRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Glyph { text: "\uf046"; font.pixelSize: 13; color: Theme.green; height: Theme.islandHeight }
                Label { text: Focus.openCount; color: Theme.textDim }
            }
            MouseArea { anchors.fill: parent; anchors.margins: -4; z: 5; cursorShape: Qt.PointingHandCursor; onClicked: UiState.openFocus("todo") }
        }
    }

    // active: event
    Row {
        id: evRow
        anchors.centerIn: parent
        spacing: 10
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Glyph {
            text: UiState.islandIcon
            color: UiState.islandColor
            font.pixelSize: 16
            height: parent.height
        }
        Rectangle {
            visible: UiState.islandValue >= 0
            anchors.verticalCenter: parent.verticalCenter
            width: 110; height: 6; radius: 3
            color: Theme.surfaceHigh
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, UiState.islandValue))
                height: parent.height; radius: 3
                color: UiState.islandColor
                Behavior on width { NumberAnimation { duration: 120 } }
            }
        }
        Label {
            text: UiState.islandText
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 320)
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.active && UiState.islandKind === "media") { if (Song.started) UiState.songOpen = true; else UiState.media = true; }
            else if (!root.active && Song.playing) UiState.songOpen = true;
            else if (!root.active && root.songShown) UiState.media = true;
            else UiState.openFocus("todo");
        }
    }
}
