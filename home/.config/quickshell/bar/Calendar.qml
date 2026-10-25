import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Month popup under the clock; click anywhere outside (or the clock again) to close.
PanelWindow {
    id: win
    visible: UiState.calendar
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-calendar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    onVisibleChanged: if (visible) { today = new Date(); year = today.getFullYear(); month = today.getMonth(); }

    function shift(d) {
        const n = new Date(year, month + d, 1);
        year = n.getFullYear(); month = n.getMonth();
    }
    readonly property int first: (new Date(year, month, 1).getDay() + 6) % 7   // Monday-first
    readonly property int dim: new Date(year, month + 1, 0).getDate()

    MouseArea { anchors.fill: parent; onClicked: UiState.calendar = false }
    Item { focus: true; Keys.onEscapePressed: UiState.calendar = false }

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.topMargin: 56
        anchors.horizontalCenter: parent.horizontalCenter
        width: 300
        height: inner.implicitHeight + 32
        radius: Theme.radius + 4
        color: Qt.alpha(Theme.surface, 0.985)
        border.width: 1
        border.color: Theme.outlineVariant

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: inner
            anchors { fill: parent; margins: 16 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.shift(-1) }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(new Date(win.year, win.month, 1), "MMMM yyyy")
                    font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text
                }
                Text {
                    text: ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.shift(1) }
                }
            }

            Grid {
                Layout.alignment: Qt.AlignHCenter
                columns: 7
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Text {
                        required property string modelData
                        width: 36; horizontalAlignment: Text.AlignHCenter
                        text: modelData; font.family: Theme.font; font.pixelSize: 11; color: Theme.outline
                    }
                }
                Repeater {
                    model: Math.ceil((win.first + win.dim) / 7) * 7
                    delegate: Rectangle {
                        required property int index
                        readonly property int day: index - win.first + 1
                        readonly property bool inMonth: day >= 1 && day <= win.dim
                        readonly property bool isToday: inMonth && day === win.today.getDate()
                            && win.month === win.today.getMonth() && win.year === win.today.getFullYear()
                        width: 36; height: 30; radius: 10
                        color: isToday ? Theme.primary : "transparent"
                        Text {
                            anchors.centerIn: parent
                            visible: parent.inMonth
                            text: parent.day
                            font.family: Theme.font; font.pixelSize: 12
                            font.bold: parent.isToday
                            color: parent.isToday ? Theme.fgPrimary : Theme.text
                        }
                    }
                }
            }
        }
    }
}
