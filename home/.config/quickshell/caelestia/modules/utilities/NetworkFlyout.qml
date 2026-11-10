pragma ComponentBehavior: Bound

import "cards"
import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts

// Flyout to the left of the utilities panel, opened by hovering a quick-toggle:
//   - wifi / bluetooth -> the bar's Network/Bluetooth popouts (reused, so the wifi password flow works)
//   - nightlight       -> the Display card (night light + idle auto-off)
// The visible card sits a `bridge` gap off the panel; that gap is transparent but still part of this
// item's hover area, so moving the pointer from the panel across the gap into the card never closes it.
Item {
    id: root

    readonly property real bridge: Tokens.padding.medium
    readonly property string which: QuickFlyout.which
    readonly property bool isNet: which === "network" || which === "bluetooth"

    visible: opacity > 0
    opacity: which !== "" ? 1 : 0

    // size follows the content instantly (no Behavior): an animated resize lagged behind the pointer and
    // dropped the hover as the card reflowed, closing the flyout
    implicitWidth: (loader.item?.implicitWidth ?? 0) + bridge
    implicitHeight: loader.item?.implicitHeight ?? 0

    Behavior on opacity { Anim {} }

    // keep the flyout open while the pointer is over the card OR the transparent bridge to the panel
    HoverHandler {
        onHoveredChanged: hovered ? QuickFlyout.hold() : QuickFlyout.release()
    }

    BarPopouts.PopoutState {
        id: popoutState
        hasCurrent: root.isNet
    }

    // drive the bar Content for net/bt (letting Network switch itself to the password dialog between
    // updates); clear it otherwise so Content collapses
    // compute net-ness from the new `which` directly — reading the bound `isNet` property here gets its
    // stale value (it hasn't re-evaluated yet when this handler runs), which left currentName empty on a
    // cold ""->"bluetooth" open
    onWhichChanged: popoutState.currentName = (which === "network" || which === "bluetooth") ? which : "";

    // the visible card, pinned to the left so the bridge gap is on the right (against the panel)
    Loader {
        id: loader

        anchors.left: parent.left
        anchors.top: parent.top

        sourceComponent: root.isNet ? netComp : (root.which === "nightlight" ? nlComp : null)
    }

    Component {
        id: netComp

        StyledRect {
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surface
            implicitWidth: netContent.implicitWidth
            implicitHeight: netContent.implicitHeight

            BarPopouts.Content {
                id: netContent
                anchors.fill: parent
                popouts: popoutState
            }
        }
    }

    Component {
        id: nlComp
        Display {}
    }
}
