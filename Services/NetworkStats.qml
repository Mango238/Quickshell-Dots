pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Fuente única de velocidad de red para la barra. Detecta la interfaz de la
// ruta por defecto al iniciar y sondea /proc/net/dev cada 2 s (decisión del
// usuario, antes 1 s), compartida entre todas las instancias del widget.
//
// Optimización: la lectura se hace con un FileView recargado por tick en vez
// del anterior `sh -c grep /proc/net/dev` — se elimina un fork+exec por
// segundo permanente. Las velocidades se calculan con el tiempo real
// transcurrido entre lecturas, no asumiendo el intervalo nominal.
Singleton {
    id: netStats

    property string iface: ""
    property double lastBytesRecv: 0
    property double lastBytesSent: 0
    property double lastStampMs: 0
    property string downloadSpeed: "0 KB/s"
    property string uploadSpeed: "0 KB/s"

    Process {
        id: ifaceProc
        running: true
        command: ["sh", "-c", "ip route show default | awk '/ dev / {for (i=1; i<NF; i++) if ($i == \"dev\") {print $(i+1); exit}}'"]

        stdout: StdioCollector {
            onStreamFinished: {
                const name = this.text.trim()
                if (name !== "")
                    netStats.iface = name
            }
        }
    }

    FileView {
        id: netFile
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: netStats._parse(this.text())
    }

    function _parse(content) {
        if (netStats.iface === "" || !content)
            return
        const lines = content.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.indexOf(netStats.iface + ":") === -1)
                continue

            const parts = line.trim().split(/\s+/)
            // parts[1] = bytes recibidos, parts[9] = bytes transmitidos
            if (parts.length > 9) {
                const now = Date.now()
                const currentBytesRecv = parseInt(parts[1])
                const currentBytesSent = parseInt(parts[9])

                if (netStats.lastStampMs > 0) {
                    const elapsed = Math.max(0.001, (now - netStats.lastStampMs) / 1000)
                    const diffDown = (currentBytesRecv - netStats.lastBytesRecv) / elapsed
                    const diffUp = (currentBytesSent - netStats.lastBytesSent) / elapsed
                    netStats.downloadSpeed = (diffDown / 1024).toFixed(2) + " KB/s"
                    netStats.uploadSpeed = (diffUp / 1024).toFixed(2) + " KB/s"
                }

                netStats.lastBytesRecv = currentBytesRecv
                netStats.lastBytesSent = currentBytesSent
                netStats.lastStampMs = now
            }
            return
        }
    }

    Timer {
        interval: 2000
        running: netStats.iface !== ""
        repeat: true
        onTriggered: netFile.reload()
    }
}
