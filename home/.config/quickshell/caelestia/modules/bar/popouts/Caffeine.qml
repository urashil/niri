pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Column {
    id: root

    readonly property string cur: IdleInhibitor.superEnabled ? "super" : IdleInhibitor.enabled ? "caffeine" : "off"

    spacing: Tokens.spacing.small
    width: 270

    StyledText {
        text: IdleInhibitor.superEnabled ? Tr.tr("Super caffeine") : IdleInhibitor.enabled ? Tr.tr("Caffeine") : Tr.tr("Caffeine off")
        font: Tokens.font.title.small
    }

    StyledText {
        width: parent.width
        wrapMode: Text.Wrap
        color: Colours.palette.m3onSurfaceVariant
        text: IdleInhibitor.superEnabled ? Tr.tr("Screen on + suspend blocked") : IdleInhibitor.enabled ? (Tr.tr("Screen stays on") + (IdleInhibitor.remaining ? "  ·  " + IdleInhibitor.remaining : "")) : Tr.tr("Normal idle + sleep")
    }

    RowLayout {
        width: parent.width
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
        topPadding: Tokens.spacing.small
        text: Tr.tr("Auto-off after")
        color: Colours.palette.m3onSurfaceVariant
    }
    RowLayout {
        width: parent.width
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
        topPadding: Tokens.spacing.small
        text: Tr.tr("Off below battery")
        color: Colours.palette.m3onSurfaceVariant
    }
    RowLayout {
        width: parent.width
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
