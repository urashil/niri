import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Click CPU / RAM / network in the bar: a task-manager style popout (processes, memory, connections).
PanelWindow {
    id: win
    visible: UiState.monitor
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-monitor"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.monitor ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 6 }

    readonly property string tab: UiState.monitorTab
    readonly property string me: Quickshell.env("USER")

    // ---- samples ----
    property var cores: []
    property var cpuHist: []
    property real cpuTotal: 0
    property var prevCpu: ({})
    property string load: ""
    property var mem: ({ total: 1, avail: 0, cached: 0, swapTotal: 0, swapFree: 0 })
    property var procs: []
    property var conns: []
    property var listens: []
    property var info: ({ ip: "", gw: "", dns: "" })

    onVisibleChanged: if (visible) { infoProc.running = true; topProc.running = true; netProc.running = true; }
    onTabChanged: { if (visible) { procs = []; topProc.running = true; netProc.running = true; } }

    function fmtKb(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + "G";
        if (kb >= 1024) return Math.round(kb / 1024) + "M";
        return kb + "K";
    }
    function resKb(s) {
        const m = s.match(/^([\d.]+)([kKmMgGtT]?)$/);
        if (!m) return 0;
        const v = parseFloat(m[1]);
        switch (m[2].toLowerCase()) { case "m": return v * 1024; case "g": return v * 1048576; case "t": return v * 1073741824; default: return v; }
    }
    function isLocal(a) { return /^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|\[?::1|\[?fe80|\[?fd|\[?fc)/.test(a); }

    // CPU: /proc/stat deltas
    Process {
        id: cpuProc
        command: ["sh", "-c", "grep '^cpu' /proc/stat; cat /proc/loadavg"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const cur = {}, pct = [];
                let total = 0;
                for (const l of lines) {
                    if (!l.startsWith("cpu")) { win.load = l.split(" ").slice(0, 3).join("  "); continue; }
                    const f = l.trim().split(/\s+/);
                    const name = f[0], n = f.slice(1).map(Number);
                    const idle = n[3] + (n[4] || 0), sum = n.reduce((a, b) => a + b, 0);
                    cur[name] = { idle: idle, sum: sum };
                    const p = win.prevCpu[name];
                    if (p && sum - p.sum > 0) {
                        const v = 100 * (1 - (idle - p.idle) / (sum - p.sum));
                        if (name === "cpu") total = v; else pct.push(v);
                    }
                }
                win.prevCpu = cur;
                if (pct.length) { win.cores = pct; win.cpuTotal = total; win.cpuHist = win.cpuHist.concat([total]).slice(-60); }
            }
        }
    }
    Process {
        id: memProc
        command: ["sh", "-c", "awk '/^(MemTotal|MemAvailable|Cached|SwapTotal|SwapFree):/{print $1, $2}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = { total: 1, avail: 0, cached: 0, swapTotal: 0, swapFree: 0 };
                for (const l of text.trim().split("\n")) {
                    const [k, v] = l.split(" ");
                    const n = parseInt(v);
                    if (k === "MemTotal:") m.total = n; else if (k === "MemAvailable:") m.avail = n; else if (k === "Cached:") m.cached = n;
                    else if (k === "SwapTotal:") m.swapTotal = n; else if (k === "SwapFree:") m.swapFree = n;
                }
                win.mem = m;
            }
        }
    }
    // top two iterations: the second one is the live CPU %
    Process {
        id: topProc
        command: ["sh", "-c", "top -b -n 2 -d 0.6 -w 200 -o " + (win.tab === "mem" ? "%MEM" : "%CPU")
            + " | awk '/^top -/{n++} n==2 && $1 ~ /^[0-9]+$/ {print $1\"\\t\"$2\"\\t\"$9\"\\t\"$10\"\\t\"$6\"\\t\"$12}' | head -n 12"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of text.trim().split("\n")) {
                    const f = l.split("\t");
                    if (f.length < 6) continue;
                    out.push({ pid: f[0], user: f[1], cpu: parseFloat(f[2]) || 0, memp: parseFloat(f[3]) || 0, res: win.resKb(f[4]), name: f[5] });
                }
                win.procs = out;
            }
        }
    }
    Process {
        id: netProc
        command: ["ss", "-H", "-tunap"]
        stdout: StdioCollector {
            onStreamFinished: {
                const conns = [], listens = [];
                for (const l of text.trim().split("\n")) {
                    const f = l.trim().split(/\s+/);
                    if (f.length < 6) continue;
                    const pm = (f.slice(6).join(" ")).match(/\(\("([^"]+)",pid=(\d+)/);
                    const row = { proto: f[0], state: f[1], local: f[4], peer: f[5], name: pm ? pm[1] : "", pid: pm ? pm[2] : "" };
                    if (f[1] === "ESTAB") conns.push(row);
                    else if (f[1] === "LISTEN" || (f[0] === "udp" && f[1] === "UNCONN")) listens.push(row);
                }
                const byName = (a, b) => (a.name || "~").localeCompare(b.name || "~");
                conns.sort(byName); listens.sort(byName);
                win.conns = conns; win.listens = listens;
            }
        }
    }
    Process {
        id: infoProc
        command: ["sh", "-c", "ip -4 -o addr show wlan0 | awk '{print $4; exit}'; ip route | awk '/^default/{print $3; exit}'; awk '/^nameserver/{printf \"%s \", $2}' /etc/resolv.conf"]
        stdout: StdioCollector {
            onStreamFinished: { const l = text.split("\n"); win.info = { ip: l[0] || "", gw: l[1] || "", dns: (l[2] || "").trim() }; }
        }
    }

    Timer { interval: 1000; running: win.visible; repeat: true; triggeredOnStart: true; onTriggered: { cpuProc.running = true; memProc.running = true; } }
    Timer { interval: 2200; running: win.visible && win.tab !== "net"; repeat: true; onTriggered: topProc.running = true }
    Timer { interval: 2000; running: win.visible && win.tab === "net"; repeat: true; onTriggered: netProc.running = true }

    MouseArea { anchors.fill: parent; onClicked: UiState.monitor = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.monitor = false }

    component Spark: Item {
        id: sp
        property var data: []
        property real maxv: 100
        property color col: Theme.primary
        height: 46
        Row {
            anchors.fill: parent
            spacing: 1
            layoutDirection: Qt.RightToLeft
            Repeater {
                model: sp.data.length
                delegate: Rectangle {
                    required property int index
                    readonly property real v: sp.data[sp.data.length - 1 - index]
                    width: Math.max(2, (sp.width - 59) / 60)
                    height: Math.max(2, sp.height * Math.min(1, v / Math.max(1, sp.maxv)))
                    anchors.bottom: parent.bottom
                    radius: 1
                    color: sp.col
                    opacity: 0.35 + 0.65 * (1 - index / 60)
                }
            }
        }
    }
    component Bar: Rectangle {
        property real frac: 0
        property color col: Theme.primary
        height: 8; radius: 4; color: Theme.surfaceHigh
        Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.frac)); height: parent.height; radius: 4; color: parent.col; Behavior on width { NumberAnimation { duration: 300 } } }
    }
    component Tab: Rectangle {
        id: t
        property string key
        property string label
        property string glyph
        height: 30; radius: 15; width: tl.implicitWidth + 28
        color: win.tab === key ? Theme.primaryContainer : Theme.surfaceHigh
        Behavior on color { ColorAnimation { duration: 150 } }
        Text { id: tl; anchors.centerIn: parent; text: t.glyph + "  " + t.label; font.family: Theme.font; font.pixelSize: 11; color: win.tab === t.key ? Theme.fgContainer : Theme.text }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: UiState.monitorTab = t.key }
    }

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: 56; rightMargin: 230 }
        width: 560
        height: Math.min(win.height - 80, body.implicitHeight + 36)
        radius: Theme.radius + 6
        color: Qt.alpha(Theme.surface, 0.84)
        border.width: 1
        border.color: Theme.outlineVariant
        clip: true
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 10

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Tab { key: "cpu"; label: "CPU"; glyph: "\uf2db" }
                Tab { key: "mem"; label: "Memory"; glyph: "\udb80\udf5b" }
                Tab { key: "net"; label: "Network"; glyph: "\uf1eb" }
                Item { Layout.fillWidth: true }
                Rectangle {
                    height: 30; radius: 15; width: bt.implicitWidth + 24; color: Theme.surfaceHigh
                    Text { id: bt; anchors.centerIn: parent; text: "\uf120  btop"; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { UiState.monitor = false; Quickshell.execDetached(["kitty", "--class", "btop-float", "-e", "btop"]); } }
                }
            }

            // ================= CPU =================
            ColumnLayout {
                visible: win.tab === "cpu"
                Layout.fillWidth: true
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: Math.round(win.cpuTotal) + "%"; font.family: Theme.font; font.pixelSize: 34; font.bold: true; color: win.cpuTotal > 85 ? Theme.error : Theme.green }
                    ColumnLayout {
                        spacing: 1
                        Text { text: win.cores.length + " cores · load " + win.load; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
                    }
                    Item { Layout.fillWidth: true }
                    Spark { Layout.preferredWidth: 280; data: win.cpuHist; col: Theme.green }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: win.cores
                        delegate: ColumnLayout {
                            required property real modelData
                            required property int index
                            width: 62; spacing: 3
                            Text { text: "cpu" + index + "  " + Math.round(modelData) + "%"; font.family: Theme.font; font.pixelSize: 9; color: Theme.textDim }
                            Bar { Layout.fillWidth: true; frac: modelData / 100; col: modelData > 85 ? Theme.error : Theme.green }
                        }
                    }
                }
                Text { text: "Top processes by CPU"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
            }

            // ================= Memory =================
            ColumnLayout {
                visible: win.tab === "mem"
                Layout.fillWidth: true
                spacing: 9
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: win.fmtKb(win.mem.total - win.mem.avail); font.family: Theme.font; font.pixelSize: 34; font.bold: true; color: (win.mem.total - win.mem.avail) / win.mem.total > 0.85 ? Theme.error : Theme.yellow }
                    Text { text: "of " + win.fmtKb(win.mem.total) + " used · " + win.fmtKb(win.mem.cached) + " cached"; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 6 }
                }
                Bar { Layout.fillWidth: true; frac: (win.mem.total - win.mem.avail) / win.mem.total; col: Theme.yellow }
                RowLayout {
                    visible: win.mem.swapTotal > 0
                    Layout.fillWidth: true
                    Text { text: "swap " + win.fmtKb(win.mem.swapTotal - win.mem.swapFree) + " / " + win.fmtKb(win.mem.swapTotal); font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; Layout.preferredWidth: 150 }
                    Bar { Layout.fillWidth: true; frac: win.mem.swapTotal > 0 ? (win.mem.swapTotal - win.mem.swapFree) / win.mem.swapTotal : 0; col: Theme.magenta }
                }
                Text { text: "Top processes by memory"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
            }

            // process list (cpu + mem tabs)
            ColumnLayout {
                visible: win.tab !== "net"
                Layout.fillWidth: true
                spacing: 3
                Repeater {
                    model: win.procs
                    delegate: Rectangle {
                        id: pr
                        required property var modelData
                        Layout.fillWidth: true
                        height: 30; radius: 9
                        color: hov.containsMouse ? Theme.surfaceContainer : "transparent"
                        readonly property bool mine: modelData.user === win.me || modelData.user.startsWith(win.me.slice(0, 7))
                        Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } width: 190; elide: Text.ElideRight; text: pr.modelData.name; font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
                        Text { anchors { left: parent.left; leftMargin: 208; verticalCenter: parent.verticalCenter } text: pr.modelData.pid; font.family: Theme.font; font.pixelSize: 10; color: Theme.outline }
                        Text { anchors { left: parent.left; leftMargin: 270; verticalCenter: parent.verticalCenter } width: 70; text: pr.modelData.user.slice(0, 9); elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 10; color: pr.mine ? Theme.textDim : Theme.outline }
                        Text {
                            anchors { right: parent.right; rightMargin: 52; verticalCenter: parent.verticalCenter }
                            text: win.tab === "mem" ? win.fmtKb(pr.modelData.res) + "  " + pr.modelData.memp.toFixed(1) + "%" : pr.modelData.cpu.toFixed(1) + "%  " + pr.modelData.memp.toFixed(1) + "% mem"
                            font.family: Theme.font; font.pixelSize: 11; font.bold: true
                            color: (win.tab === "mem" ? pr.modelData.memp : pr.modelData.cpu) > 50 ? Theme.error : Theme.text
                        }
                        Text {
                            visible: hov.containsMouse && pr.mine
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: "\uf00d"; font.family: Theme.font; font.pixelSize: 13; color: Theme.error
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["kill", pr.modelData.pid]) }
                        }
                        MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    }
                }
                Text { visible: win.procs.length === 0; text: "sampling…"; font.family: Theme.font; font.pixelSize: 11; color: Theme.outline }
                Text { text: "hover a row of yours and click ✕ to send SIGTERM"; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline }
            }

            // ================= Network =================
            ColumnLayout {
                visible: win.tab === "net"
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18
                    ColumnLayout {
                        spacing: 0
                        Text { text: "\uf063  " + NetStats.fmt(NetStats.down) + "/s"; font.family: Theme.font; font.pixelSize: 22; font.bold: true; color: Theme.cyan }
                        Text { text: "\uf062  " + NetStats.fmt(NetStats.up) + "/s"; font.family: Theme.font; font.pixelSize: 22; font.bold: true; color: Theme.magenta }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Spark { Layout.fillWidth: true; height: 30; data: NetStats.downHist; maxv: Math.max.apply(null, NetStats.downHist.concat([102400])); col: Theme.cyan }
                        Spark { Layout.fillWidth: true; height: 30; data: NetStats.upHist; maxv: Math.max.apply(null, NetStats.upHist.concat([102400])); col: Theme.magenta }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ncol.implicitHeight + 22
                    radius: 14; color: Theme.surfaceContainer
                    ColumnLayout {
                        id: ncol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 }
                        spacing: 3
                        Text { text: (Wifi.connected ? Wifi.ssid : "not connected") + "   " + win.info.ip + "   gw " + win.info.gw; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                        Text { text: "dns " + win.info.dns + (Vpn.connected ? "   ·   VPN " + Vpn.pretty(Vpn.region) + "  public " + Vpn.pubIp : Vpn.pubIp !== "" ? "   ·   public " + Vpn.pubIp : ""); font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }

                Text { text: "Connections  (" + win.conns.length + ")"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 200)
                    clip: true; spacing: 2
                    model: win.conns
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: 26; radius: 8; color: "transparent"
                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 130; elide: Text.ElideRight; text: modelData.name || "—"; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                        Text { x: 142; anchors.verticalCenter: parent.verticalCenter; text: modelData.proto; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline }
                        Text { x: 178; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 190; elide: Text.ElideMiddle; text: modelData.local + "  →  " + modelData.peer; font.family: Theme.font; font.pixelSize: 10; color: win.isLocal(modelData.peer) ? Theme.outline : Theme.cyan }
                    }
                }
                Text { text: "Listening  (" + win.listens.length + ")"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 120)
                    clip: true; spacing: 2
                    model: win.listens
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: 24; radius: 8; color: "transparent"
                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 130; elide: Text.ElideRight; text: modelData.name || "—"; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                        Text { x: 142; anchors.verticalCenter: parent.verticalCenter; text: modelData.proto; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline }
                        Text { x: 178; anchors.verticalCenter: parent.verticalCenter; text: modelData.local; font.family: Theme.font; font.pixelSize: 10; color: modelData.local.startsWith("127.") || modelData.local.startsWith("[::1]") ? Theme.outline : Theme.yellow }
                    }
                }
                Text { text: "cyan = remote peer, dim = local · yellow = open to the network · process names only show for your own programs"; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
    }
}
