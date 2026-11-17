import Quickshell
import Quickshell.Wayland
import QtQuick

import qs.services

// Handle on the right edge of the pinned window column, to resize it. Hyprland
// reserves the column for windows only, so the bar and the frame stay in place;
// this layer reserves nothing and only the handle takes input.
Variants {
	model: Quickshell.screens

	delegate: LazyLoader {
		id: loader

		required property var modelData
		active: PinStack.active && PinStack.screenName === modelData.name

		PanelWindow {
			id: panel

			readonly property int handleWidth: 12

			screen: loader.modelData
			color: "transparent"
			focusable: false
			// Above the pinned windows and the screen frame, which sits right
			// after the column and would otherwise cover the handle.
			aboveWindows: true
			exclusionMode: ExclusionMode.Ignore
			anchors {
				left: true
				top: true
				bottom: true
			}
			// The handle straddles the edge: half over the column gap, half outside.
			implicitWidth: PinStack.width + handleWidth / 2
			mask: Region { item: handle }
			WlrLayershell.namespace: "Zenda:PinStack"
			WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

			MouseArea {
				id: handle

				x: PinStack.width - panel.handleWidth / 2
				width: panel.handleWidth
				height: parent.height
				hoverEnabled: true
				cursorShape: Qt.SizeHorCursor

				property real startX: 0
				property int startWidth: 0

				onPressed: mouse => {
					startX = mapToGlobal(mouse.x, 0).x;
					startWidth = PinStack.width;
				}
				onPositionChanged: mouse => {
					if (!pressed)
						return;
					const delta = mapToGlobal(mouse.x, 0).x - startX;
					const next = PinStack.clampWidth(startWidth + delta, loader.modelData.width);
					if (next !== PinStack.width)
						PinStack.setWidth(next, true);
				}
				onReleased: PinStack.setWidth(PinStack.width, false)
				// A lost grab keeps the width reached so far.
				onCanceled: PinStack.setWidth(PinStack.width, false)
			}
		}
	}
}
