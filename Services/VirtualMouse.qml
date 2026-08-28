pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mouse virtual por gestos de mano: el daemon Python de ~/virtual_mouse
// (MediaPipe + evdev/uinput) que antes prendía y apagaba un botón de eww.
//
// Singleton a propósito: la barra y el sidebar se instancian una vez POR
// MONITOR (Variants sobre Quickshell.screens en Modules/Bar.qml), así que un
// Process dentro del widget levantaría N daemons peleándose por /dev/video0.
//
// La diferencia con la versión de eww: ahí el estado era una defvar que se
// adivinaba, y si el python moría solo el botón seguía diciendo "prendido".
// Acá `active` ES el running del proceso, y onExited lo devuelve a false.
Singleton {
    id: root

    // El interruptor. Deliberadamente NO se persiste en Config: esto toma la
    // cámara y el puntero; arrancar el shell con el mouse virtual ya prendido
    // sería una sorpresa desagradable.
    property bool active: false

    readonly property string _dir: Quickshell.env("HOME") + "/virtual_mouse"

    Process {
        running: root.active

        // El python del venv por ruta absoluta, no `source activate`: el
        // activate de ese venv tiene VIRTUAL_ENV apuntando a otra ruta y
        // activaba un venv distinto (ver virtual_mouse_check.sh).
        command: [root._dir + "/venv/bin/python", root._dir + "/main.py"]

        // Cámara ocupada, venv roto, crash de MediaPipe: que el toggle vuelva
        // a apagado en vez de mentir.
        onExited: root.active = false

        stdout: SplitParser { onRead: data => console.log("virtual_mouse:", data) }
        // main.py escupe una línea de fps cada 2 s; solo interesa lo que no
        // sea eso (trazas, "Cámara no detectada").
        stderr: SplitParser {
            onRead: data => { if (!data.includes("fps")) console.warn("virtual_mouse:", data) }
        }
    }
}
