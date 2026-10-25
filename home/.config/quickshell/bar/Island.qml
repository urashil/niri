import QtQuick

Rectangle {
    id: island
    default property alias content: row.data
    property alias spacing: row.spacing
    property alias overlay: overlayItem.data
    property int pad: 12

    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: Theme.islandHeight
    radius: Theme.radius
    color: Qt.alpha(Theme.surface, 0.88)
    border.width: 1
    border.color: Qt.alpha(Theme.outlineVariant, 0.8)

    Behavior on color { ColorAnimation { duration: 400 } }
    Behavior on border.color { ColorAnimation { duration: 400 } }

    Item { id: overlayItem; anchors.fill: parent; z: 1 }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10
    }
}
