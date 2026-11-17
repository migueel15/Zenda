pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// State of the pinned window column. Hyprland (generated pinstack module)
// places the windows and reports when the column is shown; this service owns
// its width, which the PinStackPanel lets the user drag.
Singleton {
    id: root

    readonly property string binaryPath: Quickshell.env("ZENDA_BIN") || "zenda"
    readonly property int minWidth: 200
    readonly property real maxRatio: 0.8

    property bool active: false
    property string screenName: ""
    property int width: 900
    // Narrowest column the pinned windows accept, reported by Hyprland.
    property int stackMinWidth: 0

    // Sent to Hyprland while dragging; null when nothing is pending.
    property var pending: null

    function clampWidth(value: real, screenWidth: real): int {
        return Math.round(Math.max(root.minWidth, root.stackMinWidth, Math.min(screenWidth * root.maxRatio, value)));
    }

    // live is true while the edge is still being dragged.
    function setWidth(value: int, live: bool) {
        root.width = value;
        root.pending = { width: value, live: live };
        if (!sender.running)
            root.flush();
        if (!live)
            widthFile.setText(JSON.stringify({ width: value }));
    }

    function flush() {
        if (root.pending === null)
            return;
        const next = root.pending;
        root.pending = null;
        const command = [root.binaryPath, "pinstack", "width", String(next.width)];
        if (next.live)
            command.push("--live");
        sender.command = command;
        sender.running = true;
    }

    // One process at a time; the newest width wins while one is running.
    Process {
        id: sender
        onExited: root.flush()
    }

    FileView {
        id: widthFile
        path: Quickshell.statePath("pinstack.json")
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(widthFile.text()).width;
                // Hyprland may have reported the column before this file loaded
                // and got the default width: send the stored one too.
                if (saved > 0 && saved !== root.width) {
                    if (root.active)
                        root.setWidth(Math.max(saved, root.stackMinWidth), false);
                    else
                        root.width = saved;
                }
            } catch (error) {}
        }
    }

    IpcHandler {
        target: "pinstack"
        // Hyprland calls this through `zenda pinstack state`; it starts from the
        // stored width, so the column comes back as the user left it.
        // width is Hyprland's column width (0 when unknown).
        function setState(active: bool, screenName: string, minWidth: int, width: int) {
            const wasActive = root.active;
            root.active = active;
            root.screenName = screenName;
            root.stackMinWidth = minWidth;
            if (active && !wasActive) {
                // A column that just appeared takes the stored width.
                root.setWidth(Math.max(root.width, minWidth), false);
            } else if (active && width > 0 && width !== root.width) {
                // Hyprland changed it (minimum, or a single window resized).
                root.width = width;
                widthFile.setText(JSON.stringify({ width: width }));
            }
        }
    }
}
