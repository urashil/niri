import Quickshell.Io
import QtQuick

Island {
    id: root
    spacing: 12
    property int cpu: 0
    property int mem: 0
    property int temp: 0
    property var last: null

    Process {
        id: proc
        command: ["sh", "-c", "head -1 /proc/stat; awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"%d\\n\", (t-a)*100/t}' /proc/meminfo; m=0; for z in /sys/class/thermal/thermal_zone*/temp; do v=$(cat $z 2>/dev/null); [ \"${v:-0}\" -gt \"$m\" ] && m=$v; done; echo $((m/1000))"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                if (l.length < 3) return;
                const f = l[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = f[3] + f[4];
                const total = f.reduce((a, b) => a + b, 0);
                if (root.last) {
                    const dt = total - root.last.total, di = idle - root.last.idle;
                    if (dt > 0) root.cpu = Math.round(100 * (dt - di) / dt);
                }
                root.last = { idle: idle, total: total };
                root.mem = parseInt(l[1]);
                root.temp = parseInt(l[2]);
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }

    Row {
        spacing: 5
        Glyph { text: ""; color: root.cpu > 85 ? Theme.error : Theme.green; font.pixelSize: 14 }
        Label { text: root.cpu + "%" }
    }
    Row {
        spacing: 5
        Glyph { text: "󰍛"; color: root.mem > 85 ? Theme.error : Theme.yellow; font.pixelSize: 14 }
        Label { text: root.mem + "%" }
    }
    Row {
        spacing: 4
        Glyph { text: "\uf063"; color: Theme.cyan; font.pixelSize: 11 }
        Label { text: NetStats.fmt(NetStats.down); font.pixelSize: 12; width: 38 }
        Glyph { text: "\uf062"; color: Theme.magenta; font.pixelSize: 11 }
        Label { text: NetStats.fmt(NetStats.up); font.pixelSize: 12; width: 38 }
    }
    Row {
        visible: root.temp > 0
        spacing: 5
        Glyph { text: ""; color: root.temp > 85 ? Theme.error : Theme.magenta; font.pixelSize: 14 }
        Label { text: root.temp + "°" }
    }
}
