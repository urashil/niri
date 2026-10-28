import QtQuick

// Four bouncing bars; still when not active.
Row {
    id: eq
    property bool active: true
    property color barColor: Theme.tertiary
    property int barWidth: 3
    property int barHeight: 14
    spacing: Math.max(1, Math.round(barWidth / 2))
    height: barHeight
    Repeater {
        model: 4
        delegate: Rectangle {
            id: bar
            required property int index
            anchors.bottom: parent.bottom
            width: eq.barWidth; radius: width / 2
            color: eq.barColor
            height: eq.barHeight * 0.3
            SequentialAnimation on height {
                running: eq.active
                loops: Animation.Infinite
                NumberAnimation { to: eq.barHeight * (0.45 + 0.55 * ((bar.index * 37) % 10) / 10); duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
                NumberAnimation { to: eq.barHeight * 0.25; duration: 300 + bar.index * 50; easing.type: Easing.InOutSine }
            }
        }
    }
}
