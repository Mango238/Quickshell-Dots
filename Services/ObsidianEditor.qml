pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Buffer de la nota abierta en el editor del sidebar. Vive en un singleton y
// no dentro de la vista porque el Loader de Modules/Sidebar.qml destruye el
// contenido al cerrar el panel o al cambiar de sección del rail: el guardado
// al salir tiene que sobrevivir a esa destrucción.
Singleton {
    id: root

    property string path: ""        // "" = editor cerrado
    property string text: ""        // buffer editable
    property string savedText: ""   // último contenido confirmado en disco
    property string error: ""
    property string _pending: ""

    readonly property bool dirty: root.path !== "" && root.text !== root.savedText

    // El TextEdit se sincroniza con esta señal: la carga del FileView es
    // asíncrona y puede terminar antes o después de que exista la vista.
    signal textLoaded(string t)

    function open(p) {
        root.save()
        root.savedText = ""
        root.text = ""
        root.error = ""
        root.path = p
    }

    function close() {
        root.save()
        root.path = ""
    }

    function save() {
        if (!root.dirty)
            return
        root._pending = root.text
        file.setText(root.text)
    }

    FileView {
        id: file
        path: root.path
        printErrors: false   // con path "" (editor cerrado) la lectura falla

        onLoaded: {
            root.savedText = file.text()
            root.text = root.savedText
            root.error = ""
            root.textLoaded(root.text)
        }
        onLoadFailed: (err) => root.error = "No se pudo leer la nota"
        // savedText solo se mueve cuando el disco confirmó: si el guardado
        // falla, sigue `dirty` y el header lo muestra.
        onSaved: root.savedText = root._pending
        onSaveFailed: (err) => root.error = "No se pudo guardar"
    }
}
