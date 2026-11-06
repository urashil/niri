import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Top-center pulldown. Hover the top to reveal a card you cycle through:
// Time / Media / System (scroll over it, or click the dots). On an event it drops
// the small island pill instead. Click-through except the strip/card it occupies.
PanelWindow {
    id: win
    anchors { top: true; left: true; right: true }
    implicitHeight: 360
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-island"
    WlrLayershell.layer: WlrLayer.Top

    readonly property var p: Mpris.players.values.find(x => x.isPlaying) ?? (Mpris.players.values.length > 0 ? Mpris.players.values[0] : null)
    property bool reveal: false
    Timer { id: revealTimer; interval: 350; onTriggered: win.reveal = false }
    readonly property bool pill: UiState.islandActive && !reveal
    property int page: 0 // 0 time, 1 media, 2 system
    function cycle(dir) { page = (page + dir + 3) % 3; }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    property int cpu: 0
    property int mem: 0
    property int temp: 0
    property var last: null
    Process {
        id: statProc
        command: ["sh", "-c", "head -1 /proc/stat; awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"%d\\n\", (t-a)*100/t}' /proc/meminfo; m=0; for z in /sys/class/thermal/thermal_zone*/temp; do v=$(cat $z 2>/dev/null); [ \"${v:-0}\" -gt \"$m\" ] && m=$v; done; echo $((m/1000))"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                if (l.length < 3) return;
                const f = l[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
                if (win.last) { const dt = total - win.last.total, di = idle - win.last.idle; if (dt > 0) win.cpu = Math.round(100 * (dt - di) / dt); }
                win.last = { idle: idle, total: total };
                win.mem = parseInt(l[1]); win.temp = parseInt(l[2]);
            }
        }
    }
    Timer { interval: 2000; running: win.reveal && win.page === 2; repeat: true; triggeredOnStart: true; onTriggered: statProc.running = true }
    Timer { interval: 500; running: win.reveal && win.page === 1 && win.p && win.p.isPlaying; repeat: true; onTriggered: if (win.p) win.p.positionChanged() }

    component Meter: RowLayout {
        id: meter
        property string label
        property real pct
        property string value: Math.round(pct) + "%"
        property color tint: pct >= 85 ? Theme.error : pct >= 60 ? Theme.yellow : Theme.primary
        Layout.fillWidth: true
        spacing: 12
        Text { text: meter.label; Layout.preferredWidth: 58; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim }
        Rectangle {
            Layout.fillWidth: true; height: 9; radius: 5; color: Theme.surfaceHigh
            Rectangle { height: parent.height; radius: 5; width: parent.width * Math.max(0, Math.min(1, meter.pct / 100)); color: meter.tint
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } }
        }
        Text { text: meter.value; Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: meter.tint }
    }

    mask: Region { item: catcher }
    Item {
        id: catcher
        width: win.reveal ? dash.width + 60 : 320
        x: (win.width - width) / 2
        y: 0
        height: win.reveal ? win.height : 6
        HoverHandler { id: hov; onHoveredChanged: if (hovered) { revealTimer.stop(); win.reveal = true; } else revealTimer.restart(); }
    }

    // small event pill
    DynamicIsland {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.pill ? 8 : -height - 12
        maxW: win.width - 2 * 160
        opacity: win.pill ? 1 : 0
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // the card you cycle through
    Rectangle {
        id: dash
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.reveal ? 12 : -height - 28
        width: 440
        height: body.implicitHeight + 36
        radius: Theme.radius + 12
        color: Qt.alpha(Theme.surface, 0.97)
        border.width: 1
        border.color: Theme.outlineVariant
        opacity: win.reveal ? 1 : 0
        Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        WheelHandler { onWheel: e => win.cycle(e.angleDelta.y < 0 ? 1 : -1) }

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 14

            // card header: name + left/right arrows
            RowLayout {
                Layout.fillWidth: true
                Text { text: ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.cycle(-1) } }
                Item { Layout.fillWidth: true }
                Text { text: ["Time", "Media", "System"][win.page]; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.textDim }
                Item { Layout.fillWidth: true }
                Text { text: ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.cycle(1) } }
            }

            // ── pages ──
            StackLayout {
                Layout.fillWidth: true
                currentIndex: win.page

                // TIME
                ColumnLayout {
                    spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(clock.date, "HH:mm"); font.family: Theme.font; font.pixelSize: 52; font.bold: true; color: Theme.text }
                    Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(clock.date, "dddd, MMMM d"); font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim }
                    Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(clock.date, "ss") + "s"; font.family: Theme.font; font.pixelSize: 11; color: Theme.outline }
                }

                // MEDIA
                RowLayout {
                    spacing: 14
                    Rectangle {
                        width: 72; height: 72; radius: 12; color: Theme.surfaceHigh; clip: true
                        Image { anchors.fill: parent; source: win.p && win.p.trackArtUrl ? win.p.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                        Text { anchors.centerIn: parent; visible: !win.p || !win.p.trackArtUrl; text: ""; font.family: Theme.font; font.pixelSize: 30; color: Theme.outline }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: win.p ? win.p.trackTitle : "Nothing playing"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; textFormat: Text.PlainText }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; visible: !!win.p; text: win.p ? win.p.trackArtist : ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim; textFormat: Text.PlainText }
                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 26
                            Text { text: ""; font.family: Theme.font; font.pixelSize: 18; color: Theme.text; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.previous() } }
                            Text { text: win.p && win.p.isPlaying ? "" : ""; font.family: Theme.font; font.pixelSize: 24; color: Theme.primary; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.togglePlaying() } }
                            Text { text: ""; font.family: Theme.font; font.pixelSize: 18; color: Theme.text; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (win.p) win.p.next() } }
                        }
                    }
                }

                // SYSTEM
                ColumnLayout {
                    spacing: 14
                    Meter { label: "CPU"; pct: win.cpu }
                    Meter { label: "Memory"; pct: win.mem }
                    Meter { label: "Temp"; pct: Math.min(100, win.temp); value: win.temp + "°C" }
                }
            }

            // page dots
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: win.page === index ? 18 : 7
                        height: 7; radius: 4
                        color: win.page === index ? Theme.primary : Theme.outlineVariant
                        Behavior on width { NumberAnimation { duration: 180 } }
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: win.page = parent.index }
                    }
                }
            }
        }
    }
}
