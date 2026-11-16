pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services

// While an app from ZENDA_MIC_PRIORITY_APPS records from any microphone, every
// other recording stream is muted, and unmuted again when it stops.
Singleton {
	id: root

	readonly property var patterns: String(ZendaSettings.values.ZENDA_MIC_PRIORITY_APPS || "")
		.split(",").map(p => p.trim().toLowerCase()).filter(p => p !== "")

	// Properties and audio controls only load once a node is tracked, so every
	// non-sink stream is tracked and filtered afterwards.
	readonly property var candidateStreams: Pipewire.nodes.values.filter(node => node.isStream && !node.isSink)
	readonly property var inputStreams: root.candidateStreams.filter(node =>
		String(node.properties["media.class"] || "").startsWith("Stream/Input/Audio"))

	readonly property var priorityStreams: root.inputStreams.filter(node => root.matches(node))
	readonly property bool active: root.priorityStreams.length > 0

	// Node ids muted here, and the app keys they belong to, so a stream that
	// WirePlumber restores muted later is unmuted too.
	// mutedKeys is saved to disk, because WirePlumber remembers the mute of each
	// app and a restart of the shell must still undo it.
	property var mutedIds: ({})
	property var mutedKeys: ({})
	property bool keysLoaded: false

	function appKey(node) {
		const p = node.properties || {};
		return String(p["application.name"] || p["application.process.binary"] || node.name || "");
	}

	function matches(node) {
		if (root.patterns.length === 0) return false;
		const p = node.properties || {};
		const text = [p["application.name"], p["application.process.binary"], p["application.id"],
			p["node.name"], p["media.name"], node.name, node.description]
			.filter(v => v).join(" ").toLowerCase();
		return root.patterns.some(pattern => text.includes(pattern));
	}

	function apply() {
		if (!Pipewire.ready || !root.keysLoaded) return;
		const ids = Object.assign({}, root.mutedIds);
		const keys = Object.assign({}, root.mutedKeys);
		for (const node of root.inputStreams) {
			if (!node.ready || !node.audio || root.matches(node)) continue;
			const key = root.appKey(node);
			if (root.active) {
				if (!node.audio.muted) {
					node.audio.muted = true;
					ids[node.id] = true;
					keys[key] = true;
				}
			} else if (ids[node.id] || keys[key]) {
				if (node.audio.muted) node.audio.muted = false;
				delete ids[node.id];
				delete keys[key];
			}
		}
		if (!root.active) {
			// Keys of streams that already closed stay until the app records again.
			for (const id in ids) delete ids[id];
		}
		root.mutedIds = ids;
		if (JSON.stringify(keys) !== JSON.stringify(root.mutedKeys)) {
			root.mutedKeys = keys;
			keysFile.setText(JSON.stringify(Object.keys(keys)));
		}
	}

	FileView {
		id: keysFile
		path: Quickshell.statePath("mic-priority-muted.json")
		printErrors: false
		onLoaded: {
			try {
				const keys = {};
				for (const key of JSON.parse(keysFile.text())) keys[key] = true;
				root.mutedKeys = keys;
			} catch (error) {}
			root.keysLoaded = true;
			root.apply();
		}
		onLoadFailed: { root.keysLoaded = true; root.apply(); }
	}

	PwObjectTracker {
		objects: root.candidateStreams
	}

	onActiveChanged: root.apply()
	onInputStreamsChanged: Qt.callLater(root.apply)

	// Streams become ready shortly after they appear.
	Timer {
		interval: 1000
		running: root.active || Object.keys(root.mutedKeys).length > 0
		repeat: true
		onTriggered: root.apply()
	}
}
