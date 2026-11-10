pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Night light (wlsunset) + normal idle auto-off (screen-off / lock timeouts, which caffeine overrides).
StyledRect {
    id: root

    readonly property real nonAnimHeight: layout.implicitHeight + Tokens.padding.large * 2

    implicitWidth: 300
    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    // ---- idle timeouts (GlobalConfig.general.idle.timeouts): find the entry by its action ----
    function idleEntry(action: string): var {
        const list = GlobalConfig.general.idle.timeouts;
        for (let i = 0; i < list.count; i++) {
            const it = list.at(i);
            if (it.idleAction === action)
                return it;
        }
        return null;
    }
    function idleAfter(action: string): int {
        const e = idleEntry(action);
        return (e && e.enabled) ? e.timeout : 0;
    }
    function setIdleAfter(action: string, sec: int): void {
        const e = idleEntry(action);
        if (!e)
            return;
        if (sec === 0) {
            e.enabled = false;
        } else {
            e.enabled = true;
            e.timeout = sec;
        }
    }

    component Lbl: StyledText {
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        Layout.topMargin: Tokens.spacing.extraSmall
    }
    component Seg: IconTextButton {
        required property var modelData
        Layout.fillWidth: true
        isToggle: true
        font: Tokens.font.label.small
        verticalPadding: Tokens.padding.small
        text: modelData[1]
    }

    // one idle-timeout control: presets + a Custom chip that reveals a minutes spin box
    component IdleControl: ColumnLayout {
        id: ic

        required property string label
        required property string action
        property var presets: [[0, Tr.tr("Never")], [300, "5m"], [600, "10m"]]
        readonly property int cur: root.idleAfter(action)
        readonly property bool custom: cur > 0 && !presets.some(p => p[0] === cur)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Lbl { text: ic.label }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: ic.presets
                delegate: Seg {
                    checked: ic.cur === modelData[0] && !ic.custom
                    onClicked: root.setIdleAfter(ic.action, modelData[0])
                }
            }
            IconTextButton {
                Layout.fillWidth: true
                isToggle: true
                checked: ic.custom
                font: Tokens.font.label.small
                verticalPadding: Tokens.padding.small
                text: Tr.tr("Custom")
                onClicked: if (!ic.custom) root.setIdleAfter(ic.action, 900) // default 15 min
            }
        }

        RowLayout {
            visible: ic.custom
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledSpinBox {
                from: 1
                to: 600
                stepSize: 1
                value: Math.max(1, Math.round(ic.cur / 60))
                onValueModified: root.setIdleAfter(ic.action, Math.round(value) * 60)
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Tr.tr("minutes")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        StyledText {
            text: Tr.tr("Night light")
            font: Tokens.font.body.medium
        }

        StyledText {
            visible: !NightLight.installed
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Tr.tr("Install wlsunset to use night light")
            color: Colours.palette.m3error
            font: Tokens.font.label.small
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [["off", Tr.tr("Off")], ["auto", Tr.tr("Auto")], ["on", Tr.tr("On")]]
                delegate: Seg {
                    checked: NightLight.mode === modelData[0]
                    onClicked: NightLight.setMode(modelData[0])
                }
            }
        }

        Lbl {
            visible: NightLight.active
            text: Tr.tr("Warmth")
        }
        RowLayout {
            visible: NightLight.active
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [[5000, Tr.tr("Soft")], [4000, Tr.tr("Warm")], [3400, Tr.tr("Warmer")], [2700, Tr.tr("Candle")]]
                delegate: Seg {
                    checked: NightLight.temp === modelData[0]
                    onClicked: NightLight.setTemp(modelData[0])
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.bottomMargin: Tokens.spacing.extraSmall
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
        }

        StyledText {
            text: Tr.tr("Auto-off when idle")
            font: Tokens.font.body.medium
        }

        IdleControl {
            label: Tr.tr("Lock after")
            action: "lock"
        }

        IdleControl {
            label: Tr.tr("Screen off after")
            action: "dpms off"
            presets: [[0, Tr.tr("Never")], [120, "2m"], [300, "5m"]]
        }
    }
}
