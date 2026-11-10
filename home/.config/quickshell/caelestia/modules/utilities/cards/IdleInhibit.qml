pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Caffeine control (moved out of the bar): off / caffeine (screen stays on) / super (also blocks suspend),
// plus auto-off timer and a battery cutoff so a stuck inhibitor can't flatten the laptop.
StyledRect {
    id: root

    readonly property string cur: IdleInhibitor.superEnabled ? "super" : IdleInhibitor.enabled ? "caffeine" : "off"
    readonly property real nonAnimHeight: layout.implicitHeight + Tokens.padding.large * 2

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: IdleInhibitor.superEnabled ? Colours.palette.m3errorContainer : IdleInhibitor.enabled ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: IdleInhibitor.superEnabled ? "local_fire_department" : "local_cafe"
                    color: IdleInhibitor.superEnabled ? Colours.palette.m3onErrorContainer : IdleInhibitor.enabled ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: IdleInhibitor.superEnabled ? Tr.tr("Super caffeine") : Tr.tr("Caffeine")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: IdleInhibitor.superEnabled ? Tr.tr("Screen on + suspend blocked") : IdleInhibitor.enabled ? (Tr.tr("Screen stays on") + (IdleInhibitor.remaining ? "  ·  " + IdleInhibitor.remaining : "")) : Tr.tr("Normal idle + sleep")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconTextButton {
                Layout.fillWidth: true
                isToggle: true
                checked: root.cur === "off"
                text: Tr.tr("Off")
                onClicked: IdleInhibitor.disableAll()
            }
            IconTextButton {
                Layout.fillWidth: true
                isToggle: true
                checked: root.cur === "caffeine"
                text: Tr.tr("On")
                onClicked: {
                    IdleInhibitor.superEnabled = false;
                    IdleInhibitor.enabled = true;
                }
            }
            IconTextButton {
                Layout.fillWidth: true
                isToggle: true
                checked: root.cur === "super"
                text: Tr.tr("Super")
                onClicked: IdleInhibitor.superEnabled = true
            }
        }

        StyledText {
            text: Tr.tr("Auto-off after")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [[0, Tr.tr("Never")], [30, "30m"], [60, "1h"], [120, "2h"]]
                delegate: IconTextButton {
                    required property var modelData
                    Layout.fillWidth: true
                    isToggle: true
                    checked: IdleInhibitor.stopAfterMin === modelData[0]
                    text: modelData[1]
                    onClicked: IdleInhibitor.stopAfterMin = modelData[0]
                }
            }
        }

        StyledText {
            text: Tr.tr("Off below battery")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [[0, Tr.tr("Off")], [5, "5%"], [10, "10%"], [20, "20%"]]
                delegate: IconTextButton {
                    required property var modelData
                    Layout.fillWidth: true
                    isToggle: true
                    checked: IdleInhibitor.batteryCutoff === modelData[0]
                    text: modelData[1]
                    onClicked: IdleInhibitor.batteryCutoff = modelData[0]
                }
            }
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
