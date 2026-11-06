import QtQuick

Text {
    font.family: Theme.font
    font.pixelSize: 13
    font.weight: Font.Medium
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
    height: Theme.islandHeight
    Behavior on color { ColorAnimation { duration: 400 } }
}
