import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

import qs.common
import qs.common.components.controls

// Material 3 style list row for selectors and menus: optional leading icon,
// title, optional supporting text, trailing text and trailing icon. Selected
// rows get a tonal pill and the primary color.
Rectangle {
    id: root

    property string leadingIcon: ""
    property string leadingActionIcon: ""
    property string leadingActionLabel: ""
    readonly property bool showLeadingAction: interactive && hover.hovered && leadingActionIcon !== ""
    property string text: ""
    property string supportingText: ""
    property string trailingText: ""
    property color trailingColor: Theme.colors.overlay
    // Defaults to a check mark on the selected row.
    property string trailingIcon: selected ? "" : ""
    property bool selected: false
    property bool interactive: true

    signal clicked
    signal leadingActionClicked

    width: parent ? parent.width : 0
    implicitHeight: supportingText !== "" ? Theme.scaled(52) : Theme.scaled(40)
    radius: Theme.rounding.full
    color: selected ? Theme.colors.selection : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.motion.fast } }
    scale: tap.pressed ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: Theme.motion.fast; easing.type: Easing.OutBack } }

    Accessible.role: Accessible.ListItem
    Accessible.name: text

    ZendaStateLayer { hovered: hover.hovered && root.interactive; pressed: tap.pressed }

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.md
        anchors.rightMargin: Theme.spacing.md
        spacing: Theme.spacing.sm

        Item {
            id: leadingSlot

            visible: root.leadingIcon !== "" || root.leadingActionIcon !== ""
            implicitWidth: root.leadingActionIcon !== "" ? Math.max(iconLabel.implicitWidth, actionButton.implicitWidth) : iconLabel.implicitWidth
            implicitHeight: root.leadingActionIcon !== "" ? Math.max(iconLabel.implicitHeight, actionButton.implicitHeight) : iconLabel.implicitHeight

            Text {
                id: iconLabel

                anchors.centerIn: parent
                visible: !root.showLeadingAction
                text: root.leadingIcon
                color: root.selected ? Theme.colors.primary : Theme.colors.textMuted
                font.family: Theme.iconFamily
                font.pixelSize: Theme.scaled(14)
            }

            ZendaIconButton {
                id: actionButton

                anchors.centerIn: parent
                visible: root.showLeadingAction
                size: Theme.scaled(28)
                icon: root.leadingActionIcon
                accessibleLabel: root.leadingActionLabel
                onClicked: root.leadingActionClicked()

                HoverHandler { id: actionHover }
                Controls.ToolTip.visible: visible && actionHover.hovered
                Controls.ToolTip.delay: 500
                Controls.ToolTip.text: accessibleLabel
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.text
                color: root.selected ? Theme.colors.primary : Theme.colors.text
                font: Theme.font.overlay
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: root.supportingText !== ""
                text: root.supportingText
                color: Theme.colors.overlay
                font: Theme.font.caption
                elide: Text.ElideRight
            }
        }

        Text {
            visible: root.trailingText !== ""
            text: root.trailingText
            color: root.trailingColor
            font: Theme.font.caption
        }

        Text {
            visible: root.trailingIcon !== ""
            text: root.trailingIcon
            color: root.selected ? Theme.colors.primary : Theme.colors.overlay
            font.family: Theme.iconFamily
            font.pixelSize: Theme.scaled(12)
        }
    }

    HoverHandler { id: hover; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    Item {
        anchors.fill: parent
        anchors.leftMargin: root.showLeadingAction ? rowLayout.x + leadingSlot.x + leadingSlot.width : 0

        TapHandler { id: tap; enabled: root.interactive; onTapped: root.clicked() }
    }
}
