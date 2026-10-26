import Quickshell
import Quickshell.Io
import QtQuick

// Windows that imitate the GRUB menu and the Plymouth passphrase screen, built from the real theme assets.
// Start with `boot-preview` (it generates the assets first). Approximation: real GRUB / Plymouth render a little differently.
ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("BOOTPREVIEW")
    readonly property string font: "JetBrainsMono Nerd Font"
    property var c: ({ primary: "#ffb3b3", fgPrimary: "#561d20", primaryContainer: "#733335", fgContainer: "#ffdad9", text: "#f0dede", textDim: "#d7c1c1" })

    FileView {
        path: root.dir + "/colors.json"
        onLoaded: { try { root.c = JSON.parse(text()); } catch (e) {} }
    }

    // ============================== GRUB ==============================
    FloatingWindow {
        id: grubWin
        title: "GRUB preview (up/down, Enter, Esc closes)"
        implicitWidth: 1280; implicitHeight: 720
        color: "black"

        Item {
            id: grub
            width: 1920; height: 1080
            readonly property real fit: Math.min(grubWin.width / 1920, grubWin.height / 1080)
            scale: fit
            transformOrigin: Item.TopLeft
            x: (grubWin.width - 1920 * fit) / 2
            y: (grubWin.height - 1080 * fit) / 2
            focus: true

            property int sel: 0
            property int secs: 5
            property bool counting: true
            property bool booting: false
            readonly property var entries: ["Arch Linux", "Arch Linux  (no splash)", "Advanced", "UEFI Firmware Settings", "Restart", "Shut down"]

            Keys.onPressed: event => {
                counting = false;
                if (event.key === Qt.Key_Down) sel = Math.min(entries.length - 1, sel + 1);
                else if (event.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) booting = !booting;
                else if (event.key === Qt.Key_Escape) Qt.quit();
            }
            Timer { interval: 1000; repeat: true; running: grub.counting; onTriggered: { grub.secs--; if (grub.secs <= 0) { grub.counting = false; grub.booting = true; } } }

            Image { anchors.fill: parent; source: "file://" + root.dir + "/gt/background.png"; fillMode: Image.PreserveAspectCrop }
            Text { x: 0; y: 17 * 10.8; width: 1920; horizontalAlignment: Text.AlignHCenter; text: "hephaestus"; font.family: root.font; font.pixelSize: 36; color: root.c.primary }
            Text { x: 0; y: 24 * 10.8; width: 1920; horizontalAlignment: Text.AlignHCenter; text: "choose what to start"; font.family: root.font; font.pixelSize: 16; color: root.c.textDim }

            BorderImage {
                x: 680; y: 335; width: 560; height: 420
                source: "file://" + root.dir + "/card.png"
                border { left: 26; right: 26; top: 26; bottom: 26 }
            }
            Repeater {
                model: grub.entries
                delegate: Item {
                    required property int index
                    required property string modelData
                    x: 706; y: 361 + index * 58; width: 508; height: 52
                    BorderImage {
                        anchors.fill: parent
                        visible: index === grub.sel
                        source: "file://" + root.dir + "/pill.png"
                        border { left: 26; right: 26; top: 26; bottom: 26 }
                    }
                    Text {
                        x: 22; anchors.verticalCenter: parent.verticalCenter
                        text: modelData; font.family: root.font; font.pixelSize: 22; font.bold: index === grub.sel
                        color: index === grub.sel ? root.c.fgPrimary : root.c.textDim
                    }
                }
            }
            Text {
                x: 0; y: 84 * 10.8; width: 1920; horizontalAlignment: Text.AlignHCenter
                visible: grub.counting
                text: "starting in " + grub.secs + " s, press any key to stay"
                font.family: root.font; font.pixelSize: 16; color: root.c.textDim
            }
            Rectangle {
                anchors.fill: parent; color: "black"; visible: grub.booting
                Text { anchors.centerIn: parent; text: "(booting " + grub.entries[grub.sel] + ", press Enter to go back)"; font.family: root.font; font.pixelSize: 22; color: root.c.textDim }
            }
        }
    }

    // ============================== Plymouth ==============================
    FloatingWindow {
        id: plyWin
        title: "Plymouth preview (type = dots, Enter = wrong passphrase, Esc closes)"
        implicitWidth: 1280; implicitHeight: 720
        color: "black"

        Item {
            id: ply
            width: 1920; height: 1080
            readonly property real fit: Math.min(plyWin.width / 1920, plyWin.height / 1080)
            scale: fit
            transformOrigin: Item.TopLeft
            x: (plyWin.width - 1920 * fit) / 2
            y: (plyWin.height - 1080 * fit) / 2
            focus: true

            property int tick: 0
            property real promptTarget: 0
            property real promptAlpha: 0
            property int count: 0
            property real shake: 0
            property real shakeT: 0
            property real off: 0
            readonly property int cx: 960
            readonly property int cy: 540

            // the same per-frame logic as rice.script, at 50 Hz
            Timer {
                interval: 20; repeat: true; running: true
                onTriggered: {
                    ply.tick++;
                    ply.promptAlpha += (ply.promptTarget - ply.promptAlpha) * 0.18;
                    if (ply.shake > 0.5) { ply.off = Math.sin(ply.shakeT * 1.2) * ply.shake; ply.shake *= 0.9; ply.shakeT++; }
                    else { ply.shake = 0; ply.off = 0; }
                }
            }
            Timer { interval: 1800; running: true; onTriggered: ply.promptTarget = 1 }   // the disk asks for its passphrase

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) Qt.quit();
                else if (event.key === Qt.Key_Backspace) ply.count = Math.max(0, ply.count - 1);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (ply.count > 1) { ply.shake = 14; ply.shakeT = 0; } ply.count = 0; }
                else if (event.text !== "") ply.count = Math.min(96, ply.count + 1);
            }

            Image { anchors.fill: parent; source: "file://" + root.dir + "/ply/bg.png"; fillMode: Image.Stretch }
            Image { x: ply.cx - 100; y: ply.cy - 100; source: "file://" + root.dir + "/ply/track.png" }
            Image {
                x: ply.cx - 100; y: ply.cy - 100; source: "file://" + root.dir + "/ply/arc.png"
                // 0.085 rad per 50 Hz frame
                NumberAnimation on rotation { from: 0; to: 360; duration: Math.round(2 * Math.PI / 0.085 * 20); loops: Animation.Infinite }
            }
            Image { x: ply.cx - 9; y: ply.cy - 9; source: "file://" + root.dir + "/ply/dot.png"; opacity: 0.7 + 0.3 * Math.sin(ply.tick * 0.06) }

            Image { x: ply.cx - 220 + ply.off; y: ply.cy + 92; source: "file://" + root.dir + "/ply/label.png"; opacity: ply.promptAlpha }
            Image { x: ply.cx - 220 + ply.off; y: ply.cy + 134; source: "file://" + root.dir + "/ply/entry.png"; opacity: ply.promptAlpha }
            Repeater {
                model: 96
                delegate: Image {
                    required property int index
                    readonly property real step: Math.min(22, 372 / Math.max(1, ply.count))
                    readonly property real d: Math.max(4, Math.min(14, Math.floor(step * 0.64)))
                    width: d; height: d; sourceSize: Qt.size(28, 28)
                    x: ply.cx - 220 + ply.off + 34 + index * step; y: ply.cy + 134 + 28 - d / 2
                    source: "file://" + root.dir + "/ply/bullet.png"
                    opacity: index < ply.count ? ply.promptAlpha : 0
                }
            }
        }
    }
}
