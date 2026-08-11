import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: backend

    property var eqFrequencies: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    property var eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string selectedPreset: "Flat"
    property string applyStatus: "Not applied"
    property string lastAppliedTargetSink: ""
    property string pendingAutoTargetSink: ""
    property bool pendingEqApply: false
    property bool hydratingEqState: false
    property var pendingEqBandsSnapshot: null
    property var appliedEqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool hasPendingEqChanges: false
    property bool bandDragActive: false
    readonly property bool isBusy: eqProc.running
    readonly property var defaultSink: Pipewire.defaultAudioSink
    // El EQ vive colgado del sink por defecto (filter-graph en su propiedad
    // audioconvert.filter-graph.0), así que la salida "real" ya no hay que deducirla con
    // pactl y el state file como cuando existía el sink virtual: es exactamente este nodo.
    // Mientras PipeWire cambia de salida, defaultAudioSink queda un instante en null; el ""
    // resultante lo absorbe la guarda de onCurrentSinkNameChanged.
    readonly property string currentSinkName: backend.defaultSink ? (backend.defaultSink.name || "") : ""
    readonly property var presetNames: ["Flat", "Bass", "Movie", "Treble", "Voice", "Vocal", "Pop", "Rock", "Jazz", "Classic"]
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (homeDir + "/.config")
    readonly property string eqScriptPath: configDir + "/quickshell/scripts/eq_filter_chain.sh"

    readonly property var presetMap: ({
        "Flat":    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":    [5, 4, 3, 2, 1, 0, -2, -3, -4, -5],
        "Movie":   [4, 3, 2, 0, -1, 0, 2, 3, 4, 4],
        "Treble":  [-4, -3, -2, -1, 0, 1, 2, 3, 4, 5],
        "Voice":   [-4, -3, -1, 2, 4, 5, 4, 2, 0, -1],
        "Vocal":   [-2, -1, 1, 3, 4, 3, 1, -1, -2, -3],
        "Pop":     [-1, 1, 3, 4, 2, 0, -1, 1, 3, 4],
        "Rock":    [3, 2, 1, 0, -1, 1, 3, 4, 3, 2],
        "Jazz":    [2, 1, 0, 2, 3, 2, 1, 0, 1, 2],
        "Classic": [1, 2, 3, 1, -1, -1, 0, 1, 2, 3]
    })

    function resetProcessBuffer(proc) {
        if (proc.out !== undefined) proc.out = "";
    }

    function startManagedProcess(proc, nextCommand) {
        if (proc.running) return false;
        resetProcessBuffer(proc);
        if (nextCommand !== undefined) proc.command = nextCommand;
        proc.running = true;
        return true;
    }

    function parseEqState(text) {
        var lines = text.split("\n");
        var gains = [];
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var m = line.match(/Gain\s+(-?\d+(?:\.\d+)?)\s+dB/i);
            if (m && m.length > 1) gains.push(parseFloat(m[1]));
        }
        if (gains.length === 10) {
            backend.hydratingEqState = true;
            backend.eqBands = gains;
            backend.appliedEqBands = gains.slice();
            backend.selectedPreset = backend.detectPresetFromBands(gains);
            backend.hydratingEqState = false;
            backend.updatePendingEqState();
        }
    }

    function updatePendingEqState() {
        backend.hasPendingEqChanges = !backend.sameBands(backend.eqBands, backend.appliedEqBands);
    }

    Process {
        id: eqProc
        command: []
        running: false
        property string out: ""
        property string requestedTargetSink: "auto"
        property string requestedAction: ""
        property var requestedBandsSnapshot: null
        stdout: SplitParser { onRead: data => { eqProc.out += data + "\n"; } }
        stderr: SplitParser { onRead: data => { eqProc.out += data + "\n"; } }
        onExited: code => {
            if (code === 0) {
                if (eqProc.requestedAction === "switch") {
                    backend.applyStatus = "Output switched";
                } else if (eqProc.requestedAction === "disable") {
                    backend.applyStatus = "Disabled";
                } else {
                    backend.applyStatus = "Applied";
                }
                if (eqProc.requestedTargetSink.length > 0 && eqProc.requestedTargetSink !== "auto") {
                    backend.lastAppliedTargetSink = eqProc.requestedTargetSink;
                }
                if (eqProc.requestedAction === "apply" && eqProc.requestedBandsSnapshot && eqProc.requestedBandsSnapshot.length === 10) {
                    backend.appliedEqBands = eqProc.requestedBandsSnapshot.slice();
                    backend.updatePendingEqState();
                }
                if (eqProc.requestedAction === "switch") {
                    backend.pendingAutoTargetSink = "";
                }
            } else {
                var errText = eqProc.out.trim();
                if (errText.length > 80) errText = errText.substring(0, 80) + "...";
                backend.applyStatus = errText.length > 0 ? ("Error (" + code + "): " + errText) : ("Error (" + code + ")");
                console.warn("EqualizerBackend", backend.applyStatus);
            }
            if (eqProc.requestedAction !== "disable") routeRecoveryTimer.restart();
            eqProc.out = "";
            eqProc.requestedAction = "";
            eqProc.requestedBandsSnapshot = null;
            if (backend.pendingEqApply) {
                backend.pendingEqApply = false;
                if (!backend.bandDragActive
                    && backend.pendingEqBandsSnapshot && backend.pendingEqBandsSnapshot.length === 10) {
                    backend.applyToPipeWire(backend.pendingEqBandsSnapshot);
                }
                // si hay drag activo, commitBandDrag re-encola al soltar
            }
        }
    }

    Process {
        id: recoverProc
        command: ["/bin/bash", backend.eqScriptPath, "recover"]
        running: false
    }

    PwObjectTracker { objects: [ backend.defaultSink ] }

    // Un sink SUSPENDIDO ignora el set del filter-graph en silencio: solo lo acepta mientras
    // está `running`, o sea con audio pasando de verdad. PwNode no expone ese estado, pero
    // que le aparezca un link es el mismo momento, así que sirve de disparador para
    // re-aplicar. Cubre el caso de mover un slider sin nada sonando: al arrancar la música,
    // el EQ se engancha solo.
    // `linkGroups` acá es una lista de QML (QQmlListReference), no un ObjectModel como
    // Pipewire.linkGroups: no tiene `values` ni `valuesChanged`, así que se escucha su propio
    // notify y se mide con `length`.
    PwNodeLinkTracker {
        id: sinkLinks
        node: backend.defaultSink
        onLinkGroupsChanged: if (sinkLinks.linkGroups.length > 0) routeRecoveryTimer.restart()
    }

    Process {
        id: readEqProc
        command: ["/bin/bash", "-c", "if [ -f \"" + backend.configDir + "/quickshell/eq/parametric-eq.txt\" ]; then cat \"" + backend.configDir + "/quickshell/eq/parametric-eq.txt\"; fi"]
        running: false
        property string out: ""
        stdout: SplitParser { onRead: data => { readEqProc.out += data + "\n"; } }
        onExited: {
            backend.parseEqState(readEqProc.out);
            readEqProc.out = "";
        }
    }

    onCurrentSinkNameChanged: {
        if (currentSinkName.length === 0) return;
        if (lastAppliedTargetSink.length === 0) {
            lastAppliedTargetSink = currentSinkName;
            return;
        }
        if (currentSinkName === lastAppliedTargetSink) return;
        pendingAutoTargetSink = currentSinkName;
        autoApplyTimer.restart();
    }

    Timer {
        id: autoApplyTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (backend.pendingAutoTargetSink.length === 0) return;
            if (backend.pendingAutoTargetSink !== backend.currentSinkName) return;
            backend.autoApplyForCurrentSink();
        }
    }

    // Red de seguridad: re-aplica el grafo poco después de cada operación y cuando el sink
    // gana links. Volver a poner un grafo que ya está puesto es idempotente — la propiedad es
    // de solo escritura y no hay forma de consultar si está, así que se re-aplica en vez de
    // detectar.
    Timer {
        id: routeRecoveryTimer
        interval: 1800
        repeat: false
        onTriggered: if (!recoverProc.running) recoverProc.running = true
    }

    function sameBands(a, b) {
        if (!a || !b || a.length !== b.length) return false;
        for (var i = 0; i < a.length; i++) {
            if (Math.round(Number(a[i])) !== Math.round(Number(b[i]))) return false;
        }
        return true;
    }

    function detectPresetFromBands(arr) {
        var keys = backend.presetNames;
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            if (backend.sameBands(arr, presetMap[key])) return key;
        }
        return "Custom";
    }

    function queueEqApply() {
        if (hydratingEqState) return;
        pendingEqBandsSnapshot = eqBands.slice();
        if (eqProc.running) { pendingEqApply = true; return; }
        pendingEqApply = false;
        applyToPipeWire(pendingEqBandsSnapshot);
    }

    onEqBandsChanged: {
        updatePendingEqState();
        if (!hydratingEqState && hasPendingEqChanges) {
            applyStatus = "Unapplied changes";
        }
    }

    function applyPreset(name) {
        if (!presetMap[name]) return;
        selectedPreset = name;
        eqBands = presetMap[name].slice();
        queueEqApply();
    }

    function setBandFromY(idx, y, h) {
        var ratio = 1 - Math.min(Math.max(y / h, 0), 1);
        var arr = eqBands.slice();
        arr[idx] = Math.round((ratio * 24) - 12);
        eqBands = arr;
        selectedPreset = "Custom";
        pendingEqBandsSnapshot = arr.slice();
        applyStatus = "Unapplied changes";
    }

    function beginBandDrag() {
        bandDragActive = true;
    }

    function commitBandDrag() {
        bandDragActive = false;
        if (!hasPendingEqChanges) return;
        if (eqProc.running) {
            pendingEqApply = true;
            applyStatus = "Applying...";
            return;
        }
        queueEqApply();
    }

    function applyEqToTarget(targetSink, bands) {
        if (eqProc.running) return;
        applyStatus = targetSink === "auto" ? "Applying..." : "Switching output...";
        eqProc.requestedTargetSink = targetSink;
        eqProc.requestedAction = "apply";
        var gains = (bands && bands.length === 10) ? bands : eqBands;
        eqProc.requestedBandsSnapshot = gains.slice();
        startManagedProcess(eqProc, [
            "/bin/bash", eqScriptPath, "apply",
            String(gains[0]), String(gains[1]), String(gains[2]), String(gains[3]), String(gains[4]),
            String(gains[5]), String(gains[6]), String(gains[7]), String(gains[8]), String(gains[9]),
            targetSink
        ]);
    }

    function applyToPipeWire(bands) {
        var targetSink = currentSinkName.length > 0 ? currentSinkName : "auto";
        applyEqToTarget(targetSink, bands);
    }

    function autoApplyForCurrentSink() {
        if (currentSinkName.length === 0) return;
        if (eqProc.running) return;
        applyStatus = "Syncing output...";
        eqProc.requestedTargetSink = currentSinkName;
        eqProc.requestedAction = "switch";
        eqProc.requestedBandsSnapshot = null;
        startManagedProcess(eqProc, ["/bin/bash", eqScriptPath, "switch", currentSinkName]);
    }

    function disablePipeWireEq() {
        if (eqProc.running) return;
        applyStatus = "Disabling...";
        eqProc.requestedAction = "disable";
        eqProc.requestedTargetSink = "";
        eqProc.requestedBandsSnapshot = null;
        startManagedProcess(eqProc, ["/bin/bash", eqScriptPath, "disable"]);
    }

    function applyPendingBands() {
        if (eqProc.running || !hasPendingEqChanges) return;
        queueEqApply();
    }

    function loadEqStateFromFile() {
        startManagedProcess(readEqProc);
    }

    Component.onCompleted: loadEqStateFromFile()
}
