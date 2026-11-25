import QtQuick
import QtQuick.Layouts

import qs.common
import qs.services

Item {
    id: root

    readonly property var devices: DeviceBattery.devices
    readonly property bool hasDevices: devices.length > 0

    width: parent ? parent.width : 0
    visible: hasDevices
    implicitHeight: hasDevices ? card.implicitHeight : 0

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: grid.implicitHeight + Theme.spacing.md * 2
        radius: Theme.card.radius
        color: Theme.card.fill
        border.width: Theme.card.borderWidth
        border.color: Theme.card.borderColor

        GridLayout {
            id: grid
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.md
            }
            columns: Math.max(1, Math.min(root.devices.length, 4))
            columnSpacing: Theme.spacing.sm
            rowSpacing: Theme.spacing.md

            Repeater {
                model: root.devices

                delegate: Column {
                    id: itemDelegate
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    spacing: Theme.spacing.xs

                    readonly property int percentage: Math.max(0, Math.min(100, modelData.percentage ?? 0))
                    readonly property bool charging: !!modelData.charging
                    readonly property string kind: modelData.kind || "other"

                    readonly property color ringColor: {
                        if (charging) return Theme.colors.primary;
                        if (percentage <= 15) return Theme.colors.error;
                        if (percentage <= 30) return Theme.colors.warning;
                        return Theme.colors.primary;
                    }

                    readonly property string deviceIcon: {
                        switch (kind) {
                        case "mouse":
                            return "󰍽";
                        case "headset":
                            return "󰋎";
                        case "earbuds":
                            return "󱡏";
                        case "keyboard":
                            return "󰌌";
                        case "gamepad":
                            return "󰊗";
                        case "phone":
                            return "󰏲";
                        case "tablet":
                            return "󰓶";
                        default:
                            return "󰁹";
                        }
                    }

                    Item {
                        id: ringContainer
                        width: Theme.scaled(58)
                        height: Theme.scaled(58)
                        anchors.horizontalCenter: parent.horizontalCenter

                        Canvas {
                            id: ringCanvas
                            anchors.fill: parent
                            antialiasing: true

                            property real progress: itemDelegate.percentage / 100.0
                            property color activeColor: itemDelegate.ringColor
                            property color trackColor: Theme.colors.surfaceVariant

                            onProgressChanged: requestPaint()
                            onActiveColorChanged: requestPaint()
                            onTrackColorChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

                            Behavior on progress {
                                NumberAnimation {
                                    duration: Theme.motion.normal
                                    easing.type: Easing.OutCubic
                                }
                            }

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const w = width;
                                const h = height;
                                const cx = w / 2;
                                const cy = h / 2;
                                const lineWidth = Math.max(4, Math.round(w * 0.095));
                                const radius = Math.min(w, h) / 2 - lineWidth / 2 - 2;

                                // Background track
                                ctx.beginPath();
                                ctx.arc(cx, cy, radius, 0, Math.PI * 2, false);
                                ctx.strokeStyle = trackColor;
                                ctx.lineWidth = lineWidth;
                                ctx.stroke();

                                // Progress arc starting at top (-90 deg)
                                if (progress > 0) {
                                    const startAngle = -Math.PI / 2;
                                    const endAngle = startAngle + Math.PI * 2 * Math.min(1, progress);
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, radius, startAngle, endAngle, false);
                                    ctx.strokeStyle = activeColor;
                                    ctx.lineWidth = lineWidth;
                                    ctx.lineCap = "round";
                                    ctx.stroke();
                                }
                            }
                        }

                        // Centered device icon
                        Text {
                            anchors.centerIn: parent
                            text: itemDelegate.deviceIcon
                            color: Theme.colors.text
                            font: Qt.font({
                                family: Theme.iconFamily,
                                pixelSize: Theme.scaled(22),
                                weight: Font.Normal
                            })
                        }

                        // Charging lightning bolt at the top of the ring
                        Rectangle {
                            visible: itemDelegate.charging
                            width: Theme.scaled(16)
                            height: Theme.scaled(16)
                            radius: width / 2
                            color: Theme.card.fill
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: -Theme.scaled(2)

                            Text {
                                anchors.centerIn: parent
                                text: "󱐋"
                                color: Theme.colors.primary
                                font: Qt.font({
                                    family: Theme.iconFamily,
                                    pixelSize: Theme.scaled(12),
                                    weight: Font.Normal
                                })
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: `${itemDelegate.percentage}%`
                        color: Theme.colors.text
                        font: Qt.font({
                            family: Theme.font.heading.family,
                            pixelSize: Theme.scaled(14),
                            weight: Font.DemiBold
                        })
                    }
                }
            }
        }
    }
}
