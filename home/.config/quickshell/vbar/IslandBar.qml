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
    // reveal stays while the pointer is over EITHER the catcher strip or the card (incl. its
    // controls — arrows, dots, media buttons); it only closes once both are clear
    property bool catcherHover: false
    property bool cardHover: false
    onCatcherHoverChanged: win.syncReveal()
    onCardHoverChanged: win.syncReveal()
    function syncReveal() { if (win.catcherHover || win.cardHover) { revealTimer.stop(); win.reveal = true; } else revealTimer.restart(); }
    readonly property bool pill: UiState.islandActive && !reveal
    property int page: 0 // 0 time, 1 media, 2 system
    function cycle(dir) { page = (page + dir + 3) % 3; }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    property int cpu: 0
    property int mem: 0
    property int temp: 0
    property real memUsed: 0     // GB
    property real memTotal: 0    // GB
    property int disk: 0
    property real diskUsed: 0    // GB
    property real diskTotal: 0   // GB
    property real netDown: 0     // bytes/s
    property real netUp: 0       // bytes/s
    property int uptimeS: 0
    property string load: ""
    property var last: null
    property var lastNet: null

    function fmtRate(b) { return b < 1024 ? Math.round(b) + " B/s" : b < 1048576 ? Math.round(b / 1024) + " KB/s" : (b / 1048576).toFixed(1) + " MB/s"; }
    function fmtUp(s) { const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m"; }

    Process {
        id: statProc
        command: ["sh", "-c",
            "head -1 /proc/stat; " +
            "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"%d %d %d\\n\",(t-a)*100/t,t-a,t}' /proc/meminfo; " +
            "m=0; for z in /sys/class/thermal/thermal_zone*/temp; do v=$(cat $z 2>/dev/null); [ \"${v:-0}\" -gt \"$m\" ] && m=$v; done; echo $((m/1000)); " +
            "df -P / | awk 'NR==2{printf \"%d %d %d\\n\",($3/$2*100),$3,$2}'; " +
            "awk '{sub(/:/,\" \")} NR>2{if($1!=\"lo\"){rx+=$2;tx+=$10}}END{printf \"%d %d\\n\",rx,tx}' /proc/net/dev; " +
            "cut -d. -f1 /proc/uptime; " +
            "cut -d' ' -f1-3 /proc/loadavg"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                if (l.length < 7) return;
                const f = l[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
                if (win.last) { const dt = total - win.last.total, di = idle - win.last.idle; if (dt > 0) win.cpu = Math.round(100 * (dt - di) / dt); }
                win.last = { idle: idle, total: total };
                const mm = l[1].split(/\s+/).map(Number);
                win.mem = mm[0]; win.memUsed = mm[1] / 1048576; win.memTotal = mm[2] / 1048576;
                win.temp = parseInt(l[2]);
                const dk = l[3].split(/\s+/).map(Number);
                win.disk = dk[0]; win.diskUsed = dk[1] / 1048576; win.diskTotal = dk[2] / 1048576;
                const net = l[4].split(/\s+/).map(Number);
                const now = Date.now();
                if (win.lastNet) { const dts = (now - win.lastNet.t) / 1000; if (dts > 0.3 && dts < 10) { win.netDown = Math.max(0, (net[0] - win.lastNet.rx) / dts); win.netUp = Math.max(0, (net[1] - win.lastNet.tx) / dts); } }
                win.lastNet = { rx: net[0], tx: net[1], t: now };
                win.uptimeS = parseInt(l[5]);
                win.load = l[6].trim().replace(/\s+/g, "  ");
            }
        }
    }
    Timer { interval: 1500; running: win.reveal && win.page === 2; repeat: true; triggeredOnStart: true; onTriggered: statProc.running = true }
    // drop stale deltas when leaving the system page, so the next first reading isn't a spike
    onPageChanged: if (page !== 2) { win.last = null; win.lastNet = null; }
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
        Text { text: meter.value; Layout.preferredWidth: Math.max(52, implicitWidth); horizontalAlignment: Text.AlignRight; maximumLineCount: 1; elide: Text.ElideNone; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: meter.tint }
    }

    mask: Region { item: catcher }
    Item {
        id: catcher
        width: win.reveal ? dash.width + 60 : 320
        x: (win.width - width) / 2
        y: 0
        height: win.reveal ? win.height : 6
        HoverHandler { id: hov; onHoveredChanged: win.catcherHover = hovered; }
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
        // keep the pulldown open while the pointer is anywhere over the card, including its controls
        HoverHandler { onHoveredChanged: win.cardHover = hovered; }

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 14

            // card header: name + left/right arrows
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 30; implicitHeight: 30; radius: 15
                    color: lhov.hovered ? Theme.surfaceHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: ""; font.family: Theme.font; font.pixelSize: 19; color: lhov.hovered ? Theme.primary : Theme.text }
                    HoverHandler { id: lhov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.cycle(-1) }
                }
                Item { Layout.fillWidth: true }
                Text { text: ["Time", "Media", "System"][win.page]; font.family: Theme.font; font.pixelSize: 13; font.bold: true; color: Theme.textDim }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 30; implicitHeight: 30; radius: 15
                    color: rhov.hovered ? Theme.surfaceHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: ""; font.family: Theme.font; font.pixelSize: 19; color: rhov.hovered ? Theme.primary : Theme.text }
                    HoverHandler { id: rhov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.cycle(1) }
                }
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
                    spacing: 11
                    Meter { label: "CPU"; pct: win.cpu }
                    Meter { label: "Memory"; pct: win.mem; value: win.memUsed.toFixed(1) + " / " + win.memTotal.toFixed(1) + " GB" }
                    Meter { label: "Disk /"; pct: win.disk; value: win.diskUsed.toFixed(0) + " / " + win.diskTotal.toFixed(0) + " GB" }
                    Meter { label: "Temp"; pct: Math.min(100, win.temp); value: win.temp + "°C" }

                    // network throughput
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 3
                        spacing: 10
                        Repeater {
                            model: [
                                { g: "", tint: Theme.primary, rate: win.netDown, label: "download" },
                                { g: "", tint: Theme.yellow,  rate: win.netUp,   label: "upload" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 48; radius: 12; color: Theme.surfaceHigh
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 9
                                    Text { text: modelData.g; font.family: Theme.font; font.pixelSize: 15; color: modelData.tint }
                                    ColumnLayout {
                                        spacing: 0
                                        Text { text: win.fmtRate(modelData.rate); font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text }
                                        Text { text: modelData.label; font.family: Theme.font; font.pixelSize: 9; color: Theme.textDim }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }

                    // uptime + load average
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Text { text: "  up " + win.fmtUp(win.uptimeS); font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        Item { Layout.fillWidth: true }
                        Text { text: "load  " + win.load; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                    }
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
