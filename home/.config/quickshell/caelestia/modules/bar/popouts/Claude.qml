pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.small
    width: 300

    function tint(pct) {
        return pct >= 90 ? Colours.palette.m3error : pct >= 70 ? Colours.palette.m3secondary : Colours.palette.m3primary;
    }

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("Claude usage")
            font: Tokens.font.title.small
        }
        StyledText {
            text: ClaudeUsage.plan
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    StyledText {
        visible: ClaudeUsage.error !== "" && !ClaudeUsage.loaded
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        text: Tr.tr("Couldn't load limits: ") + ClaudeUsage.error
    }

    // single account: plan-wide limits
    Meter {
        Layout.fillWidth: true
        visible: ClaudeUsage.accounts.length === 0
        label: Tr.tr("5 hour limit")
        pct: ClaudeUsage.session
        reset: ClaudeUsage.sessionReset
    }
    Meter {
        Layout.fillWidth: true
        visible: ClaudeUsage.accounts.length === 0
        label: Tr.tr("Weekly limit")
        pct: ClaudeUsage.weekly
        reset: ClaudeUsage.weeklyReset
    }

    // multiple accounts
    Repeater {
        model: ClaudeUsage.accounts
        delegate: StyledRect {
            id: acc
            required property var modelData
            readonly property var f: modelData.five_hour || ({})
            readonly property var w: modelData.seven_day || ({})

            Layout.fillWidth: true
            implicitHeight: accol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: modelData.active ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

            StateLayer {
                radius: Tokens.rounding.medium
                disabled: acc.modelData.active
                onClicked: if (!acc.modelData.active) ClaudeUsage.use(acc.modelData.name)
            }

            ColumnLayout {
                id: accol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small / 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    StyledText {
                        text: acc.modelData.name
                        color: acc.modelData.active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: acc.modelData.email || ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                    StyledText {
                        text: acc.modelData.active ? Tr.tr("in use") : Tr.tr("switch")
                        color: acc.modelData.active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
                Meter { Layout.fillWidth: true; label: Tr.tr("5 hour"); pct: acc.f.used || 0; reset: (acc.f.used || 0) > 0 && acc.f.resets ? acc.f.resets : "" }
                Meter { Layout.fillWidth: true; label: Tr.tr("Weekly"); pct: acc.w.used || 0; reset: (acc.w.used || 0) > 0 && acc.w.resets ? acc.w.resets : "" }
            }
        }
    }
    StyledText {
        visible: ClaudeUsage.accounts.length > 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: ClaudeUsage.auto ? Tr.tr("Switches automatically when the one in use hits a limit.") : Tr.tr("Auto switching is off (claude-account auto on).")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
    }

    StyledText {
        visible: ClaudeUsage.sessions.length > 0
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Sessions")
        color: Colours.palette.m3onSurfaceVariant
    }
    Repeater {
        model: ClaudeUsage.sessions
        delegate: StyledRect {
            id: srow
            required property var modelData
            readonly property color dot: modelData.state === "waiting" ? Colours.palette.m3secondary : modelData.state === "working" ? Colours.palette.m3primary : Colours.palette.m3outline

            Layout.fillWidth: true
            implicitHeight: 40
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            StateLayer {
                radius: Tokens.rounding.medium
                disabled: !srow.modelData.window
                onClicked: {
                    if (srow.modelData.window)
                        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(srow.modelData.window)]);
                }
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: srow.dot
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: srow.modelData.project + "  ·  " + (srow.modelData.state === "waiting" ? Tr.tr("needs you") : srow.modelData.state === "working" ? Tr.tr("working") : srow.modelData.state === "done" ? Tr.tr("done") : Tr.tr("idle"))
                }
            }
        }
    }

    // meter: label + % on one row, a bar under it — plain Item so it nests cleanly in a layout
    component Meter: Item {
        id: meter
        property string label
        property real pct
        property string reset

        Layout.fillWidth: true
        implicitHeight: mcol.implicitHeight

        Column {
            id: mcol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Tokens.spacing.small / 2

            Item {
                width: parent.width
                implicitHeight: lbl.implicitHeight
                StyledText {
                    id: lbl
                    anchors.left: parent.left
                    text: meter.label
                    font: Tokens.font.body.small
                }
                StyledText {
                    anchors.right: parent.right
                    text: Math.round(meter.pct) + "%"
                    color: root.tint(meter.pct)
                    font: Tokens.font.body.small
                }
            }
            Rectangle {
                width: parent.width
                height: 8
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainer
                Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, meter.pct / 100))
                    radius: Tokens.rounding.full
                    color: root.tint(meter.pct)
                    Behavior on width { Anim {} }
                }
            }
            StyledText {
                visible: meter.reset !== ""
                text: Tr.tr("resets in ") + ClaudeUsage.until(meter.reset)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }
}
