import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// USBGuard prompt: when a plugged-in device is blocked (sysfs authorized=0), a card asks to allow it once or always,
// "Later" (this boot) or "Never" (remembered in ~/.config/rice/usb-ignored.json). Allowing goes through /usr/local/lib/rice/usb-helper.
PanelWindow {
    id: win
    visible: queue.length > 0
    // bottom right, out of the way of the quick settings and notifications
    anchors { bottom: true; right: true }
    margins { bottom: 16; right: 16 }
    implicitWidth: 380
    implicitHeight: card.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-usb"
    WlrLayershell.layer: WlrLayer.Overlay
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 4 }

    readonly property string helper: "/usr/local/lib/rice/usb-helper"
    property var queue: []              // blocked devices still to answer: [{ port, id, name, kinds, key }]
    property var ignored: []            // "vid:pid serial" keys
    property var answered: ({})         // port -> true for this boot (so a refused / failed one does not come back in a loop)
    property string error: ""
    property bool busy: false
    readonly property var dev: queue.length > 0 ? queue[0] : null

    FileView {
        id: ignoreFile
        path: Quickshell.env("HOME") + "/.config/rice/usb-ignored.json"
        onLoaded: { try { win.ignored = JSON.parse(text()); } catch (e) { win.ignored = []; } scan.running = true; }
    }
    Component.onCompleted: scanDelay.start()
    Timer { id: scanDelay; interval: 1500; onTriggered: scan.running = true }
    function ignore(d) {
        ignored = ignored.concat([d.key]);
        ignoreFile.setText(JSON.stringify(ignored));
        next();
    }
    function next() { answered[dev.port] = true; error = ""; queue = queue.slice(1); }

    // blocked devices: port, ids, names and interface classes straight from sysfs (no root needed)
    Process {
        id: scan
        command: ["sh", "-c", "for d in /sys/bus/usb/devices/*; do [ -f \"$d/idVendor\" ] && [ \"$(cat \"$d/authorized\" 2>/dev/null)\" = 0 ] || continue; "
            + "printf '%s\\t%s:%s\\t%s\\t%s\\t%s\\t%s\\n' \"${d##*/}\" \"$(cat $d/idVendor)\" \"$(cat $d/idProduct)\" \"$(cat $d/manufacturer 2>/dev/null)\" \"$(cat $d/product 2>/dev/null)\" \"$(cat $d/serial 2>/dev/null)\" "
            + "\"$(cat $d/bDeviceClass 2>/dev/null) $(cat $d/*:*/bInterfaceClass 2>/dev/null | tr '\\n' ' ')\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const q = win.queue.slice();
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f.length < 6) continue;
                    const key = f[1] + " " + f[4];
                    if (win.answered[f[0]] || win.ignored.indexOf(key) >= 0 || q.some(d => d.port === f[0])) continue;
                    q.push({ port: f[0], id: f[1], name: ((f[2] + " " + f[3]).trim()) || "Unknown device", kinds: win.kinds(f[5].trim().split(/\s+/)), key: key });
                }
                // devices that were allowed or unplugged meanwhile drop out
                const now = text.split("\n").map(l => l.split("\t")[0]);
                win.queue = q.filter(d => now.indexOf(d.port) >= 0);
            }
        }
    }
    function kinds(c) {
        // USB class codes (device class first, then each interface)
        const names = { "01": "audio", "02": "network", "03": "keyboard/mouse", "06": "camera", "07": "printer", "08": "storage", "09": "hub", "0a": "network", "0e": "camera", "e0": "wireless", "ef": "", "ff": "vendor-specific" };
        const out = [];
        for (const x of c) if (names[x] !== undefined && names[x] !== "" && out.indexOf(names[x]) < 0) out.push(names[x]);
        return out;
    }
    Process {
        id: monitor
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb"]
        stdout: SplitParser { onRead: line => { if (line.indexOf(" add ") >= 0 || line.indexOf(" remove ") >= 0 || line.indexOf(" change ") >= 0) settle.restart(); } }
    }
    Timer { id: settle; interval: 700; onTriggered: scan.running = true }

    Process {
        id: allow
        property string port: ""
        stderr: StdioCollector { id: allowErr }
        onExited: code => {
            win.busy = false;
            if (code === 0) { if (win.dev && win.dev.port === allow.port) win.next(); }
            else win.error = code === 127 ? "The USB helper is not installed (run deps.sh)" : (allowErr.text.trim().split("\n").slice(-1)[0] || "Not allowed");
        }
    }
    function permit(permanent) {
        if (!dev || busy) return;
        busy = true; error = "";
        allow.port = dev.port;
        allow.command = ["pkexec", helper, "allow", dev.port].concat(permanent ? ["permanent"] : []);
        allow.running = true;
    }

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + 32
        radius: Theme.radius + 4
        color: Qt.alpha(Theme.surface, 0.9)
        border.width: 1
        border.color: win.dev && win.dev.kinds.indexOf("keyboard/mouse") >= 0 ? Theme.yellow : Theme.outlineVariant

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text { text: ""; font.family: Theme.font; font.pixelSize: 16; color: Theme.primary }
                Text { Layout.fillWidth: true; text: "USB device blocked" + (win.queue.length > 1 ? "  (" + win.queue.length + ")" : ""); font.family: Theme.font; font.pixelSize: 13; font.bold: true; color: Theme.text }
            }
            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: win.dev ? win.dev.name : ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: win.dev ? win.dev.id + "  ·  port " + win.dev.port + (win.dev.kinds.length ? "  ·  " + win.dev.kinds.join(", ") : "") : ""
                font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim
            }
            Text {
                visible: win.dev !== null && win.dev.kinds.indexOf("keyboard/mouse") >= 0
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: "  It says it is a keyboard or mouse. Only allow it if you just plugged one in."
                font.family: Theme.font; font.pixelSize: 10; color: Theme.yellow
            }
            Text { visible: win.error !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; text: win.error; font.family: Theme.font; font.pixelSize: 10; color: Theme.error }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Controls.Chip { label: win.busy ? "Allowing…" : "Allow once"; on: true; onClicked: win.permit(false) }
                Controls.Chip { label: "Always allow"; onClicked: win.permit(true) }
                Item { Layout.fillWidth: true }
                Controls.Chip { label: "Later"; onClicked: if (win.dev) win.next() }
                Controls.Chip { label: "Never"; accent: Theme.error; onClicked: if (win.dev) win.ignore(win.dev) }
            }
        }
    }
}
