import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (homeDir + "/.config")
    readonly property string eqScriptPath: configDir + "/quickshell/scripts/eq_filter_chain.sh"
    readonly property string eqPipewireConfPath: configDir + "/pipewire/pipewire.conf.d/90-quickshell-eq.conf"
    property int attempts: 0
    property int maxAttempts: 8

    function scheduleAttempt(delayMs) {
        retryTimer.interval = delayMs
        retryTimer.restart()
    }

    Process {
        id: recoverProc
        command: ["/bin/bash", root.eqScriptPath, "recover"]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("EqBootstrap", "EQ recover failed with code " + exitCode)
            }
        }
    }

    Process {
        id: readyCheckProc
        command: [
            "/bin/bash",
            "-lc",
            // exit 2 = EQ no configurado (sin conf de pipewire); exit 1 = audio aún no listo
            "test -f " + "'" + root.eqPipewireConfPath.replace(/'/g, "'\\''") + "'" + " || exit 2; " +
            "pactl info >/dev/null 2>&1 || exit 1; " +
            "pactl list short sinks 2>/dev/null | grep -q . || exit 1"
        ]
        running: false
        onExited: exitCode => {
            if (exitCode === 0) {
                if (!recoverProc.running) recoverProc.running = true
                return
            }
            if (exitCode === 2) {
                // Sin 90-quickshell-eq.conf el EQ está deshabilitado a propósito:
                // no hay nada que recuperar y reintentar solo genera ruido en el log.
                return
            }
            root.attempts += 1
            if (root.attempts < root.maxAttempts) {
                root.scheduleAttempt(1500)
            } else {
                console.warn("EqBootstrap", "EQ startup recovery skipped after max attempts")
            }
        }
    }

    Timer {
        id: initialDelay
        interval: 2500
        running: true
        repeat: false
        onTriggered: readyCheckProc.running = true
    }

    Timer {
        id: retryTimer
        interval: 1500
        running: false
        repeat: false
        onTriggered: {
            if (!readyCheckProc.running) readyCheckProc.running = true
        }
    }
}
