import QtQuick

Text {
    font.family: Theme.font
    font.pixelSize: 15
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
    height: Theme.islandHeight
    Behavior on color { ColorAnimation { duration: 400 } }
}
