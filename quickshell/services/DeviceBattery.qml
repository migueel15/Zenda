pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Bluetooth

Singleton {
    id: root

    readonly property string binaryPath: Quickshell.env("ZENDA_BIN") || "zenda"
    property var hidppDevices: []
    property bool refreshQueued: false
    property bool fastPolling: false

    function normalizeKey(text) {
        return (text || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function inferKindFromName(name, fallback) {
        const lower = (name || "").toLowerCase();
        if (lower.includes("buds") || lower.includes("airpods") || lower.includes("beats") || lower.includes("earbud") || lower.includes("in-ear")) {
            return "earbuds";
        }
        if (lower.includes("headset") || lower.includes("headphone") || lower.includes("pro x") || lower.includes("audífono") || lower.includes("auricular")) {
            return "headset";
        }
        if (lower.includes("mouse") || lower.includes("g pro") || lower.includes("ratón") || lower.includes("mx master") || lower.includes("mx anywhere")) {
            return "mouse";
        }
        if (lower.includes("keyboard") || lower.includes("teclado")) {
            return "keyboard";
        }
        if (lower.includes("controller") || lower.includes("gamepad") || lower.includes("dualsense") || lower.includes("xbox")) {
            return "gamepad";
        }
        if (lower.includes("phone") || lower.includes("iphone") || lower.includes("pixel") || lower.includes("galaxy")) {
            return "phone";
        }
        return fallback || "other";
    }

    function kindFromUPowerType(dev) {
        const t = dev.type;
        let fallback = "other";
        if (t === UPowerDeviceType.Mouse) fallback = "mouse";
        else if (t === UPowerDeviceType.Keyboard) fallback = "keyboard";
        else if (t === UPowerDeviceType.Headset || t === UPowerDeviceType.Headphones) fallback = "headset";
        else if (t === UPowerDeviceType.GamingInput) fallback = "gamepad";
        else if (t === UPowerDeviceType.Phone) fallback = "phone";
        else if (t === UPowerDeviceType.Tablet) fallback = "tablet";
        return inferKindFromName(dev.model || "", fallback);
    }

    function kindFromBluetoothIcon(icon, name) {
        const ic = (icon || "").toLowerCase();
        let fallback = "other";
        if (ic.includes("headset") || ic.includes("headphone")) fallback = "headset";
        else if (ic.includes("mouse")) fallback = "mouse";
        else if (ic.includes("keyboard")) fallback = "keyboard";
        else if (ic.includes("gaming")) fallback = "gamepad";
        else if (ic.includes("phone")) fallback = "phone";
        return inferKindFromName(name, fallback);
    }

    readonly property var devices: {
        const list = [];
        const seenNames = {};

        // 1. UPower peripheral devices (e.g. Logitech G Pro Wireless via hidpp_battery_*,
        //    Bluetooth devices reported by UPower, etc.)
        const upowerList = UPower.devices ? UPower.devices.values : [];
        for (let i = 0; i < upowerList.length; i++) {
            const dev = upowerList[i];
            if (!dev) continue;
            if (dev.isLaptopBattery) continue;
            if (dev.ready === false || dev.isPresent === false) continue;
            if (dev.type === UPowerDeviceType.LinePower || dev.type === UPowerDeviceType.Unknown) continue;
            const rawPct = Number(dev.percentage);
            if (!isFinite(rawPct) || rawPct < 0) continue;
            const pct = Math.max(0, Math.min(100, Math.round(rawPct * 100)));
            const name = (dev.model || "").trim() || "Dispositivo";
            const key = normalizeKey(name);
            if (key) seenNames[key] = true;
            list.push({
                id: "upower:" + (dev.nativePath || dev.serial || name),
                name: name,
                kind: kindFromUPowerType(dev),
                percentage: pct,
                charging: dev.state === UPowerDeviceState.Charging
            });
        }

        // 2. HID++ 2.0 devices not exposed by UPower (e.g. Logitech PRO X Wireless 046d:0aba)
        const hidpp = root.hidppDevices || [];
        for (let i = 0; i < hidpp.length; i++) {
            const dev = hidpp[i];
            if (!dev) continue;
            const key = normalizeKey(dev.name);
            if (key && seenNames[key]) continue;
            if (key) seenNames[key] = true;
            list.push({
                id: dev.id || ("hidpp:" + i),
                name: dev.name || "Dispositivo",
                kind: dev.kind || inferKindFromName(dev.name, "headset"),
                percentage: Math.max(0, Math.min(100, Math.round(Number(dev.percentage) || 0))),
                charging: !!dev.charging
            });
        }

        // 3. Connected Bluetooth devices with BlueZ Battery1 (deduplicated against UPower)
        const btList = Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values : [];
        for (let i = 0; i < btList.length; i++) {
            const dev = btList[i];
            if (!dev || !dev.connected || !dev.batteryAvailable) continue;
            const name = (dev.name || dev.deviceName || "").trim() || "Bluetooth";
            const key = normalizeKey(name);
            if (key && seenNames[key]) continue;
            if (key) seenNames[key] = true;
            const pct = Math.max(0, Math.min(100, Math.round((Number(dev.battery) || 0) * 100)));
            list.push({
                id: "bt:" + (dev.dbusPath || name),
                name: name,
                kind: kindFromBluetoothIcon(dev.icon, name),
                percentage: pct,
                charging: false
            });
        }

        return list;
    }

    function refresh() {
        if (hidppProcess.running) {
            root.refreshQueued = true;
            return;
        }
        root.refreshQueued = false;
        hidppProcess.command = [root.binaryPath, "battery", "list"];
        hidppProcess.running = true;
    }

    Process {
        id: hidppProcess
        running: false

        stdout: StdioCollector {
            id: hidppOutput
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    const parsed = JSON.parse(hidppOutput.text);
                    if (Array.isArray(parsed)) {
                        root.hidppDevices = parsed;
                    }
                } catch (error) {
                    // Keep last known readings on transient parse error.
                }
            }
            if (root.refreshQueued) {
                root.refresh();
            }
        }
    }

    Timer {
        interval: root.fastPolling ? 3000 : 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
