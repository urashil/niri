import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// mitch.pro GitHub card (button in the bar): deployments waiting on you + open PRs.
PanelWindow {
    id: win
    visible: UiState.mitch
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-mitch"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.mitch ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 4 }
    onVisibleChanged: if (visible) MitchHub.refresh()

    // hover-open: card-only input (no flicker); click-open: whole-screen input (click-outside closes)
    readonly property bool hoverMode: UiState.hoverPopout === "mitch"
    mask: Region { item: win.hoverMode ? card : clickCatcher }

    MouseArea { id: clickCatcher; anchors.fill: parent; onClicked: UiState.mitch = false }
    Item { focus: win.visible; Keys.onEscapePressed: UiState.mitch = false }

    Rectangle {
        id: card
        x: 54
        y: Math.min(win.height - height - 12, Math.max(12, UiState.mitchCenter - height / 2))
        width: 340
        height: col.implicitHeight + 32
        radius: Theme.radius + 4
        color: Qt.alpha(Theme.surface, 0.82)
        border.width: 1
        border.color: Theme.outlineVariant
        MouseArea { anchors.fill: parent }
        HoverHandler { onHoveredChanged: hovered ? UiState.hoverKeep() : UiState.hoverRelease() }

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text { text: "  mitch.pro"; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text }
                Item { Layout.fillWidth: true }
                Text {
                    text: "open repo ↗"; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: MitchHub.open(MitchHub.repoUrl) }
                }
            }

            Text {
                visible: MitchHub.error !== ""
                text: "GitHub error: " + MitchHub.error
                wrapMode: Text.Wrap; Layout.fillWidth: true
                font.family: Theme.font; font.pixelSize: 11; color: Theme.error
                textFormat: Text.PlainText
            }

            // ---- deployments waiting on approval ----
            Text {
                visible: MitchHub.deployCount > 0
                text: "Deploys waiting on you"
                font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim
            }
            Repeater {
                model: MitchHub.deploys
                delegate: Rectangle {
                    id: drow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: dcol.implicitHeight + 20
                    radius: 10
                    color: Theme.surfaceHigh
                    border.width: 1
                    border.color: modelData.canApprove ? Theme.yellow : Theme.outlineVariant

                    ColumnLayout {
                        id: dcol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "  " + drow.modelData.env; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text; textFormat: Text.PlainText }
                            Item { Layout.fillWidth: true }
                            Text { text: drow.modelData.branch; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; textFormat: Text.PlainText }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (drow.modelData.title || drow.modelData.name || "")
                            elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                            font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim; textFormat: Text.PlainText
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Controls.Chip {
                                visible: drow.modelData.canApprove
                                label: "Approve"; accent: Theme.green; on: true
                                onClicked: MitchHub.approve(drow.modelData.run_id, drow.modelData.env_id)
                            }
                            Text {
                                visible: !drow.modelData.canApprove
                                text: "not yours to approve"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "view ↗"; font.family: Theme.font; font.pixelSize: 11; color: Theme.primary
                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: MitchHub.open(drow.modelData.url) }
                            }
                        }
                    }
                }
            }

            Rectangle { visible: MitchHub.deployCount > 0 && (MitchHub.failedRuns.length > 0 || MitchHub.prCount > 0); Layout.fillWidth: true; height: 1; color: Theme.outlineVariant }

            // ---- recent failed workflow runs (CI, deploy, notify, ...) ----
            Text {
                visible: MitchHub.failedRuns.length > 0
                text: "Recent failures"
                font.family: Theme.font; font.pixelSize: 10; color: Theme.error
            }
            Repeater {
                model: MitchHub.failedRuns.slice(0, 4)
                delegate: Rectangle {
                    id: frow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: fcol.implicitHeight + 14
                    radius: 10
                    color: hovf.hovered ? Theme.surfaceHigh : Qt.alpha(Theme.surfaceHigh, 0.5)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: hovf }
                    TapHandler { onTapped: MitchHub.open(frow.modelData.url) }

                    ColumnLayout {
                        id: fcol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: ""; font.family: Theme.font; font.pixelSize: 11; color: Theme.error }
                            Text { text: frow.modelData.name; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text; textFormat: Text.PlainText }
                            Item { Layout.fillWidth: true }
                            Text { text: frow.modelData.conclusion; font.family: Theme.font; font.pixelSize: 10; color: Theme.error; textFormat: Text.PlainText }
                            // clear this failure from the card (it lingers in GitHub's recent-runs list otherwise)
                            Text {
                                text: ""; font.family: Theme.font; font.pixelSize: 11
                                color: dma.containsMouse ? Theme.error : Theme.textDim
                                MouseArea { id: dma; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: MitchHub.dismiss(frow.modelData.id) }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: frow.modelData.branch + (frow.modelData.title ? " · " + frow.modelData.title : "") + " · " + MitchHub.ago(frow.modelData.at)
                            elide: Text.ElideRight; maximumLineCount: 1
                            font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; textFormat: Text.PlainText
                        }
                    }
                }
            }

            Rectangle { visible: (MitchHub.deployCount > 0 || MitchHub.failedRuns.length > 0) && MitchHub.prCount > 0; Layout.fillWidth: true; height: 1; color: Theme.outlineVariant }

            // ---- open pull requests ----
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Open PRs"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Item { Layout.fillWidth: true }
                Text { text: MitchHub.prCount > 0 ? MitchHub.prCount : ""; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
            }
            Text {
                visible: MitchHub.loaded && MitchHub.prCount === 0 && MitchHub.error === ""
                text: "No open pull requests."
                font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
            }
            Repeater {
                model: MitchHub.prs
                delegate: Rectangle {
                    id: prow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: pcol.implicitHeight + 16
                    radius: 10
                    color: hov.hovered ? Theme.surfaceHigh : Qt.alpha(Theme.surfaceHigh, 0.5)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: hov }
                    TapHandler { onTapped: { MitchHub.open(prow.modelData.url); UiState.mitch = false; } }

                    ColumnLayout {
                        id: pcol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: "#" + prow.modelData.number; font.family: Theme.font; font.pixelSize: 11; font.bold: true; color: Theme.primary }
                            Text {
                                Layout.fillWidth: true
                                text: prow.modelData.title
                                elide: Text.ElideRight; maximumLineCount: 1
                                font.family: Theme.font; font.pixelSize: 12; color: Theme.text; textFormat: Text.PlainText
                            }
                            Text {
                                visible: prow.modelData.isDraft
                                text: "draft"; font.family: Theme.font; font.pixelSize: 9; color: Theme.textDim
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (prow.modelData.author ? prow.modelData.author.login : "?") + " · " + MitchHub.ago(prow.modelData.createdAt)
                                  + (prow.modelData.reviewDecision === "APPROVED" ? " · approved"
                                     : prow.modelData.reviewDecision === "CHANGES_REQUESTED" ? " · changes requested" : "")
                            font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; textFormat: Text.PlainText
                        }
                    }
                }
            }
        }
    }
}
