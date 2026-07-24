pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * CpuService.qml — Fuente única del uso de CPU para la barra.
 *
 * Lanza UNA sola instancia del binario Rust (mide con sysinfo y duerme 60 s
 * entre lecturas) y comparte el valor entre las barras de todos los
 * monitores. Antes cada Cpu.qml (×3 monitores) lanzaba su propio proceso.
 */
Singleton {
    id: cpuService

    /// Uso de CPU como string ("7.3"), tal como lo imprime el binario.
    property string usage: ""

    readonly property Process cpuProcess: Process {
        command: [Quickshell.shellDir + "/Widgets/Bar/Rust/cpu/target/release/cpu"]
        running: true

        // Sin esto, si el binario Rust falta o no compila el widget de CPU
        // queda congelado en silencio. Un exit code != 0 lo delata en stderr.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("CpuService: el binario 'cpu' terminó con código", exitCode,
                             "— el uso de CPU no se actualizará. ¿Está compilado en Widgets/Bar/Rust/cpu/target/release/cpu?")
        }

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                cpuService.usage = data.trim()
            }
        }
    }
}
