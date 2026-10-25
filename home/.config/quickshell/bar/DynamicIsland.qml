import QtQuick

// The center pill: clock when idle, morphs into whatever just happened.
Rectangle {
    id: root
    readonly property bool active: UiState.islandActive
    readonly property real idleW: clockRow.implicitWidth + 32
    readonly property real eventW: Math.max(idleW, evRow.implicitWidth + 36)

    width: active ? eventW : idleW
    height: Theme.islandHeight + (active ? 4 : 0)
    radius: height / 2
    color: Qt.alpha(Theme.surface, 0.92)
    border.width: 1
    border.color: active ? Qt.alpha(UiState.islandColor, 0.7) : Qt.alpha(Theme.outlineVariant, 0.8)
    clip: true

    Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 300 } }
    Behavior on color { ColorAnimation { duration: 400 } }

    // idle: clock
    Row {
        id: clockRow
        anchors.centerIn: parent
        spacing: 10
        opacity: root.active ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Glyph { text: ""; color: Theme.primary; font.pixelSize: 14 }
        Label { text: Qt.formatDateTime(clock.date, "ddd d MMM"); color: Theme.textDim }
        Label { text: Qt.formatDateTime(clock.date, "HH:mm:ss"); font.weight: Font.Bold }
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
            if (root.active && UiState.islandKind === "media") UiState.media = true;
            else UiState.calendar = !UiState.calendar;
        }
    }
}
